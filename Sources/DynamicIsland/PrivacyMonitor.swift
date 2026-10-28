import Foundation
import CoreAudio
import AVFoundation

@MainActor
public final class PrivacyMonitor: ObservableObject {
    public static let shared = PrivacyMonitor()

    @Published public private(set) var isMicActive: Bool = false
    @Published public private(set) var isCameraActive: Bool = false

    public var onPrivacyStateChanged: ((Bool, Bool) -> Void)?

    private init() {}

    public func setMicActive(_ active: Bool) {
        guard isMicActive != active else { return }
        isMicActive = active
        onPrivacyStateChanged?(isMicActive, isCameraActive)
    }

    public func setCameraActive(_ active: Bool) {
        guard isCameraActive != active else { return }
        isCameraActive = active
        onPrivacyStateChanged?(isMicActive, isCameraActive)
    }

    public var isAnyActive: Bool {
        isMicActive || isCameraActive
    }
}
