import AppKit
import SwiftUI

@MainActor
public final class IslandWindowController: NSObject {
    public static let shared = IslandWindowController()

    private var panel: NSPanel!
    private var hostingView: NSHostingView<IslandView>!

    @Published public var isPinned: Bool = false
    @Published public var presentationMode: IslandPresentationMode = .idle {
        didSet {
            print("[DynamicIsland] presentationMode -> \(presentationMode)")
            updateWindowFrame(animated: true)
            if isExpanded {
                startMonitoringDismissEvents()
            } else {
                stopMonitoringDismissEvents()
            }
        }
    }

    private var notchWidth: CGFloat = 180
    private var notchHeight: CGFloat = 32
    private var trackingArea: NSTrackingArea?

    private var hoverTimer: Timer?
    private var transientAlertTimer: Timer?
    private var musicPauseGraceTimer: Timer?
    private var clickOutsideMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?

    public var isExpanded: Bool {
        switch presentationMode {
        case .expandedMusic, .expandedBattery, .expandedRoutes, .expandedTimer, .expandedFileShelf:
            return true
        default:
            return isPinned
        }
    }

    private func startMonitoringDismissEvents() {
        stopMonitoringDismissEvents()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isExpanded else { return }
                let mouseLoc = NSEvent.mouseLocation
                if !self.panel.frame.contains(mouseLoc) {
                    self.collapse()
                }
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isExpanded else { return event }
            let mouseLoc = NSEvent.mouseLocation
            if !self.panel.frame.contains(mouseLoc) {
                Task { @MainActor [weak self] in
                    self?.collapse()
                }
            }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor [weak self] in
                    self?.collapse()
                }
            }
            return event
        }
    }

    private func stopMonitoringDismissEvents() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    public func collapse() {
        isPinned = false
        stopMonitoringDismissEvents()
        let isPlaying = NowPlayingManager.shared.currentTrack.isPlaying
        let activeTimer = TimerManager.shared.activeTimer
        if isPlaying && activeTimer != nil {
            presentationMode = .compactDual(NowPlayingManager.shared.currentTrack, activeTimer!)
        } else if let activeTimer = activeTimer {
            presentationMode = .compactTimer(activeTimer)
        } else if isPlaying {
            presentationMode = .compactMusic
        } else {
            presentationMode = .idle
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private override init() {
        super.init()
        setupNotchGeometry()
        setupWindow()
        setupObservers()
    }

    public var targetScreen: NSScreen {
        if let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }
        return NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
    }

    private func setupNotchGeometry() {
        let screen = targetScreen
        let topInset = screen.safeAreaInsets.top
        if topInset > 0 {
            notchHeight = topInset
            if let auxLeft = screen.auxiliaryTopLeftArea, let auxRight = screen.auxiliaryTopRightArea {
                notchWidth = screen.frame.width - (auxLeft.width + auxRight.width)
            } else {
                notchWidth = 180
            }
        } else {
            notchHeight = 32
            notchWidth = 180
        }
    }

    private func setupWindow() {
        let screen = targetScreen
        let initialFrame = calculateFrame(for: .idle, on: screen)

        panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Level set to screenSaverWindow + 5 so it floats above Lock Screen and full-screen spaces
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 5)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.registerForDraggedTypes([.fileURL])

        let binding = Binding<IslandPresentationMode>(
            get: { self.presentationMode },
            set: {
                switch $0 {
                case .expandedMusic, .expandedBattery, .expandedRoutes, .expandedTimer, .expandedFileShelf:
                    self.isPinned = true
                default:
                    self.isPinned = false
                }
                self.presentationMode = $0
            }
        )

        let islandView = IslandView(
            presentationMode: binding,
            notchWidth: notchWidth,
            notchHeight: notchHeight
        )

        hostingView = NSHostingView(rootView: islandView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView?.addSubview(hostingView)
        setupTrackingArea()

        panel.orderFrontRegardless()
    }

    private func setupTrackingArea() {
        if let trackingArea = trackingArea {
            hostingView.removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: hostingView.bounds, options: options, owner: self, userInfo: nil)
        hostingView.addTrackingArea(trackingArea!)
    }

    @objc public func mouseEntered(with event: NSEvent) {
        guard !isPinned && !isExpanded else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isPinned && !self.isExpanded else { return }
                if self.presentationMode == .compactMusic || self.presentationMode == .idle {
                    let hasMusic = NowPlayingManager.shared.currentTrack.isPlaying || !NowPlayingManager.shared.currentTrack.title.isEmpty
                    self.presentationMode = hasMusic ? .expandedMusic : .expandedBattery
                }
            }
        }
    }

    @objc public func mouseExited(with event: NSEvent) {
        guard !isPinned && !isExpanded else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isPinned && !self.isExpanded else { return }
                if self.presentationMode == .expandedMusic || self.presentationMode == .expandedBattery {
                    let isPlaying = NowPlayingManager.shared.currentTrack.isPlaying
                    self.presentationMode = isPlaying ? .compactMusic : .idle
                }
            }
        }
    }

    // MARK: - Autonomous Observers
    private func setupObservers() {
        // Initial state sync on startup
        Task { @MainActor [weak self] in
            await NowPlayingManager.shared.updateNowPlaying()
            if let self = self, NowPlayingManager.shared.currentTrack.isPlaying && self.presentationMode == .idle {
                self.presentationMode = .compactMusic
            }
        }

        // 1. Battery Power State Changed (Plugged in or Unplugged)
        BatteryMonitor.shared.onPluggedInStateChanged = { [weak self] isPlugged in
            Task { @MainActor [weak self] in
                if isPlugged { SoundManager.shared.play("chime") }
                self?.showTransientAlert(mode: .compactBattery, duration: 3.5)
            }
        }

        // 2. Low Battery Warning (20% or 10%)
        BatteryMonitor.shared.onLowBatteryWarning = { [weak self] pct in
            Task { @MainActor [weak self] in
                SoundManager.shared.play("low-battery")
                self?.showTransientAlert(mode: .compactLowBattery, duration: 4.5)
            }
        }

        // 3. System Volume Changed (Automatic notch HUD replacement)
        AudioDeviceMonitor.shared.onVolumeChanged = { [weak self] vol in
            Task { @MainActor [weak self] in
                SoundManager.shared.play("volume")
                self?.showTransientAlert(mode: .compactVolume, duration: 1.6)
            }
        }

        // 4. System Mute Toggled
        AudioDeviceMonitor.shared.onMuteChanged = { [weak self] isMuted in
            Task { @MainActor [weak self] in
                SoundManager.shared.play("volume")
                self?.showTransientAlert(mode: .compactMute, duration: 1.6)
            }
        }

        // 5. Audio Device Connected (AirPods / Headphones)
        AudioDeviceMonitor.shared.onDeviceChanged = { [weak self] name, isHeadphones in
            Task { @MainActor [weak self] in
                if isHeadphones {
                    SoundManager.shared.play("chime")
                    self?.showTransientAlert(mode: .compactAirPods, duration: 3.2)
                }
            }
        }

        // 6. Screen Lock & Unlock Observers (Lock Screen & FaceID / TouchID style animation)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenLocked(_:)),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenUnlocked(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.setupNotchGeometry()
                self?.updateWindowFrame(animated: false)
            }
        }

        // 7. Track Change Auto-Banner (Title/Artist brief slide-in)
        NowPlayingManager.shared.onTrackChanged = { [weak self] track in
            Task { @MainActor [weak self] in
                self?.musicPauseGraceTimer?.invalidate()
                self?.musicPauseGraceTimer = nil
                self?.showTransientAlert(mode: .compactTrackChange(track), duration: 2.8)
            }
        }

        // 7b. Instant Playback State Changed (Zero-latency 0ms reaction)
        NowPlayingManager.shared.onPlaybackStateChanged = { [weak self] isPlaying in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.musicPauseGraceTimer?.invalidate()
                self.musicPauseGraceTimer = nil

                guard self.transientAlertTimer == nil && !self.isPinned && !self.isExpanded && self.presentationMode != .compactLockScreen else { return }

                if isPlaying {
                    let activeTimer = TimerManager.shared.activeTimer
                    if let activeTimer = activeTimer {
                        self.presentationMode = .compactDual(NowPlayingManager.shared.currentTrack, activeTimer)
                    } else {
                        self.presentationMode = .compactMusic
                    }
                } else {
                    // Apple iOS Dynamic Island: keep paused island visible for 5.0 seconds
                    // so user sees paused resting state before graceful collapse to idle!
                    self.musicPauseGraceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            if !NowPlayingManager.shared.currentTrack.isPlaying && !self.isPinned && !self.isExpanded {
                                if let activeTimer = TimerManager.shared.activeTimer {
                                    self.presentationMode = .compactTimer(activeTimer)
                                } else {
                                    self.presentationMode = .idle
                                }
                            }
                        }
                    }
                }
            }
        }

        // 8. Live Timer & Countdown Observer
        TimerManager.shared.onTimerTick = { [weak self] info in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .expandedTimer = self.presentationMode {
                    self.presentationMode = .expandedTimer(info)
                } else if !self.isPinned && !self.isExpanded && self.transientAlertTimer == nil && self.presentationMode != .compactLockScreen {
                    let isPlaying = NowPlayingManager.shared.currentTrack.isPlaying
                    if isPlaying {
                        self.presentationMode = .compactDual(NowPlayingManager.shared.currentTrack, info)
                    } else {
                        self.presentationMode = .compactTimer(info)
                    }
                }
            }
        }

        TimerManager.shared.onTimerEnded = { [weak self] info in
            Task { @MainActor [weak self] in
                SoundManager.shared.play("chime")
                let alert = SystemAlertInfo(title: info.label, subtitle: "Time's up!", iconName: "timer", iconColor: "yellow")
                self?.showTransientAlert(mode: .compactAlert(alert), duration: 4.0)
            }
        }

        // 9. Media Playback Fallback Watchdog (Safe 2.5s interval to conserve CPU/battery)
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard self.transientAlertTimer == nil && self.musicPauseGraceTimer == nil && !self.isPinned && !self.isExpanded && self.presentationMode != .compactLockScreen else { return }

                let isPlaying = NowPlayingManager.shared.currentTrack.isPlaying
                let activeTimer = TimerManager.shared.activeTimer

                if isPlaying && activeTimer != nil {
                    let dual = IslandPresentationMode.compactDual(NowPlayingManager.shared.currentTrack, activeTimer!)
                    if self.presentationMode != dual {
                        self.presentationMode = dual
                    }
                } else if let activeTimer = activeTimer {
                    let timerMode = IslandPresentationMode.compactTimer(activeTimer)
                    if self.presentationMode != timerMode {
                        self.presentationMode = timerMode
                    }
                } else if isPlaying {
                    if self.presentationMode != .compactMusic {
                        self.presentationMode = .compactMusic
                    }
                } else {
                    if self.presentationMode != .idle {
                        self.presentationMode = .idle
                    }
                }
            }
        }
    }

    public func showTransientAlert(mode: IslandPresentationMode, duration: TimeInterval) {
        // Do not interrupt expanded cards unless it's a critical low battery alert
        if (isPinned || isExpanded) && mode != .compactLowBattery {
            return
        }

        transientAlertTimer?.invalidate()
        presentationMode = mode
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        transientAlertTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.transientAlertTimer = nil
                if !self.isPinned && !self.isExpanded {
                    let isPlaying = NowPlayingManager.shared.currentTrack.isPlaying
                    let activeTimer = TimerManager.shared.activeTimer
                    if isPlaying && activeTimer != nil {
                        self.presentationMode = .compactDual(NowPlayingManager.shared.currentTrack, activeTimer!)
                    } else if let activeTimer = activeTimer {
                        self.presentationMode = .compactTimer(activeTimer)
                    } else if isPlaying {
                        self.presentationMode = .compactMusic
                    } else {
                        self.presentationMode = .idle
                    }
                }
            }
        }
    }

    @objc private func handleScreenLocked(_ notification: Notification) {
        Task { @MainActor [weak self] in
            SoundManager.shared.play("lock")
            self?.presentationMode = .compactLockScreen
        }
    }

    @objc private func handleScreenUnlocked(_ notification: Notification) {
        Task { @MainActor [weak self] in
            SoundManager.shared.play("unlock")
            self?.showTransientAlert(mode: .compactUnlock, duration: 2.0)
        }
    }

    public func triggerBatteryAlert() {
        showTransientAlert(mode: .compactBattery, duration: 3.5)
    }

    public func triggerUnlockAlert() {
        showTransientAlert(mode: .compactUnlock, duration: 2.0)
    }

    public func triggerCustomAlert(title: String, subtitle: String, icon: String, color: String = "white", duration: TimeInterval = 3.0) {
        let alert = SystemAlertInfo(title: title, subtitle: subtitle, iconName: icon, iconColor: color)
        showTransientAlert(mode: .compactAlert(alert), duration: duration)
    }

    public func triggerBrightnessAlert(level: Int) {
        SoundManager.shared.play("volume")
        showTransientAlert(mode: .compactBrightness(level), duration: 1.8)
    }

    public func toggleFileShelf() {
        if presentationMode == .expandedFileShelf {
            collapse()
        } else {
            isPinned = true
            presentationMode = .expandedFileShelf
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    public func toggleExpansion() {
        if isExpanded {
            collapse()
        } else {
            isPinned = true
            let hasMusic = NowPlayingManager.shared.currentTrack.isPlaying || !NowPlayingManager.shared.currentTrack.title.isEmpty
            presentationMode = hasMusic ? .expandedMusic : .expandedBattery
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    private func calculateFrame(for mode: IslandPresentationMode, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let originScreenX = screenFrame.origin.x
        let originScreenY = screenFrame.origin.y

        var width: CGFloat
        var height: CGFloat

        switch mode {
        case .idle:
            width = notchWidth
            height = notchHeight
        case .compactMusic:
            width = notchWidth + 92
            height = notchHeight
        case .compactBattery:
            width = notchWidth + 110
            height = notchHeight
        case .compactTrackChange:
            width = notchWidth + 240
            height = notchHeight
        case .compactLowBattery:
            width = notchWidth + 260
            height = notchHeight
        case .compactVolume:
            width = notchWidth + 140
            height = notchHeight
        case .compactMute:
            width = notchWidth + 130
            height = notchHeight
        case .compactAirPods:
            width = notchWidth + 200
            height = notchHeight
        case .compactUnlock:
            width = notchWidth + 180
            height = notchHeight
        case .compactLockScreen:
            width = notchWidth + 80
            height = notchHeight
        case .compactAlert:
            width = notchWidth + 240
            height = notchHeight
        case .compactFocus:
            width = notchWidth + 240
            height = notchHeight
        case .compactTimer:
            width = notchWidth + 130
            height = notchHeight
        case .compactDual:
            width = notchWidth + 170
            height = notchHeight
        case .compactBrightness:
            width = notchWidth + 140
            height = notchHeight
        case .expandedMusic:
            width = 348
            height = 148 + notchHeight
        case .expandedBattery:
            width = 310
            height = 92 + notchHeight
        case .expandedRoutes:
            width = 348
            let count = CGFloat(max(1, AudioDeviceMonitor.shared.availableRoutes.count))
            height = notchHeight + 62 + (count * 44) + ((count - 1) * 6) + 14
        case .expandedTimer:
            width = 348
            height = 112 + notchHeight
        case .expandedFileShelf:
            width = 360
            let itemCount = CGFloat(max(1, FileShelfManager.shared.items.count))
            height = notchHeight + 70 + min(itemCount * 48, 160)
        }

        let originX = originScreenX + (screenFrame.width - width) / 2.0
        let originY = originScreenY + screenFrame.height - height

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func updateWindowFrame(animated: Bool) {
        let screen = targetScreen
        let targetFrame = calculateFrame(for: presentationMode, on: screen)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
        setupTrackingArea()
    }
}
