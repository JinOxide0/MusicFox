use std::fs;
use std::path::{Path, PathBuf};

use crate::model::{LibraryData, SourceInfo};

pub struct Store {
    pub support_dir: PathBuf,
    pub docs_dir: PathBuf,
    pub media_dir: PathBuf,
    pub covers_dir: PathBuf,
    pub lyrics_dir: PathBuf,
    pub sources_dir: PathBuf,
    pub library_path: PathBuf,
    pub sources_path: PathBuf,
}

impl Store {
    pub fn new(support_dir: impl AsRef<Path>, docs_dir: impl AsRef<Path>) -> std::io::Result<Self> {
        let support_dir = support_dir.as_ref().to_path_buf();
        let docs_dir = docs_dir.as_ref().to_path_buf();
        let media_dir = docs_dir.join("Media");
        let covers_dir = support_dir.join("Covers");
        let lyrics_dir = support_dir.join("Lyrics");
        let sources_dir = support_dir.join("Sources");

        for dir in [&support_dir, &media_dir, &covers_dir, &lyrics_dir, &sources_dir] {
            fs::create_dir_all(dir)?;
        }

        Ok(Self {
            library_path: support_dir.join("library.json"),
            sources_path: support_dir.join("sources.json"),
            support_dir,
            docs_dir,
            media_dir,
            covers_dir,
            lyrics_dir,
            sources_dir,
        })
    }

    pub fn load_library(&self) -> LibraryData {
        fs::read_to_string(&self.library_path)
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_default()
    }

    pub fn save_library(&self, library: &LibraryData) -> std::io::Result<()> {
        let tmp = self.library_path.with_extension("json.tmp");
        let raw = serde_json::to_vec_pretty(library)?;
        fs::write(&tmp, raw)?;
        fs::rename(tmp, &self.library_path)?;
        Ok(())
    }

    pub fn load_sources(&self) -> Vec<SourceInfo> {
        fs::read_to_string(&self.sources_path)
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok())
            .unwrap_or_default()
    }

    pub fn save_sources(&self, sources: &[SourceInfo]) -> std::io::Result<()> {
        let tmp = self.sources_path.with_extension("json.tmp");
        let raw = serde_json::to_vec_pretty(sources)?;
        fs::write(&tmp, raw)?;
        fs::rename(tmp, &self.sources_path)?;
        Ok(())
    }
}

pub fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}
