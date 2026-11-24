import AppKit
import SwiftUI
import Testing
@testable import DynamicIsland

@Suite("Dynamic Island Context-Driven States, 1:1 Geometry & Managers")
struct DynamicIslandTests {

    @Test("Priority queue enforces critical lock screen and protects pinned expanded cards")
    func statePriorityPreemption() {
        let resolver = IslandStateResolver()

        #expect(
            resolver.canPreempt(
                current: .compactLockScreen,
                isPinned: false,
                candidate: .compactVolume
            ) == false
        )

        #expect(
            resolver.canPreempt(
                current: .compactLockScreen,
                isPinned: false,
                candidate: .compactUnlock
            ) == true
        )

        #expect(
            resolver.canPreempt(
                current: .expandedMusic,
                isPinned: true,
                candidate: .compactVolume
            ) == false
        )

        #expect(
            resolver.canPreempt(
                current: .expandedMusic,
                isPinned: true,
                candidate: .compactLowBattery,
                overridePriority: .critical
            ) == true
        )

        let track1 = MediaTrack(title: "First", artist: "Artist", album: "Album", isPlaying: true, duration: 120, position: 0, source: .spotify)
        let track2 = MediaTrack(title: "Second", artist: "Artist", album: "Album", isPlaying: true, duration: 150, position: 0, source: .spotify)
        #expect(
            resolver.canPreempt(
                current: .compactTrackChange(track1),
                isPinned: false,
                candidate: .compactTrackChange(track2)
            ) == true
        )
    }

    @Test("Baseline mode resolves purely from active contexts (no empty dashboard states)")
    func contextDrivenBaselineResolution() {
        let resolver = IslandStateResolver()
        let playingTrack = MediaTrack(title: "Test", artist: "Artist", album: "Album", isPlaying: true, duration: 120, position: 10, source: .spotify)
        let pausedTrack = MediaTrack(title: "Test", artist: "Artist", album: "Album", isPlaying: false, duration: 120, position: 10, source: .spotify)
        let timer = TimerInfo(totalSeconds: 300, remainingSeconds: 200, label: "Focus", isPaused: false)

        #expect(
            resolver.baselineMode(isScreenLocked: false, isPlaying: true, currentTrack: playingTrack, activeTimer: timer, shelfItemCount: 0)
            == .compactDual(playingTrack, timer)
        )

        #expect(
            resolver.baselineMode(isScreenLocked: true, isPlaying: true, currentTrack: playingTrack, activeTimer: timer, shelfItemCount: 2)
            == .compactLockScreen
        )

        #expect(
            resolver.baselineMode(isScreenLocked: false, isPlaying: false, currentTrack: pausedTrack, activeTimer: timer, shelfItemCount: 1)
            == .compactTimer(timer)
        )

        #expect(
            resolver.baselineMode(isScreenLocked: false, isPlaying: false, currentTrack: pausedTrack, activeTimer: nil, shelfItemCount: 2)
            == .compactShelf(2)
        )

        #expect(
            resolver.baselineMode(isScreenLocked: false, isPlaying: false, currentTrack: pausedTrack, activeTimer: nil, shelfItemCount: 0)
            == .idle
        )
    }

    @Test("ScreenNotchMetrics anchors panel flush to physical top pixel screen.frame.maxY")
    @MainActor
    func topFlushWindowPositioning() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let metrics = ScreenNotchMetrics(
            hasHardwareNotch: true,
            notchWidth: 183,
            notchHeight: 32,
            screenFrame: screenFrame
        )
        let panelFrame = metrics.panelFrame()

        #expect(panelFrame.width == MetaballSplitState.canvasWidth)
        #expect(panelFrame.height == MetaballSplitState.canvasHeight)
        #expect(panelFrame.origin.y == screenFrame.maxY - MetaballSplitState.canvasHeight)
        #expect(panelFrame.maxY == screenFrame.maxY)
        #expect(abs(panelFrame.midX - screenFrame.midX) < 0.01)

        let panel = IslandPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        #expect(panel.constrainFrameRect(panelFrame, to: nil) == panelFrame)
    }

    @Test("NotchShape path is top-flush at y=0 with concave top ears and zero top gap")
    func notchShapeTopFlushGeometry() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 32)
        let path = NotchShape(topCornerRadius: 10, bottomCornerRadius: 14).path(in: rect)
        let bounds = path.boundingRect

        #expect(abs(bounds.minY) < 0.01)
        #expect(abs(bounds.maxY - 32) < 0.01)
        #expect(abs(bounds.minX) < 0.01)
        #expect(abs(bounds.maxX - 320) < 0.01)
        #expect(path.contains(CGPoint(x: 160, y: 1)))
        #expect(path.contains(CGPoint(x: 3, y: 1)) == false)
    }

    @Test("Idle micro-stretch adds +18pt width and +3pt height without expanding panel")
    func idleMicroStretchGeometry() {
        let idleResting = MetaballSplitState(
            mode: .idle,
            isFloatingPill: false,
            isIdleStretched: false,
            notchWidth: 183,
            notchHeight: 32,
            routeCount: 1,
            shelfItemCount: 0
        )
        let idleStretched = MetaballSplitState(
            mode: .idle,
            isFloatingPill: false,
            isIdleStretched: true,
            notchWidth: 183,
            notchHeight: 32,
            routeCount: 1,
            shelfItemCount: 0
        )

        #expect(idleStretched.mainSize.width - idleResting.mainSize.width == 18)
        #expect(idleStretched.mainSize.height - idleResting.mainSize.height == 3)
        #expect(idleStretched.isSplit == false)
    }

    @Test("1:1 Live Activity cards, ultra-tight compact wings, and pop-down HUDs prevent menu bar & camera collisions")
    func liveActivityAndTransientDimensions() {
        let notchW: CGFloat = 183
        let notchH: CGFloat = 34
        let timer = TimerInfo(totalSeconds: 180, remainingSeconds: 90, label: "Focus", isPaused: false)
        let track = MediaTrack(title: "Track", artist: "Artist", album: "Album", isPlaying: true, duration: 180, position: 30, source: .spotify)

        // Compact wings must stay <= notchWidth + 60pt (56pt max total padding = 28pt per side)
        let compactMusic = MetaballSplitState(
            mode: .compactMusic,
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(compactMusic.mainSize.width <= notchW + 60)
        #expect(compactMusic.mainSize == CGSize(width: notchW + 56, height: notchH))

        let compactTimer = MetaballSplitState(
            mode: .compactTimer(timer),
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(compactTimer.mainSize.width <= notchW + 60)

        // Expanded content top safe-zone must stay strictly below hardware camera housing
        let topPad = MetaballSplitState.expandedContentTopPadding(notchHeight: notchH, isFloatingPill: false)
        #expect(topPad >= notchH + 6)

        let musicCard = MetaballSplitState(
            mode: .expandedMusic,
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 2,
            shelfItemCount: 0
        )
        #expect(musicCard.mainSize == CGSize(width: 350, height: notchH + 132))

        let timerCard = MetaballSplitState(
            mode: .expandedTimer(timer),
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(timerCard.mainSize == CGSize(width: 350, height: notchH + 76))

        // Transient banners must use Pop-Down geometry (260 x notchHeight + 44) instead of horizontal stretching
        let trackToast = MetaballSplitState(
            mode: .compactTrackChange(track),
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(trackToast.mainSize == CGSize(width: 260, height: notchH + 44))

        let batteryHUD = MetaballSplitState(
            mode: .compactBattery,
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(batteryHUD.mainSize == CGSize(width: 260, height: notchH + 44))

        let lowPowerHUD = MetaballSplitState(
            mode: .compactLowPowerMode(true),
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(lowPowerHUD.mainSize == CGSize(width: 260, height: notchH + 44))

        let volumeHUD = MetaballSplitState(
            mode: .compactVolume,
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(volumeHUD.mainSize == CGSize(width: 260, height: notchH + 44))

        let dualSplit = MetaballSplitState(
            mode: .compactDual(track, timer),
            isFloatingPill: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(dualSplit.isSplit == true)
        #expect(dualSplit.mainSize.width <= notchW + 60)
        #expect(dualSplit.detachedCanvasRect() != nil)
        #expect(dualSplit.hitRects().count == 2)
    }

    @Test("Monochrome artwork extracts crisp white palette instead of dull grey")
    @MainActor
    func monochromeArtworkPaletteBoost() {
        let size = NSSize(width: 40, height: 40)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(white: 0.85, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let palette = NowPlayingManager.shared.extractPalette(from: image)
        let overallNS = NSColor(palette.overall).usingColorSpace(.sRGB)
        #expect(overallNS != nil)
        #expect((overallNS?.brightnessComponent ?? 0) >= 0.95)
        #expect((overallNS?.saturationComponent ?? 1) < 0.05)
    }

    @Test("Spring transitions map expansion, collapse, transient pop, and idle stretch")
    func springTransitions() {
        #expect(IslandPresentationMode.springKind(from: .compactMusic, to: .expandedMusic) == .expansion)
        #expect(IslandPresentationMode.springKind(from: .expandedMusic, to: .compactMusic) == .collapse)
        #expect(IslandPresentationMode.springKind(from: .idle, to: .compactVolume) == .transientPop)
        #expect(IslandPresentationMode.springKind(from: .compactMusic, to: .idle) == .idleStretch)
    }

    @Test("TimerManager transitions through start, pause, +1m, and stop cleanly")
    @MainActor
    func timerManagerTransitions() {
        let manager = TimerManager.shared
        manager.stopTimer()
        #expect(manager.activeTimer == nil)

        manager.startTimer(seconds: 120, label: "Deep Work")
        #expect(manager.activeTimer?.totalSeconds == 120)
        #expect(manager.activeTimer?.remainingSeconds == 120)
        #expect(manager.activeTimer?.isPaused == false)

        manager.addMinute()
        #expect(manager.activeTimer?.totalSeconds == 180)
        #expect(manager.activeTimer?.remainingSeconds == 180)

        manager.togglePause()
        #expect(manager.activeTimer?.isPaused == true)

        manager.stopTimer()
        #expect(manager.activeTimer == nil)
    }

    @Test("FileShelfManager triggers onShelfEmptied when last file removed or cleared")
    @MainActor
    func fileShelfAutoDismissTransitions() {
        let shelf = FileShelfManager.shared
        let prevEnabled = SoundManager.shared.isEnabled
        SoundManager.shared.isEnabled = false
        defer {
            SoundManager.shared.isEnabled = prevEnabled
            shelf.onShelfEmptied = nil
        }

        shelf.clearAll()
        var emptiedCount = 0
        shelf.onShelfEmptied = { emptiedCount += 1 }

        let url1 = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        shelf.addFile(url1)
        shelf.addFile(url1) // duplicate ignored
        #expect(shelf.items.count == 1)

        if let id = shelf.items.first?.id {
            shelf.removeFile(id: id)
        }
        #expect(shelf.items.isEmpty)
        #expect(emptiedCount == 1)

        shelf.addTextSnippet("Clean note")
        #expect(shelf.items.count == 1)
        shelf.clearAll()
        #expect(shelf.items.isEmpty)
        #expect(emptiedCount == 2)
    }

    @Test("PrivacyMonitor, idle privacy wing widening, interactive scrub, and all 10 .caf sounds")
    @MainActor
    func privacyAndSoundChecks() {
        let monitor = PrivacyMonitor.shared
        monitor.clearManualOverrides()
        monitor.setMicActive(true)
        #expect(monitor.isAnyActive == true)

        let notchW: CGFloat = 183
        let notchH: CGFloat = 34
        let idleWithoutPrivacy = MetaballSplitState(
            mode: .idle,
            isFloatingPill: false,
            hasActivePrivacyIndicator: false,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        let idleWithPrivacy = MetaballSplitState(
            mode: .idle,
            isFloatingPill: false,
            hasActivePrivacyIndicator: true,
            notchWidth: notchW,
            notchHeight: notchH,
            routeCount: 1,
            shelfItemCount: 0
        )
        #expect(idleWithPrivacy.mainSize.width > idleWithoutPrivacy.mainSize.width)
        #expect(idleWithPrivacy.mainSize.width > notchW)
        #expect(idleWithPrivacy.mainSize.width <= notchW + 60)

        monitor.clearManualOverrides()

        let np = NowPlayingManager.shared
        np.setExpandedTimelineActive(true)
        #expect(np.isExpandedTimelineVisible == true)
        np.setExpandedTimelineActive(false)
        #expect(np.isExpandedTimelineVisible == false)
        np.beginInteractiveScrub(to: 12)
        #expect(np.isUserScrubbing == true)
        np.commitInteractiveScrub(to: 0)
        #expect(np.isUserScrubbing == false)

        let soundCount = SoundManager.shared.preloadedSoundCount()
        #expect(SoundManager.allSoundNames.count == 10)
        #expect(soundCount == 10)
    }

    @Test("Multi-monitor geometry computes independent notch and floating pill states across N screens")
    @MainActor
    func multiMonitorIndependentGeometry() {
        let controller = IslandWindowController.shared
        let prevMode = controller.displayMode
        controller.displayMode = .automatic
        defer { controller.displayMode = prevMode }

        let builtIn = ScreenNotchMetrics(
            displayID: 1,
            hasHardwareNotch: true,
            notchWidth: 184,
            notchHeight: 37,
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956)
        )
        let external1 = ScreenNotchMetrics(
            displayID: 2,
            hasHardwareNotch: false,
            notchWidth: 160,
            notchHeight: 34,
            screenFrame: CGRect(x: 1470, y: 0, width: 2560, height: 1440)
        )
        let external2 = ScreenNotchMetrics(
            displayID: 3,
            hasHardwareNotch: false,
            notchWidth: 160,
            notchHeight: 34,
            screenFrame: CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        )

        #expect(controller.isFloatingPill(for: builtIn) == false)
        #expect(controller.isFloatingPill(for: external1) == true)
        #expect(controller.isFloatingPill(for: external2) == true)

        let builtInState = controller.metaballState(for: builtIn)
        let ext1State = controller.metaballState(for: external1)
        let ext2State = controller.metaballState(for: external2)

        #expect(builtInState.topOffset == 0)
        #expect(builtInState.topEarRadius > 0)
        #expect(ext1State.topOffset == 8)
        #expect(ext1State.topEarRadius == 0)
        #expect(ext2State.topOffset == 8)
        #expect(ext2State.topEarRadius == 0)

        for m in [builtIn, external1, external2] {
            let pf = m.panelFrame()
            #expect(abs(pf.midX - m.screenFrame.midX) < 0.01)
            #expect(abs(pf.maxY - m.screenFrame.maxY) < 0.01)
        }
    }
}
