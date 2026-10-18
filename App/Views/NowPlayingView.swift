import SwiftUI

struct NowPlayingView: View {
    @Environment(AppModel.self) private var model
    @State private var showLyrics = false
    @State private var showQueue = false

    var body: some View {
        @Bindable var player = model.player
        GeometryReader { proxy in
            let coverSize = min(proxy.size.width - 68, min(proxy.size.height * 0.40, 330))
            ZStack {
                PlayerBackground(player: player)
                VStack(spacing: 0) {
                    topBar

                    if showLyrics {
                        compactTrackInfo
                            .padding(.top, 10)
                        LyricsPanel()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 6)
                    } else {
                        Spacer(minLength: 8)
                        CoverArt(url: player.coverURL, size: coverSize, corner: 30)
                            .shadow(color: .black.opacity(0.55), radius: 32, y: 18)
                            .shadow(color: Palette.violet.opacity(0.20), radius: 48)
                        trackInfo
                            .padding(.top, 22)
                        Spacer(minLength: 8)
                    }

                    progressSection
                        .padding(.top, 8)
                    controls
                        .padding(.top, 8)
                    bottomBar
                        .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 10))
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button {
                model.player.showNowPlaying = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text(model.player.currentRemote == nil ? "本地音乐" : "在线 · \(model.player.currentRemote?.source.uppercased() ?? "")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer()

            Menu {
                if let track = model.player.currentTrack {
                    Button {
                        model.toggleFavorite(track)
                    } label: {
                        Label(track.favorite ? "取消收藏" : "收藏", systemImage: track.favorite ? "heart.slash" : "heart")
                    }
                    Menu {
                        if model.playlists.isEmpty {
                            Text("还没有歌单")
                        } else {
                            ForEach(model.playlists) { playlist in
                                Button {
                                    Task { await model.add(track, to: playlist) }
                                } label: {
                                    Label(playlist.name, systemImage: "text.badge.plus")
                                }
                            }
                        }
                    } label: {
                        Label("加入歌单", systemImage: "text.badge.plus")
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLyrics.toggle()
                    }
                } label: {
                    Label(showLyrics ? "显示封面" : "显示歌词", systemImage: "text.alignleft")
                }
                Button {
                    showQueue = true
                } label: {
                    Label("播放队列", systemImage: "list.bullet")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
            }
        }
    }

    private var trackInfo: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Text(model.player.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let track = model.player.currentTrack {
                    Button {
                        model.toggleFavorite(track)
                    } label: {
                        Image(systemName: track.favorite ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(track.favorite ? Palette.pink : Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(model.player.artist)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let track = model.player.currentTrack {
                    TagPill(text: track.format.uppercased(), color: Palette.cyan)
                    if let depth = track.bitDepth, let rate = track.sampleRate {
                        TagPill(text: "\(depth)bit · \(rate / 1000)kHz", color: Palette.violet)
                    }
                } else if let remote = model.player.currentRemote {
                    TagPill(text: "网易云", color: Palette.pink)
                    if let quality = remote.qualitys?.last {
                        TagPill(text: quality == "flac" ? "FLAC" : quality, color: Palette.violet)
                    }
                }
            }
            .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
    }

    private var compactTrackInfo: some View {
        HStack(spacing: 10) {
            CoverArt(url: model.player.coverURL, size: 42, corner: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.player.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(model.player.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(model.player.lyrics.source)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { model.player.progress },
                    set: { model.player.seek(to: $0) }
                ),
                in: 0...max(model.player.duration, 1)
            )
            .tint(Palette.cyan)
            HStack {
                Text(model.player.progressText)
                Spacer()
                Text(model.player.durationText)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.textTertiary)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button {
                model.player.shuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.player.shuffle ? Palette.cyan : Palette.textSecondary)
                    .frame(width: 38, height: 40)
            }
            .buttonStyle(.plain)

            Button {
                model.player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Button {
                model.player.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(Palette.accentGradient)
                        .frame(width: 70, height: 70)
                        .shadow(color: Palette.cyan.opacity(0.25), radius: 20)
                    Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(Color(hex: 0x05060A))
                        .offset(x: model.player.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)

            Button {
                model.player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Button {
                model.player.cycleRepeatMode()
            } label: {
                Image(systemName: model.player.repeatMode.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(model.player.repeatMode == .off ? Palette.textSecondary : Palette.cyan)
                    .frame(width: 38, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomBar: some View {
        HStack {
            bottomButton(
                title: "歌词",
                icon: "text.alignleft",
                active: showLyrics
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLyrics.toggle()
                }
            }
            Spacer()
            bottomButton(title: "队列", icon: "list.bullet", active: showQueue) {
                showQueue = true
            }
            Spacer()
            if let track = model.player.currentTrack {
                bottomButton(
                    title: track.favorite ? "已收藏" : "收藏",
                    icon: track.favorite ? "heart.fill" : "heart",
                    active: track.favorite
                ) {
                    model.toggleFavorite(track)
                }
            } else {
                bottomButton(title: "音源", icon: "bolt.horizontal", active: false) {
                    model.player.showNowPlaying = false
                    model.tab = .sources
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func bottomButton(
        title: String,
        icon: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(active ? Palette.cyan : Palette.textSecondary)
            .frame(width: 58, height: 40)
        }
        .buttonStyle(.plain)
    }
}

struct PlayerBackground: View {
    let player: Player

    var body: some View {
        ZStack {
            AppBackground()
            if let track = player.currentTrack,
               let image = ImageCache.shared.localImage(for: track.coverURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 68)
                    .opacity(0.42)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if let raw = player.currentRemote?.coverUrl,
                      let url = URL(string: raw) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 68)
                        .opacity(0.38)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } placeholder: {
                    Color.clear
                }
            }
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct LyricsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            if model.player.lyricsLoading {
                Spacer()
                ProgressView()
                    .tint(Palette.cyan)
                Text("正在获取歌词…")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 8)
                Spacer()
            } else if model.player.lyrics.lines.isEmpty {
                if model.player.lyrics.plain.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "text.alignleft",
                        title: "暂无歌词",
                        subtitle: "本地文件没有内嵌歌词，\n可以尝试从网络匹配。",
                        actionTitle: "从网络获取"
                    ) {
                        model.player.reloadLyrics()
                    }
                    Spacer()
                } else {
                    ScrollView {
                        Text(model.player.lyrics.plain)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.textPrimary.opacity(0.86))
                            .lineSpacing(8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                syncedLyrics
            }
        }
    }

    private var syncedLyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(Array(model.player.lyrics.lines.enumerated()), id: \.offset) { index, line in
                        let active = model.player.activeLyricIndex == index
                        VStack(spacing: 5) {
                            Text(line.text)
                                .font(.system(
                                    size: active ? 21 : 17,
                                    weight: active ? .bold : .medium,
                                    design: .rounded
                                ))
                                .foregroundStyle(active ? Palette.cyan : Palette.textPrimary.opacity(0.55))
                            if let translation = line.translation, !translation.isEmpty {
                                Text(translation)
                                    .font(.system(size: active ? 13 : 11, weight: .medium))
                                    .foregroundStyle(active ? Palette.textPrimary.opacity(0.8) : Palette.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .scaleEffect(active ? 1.0 : 0.96)
                        .id(index)
                    }
                }
                .padding(.vertical, 44)
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let active = model.player.activeLyricIndex {
                    proxy.scrollTo(active, anchor: .center)
                }
            }
            .onChange(of: model.player.activeLyricIndex) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

struct QueueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if model.player.queue.isEmpty {
                        EmptyStateView(
                            icon: "list.bullet",
                            title: "队列是空的",
                            subtitle: "从音乐库播放一首歌，队列会显示在这里。"
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(Array(model.player.queue.enumerated()), id: \.element.id) { index, track in
                            Button {
                                model.player.playPlaylist(model.player.queue, startingAt: index)
                            } label: {
                                HStack(spacing: 12) {
                                    CoverArt(url: track.coverURL, size: 44, corner: 10)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(
                                                model.player.currentTrack?.id == track.id
                                                ? Palette.cyan
                                                : Palette.textPrimary
                                            )
                                            .lineLimit(1)
                                        Text(track.artist)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if model.player.currentTrack?.id == track.id {
                                        Image(systemName: "waveform")
                                            .foregroundStyle(Palette.cyan)
                                    }
                                    Text(track.durationText)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Palette.textTertiary)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 62)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < model.player.queue.count - 1 {
                                Divider().overlay(Palette.stroke).padding(.leading, 72)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
