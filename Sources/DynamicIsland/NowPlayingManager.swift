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
    public var onPlaybackStateChanged: ((Bool) -> Void)?

    public struct ArtworkPalette: Sendable {
        public let overall: Color
        public let top: Color
        public let bottom: Color

        public static let neutral = ArtworkPalette(
            overall: Color(red: 0.44, green: 0.43, blue: 0.48),
            top: Color(red: 0.51, green: 0.50, blue: 0.56),
            bottom: Color(red: 0.38, green: 0.37, blue: 0.41)
        )
    }

    private var artworkCache: [URL: (image: NSImage, palette: ArtworkPalette)] = [:]
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
        setupDistributedObservers()
        setupPowerStateObservers()
        Task {
            await updateNowPlaying()
        }
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
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Apple Music instant state change notification
        center.addObserver(
            self,
            selector: #selector(handleMusicNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleSpotifyNotification(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let info = note.userInfo as? [String: Any],
               let stateStr = info["Player State"] as? String {
                let playing = (stateStr.lowercased() == "playing")
                if self.currentTrack.isPlaying != playing {
                    self.currentTrack.isPlaying = playing
                    self.onPlaybackStateChanged?(playing)
                }
            }
            await self.updateNowPlaying()
        }
    }

    @objc private func handleMusicNotification(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let info = note.userInfo as? [String: Any],
               let stateStr = info["Player State"] as? String {
                let playing = (stateStr.lowercased() == "playing")
                if self.currentTrack.isPlaying != playing {
                    self.currentTrack.isPlaying = playing
                    self.onPlaybackStateChanged?(playing)
                }
            }
            await self.updateNowPlaying()
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
            let isPlayingChanged = (track.isPlaying != currentTrack.isPlaying)

            // 1. Fetch artwork and extract palette BEFORE mutating published state
            let (newArt, palette) = await fetchArtworkAndPalette(from: track.artworkURL)

            // 2. Atomic state mutation on MainActor with smooth transition
            withAnimation(.easeInOut(duration: 0.28)) {
                self.artworkImage = newArt
                self.accentColor = palette.overall
                self.accentTopColor = palette.top
                self.accentBottomColor = palette.bottom
                self.currentTrack = track
            }

            self.previousTrackTitle = track.title

            // 3. Notify track change and playback state immediately
            if wasDifferent && !previousTrackTitle.isEmpty {
                self.onTrackChanged?(track)
            }
            if isPlayingChanged {
                self.onPlaybackStateChanged?(track.isPlaying)
            }

            if track.isPlaying && pollTimer == nil {
                startPolling()
            } else if !track.isPlaying && pollTimer != nil {
                stopPolling()
            }
            return
        }

        if currentTrack != .empty {
            withAnimation(.easeInOut(duration: 0.28)) {
                self.currentTrack = .empty
                self.artworkImage = nil
                self.cachedArtworkURL = nil
                self.accentColor = ArtworkPalette.neutral.overall
                self.accentTopColor = ArtworkPalette.neutral.top
                self.accentBottomColor = ArtworkPalette.neutral.bottom
            }
            self.previousTrackTitle = ""
            self.onPlaybackStateChanged?(false)
            stopPolling()
        }
    }

    private func fetchArtworkAndPalette(from url: URL?) async -> (NSImage?, ArtworkPalette) {
        guard let url = url else {
            return (nil, .neutral)
        }
        if let cached = artworkCache[url] {
            return (cached.image, cached.palette)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = NSImage(data: data) {
                let palette = extractPalette(from: image)
                artworkCache[url] = (image, palette)
                return (image, palette)
            }
        } catch {
            print("Artwork fetch error: \(error.localizedDescription)")
        }
        return (nil, .neutral)
    }

    private func extractPalette(from image: NSImage) -> ArtworkPalette {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .neutral
        }
        let width = 36
        let height = 36
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
            return .neutral
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct Pixel {
            let r: Double
            let g: Double
            let b: Double
            let h: Double
            let s: Double
            let v: Double
        }

        var validPixels: [Pixel] = []
        var chromaticPixels: [Pixel] = []

        for y in 0..<height {
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

                // Apple ignores dark shadows/background and pure white highlights
                if v < 0.18 { continue }
                if v > 0.95 && s < 0.08 { continue }

                let p = Pixel(r: r, g: g, b: b, h: h, s: s, v: v)
                validPixels.append(p)
                if s >= 0.22 && v >= 0.20 {
                    chromaticPixels.append(p)
                }
            }
        }

        let totalValid = Double(validPixels.count)
        let chromaticRatio = totalValid > 0 ? Double(chromaticPixels.count) / totalValid : 0

        // If the artwork is mostly monochrome / silver / low-saturation (e.g. < 20% chromatic)
        if chromaticRatio < 0.20 || chromaticPixels.count < 20 {
            // Authentic Apple Titanium Silver / Slate matching iPhone 15 Pro Dynamic Island
            var avgR: Double = 0.44
            var avgG: Double = 0.43
            var avgB: Double = 0.48
            if !validPixels.isEmpty {
                let rSum = validPixels.reduce(0.0) { $0 + $1.r } / totalValid
                let gSum = validPixels.reduce(0.0) { $0 + $1.g } / totalValid
                let bSum = validPixels.reduce(0.0) { $0 + $1.b } / totalValid
                let maxAvg = max(rSum, max(gSum, bSum), 0.001)
                // Blend 75% pure titanium slate with 25% subtle image tone
                avgR = 0.44 * 0.75 + (rSum / maxAvg * 0.44) * 0.25
                avgG = 0.43 * 0.75 + (gSum / maxAvg * 0.43) * 0.25
                avgB = 0.48 * 0.75 + (bSum / maxAvg * 0.48) * 0.25
            }
            let topColor = Color(red: min(avgR * 1.14 + 0.02, 0.62), green: min(avgG * 1.14 + 0.02, 0.62), blue: min(avgB * 1.14 + 0.02, 0.65))
            let bottomColor = Color(red: avgR * 0.86, green: avgG * 0.86, blue: avgB * 0.86)
            let overallColor = Color(red: avgR, green: avgG, blue: avgB)
            return ArtworkPalette(overall: overallColor, top: topColor, bottom: bottomColor)
        }

        // Chromatic: Bucket into 16 hue sectors
        struct HueBucket {
            var pixels: [Pixel] = []
            var score: Double = 0
        }
        var buckets = [HueBucket](repeating: HueBucket(), count: 16)
        for p in chromaticPixels {
            let bIdx = min(max(Int(p.h * 16.0), 0), 15)
            // Weight by saturation and midtone balance
            let weight = pow(p.s, 1.1) * (1.0 - abs(p.v - 0.6) * 0.4)
            buckets[bIdx].pixels.append(p)
            buckets[bIdx].score += weight
        }

        guard let winning = buckets.max(by: { $0.score < $1.score }), !winning.pixels.isEmpty else {
            return .neutral
        }

        let pCount = Double(winning.pixels.count)
        var winR = winning.pixels.reduce(0.0) { $0 + $1.r } / pCount
        var winG = winning.pixels.reduce(0.0) { $0 + $1.g } / pCount
        var winB = winning.pixels.reduce(0.0) { $0 + $1.b } / pCount

        // Subtle, elegant Apple Dynamic Island luminance (never blinding neon)
        let maxComponent = max(winR, max(winG, winB))
        if maxComponent < 0.44 && maxComponent > 0.001 {
            let scale = min(0.50 / maxComponent, 1.8)
            winR = min(winR * scale, 0.62)
            winG = min(winG * scale, 0.62)
            winB = min(winB * scale, 0.62)
        } else if maxComponent > 0.65 {
            let scale = 0.60 / maxComponent
            winR *= scale
            winG *= scale
            winB *= scale
        }

        // Apple signature vertical gradient with subtle top highlight
        let topColor = Color(
            red: min(winR * 1.14 + 0.02, 0.68),
            green: min(winG * 1.14 + 0.02, 0.68),
            blue: min(winB * 1.14 + 0.02, 0.68)
        )
        let bottomColor = Color(red: winR * 0.86, green: winG * 0.86, blue: winB * 0.86)
        let overallColor = Color(red: winR, green: winG, blue: winB)

        return ArtworkPalette(overall: overallColor, top: topColor, bottom: bottomColor)
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
        onPlaybackStateChanged?(currentTrack.isPlaying)
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
