import AppKit
import Foundation
import SwiftUI

@MainActor
public final class NowPlayingManager: ObservableObject {
    public static let shared = NowPlayingManager()

    @Published public private(set) var currentTrack: MediaTrack = .empty
    @Published public private(set) var artworkImage: NSImage? = nil
    @Published public private(set) var accentColor: Color = Color(white: 0.9)
    @Published public private(set) var accentTopColor: Color = Color(white: 0.95)
    @Published public private(set) var accentBottomColor: Color = Color(white: 0.75)

    public var waveformGradient: LinearGradient {
        LinearGradient(
            colors: [accentTopColor, accentBottomColor],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public var onTrackChanged: ((MediaTrack) -> Void)?

    private var pollTimer: Timer?
    private var isUpdating = false
    private var cachedArtworkURL: URL?
    private var previousTrackTitle: String = ""

    private lazy var compiledSpotifyScript: NSAppleScript? = {
        let scriptSource = """
        if application "Spotify" is running then
            tell application "Spotify"
                return {player state as string, name of current track, artist of current track, player position, duration of current track, artwork url of current track, album of current track}
            end tell
        end if
        """
        let s = NSAppleScript(source: scriptSource)
        s?.compileAndReturnError(nil)
        return s
    }()

    private lazy var compiledMusicScript: NSAppleScript? = {
        let scriptSource = """
        if application "Music" is running then
            tell application "Music"
                return {player state as string, name of current track, artist of current track, player position, duration of current track, album of current track}
            end tell
        end if
        """
        let s = NSAppleScript(source: scriptSource)
        s?.compileAndReturnError(nil)
        return s
    }()

    private init() {
        startPolling()
        setupDistributedObservers()
        setupPowerStateObservers()
    }

    private func setupPowerStateObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopPolling()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateNowPlaying()
            }
        }
    }

    private func setupDistributedObservers() {
        let center = DistributedNotificationCenter.default()

        // Spotify instant state change notification
        center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateNowPlaying()
            }
        }

        // Apple Music instant state change notification
        center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateNowPlaying()
            }
        }
    }

    public func startPolling() {
        pollTimer?.invalidate()
        // Adaptive polling: only poll while track is playing to conserve 100% battery
        guard currentTrack.isPlaying else {
            pollTimer = nil
            return
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateNowPlaying()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func updateNowPlaying() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        var newTrack: MediaTrack? = nil
        if let track = await fetchSpotifyTrack() {
            newTrack = track
        } else if let track = await fetchAppleMusicTrack() {
            newTrack = track
        }

        if let track = newTrack {
            let wasDifferent = (track.title != previousTrackTitle && !track.title.isEmpty)
            self.currentTrack = track
            await updateArtwork(from: track.artworkURL)
            if wasDifferent && !previousTrackTitle.isEmpty {
                self.onTrackChanged?(track)
            }
            self.previousTrackTitle = track.title
            if track.isPlaying && pollTimer == nil {
                startPolling()
            } else if !track.isPlaying && pollTimer != nil {
                stopPolling()
            }
            return
        }

        if currentTrack != .empty {
            self.currentTrack = .empty
            self.artworkImage = nil
            self.cachedArtworkURL = nil
            self.accentColor = Color(white: 0.9)
            self.accentTopColor = Color(white: 0.95)
            self.accentBottomColor = Color(white: 0.75)
            self.previousTrackTitle = ""
            stopPolling()
        }
    }

    private func updateArtwork(from url: URL?) async {
        guard let url = url else {
            self.artworkImage = nil
            self.cachedArtworkURL = nil
            self.accentColor = Color(white: 0.9)
            self.accentTopColor = Color(white: 0.95)
            self.accentBottomColor = Color(white: 0.75)
            return
        }
        if url == cachedArtworkURL && artworkImage != nil {
            return
        }
        cachedArtworkURL = url

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                self.artworkImage = image
                let palette = extractPalette(from: image)
                self.accentColor = palette.overall
                self.accentTopColor = palette.top
                self.accentBottomColor = palette.bottom
            }
        } catch {
            print("Artwork fetch failed: \(error.localizedDescription)")
        }
    }

    private func extractPalette(from image: NSImage) -> (overall: Color, top: Color, bottom: Color) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (Color(white: 0.9), Color(white: 0.95), Color(white: 0.75))
        }
        let width = 32
        let height = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (Color(white: 0.9), Color(white: 0.95), Color(white: 0.75))
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func scoreZone(yStart: Int, yEnd: Int) -> (r: Double, g: Double, b: Double)? {
            struct ColorBucket {
                var score: Double = 0
                var rSum: Double = 0
                var gSum: Double = 0
                var bSum: Double = 0
                var count: Int = 0
            }
            var buckets: [Int: ColorBucket] = [:]

            for y in yStart..<yEnd {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let r = Double(rawData[offset]) / 255.0
                    let g = Double(rawData[offset + 1]) / 255.0
                    let b = Double(rawData[offset + 2]) / 255.0

                    let maxC = max(r, max(g, b))
                    let minC = min(r, min(g, b))
                    let delta = maxC - minC
                    let v = maxC
                    let s = maxC == 0 ? 0 : delta / maxC
                    var h: Double = 0
                    if delta > 0.0001 {
                        if maxC == r {
                            h = (g - b) / delta
                            if h < 0 { h += 6.0 }
                        } else if maxC == g {
                            h = 2.0 + (b - r) / delta
                        } else {
                            h = 4.0 + (r - g) / delta
                        }
                        h /= 6.0
                    }

                    if v < 0.10 || (v > 0.95 && s < 0.10) { continue }

                    let bucketIdx = s < 0.10 ? -1 : (Int(h * 16.0) % 16)
                    var score = pow(s, 1.15) * (1.0 - abs(v - 0.55) * 0.7)
                    if (h >= 0.04 && h <= 0.14) && s >= 0.10 { score *= 1.35 }
                    if bucketIdx == -1 && (v >= 0.40 && v <= 0.85) { score = 0.22 }

                    var bucket = buckets[bucketIdx] ?? ColorBucket()
                    bucket.score += score
                    bucket.rSum += r
                    bucket.gSum += g
                    bucket.bSum += b
                    bucket.count += 1
                    buckets[bucketIdx] = bucket
                }
            }

            guard let winning = buckets.values.max(by: { $0.score < $1.score }), winning.count > 0 else {
                return nil
            }
            var avgR = winning.rSum / Double(winning.count)
            var avgG = winning.gSum / Double(winning.count)
            var avgB = winning.bSum / Double(winning.count)
            let curMax = max(avgR, max(avgG, avgB))
            if curMax > 0.001 && curMax < 0.65 {
                let scale = min(0.72 / curMax, 1.8)
                avgR = min(avgR * scale, 1.0)
                avgG = min(avgG * scale, 1.0)
                avgB = min(avgB * scale, 1.0)
            }
            return (avgR, avgG, avgB)
        }

        let overallRGB = scoreZone(yStart: 0, yEnd: height) ?? (0.9, 0.9, 0.9)
        // CGContext standard coords: y=0..16 is bottom half, y=16..32 is top half!
        let bottomRGB = scoreZone(yStart: 0, yEnd: 16) ?? overallRGB
        let topRGB = scoreZone(yStart: 16, yEnd: 32) ?? overallRGB

        // Ensure vertical gradient with authentic luminance highlight on top
        let topColor = Color(
            red: min(topRGB.r * 1.18 + 0.04, 1.0),
            green: min(topRGB.g * 1.18 + 0.04, 1.0),
            blue: min(topRGB.b * 1.18 + 0.04, 1.0)
        )
        let bottomColor = Color(red: bottomRGB.r, green: bottomRGB.g, blue: bottomRGB.b)
        let overallColor = Color(red: overallRGB.r, green: overallRGB.g, blue: overallRGB.b)

        return (overallColor, topColor, bottomColor)
    }

    // MARK: - Spotify Fetcher
    private func fetchSpotifyTrack() async -> MediaTrack? {
        nonisolated(unsafe) let script = self.compiledSpotifyScript
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                guard let script = script else {
                    continuation.resume(returning: nil)
                    return
                }

                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                guard error == nil, result.numberOfItems >= 5 else {
                    continuation.resume(returning: nil)
                    return
                }

                let state = result.atIndex(1)?.stringValue ?? ""
                let title = result.atIndex(2)?.stringValue ?? ""
                let artist = result.atIndex(3)?.stringValue ?? ""
                let position = result.atIndex(4)?.doubleValue ?? 0
                var duration = (result.atIndex(5)?.doubleValue ?? 0)
                if duration > 1000.0 { duration /= 1000.0 }
                let artworkString = result.numberOfItems >= 6 ? (result.atIndex(6)?.stringValue ?? "") : ""
                let album = result.numberOfItems >= 7 ? (result.atIndex(7)?.stringValue ?? "") : ""
                let artURL = URL(string: artworkString)

                let isPlaying = (state.lowercased() == "playing")

                if !title.isEmpty {
                    let track = MediaTrack(
                        title: title,
                        artist: artist,
                        album: album,
                        artworkURL: artURL,
                        isPlaying: isPlaying,
                        duration: duration,
                        position: position,
                        source: .spotify
                    )
                    continuation.resume(returning: track)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Apple Music Fetcher
    private func fetchAppleMusicTrack() async -> MediaTrack? {
        nonisolated(unsafe) let script = self.compiledMusicScript
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                guard let script = script else {
                    continuation.resume(returning: nil)
                    return
                }

                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                guard error == nil, result.numberOfItems >= 5 else {
                    continuation.resume(returning: nil)
                    return
                }

                let state = result.atIndex(1)?.stringValue ?? ""
                let title = result.atIndex(2)?.stringValue ?? ""
                let artist = result.atIndex(3)?.stringValue ?? ""
                let position = result.atIndex(4)?.doubleValue ?? 0
                let duration = result.atIndex(5)?.doubleValue ?? 0
                let album = result.numberOfItems >= 6 ? (result.atIndex(6)?.stringValue ?? "") : ""

                let isPlaying = (state.lowercased() == "playing")

                if !title.isEmpty {
                    let track = MediaTrack(
                        title: title,
                        artist: artist,
                        album: album,
                        artworkURL: nil,
                        isPlaying: isPlaying,
                        duration: duration,
                        position: position,
                        source: .appleMusic
                    )
                    continuation.resume(returning: track)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Playback Controls
    public func togglePlayPause() {
        let appName = currentTrack.source == .appleMusic ? "Music" : "Spotify"
        executeScript("tell application \"\(appName)\" to playpause")
        currentTrack.isPlaying.toggle()
    }

    public func nextTrack() {
        let appName = currentTrack.source == .appleMusic ? "Music" : "Spotify"
        executeScript("tell application \"\(appName)\" to next track")
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await updateNowPlaying()
        }
    }

    public func previousTrack() {
        let appName = currentTrack.source == .appleMusic ? "Music" : "Spotify"
        executeScript("tell application \"\(appName)\" to previous track")
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await updateNowPlaying()
        }
    }

    public func seek(to seconds: Double) {
        let appName = currentTrack.source == .appleMusic ? "Music" : "Spotify"
        executeScript("tell application \"\(appName)\" to set player position to \(seconds)")
        currentTrack.position = seconds
    }

    private func executeScript(_ src: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&err)
        }
    }
}
