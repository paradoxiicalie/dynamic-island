import AppKit
import Foundation
import SwiftUI

// MARK: - Media & Playback Models

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
    public var trackURI: String?
    public var bundleIdentifier: String?
    public var isPlaying: Bool
    public var duration: Double
    public var position: Double
    public var source: MediaSource

    public init(
        title: String,
        artist: String,
        album: String,
        artworkURL: URL? = nil,
        trackURI: String? = nil,
        bundleIdentifier: String? = nil,
        isPlaying: Bool,
        duration: Double,
        position: Double,
        source: MediaSource
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.trackURI = trackURI
        self.bundleIdentifier = bundleIdentifier
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.source = source
    }

    public static let empty = MediaTrack(
        title: "",
        artist: "",
        album: "",
        artworkURL: nil,
        trackURI: nil,
        bundleIdentifier: nil,
        isPlaying: false,
        duration: 0,
        position: 0,
        source: .none
    )
}

// MARK: - Power, Focus & System Alert Models

public struct BatteryInfo: Equatable, Sendable {
    public var percentage: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isLowPowerMode: Bool
    public var timeRemainingFormatted: String

    public init(
        percentage: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        isLowPowerMode: Bool,
        timeRemainingFormatted: String
    ) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isLowPowerMode = isLowPowerMode
        self.timeRemainingFormatted = timeRemainingFormatted
    }

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
    public var iconColor: String

    public init(title: String, subtitle: String, iconName: String, iconColor: String) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconColor = iconColor
    }

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

    public init(name: String, iconName: String, isOn: Bool) {
        self.name = name
        self.iconName = iconName
        self.isOn = isOn
    }

    public static let dndOn = FocusInfo(name: "Do Not Disturb", iconName: "moon.fill", isOn: true)
    public static let dndOff = FocusInfo(name: "Do Not Disturb", iconName: "moon.fill", isOn: false)
}

public struct TimerInfo: Equatable, Sendable {
    public var totalSeconds: Int
    public var remainingSeconds: Int
    public var label: String
    public var isPaused: Bool

    public init(totalSeconds: Int, remainingSeconds: Int, label: String, isPaused: Bool) {
        self.totalSeconds = totalSeconds
        self.remainingSeconds = remainingSeconds
        self.label = label
        self.isPaused = isPaused
    }

    public var formattedRemaining: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(Double(totalSeconds - remainingSeconds) / Double(totalSeconds), 0), 1)
    }

    public var remainingFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(totalSeconds), 0), 1)
    }
}

// MARK: - Display Mode

public enum IslandDisplayMode: String, CaseIterable, Sendable {
    case automatic = "auto"
    case notch = "notch"
    case floatingPill = "pill"

    public var localizedTitle: String {
        switch self {
        case .automatic: return "Авто (по экрану)"
        case .notch: return "Аппаратная чёлка"
        case .floatingPill: return "Парящая пилюля (iPhone)"
        }
    }
}

// MARK: - Hardware Screen & Canvas Geometry

public struct ScreenNotchMetrics: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let hasHardwareNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let screenFrame: CGRect

    public init(
        displayID: CGDirectDisplayID = 0,
        hasHardwareNotch: Bool,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        screenFrame: CGRect
    ) {
        self.displayID = displayID
        self.hasHardwareNotch = hasHardwareNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.screenFrame = screenFrame
    }

    @MainActor
    public static func measure(screen: NSScreen) -> ScreenNotchMetrics {
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let safeTop = screen.safeAreaInsets.top
        let menuBarHeight = NSStatusBar.system.thickness
        let hasHardwareNotch = safeTop > 0 || (screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil)
        let width: CGFloat = {
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                return max(180, screen.frame.width - left.width - right.width + 4)
            }
            return hasHardwareNotch ? 186 : 160
        }()
        let height: CGFloat = max(safeTop, menuBarHeight, 34.0)
        return ScreenNotchMetrics(
            displayID: displayID,
            hasHardwareNotch: hasHardwareNotch,
            notchWidth: width,
            notchHeight: height,
            screenFrame: screen.frame
        )
    }

    @MainActor
    public static func measureAll(screens: [NSScreen] = NSScreen.screens) -> [ScreenNotchMetrics] {
        screens.map { measure(screen: $0) }
    }

    public func panelFrame(
        canvasWidth: CGFloat = MetaballSplitState.canvasWidth,
        canvasHeight: CGFloat = MetaballSplitState.canvasHeight
    ) -> CGRect {
        let x = screenFrame.midX - (canvasWidth / 2.0)
        let y = screenFrame.maxY - canvasHeight
        return CGRect(x: x, y: y, width: canvasWidth, height: canvasHeight)
    }
}

