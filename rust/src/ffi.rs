use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use serde::Deserialize;
use serde_json::{json, Value};

use crate::library;
use crate::lyrics;
use crate::model::{LibraryData, SourceInfo};
use crate::ncm;
use crate::source;
use crate::store::Store;

struct AppState {
    store: Store,
    library: LibraryData,
    sources: Vec<SourceInfo>,
}

static STATE: OnceLock<Mutex<AppState>> = OnceLock::new();

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct InitPayload {
    support_dir: String,
    docs_dir: String,
}

fn state_mut() -> Result<std::sync::MutexGuard<'static, AppState>, String> {
    STATE
        .get()
        .ok_or_else(|| "核心尚未初始化".to_string())?
        .lock()
        .map_err(|_| "核心状态被锁定".to_string())
}

fn init(payload: &Value) -> Result<Value, String> {
    if STATE.get().is_some() {
        let state = state_mut()?;
        return Ok(json!({
            "tracks": state.library.tracks,
            "playlists": state.library.playlists,
        }));
    }
    let payload: InitPayload =
        serde_json::from_value(payload.clone()).map_err(|e| format!("初始化参数错误: {e}"))?;
    let store = Store::new(PathBuf::from(&payload.support_dir), PathBuf::from(&payload.docs_dir))
        .map_err(|e| format!("创建目录失败: {e}"))?;
    let library = store.load_library();
    let sources = store.load_sources();
    let data = json!({
        "tracks": library.tracks,
        "playlists": library.playlists,
        "sources": sources,
    });
    STATE
        .set(Mutex::new(AppState {
            store,
            library,
            sources,
        }))
        .map_err(|_| "核心已经初始化".to_string())?;
    Ok(data)
}

