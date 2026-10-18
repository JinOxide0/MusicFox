use std::sync::OnceLock;
use std::time::Duration;

use ureq::Agent;

static AGENT: OnceLock<Agent> = OnceLock::new();

pub fn agent() -> &'static Agent {
    AGENT.get_or_init(|| {
        Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(12)))
            .user_agent("MusicFox/0.1 (iOS; +https://github.com/JinOxide0/MusicFox)")
            .build()
            .into()
    })
}

pub fn get_text(url: &str) -> Result<String, String> {
    let mut response = agent()
        .get(url)
        .call()
        .map_err(|e| format!("网络请求失败: {e}"))?;
    response
        .body_mut()
        .read_to_string()
        .map_err(|e| format!("读取响应失败: {e}"))
}

pub fn get_json<T: serde::de::DeserializeOwned>(url: &str) -> Result<T, String> {
    let mut response = agent()
        .get(url)
        .call()
        .map_err(|e| format!("网络请求失败: {e}"))?;
    response
        .body_mut()
        .read_json::<T>()
        .map_err(|e| format!("解析响应失败: {e}"))
}
