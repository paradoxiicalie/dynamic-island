import AppKit
import Foundation

public final class SoundManager: @unchecked Sendable {
    public static let shared = SoundManager()

    private var soundCache: [String: NSSound] = [:]
    private let soundQueue = DispatchQueue(label: "com.alexey.dynamicisland.sound", qos: .userInteractive)

    private init() {
        preload(named: "chime")
        preload(named: "unlock")
        preload(named: "lock")
        preload(named: "low-battery")
        preload(named: "volume")
    }

    private func preload(named name: String) {
        if let sound = findSound(named: name) {
            soundCache[name] = sound
        }
    }

    private func findSound(named name: String) -> NSSound? {
        if let path = Bundle.main.path(forResource: name, ofType: "caf") {
            return NSSound(contentsOfFile: path, byReference: true)
        }
        let fallbackPath = "/Applications/DynamicIsland.app/Contents/Resources/\(name).caf"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            return NSSound(contentsOfFile: fallbackPath, byReference: true)
        }
        let sourcePath = "/Users/alexeytikunov/.gemini/antigravity/scratch/dynamic-island-clone/Resources/\(name).caf"
        if FileManager.default.fileExists(atPath: sourcePath) {
            return NSSound(contentsOfFile: sourcePath, byReference: true)
        }
        return nil
    }

    public func play(_ name: String) {
        soundQueue.async { [weak self] in
            guard let self = self else { return }
            let sound = self.soundCache[name] ?? self.findSound(named: name)
            sound?.stop()
            sound?.play()
        }
    }
}
