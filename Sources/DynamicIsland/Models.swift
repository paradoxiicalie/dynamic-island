import AppKit
import Foundation
import SwiftUI

public enum MediaSource: String, Sendable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
    case system = "System Audio"
    case none = "None"
}

public struct MediaTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var isPlaying: Bool
    public var duration: Double
    public var position: Double
    public var source: MediaSource

    public static let empty = MediaTrack(
        title: "",
        artist: "",
        album: "",
        artworkURL: nil,
        isPlaying: false,
        duration: 0,
        position: 0,
        source: .none
    )
}

public struct BatteryInfo: Equatable, Sendable {
    public var percentage: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isLowPowerMode: Bool
    public var timeRemainingFormatted: String

    public static let empty = BatteryInfo(
        percentage: 100,
        isCharging: false,
        isPluggedIn: true,
        isLowPowerMode: false,
        timeRemainingFormatted: ""
    )
}

public struct SystemAlertInfo: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var iconName: String
    public var iconColor: String // "green", "yellow", "red", "blue", "white"

    public static let empty = SystemAlertInfo(
        title: "",
        subtitle: "",
        iconName: "bell.fill",
        iconColor: "white"
    )
}

public struct FocusInfo: Equatable, Sendable {
    public var name: String
    public var iconName: String
    public var isOn: Bool

    public static let dndOn = FocusInfo(name: "Do Not Disturb", iconName: "moon.fill", isOn: true)
    public static let dndOff = FocusInfo(name: "Do Not Disturb", iconName: "moon.fill", isOn: false)
}

public struct TimerInfo: Equatable, Sendable {
    public var totalSeconds: Int
    public var remainingSeconds: Int
    public var label: String
    public var isPaused: Bool

    public var formattedRemaining: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }
}

public enum IslandPresentationMode: Equatable {
    case idle
    case compactMusic
    case compactTrackChange(MediaTrack)
    case compactBattery
    case compactLowBattery
    case compactVolume
    case compactMute
    case compactAirPods
    case compactUnlock
    case compactLockScreen
    case compactAlert(SystemAlertInfo)
    case compactFocus(FocusInfo)
    case compactTimer(TimerInfo)
    case compactDual(MediaTrack, TimerInfo)
    case compactBrightness(Int)
    case expandedMusic
    case expandedBattery
    case expandedRoutes
    case expandedTimer(TimerInfo)
    case expandedFileShelf
}
