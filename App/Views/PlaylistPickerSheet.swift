import SwiftUI

struct PlaylistPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tracks: [Track]
    var onAdded: (() -> Void)? = nil

    @State private var showCreate = false
    @State private var newName = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 9) {
                        TagPill(text: "\(tracks.count) 首", color: Palette.cyan)
                        Text("选择要加入的歌单")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }

                    if model.playlists.isEmpty && !showCreate {
                        EmptyStateView(
                            icon: "music.note.list",
                            title: "还没有歌单",
                            subtitle: "先建一个歌单，再把选中的歌曲一次放进去。",
                            actionTitle: "新建歌单"
                        ) {
                            showCreate = true
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.playlists) { playlist in
                                Button {
                                    add(to: playlist)
                                } label: {
                                    HStack(spacing: 12) {
                                        PlaylistCover(
                                            tracks: model.playlistTracks(playlist),
                                            size: 46,
                                            corner: 11
                                        )
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(playlist.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Palette.textPrimary)
                                                .lineLimit(1)
                                            Text("\(model.playlistTracks(playlist).count) 首歌曲")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Palette.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(Palette.cyan)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 64)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(busy)
                                if playlist.id != model.playlists.last?.id {
                                    Divider().overlay(Palette.stroke).padding(.leading, 70)
                                }
                            }
                        }
                        .glassPanel(corner: 18)
                    }

                    if showCreate {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("新建歌单并加入")
                                .font(.system(size: 14, weight: .semibold))
                            HStack(spacing: 8) {
                                TextField("歌单名称", text: $newName)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .frame(height: 42)
                                    .background(
                                        Palette.surfaceElevated,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                Button {
                                    createAndAdd()
                                } label: {
                                    Text("创建")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x05060A))
                                        .padding(.horizontal, 16)
                                        .frame(height: 42)
                                        .background(
                                            Palette.accentGradient,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(busy || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(14)
                        .glassPanel(corner: 18)
                    } else {
                        GhostButton(title: "新建歌单", icon: "plus") {
                            showCreate = true
                        }
                    }

                    if busy {
                        HStack {
                            Spacer()
                            ProgressView().tint(Palette.cyan)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("加入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear {
                if model.playlists.isEmpty {
                    showCreate = true
                }
            }
        }
    }

    private func add(to playlist: Playlist) {
        guard !tracks.isEmpty, !busy else { return }
        busy = true
        Task {
            await model.add(tracks, to: playlist)
            busy = false
            onAdded?()
            dismiss()
        }
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !busy else { return }
        busy = true
        Task {
            await model.createPlaylist(name: name)
            if let playlist = model.playlists.last(where: { $0.name == name }) {
                await model.add(tracks, to: playlist)
            }
            busy = false
            onAdded?()
            dismiss()
        }
    }
}
