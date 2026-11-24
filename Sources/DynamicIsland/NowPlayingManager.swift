import AppKit
import CoreImage
import Foundation
import SwiftUI

@MainActor
public final class NowPlayingManager: ObservableObject {
    public static let shared = NowPlayingManager()

    @Published public private(set) var currentTrack: MediaTrack = .empty
    @Published public private(set) var artworkImage: NSImage? = nil
    @Published public private(set) var accentColor: Color = ArtworkPalette.neutral.overall
    @Published public private(set) var accentTopColor: Color = ArtworkPalette.neutral.top
    @Published public private(set) var accentBottomColor: Color = ArtworkPalette.neutral.bottom
    @Published public private(set) var glowColor: Color = ArtworkPalette.neutral.glow
    @Published public private(set) var isUserScrubbing: Bool = false
    @Published public private(set) var isExpandedTimelineVisible: Bool = false

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
        public let glow: Color

        public static let neutral = ArtworkPalette(
            overall: Color.white.opacity(0.95),
            top: Color.white.opacity(0.98),
            bottom: Color.white.opacity(0.85),
            glow: Color.white.opacity(0.28)
        )
    }

    // MARK: - Private State & Caches

    private var artworkCache: [String: (image: NSImage, palette: ArtworkPalette)] = [:]
    private var spotifyOEmbedArtCache: [String: URL] = [:]
    private var lastDistributedTrack: MediaTrack? = nil
    private var pollTimer: Timer?
    private var positionTicker: Timer?
    private var isUpdating = false
    private var previousTrackSignature: String = ""
    private var failedUpdateCount = 0
    private var lastElapsedSyncDate: Date = Date()

    // MARK: - MediaRemote Private Framework Bindings

    private typealias MRRegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias MRGetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias MRGetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias MRSendCommandFn = @convention(c) (Int32, CFDictionary?) -> UInt8
    private typealias MRSetElapsedFn = @convention(c) (Double) -> Void
    private typealias MRGetClientFn = @convention(c) (DispatchQueue, @escaping (UnsafeMutableRawPointer?) -> Void) -> Void
    private typealias MRClientBundleFn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFString>?

    private var mrHandle: UnsafeMutableRawPointer?
    private var mrGetInfo: MRGetInfoFn?
    private var mrGetIsPlaying: MRGetIsPlayingFn?
    private var mrSendCommand: MRSendCommandFn?
    private var mrSetElapsedTime: MRSetElapsedFn?
    private var mrGetClient: MRGetClientFn?
    private var mrClientBundleID: MRClientBundleFn?

    // MARK: - Pre-compiled AppleScripts

    private lazy var compiledSpotifyScript: NSAppleScript? = {
        let src = """
        tell application "Spotify"
            set pState to player state as string
            set tName to ""
            set tArtist to ""
            set tAlbum to ""
            set tArt to ""
            set tDur to 0
            set tPos to 0
            try
                set tName to name of current track
                set tArtist to artist of current track
                set tAlbum to album of current track
                set tDur to duration of current track
                set tPos to player position
                set tArt to artwork url of current track
            end try
            return {pState, tName, tArtist, tPos, tDur, tArt, tAlbum}
        end tell
        """
        let s = NSAppleScript(source: src)
        s?.compileAndReturnError(nil)
        return s
    }()

    private lazy var compiledMusicScript: NSAppleScript? = {
        let src = """
        tell application "Music"
            set pState to player state as string
            set tName to ""
            set tArtist to ""
            set tAlbum to ""
            set tDur to 0
            set tPos to 0
            try
                set tName to name of current track
                set tArtist to artist of current track
                set tAlbum to album of current track
                set tDur to duration of current track
                set tPos to player position
            end try
            return {pState, tName, tArtist, tPos, tDur, tAlbum}
        end tell
        """
        let s = NSAppleScript(source: src)
        s?.compileAndReturnError(nil)
        return s
    }()

    // MARK: - Init & Observers

    private init() {
        setupMediaRemote()
        setupDistributedObservers()
        setupPowerStateObservers()
        Task {
            await updateNowPlaying()
        }
    }

    private func setupMediaRemote() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else {
            return
        }
        mrHandle = handle

        if let regPtr = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let regFn = unsafeBitCast(regPtr, to: MRRegisterFn.self)
            regFn(DispatchQueue.main)
        }
        if let infoPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            mrGetInfo = unsafeBitCast(infoPtr, to: MRGetInfoFn.self)
        }
        if let playPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            mrGetIsPlaying = unsafeBitCast(playPtr, to: MRGetIsPlayingFn.self)
        }
        if let cmdPtr = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(cmdPtr, to: MRSendCommandFn.self)
        }
        if let seekPtr = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
            mrSetElapsedTime = unsafeBitCast(seekPtr, to: MRSetElapsedFn.self)
        }
        if let clientPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingClient") {
            mrGetClient = unsafeBitCast(clientPtr, to: MRGetClientFn.self)
        }
        if let bundlePtr = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier") {
            mrClientBundleID = unsafeBitCast(bundlePtr, to: MRClientBundleFn.self)
        }

        let nc = NotificationCenter.default
        let mrNotifications = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]
        for noteName in mrNotifications {
            nc.addObserver(
                self,
                selector: #selector(handleMediaRemoteNotification(_:)),
                name: NSNotification.Name(noteName),
                object: nil
            )
        }
    }

    private func setupPowerStateObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopTimers()
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
        center.addObserver(
            self,
            selector: #selector(handleSpotifyDistributedNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self,
            selector: #selector(handleMusicDistributedNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleMediaRemoteNotification(_ note: Notification) {
        Task { @MainActor [weak self] in
            await self?.updateNowPlaying()
        }
    }

    @objc private func handleSpotifyDistributedNotification(_ note: Notification) {
        let info = note.userInfo as? [String: Any] ?? [:]
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.ingestDistributedUserInfo(info, source: .spotify, bundleID: "com.spotify.client")
            await self.updateNowPlaying()
        }
    }

    @objc private func handleMusicDistributedNotification(_ note: Notification) {
        let info = note.userInfo as? [String: Any] ?? [:]
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.ingestDistributedUserInfo(info, source: .appleMusic, bundleID: "com.apple.Music")
            await self.updateNowPlaying()
        }
    }

    private func ingestDistributedUserInfo(_ info: [String: Any], source: MediaSource, bundleID: String) {
        let stateStr = (info["Player State"] as? String ?? "").lowercased()
        if stateStr == "stopped" {
            lastDistributedTrack = nil
            return
        }
        let playing = (stateStr == "playing")
        let name = info["Name"] as? String ?? lastDistributedTrack?.title ?? ""
        guard !name.isEmpty else { return }

        let artist = info["Artist"] as? String ?? lastDistributedTrack?.artist ?? ""
        let album = info["Album"] as? String ?? lastDistributedTrack?.album ?? ""
        let trackURI = info["Track ID"] as? String ?? lastDistributedTrack?.trackURI
        let rawDur = (info["Duration"] as? NSNumber)?.doubleValue ?? lastDistributedTrack?.duration ?? 0
        // Spotify distributed notification Duration is in seconds; Apple Music Total Time is in milliseconds
        let duration = (source == .appleMusic && info["Total Time"] != nil)
            ? ((info["Total Time"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
            : (rawDur > 10_800 ? rawDur / 1000.0 : rawDur)
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? currentTrack.position

        var artURL: URL? = lastDistributedTrack?.artworkURL
        if let uri = trackURI, let cached = spotifyOEmbedArtCache[uri] {
            artURL = cached
        }

        let track = MediaTrack(
            title: name,
            artist: artist,
            album: album,
            artworkURL: artURL,
            trackURI: trackURI,
            bundleIdentifier: bundleID,
            isPlaying: playing,
            duration: duration,
            position: position,
            source: source
        )
        lastDistributedTrack = track

        let wasPlayingChanged = (currentTrack.isPlaying != playing)
        if wasPlayingChanged {
            currentTrack.isPlaying = playing
            lastElapsedSyncDate = Date()
            onPlaybackStateChanged?(playing)
        }
    }

    // MARK: - Adaptive Timers

    public func setExpandedTimelineActive(_ active: Bool) {
        guard isExpandedTimelineVisible != active else { return }
        isExpandedTimelineVisible = active
        if active && currentTrack.isPlaying {
            advanceLocalPlaybackPosition()
            startPositionTickerIfNeeded()
        } else {
            positionTicker?.invalidate()
            positionTicker = nil
        }
    }

    private func startPositionTickerIfNeeded() {
        guard currentTrack.isPlaying, isExpandedTimelineVisible else {
            positionTicker?.invalidate()
            positionTicker = nil
            return
        }
        guard positionTicker == nil else { return }
        lastElapsedSyncDate = Date()
        positionTicker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceLocalPlaybackPosition()
            }
        }
        positionTicker?.tolerance = 0.1
    }

    public func startPolling() {
        pollTimer?.invalidate()
        guard currentTrack.isPlaying || isSpotifyOrMusicRunning else {
            pollTimer = nil
            positionTicker?.invalidate()
            positionTicker = nil
            return
        }

        let interval: TimeInterval = currentTrack.isPlaying ? 6.0 : 12.0
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateNowPlaying()
            }
        }
        pollTimer?.tolerance = 1.5

        startPositionTickerIfNeeded()
    }

    public func stopPolling() {
        stopTimers()
    }

    private func stopTimers() {
        pollTimer?.invalidate()
        pollTimer = nil
        positionTicker?.invalidate()
        positionTicker = nil
    }

    private var isSpotifyOrMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty ||
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    private func advanceLocalPlaybackPosition() {
        guard currentTrack.isPlaying, !isUserScrubbing, currentTrack.duration > 0 else { return }
        let now = Date()
        let delta = now.timeIntervalSince(lastElapsedSyncDate)
        lastElapsedSyncDate = now
        let nextPos = min(currentTrack.position + delta, currentTrack.duration)
        currentTrack.position = nextPos
    }

    // MARK: - Unified Dual-Engine Metadata Refresh

    public func updateNowPlaying() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        var resolvedTrack: MediaTrack? = nil
        var embeddedArt: NSImage? = nil

        let spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty

        // Engine 1: MediaRemote.framework (System-wide Safari / Chrome / Podcasts / Players)
        if let mrResult = await fetchMediaRemoteSnapshot() {
            var track = mrResult.track
            if let cached = lastDistributedTrack, cached.title == track.title {
                if track.artworkURL == nil { track.artworkURL = cached.artworkURL }
                if track.trackURI == nil { track.trackURI = cached.trackURI }
            }
            resolvedTrack = track
            embeddedArt = mrResult.artwork
        }

        // Engine 2: Direct Spotify / Apple Music AppleScript only when MediaRemote lacks metadata or artwork
        let needsSpotifyLookup = spotifyRunning && (resolvedTrack == nil || (resolvedTrack?.source == .spotify && resolvedTrack?.artworkURL == nil && embeddedArt == nil))
        if needsSpotifyLookup {
            if let sp = await fetchSpotifyTrack() {
                if resolvedTrack == nil || resolvedTrack?.source == .spotify || sp.isPlaying {
                    resolvedTrack = sp
                } else if resolvedTrack?.title == sp.title && resolvedTrack?.artworkURL == nil {
                    resolvedTrack?.artworkURL = sp.artworkURL
                }
            } else if resolvedTrack == nil, let cached = lastDistributedTrack, cached.source == .spotify {
                resolvedTrack = cached
            }
        }

        if musicRunning {
            if resolvedTrack == nil {
                if let am = await fetchAppleMusicTrack() {
                    resolvedTrack = am
                    embeddedArt = await fetchAppleMusicArtworkData()
                } else if let cached = lastDistributedTrack, cached.source == .appleMusic {
                    resolvedTrack = cached
                }
            } else if resolvedTrack?.source == .appleMusic && embeddedArt == nil {
                embeddedArt = await fetchAppleMusicArtworkData()
            }
        }

        // If we have a Spotify track URI from notification but still no artwork URL, resolve via Spotify oEmbed
        if var track = resolvedTrack, track.artworkURL == nil, embeddedArt == nil,
           let uri = track.trackURI, uri.hasPrefix("spotify:track:") {
            if let oembedURL = await fetchSpotifyOEmbedArtworkURL(trackURI: uri) {
                track.artworkURL = oembedURL
                resolvedTrack = track
            }
        }

        if let track = resolvedTrack {
            failedUpdateCount = 0
            let newSignature = "\(track.title)::\(track.artist)"
            let wasDifferent = (!previousTrackSignature.isEmpty && newSignature != previousTrackSignature && !track.title.isEmpty)
            let isPlayingChanged = (track.isPlaying != currentTrack.isPlaying)

            let (newArt, palette) = await resolveArtworkAndPalette(
                track: track,
                embeddedArtwork: embeddedArt
            )

            var updatedTrack = track
            if isUserScrubbing && newSignature == previousTrackSignature {
                updatedTrack.position = currentTrack.position
            }

            withAnimation(.easeInOut(duration: 0.28)) {
                self.artworkImage = newArt
                self.accentColor = palette.overall
                self.accentTopColor = palette.top
                self.accentBottomColor = palette.bottom
                self.glowColor = palette.glow
                self.currentTrack = updatedTrack
                self.lastElapsedSyncDate = Date()
            }

            previousTrackSignature = newSignature

            if wasDifferent {
                onTrackChanged?(track)
            }
            if isPlayingChanged {
                onPlaybackStateChanged?(track.isPlaying)
            }

            if track.isPlaying || spotifyRunning || musicRunning {
                startPolling()
            } else {
                stopTimers()
            }
            return
        }

        failedUpdateCount += 1
        if failedUpdateCount >= 2 && currentTrack != .empty {
            withAnimation(.easeInOut(duration: 0.28)) {
                self.currentTrack = .empty
                self.artworkImage = nil
                self.accentColor = ArtworkPalette.neutral.overall
                self.accentTopColor = ArtworkPalette.neutral.top
                self.accentBottomColor = ArtworkPalette.neutral.bottom
                self.glowColor = ArtworkPalette.neutral.glow
            }
            previousTrackSignature = ""
            onPlaybackStateChanged?(false)
            if !spotifyRunning && !musicRunning {
                stopTimers()
            }
        }
    }

    // MARK: - MediaRemote Fetcher

    private func fetchMediaRemoteSnapshot() async -> (track: MediaTrack, artwork: NSImage?)? {
        guard let getInfo = mrGetInfo else { return nil }

        let infoDict: [String: Any] = await withCheckedContinuation { continuation in
            getInfo(DispatchQueue.global(qos: .userInteractive)) { cfDict in
                let dict = (cfDict as NSDictionary?) as? [String: Any] ?? [:]
                continuation.resume(returning: dict)
            }
        }

        guard let title = infoDict["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else {
            return nil
        }

        let artist = infoDict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = infoDict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = (infoDict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
        var elapsed = (infoDict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let rate = (infoDict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0

        let isPlayingFlag: Bool
        if let getPlaying = mrGetIsPlaying {
            isPlayingFlag = await withCheckedContinuation { cont in
                getPlaying(DispatchQueue.global(qos: .userInteractive)) { flag in
                    cont.resume(returning: flag)
                }
            }
        } else {
            isPlayingFlag = rate > 0.0
        }

        if isPlayingFlag, let timestamp = infoDict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
            let extra = max(0, Date().timeIntervalSince(timestamp)) * (rate > 0 ? rate : 1.0)
            elapsed = duration > 0 ? min(elapsed + extra, duration) : elapsed + extra
        }

        var clientBundleID: String? = nil
        if let getClient = mrGetClient, let extractBundle = mrClientBundleID {
            clientBundleID = await withCheckedContinuation { cont in
                getClient(DispatchQueue.global(qos: .userInteractive)) { rawClient in
                    if let rawClient = rawClient,
                       let cfStr = extractBundle(rawClient)?.takeUnretainedValue() {
                        cont.resume(returning: cfStr as String)
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
        }

        let source: MediaSource
        if clientBundleID == "com.spotify.client" {
            source = .spotify
        } else if clientBundleID == "com.apple.Music" {
            source = .appleMusic
        } else {
            source = .system
        }

        var embeddedArt: NSImage? = nil
        if let artData = infoDict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            embeddedArt = NSImage(data: artData)
        }

        let track = MediaTrack(
            title: title,
            artist: artist,
            album: album,
            artworkURL: nil,
            trackURI: nil,
            bundleIdentifier: clientBundleID,
            isPlaying: isPlayingFlag,
            duration: duration,
            position: elapsed,
            source: source
        )
        return (track, embeddedArt)
    }

    // MARK: - Artwork Resolution & Dominant Color Extraction

    private func fetchSpotifyOEmbedArtworkURL(trackURI: String) async -> URL? {
        if let cached = spotifyOEmbedArtCache[trackURI] { return cached }
        let parts = trackURI.split(separator: ":")
        guard parts.count == 3, let oembedURL = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/track/\(parts[2])") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: oembedURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let thumb = json["thumbnail_url"] as? String,
               let url = URL(string: thumb) {
                spotifyOEmbedArtCache[trackURI] = url
                return url
            }
        } catch {
            // Network unavailable or private local track
        }
        return nil
    }

    private func resolveArtworkAndPalette(
        track: MediaTrack,
        embeddedArtwork: NSImage?
    ) async -> (NSImage?, ArtworkPalette) {
        let cacheKey = track.artworkURL?.absoluteString ?? "\(track.title)::\(track.artist)::\(track.album)"
        if let cached = artworkCache[cacheKey] {
            return cached
        }

        if let art = embeddedArtwork {
            let palette = extractPalette(from: art)
            cacheEntry((art, palette), forKey: cacheKey)
            return (art, palette)
        }

        if let url = track.artworkURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    let palette = extractPalette(from: image)
                    cacheEntry((image, palette), forKey: cacheKey)
                    return (image, palette)
                }
            } catch {
                // Fall back gracefully
            }
        }

        return (nil, .neutral)
    }

    private func cacheEntry(_ value: (image: NSImage, palette: ArtworkPalette), forKey key: String) {
        if artworkCache.count > 40 {
            artworkCache.removeAll()
        }
        artworkCache[key] = value
    }

    public func extractPalette(from image: NSImage) -> ArtworkPalette {
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

                if v < 0.16 { continue }
                if v > 0.96 && s < 0.08 { continue }

                let p = Pixel(r: r, g: g, b: b, h: h, s: s, v: v)
                validPixels.append(p)
                if s >= 0.22 && v >= 0.20 {
                    chromaticPixels.append(p)
                }
            }
        }

        let totalValid = Double(validPixels.count)
        let chromaticRatio = totalValid > 0 ? Double(chromaticPixels.count) / totalValid : 0

        if chromaticRatio < 0.18 || chromaticPixels.count < 18 {
            return .neutral
        }

        struct HueBucket {
            var pixels: [Pixel] = []
            var score: Double = 0
        }
        var buckets = [HueBucket](repeating: HueBucket(), count: 16)
        for p in chromaticPixels {
            let bIdx = min(max(Int(p.h * 16.0), 0), 15)
            let weight = pow(p.s, 1.2) * (1.0 - abs(p.v - 0.62) * 0.35)
            buckets[bIdx].pixels.append(p)
            buckets[bIdx].score += weight
        }

        guard let winning = buckets.max(by: { $0.score < $1.score }), !winning.pixels.isEmpty else {
            return .neutral
        }

        let pCount = Double(winning.pixels.count)
        let winR = winning.pixels.reduce(0.0) { $0 + $1.r } / pCount
        let winG = winning.pixels.reduce(0.0) { $0 + $1.g } / pCount
        let winB = winning.pixels.reduce(0.0) { $0 + $1.b } / pCount

        // Convert winning color via NSColor HSB so desaturated/white/B&W artwork stays crisp white,
        // while colorful covers get vivid saturated visualizer bars and a clamped dark ambient glow.
        let nsColor = NSColor(srgbRed: winR, green: winG, blue: winB, alpha: 1.0)
            .usingColorSpace(.sRGB) ?? NSColor(srgbRed: winR, green: winG, blue: winB, alpha: 1.0)
        let hue = nsColor.hueComponent
        let sat = nsColor.saturationComponent
        let bri = nsColor.brightnessComponent

        if sat < 0.18 {
            return .neutral
        }

        let boostedSat = min(max(sat, 0.72), 1.0)
        let boostedBri = min(max(bri, 0.88), 1.0)

        let overallNS = NSColor(hue: hue, saturation: boostedSat, brightness: boostedBri, alpha: 1.0)
        let topNS = NSColor(hue: hue, saturation: boostedSat, brightness: min(boostedBri + 0.06, 1.0), alpha: 1.0)
        let bottomNS = NSColor(hue: hue, saturation: boostedSat, brightness: max(boostedBri * 0.78, 0.68), alpha: 1.0)
        let glowNS = NSColor(hue: hue, saturation: boostedSat, brightness: min(bri, 0.62), alpha: 1.0)

        return ArtworkPalette(
            overall: Color(nsColor: overallNS),
            top: Color(nsColor: topNS),
            bottom: Color(nsColor: bottomNS),
            glow: Color(nsColor: glowNS)
        )
    }

    // MARK: - Spotify AppleScript + OSAScript Fallback

    private func fetchSpotifyTrack() async -> MediaTrack? {
        nonisolated(unsafe) let script = self.compiledSpotifyScript
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                var didScriptSucceed = false
                if let script = script {
                    var error: NSDictionary?
                    let result = script.executeAndReturnError(&error)
                    if error == nil {
                        didScriptSucceed = true
                        if result.numberOfItems >= 5 {
                            let state = result.atIndex(1)?.stringValue ?? ""
                            let title = result.atIndex(2)?.stringValue ?? ""
                            let artist = result.atIndex(3)?.stringValue ?? ""
                            let position = result.atIndex(4)?.doubleValue ?? 0
                            let duration = (result.atIndex(5)?.doubleValue ?? 0) / 1000.0
                            let artString = result.numberOfItems >= 6 ? (result.atIndex(6)?.stringValue ?? "") : ""
                            let album = result.numberOfItems >= 7 ? (result.atIndex(7)?.stringValue ?? "") : ""

                            if !title.isEmpty {
                                continuation.resume(returning: MediaTrack(
                                    title: title,
                                    artist: artist,
                                    album: album,
                                    artworkURL: URL(string: artString),
                                    bundleIdentifier: "com.spotify.client",
                                    isPlaying: state.lowercased() == "playing",
                                    duration: duration,
                                    position: position,
                                    source: .spotify
                                ))
                                return
                            }
                        }
                    }
                }

                // Subprocess OSAScript fallback only if compiled NSAppleScript errored out
                if !didScriptSucceed {
                    let osaSrc = "tell application \"Spotify\" to (player state as string) & \"\t\" & (name of current track) & \"\t\" & (artist of current track) & \"\t\" & (player position) & \"\t\" & (duration of current track) & \"\t\" & (artwork url of current track) & \"\t\" & (album of current track)"
                    if let out = Self.runOsaScriptSync(osaSrc) {
                        let parts = out.components(separatedBy: "\t")
                        if parts.count >= 5, !parts[1].isEmpty {
                            let state = parts[0].lowercased()
                            let pos = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
                            let durMs = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
                            let artURL = parts.count >= 6 ? URL(string: parts[5]) : nil
                            let album = parts.count >= 7 ? parts[6] : ""
                            continuation.resume(returning: MediaTrack(
                                title: parts[1],
                                artist: parts[2],
                                album: album,
                                artworkURL: artURL,
                                bundleIdentifier: "com.spotify.client",
                                isPlaying: state == "playing",
                                duration: durMs / 1000.0,
                                position: pos,
                                source: .spotify
                            ))
                            return
                        }
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Apple Music AppleScript + OSAScript Fallback

    private func fetchAppleMusicTrack() async -> MediaTrack? {
        nonisolated(unsafe) let script = self.compiledMusicScript
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                var didScriptSucceed = false
                if let script = script {
                    var error: NSDictionary?
                    let result = script.executeAndReturnError(&error)
                    if error == nil {
                        didScriptSucceed = true
                        if result.numberOfItems >= 5 {
                            let state = result.atIndex(1)?.stringValue ?? ""
                            let title = result.atIndex(2)?.stringValue ?? ""
                            let artist = result.atIndex(3)?.stringValue ?? ""
                            let position = result.atIndex(4)?.doubleValue ?? 0
                            let duration = result.atIndex(5)?.doubleValue ?? 0
                            let album = result.numberOfItems >= 6 ? (result.atIndex(6)?.stringValue ?? "") : ""

                            if !title.isEmpty {
                                continuation.resume(returning: MediaTrack(
                                    title: title,
                                    artist: artist,
                                    album: album,
                                    artworkURL: nil,
                                    bundleIdentifier: "com.apple.Music",
                                    isPlaying: state.lowercased() == "playing",
                                    duration: duration,
                                    position: position,
                                    source: .appleMusic
                                ))
                                return
                            }
                        }
                    }
                }

                if !didScriptSucceed {
                    let osaSrc = "tell application \"Music\" to (player state as string) & \"\t\" & (name of current track) & \"\t\" & (artist of current track) & \"\t\" & (player position) & \"\t\" & (duration of current track) & \"\t\" & (album of current track)"
                    if let out = Self.runOsaScriptSync(osaSrc) {
                        let parts = out.components(separatedBy: "\t")
                        if parts.count >= 5, !parts[1].isEmpty {
                            let state = parts[0].lowercased()
                            let pos = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0
                            let dur = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
                            let album = parts.count >= 6 ? parts[5] : ""
                            continuation.resume(returning: MediaTrack(
                                title: parts[1],
                                artist: parts[2],
                                album: album,
                                artworkURL: nil,
                                bundleIdentifier: "com.apple.Music",
                                isPlaying: state == "playing",
                                duration: dur,
                                position: pos,
                                source: .appleMusic
                            ))
                            return
                        }
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func fetchAppleMusicArtworkData() async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let src = "tell application \"Music\" to if (count of artworks of current track) > 0 then return raw data of artwork 1 of current track"
                var err: NSDictionary?
                if let desc = NSAppleScript(source: src)?.executeAndReturnError(&err), err == nil {
                    let data = desc.data
                    if !data.isEmpty, let img = NSImage(data: data) {
                        continuation.resume(returning: img)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private nonisolated static func runOsaScriptSync(_ source: String) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Playback Controls & Source Activation

    public func togglePlayPause() {
        _ = mrSendCommand?(2, nil)
        if currentTrack.source == .spotify || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            executeScript("tell application \"Spotify\" to playpause")
        } else if currentTrack.source == .appleMusic || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            executeScript("tell application \"Music\" to playpause")
        }
        currentTrack.isPlaying.toggle()
        lastElapsedSyncDate = Date()
        onPlaybackStateChanged?(currentTrack.isPlaying)
        if currentTrack.isPlaying { startPolling() } else { stopTimers() }
    }

    public func nextTrack() {
        _ = mrSendCommand?(4, nil)
        if currentTrack.source == .spotify || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            executeScript("tell application \"Spotify\" to next track")
        } else if currentTrack.source == .appleMusic || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            executeScript("tell application \"Music\" to next track")
        }
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await updateNowPlaying()
        }
    }

    public func previousTrack() {
        _ = mrSendCommand?(5, nil)
        if currentTrack.source == .spotify || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            executeScript("tell application \"Spotify\" to previous track")
        } else if currentTrack.source == .appleMusic || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            executeScript("tell application \"Music\" to previous track")
        }
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await updateNowPlaying()
        }
    }

    public func beginInteractiveScrub(to seconds: Double) {
        let clamped = max(0, min(seconds, currentTrack.duration))
        isUserScrubbing = true
        currentTrack.position = clamped
        lastElapsedSyncDate = Date()
    }

    public func commitInteractiveScrub(to seconds: Double) {
        let clamped = max(0, min(seconds, currentTrack.duration))
        isUserScrubbing = false
        seek(to: clamped)
    }

    public func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, currentTrack.duration))
        currentTrack.position = clamped
        lastElapsedSyncDate = Date()
        guard !currentTrack.title.isEmpty else { return }
        mrSetElapsedTime?(clamped)
        if currentTrack.source == .spotify || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            executeScript("tell application \"Spotify\" to set player position to \(clamped)")
        } else if currentTrack.source == .appleMusic || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            executeScript("tell application \"Music\" to set player position to \(clamped)")
        }
    }

    public func activateSourceApp() {
        let spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        let fallbackRunning: String? = spotifyRunning ? "com.spotify.client" : (musicRunning ? "com.apple.Music" : nil)

        if let preferredBundle = currentTrack.bundleIdentifier ?? fallbackRunning,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferredBundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        guard currentTrack.source != .system else { return }
        let appName = currentTrack.source == .appleMusic ? "Music" : "Spotify"
        for candidate in ["/Applications/\(appName).app", "/System/Applications/\(appName).app"] {
            let appURL = URL(fileURLWithPath: candidate)
            if FileManager.default.fileExists(atPath: appURL.path) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }

    private func executeScript(_ src: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            if NSAppleScript(source: src)?.executeAndReturnError(&err) == nil || err != nil {
                _ = Self.runOsaScriptSync(src)
            }
        }
    }
}
