import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var keyword = ""
    @State private var results: [RemoteTrack] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var hasSearched = false
    @State private var showAddSource = false
    @State private var sourceURL = ""
    @State private var importing = false
    @State private var showSourceFileImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    searchCard
                    resultsSection
                    sourcesSection
                    engineNote
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddSource) {
                addSourceSheet
                    .presentationDetents([.height(360), .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("音乐源")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                Text("搜索在线音乐，或导入洛雪 LX 音源")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                sourceURL = ""
                showAddSource = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0x05060A))
                    .frame(width: 38, height: 38)
                    .background(Palette.accentGradient, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.cyan)
                    Text("网易云公开搜索")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }
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
                        Text(model.resolveQuality == "flac" ? "无损" : model.resolveQuality)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.cyan)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Palette.cyan.opacity(0.10), in: Capsule())
                }
            }
            HStack(spacing: 9) {
                SearchField(text: $keyword, placeholder: "搜索歌曲、歌手")
                Button {
                    Task { await search() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Palette.accentGradient)
                            .frame(width: 46, height: 44)
                        if isSearching {
                            ProgressView()
                                .tint(Color(hex: 0x05060A))
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(hex: 0x05060A))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            Text("搜索使用公开接口；播放时优先调用已导入的 LX 音源解析高质量地址。")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)
        }
        .padding(14)
        .glassPanel(corner: 20)
    }

    @ViewBuilder
    private var resultsSection: some View {
        if isSearching && results.isEmpty {
            HStack {
                Spacer()
                ProgressView().tint(Palette.cyan)
                Spacer()
            }
            .padding(.vertical, 24)
        } else if let searchError {
            EmptyStateView(
                icon: "wifi.exclamationmark",
                title: "搜索失败",
                subtitle: searchError
            )
        } else if !results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "搜索结果", actionTitle: "\(results.count) 首")
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, track in
                        RemoteTrackRow(track: track)
                        if index < results.count - 1 {
                            Divider().overlay(Palette.stroke).padding(.leading, 62)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .glassPanel(corner: 20)
            }
        } else if hasSearched {
            EmptyStateView(
                icon: "music.note",
                title: "没有找到结果",
                subtitle: "换个关键词试试，或导入一个 LX 音源。"
            )
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "我的音源", actionTitle: "添加") {
                sourceURL = ""
                showAddSource = true
            }
            if model.sources.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.accentGradient)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("还没有导入音源")
                                .font(.system(size: 15, weight: .semibold))
                            Text("兼容洛雪 LX 自定义音源 .js 脚本")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Text("导入后，MusicFox 会在播放时调用音源解析地址。音源由你自行提供，应用不内置任何音乐平台接口。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .lineSpacing(3)
                    GhostButton(title: "导入音源", icon: "plus") {
                        sourceURL = ""
                        showAddSource = true
                    }
                }
                .padding(15)
                .glassPanel(corner: 20)
            } else {
                ForEach(model.sources) { source in
                    SourceRow(source: source)
                }
            }
        }
    }

    private var engineNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
            Text("LX 音源脚本在 Rust 沙箱中运行，只负责解析播放地址与歌词。请只导入你信任的脚本。")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(3)
        }
        .padding(.horizontal, 4)
    }

    private func search() async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        searchError = nil
        hasSearched = true
        results = []
        do {
            let response = try await model.searchOnline(keyword: query)
            results = response.items
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    private var addSourceSheet: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("添加 LX 音源")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("支持 .js 脚本，可从网络或文件导入")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button {
                    showAddSource = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Palette.surfaceElevated, in: Circle())
                }
                .buttonStyle(.plain)
            }

            TextField("https://raw.githubusercontent.com/.../latest.js", text: $sourceURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.stroke, lineWidth: 1)
                )

            Button {
                let url = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty else { return }
                importing = true
                Task {
                    await model.importSource(url: url)
                    importing = false
                    showAddSource = false
                }
            } label: {
                HStack(spacing: 8) {
                    if importing {
                        ProgressView().tint(Color(hex: 0x05060A))
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Text(importing ? "正在导入…" : "从网络导入")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x05060A))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Palette.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(importing)

            Button {
                showSourceFileImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                    Text("从文件导入 .js")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Palette.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Text("导入来源示例：pdone/lx-music-source。脚本只保存在本机，不随应用打包。")
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
                .lineSpacing(2)

            Spacer()
        }
        .padding(20)
        .background(Palette.background)
        .fileImporter(
            isPresented: $showSourceFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "js") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let script = try String(contentsOf: url, encoding: .utf8)
                    let name = url.deletingPathExtension().lastPathComponent
                    importing = true
                    Task {
                        await model.importSource(script: script, name: name)
                        importing = false
                        showAddSource = false
                    }
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
    }
}
