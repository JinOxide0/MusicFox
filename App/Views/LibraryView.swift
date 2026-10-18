import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .songs
    @State private var sort: SortOption = .title

    private enum SortOption: String, CaseIterable, Identifiable {
        case title = "标题"
        case artist = "艺术家"
        case album = "专辑"
        case recent = "最近加入"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    SearchField(text: $searchText, placeholder: "搜索歌曲、专辑、艺术家")
                    filterBar
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("音乐库")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                Text("\(model.tracks.count) 首歌曲 · \(model.albums.count) 张专辑")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Menu {
                Picker("排序", selection: $sort) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Palette.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
            }
            Button {
                Task { await model.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Palette.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(Palette.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        filter = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(filter == item ? Color(hex: 0x05060A) : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            filter == item ? AnyShapeStyle(Palette.accentGradient) : AnyShapeStyle(Palette.surfaceElevated),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.tracks.isEmpty {
            EmptyStateView(
                icon: "music.note.list",
                title: "音乐库还是空的",
                subtitle: "从文件 App 导入 FLAC、MP3、M4A 等音频，\n或者导入 NCM 让 MusicFox 自动解密。",
                actionTitle: "去设置导入"
            ) {
                model.tab = .settings
            }
        } else if filter == .songs {
            songList
        } else if filter == .albums {
            albumGrid
        } else {
            artistList
        }
    }

    private var filteredTracks: [Track] {
        var items = model.tracks
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.album.lowercased().contains(query)
            }
        }
        switch sort {
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            items.sort {
                $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
            }
        case .album:
            items.sort {
                $0.album.localizedStandardCompare($1.album) == .orderedAscending
            }
        case .recent:
            items.sort { $0.addedAt > $1.addedAt }
        }
        return items
    }

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, showAlbum: true)
                if index < filteredTracks.count - 1 {
                    Divider().overlay(Palette.stroke).padding(.leading, 64)
                }
            }
        }
        .padding(.horizontal, 12)
        .glassPanel(corner: 20)
    }

    private var albumGroups: [(String, [Track])] {
        var seen = Set<String>()
        var groups: [(String, [Track])] = []
        let source = filteredTracks
        for track in source {
            guard !seen.contains(track.album) else { continue }
            seen.insert(track.album)
            var albumTracks = source.filter { $0.album == track.album }
            albumTracks.sort { ($0.discNo ?? 0, $0.trackNo ?? 0) < ($1.discNo ?? 0, $1.trackNo ?? 0) }
            groups.append((track.album, albumTracks))
        }
        groups.sort { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        return groups
    }

    private var albumGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], alignment: .leading, spacing: 18) {
            ForEach(Array(albumGroups.enumerated()), id: \.offset) { _, group in
                AlbumCard(album: group.0, tracks: group.1, width: 156)
            }
        }
    }

    private var artistGroups: [(String, [Track])] {
        var groups: [(String, [Track])] = []
        var map: [String: [Track]] = [:]
        for track in filteredTracks {
            map[track.artist, default: []].append(track)
        }
        for (artist, items) in map {
            groups.append((artist, items))
        }
        groups.sort { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        return groups
    }

    private var artistList: some View {
        VStack(spacing: 0) {
            ForEach(Array(artistGroups.enumerated()), id: \.offset) { index, group in
                ArtistRow(artist: group.0, tracks: group.1)
                if index < artistGroups.count - 1 {
                    Divider().overlay(Palette.stroke).padding(.leading, 64)
                }
            }
        }
        .padding(.horizontal, 12)
        .glassPanel(corner: 20)
    }
}
