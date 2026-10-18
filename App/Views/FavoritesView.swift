import SwiftUI

struct FavoritesView: View {
    @Environment(AppModel.self) private var model
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var editingPlaylist: Playlist?
    @State private var renameText = ""
    @State private var deletingPlaylist: Playlist?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    favorites
                    playlists
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 160)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .sheet(isPresented: $showCreatePlaylist) {
                createPlaylistSheet
                    .presentationDetents([.height(230)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingPlaylist) { playlist in
                renamePlaylistSheet(playlist)
                    .presentationDetents([.height(230)])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "删除歌单「\(deletingPlaylist?.name ?? "")」？",
                isPresented: Binding(
                    get: { deletingPlaylist != nil },
                    set: { if !$0 { deletingPlaylist = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let playlist = deletingPlaylist {
                        Task { await model.deletePlaylist(playlist) }
                    }
                    deletingPlaylist = nil
                }
                Button("取消", role: .cancel) { deletingPlaylist = nil }
            } message: {
                Text("只会删除歌单，不会删除音乐文件。")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("收藏")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                Text("\(model.favoriteTracks.count) 首收藏 · \(model.playlists.count) 个歌单")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                newPlaylistName = ""
                showCreatePlaylist = true
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

    @ViewBuilder
    private var favorites: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "喜欢的歌曲")
            if model.favoriteTracks.isEmpty {
                EmptyStateView(
                    icon: "heart",
                    title: "还没有收藏",
                    subtitle: "在播放页或歌曲列表点一下爱心，\n喜欢的歌就会出现在这里。"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.favoriteTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: track, showAlbum: true)
                        if index < model.favoriteTracks.count - 1 {
                            Divider().overlay(Palette.stroke).padding(.leading, 64)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .glassPanel(corner: 20)
            }
        }
    }

    private var playlists: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "我的歌单", actionTitle: "新建") {
                newPlaylistName = ""
                showCreatePlaylist = true
            }
            if model.playlists.isEmpty {
                EmptyStateView(
                    icon: "music.note.list",
                    title: "建立你的第一个歌单",
                    subtitle: "按心情、场景或风格整理音乐，\n歌单只保存在本机。",
                    actionTitle: "新建歌单"
                ) {
                    newPlaylistName = ""
                    showCreatePlaylist = true
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(model.playlists) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistCard(playlist: playlist, width: 156)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingPlaylist = playlist
                                renameText = playlist.name
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deletingPlaylist = playlist
                            } label: {
                                Label("删除歌单", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var createPlaylistSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建歌单")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            TextField("歌单名称", text: $newPlaylistName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Palette.stroke, lineWidth: 1)
                )
            HStack(spacing: 10) {
                Button("取消") { showCreatePlaylist = false }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Button("创建") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    showCreatePlaylist = false
                    Task { await model.createPlaylist(name: name) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x05060A))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Palette.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            Spacer()
        }
        .padding(20)
        .background(Palette.background)
    }

    private func renamePlaylistSheet(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名歌单")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            TextField("歌单名称", text: $renameText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Palette.stroke, lineWidth: 1)
                )
            HStack(spacing: 10) {
                Button("取消") { editingPlaylist = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Button("保存") {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    editingPlaylist = nil
                    Task { await model.renamePlaylist(playlist, name: name) }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x05060A))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Palette.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            Spacer()
        }
        .padding(20)
        .background(Palette.background)
    }
}

struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDelete = false

    private var current: Playlist {
        model.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }

    private var items: [Track] {
        model.playlistTracks(current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if items.isEmpty {
                    EmptyStateView(
                        icon: "music.note",
                        title: "歌单是空的",
                        subtitle: "在歌曲的右键菜单里选择「加入歌单」，\n把喜欢的歌放进来。"
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                showAlbum: true,
                                removeFromPlaylist: current
                            )
                            if index < items.count - 1 {
                                Divider().overlay(Palette.stroke).padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .glassPanel(corner: 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 160)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = current.name
                        showRename = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDelete = true
                    } label: {
                        Label("删除歌单", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .alert("重命名歌单", isPresented: $showRename) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { await model.renamePlaylist(current, name: name) }
            }
        }
        .confirmationDialog("删除这个歌单？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    await model.deletePlaylist(current)
                    model.tab = .favorites
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除歌单，不会删除音乐文件。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            PlaylistCover(tracks: items, size: 92, corner: 20)
            VStack(alignment: .leading, spacing: 6) {
                Text(current.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text("\(items.count) 首歌曲")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                Button {
                    if !items.isEmpty {
                        model.player.playPlaylist(items)
                    }
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x05060A))
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Palette.accentGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0.5 : 1)
            }
            Spacer()
        }
    }
}
