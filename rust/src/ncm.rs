use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{Seek, SeekFrom};
use std::path::{Path, PathBuf};

use ncmdump::Ncmdump;

use crate::library::{song_key, track_key, write_sidecar, SidecarMeta};
use crate::model::{ImportResult, LibraryData, NcmImportSummary};
use crate::store::Store;

fn sanitize_component(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        if ch.is_control() || matches!(ch, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') {
            out.push('_');
        } else {
            out.push(ch);
        }
    }
    let trimmed = out.trim().trim_matches('.').trim();
    let mut result: String = trimmed.chars().take(120).collect();
    if result.is_empty() {
        result = "未命名".into();
    }
    result
}

fn detect_extension(info_format: Option<&str>, data: &[u8]) -> &'static str {
    if let Some(format) = info_format {
        match format.to_ascii_lowercase().as_str() {
            "flac" => return "flac",
            "mp3" => return "mp3",
            "m4a" | "mp4" | "aac" => return "m4a",
            "wav" => return "wav",
            _ => {}
        }
    }
    if data.starts_with(b"fLaC") {
        "flac"
    } else if data.starts_with(b"ID3") || (data.len() > 2 && data[0] == 0xFF && data[1] == 0xFB) {
        "mp3"
    } else {
        "flac"
    }
}

fn cover_extension(data: &[u8]) -> &'static str {
    if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
        "jpg"
    } else if data.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        "png"
    } else {
        "jpg"
    }
}

fn unique_output(dir: &Path, stem: &str, ext: &str) -> PathBuf {
    let mut candidate = dir.join(format!("{stem}.{ext}"));
    let mut index = 2;
    while candidate.exists() {
        candidate = dir.join(format!("{stem} ({index}).{ext}"));
        index += 1;
    }
    candidate
}

enum DecryptOutcome {
    Imported(ImportResult, String),
    Skipped(String),
}

fn decrypt_one(
    store: &Store,
    source: &Path,
    existing_keys: &HashSet<String>,
    skip_duplicates: bool,
) -> Result<DecryptOutcome, String> {
    let file = File::open(source).map_err(|e| format!("无法打开文件: {e}"))?;
    let mut ncm = Ncmdump::from_reader(file).map_err(|e| format!("不是有效的 NCM 文件: {e}"))?;

    let info = ncm.get_info().ok();
    let title = info
        .as_ref()
        .map(|i| i.name.clone())
        .unwrap_or_else(|| {
            source
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("未命名")
                .to_string()
        });
    let artist = info
        .as_ref()
        .map(|i| {
            i.artist
                .iter()
                .map(|(name, _)| name.clone())
                .collect::<Vec<_>>()
                .join(" / ")
        })
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "未知艺术家".into());
    let album = info
        .as_ref()
        .map(|i| i.album.clone())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "未知专辑".into());
    let duration = info
        .as_ref()
        .map(|i| i.duration as f64 / 1000.0)
        .unwrap_or(0.0);
    let key = song_key(&title, &artist, duration);

    if skip_duplicates && existing_keys.contains(&key) {
        return Ok(DecryptOutcome::Skipped(format!("{artist} - {title}")));
    }

    let image = ncm.get_image().ok().filter(|data| !data.is_empty());
    ncm.seek(SeekFrom::Start(0))
        .map_err(|e| format!("读取失败: {e}"))?;
    let data = ncm.get_data().map_err(|e| format!("解密失败: {e}"))?;
    if data.is_empty() {
        return Err("解密结果为空".into());
    }
    let ext = detect_extension(info.as_ref().map(|i| i.format.as_str()), &data);

    fs::create_dir_all(&store.media_dir).map_err(|e| format!("无法创建音乐目录: {e}"))?;
    let stem = sanitize_component(&format!("{artist} - {title}"));
    let output = unique_output(&store.media_dir, &stem, ext);
    fs::write(&output, &data).map_err(|e| format!("写入文件失败: {e}"))?;

    let mut cover_path = None;
    if let Some(image) = image {
        let cover = output.with_extension(cover_extension(&image));
        if fs::write(&cover, &image).is_ok() {
            cover_path = Some(cover.to_string_lossy().to_string());
        }
    }

    let netease_id = info.as_ref().map(|i| i.id).filter(|id| *id > 0);

    let meta = SidecarMeta {
        title: Some(title.clone()),
        artist: Some(artist.clone()),
        album: Some(album.clone()),
        album_artist: Some(artist.clone()),
        lyrics: None,
        netease_id,
        ..Default::default()
    };
    let _ = write_sidecar(&output, &meta);

    Ok(DecryptOutcome::Imported(
        ImportResult {
            source: source.to_string_lossy().to_string(),
            output: output.to_string_lossy().to_string(),
            title,
            artist,
            album,
            cover_path,
        },
        key,
    ))
}

pub fn decrypt_batch(
    store: &Store,
    library: &LibraryData,
    sources: &[String],
    skip_duplicates: bool,
) -> NcmImportSummary {
    let mut summary = NcmImportSummary::default();
    let mut seen: HashSet<String> = if skip_duplicates {
        library.tracks.iter().map(track_key).collect()
    } else {
        HashSet::new()
    };

    for source in sources {
        let path = Path::new(source);
        if !path.is_file() {
            summary.errors.push(format!("文件不存在: {source}"));
            continue;
        }
        match decrypt_one(store, path, &seen, skip_duplicates) {
            Ok(DecryptOutcome::Imported(result, key)) => {
                if skip_duplicates {
                    seen.insert(key);
                }
                summary.imported.push(result);
            }
            Ok(DecryptOutcome::Skipped(label)) => summary.skipped.push(label),
            Err(error) => summary.errors.push(format!("{}: {error}", path.display())),
        }
    }
    summary
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decrypts_reference_ncm() {
        let sample = Path::new("/tmp/opencode/ncmdump.rs/crates/ncmdump/res/test.ncm");
        if !sample.exists() {
            return;
        }
        let dir = std::env::temp_dir().join(format!("musicfox-ncm-{}", std::process::id()));
        let store = Store::new(dir.join("support"), dir.join("docs")).unwrap();
        let outcome = decrypt_one(&store, sample, &HashSet::new(), false).expect("ncm decrypt");
        let DecryptOutcome::Imported(result, _) = outcome else {
            panic!("expected imported file");
        };
        assert!(Path::new(&result.output).is_file());
        assert!(!result.title.is_empty());
        let bytes = fs::read(&result.output).unwrap();
        assert!(bytes.starts_with(b"fLaC") || bytes.starts_with(b"ID3"));
        eprintln!("decrypted: {} ({} bytes)", result.output, bytes.len());
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn skips_duplicate_ncm() {
        let sample = Path::new("/tmp/opencode/ncmdump.rs/crates/ncmdump/res/test.ncm");
        if !sample.exists() {
            return;
        }
        let dir = std::env::temp_dir().join(format!("musicfox-ncm-dup-{}", std::process::id()));
        let store = Store::new(dir.join("support"), dir.join("docs")).unwrap();
        let paths = vec![
            sample.to_string_lossy().to_string(),
            sample.to_string_lossy().to_string(),
        ];
        let summary = decrypt_batch(&store, &LibraryData::default(), &paths, true);
        assert_eq!(summary.imported.len(), 1);
        assert_eq!(summary.skipped.len(), 1);
        let _ = fs::remove_dir_all(dir);
    }
}
