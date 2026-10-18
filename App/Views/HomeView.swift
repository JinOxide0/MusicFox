import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showAudioImporter = false
    @State private var showFolderImporter = false
    @State private var showNCMImporter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    hero
                    quickActions
                    stats
                    if !recentAlbums.isEmpty {
                        recentSection
                    }
                    if !model.favoriteTracks.isEmpty {
                        favoritesSection
                    }
                    if !model.playlists.isEmpty {
                        playlistsSection
                    }
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: Self.audioTypes,
                allowsMultipleSelection: true
            ) { result in handleImport(result) }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { result in handleImport(result) }
            .fileImporter(
                isPresented: $showNCMImporter,
                allowedContentTypes: Self.ncmTypes,
                allowsMultipleSelection: true
            ) { result in handleNCM(result) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            FoxMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("MusicFox")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text("把音乐留在自己的设备里")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                model.tab = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Palette.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let remote = model.player.currentRemote {
            remoteNowPlayingCard(remote)
        } else if let track = model.player.currentTrack {
            nowPlayingCard(track)
        } else if model.tracks.isEmpty {
            onboardingCard
        } else if let track = model.recentlyAdded.first {
            libraryHero(track)
        }
    }

    private func nowPlayingCard(_ track: Track) -> some View {
        Button {
            model.player.showNowPlaying = true
        } label: {
            HStack(spacing: 14) {
                CoverArt(url: track.coverURL, size: 76, corner: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text("继续聆听")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.cyan)
                    Text(track.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Palette.accentGradient)
            }
            .padding(15)
            .background(
                LinearGradient(
                    colors: [Palette.cyan.opacity(0.15), Palette.violet.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Palette.cyan.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func remoteNowPlayingCard(_ track: RemoteTrack) -> some View {
        Button {
            model.player.showNowPlaying = true
        } label: {
            HStack(spacing: 14) {
                CoverArt(url: track.coverUrl.flatMap { URL(string: $0) }, size: 76, corner: 18)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("在线播放")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.violet)
                        TagPill(text: "LX", color: Palette.violet)
                    }
                    Text(track.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Palette.accentGradient)
            }
            .padding(15)
            .background(
                LinearGradient(
                    colors: [Palette.violet.opacity(0.18), Palette.cyan.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Palette.violet.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Palette.softGradient)
                        .frame(width: 54, height: 54)
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Palette.accentGradient)
                }
                Spacer()
                TagPill(text: "RUST CORE", color: Palette.cyan)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("把你的音乐带回来")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("FLAC 无损、NCM 解密、同步歌词、收藏与歌单，全部留在本机。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
            }
            HStack(spacing: 9) {
                PrimaryButton(title: "导入音乐", icon: "plus") {
                    showAudioImporter = true
                }
                Button {
                    showNCMImporter = true
                } label: {
                    Text("NCM 解密")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Palette.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .glassPanel(corner: 24)
    }

    private func libraryHero(_ track: Track) -> some View {
        Button {
            model.play(track)
        } label: {
            HStack(spacing: 14) {
                CoverArt(url: track.coverURL, size: 78, corner: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text("从最近加入开始")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.cyan)
                    Text(track.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text("\(track.artist) · \(track.album)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Palette.accentGradient)
            }
            .padding(15)
            .glassPanel(corner: 24)
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ActionCard(icon: "square.and.arrow.down", title: "导入文件", subtitle: "FLAC / MP3 / M4A") {
                showAudioImporter = true
            }
            ActionCard(icon: "folder.badge.plus", title: "导入文件夹", subtitle: "整个专辑一次导入") {
                showFolderImporter = true
            }
            ActionCard(icon: "lock.open.fill", title: "NCM 解密", subtitle: "网易云下载歌曲") {
                showNCMImporter = true
            }
            ActionCard(icon: "bolt.horizontal.fill", title: "添加音源", subtitle: "兼容洛雪 LX 脚本") {
                model.tab = .sources
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 9) {
            StatCard(value: "\(model.tracks.count)", label: "首歌曲", icon: "music.note")
            StatCard(value: "\(model.albums.count)", label: "张专辑", icon: "square.stack")
            StatCard(value: "\(model.favoriteTracks.count)", label: "个收藏", icon: "heart.fill")
        }
    }

    private var recentAlbums: [AlbumGroup] {
        var seen = Set<String>()
        var result: [AlbumGroup] = []
        for track in model.recentlyAdded {
            guard !seen.contains(track.album) else { continue }
            seen.insert(track.album)
            result.append(
                AlbumGroup(
                    id: track.album,
                    album: track.album,
                    tracks: model.tracks(inAlbum: track.album)
                )
            )
        }
        return Array(result.prefix(8))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "最近加入", actionTitle: "查看全部") {
                model.tab = .library
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 13) {
                    ForEach(recentAlbums) { group in
                        AlbumCard(album: group.album, tracks: group.tracks)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "我的收藏", actionTitle: "查看全部") {
                model.tab = .favorites
            }
            VStack(spacing: 0) {
                ForEach(Array(model.favoriteTracks.prefix(4))) { track in
                    TrackRow(track: track)
                    if track.id != model.favoriteTracks.prefix(4).last?.id {
                        Divider().overlay(Palette.stroke)
                    }
                }
            }
            .padding(.horizontal, 12)
            .glassPanel(corner: 20)
        }
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的歌单", actionTitle: "管理") {
                model.tab = .favorites
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 13) {
                    ForEach(model.playlists) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            FoxMark(size: 18)
            Text("MusicFox 0.1 · Rust core · 本地优先")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await model.importAudio(urls) }
        case .failure(let error):
            model.errorMessage = error.localizedDescription
        }
    }

    private func handleNCM(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await model.importNCM(urls) }
        case .failure(let error):
            model.errorMessage = error.localizedDescription
        }
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
        // The picker must accept every regular file: some file providers mark
        // .ncm as a dynamic type, which makes a narrow filter grey out files.
        [.data]
    }
}

private struct AlbumGroup: Identifiable {
    let id: String
    let album: String
    let tracks: [Track]
}

private struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.softGradient)
                        .frame(width: 39, height: 39)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.cyan)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(height: 66)
            .glassPanel(corner: 17)
        }
        .buttonStyle(.plain)
    }
}
