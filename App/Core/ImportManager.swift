import Foundation

struct ImportCopyResult {
    var count: Int = 0
    var skipped: Int = 0
    var errors: [String] = []
}

enum ImportManager {
    static let audioExtensions: Set<String> = [
        "flac", "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "alac", "mp4"
    ]

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func copyAudio(
        urls: [URL],
        to mediaDir: URL,
        skipDuplicates: Bool
    ) -> ImportCopyResult {
        var result = ImportCopyResult()
        let fm = FileManager.default
        try? fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        var existing: Set<String> = skipDuplicates ? existingFingerprints(in: mediaDir) : []

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
                        if skipDuplicates, existing.contains(fingerprint(for: fileURL)) {
                            result.skipped += 1
                            continue
                        }
                        let destination = uniqueFile(folder.appendingPathComponent(fileURL.lastPathComponent))
                        do {
                            try fm.copyItem(at: fileURL, to: destination)
                            existing.insert(fingerprint(for: destination))
                            result.count += 1
                        } catch {
                            result.errors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                } catch {
                    result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            } else if isAudio(url) {
                if skipDuplicates, existing.contains(fingerprint(for: url)) {
                    result.skipped += 1
                    continue
                }
                let destination = uniqueFile(mediaDir.appendingPathComponent(url.lastPathComponent))
                do {
                    if url.standardizedFileURL == destination.standardizedFileURL {
                        continue
                    }
                    try fm.copyItem(at: url, to: destination)
                    existing.insert(fingerprint(for: destination))
                    result.count += 1
                } catch {
                    result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        return result
    }

    private static func fingerprint(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return "\(url.lastPathComponent.lowercased())|\(size)"
    }

    private static func existingFingerprints(in directory: URL) -> Set<String> {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result = Set<String>()
        for case let url as URL in enumerator {
            guard isAudio(url) else { continue }
            result.insert(fingerprint(for: url))
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
