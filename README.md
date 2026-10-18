# MusicFox

一款面向 iPhone 的本地优先音乐播放器。Rust 负责音乐库、NCM 解密、歌词和音源核心，SwiftUI 负责原生界面与播放。

## 已实现

- 本地音乐导入：FLAC / MP3 / M4A / AAC / WAV / AIFF / ALAC
- 读取内嵌标签、封面、时长、采样率、位深
- 网易云 `.ncm` 解密为原始 FLAC / MP3，并保留封面与元数据
- 本地 `.lrc`、内嵌歌词、LRCLIB / 网易云歌词匹配
- 收藏、歌单、专辑 / 艺术家分类
- 导入/歌单去重开关、音乐库管理与删除、重复歌曲清理
- 后台播放、锁屏控制、播放队列
- 深色玻璃拟态界面、几何科技狐狸图标
- 洛雪 LX 音源脚本导入（运行时正在接入）
- 网易云公开搜索 + 在线播放兜底

## 为什么是 Rust + SwiftUI

- Rust：NCM 解密、FLAC 标签、歌词解析、音源沙箱、文件扫描
- SwiftUI：原生 AVFoundation 播放、后台/锁屏、低功耗界面
- 不使用 WebView，不做跨端套壳

## 构建

没有 Mac 也可以构建。推送到 GitHub 后，`Build MusicFox IPA` Actions 会在 macOS runner 上：

1. 编译 `aarch64-apple-ios` 的 Rust 静态库
2. 用 XcodeGen 生成工程
3. 编译未签名 IPA
4. 上传 `MusicFox-ipa` artifact

下载 artifact，解压得到 `MusicFox.ipa`，用 SideStore 安装并签名即可。免费 Apple ID 需要每 7 天刷新。

## 安装后

1. 打开 SideStore，导入 `MusicFox.ipa`
2. 首次启动允许本地网络（如果使用局域网音源）
3. 首页或设置里导入音乐 / NCM
4. 文件 App › MusicFox › Media 也可以直接放音乐，然后在设置里重新扫描

## 目录

```
App/            SwiftUI 界面与播放器
rust/           Rust 核心（FFI: mf_call / mf_free）
scripts/        图标生成脚本
project.yml     XcodeGen 工程描述
.github/        macOS 构建流水线
```

## 支持格式

播放依赖 iOS AVFoundation：FLAC、MP3、M4A/AAC、ALAC、WAV、AIFF、CAF。OGG/Opus 暂未接入。

## 说明

MusicFox 不内置任何音乐内容。NCM 解密与本地播放均在本机完成；在线音源由用户自行导入，请遵守当地法律与平台条款。