fn handle(cmd: &str, payload: &Value) -> Result<Value, String> {
    if cmd == "init" {
        return init(payload);
    }

    let mut state = state_mut()?;
    match cmd {
        "library.load" => Ok(json!({
            "tracks": state.library.tracks,
            "playlists": state.library.playlists,
        })),
        "library.scan" => {
            let scanned = library::scan(&state.store, &state.library)?;
            state.library = scanned;
            state
                .store
                .save_library(&state.library)
                .map_err(|e| format!("保存音乐库失败: {e}"))?;
            Ok(json!({
                "tracks": state.library.tracks,
                "playlists": state.library.playlists,
            }))
        }
        "library.favorite" => {
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少歌曲 ID")?;
            let favorite = payload
                .get("favorite")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            library::set_favorite(&mut state.library, id, favorite)?;
            state
                .store
                .save_library(&state.library)
                .map_err(|e| format!("保存失败: {e}"))?;
            Ok(json!({ "ok": true }))
        }
        "playlist.create" => {
            let name = payload
                .get("name")
                .and_then(Value::as_str)
                .ok_or("缺少歌单名称")?;
            let playlist = library::create_playlist(&mut state.library, name)?;
            state
                .store
                .save_library(&state.library)
                .map_err(|e| format!("保存失败: {e}"))?;
            Ok(json!({ "playlist": playlist, "playlists": state.library.playlists }))
        }
        "playlist.rename" => {
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少歌单 ID")?;
            let name = payload
                .get("name")
                .and_then(Value::as_str)
                .ok_or("缺少歌单名称")?;
            library::rename_playlist(&mut state.library, id, name)?;
            state
                .store
                .save_library(&state.library)
                .map_err(|e| format!("保存失败: {e}"))?;
            Ok(json!({ "playlists": state.library.playlists }))
        }
        "playlist.delete" => {
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少歌单 ID")?;
            library::delete_playlist(&mut state.library, id)?;
            state
                .store
                .save_library(&state.library)
                .map_err(|e| format!("保存失败: {e}"))?;
            Ok(json!({ "playlists": state.library.playlists }))
        }
        "playlist.add" => {
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少歌单 ID")?;
            let track_id = payload
                .get("trackId")
                .and_then(Value::as_str)
                .ok_or("缺少歌曲 ID")?;
            library::add_to_playlist(&mut state.library, id, track_id)?;
            state
                .store
                .save_library(&state.library)
                .map_err(|e| format!("保存失败: {e}"))?;
            Ok(json!({ "playlists": state.library.playlists }))
        }
        "playlist.remove" => {
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少歌单 ID")?;
            let track_id = payload
                .get("trackId")
                .and_then(Value::as_str)
                .ok_or("缺少歌曲 ID")?;
            library::remove_from_playlist(&mut state.library, id, track_id)?;
            state
                .store
                .save_library(&state.library)
                .map_err(|e| format!("保存失败: {e}"))?;
            Ok(json!({ "playlists": state.library.playlists }))
        }
        "ncm.decrypt" => {
            let paths: Vec<String> = payload
                .get("paths")
                .and_then(|v| serde_json::from_value(v.clone()).ok())
                .ok_or("缺少文件列表")?;
            Ok(serde_json::to_value(ncm::decrypt_batch(&state.store, &paths))
                .map_err(|e| e.to_string())?)
        }
        "lyrics.get" => {
            let id = payload
                .get("trackId")
                .and_then(Value::as_str)
                .ok_or("缺少歌曲 ID")?;
            let track = lyrics::find_track(&state.library, id).ok_or("找不到这首歌")?;
            Ok(serde_json::to_value(
                lyrics::local_lyrics(&state.store, track).unwrap_or_default(),
            )
            .map_err(|e| e.to_string())?)
        }
        "lyrics.fetch" => {
            let id = payload
                .get("trackId")
                .and_then(Value::as_str)
                .ok_or("缺少歌曲 ID")?;
            let track = lyrics::find_track(&state.library, id).ok_or("找不到这首歌")?;
            let result = lyrics::fetch_lyrics(&state.store, track);
            if result.synced {
                if let Some(track) = state.library.tracks.iter_mut().find(|t| t.id == id) {
                    track.lyrics = Some(
                        result
                            .lines
                            .iter()
                            .map(|line| format!("[{}]{}\n", lyrics::format_time(line.time), line.text))
                            .collect::<String>(),
                    );
                    let _ = state.store.save_library(&state.library);
                }
            }
            Ok(serde_json::to_value(result).map_err(|e| e.to_string())?)
        }
        "source.list" => Ok(serde_json::to_value(&state.sources).map_err(|e| e.to_string())?),
        "source.import" => {
            let AppState { store, sources, .. } = &mut *state;
            let info = if let Some(url) = payload.get("url").and_then(Value::as_str) {
                source::import_source_from_url(store, sources, url)?
            } else {
                let script = payload
                    .get("script")
                    .and_then(Value::as_str)
                    .ok_or("缺少音源脚本")?;
                let name = payload
                    .get("name")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());
                source::import_source(store, sources, script, name)?
            };
            let list = sources.clone();
            Ok(json!({ "source": info, "sources": list }))
        }
        "source.remove" => {
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少音源 ID")?;
            let AppState { store, sources, .. } = &mut *state;
            source::remove_source(store, sources, id)?;
            let list = sources.clone();
            Ok(json!({ "sources": list }))
        }
        "source.toggle" => {
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少音源 ID")?;
            let enabled = payload
                .get("enabled")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            let AppState { store, sources, .. } = &mut *state;
            source::toggle_source(store, sources, id, enabled)?;
            let list = sources.clone();
            Ok(json!({ "sources": list }))
        }
        "source.search" => {
            let provider = payload
                .get("provider")
                .and_then(Value::as_str)
                .unwrap_or("wy");
            let keyword = payload
                .get("keyword")
                .and_then(Value::as_str)
                .ok_or("缺少搜索关键词")?;
            let page = payload.get("page").and_then(Value::as_u64).unwrap_or(1) as usize;
            let limit = payload.get("limit").and_then(Value::as_u64).unwrap_or(30) as usize;
            let result = source::search(provider, keyword, page, limit)?;
            Ok(serde_json::to_value(result).map_err(|e| e.to_string())?)
        }
        "source.resolve" => {
            let provider = payload
                .get("provider")
                .and_then(Value::as_str)
                .unwrap_or("wy");
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少歌曲 ID")?;
            let quality = payload
                .get("quality")
                .and_then(Value::as_str)
                .unwrap_or("128k");
            let music_info = music_info_from_payload(payload, provider, id);
            let result =
                source::resolve_with_sources(&state.sources, provider, id, quality, &music_info)?;
            Ok(serde_json::to_value(result).map_err(|e| e.to_string())?)
        }
        "source.lyrics" => {
            let provider = payload
                .get("provider")
                .and_then(Value::as_str)
                .unwrap_or("wy");
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .ok_or("缺少歌曲 ID")?;
            let music_info = music_info_from_payload(payload, provider, id);
            let raw = source::lyrics_with_sources(&state.sources, provider, id, &music_info)?;
            Ok(serde_json::to_value(lyrics::result_from_raw(&raw, "在线音源"))
                .map_err(|e| e.to_string())?)
        }
        "system.info" => Ok(json!({
            "supportDir": state.store.support_dir.to_string_lossy(),
            "docsDir": state.store.docs_dir.to_string_lossy(),
            "mediaDir": state.store.media_dir.to_string_lossy(),
            "trackCount": state.library.tracks.len(),
            "sourceCount": state.sources.len(),
        })),
        _ => Err(format!("未知命令: {cmd}")),
    }
}

