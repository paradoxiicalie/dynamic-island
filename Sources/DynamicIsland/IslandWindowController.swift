import AppKit
import SwiftUI

// MARK: - Custom Unconstrained NSPanel Subclass

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // CRITICAL: Prevent AppKit from clamping window below Menu Bar / Hardware Notch (visibleFrame.maxY).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

@MainActor
public final class IslandWindowController: NSObject, ObservableObject {
    public static let shared = IslandWindowController()

    private struct ScreenPanelEntry {
        let displayID: CGDirectDisplayID
        let panel: IslandPanel
        let hostingView: NSHostingView<IslandView>
        var metrics: ScreenNotchMetrics
        var cachedFrame: NSRect
    }

    private var screenPanels: [CGDirectDisplayID: ScreenPanelEntry] = [:]
    private var panel: IslandPanel!
    private var hostingView: NSHostingView<IslandView>!
    private let stateResolver = IslandStateResolver()

    public var activePanelCount: Int { screenPanels.count }
    public var activeScreenMetrics: [ScreenNotchMetrics] { screenPanels.values.map(\.metrics) }

    // MARK: - Published Reactive State

    @Published public var isPinned: Bool = false
    @Published public var isHovered: Bool = false
    @Published public var isIdlePressedBounce: Bool = false
    @Published public private(set) var isDropHovered: Bool = false
    @Published public private(set) var notchWidth: CGFloat = 186
    @Published public private(set) var notchHeight: CGFloat = 34
    @Published public private(set) var screenHasPhysicalNotch: Bool = false

