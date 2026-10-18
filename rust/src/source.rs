use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::http;
use crate::lx;
use crate::model::{RemoteTrack, ResolveResult, SearchResult, SourceInfo};
use crate::store::{now_secs, Store};

#[derive(Debug, Deserialize)]
struct NeteaseSearchResponse {
    result: Option<NeteaseSearchResult>,
}

#[derive(Debug, Deserialize)]
struct NeteaseSearchResult {
    #[serde(default)]
    songs: Vec<NeteaseSong>,
    #[serde(default, rename = "songCount")]
    song_count: usize,
}

#[derive(Debug, Deserialize)]
struct NeteaseSong {
    id: u64,
    name: String,
    #[serde(default)]
    artists: Vec<NeteaseArtist>,
    #[serde(default)]
    album: Option<NeteaseAlbum>,
    #[serde(default)]
    duration: u64,
}

#[derive(Debug, Deserialize)]
struct NeteaseArtist {
    name: String,
}

#[derive(Debug, Deserialize)]
struct NeteaseAlbum {
    name: String,
    #[serde(default, rename = "picUrl")]
    pic_url: Option<String>,
    #[serde(default)]
    id: Option<u64>,
}

fn netease_search(keyword: &str, page: usize, limit: usize) -> Result<SearchResult, String> {
    let keyword = urlencoding::encode(keyword);
    let offset = page.saturating_sub(1) * limit;
    let url = format!(
        "https://music.163.com/api/search/get/web?s={keyword}&type=1&offset={offset}&limit={limit}"
    );
    let response: NeteaseSearchResponse = http::get_json(&url)?;
    let result = response.result.ok_or_else(|| "没有搜索结果".to_string())?;
    let items = result
        .songs
        .into_iter()
        .map(|song| {
            let artist = song
                .artists
                .iter()
                .map(|a| a.name.clone())
                .collect::<Vec<_>>()
                .join(" / ");
            let album = song
                .album
                .as_ref()
                .map(|a| a.name.clone())
                .unwrap_or_else(|| "未知专辑".into());
            let cover = song.album.as_ref().and_then(|a| a.pic_url.clone());
            let album_id = song.album.as_ref().and_then(|a| a.id);
            RemoteTrack {
                id: song.id.to_string(),
                source: "wy".into(),
                title: song.name.clone(),
                artist: artist.clone(),
                album: album.clone(),
                duration: song.duration as f64 / 1000.0,
                cover_url: cover.clone(),
                qualitys: vec!["128k".into(), "320k".into(), "flac".into()],
                extra: serde_json::json!({
                    "songmid": song.id,
                    "name": song.name,
                    "singer": artist,
                    "albumName": album,
                    "albumId": album_id,
                    "interval": format!("{}:{:02}", (song.duration / 1000) / 60, (song.duration / 1000) % 60),
                    "img": cover,
                    "source": "wy",
                }),
            }
        })
        .collect();
    Ok(SearchResult {
        source: "wy".into(),
        total: result.song_count,
        items,
    })
}

pub fn search(provider: &str, keyword: &str, page: usize, limit: usize) -> Result<SearchResult, String> {
    match provider {
        "wy" | "netease" => netease_search(keyword, page, limit),
        _ => Err(format!("暂不支持这个搜索来源: {provider}")),
    }
}

pub fn resolve_with_sources(
    sources: &[SourceInfo],
    provider: &str,
    id: &str,
    quality: &str,
    music_info: &Value,
) -> Result<ResolveResult, String> {
    let mut qualities = vec![quality.to_string()];
    for fallback in ["flac24bit", "flac", "320k", "128k"] {
        if !qualities.iter().any(|q| q == fallback) {
            qualities.push(fallback.to_string());
        }
    }

    for info in sources.iter().filter(|s| s.enabled) {
        let Ok(script) = lx::read_script(&info.script_path) else { continue };
        for item_quality in &qualities {
            if let Ok(url) = lx::resolve(&script, info, provider, item_quality, music_info.clone()) {
                return Ok(ResolveResult {
                    url,
                    quality: item_quality.clone(),
                    source: info.name.clone(),
                });
            }
        }
    }

    resolve_remote(provider, id, quality)
}

pub fn lyrics_with_sources(
    sources: &[SourceInfo],
    provider: &str,
    id: &str,
    music_info: &Value,
) -> Result<String, String> {
    for info in sources.iter().filter(|s| s.enabled) {
        let Ok(script) = lx::read_script(&info.script_path) else { continue };
        if let Ok(lyric) = lx::lyric(&script, info, provider, music_info.clone()) {
            return Ok(lyric);
        }
    }
    remote_lyrics(provider, id)
}

pub fn resolve_remote(
    provider: &str,
    id: &str,
    quality: &str,
) -> Result<ResolveResult, String> {
    match provider {
        "wy" | "netease" => {
            // Public 128k fallback. An imported LX source can later provide
            // higher quality and VIP tracks.
            let _ = quality;
            Ok(ResolveResult {
                url: format!("https://music.163.com/song/media/outer/url?id={id}.mp3"),
                quality: "128k".into(),
                source: "wy".into(),
            })
        }
        _ => Err(format!("暂不支持这个播放来源: {provider}")),
    }
}

