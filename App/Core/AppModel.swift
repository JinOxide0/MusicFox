import Foundation
import Observation

struct EmptyResponse: Codable {}
struct PlaylistMutation: Codable { var playlists: [Playlist] }
struct SourceImportResponse: Codable {
    var source: SourceInfo
    var sources: [SourceInfo]
}

@MainActor
@Observable
final class AppModel {
    var tracks: [Track] = []
    var playlists: [Playlist] = []
    var sources: [SourceInfo] = []
    var tab: AppTab = .home
    var isLoading = false
    var importStatus: String?
    var errorMessage: String?
    var resolveQuality = "flac"
    var resolvingRemoteId: String?
    var noticeMessage: String?
    var excludeDuplicatesOnImport: Bool {
        didSet {
            UserDefaults.standard.set(excludeDuplicatesOnImport, forKey: Self.importDedupeKey)
        }
    }
    var excludeDuplicatesInPlaylists: Bool {
        didSet {
            UserDefaults.standard.set(excludeDuplicatesInPlaylists, forKey: Self.playlistDedupeKey)
        }
    }

    let player = Player()

    private static let importDedupeKey = "MusicFox.excludeDuplicatesOnImport"
    private static let playlistDedupeKey = "MusicFox.excludeDuplicatesInPlaylists"

    private(set) var supportDir: URL?
    private(set) var docsDir: URL?
    private(set) var mediaDir: URL?
    private(set) var inboxDir: URL?

    init() {
        let defaults = UserDefaults.standard
        excludeDuplicatesOnImport =
            defaults.object(forKey: Self.importDedupeKey) as? Bool ?? true
        excludeDuplicatesInPlaylists =
            defaults.object(forKey: Self.playlistDedupeKey) as? Bool ?? true

        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let support = appSupport.appendingPathComponent("MusicFox", isDirectory: true)
            let media = documents.appendingPathComponent("Media", isDirectory: true)
            let inbox = documents.appendingPathComponent("NCMInbox", isDirectory: true)
            for directory in [support, media, inbox] {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            supportDir = support
            docsDir = documents
            mediaDir = media
            inboxDir = inbox
        }
        Task { await bootstrap() }
    }

