import Foundation

struct ImportCopyResult {
    var count: Int = 0
    var errors: [String] = []
}

enum ImportManager {
    static let audioExtensions: Set<String> = [
        "flac", "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "alac", "mp4"
    ]

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func copyAudio(urls: [URL], to mediaDir: URL) -> ImportCopyResult {
        var result = ImportCopyResult()
        let fm = FileManager.default
        try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                result.errors.append("文件不存在: \(url.lastPathComponent)")
                continue
            }

            if isDirectory.boolValue {
                let folder = uniqueDirectory(mediaDir.appendingPathComponent(url.lastPathComponent, isDirectory: true))
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    guard let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }
                    for case let fileURL as URL in enumerator {
                        guard isAudio(fileURL), !fileURL.path.contains("/.") else { continue }
                        let destination = uniqueFile(folder.appendingPathComponent(fileURL.lastPathComponent))
                        do {
                            try fm.copyItem(at: fileURL, to: destination)
                            result.count += 1
                        } catch {
                            result.errors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                } catch {
                    result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            } else if isAudio(url) {
                let destination = uniqueFile(mediaDir.appendingPathComponent(url.lastPathComponent))
                do {
                    if url.standardizedFileURL == destination.standardizedFileURL {
                        continue
                    }
                    try fm.copyItem(at: url, to: destination)
                    result.count += 1
                } catch {
                    result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return result
    }

    static func copyNCMToInbox(urls: [URL], inbox: URL) -> [URL] {
        let fm = FileManager.default
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        var copied: [URL] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard url.pathExtension.lowercased() == "ncm" else { continue }
            let destination = uniqueFile(inbox.appendingPathComponent(url.lastPathComponent))
            do {
                try fm.copyItem(at: url, to: destination)
                copied.append(destination)
            } catch {
                continue
            }
        }
        return copied
    }

    static func uniqueFile(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent("\(base) (\(index))")
                .appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    static func uniqueDirectory(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.lastPathComponent
        var index = 2
        while true {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(index))", isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