    @Published public var displayMode: IslandDisplayMode = {
        if let raw = UserDefaults.standard.string(forKey: "com.alexey.dynamicisland.displayMode"),
           let mode = IslandDisplayMode(rawValue: raw) {
            return mode
        }
        return .automatic
    }() {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "com.alexey.dynamicisland.displayMode")
            updateCanvasPosition()
        }
    }

    @Published public var hoverToExpand: Bool = UserDefaults.standard.bool(forKey: "com.alexey.dynamicisland.hoverToExpand") {
        didSet {
            UserDefaults.standard.set(hoverToExpand, forKey: "com.alexey.dynamicisland.hoverToExpand")
        }
    }

    @Published public var presentationMode: IslandPresentationMode = .idle {
        didSet {
            if oldValue != presentationMode {
                lastTransitionSpring = IslandPresentationMode.springKind(from: oldValue, to: presentationMode)
                NowPlayingManager.shared.setExpandedTimelineActive(presentationMode == .expandedMusic)
                if presentationMode.isExpandedMode {
                    if !oldValue.isExpandedMode {
                        didCursorEnterWhileExpanded = isPointInsideIsland(NSEvent.mouseLocation, padding: 8)
                    }
                    startMonitoringDismissEvents()
                } else {
                    didCursorEnterWhileExpanded = false
                    mouseExitCollapseTimer?.invalidate()
                    mouseExitCollapseTimer = nil
                    stopMonitoringDismissEvents()
                }
                updateHitTesting(mouseLocation: NSEvent.mouseLocation)
            }
        }
    }

    @Published public private(set) var lastTransitionSpring: IslandSpringKind = .idleStretch

    public var isFloatingPill: Bool {
        isFloatingPill(for: nil)
    }

    public func isFloatingPill(for metrics: ScreenNotchMetrics?) -> Bool {
        switch displayMode {
        case .automatic:
            if let metrics = metrics {
                return !metrics.hasHardwareNotch
            }
            return !screenHasPhysicalNotch
        case .notch:
            return false
        case .floatingPill:
            return true
        }
    }

    public var isExpanded: Bool {
        presentationMode.isExpandedMode || isPinned
    }

    public var isIdleStretched: Bool {
        presentationMode == .idle && (isHovered || isIdlePressedBounce)
    }

    public var metaballState: MetaballSplitState {
        metaballState(for: nil)
    }

    public func metaballState(for metrics: ScreenNotchMetrics?) -> MetaballSplitState {
        MetaballSplitState(
            mode: presentationMode,
            isFloatingPill: isFloatingPill(for: metrics),
            isIdleStretched: isIdleStretched,
            hasActivePrivacyIndicator: PrivacyMonitor.shared.isAnyActive,
            notchWidth: metrics?.notchWidth ?? notchWidth,
            notchHeight: metrics?.notchHeight ?? notchHeight,
            routeCount: AudioDeviceMonitor.shared.availableRoutes.count,
            shelfItemCount: FileShelfManager.shared.items.count
        )
    }

    // MARK: - Private Monitors & Timers

    private var isScreenLocked: Bool = false
    private var isContextMenuOpen: Bool = false
    private var didCursorEnterWhileExpanded: Bool = false
    private var cachedPanelFrame: NSRect = .zero
    private var hoverTimer: Timer?
    private var mouseExitCollapseTimer: Timer?
    private var idleBounceTimer: Timer?
    private var transientAlertTimer: Timer?
    private var musicPauseGraceTimer: Timer?
    private var dragWatchTimer: Timer?
    private var reconcileTimer: Timer?

    private var clickOutsideMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var localRightClickMonitor: Any?
    private var lastScrollTriggerDate: Date = .distantPast
    private var lastDragChangeCount: Int = -1

    // MARK: - Lifecycle & Init

    private override init() {
        super.init()
        setupNotchGeometry()
        setupWindow()
        setupInteractionMonitors()
        setupObservers()
    }

    public var targetScreen: NSScreen {
        if displayMode != .floatingPill,
           let notchScreen = NSScreen.screens.first(where: {
               $0.safeAreaInsets.top > 0 || ($0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil)
           }) {
            return notchScreen
        }
        let mouseLoc = NSEvent.mouseLocation
        if let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) }) {
            return activeScreen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func setupNotchGeometry() {
        let metrics = ScreenNotchMetrics.measure(screen: targetScreen)
        screenHasPhysicalNotch = metrics.hasHardwareNotch
        notchWidth = metrics.notchWidth
        notchHeight = metrics.notchHeight
    }

    private func staticCanvasFrame(on screen: NSScreen) -> NSRect {
        return ScreenNotchMetrics.measure(screen: screen).panelFrame()
    }

    private func setupWindow() {
        syncScreenPanels()
        updateHitTesting(mouseLocation: NSEvent.mouseLocation)
    }

    public func syncScreenPanels() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let aboveMenuBar = Int(CGWindowLevelForKey(.mainMenuWindow)) + 3
        let aboveLockScreen = Int(CGWindowLevelForKey(.screenSaverWindow)) + 5
        let panelLevel = NSWindow.Level(rawValue: max(aboveMenuBar, aboveLockScreen))

        var activeIDs = Set<CGDirectDisplayID>()
        let primaryTarget = targetScreen

        for (idx, screen) in screens.enumerated() {
            let measured = ScreenNotchMetrics.measure(screen: screen)
            let key: CGDirectDisplayID = measured.displayID != 0 ? measured.displayID : CGDirectDisplayID(idx + 1)
            let metrics = ScreenNotchMetrics(
                displayID: key,
                hasHardwareNotch: measured.hasHardwareNotch,
                notchWidth: measured.notchWidth,
                notchHeight: measured.notchHeight,
                screenFrame: measured.screenFrame
            )
            activeIDs.insert(key)
            let canvasFrame = metrics.panelFrame()

            if var existing = screenPanels[key] {
                if existing.panel.frame != canvasFrame {
                    existing.panel.setFrame(canvasFrame, display: true)
                }
                existing.metrics = metrics
                existing.cachedFrame = existing.panel.frame
                if existing.hostingView.rootView.screenMetrics != metrics {
                    existing.hostingView.rootView = IslandView(controller: self, screenMetrics: metrics)
                }
                existing.panel.level = panelLevel
                existing.panel.orderFrontRegardless()
                screenPanels[key] = existing
            } else {
                let newPanel = IslandPanel(
                    contentRect: canvasFrame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                newPanel.level = panelLevel
                newPanel.hidesOnDeactivate = false
                newPanel.worksWhenModal = true
                newPanel.animationBehavior = .none
                newPanel.backgroundColor = .clear
                newPanel.isOpaque = false
                newPanel.hasShadow = false
                newPanel.ignoresMouseEvents = true
                newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                newPanel.registerForDraggedTypes([.fileURL, .png, .tiff, .string])

                let islandView = IslandView(controller: self, screenMetrics: metrics)
                let newHosting = NSHostingView(rootView: islandView)
                newHosting.safeAreaRegions = []
                newHosting.frame = newPanel.contentView?.bounds ?? .zero
                newHosting.autoresizingMask = [.width, .height]

                newPanel.contentView?.addSubview(newHosting)
                newPanel.setFrame(canvasFrame, display: true)
                newPanel.orderFrontRegardless()

                screenPanels[key] = ScreenPanelEntry(
                    displayID: key,
                    panel: newPanel,
                    hostingView: newHosting,
                    metrics: metrics,
                    cachedFrame: newPanel.frame
                )
            }
        }

        for (staleID, entry) in screenPanels where !activeIDs.contains(staleID) {
            entry.panel.orderOut(nil)
            entry.panel.close()
            screenPanels.removeValue(forKey: staleID)
        }

        let primaryMetrics = ScreenNotchMetrics.measure(screen: primaryTarget)
        let primaryKey: CGDirectDisplayID = primaryMetrics.displayID != 0 ? primaryMetrics.displayID : 1
        if let primaryEntry = screenPanels[primaryKey] ?? screenPanels.values.first {
            self.panel = primaryEntry.panel
            self.hostingView = primaryEntry.hostingView
            self.cachedPanelFrame = primaryEntry.cachedFrame
        }
    }

    private func orderAllPanelsFront() {
        for entry in screenPanels.values {
            entry.panel.orderFrontRegardless()
        }
    }

    public func updateCanvasPosition() {
        setupNotchGeometry()
        syncScreenPanels()
        updateHitTesting(mouseLocation: NSEvent.mouseLocation)
    }

    // MARK: - Precision Hit-Testing, Hover Micro-Stretch & Auto-Collapse

    private func setupInteractionMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handlePointerMovement(at: NSEvent.mouseLocation, eventType: event.type)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handlePointerMovement(at: NSEvent.mouseLocation, eventType: event.type)
            }
            return event
        }

        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScrollGesture(event)
            }
        }

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScrollGesture(event)
            }
            return event
        }

        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self else { return event }
            let loc = NSEvent.mouseLocation
            if let entry = self.panelEntryContaining(loc, padding: 6), !entry.panel.ignoresMouseEvents {
                Task { @MainActor [weak self] in
                    self?.presentContextMenu(at: loc)
                }
                return nil
            }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCanvasPosition()
            }
        }
    }

    private func handlePointerMovement(at location: NSPoint, eventType: NSEvent.EventType) {
        let verticalMargin: CGFloat = (eventType == .leftMouseDragged) ? 104 : 56
        if !isExpanded && !isHovered && !isDropHovered && !presentationMode.isPopDownMode {
            let nearAnyTop = screenPanels.values.contains { location.y >= ($0.cachedFrame.maxY - verticalMargin) }
            if !nearAnyTop { return }
        }
        updateDragProximity(at: location, isDraggingEvent: eventType == .leftMouseDragged)
        updateHitTesting(mouseLocation: location)
    }

    private func panelEntryContaining(_ point: NSPoint, padding: CGFloat = 6) -> ScreenPanelEntry? {
        for entry in screenPanels.values {
            let hitRects = metaballState(for: entry.metrics).screenHitRects(inPanelFrame: entry.panel.frame)
            if hitRects.contains(where: { $0.insetBy(dx: -padding, dy: -padding).contains(point) }) {
                return entry
            }
        }
        return nil
    }

    private func isPointInsideIsland(_ point: NSPoint, padding: CGFloat = 6) -> Bool {
        panelEntryContaining(point, padding: padding) != nil
    }

    public func updateHitTesting(mouseLocation: NSPoint) {
        guard !screenPanels.isEmpty else { return }
        var inside = false
        let dropActive = (presentationMode == .compactDropZone)

        for entry in screenPanels.values {
            let hitRects = metaballState(for: entry.metrics).screenHitRects(inPanelFrame: entry.panel.frame)
            let insideThis = hitRects.contains { $0.insetBy(dx: -6, dy: -6).contains(mouseLocation) }
            if insideThis { inside = true }
            let shouldAcceptMouse = insideThis || dropActive
            if entry.panel.ignoresMouseEvents == shouldAcceptMouse {
                entry.panel.ignoresMouseEvents = !shouldAcceptMouse
            }
        }

        if inside {
            if isExpanded {
                didCursorEnterWhileExpanded = true
            }
            mouseExitCollapseTimer?.invalidate()
            mouseExitCollapseTimer = nil
        } else if isExpanded && didCursorEnterWhileExpanded && !isDropHovered && !isContextMenuOpen {
            scheduleMouseExitAutoCollapse()
        }

        if inside != isHovered {
            isHovered = inside
            if inside {
                if !isExpanded {
                    HapticEngine.perform(.alignment)
                }
                if hoverToExpand && !isExpanded && hasActiveExpandableActivity && presentationMode != .compactLockScreen {
                    scheduleHoverExpand()
                }
            } else {
                hoverTimer?.invalidate()
                hoverTimer = nil
            }
        }
    }

    private func scheduleMouseExitAutoCollapse() {
        guard mouseExitCollapseTimer == nil else { return }
        mouseExitCollapseTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.mouseExitCollapseTimer = nil
                if self.isExpanded && !self.isHovered && !self.isDropHovered && !self.isContextMenuOpen {
                    self.collapse()
                }
            }
        }
    }

    private func updateDragProximity(at mouseLoc: NSPoint, isDraggingEvent: Bool) {
        let leftButtonDown = isDraggingEvent || (NSEvent.pressedMouseButtons & 1) != 0
        let inTopZone = screenPanels.values.contains { entry in
            mouseLoc.y >= (entry.panel.frame.maxY - 96) && abs(mouseLoc.x - entry.panel.frame.midX) <= 180
        }

        if leftButtonDown && inTopZone && FileShelfManager.pasteboardHasSupportedDragPayload() {
            let dragPB = NSPasteboard(name: .drag)
            if !isDropHovered || dragPB.changeCount != lastDragChangeCount {
                lastDragChangeCount = dragPB.changeCount
                isDropHovered = true
                if !isExpanded && presentationMode != .compactDropZone {
                    presentationMode = .compactDropZone
                }
            }
            if dragWatchTimer == nil {
                dragWatchTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.pollDragRelease()
                    }
                }
            }
        } else if isDropHovered && (!leftButtonDown || !inTopZone) {
            endDragProximity()
        }
    }

    private func pollDragRelease() {
        let leftDown = (NSEvent.pressedMouseButtons & 1) != 0
        let mouseLoc = NSEvent.mouseLocation
        let inTopZone = screenPanels.values.contains { entry in
            mouseLoc.y >= (entry.panel.frame.maxY - 120) && abs(mouseLoc.x - entry.panel.frame.midX) <= 250
        }
        if !leftDown || !inTopZone {
            endDragProximity()
        }
    }

    private func endDragProximity() {
        dragWatchTimer?.invalidate()
        dragWatchTimer = nil
        isDropHovered = false
        if presentationMode == .compactDropZone {
            reconcileBaselineMode()
        }
    }

    private func scheduleHoverExpand() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isHovered, !self.isExpanded, self.hasActiveExpandableActivity else { return }
                self.expandActiveContext()
            }
        }
    }

    // MARK: - Trackpad Swipes & Click-Outside Dismiss

    private func handleScrollGesture(_ event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation
        if !isExpanded && !isHovered && !presentationMode.isPopDownMode {
            let nearAnyTop = screenPanels.values.contains { mouseLoc.y >= ($0.cachedFrame.maxY - 64) }
            if !nearAnyTop { return }
        }
        guard isPointInsideIsland(mouseLoc, padding: 12) else { return }

        let now = Date()
        guard now.timeIntervalSince(lastScrollTriggerDate) > 0.42 else { return }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let minSwipeThreshold: CGFloat = 18.0

        let isPhysicalSwipeUp = event.isDirectionInvertedFromDevice ? (dy > minSwipeThreshold) : (dy < -minSwipeThreshold)
        if abs(dy) > abs(dx) && isPhysicalSwipeUp && isExpanded {
            lastScrollTriggerDate = now
            collapse()
            return
        }

        if abs(dx) > minSwipeThreshold && abs(dx) > abs(dy) * 1.25 {
            lastScrollTriggerDate = now
            if presentationMode.isTransientMode {
                dismissTransientAlert()
                return
            }
            if presentationMode == .expandedRoutes && dx > 0 {
                presentationMode = .expandedMusic
                HapticEngine.perform(.generic)
                return
            }
            if isExpanded {
                // Switch strictly between genuinely active concurrent live activities
                if case .expandedMusic = presentationMode, let activeTimer = TimerManager.shared.activeTimer {
                    presentationMode = .expandedTimer(activeTimer)
                    HapticEngine.perform(.generic)
                } else if case .expandedTimer = presentationMode, NowPlayingManager.shared.currentTrack.isPlaying {
                    presentationMode = .expandedMusic
                    HapticEngine.perform(.generic)
                }
                return
            }
            if NowPlayingManager.shared.currentTrack.isPlaying {
                HapticEngine.perform(.generic)
                if dx < 0 {
                    NowPlayingManager.shared.nextTrack()
                } else {
                    NowPlayingManager.shared.previousTrack()
                }
            }
        }
    }

    private func startMonitoringDismissEvents() {
        stopMonitoringDismissEvents()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isExpanded, !self.isContextMenuOpen else { return }
                let mouseLoc = NSEvent.mouseLocation
                if !self.isPointInsideIsland(mouseLoc, padding: 4) {
                    self.collapse()
                }
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isExpanded, !self.isContextMenuOpen else { return event }
            let mouseLoc = NSEvent.mouseLocation
            if !self.isPointInsideIsland(mouseLoc, padding: 4) {
                Task { @MainActor [weak self] in
                    self?.collapse()
                }
            }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor [weak self] in
                    self?.collapse()
                }
            }
            return event
        }
    }

    private func stopMonitoringDismissEvents() {
        if let monitor = clickOutsideMonitor { NSEvent.removeMonitor(monitor); clickOutsideMonitor = nil }
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor); localClickMonitor = nil }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor); keyMonitor = nil }
    }

    // MARK: - Native Right-Click Context Menu (Timer Presets & Settings)

    public func presentContextMenu(at screenPoint: NSPoint) {
        let menu = NSMenu(title: "Dynamic Island")

        let modeMenu = NSMenu(title: "Режим отображения")
        for mode in IslandDisplayMode.allCases {
            let item = NSMenuItem(title: mode.localizedTitle, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (displayMode == mode) ? .on : .off
            modeMenu.addItem(item)
        }
        let modeParent = NSMenuItem(title: "Режим отображения", action: nil, keyEquivalent: "")
        modeParent.submenu = modeMenu
        menu.addItem(modeParent)

        // Timer Presets live strictly inside Context Menu (zero island preset clutter)
        let timerMenu = NSMenu(title: "Таймер")
        for preset in TimerManager.presetDurations {
            let item = NSMenuItem(title: preset.label, action: #selector(startTimerPresetMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = preset.seconds
            item.representedObject = preset.label
            timerMenu.addItem(item)
        }
        if TimerManager.shared.activeTimer != nil {
            timerMenu.addItem(.separator())
            let stopItem = NSMenuItem(title: "Остановить таймер", action: #selector(stopTimerMenu), keyEquivalent: "")
            stopItem.target = self
            timerMenu.addItem(stopItem)
        }
        let timerParent = NSMenuItem(title: "Таймер", action: nil, keyEquivalent: "")
        timerParent.submenu = timerMenu
        menu.addItem(timerParent)

        menu.addItem(.separator())

        let hoverItem = NSMenuItem(title: "Раскрытие при наведении", action: #selector(toggleHoverExpandMenu), keyEquivalent: "")
        hoverItem.target = self
        hoverItem.state = hoverToExpand ? .on : .off
        menu.addItem(hoverItem)

        let soundItem = NSMenuItem(title: "Звуковые эффекты", action: #selector(toggleSoundMenu), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = SoundManager.shared.isEnabled ? .on : .off
        menu.addItem(soundItem)

        let hapticItem = NSMenuItem(title: "Тактильный отклик", action: #selector(toggleHapticsMenu), keyEquivalent: "")
        hapticItem.target = self
        hapticItem.state = HapticEngine.isEnabled ? .on : .off
        menu.addItem(hapticItem)

        let loginItem = NSMenuItem(title: "Запуск при входе", action: #selector(toggleLoginMenu), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItemHelper.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Завершить", action: #selector(quitMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        isContextMenuOpen = true
        let targetEntry = panelEntryContaining(screenPoint, padding: 16)
        let targetPanelFrame = targetEntry?.panel.frame ?? panel.frame
        let targetHosting = targetEntry?.hostingView ?? hostingView
        let panelPoint = NSPoint(x: screenPoint.x - targetPanelFrame.origin.x, y: screenPoint.y - targetPanelFrame.origin.y)
        menu.popUp(positioning: nil, at: panelPoint, in: targetHosting)
        isContextMenuOpen = false
        updateHitTesting(mouseLocation: NSEvent.mouseLocation)
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = IslandDisplayMode(rawValue: raw) {
            displayMode = mode
        }
    }

    @objc private func startTimerPresetMenu(_ sender: NSMenuItem) {
        let label = sender.representedObject as? String ?? "Timer"
        TimerManager.shared.startTimer(seconds: sender.tag, label: label)
        reconcileBaselineMode()
    }

    @objc private func stopTimerMenu() {
        TimerManager.shared.stopTimer()
        collapse()
    }

    @objc private func toggleHoverExpandMenu() { hoverToExpand.toggle() }
    @objc private func toggleSoundMenu() { _ = SoundManager.shared.toggleEnabled() }
    @objc private func toggleHapticsMenu() { HapticEngine.isEnabled.toggle() }
    @objc private func toggleLoginMenu() { LoginItemHelper.toggle() }
    @objc private func quitMenu() { NSApplication.shared.terminate(nil) }

    // MARK: - Autonomous System Observers

    private func setupObservers() {
        Task { @MainActor [weak self] in
            await NowPlayingManager.shared.updateNowPlaying()
            self?.reconcileBaselineMode()
        }

        FileShelfManager.shared.onShelfEmptied = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.presentationMode == .expandedFileShelf {
                    self.collapse()
                } else {
                    self.reconcileBaselineMode()
                }
            }
        }

        BatteryMonitor.shared.onPluggedInStateChanged = { [weak self] isPlugged in
            Task { @MainActor [weak self] in
                if isPlugged { SoundManager.shared.play("chime") }
                self?.showTransientAlert(mode: .compactBattery, duration: 3.0)
            }
        }

        BatteryMonitor.shared.onLowBatteryWarning = { [weak self] pct in
            Task { @MainActor [weak self] in
                SoundManager.shared.play("low-battery")
                let prio: IslandActivityPriority = pct <= 10 ? .critical : .transientHigh
                self?.showTransientAlert(mode: .compactLowBattery, duration: 3.0, overridePriority: prio)
            }
        }

        BatteryMonitor.shared.onLowPowerModeChanged = { [weak self] enabled in
            Task { @MainActor [weak self] in
                SoundManager.shared.play("low-power")
                self?.showTransientAlert(mode: .compactLowPowerMode(enabled), duration: 3.0)
            }
        }

        AudioDeviceMonitor.shared.onVolumeChanged = { [weak self] _ in
            Task { @MainActor [weak self] in
                SoundManager.shared.playThrottled("volume", minInterval: 0.08)
                self?.showTransientAlert(mode: .compactVolume, duration: 2.0)
            }
        }

        AudioDeviceMonitor.shared.onMuteChanged = { [weak self] _ in
            Task { @MainActor [weak self] in
                SoundManager.shared.playThrottled("volume", minInterval: 0.08)
                self?.showTransientAlert(mode: .compactMute, duration: 2.0)
            }
        }

        AudioDeviceMonitor.shared.onDeviceChanged = { [weak self] _, isHeadphones in
            Task { @MainActor [weak self] in
                if isHeadphones {
                    SoundManager.shared.play("chime")
                    self?.showTransientAlert(mode: .compactAirPods, duration: 3.2)
                }
            }
        }

        AudioDeviceMonitor.shared.onBrightnessChanged = { [weak self] pct in
            Task { @MainActor [weak self] in
                self?.showTransientAlert(mode: .compactBrightness(pct), duration: 2.0)
            }
        }

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
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            SoundManager.shared.play("sleep")
            Task { @MainActor [weak self] in
                NowPlayingManager.shared.stopPolling()
                NowPlayingManager.shared.setExpandedTimelineActive(false)
                BatteryMonitor.shared.stopMonitoring()
                self?.reconcileTimer?.invalidate()
                self?.reconcileTimer = nil
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                BatteryMonitor.shared.startMonitoring()
                self.scheduleReconcileTimer()
                self.updateCanvasPosition()
                self.orderAllPanelsFront()
                await NowPlayingManager.shared.updateNowPlaying()
                if self.transientAlertTimer == nil && !self.isScreenLocked {
                    self.reconcileBaselineMode()
                }
            }
        }

        NowPlayingManager.shared.onTrackChanged = { [weak self] track in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isScreenLocked else { return }
                self.musicPauseGraceTimer?.invalidate()
                self.musicPauseGraceTimer = nil
                if self.presentationMode == .expandedMusic {
                    return
                }
                self.showTransientAlert(mode: .compactTrackChange(track), duration: 2.8)
            }
        }

        NowPlayingManager.shared.onPlaybackStateChanged = { [weak self] isPlaying in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.musicPauseGraceTimer?.invalidate()
                self.musicPauseGraceTimer = nil
                guard self.transientAlertTimer == nil && !self.isExpanded && !self.isScreenLocked else { return }

                if isPlaying {
                    self.reconcileBaselineMode()
                } else {
                    self.musicPauseGraceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self = self, !NowPlayingManager.shared.currentTrack.isPlaying,
                                  !self.isExpanded, self.transientAlertTimer == nil else { return }
                            self.reconcileBaselineMode()
                        }
                    }
                }
            }
        }

        TimerManager.shared.onTimerTick = { [weak self] info in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .expandedTimer = self.presentationMode {
                    self.presentationMode = .expandedTimer(info)
                } else if !self.isExpanded && self.transientAlertTimer == nil && !self.isScreenLocked && self.presentationMode != .compactDropZone {
                    self.reconcileBaselineMode()
                }
            }
        }

        TimerManager.shared.onTimerStopped = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if case .expandedTimer = self.presentationMode {
                    self.collapse()
                } else if self.transientAlertTimer == nil {
                    self.reconcileBaselineMode()
                }
            }
        }

        TimerManager.shared.onTimerEnded = { [weak self] info in
            Task { @MainActor [weak self] in
                SoundManager.shared.play("event")
                let alert = SystemAlertInfo(title: info.label, subtitle: "Time's Up!", iconName: "timer", iconColor: "orange")
                self?.showTransientAlert(mode: .compactAlert(alert), duration: 4.5, overridePriority: .critical)
            }
        }

        PrivacyMonitor.shared.onPrivacyStateChanged = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.updateHitTesting(mouseLocation: NSEvent.mouseLocation)
                HapticEngine.perform(.alignment)
            }
        }

        scheduleReconcileTimer()
    }

    private func scheduleReconcileTimer() {
        reconcileTimer?.invalidate()
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      self.transientAlertTimer == nil,
                      self.musicPauseGraceTimer == nil,
                      !self.isExpanded,
                      !self.isScreenLocked,
                      self.presentationMode != .compactDropZone else { return }
                self.reconcileBaselineMode()
            }
        }
        reconcileTimer?.tolerance = 8.0
    }

    // MARK: - Context-Driven Priority Actions

    public var hasActiveExpandableActivity: Bool {
        let hasMusic = NowPlayingManager.shared.currentTrack.isPlaying || !NowPlayingManager.shared.currentTrack.title.isEmpty
        return hasMusic || TimerManager.shared.activeTimer != nil || !FileShelfManager.shared.items.isEmpty
    }

    public func reconcileBaselineMode() {
        let target = stateResolver.baselineMode(
            isScreenLocked: isScreenLocked,
            isPlaying: NowPlayingManager.shared.currentTrack.isPlaying,
            currentTrack: NowPlayingManager.shared.currentTrack,
            activeTimer: TimerManager.shared.activeTimer,
            shelfItemCount: FileShelfManager.shared.items.count
        )
        if presentationMode != target {
            presentationMode = target
        }
    }

    public func showTransientAlert(
        mode: IslandPresentationMode,
        duration: TimeInterval,
        overridePriority: IslandActivityPriority? = nil
    ) {
        guard stateResolver.canPreempt(
            current: presentationMode,
            isPinned: isPinned,
            candidate: mode,
            overridePriority: overridePriority
        ) else {
            return
        }

        transientAlertTimer?.invalidate()
        presentationMode = mode
        if case .compactFocus = mode {
            SoundManager.shared.playThrottled("haptic", minInterval: 0.1)
        }
        HapticEngine.perform(.generic)

        transientAlertTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.transientAlertTimer = nil
                if !self.isExpanded && !self.isScreenLocked {
                    self.reconcileBaselineMode()
                }
            }
        }
    }

    public func extendTransientAlert(duration: TimeInterval = 2.0) {
        guard presentationMode.isTransientMode else { return }
        transientAlertTimer?.invalidate()
        transientAlertTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.transientAlertTimer = nil
                if !self.isExpanded && !self.isScreenLocked {
                    self.reconcileBaselineMode()
                }
            }
        }
    }

    public func dismissTransientAlert() {
        transientAlertTimer?.invalidate()
        transientAlertTimer = nil
        HapticEngine.perform(.generic)
        if !isExpanded && !isScreenLocked {
            reconcileBaselineMode()
        }
    }

    public func collapse() {
        isPinned = false
        didCursorEnterWhileExpanded = false
        mouseExitCollapseTimer?.invalidate()
        mouseExitCollapseTimer = nil
        stopMonitoringDismissEvents()
        reconcileBaselineMode()
        HapticEngine.perform(.generic)
    }

    /// Context-driven expansion ONLY: never opens an empty panel when idle.
    public func expandActiveContext() {
        if NowPlayingManager.shared.currentTrack.isPlaying || !NowPlayingManager.shared.currentTrack.title.isEmpty {
            isPinned = true
            presentationMode = .expandedMusic
            HapticEngine.perform(.generic)
        } else if let timer = TimerManager.shared.activeTimer {
            isPinned = true
            presentationMode = .expandedTimer(timer)
            HapticEngine.perform(.generic)
        } else if !FileShelfManager.shared.items.isEmpty {
            isPinned = true
            presentationMode = .expandedFileShelf
            HapticEngine.perform(.generic)
        } else {
            triggerIdleElasticBounce()
        }
    }

    /// Performs the Apple subtle elastic micro-stretch in `.idle` with light haptic feedback.
    public func triggerIdleElasticBounce() {
        HapticEngine.perform(.alignment)
        idleBounceTimer?.invalidate()
        isIdlePressedBounce = true
        idleBounceTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isIdlePressedBounce = false
            }
        }
    }

    public func toggleExpansion() {
        if isExpanded {
            collapse()
        } else {
            expandActiveContext()
        }
    }

    public func toggleFileShelf() {
        if presentationMode == .expandedFileShelf {
            collapse()
        } else if !FileShelfManager.shared.items.isEmpty || isDropHovered {
            isPinned = true
            presentationMode = .expandedFileShelf
            HapticEngine.perform(.generic)
        } else {
            triggerIdleElasticBounce()
        }
    }

    // MARK: - Event Triggers

    @objc private func handleScreenLocked(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isScreenLocked = true
            self.isPinned = false
            self.transientAlertTimer?.invalidate()
            self.transientAlertTimer = nil
            NowPlayingManager.shared.setExpandedTimelineActive(false)
            SoundManager.shared.play("lock")
            self.orderAllPanelsFront()
            self.presentationMode = .compactLockScreen
        }
    }

    @objc private func handleScreenUnlocked(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isScreenLocked = false
            self.updateCanvasPosition()
            self.orderAllPanelsFront()
            SoundManager.shared.play("unlock")
            self.showTransientAlert(mode: .compactUnlock, duration: 2.2, overridePriority: .critical)
        }
    }

    public func triggerBatteryAlert() {
        SoundManager.shared.play("chime")
        showTransientAlert(mode: .compactBattery, duration: 3.0)
    }

    public func triggerUnlockAlert() {
        SoundManager.shared.play("unlock")
        showTransientAlert(mode: .compactUnlock, duration: 2.0, overridePriority: .critical)
    }

    public func triggerCustomAlert(title: String, subtitle: String, icon: String, color: String = "white", duration: TimeInterval = 3.0) {
        let alert = SystemAlertInfo(title: title, subtitle: subtitle, iconName: icon, iconColor: color)
        showTransientAlert(mode: .compactAlert(alert), duration: duration)
    }

    public func triggerBrightnessAlert(level: Int) {
        SoundManager.shared.playThrottled("volume", minInterval: 0.08)
        showTransientAlert(mode: .compactBrightness(level), duration: 2.0)
    }

    public func triggerLowPowerAlert(enabled: Bool) {
        SoundManager.shared.play("low-power")
        showTransientAlert(mode: .compactLowPowerMode(enabled), duration: 3.0)
    }
}

// MARK: - Login Item Helper

@MainActor
public enum LoginItemHelper {
    public static var isEnabled: Bool {
        let script = "tell application \"System Events\" to return (exists login item \"DynamicIsland\")"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            return appleScript.executeAndReturnError(&error).booleanValue
        }
        return false
    }

    public static func setEnabled(_ enabled: Bool) {
        let appPath = Bundle.main.bundlePath
        let script = enabled
            ? "tell application \"System Events\" to make new login item at end with properties {name:\"DynamicIsland\", path:\"\(appPath)\", hidden:false}"
            : "tell application \"System Events\" to delete (every login item whose name is \"DynamicIsland\")"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    public static func toggle() {
        setEnabled(!isEnabled)
    }
}