// MARK: - Authentic Apple Dynamic Island Springs

public enum IslandSpringKind: Equatable, Sendable {
    case expansion
    case collapse
    case transientPop
    case idleStretch

    public var animation: Animation {
        switch self {
        case .expansion:
            return .spring(response: 0.42, dampingFraction: 0.76, blendDuration: 0.15)
        case .collapse:
            return .spring(response: 0.36, dampingFraction: 0.84, blendDuration: 0.10)
        case .transientPop:
            return .spring(response: 0.38, dampingFraction: 0.68)
        case .idleStretch:
            return .spring(response: 0.32, dampingFraction: 0.65)
        }
    }
}

// MARK: - Priority Queue & Presentation State (100% Context-Driven)

public enum IslandActivityPriority: Int, Comparable, Sendable {
    case background = 0
    case liveActivity = 40
    case transientHUD = 60
    case interactiveExpanded = 70
    case transientHigh = 80
    case critical = 100

    public static func < (lhs: IslandActivityPriority, rhs: IslandActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum IslandPresentationMode: Equatable, Sendable {
    case idle
    case compactMusic
    case compactTrackChange(MediaTrack)
    case compactBattery
    case compactLowBattery
    case compactLowPowerMode(Bool)
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
    case compactDropZone
    case compactShelf(Int)
    case expandedMusic
    case expandedRoutes
    case expandedTimer(TimerInfo)
    case expandedFileShelf

    public var priority: IslandActivityPriority {
        switch self {
        case .idle:
            return .background
        case .compactMusic, .compactTimer, .compactDual, .compactShelf:
            return .liveActivity
        case .compactVolume, .compactMute, .compactBrightness, .compactTrackChange, .compactFocus, .compactDropZone:
            return .transientHUD
        case .expandedMusic, .expandedRoutes, .expandedTimer, .expandedFileShelf:
            return .interactiveExpanded
        case .compactBattery, .compactLowBattery, .compactLowPowerMode, .compactAirPods, .compactUnlock, .compactAlert:
            return .transientHigh
        case .compactLockScreen:
            return .critical
        }
    }

    public var isExpandedMode: Bool {
        switch self {
        case .expandedMusic, .expandedRoutes, .expandedTimer, .expandedFileShelf:
            return true
        default:
            return false
        }
    }

    public var isTransientMode: Bool {
        switch self {
        case .compactTrackChange, .compactBattery, .compactLowBattery, .compactLowPowerMode,
             .compactVolume, .compactMute, .compactAirPods, .compactUnlock,
             .compactAlert, .compactFocus, .compactBrightness:
            return true
        default:
            return false
        }
    }

    public var isPopDownMode: Bool {
        isTransientMode || self == .compactDropZone
    }

    public static func springKind(from old: IslandPresentationMode, to new: IslandPresentationMode) -> IslandSpringKind {
        if !old.isExpandedMode && new.isExpandedMode {
            return .expansion
        }
        if old.isExpandedMode && !new.isExpandedMode {
            return .collapse
        }
        if new.isTransientMode || new == .compactLockScreen || new == .compactDropZone {
            return .transientPop
        }
        if new == .idle {
            return .idleStretch
        }
        return .expansion
    }
}

public struct IslandStateResolver: Sendable {
    public init() {}

    public func canPreempt(
        current: IslandPresentationMode,
        isPinned: Bool,
        candidate: IslandPresentationMode,
        overridePriority: IslandActivityPriority? = nil
    ) -> Bool {
        let candidatePriority = overridePriority ?? candidate.priority
        if current == .compactLockScreen {
            return candidate == .compactUnlock || candidatePriority >= .critical
        }
        if (isPinned || current.isExpandedMode) && candidatePriority < .transientHigh && !candidate.isExpandedMode && candidate != .compactDropZone {
            return false
        }
        if isPinned && current.isExpandedMode && candidate.isTransientMode && candidatePriority < .critical {
            return false
        }
        return candidatePriority >= current.priority || candidate.isExpandedMode
    }

    public func baselineMode(
        isScreenLocked: Bool,
        isPlaying: Bool,
        currentTrack: MediaTrack,
        activeTimer: TimerInfo?,
        shelfItemCount: Int = 0
    ) -> IslandPresentationMode {
        if isScreenLocked {
            return .compactLockScreen
        }
        if isPlaying, let timer = activeTimer {
            return .compactDual(currentTrack, timer)
        }
        if let timer = activeTimer {
            return .compactTimer(timer)
        }
        if isPlaying {
            return .compactMusic
        }
        if shelfItemCount > 0 {
            return .compactShelf(shelfItemCount)
        }
        return .idle
    }
}

// MARK: - Metaball Split Layout & Hit-Testing Geometry

public enum SecondaryBubbleKind: Equatable, Sendable {
    case timer(TimerInfo)
}

public struct MetaballSplitState: Equatable, Sendable {
    public static let canvasWidth: CGFloat = 720
    public static let canvasHeight: CGFloat = 320
    public static let compactWingPaddingTotal: CGFloat = 56
    public static let popDownToastWidth: CGFloat = 260
    public static let popDownToastExtraHeight: CGFloat = 44

    public static func expandedContentTopPadding(notchHeight: CGFloat, isFloatingPill: Bool) -> CGFloat {
        isFloatingPill ? 16 : (notchHeight + 8)
    }

    public let isFloatingPill: Bool
    public let isSplit: Bool
    public let isIdleStretched: Bool
    public let hasActivePrivacyIndicator: Bool
    public let mainSize: CGSize
    public let mainCornerRadius: CGFloat
    public let topEarRadius: CGFloat
    public let topOffset: CGFloat
    public let mainOffsetX: CGFloat
    public let detachedBubbleDiameter: CGFloat
    public let detachedGap: CGFloat
    public let secondaryActivity: SecondaryBubbleKind?

    public init(
        mode: IslandPresentationMode,
        isFloatingPill: Bool,
        isIdleStretched: Bool = false,
        hasActivePrivacyIndicator: Bool = false,
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        routeCount: Int,
        shelfItemCount: Int
    ) {
        self.isFloatingPill = isFloatingPill
        self.isIdleStretched = isIdleStretched
        self.hasActivePrivacyIndicator = hasActivePrivacyIndicator

        let compactHeight: CGFloat = isFloatingPill ? 36 : notchHeight
        let compactEar: CGFloat = isFloatingPill ? 0 : 4
        let popDownEar: CGFloat = isFloatingPill ? 0 : 12
        let expandedEar: CGFloat = isFloatingPill ? 0 : 16
        let compactBottomRadius: CGFloat = min(10, compactHeight / 3.0)
        self.topOffset = isFloatingPill ? 8 : 0

        if case .compactDual(_, let timer) = mode {
            self.isSplit = true
            self.secondaryActivity = .timer(timer)
            self.detachedBubbleDiameter = compactHeight
            self.detachedGap = 6
            let w: CGFloat = isFloatingPill ? 184 : (notchWidth + Self.compactWingPaddingTotal)
            self.mainSize = CGSize(width: w, height: compactHeight)
            self.mainCornerRadius = isFloatingPill ? (compactHeight / 2.0) : compactBottomRadius
            self.topEarRadius = compactEar
            self.mainOffsetX = isFloatingPill ? -(compactHeight + 6) / 2.0 : 0
            return
        }

        self.isSplit = false
        self.secondaryActivity = nil
        self.detachedBubbleDiameter = 0
        self.detachedGap = 0
        self.mainOffsetX = 0

        let popDownWidth = max(Self.popDownToastWidth, notchWidth + 44)
        let popDownHeight = isFloatingPill ? 50 : (notchHeight + Self.popDownToastExtraHeight)
        let popDownRadius: CGFloat = isFloatingPill ? 25 : 20

        switch mode {
        case .idle:
            let stretchW: CGFloat = isIdleStretched ? 18 : 0
            let stretchH: CGFloat = isIdleStretched ? 3 : 0
            if isFloatingPill {
                let privacyW: CGFloat = hasActivePrivacyIndicator ? 18 : 0
                self.mainSize = CGSize(width: 126 + stretchW + privacyW, height: 34 + stretchH)
                self.mainCornerRadius = (34 + stretchH) / 2.0
                self.topEarRadius = 0
            } else {
                let privacyW: CGFloat = hasActivePrivacyIndicator ? 36 : 0
                self.mainSize = CGSize(width: notchWidth + compactEar * 2 + stretchW + privacyW, height: notchHeight + stretchH)
                self.mainCornerRadius = compactBottomRadius
                self.topEarRadius = compactEar
            }

        case .compactMusic, .compactTimer, .compactShelf, .compactLockScreen, .compactDual:
            let w: CGFloat = isFloatingPill ? 184 : (notchWidth + Self.compactWingPaddingTotal)
            self.mainSize = CGSize(width: w, height: compactHeight)
            self.mainCornerRadius = isFloatingPill ? 18 : compactBottomRadius
            self.topEarRadius = compactEar

        case .compactTrackChange, .compactBattery, .compactLowBattery, .compactLowPowerMode,
             .compactVolume, .compactBrightness, .compactMute, .compactAirPods,
             .compactUnlock, .compactAlert, .compactFocus, .compactDropZone:
            self.mainSize = CGSize(width: isFloatingPill ? Self.popDownToastWidth : popDownWidth, height: popDownHeight)
            self.mainCornerRadius = popDownRadius
            self.topEarRadius = popDownEar

        case .expandedMusic:
            let h: CGFloat = isFloatingPill ? 156 : (notchHeight + 132)
            self.mainSize = CGSize(width: 350, height: h)
            self.mainCornerRadius = isFloatingPill ? 36 : 26
            self.topEarRadius = expandedEar

        case .expandedRoutes:
            let visibleCount = CGFloat(min(max(1, routeCount), 4))
            let topPad = Self.expandedContentTopPadding(notchHeight: notchHeight, isFloatingPill: isFloatingPill)
            let h = topPad + 24 + 8 + visibleCount * 46 + max(0, visibleCount - 1) * 6 + 14
            self.mainSize = CGSize(width: 350, height: h)
            self.mainCornerRadius = isFloatingPill ? 36 : 26
            self.topEarRadius = expandedEar

        case .expandedTimer:
            let h: CGFloat = isFloatingPill ? 96 : (notchHeight + 76)
            self.mainSize = CGSize(width: 350, height: h)
            self.mainCornerRadius = isFloatingPill ? 34 : 26
            self.topEarRadius = expandedEar

        case .expandedFileShelf:
            let visibleCount = min(shelfItemCount, 3)
            let bodyHeight: CGFloat = visibleCount == 0 ? 78 : CGFloat(visibleCount) * 54 + 28
            let topPad = Self.expandedContentTopPadding(notchHeight: notchHeight, isFloatingPill: isFloatingPill)
            self.mainSize = CGSize(width: 350, height: topPad + bodyHeight)
            self.mainCornerRadius = isFloatingPill ? 34 : 26
            self.topEarRadius = expandedEar
        }
    }

    public func mainCanvasRect(canvasWidth: CGFloat = MetaballSplitState.canvasWidth) -> CGRect {
        let x = (canvasWidth - mainSize.width) / 2.0 + mainOffsetX
        return CGRect(x: x, y: topOffset, width: mainSize.width, height: mainSize.height)
    }

    public func detachedCanvasRect(canvasWidth: CGFloat = MetaballSplitState.canvasWidth) -> CGRect? {
        guard isSplit, detachedBubbleDiameter > 0 else { return nil }
        let mainRect = mainCanvasRect(canvasWidth: canvasWidth)
        let bubbleX = mainRect.maxX + detachedGap
        let bubbleY = mainRect.midY - detachedBubbleDiameter / 2.0
        return CGRect(x: bubbleX, y: bubbleY, width: detachedBubbleDiameter, height: detachedBubbleDiameter)
    }

    public func hitRects(canvasWidth: CGFloat = MetaballSplitState.canvasWidth) -> [CGRect] {
        var rects = [mainCanvasRect(canvasWidth: canvasWidth)]
        if let detached = detachedCanvasRect(canvasWidth: canvasWidth) {
            rects.append(detached)
        }
        return rects
    }

    public func screenHitRects(inPanelFrame panelFrame: CGRect) -> [CGRect] {
        hitRects(canvasWidth: panelFrame.width).map { canvasRect in
            let screenX = panelFrame.minX + canvasRect.minX
            let screenY = panelFrame.maxY - canvasRect.maxY
            return CGRect(x: screenX, y: screenY, width: canvasRect.width, height: canvasRect.height)
        }
    }
}

// MARK: - Haptic Preferences Helper

@MainActor
public enum HapticEngine {
    private static let key = "com.alexey.dynamicisland.hapticsEnabled"

    public static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    public static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
