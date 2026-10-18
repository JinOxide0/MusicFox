import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

@MainActor
@Observable
final class Player {
    var currentTrack: Track?
    var currentRemote: RemoteTrack?
    var isPlaying = false
    var progress: Double = 0
    var duration: Double = 0
    var repeatMode: RepeatMode = .off
    var shuffle = false
    var lyrics: LyricsResult = .empty
    var lyricsLoading = false
    var showNowPlaying = false
    var remoteArtwork: UIImage?

    private(set) var queue: [Track] = []
    private(set) var queueIndex: Int = 0

    @ObservationIgnored private var avPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var lastNowPlayingUpdate: TimeInterval = 0
    @ObservationIgnored private var remoteArtworkTask: Task<Void, Never>?

    init() {
        configureAudioSession()
        configureRemoteCommands()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    var hasCurrent: Bool {
        currentTrack != nil || currentRemote != nil
    }

    var title: String {
        currentTrack?.title ?? currentRemote?.title ?? "未在播放"
    }

    var artist: String {
        currentTrack?.artist ?? currentRemote?.artist ?? ""
    }

    var album: String {
        currentTrack?.album ?? currentRemote?.album ?? ""
    }

    var coverURL: URL? {
        if let currentTrack {
            return currentTrack.coverURL
        }
        if let remote = currentRemote?.coverUrl, let url = URL(string: remote) {
            return url
        }
        return nil
    }

    var durationText: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var progressText: String {
        guard progress.isFinite, progress > 0 else { return "0:00" }
        let total = Int(progress.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var activeLyricIndex: Int? {
        guard lyrics.synced, !lyrics.lines.isEmpty else { return nil }
        var active: Int?
        for (index, line) in lyrics.lines.enumerated() {
            if line.time <= progress + 0.12 {
                active = index
            } else {
                break
            }
        }
        return active
    }

    func play(track: Track, queue: [Track]? = nil) {
        let newQueue = queue ?? [track]
        self.queue = newQueue
        queueIndex = newQueue.firstIndex(where: { $0.id == track.id }) ?? 0
        startTrack(at: queueIndex)
    }

    private func startTrack(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queueIndex = index
        let track = queue[index]
        currentTrack = track
        currentRemote = nil
        remoteArtwork = nil
        let url = track.fileURL ?? URL(fileURLWithPath: track.path)
        startPlayback(url: url, initialDuration: track.duration)
        loadLocalLyrics(for: track)
    }

    func playRemote(track: RemoteTrack, url: URL) {
        currentTrack = nil
        currentRemote = track
        queue = []
        queueIndex = 0
        remoteArtwork = nil
        startPlayback(url: url, initialDuration: track.duration)
        loadRemoteLyrics(for: track)
        loadRemoteArtwork(for: track)
    }

    func toggle() {
        guard avPlayer?.currentItem != nil else { return }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard avPlayer?.currentItem != nil else { return }
        activateAudioSession()
        avPlayer?.play()
        isPlaying = true
        updateNowPlaying(force: true)
    }

    func pause() {
        avPlayer?.pause()
        isPlaying = false
        updateNowPlaying(force: true)
    }

    func seek(to seconds: Double) {
        guard let avPlayer, seconds.isFinite else { return }
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        avPlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        progress = clamped
        updateNowPlaying(force: true)
    }

    func next() {
        if repeatMode == .one, avPlayer?.currentItem != nil {
            seek(to: 0)
            resume()
            return
        }
        guard !queue.isEmpty else {
            if repeatMode == .all {
                seek(to: 0)
                resume()
            } else {
                pause()
            }
            return
        }
        var nextIndex: Int
        if shuffle, queue.count > 1 {
            repeat {
                nextIndex = Int.random(in: 0..<queue.count)
            } while nextIndex == queueIndex
        } else {
            nextIndex = queueIndex + 1
        }
        if nextIndex >= queue.count {
            if repeatMode == .all {
                nextIndex = 0
            } else {
                pause()
                seek(to: duration)
                return
            }
        }
        queueIndex = nextIndex
        startTrack(at: nextIndex)
    }

    func previous() {
        if progress > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else {
            seek(to: 0)
            return
        }
        let previousIndex = queueIndex - 1
        guard previousIndex >= 0 else {
            seek(to: 0)
            return
        }
        queueIndex = previousIndex
        startTrack(at: previousIndex)
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func playPlaylist(_ tracks: [Track], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let safeIndex = max(0, min(index, tracks.count - 1))
        queue = tracks
        // Playing a playlist should preserve its displayed order. Shuffle can
        // still be turned on explicitly afterwards.
        shuffle = false
        startTrack(at: safeIndex)
    }

    func setQueue(_ tracks: [Track], keepCurrent: Bool) {
        guard currentRemote == nil else { return }
        guard keepCurrent, let currentTrack else {
            queue = tracks
            return
        }
        queue = tracks
        queueIndex = tracks.firstIndex(where: { $0.id == currentTrack.id }) ?? 0
    }

    func handleLibraryChange(_ tracks: [Track]) {
        let ids = Set(tracks.map(\.id))
        queue.removeAll { !ids.contains($0.id) }
        if let currentTrack, !ids.contains(currentTrack.id) {
            stop()
        }
    }

    func stop() {
        lyricsTask?.cancel()
        remoteArtworkTask?.cancel()
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentRemote = nil
        queue = []
        queueIndex = 0
        isPlaying = false
        progress = 0
        duration = 0
        lyrics = .empty
        lyricsLoading = false
        remoteArtwork = nil
        showNowPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Playback internals

    private func startPlayback(url: URL, initialDuration: Double) {
        activateAudioSession()
        removeEndObserver()
        let item = AVPlayerItem(url: url)
        if let avPlayer {
            avPlayer.replaceCurrentItem(with: item)
        } else {
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true
            avPlayer = player
            addTimeObserver(to: player)
        }
        duration = initialDuration
        progress = 0
        isPlaying = true
        avPlayer?.play()
        updateNowPlaying(force: true)
        watchEnd(of: item)
    }

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.tick(time)
            }
        }
    }

    private func tick(_ time: CMTime) {
        guard let avPlayer else { return }
        let seconds = time.seconds
        if seconds.isFinite {
            progress = max(0, seconds)
        }
        if let itemDuration = avPlayer.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        let now = Date().timeIntervalSince1970
        if isPlaying, now - lastNowPlayingUpdate > 0.9 {
            lastNowPlayingUpdate = now
            updateNowPlaying(force: false)
        }
    }

    private func watchEnd(of item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackEnd() }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func handlePlaybackEnd() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else if queue.isEmpty {
            isPlaying = false
            progress = duration
            updateNowPlaying(force: true)
        } else {
            next()
        }
    }

    // MARK: - Audio session / remote commands

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            isPlaying = false
            updateNowPlaying(force: true)
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func updateNowPlaying(force: Bool) {
        guard hasCurrent else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let image = currentArtworkImage() {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func currentArtworkImage() -> UIImage? {
        if let currentTrack {
            return ImageCache.shared.localImage(for: currentTrack.coverURL)
        }
        return remoteArtwork
    }

    // MARK: - Lyrics

    func reloadLyrics() {
        if let track = currentTrack {
            loadLocalLyrics(for: track)
        } else if let remote = currentRemote {
            loadRemoteLyrics(for: remote)
        }
    }

    private func loadLocalLyrics(for track: Track) {
        lyricsTask?.cancel()
        lyrics = .empty
        lyricsLoading = true
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                var result: LyricsResult = try await RustCore.shared.callAsync(
                    "lyrics.get",
                    ["trackId": track.id],
                    as: LyricsResult.self
                )
                if result.lines.isEmpty && result.plain.isEmpty {
                    result = try await RustCore.shared.callAsync(
                        "lyrics.fetch",
                        ["trackId": track.id],
                        as: LyricsResult.self
                    )
                }
                guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
                self.lyrics = result
                self.lyricsLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.lyrics = .empty
                self.lyricsLoading = false
            }
        }
    }

    private func loadRemoteLyrics(for track: RemoteTrack) {
        lyricsTask?.cancel()
        lyrics = .empty
        lyricsLoading = true
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result: LyricsResult = try await RustCore.shared.callAsync(
                    "source.lyrics",
                    [
                        "provider": track.source,
                        "id": track.id,
                        "title": track.title,
                        "artist": track.artist,
                        "album": track.album,
                        "cover": track.coverUrl ?? "",
                        "duration": track.duration
                    ],
                    as: LyricsResult.self
                )
                guard !Task.isCancelled, self.currentRemote?.id == track.id else { return }
                self.lyrics = result
                self.lyricsLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.lyrics = .empty
                self.lyricsLoading = false
            }
        }
    }

    private func loadRemoteArtwork(for track: RemoteTrack) {
        remoteArtworkTask?.cancel()
        guard let raw = track.coverUrl, let url = URL(string: raw) else { return }
        remoteArtworkTask = Task { [weak self] in
            let image = await ImageCache.shared.remoteImage(for: url)
            guard !Task.isCancelled, let self, self.currentRemote?.id == track.id else { return }
            self.remoteArtwork = image
            self.updateNowPlaying(force: true)
        }
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func localImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        let key = url.path as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    func remoteImage(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
