import SwiftUI

struct TrackRow: View {
    @Environment(AppModel.self) private var model
    let track: Track
    var showAlbum = false
    var showCover = true
    var removeFromPlaylist: Playlist? = nil

    private var isCurrent: Bool {
        model.player.currentTrack?.id == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            if showCover {
                Button {
                    model.play(track)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        CoverArt(url: track.coverURL, size: 52, corner: 12)
                        if isCurrent {
                            Circle()
                                .fill(Palette.cyan)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(Palette.background, lineWidth: 2))
                                .offset(x: 2, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isCurrent ? Palette.cyan : Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(showAlbum ? "\(track.artist) · \(track.album)" : track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    if track.format.lowercased() == "flac" {
                        TagPill(text: "FLAC", color: Palette.cyan)
                    }
                }
            }

            Spacer(minLength: 6)

            if isCurrent && model.player.isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.cyan)
            } else {
                Text(track.durationText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
            }

            Button {
                model.toggleFavorite(track)
            } label: {
                Image(systemName: track.favorite ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(track.favorite ? Palette.pink : Palette.textTertiary)
                    .frame(width: 30, height: 32)
            }
            .buttonStyle(.plain)

            if let removeFromPlaylist {
                Menu {
                    Button(role: .destructive) {
                        Task { await model.remove(track, from: removeFromPlaylist) }
                    } label: {
                        Label("从歌单移除", systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            model.play(track)
        }
        .contextMenu {
            Button {
                model.play(track)
            } label: {
                Label("播放", systemImage: "play.fill")
            }
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
            if let removeFromPlaylist {
                Button(role: .destructive) {
                    Task { await model.remove(track, from: removeFromPlaylist) }
                } label: {
                    Label("从歌单移除", systemImage: "minus.circle")
                }
            }
        }
    }
}

struct AlbumCard: View {
    @Environment(AppModel.self) private var model
    let album: String
    let tracks: [Track]
    var width: CGFloat = 148

    private var cover: URL? {
        tracks.first?.coverURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArt(url: cover, size: width, corner: 17)
                .overlay(alignment: .bottomLeading) {
                    if let count = tracks.first?.format, !count.isEmpty {
                        TagPill(text: count.uppercased(), color: .white)
                            .padding(8)
                            .opacity(0.8)
                    }
                }
            Text(album)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(tracks.first?.artist ?? "")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !tracks.isEmpty {
                model.player.playPlaylist(tracks, startingAt: 0)
            }
        }
    }
}

struct PlaylistCover: View {
    let tracks: [Track]
    var size: CGFloat = 150
    var corner: CGFloat = 18

    var body: some View {
        ZStack {
            if tracks.count >= 4 {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(Array(tracks.prefix(4))) { track in
                        CoverArt(url: track.coverURL, size: (size - 2) / 2, corner: 0)
                    }
                }
            } else {
                CoverArt(url: tracks.first?.coverURL, size: size, corner: corner)
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            Image(systemName: "music.note.list")
                .font(.system(size: size * 0.2, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 10)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct PlaylistCard: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist
    var width: CGFloat = 150

    private var items: [Track] {
        model.playlistTracks(playlist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaylistCover(tracks: items, size: width, corner: 18)
            Text(playlist.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text("\(items.count) 首歌曲")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct RemoteTrackRow: View {
    @Environment(AppModel.self) private var model
    let track: RemoteTrack

    private var isCurrent: Bool {
        model.player.currentRemote?.id == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(url: track.coverUrl.flatMap { URL(string: $0) }, size: 50, corner: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isCurrent ? Palette.cyan : Palette.textPrimary)
                    .lineLimit(1)
                Text("\(track.artist) · \(track.album)")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if track.qualitys?.contains("flac") == true {
                TagPill(text: "FLAC", color: Palette.violet)
            }
            Text(track.durationText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
            if model.resolvingRemoteId == track.id {
                ProgressView()
                    .tint(Palette.cyan)
            } else {
                Image(systemName: isCurrent && model.player.isPlaying ? "waveform" : "play.circle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(isCurrent ? Palette.cyan : Palette.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            model.playRemote(track)
        }
    }
}

struct SourceRow: View {
    @Environment(AppModel.self) private var model
    let source: SourceInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Palette.softGradient)
                        .frame(width: 48, height: 48)
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.accentGradient)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(source.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if !source.version.isEmpty {
                            TagPill(text: "v\(source.version)", color: Palette.textSecondary)
                        }
                    }
                    Text(source.description.isEmpty ? "洛雪 LX 自定义音源" : source.description)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { source.enabled },
                    set: { value in Task { await model.toggleSource(source, enabled: value) } }
                ))
                .labelsHidden()
                .tint(Palette.cyan)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(source.enabled ? Palette.cyan : Palette.textTertiary)
                    .frame(width: 5, height: 5)
                Text(source.status.isEmpty ? (source.enabled ? "已启用" : "已停用") : source.status)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .glassPanel(corner: 18)
        .contextMenu {
            Button(role: .destructive) {
                Task { await model.removeSource(source) }
            } label: {
                Label("删除音源", systemImage: "trash")
            }
        }
    }
}

struct ArtistRow: View {
    @Environment(AppModel.self) private var model
    let artist: String
    let tracks: [Track]

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Palette.softGradient)
                    .frame(width: 50, height: 50)
                Text(String(artist.prefix(1)))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(artist)
                    .font(.system(size: 15, weight: .semibold))
                Text("\(tracks.count) 首歌曲 · \(Set(tracks.map(\.album)).count) 张专辑")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                model.player.playPlaylist(tracks)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            if let first = tracks.first {
                model.play(first, queue: tracks)
            }
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.cyan)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassPanel(corner: 17)
    }
}
