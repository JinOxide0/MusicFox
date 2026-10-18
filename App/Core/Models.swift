import Foundation

struct Track: Codable, Identifiable, Hashable {
    let id: String
    let path: String
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let duration: Double
    let trackNo: Int?
    let discNo: Int?
    let year: Int?
    let genre: String?
    let format: String
    let sampleRate: Int?
    let bitDepth: Int?
    let bitrate: Int?
    let coverPath: String?
    let lyrics: String?
    var favorite: Bool
    let addedAt: Int
    let sourceId: String?
    let remoteId: String?
    let remoteUrl: String?

    var fileURL: URL? {
        path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    var coverURL: URL? {
        coverPath.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    var qualityLabel: String {
        if let bitDepth, let sampleRate {
            return "\(bitDepth)bit / \(sampleRate / 1000)kHz"
        }
        if let bitrate {
            return "\(bitrate) kbps"
        }
        return format.uppercased()
    }

    var durationText: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var songKey: String {
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let normalizedArtist = artist
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return "\(normalizedTitle)|\(normalizedArtist)|\(Int(duration.rounded()))"
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var trackIds: [String]
    let createdAt: Int
}

struct LibrarySnapshot: Codable {
    var tracks: [Track]
    var playlists: [Playlist]

    static let empty = LibrarySnapshot(tracks: [], playlists: [])
}

struct InitResponse: Codable {
    var tracks: [Track]
    var playlists: [Playlist]
    var sources: [SourceInfo]
}

struct SourceInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let author: String
    let version: String
    let homepage: String
    let scriptPath: String
    var enabled: Bool
    var sources: [String]
    var status: String
}

struct LyricsLine: Codable, Hashable {
    let time: Double
    let text: String
    let translation: String?
}

struct LyricsResult: Codable {
    var lines: [LyricsLine]
    var plain: String
    var synced: Bool
    var source: String

    static let empty = LyricsResult(lines: [], plain: "", synced: false, source: "")
}

struct ImportResult: Codable, Identifiable {
    var id: String { output }
    let source: String
    let output: String
    let title: String
    let artist: String
    let album: String
    let coverPath: String?
}

struct NcmImportSummary: Codable {
    var imported: [ImportResult]
    var errors: [String]
    var skipped: [String]
}

struct PlaylistAddResponse: Codable {
    var playlists: [Playlist]
    var added: Bool
}

struct PlaylistAddManyResponse: Codable {
    var playlists: [Playlist]
    var added: Int
    var skipped: Int
}

struct PlaylistDedupeResponse: Codable {
    var playlists: [Playlist]
    var removed: Int
}

struct LibraryDedupeResponse: Codable {
    var removed: Int
    var tracks: [Track]
    var playlists: [Playlist]
}

struct RemoteTrack: Codable, Identifiable, Hashable {
    let id: String
    let source: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let coverUrl: String?
    let qualitys: [String]?

    var durationText: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct SearchResult: Codable {
    let source: String
    let total: Int
    let items: [RemoteTrack]
}

struct ResolveResult: Codable {
    let url: String
    let quality: String
    let source: String
}

struct SystemInfo: Codable {
    let supportDir: String
    let docsDir: String
    let mediaDir: String
    let trackCount: Int
    let sourceCount: Int
}

struct SourcesList: Codable {
    let sources: [SourceInfo]
}

enum RepeatMode: String, CaseIterable {
    case off
    case all
    case one

    var icon: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case songs = "歌曲"
    case albums = "专辑"
    case artists = "艺术家"

    var id: String { rawValue }
}

enum AppTab: Hashable {
    case home
    case library
    case favorites
    case sources
    case settings
}