fn music_info_from_payload(payload: &Value, provider: &str, id: &str) -> Value {
    let title = payload.get("title").and_then(Value::as_str).unwrap_or("");
    let artist = payload.get("artist").and_then(Value::as_str).unwrap_or("");
    let album = payload.get("album").and_then(Value::as_str).unwrap_or("");
    let cover = payload.get("cover").and_then(Value::as_str).unwrap_or("");
    let duration = payload.get("duration").and_then(Value::as_f64).unwrap_or(0.0);
    let total = duration.round() as u64;
    let numeric_id = id.parse::<u64>().ok();
    let id_value = numeric_id
        .map(|v| Value::Number(v.into()))
        .unwrap_or_else(|| Value::String(id.to_string()));

    json!({
        "songmid": id_value,
        "songId": id_value,
        "id": id_value,
        "hash": id,
        "name": title,
        "title": title,
        "singer": artist,
        "artist": artist,
        "albumName": album,
        "album": album,
        "albumId": Value::Null,
        "interval": format!("{}:{:02}", total / 60, total % 60),
        "duration": total * 1000,
        "img": cover,
        "source": provider,
        "copyrightId": "",
        "strMediaMid": ""
    })
}

#[no_mangle]
pub extern "C" fn mf_call(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if input.is_null() {
            return Err("空请求".to_string());
        }
        let raw = unsafe { CStr::from_ptr(input) }
            .to_str()
            .map_err(|e| format!("请求不是 UTF-8: {e}"))?;
        let request: Value =
            serde_json::from_str(raw).map_err(|e| format!("请求 JSON 错误: {e}"))?;
        let cmd = request
            .get("cmd")
            .and_then(Value::as_str)
            .ok_or("缺少命令")?;
        let payload = request.get("payload").cloned().unwrap_or(Value::Null);
        handle(cmd, &payload)
    });

    let response = match result {
        Ok(Ok(data)) => json!({ "ok": true, "data": data }),
        Ok(Err(error)) => json!({ "ok": false, "error": error }),
        Err(_) => json!({ "ok": false, "error": "核心发生异常" }),
    };
    let text = serde_json::to_string(&response).unwrap_or_else(|_| {
        r#"{"ok":false,"error":"序列化响应失败"}"#.to_string()
    });
    CString::new(text)
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn mf_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}
