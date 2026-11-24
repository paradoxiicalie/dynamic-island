import AVFoundation
import Foundation

public final class SoundManager: @unchecked Sendable {
    public static let shared = SoundManager()

    public static let allSoundNames = [
        "chime",
        "directions",
        "event",
        "haptic",
        "lock",
        "low-battery",
        "low-power",
        "sleep",
        "unlock",
        "volume"
    ]

    private let enabledKey = "com.alexey.dynamicisland.soundsEnabled"
    private let volumeKey = "com.alexey.dynamicisland.soundVolume"

    private var players: [String: AVAudioPlayer] = [:]
    private var lastPlayTimestamps: [String: Date] = [:]
    private let soundQueue = DispatchQueue(label: "com.alexey.dynamicisland.sound", qos: .userInteractive)

    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    public var volume: Float {
        get {
            if UserDefaults.standard.object(forKey: volumeKey) == nil { return 0.85 }
            return min(max(UserDefaults.standard.float(forKey: volumeKey), 0.0), 1.0)
        }
        set {
            let clamped = min(max(newValue, 0.0), 1.0)
            UserDefaults.standard.set(clamped, forKey: volumeKey)
            soundQueue.async { [weak self] in
                self?.players.values.forEach { $0.volume = clamped }
            }
        }
    }

    public func toggleEnabled() -> Bool {
        let next = !isEnabled
        isEnabled = next
        return next
    }

    private init() {
        soundQueue.async { [weak self] in
            self?.preloadAllSounds()
        }
    }

    private func preloadAllSounds() {
        for name in Self.allSoundNames {
            if let player = buildPlayer(named: name) {
                player.volume = volume
                player.prepareToPlay()
                players[name] = player
            }
        }
    }

    private func resolveSoundURL(named name: String) -> URL? {
        // 1. Main app bundle Resources (.app/Contents/Resources/<name>.caf)
        if let url = Bundle.main.url(forResource: name, withExtension: "caf") {
            return url
        }

        // 2. Embedded SwiftPM resource bundle inside .app/Contents/Resources or .app root
        let bundleName = "DynamicIsland_DynamicIsland.bundle"
        if let resourceBundleURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
           let resourceBundle = Bundle(url: resourceBundleURL),
           let url = resourceBundle.url(forResource: name, withExtension: "caf") {
            return url
        }
        if let rootBundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent(bundleName)),
           let url = rootBundle.url(forResource: name, withExtension: "caf") {
            return url
        }

        // 3. System-wide installed application resources
        let installedURL = URL(fileURLWithPath: "/Applications/DynamicIsland.app/Contents/Resources/\(name).caf")
        if FileManager.default.fileExists(atPath: installedURL.path) {
            return installedURL
        }

        // 4. SwiftPM Bundle.module (safe when running via swift run / swift test)
        #if SWIFT_PACKAGE
        let candidatePaths = [
            Bundle.main.bundleURL.appendingPathComponent(bundleName).path,
            FileManager.default.currentDirectoryPath + "/Resources/\(name).caf"
        ]
        if let bundle = Bundle(path: candidatePaths[0]),
           let url = bundle.url(forResource: name, withExtension: "caf") {
            return url
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
           Bundle.main.bundlePath.contains(".build") {
            if let url = Bundle.module.url(forResource: name, withExtension: "caf") {
                return url
            }
        }
        #endif

        // 5. Local repository Resources fallback
        let localSource = URL(fileURLWithPath: "/Users/alexeytikunov/.gemini/antigravity/scratch/dynamic-island-clone/Resources/\(name).caf")
        if FileManager.default.fileExists(atPath: localSource.path) {
            return localSource
        }

        return nil
    }

    private func buildPlayer(named name: String) -> AVAudioPlayer? {
        guard let url = resolveSoundURL(named: name) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    public func play(_ name: String) {
        playThrottled(name, minInterval: 0)
    }

    public func playThrottled(_ name: String, minInterval: TimeInterval = 0.08) {
        guard isEnabled else { return }
        soundQueue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            if minInterval > 0, let last = self.lastPlayTimestamps[name], now.timeIntervalSince(last) < minInterval {
                return
            }
            self.lastPlayTimestamps[name] = now

            let player = self.players[name] ?? self.buildPlayer(named: name)
            guard let activePlayer = player else { return }
            self.players[name] = activePlayer
            activePlayer.volume = self.volume
            activePlayer.currentTime = 0
            activePlayer.play()
        }
    }

    /// Returns count of sound assets successfully resolved/preloaded (useful for diagnostics & tests).
    public func preloadedSoundCount() -> Int {
        soundQueue.sync {
            if players.isEmpty { preloadAllSounds() }
            return players.count
        }
    }
}
