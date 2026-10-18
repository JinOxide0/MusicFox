import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAudioImporter = false
    @State private var showFolderImporter = false
    @State private var showNCMImporter = false
    @State private var storageText = "计算中…"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    importSection
                    librarySection
                    playbackSection
                    sidesStoreSection
                    aboutSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: Self.audioTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await model.importAudio(urls) }
                } else if case .failure(let error) = result {
                    model.errorMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await model.importAudio(urls) }
                } else if case .failure(let error) = result {
                    model.errorMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showNCMImporter,
                allowedContentTypes: Self.ncmTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await model.importNCM(urls) }
                } else if case .failure(let error) = result {
                    model.errorMessage = error.localizedDescription
                }
            }
            .task {
                await updateStorage()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            FoxMark(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                Text("导入、存储与播放偏好")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "导入")
            VStack(spacing: 0) {
                SettingsRow(icon: "square.and.arrow.down", title: "导入音乐文件", subtitle: "FLAC、MP3、M4A、AAC、WAV、AIFF") {
                    showAudioImporter = true
                }
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                SettingsRow(icon: "folder.badge.plus", title: "导入整个文件夹", subtitle: "保留文件夹作为专辑") {
                    showFolderImporter = true
                }
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                SettingsRow(icon: "lock.open.fill", title: "导入并解密 NCM", subtitle: "输出原始 FLAC / MP3 并保留封面歌词") {
                    showNCMImporter = true
                }
            }
            .glassPanel(corner: 20)
            Text("文件会复制到 文件 App › MusicFox › Media。你也可以直接用文件 App 把音乐拖进这个目录，然后重新扫描。")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
                .padding(.horizontal, 4)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "音乐库")
            HStack(spacing: 9) {
                StatCard(value: "\(model.tracks.count)", label: "首歌曲", icon: "music.note")
                StatCard(value: "\(model.albums.count)", label: "张专辑", icon: "square.stack")
                StatCard(value: "\(model.artists.count)", label: "位艺术家", icon: "person.2.fill")
            }
            VStack(spacing: 0) {
                SettingsInfoRow(icon: "internaldrive", title: "本地音乐占用", value: storageText)
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                SettingsInfoRow(icon: "heart.fill", title: "收藏歌曲", value: "\(model.favoriteTracks.count) 首")
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                Button {
                    Task {
                        await model.scan()
                        await updateStorage()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.cyan)
                            .frame(width: 26)
                        Text("重新扫描音乐库")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .glassPanel(corner: 20)
        }
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "播放")
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.cyan)
                        .frame(width: 26)
                    Text("在线音质偏好")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Menu {
                        ForEach(["128k", "320k", "flac"], id: \.self) { quality in
                            Button {
                                model.resolveQuality = quality
                            } label: {
                                HStack {
                                    Text(quality == "flac" ? "无损 FLAC" : quality)
                                    if model.resolveQuality == quality {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(model.resolveQuality == "flac" ? "无损 FLAC" : model.resolveQuality)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.cyan)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                SettingsInfoRow(icon: "moon.fill", title: "后台播放", value: "已启用")
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                SettingsInfoRow(icon: "lock.shield", title: "播放引擎", value: "AVFoundation 原生")
            }
            .glassPanel(corner: 20)
        }
    }

    private var sidesStoreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "SideStore")
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.cyan)
                VStack(alignment: .leading, spacing: 5) {
                    Text("7 天签名刷新")
                        .font(.system(size: 14, weight: .semibold))
                    Text("SideStore 会自动刷新签名；免费 Apple ID 同时最多安装 3 个应用。后台播放需要在系统设置中允许 MusicFox 后台刷新。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                }
            }
            .padding(14)
            .glassPanel(corner: 20)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "关于")
            VStack(spacing: 0) {
                SettingsInfoRow(icon: "musicfox", title: "MusicFox", value: versionText)
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                Link(destination: URL(string: "https://github.com/JinOxide0/MusicFox")!) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.cyan)
                            .frame(width: 26)
                        Text("GitHub 项目主页")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                Divider().overlay(Palette.stroke).padding(.leading, 50)
                SettingsInfoRow(icon: "cpu", title: "核心", value: "Rust + SwiftUI")
            }
            .glassPanel(corner: 20)
            Text("MusicFox 不提供任何音乐内容。本地播放与 NCM 解密均在你的设备上完成；在线音源由你自行导入，请遵守当地法律与平台条款。")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
                .padding(.horizontal, 4)
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private func updateStorage() async {
        guard let mediaDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Media", isDirectory: true) else { return }
        let bytes = await Task.detached(priority: .utility) { () -> Int64 in
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: mediaDir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }
            var total: Int64 = 0
            for case let url as URL in enumerator {
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let size = values.fileSize {
                    total += Int64(size)
                }
            }
            return total
        }.value
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        storageText = formatter.string(fromByteCount: bytes)
    }

    private static var audioTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        for ext in ["flac", "m4a", "aac", "caf", "alac", "aif"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    private static var ncmTypes: [UTType] {
        if let type = UTType(filenameExtension: "ncm") { return [type] }
        return [.data]
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.cyan)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.cyan)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }
}