    func bootstrap() async {
        guard let supportDir, let docsDir else { return }
        isLoading = true
        do {
            let response: InitResponse = try await RustCore.shared.callAsync(
                "init",
                ["supportDir": supportDir.path, "docsDir": docsDir.path],
                as: InitResponse.self
            )
            tracks = response.tracks
            playlists = response.playlists
            sources = response.sources
            await scan(showSpinner: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func scan(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        do {
            let snapshot: LibrarySnapshot = try await RustCore.shared.callAsync(
                "library.scan",
                [:],
                as: LibrarySnapshot.self
            )
            tracks = snapshot.tracks
            playlists = snapshot.playlists
            player.handleLibraryChange(tracks)
            player.setQueue(tracks, keepCurrent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        if showSpinner { isLoading = false }
    }

    // MARK: - Import

    func importAudio(_ urls: [URL]) async {
        guard let mediaDir else { return }
        importStatus = "正在导入 \(urls.count) 个项目…"
        let skipDuplicates = excludeDuplicatesOnImport
        let result = await Task.detached(priority: .utility) {
            ImportManager.copyAudio(
                urls: urls,
                to: mediaDir,
                skipDuplicates: skipDuplicates
            )
        }.value
        if result.count > 0 {
            importStatus = "正在整理音乐库…"
            await scan(showSpinner: false)
        }
        importStatus = nil
        if result.skipped > 0 {
            showNotice("已跳过 \(result.skipped) 个重复文件")
        }
        if result.count == 0 && result.skipped == 0 {
            errorMessage = "没有找到可播放的音频文件。支持 FLAC、MP3、M4A、AAC、WAV、AIFF。"
        } else if !result.errors.isEmpty {
            errorMessage = "有 \(result.errors.count) 个文件未能导入：\n" + result.errors.prefix(5).joined(separator: "\n")
        }
    }

    func importNCM(_ urls: [URL]) async {
        guard let inboxDir else { return }
        importStatus = "正在解密 NCM…"
        let copied = await Task.detached(priority: .utility) {
            ImportManager.copyNCMToInbox(urls: urls, inbox: inboxDir)
        }.value
        guard !copied.isEmpty else {
            importStatus = nil
            errorMessage = "没有找到 .ncm 文件。"
            return
        }
        do {
            let summary: NcmImportSummary = try await RustCore.shared.callAsync(
                "ncm.decrypt",
                [
                    "paths": copied.map(\.path),
                    "skipDuplicates": excludeDuplicatesOnImport
                ],
                as: NcmImportSummary.self
            )
            try? FileManager.default.removeItem(at: inboxDir)
            await scan(showSpinner: false)
            importStatus = nil
            if !summary.skipped.isEmpty {
                showNotice("已跳过 \(summary.skipped.count) 首重复歌曲")
            }
            if !summary.errors.isEmpty {
                errorMessage = summary.errors.prefix(6).joined(separator: "\n")
            }
        } catch {
            importStatus = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Playback

    func play(_ track: Track, queue: [Track]? = nil) {
        player.play(track: track, queue: queue ?? tracks)
    }

    func playPlaylist(_ playlist: Playlist) {
        let items = playlistTracks(playlist)
        guard !items.isEmpty else { return }
        player.playPlaylist(items)
    }

    func playRemote(_ track: RemoteTrack) {
        guard resolvingRemoteId == nil else { return }
        resolvingRemoteId = track.id
        Task {
            defer { resolvingRemoteId = nil }
            do {
                let resolved: ResolveResult = try await RustCore.shared.callAsync(
                    "source.resolve",
                    [
                        "provider": track.source,
                        "id": track.id,
                        "quality": resolveQuality,
                        "title": track.title,
                        "artist": track.artist,
                        "album": track.album,
                        "cover": track.coverUrl ?? "",
                        "duration": track.duration
                    ],
                    as: ResolveResult.self
                )
                guard let url = URL(string: resolved.url) else {
                    errorMessage = "音源返回了无效的播放地址。"
                    return
                }
                player.playRemote(track: track, url: url)
                player.showNowPlaying = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Favorites & playlists

    func toggleFavorite(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let previous = tracks[index].favorite
        tracks[index].favorite = !previous
        Task {
            do {
                let _: EmptyResponse = try await RustCore.shared.callAsync(
                    "library.favorite",
                    ["id": track.id, "favorite": !previous],
                    as: EmptyResponse.self
                )
            } catch {
                if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    tracks[index].favorite = previous
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func createPlaylist(name: String) async {
        do {
            let result: PlaylistMutation = try await RustCore.shared.callAsync(
                "playlist.create",
                ["name": name],
                as: PlaylistMutation.self
            )
            playlists = result.playlists
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renamePlaylist(_ playlist: Playlist, name: String) async {
        do {
            let result: PlaylistMutation = try await RustCore.shared.callAsync(
                "playlist.rename",
                ["id": playlist.id, "name": name],
                as: PlaylistMutation.self
            )
            playlists = result.playlists
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePlaylist(_ playlist: Playlist) async {
        do {
            let result: PlaylistMutation = try await RustCore.shared.callAsync(
                "playlist.delete",
                ["id": playlist.id],
                as: PlaylistMutation.self
            )
            playlists = result.playlists
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ track: Track, to playlist: Playlist) async {
        do {
            let result: PlaylistAddResponse = try await RustCore.shared.callAsync(
                "playlist.add",
                [
                    "id": playlist.id,
                    "trackId": track.id,
                    "skipDuplicates": excludeDuplicatesInPlaylists
                ],
                as: PlaylistAddResponse.self
            )
            playlists = result.playlists
            if !result.added {
                showNotice("歌单里已有这首歌")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ tracks: [Track], to playlist: Playlist) async {
        guard !tracks.isEmpty else { return }
        do {
            let result: PlaylistAddManyResponse = try await RustCore.shared.callAsync(
                "playlist.addMany",
                [
                    "id": playlist.id,
                    "trackIds": tracks.map(\.id),
                    "skipDuplicates": excludeDuplicatesInPlaylists
                ],
                as: PlaylistAddManyResponse.self
            )
            playlists = result.playlists
            if result.added == 0 {
                showNotice("这些歌曲已在歌单里")
            } else if result.skipped > 0 {
                showNotice("已加入 \(result.added) 首，跳过 \(result.skipped) 首重复")
            } else {
                showNotice("已加入 \(result.added) 首歌曲")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dedupePlaylist(_ playlist: Playlist) async {
        do {
            let result: PlaylistDedupeResponse = try await RustCore.shared.callAsync(
                "playlist.dedupe",
                ["id": playlist.id],
                as: PlaylistDedupeResponse.self
            )
            playlists = result.playlists
            showNotice(result.removed > 0 ? "已从歌单移除 \(result.removed) 首重复歌曲" : "歌单没有重复歌曲")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeTrack(_ track: Track) async {
        if player.currentTrack?.id == track.id {
            player.stop()
        }
        do {
            let snapshot: LibrarySnapshot = try await RustCore.shared.callAsync(
                "library.remove",
                ["id": track.id, "deleteFile": true],
                as: LibrarySnapshot.self
            )
            tracks = snapshot.tracks
            playlists = snapshot.playlists
            player.handleLibraryChange(tracks)
            showNotice("已删除《\(track.title)》")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dedupeLibrary() async {
        do {
            let result: LibraryDedupeResponse = try await RustCore.shared.callAsync(
                "library.dedupe",
                ["deleteFiles": true],
                as: LibraryDedupeResponse.self
            )
            tracks = result.tracks
            playlists = result.playlists
            player.handleLibraryChange(tracks)
            showNotice(
                result.removed > 0
                ? "已清理 \(result.removed) 首重复歌曲"
                : "没有发现重复歌曲"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var duplicateCount: Int {
        var seen = Set<String>()
        var count = 0
        for track in tracks {
            if seen.contains(track.songKey) {
                count += 1
            } else {
                seen.insert(track.songKey)
            }
        }
        return count
    }

    func showNotice(_ text: String) {
        noticeMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if noticeMessage == text {
                noticeMessage = nil
            }
        }
    }

    func remove(_ track: Track, from playlist: Playlist) async {
        do {
            let result: PlaylistMutation = try await RustCore.shared.callAsync(
                "playlist.remove",
                ["id": playlist.id, "trackId": track.id],
                as: PlaylistMutation.self
            )
            playlists = result.playlists
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playlistTracks(_ playlist: Playlist) -> [Track] {
        let map = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.trackIds.compactMap { map[$0] }
    }

    var favoriteTracks: [Track] {
        tracks.filter(\.favorite)
    }

    var recentlyAdded: [Track] {
        Array(tracks.sorted { $0.addedAt > $1.addedAt }.prefix(12))
    }

    var albums: [String] {
        Array(Set(tracks.map(\.album))).sorted()
    }

    var artists: [String] {
        Array(Set(tracks.map(\.artist))).sorted()
    }

    func tracks(inAlbum album: String) -> [Track] {
        tracks.filter { $0.album == album }
    }

    func tracks(byArtist artist: String) -> [Track] {
        tracks.filter { $0.artist == artist }
    }

    // MARK: - Sources

    func importSource(url: String) async {
        do {
            let result: SourceImportResponse = try await RustCore.shared.callAsync(
                "source.import",
                ["url": url],
                as: SourceImportResponse.self
            )
            sources = result.sources
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSource(script: String, name: String?) async {
        do {
            var payload: [String: Any] = ["script": script]
            if let name, !name.isEmpty { payload["name"] = name }
            let result: SourceImportResponse = try await RustCore.shared.callAsync(
                "source.import",
                payload,
                as: SourceImportResponse.self
            )
            sources = result.sources
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSource(_ source: SourceInfo) async {
        do {
            let result: SourcesList = try await RustCore.shared.callAsync(
                "source.remove",
                ["id": source.id],
                as: SourcesList.self
            )
            sources = result.sources
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSource(_ source: SourceInfo, enabled: Bool) async {
        do {
            let result: SourcesList = try await RustCore.shared.callAsync(
                "source.toggle",
                ["id": source.id, "enabled": enabled],
                as: SourcesList.self
            )
            sources = result.sources
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchOnline(keyword: String) async throws -> SearchResult {
        try await RustCore.shared.callAsync(
            "source.search",
            ["provider": "wy", "keyword": keyword, "page": 1, "limit": 30],
            as: SearchResult.self
        )
    }
}