pub fn remote_lyrics(provider: &str, id: &str) -> Result<String, String> {
    if provider != "wy" && provider != "netease" {
        return Err("暂不支持这个歌词来源".into());
    }
    let id: u64 = id.parse().map_err(|_| "无效的歌曲 ID".to_string())?;
    crate::lyrics::fetch_netease_lyrics(id).ok_or_else(|| "没有找到歌词".to_string())
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct SourceHeader {
    name: Option<String>,
    description: Option<String>,
    author: Option<String>,
    version: Option<String>,
    homepage: Option<String>,
}

fn parse_header(script: &str) -> SourceHeader {
    let mut header = SourceHeader::default();
    let head = script.lines().take(40);
    for line in head {
        let line = line.trim().trim_start_matches('*').trim();
        let mut parts = line.splitn(2, char::is_whitespace);
        let key = parts.next().unwrap_or("");
        let value = parts.next().unwrap_or("").trim().to_string();
        if value.is_empty() {
            continue;
        }
        match key {
            "@name" => header.name = Some(value),
            "@description" => header.description = Some(value),
            "@author" => header.author = Some(value),
            "@version" => header.version = Some(value),
            "@homepage" => header.homepage = Some(value),
            _ => {}
        }
    }
    header
}

pub fn import_source(
    store: &Store,
    sources: &mut Vec<SourceInfo>,
    script: &str,
    fallback_name: Option<String>,
) -> Result<SourceInfo, String> {
    if script.trim().len() < 32 {
        return Err("音源脚本内容太短，可能不是有效的洛雪音源".into());
    }
    let header = parse_header(script);
    let name = header
        .name
        .or(fallback_name)
        .unwrap_or_else(|| "未命名音源".to_string());
    let id = format!("src_{}", now_secs());
    let script_path = store.sources_dir.join(format!("{id}.js"));
    fs::write(&script_path, script).map_err(|e| format!("保存音源失败: {e}"))?;

    let mut info = SourceInfo {
        id,
        name,
        description: header.description.unwrap_or_default(),
        author: header.author.unwrap_or_default(),
        version: header.version.unwrap_or_default(),
        homepage: header.homepage.unwrap_or_default(),
        script_path: script_path.to_string_lossy().to_string(),
        enabled: true,
        sources: vec![],
        status: "已导入".into(),
    };
    match crate::lx::probe_script(script, &info) {
        Ok(inited) => {
            if let Some(object) = inited.get("sources").and_then(Value::as_object) {
                info.sources = object.keys().cloned().collect();
                info.sources.sort();
            }
            if info.sources.is_empty() {
                info.status = "已加载 · 未声明可用平台".into();
            } else {
                info.status = format!("已加载 · 支持 {}", info.sources.join(" / "));
            }
        }
        Err(error) => {
            info.status = format!("已导入 · 加载失败: {}", error.chars().take(80).collect::<String>());
        }
    }
    sources.push(info.clone());
    let _ = store.save_sources(sources);
    Ok(info)
}

pub fn import_source_from_url(
    store: &Store,
    sources: &mut Vec<SourceInfo>,
    url: &str,
) -> Result<SourceInfo, String> {
    let script = http::get_text(url)?;
    let fallback = Path::new(url)
        .file_stem()
        .and_then(|s| s.to_str())
        .map(|s| s.to_string());
    import_source(store, sources, &script, fallback)
}

pub fn remove_source(store: &Store, sources: &mut Vec<SourceInfo>, id: &str) -> Result<(), String> {
    if let Some(index) = sources.iter().position(|s| s.id == id) {
        let info = sources.remove(index);
        let _ = fs::remove_file(info.script_path);
        let _ = store.save_sources(sources);
    }
    Ok(())
}

pub fn toggle_source(
    store: &Store,
    sources: &mut Vec<SourceInfo>,
    id: &str,
    enabled: bool,
) -> Result<(), String> {
    if let Some(info) = sources.iter_mut().find(|s| s.id == id) {
        info.enabled = enabled;
        let _ = store.save_sources(sources);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Store;

    #[test]
    fn imports_reference_lx_source_if_available() {
        let path = "/tmp/opencode/lx-latest.js";
        let Ok(script) = fs::read_to_string(path) else { return };
        let dir = std::env::temp_dir().join(format!("musicfox-source-{}", std::process::id()));
        let store = Store::new(dir.join("support"), dir.join("docs")).unwrap();
        let mut sources = Vec::new();
        let info = import_source(&store, &mut sources, &script, Some("pdone".into()))
            .expect("import source");
        eprintln!("status: {}", info.status);
        eprintln!("sources: {:?}", info.sources);
        assert!(info.sources.contains(&"wy".to_string()));
        assert!(sources.len() == 1);
        let _ = fs::remove_dir_all(dir);
    }
}
