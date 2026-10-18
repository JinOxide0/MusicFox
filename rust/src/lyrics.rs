use std::fs;
use std::path::Path;

use serde::Deserialize;

use crate::http;
use crate::model::{LibraryData, LyricsLine, LyricsResult, Track};
use crate::store::Store;

fn parse_timestamp(raw: &str) -> Option<f64> {
    let raw = raw.trim();
    let mut parts = raw.split(':');
    let minutes: f64 = parts.next()?.parse().ok()?;
    let seconds: f64 = parts.next()?.parse().ok()?;
    if minutes < 0.0 || seconds < 0.0 || seconds >= 60.0 {
        return None;
    }
    Some(minutes * 60.0 + seconds)
}

fn clean_text(text: &str) -> String {
    // Drop enhanced LRC word timings and trim surrounding whitespace.
    let mut out = String::with_capacity(text.len());
    let mut depth = 0usize;
    for ch in text.chars() {
        match ch {
            '<' => depth += 1,
            '>' => depth = depth.saturating_sub(1),
            _ if depth == 0 => out.push(ch),
            _ => {}
        }
    }
    out.trim().to_string()
}

pub fn parse_lrc(raw: &str) -> Vec<LyricsLine> {
    let mut offset_ms = 0.0f64;
    let mut lines: Vec<LyricsLine> = Vec::new();

    for source_line in raw.lines() {
        let line = source_line.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(rest) = line.strip_prefix("[offset:") {
            if let Some(value) = rest.strip_suffix(']') {
                offset_ms = value.trim().parse().unwrap_or(0.0);
            }
            continue;
        }

        let mut times = Vec::new();
        let mut cursor = 0usize;
        let bytes = line.as_bytes();
        while cursor < bytes.len() && bytes[cursor] == b'[' {
            let Some(end_rel) = line[cursor..].find(']') else {
                break;
            };
            let end = cursor + end_rel;
            let tag = &line[cursor + 1..end];
            if let Some(time) = parse_timestamp(tag) {
                times.push(time);
                cursor = end + 1;
            } else {
                break;
            }
        }

        if times.is_empty() {
            continue;
        }

        let text = clean_text(&line[cursor..]);
        if text.is_empty() {
            continue;
        }
        for time in times {
            lines.push(LyricsLine {
                time: (time - offset_ms / 1000.0).max(0.0),
                text: text.clone(),
                translation: None,
            });
        }
    }

    lines.sort_by(|a, b| {
        a.time
            .partial_cmp(&b.time)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    lines.dedup_by(|a, b| (a.time - b.time).abs() < 0.001 && a.text == b.text);
    lines
}

pub fn merge_translation(mut lines: Vec<LyricsLine>, translation: Vec<LyricsLine>) -> Vec<LyricsLine> {
    if translation.is_empty() {
        return lines;
    }
    for line in &mut lines {
        if let Some(found) = translation
            .iter()
            .find(|t| (t.time - line.time).abs() < 0.35)
        {
            line.translation = Some(found.text.clone());
        }
    }
    lines
}

fn plain_text(raw: &str) -> String {
    raw.lines()
        .map(|line| {
            let mut text = line.trim();
            if text.starts_with('[') {
                if let Some(end) = text.find(']') {
                    text = &text[end + 1..];
                }
            }
            clean_text(text)
        })
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn result_from_raw(raw: &str, source: &str) -> LyricsResult {
    let lines = parse_lrc(raw);
    if lines.is_empty() {
        let plain = plain_text(raw);
        return LyricsResult {
            lines: Vec::new(),
            plain,
            synced: false,
            source: source.to_string(),
        };
    }
    LyricsResult {
        lines,
        plain: plain_text(raw),
        synced: true,
        source: source.to_string(),
    }
}

fn lrclib_url(track: &Track) -> String {
    let artist = urlencoding::encode(&track.artist);
    let title = urlencoding::encode(&track.title);
    let album = urlencoding::encode(&track.album);
    format!(
        "https://lrclib.net/api/get?artist_name={artist}&track_name={title}&album_name={album}&duration={}",
        track.duration.round() as i64
    )
}

#[derive(Debug, Deserialize)]
struct LrclibItem {
    #[serde(default, rename = "syncedLyrics")]
    synced_lyrics: Option<String>,
    #[serde(default, rename = "plainLyrics")]
    plain_lyrics: Option<String>,
}

fn fetch_lrclib(track: &Track) -> Option<LyricsResult> {
    let item: LrclibItem = http::get_json(&lrclib_url(track)).ok()?;
    if let Some(synced) = item.synced_lyrics.filter(|s| !s.trim().is_empty()) {
        return Some(result_from_raw(&synced, "LRCLIB"));
    }
    item.plain_lyrics
        .filter(|s| !s.trim().is_empty())
        .map(|plain| LyricsResult {
            lines: Vec::new(),
            plain,
            synced: false,
            source: "LRCLIB".into(),
        })
}

fn fetch_lrclib_search(track: &Track) -> Option<LyricsResult> {
    let artist = urlencoding::encode(&track.artist);
    let title = urlencoding::encode(&track.title);
    let url = format!(
        "https://lrclib.net/api/search?artist_name={artist}&track_name={title}"
    );
    let items: Vec<LrclibItem> = http::get_json(&url).ok()?;
    for item in items {
        if let Some(synced) = item.synced_lyrics.filter(|s| !s.trim().is_empty()) {
            return Some(result_from_raw(&synced, "LRCLIB"));
        }
        if let Some(plain) = item.plain_lyrics.filter(|s| !s.trim().is_empty()) {
            return Some(LyricsResult {
                lines: Vec::new(),
                plain,
                synced: false,
                source: "LRCLIB".into(),
            });
        }
    }
    None
}

#[derive(Debug, Deserialize)]
struct NeteaseLyric {
    #[serde(default)]
    lrc: Option<NeteaseText>,
    #[serde(default)]
    tlyric: Option<NeteaseText>,
}

#[derive(Debug, Deserialize)]
struct NeteaseText {
    #[serde(default)]
    lyric: Option<String>,
}

pub fn fetch_netease_lyrics(song_id: u64) -> Option<String> {
    let url = format!(
        "https://music.163.com/api/song/lyric?id={song_id}&lv=1&kv=1&tv=-1"
    );
    let data: NeteaseLyric = http::get_json(&url).ok()?;
    let raw = data.lrc?.lyric?;
    if raw.trim().is_empty() {
        return None;
    }
    let mut lines = parse_lrc(&raw);
    if let Some(tlyric) = data.tlyric.and_then(|t| t.lyric) {
        lines = merge_translation(lines, parse_lrc(&tlyric));
    }
    let mut out = String::new();
    for line in lines {
        out.push_str(&format!("[{}]{}\n", format_time(line.time), line.text));
        if let Some(translation) = line.translation {
            out.push_str(&format!("[{}]{}\n", format_time(line.time), translation));
        }
    }
    Some(out)
}

fn fetch_netease(song_id: u64) -> Option<LyricsResult> {
    let url = format!(
        "https://music.163.com/api/song/lyric?id={song_id}&lv=1&kv=1&tv=-1"
    );
    let data: NeteaseLyric = http::get_json(&url).ok()?;
    let raw = data.lrc?.lyric?;
    if raw.trim().is_empty() {
        return None;
    }
    let mut lines = parse_lrc(&raw);
    if let Some(tlyric) = data.tlyric.and_then(|t| t.lyric) {
        lines = merge_translation(lines, parse_lrc(&tlyric));
    }
    if lines.is_empty() {
        return Some(LyricsResult {
            plain: plain_text(&raw),
            lines: Vec::new(),
            synced: false,
            source: "网易云".into(),
        });
    }
    Some(LyricsResult {
        plain: plain_text(&raw),
        lines,
        synced: true,
        source: "网易云".into(),
    })
}

fn cache_path(store: &Store, track_id: &str) -> std::path::PathBuf {
    store.lyrics_dir.join(format!("{track_id}.lrc"))
}

pub fn local_lyrics(store: &Store, track: &Track) -> Option<LyricsResult> {
    if let Some(raw) = track
        .lyrics
        .as_deref()
        .filter(|s| !s.trim().is_empty())
    {
        return Some(result_from_raw(raw, "本地"));
    }
    let cached = cache_path(store, &track.id);
    if let Some(raw) = fs::read_to_string(cached).ok().filter(|s| !s.trim().is_empty()) {
        return Some(result_from_raw(&raw, "LRCLIB"));
    }
    None
}

pub fn fetch_lyrics(store: &Store, track: &Track) -> LyricsResult {
    if let Some(local) = local_lyrics(store, track) {
        return local;
    }

    let some_id = fs::read_to_string(Path::new(&track.path).with_extension("musicfox.json"))
        .ok()
        .and_then(|raw| serde_json::from_str::<crate::library::SidecarMeta>(&raw).ok())
        .and_then(|meta| meta.netease_id);

    let result = some_id
        .and_then(fetch_netease)
        .or_else(|| fetch_lrclib(track))
        .or_else(|| fetch_lrclib_search(track));

    if let Some(result) = result {
        if result.synced {
            let raw = result
                .lines
                .iter()
                .map(|line| format!("[{}]{}\n", format_time(line.time), line.text))
                .collect::<String>();
            let _ = fs::create_dir_all(&store.lyrics_dir);
            let _ = fs::write(cache_path(store, &track.id), raw);
        }
        return result;
    }

    LyricsResult {
        lines: Vec::new(),
        plain: String::new(),
        synced: false,
        source: "无".into(),
    }
}

pub fn format_time(seconds: f64) -> String {
    let seconds = seconds.max(0.0);
    let minutes = (seconds / 60.0).floor() as u64;
    let secs = seconds - (minutes as f64 * 60.0);
    format!("{minutes:02}:{secs:05.2}")
}

pub fn find_track<'a>(library: &'a LibraryData, id: &str) -> Option<&'a Track> {
    library.tracks.iter().find(|t| t.id == id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_standard_and_multi_timestamp_lrc() {
        let raw = "[ar:test]\n[offset:100]\n[00:01.00]第一句\n[00:02.50][00:03.50]重复\n";
        let lines = parse_lrc(raw);
        assert_eq!(lines.len(), 3);
        assert!((lines[0].time - 0.9).abs() < 0.001);
        assert_eq!(lines[1].text, "重复");
        assert!((lines[2].time - 3.4).abs() < 0.001);
    }

    #[test]
    fn merges_translation_by_time() {
        let lines = parse_lrc("[00:01.00]hello\n");
        let tr = parse_lrc("[00:01.00]你好\n");
        let merged = merge_translation(lines, tr);
        assert_eq!(merged[0].translation.as_deref(), Some("你好"));
    }
}
