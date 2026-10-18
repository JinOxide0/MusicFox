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

    let player = Player()

    private(set) var supportDir: URL?
    private(set) var docsDir: URL?
    private(set) var mediaDir: URL?
    private(set) var inboxDir: URL?

    init() {
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
        let result = await Task.detached(priority: .utility) {
            ImportManager.copyAudio(urls: urls, to: mediaDir)
        }.value
        if result.count > 0 {
            importStatus = "正在整理音乐库…"
            await scan(showSpinner: false)
        }
        importStatus = nil
        if result.count == 0 {
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
                ["paths": copied.map(\.path)],
                as: NcmImportSummary.self
            )
            try? FileManager.default.removeItem(at: inboxDir)
            await scan(showSpinner: false)
            importStatus = nil
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
        Task {
            do {
                let resolved: ResolveResult = try await RustCore.shared.callAsync(
                    "source.resolve",
                    [
                        "provider": track.source,
                        "id": track.id,
                        "quality": resolveQuality
                    ],
                    as: ResolveResult.self
                )
                guard let url = URL(string: resolved.url) else {
                    errorMessage = "音源返回了无效的播放地址。"
                    return
                }
                player.playRemote(track: track, url: url)
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
            let result: PlaylistMutation = try await RustCore.shared.callAsync(
                "playlist.add",
                ["id": playlist.id, "trackId": track.id],
                as: PlaylistMutation.self
            )
            playlists = result.playlists
        } catch {
            errorMessage = error.localizedDescription
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
