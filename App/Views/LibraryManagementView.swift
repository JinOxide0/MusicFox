import SwiftUI

struct LibraryManagementView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var pendingDelete: Track?
    @State private var showDedupeConfirm = false

    private var filteredTracks: [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = query.isEmpty
            ? model.tracks
            : model.tracks.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.album.lowercased().contains(query)
            }
        return items.sorted {
            $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                SearchField(text: $searchText, placeholder: "搜索要删除的歌曲")
                if filteredTracks.isEmpty {
                    EmptyStateView(
                        icon: "music.note",
                        title: model.tracks.isEmpty ? "音乐库是空的" : "没有匹配的歌曲",
                        subtitle: model.tracks.isEmpty
                            ? "先在首页或设置里导入音乐。"
                            : "换个关键词试试。"
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                            ManageTrackRow(track: track) {
                                pendingDelete = track
                            }
                            if index < filteredTracks.count - 1 {
                                Divider().overlay(Palette.stroke).padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .glassPanel(corner: 20)
                }
                Text("删除会把歌曲文件从设备上永久移除，无法恢复。只是想从歌单移除时，请到歌单详情里操作。")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .lineSpacing(2)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationTitle("管理音乐库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog(
            "删除歌曲文件？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除文件", role: .destructive) {
                if let track = pendingDelete {
                    pendingDelete = nil
                    Task { await model.removeTrack(track) }
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("《\(pendingDelete?.title ?? "")》将从设备中永久删除，无法恢复。")
        }
        .confirmationDialog(
            "清理重复歌曲？",
            isPresented: $showDedupeConfirm,
            titleVisibility: .visible
        ) {
            Button("清理并删除重复文件", role: .destructive) {
                Task { await model.dedupeLibrary() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将保留音质最好的一份，删除其余 \(model.duplicateCount) 个重复文件，并从所有歌单中移除。")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                StatCard(value: "\(model.tracks.count)", label: "首歌曲", icon: "music.note")
                StatCard(value: "\(model.duplicateCount)", label: "首重复", icon: "square.on.square")
            }
            HStack(spacing: 9) {
                Button {
                    showDedupeConfirm = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                        Text(model.duplicateCount > 0 ? "清理 \(model.duplicateCount) 首重复歌曲" : "扫描重复歌曲")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        model.duplicateCount > 0 ? Color(hex: 0x05060A) : Palette.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        model.duplicateCount > 0
                        ? AnyShapeStyle(Palette.accentGradient)
                        : AnyShapeStyle(Palette.surfaceElevated),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.duplicateCount == 0)
            }
        }
        .padding(14)
        .glassPanel(corner: 20)
    }
}

private struct ManageTrackRow: View {
    @Environment(AppModel.self) private var model
    let track: Track
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.play(track)
            } label: {
                CoverArt(url: track.coverURL, size: 52, corner: 12)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(track.artist) · \(track.album)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                Text("\(track.format.uppercased()) · \(track.durationText) · \(track.qualityLabel)")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 6)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.pink)
                    .frame(width: 36, height: 36)
                    .background(Palette.pink.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}
