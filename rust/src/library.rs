use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use lofty::file::TaggedFileExt;
use lofty::prelude::{Accessor, AudioFile, ItemKey};
use lofty::probe::Probe;
use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};
use walkdir::WalkDir;

use crate::model::{LibraryData, Playlist, Track};
use crate::store::{now_secs, Store};

const AUDIO_EXTENSIONS: &[&str] = &[
    "flac", "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "alac", "mp4",
];

fn is_audio(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .map(|e| AUDIO_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

pub fn stable_id(relative: &Path) -> String {
    let mut hasher = Sha1::new();
    hasher.update(relative.to_string_lossy().as_bytes());
    let digest = hasher.finalize();
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SidecarMeta {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub year: Option<u32>,
    pub track_no: Option<u32>,
    pub disc_no: Option<u32>,
    pub lyrics: Option<String>,
    pub netease_id: Option<u64>,
}

fn read_sidecar(path: &Path) -> SidecarMeta {
    let sidecar = path.with_extension("musicfox.json");
    fs::read_to_string(sidecar)
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

pub fn write_sidecar(path: &Path, meta: &SidecarMeta) -> std::io::Result<()> {
    let sidecar = path.with_extension("musicfox.json");
    fs::write(sidecar, serde_json::to_vec_pretty(meta)?)
}

fn sidecar_cover(path: &Path) -> Option<PathBuf> {
    for ext in ["jpg", "jpeg", "png", "webp"] {
        let candidate = path.with_extension(ext);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    let parent = path.parent()?;
    for name in ["cover.jpg", "cover.jpeg", "cover.png", "folder.jpg", "front.jpg"] {
        let candidate = parent.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn picture_extension(data: &[u8]) -> &'static str {
    if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
        "jpg"
    } else if data.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        "png"
    } else if data.len() > 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        "webp"
    } else {
        "jpg"
    }
}

fn extract_cover(path: &Path, id: &str, covers_dir: &Path) -> Option<String> {
    if let Some(sidecar) = sidecar_cover(path) {
        return Some(sidecar.to_string_lossy().to_string());
    }

    let tagged = Probe::open(path).ok()?.read().ok()?;
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag())?;
    let picture = tag.pictures().first()?;
    let ext = picture_extension(picture.data());
    let cover_path = covers_dir.join(format!("{id}.{ext}"));
    if !cover_path.is_file() {
        fs::write(&cover_path, picture.data()).ok()?;
    }
    Some(cover_path.to_string_lossy().to_string())
}

fn embedded_lyrics(path: &Path) -> Option<String> {
    let tagged = Probe::open(path).ok()?.read().ok()?;
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag())?;
    tag.get_string(ItemKey::Lyrics)
        .or_else(|| tag.get_string(ItemKey::UnsyncLyrics))
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn sidecar_lyrics(path: &Path) -> Option<String> {
    let lrc = path.with_extension("lrc");
    fs::read_to_string(lrc)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn fallback_title(path: &Path) -> String {
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("未知曲目")
        .to_string()
}

fn read_track(path: &Path, media_root: &Path, covers_dir: &Path) -> Track {
    let relative = path.strip_prefix(media_root).unwrap_or(path);
    let id = stable_id(relative);
    let meta = read_sidecar(path);

    let mut track = Track {
        id: id.clone(),
        path: path.to_string_lossy().to_string(),
        title: meta.title.clone().unwrap_or_else(|| fallback_title(path)),
        artist: meta.artist.clone().unwrap_or_else(|| "未知艺术家".into()),
        album: meta.album.clone().unwrap_or_else(|| "未知专辑".into()),
        album_artist: meta.album_artist.clone().unwrap_or_default(),
        format: path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_ascii_lowercase(),
        ..Default::default()
    };

    if let Ok(tagged) = Probe::open(path).and_then(|p| p.read()) {
        let props = tagged.properties();
        track.duration = props.duration().as_secs_f64();
        track.sample_rate = props.sample_rate();
        track.bit_depth = props.bit_depth();
        track.bitrate = props.audio_bitrate();

        if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
            if let Some(v) = tag.title().map(|v| v.trim().to_string()).filter(|v| !v.is_empty()) {
                track.title = v;
            }
            if let Some(v) = tag.artist().map(|v| v.trim().to_string()).filter(|v| !v.is_empty()) {
                track.artist = v;
            }
            if let Some(v) = tag.album().map(|v| v.trim().to_string()).filter(|v| !v.is_empty()) {
                track.album = v;
            }
            if let Some(v) = tag
                .get_string(ItemKey::AlbumArtist)
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
            {
                track.album_artist = v;
            }
            if let Some(v) = tag.genre().map(|v| v.trim().to_string()).filter(|v| !v.is_empty()) {
                track.genre = Some(v);
            }
            if let Some(v) = tag.track().filter(|v| *v > 0) {
                track.track_no = Some(v);
            }
            if let Some(v) = tag.disk().filter(|v| *v > 0) {
                track.disc_no = Some(v);
            }
            if let Some(v) = tag.date().map(|d| d.year as u32).filter(|v| *v > 0) {
                track.year = Some(v);
            }
        }
    }

    if track.album_artist.is_empty() {
        track.album_artist = track.artist.clone();
    }
    if track.duration <= 0.0 {
        track.duration = 0.0;
    }

    track.cover_path = extract_cover(path, &id, covers_dir);
    track.lyrics = meta
        .lyrics
        .clone()
        .or_else(|| sidecar_lyrics(path))
        .or_else(|| embedded_lyrics(path));
    if track.year.is_none() {
        track.year = meta.year;
    }
    if track.track_no.is_none() {
        track.track_no = meta.track_no;
    }
    if track.disc_no.is_none() {
        track.disc_no = meta.disc_no;
    }
    track
}

pub fn scan(store: &Store, old: &LibraryData) -> Result<LibraryData, String> {
    let mut existing: HashMap<String, &Track> =
        old.tracks.iter().map(|t| (t.id.clone(), t)).collect();

    let mut tracks = Vec::new();
    for entry in WalkDir::new(&store.media_dir)
        .follow_links(false)
        .into_iter()
        .filter_map(Result::ok)
    {
        if !entry.file_type().is_file() {
            continue;
        }
        let path = entry.path();
        if path
            .file_name()
            .and_then(|n| n.to_str())
            .map(|n| n.starts_with('.'))
            .unwrap_or(false)
        {
            continue;
        }
        if !is_audio(path) {
            continue;
        }
        let mut track = read_track(path, &store.media_dir, &store.covers_dir);
        if let Some(prev) = existing.remove(&track.id) {
            track.favorite = prev.favorite;
            track.added_at = prev.added_at;
            // Keep a previously fetched online lyric if the file has none.
            if track.lyrics.is_none() {
                track.lyrics = prev.lyrics.clone();
            }
            if track.cover_path.is_none() {
                track.cover_path = prev.cover_path.clone();
            }
        }
        if track.added_at == 0 {
            track.added_at = now_secs();
        }
        tracks.push(track);
    }

    tracks.sort_by(|a, b| {
        a.album
            .to_lowercase()
            .cmp(&b.album.to_lowercase())
            .then(a.disc_no.unwrap_or(0).cmp(&b.disc_no.unwrap_or(0)))
            .then(a.track_no.unwrap_or(0).cmp(&b.track_no.unwrap_or(0)))
            .then(a.title.to_lowercase().cmp(&b.title.to_lowercase()))
    });

    let ids: std::collections::HashSet<&str> = tracks.iter().map(|t| t.id.as_str()).collect();
    let mut playlists = old.playlists.clone();
    for playlist in &mut playlists {
        playlist.track_ids.retain(|id| ids.contains(id.as_str()));
    }

    Ok(LibraryData { tracks, playlists })
}

pub fn set_favorite(library: &mut LibraryData, id: &str, favorite: bool) -> Result<(), String> {
    let track = library
        .tracks
        .iter_mut()
        .find(|t| t.id == id)
        .ok_or_else(|| "找不到这首歌".to_string())?;
    track.favorite = favorite;
    Ok(())
}

pub fn create_playlist(library: &mut LibraryData, name: &str) -> Result<Playlist, String> {
    let name = name.trim();
    if name.is_empty() {
        return Err("歌单名称不能为空".into());
    }
    let playlist = Playlist {
        id: format!("pl_{}", now_secs()),
        name: name.to_string(),
        track_ids: Vec::new(),
        created_at: now_secs(),
    };
    library.playlists.push(playlist.clone());
    Ok(playlist)
}

pub fn rename_playlist(
    library: &mut LibraryData,
    id: &str,
    name: &str,
) -> Result<(), String> {
    let playlist = library
        .playlists
        .iter_mut()
        .find(|p| p.id == id)
        .ok_or_else(|| "找不到歌单".to_string())?;
    let name = name.trim();
    if name.is_empty() {
        return Err("歌单名称不能为空".into());
    }
    playlist.name = name.to_string();
    Ok(())
}

pub fn delete_playlist(library: &mut LibraryData, id: &str) -> Result<(), String> {
    library.playlists.retain(|p| p.id != id);
    Ok(())
}

pub fn add_to_playlist(
    library: &mut LibraryData,
    id: &str,
    track_id: &str,
) -> Result<(), String> {
    let playlist = library
        .playlists
        .iter_mut()
        .find(|p| p.id == id)
        .ok_or_else(|| "找不到歌单".to_string())?;
    if !playlist.track_ids.iter().any(|t| t == track_id) {
        playlist.track_ids.push(track_id.to_string());
    }
    Ok(())
}

pub fn remove_from_playlist(
    library: &mut LibraryData,
    id: &str,
    track_id: &str,
) -> Result<(), String> {
    let playlist = library
        .playlists
        .iter_mut()
        .find(|p| p.id == id)
        .ok_or_else(|| "找不到歌单".to_string())?;
    playlist.track_ids.retain(|t| t != track_id);
    Ok(())
}

pub fn format_duration(duration: Duration) -> String {
    let secs = duration.as_secs();
    format!("{}:{:02}", secs / 60, secs % 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scans_flac_and_keeps_favorite() {
        let dir = std::env::temp_dir().join(format!("musicfox-scan-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let store = Store::new(dir.join("support"), dir.join("docs")).unwrap();
        let flac = store.media_dir.join("测试.flac");
        let status = std::process::Command::new("ffmpeg")
            .args(["-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=2"])
            .args(["-metadata", "title=测试歌曲", "-metadata", "artist=测试歌手", "-metadata", "album=测试专辑"])
            .arg(&flac)
            .status();
        if status.map(|s| !s.success()).unwrap_or(true) {
            return;
        }
        let first = scan(&store, &LibraryData::default()).unwrap();
        assert_eq!(first.tracks.len(), 1);
        assert_eq!(first.tracks[0].title, "测试歌曲");
        assert_eq!(first.tracks[0].artist, "测试歌手");
        assert!(first.tracks[0].duration > 1.0);
        let mut lib = first;
        lib.tracks[0].favorite = true;
        let second = scan(&store, &lib).unwrap();
        assert!(second.tracks[0].favorite);
        let _ = fs::remove_dir_all(dir);
    }
}
