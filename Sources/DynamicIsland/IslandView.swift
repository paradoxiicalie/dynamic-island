import AppKit
import SwiftUI

// MARK: - Blur + Scale Asymmetric Transition

private struct BlurScaleModifier: ViewModifier {
    let scale: CGFloat
    let blurRadius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .blur(radius: blurRadius)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var islandContentMorph: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurScaleModifier(scale: 0.82, blurRadius: 5, opacity: 0),
                identity: BlurScaleModifier(scale: 1.0, blurRadius: 0, opacity: 1)
            ).animation(.spring(response: 0.34, dampingFraction: 0.78).delay(0.04)),
            removal: .modifier(
                active: BlurScaleModifier(scale: 0.88, blurRadius: 4, opacity: 0),
                identity: BlurScaleModifier(scale: 1.0, blurRadius: 0, opacity: 1)
            ).animation(.easeOut(duration: 0.12))
        )
    }

    static var islandCardMorph: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurScaleModifier(scale: 0.92, blurRadius: 7, opacity: 0),
                identity: BlurScaleModifier(scale: 1.0, blurRadius: 0, opacity: 1)
            ).animation(.spring(response: 0.38, dampingFraction: 0.80).delay(0.03)),
            removal: .modifier(
                active: BlurScaleModifier(scale: 0.94, blurRadius: 5, opacity: 0),
                identity: BlurScaleModifier(scale: 1.0, blurRadius: 0, opacity: 1)
            ).animation(.easeOut(duration: 0.13))
        )
    }
}

// MARK: - Custom Animated Apple Battery Glyph

private struct AppleBatteryGlyph: View {
    let percentage: Int
    let isCharging: Bool
    let isLow: Bool
    @State private var pulse: Bool = false

    private var fillColor: Color {
        if isLow && !isCharging {
            return Color(red: 1.0, green: 0.271, blue: 0.227) // #FF453A
        }
        if isCharging {
            return Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
        }
        return .white
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(fillColor.opacity(0.45), lineWidth: 1.2)
                    .frame(width: 24, height: 12)

                let fillWidth = max(2.0, 20.0 * CGFloat(min(max(percentage, 0), 100)) / 100.0)
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .fill(fillColor)
                    .frame(width: fillWidth, height: 8.5)
                    .padding(.leading, 2)

                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8.5, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .frame(width: 24, height: 12)
                        .scaleEffect(pulse ? 1.12 : 0.92)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                        .onDisappear { pulse = false }
                }
            }

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(fillColor.opacity(0.45))
                .frame(width: 1.8, height: 4.5)
        }
    }
}

// MARK: - True Hardware Notch Geometry (`NotchShape`)

public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    public init(topCornerRadius: CGFloat = 10, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        Self.path(in: rect, topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius, bleedAboveTop: 0)
    }

    static func path(in rect: CGRect, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, bleedAboveTop: CGFloat = 0) -> Path {
        var path = Path()
        let ear = min(max(0, topCornerRadius), rect.width * 0.20)
        let innerWidth = max(1, rect.width - ear * 2.0)
        let r = min(max(0, bottomCornerRadius), min(innerWidth / 2.0, rect.height / 2.0))

        if ear > 0.25 && rect.minY <= 2.0 {
            let startY = rect.minY - bleedAboveTop
            path.move(to: CGPoint(x: rect.minX, y: startY))
            path.addLine(to: CGPoint(x: rect.maxX, y: startY))
            if bleedAboveTop > 0 {
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            }
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear),
                control: CGPoint(x: rect.maxX - ear, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - r))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - ear - r, y: rect.maxY),
                control: CGPoint(x: rect.maxX - ear, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + ear + r, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + ear, y: rect.maxY - r),
                control: CGPoint(x: rect.minX + ear, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control: CGPoint(x: rect.minX + ear, y: rect.minY)
            )
            if bleedAboveTop > 0 {
                path.addLine(to: CGPoint(x: rect.minX, y: startY))
            }
            path.closeSubpath()
        } else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r), style: .continuous)
        }
        return path
    }

    static func openPerimeterPath(in rect: CGRect, topCornerRadius: CGFloat, bottomCornerRadius: CGFloat) -> Path {
        var path = Path()
        let ear = min(max(0, topCornerRadius), rect.width * 0.20)
        let innerWidth = max(1, rect.width - ear * 2.0)
        let r = min(max(0, bottomCornerRadius), min(innerWidth / 2.0, rect.height / 2.0))

        guard ear > 0.25 else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r), style: .continuous)
            return path
        }

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
            control: CGPoint(x: rect.minX + ear, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + ear + r, y: rect.maxY),
            control: CGPoint(x: rect.minX + ear, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear - r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - ear, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX - ear, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - ear, y: rect.minY)
        )
        return path
    }
}

private struct NotchOpenPerimeterShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        NotchShape.openPerimeterPath(in: rect, topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
    }
}

// MARK: - Liquid Metaball Gooey Background Canvas (True Per-Frame Animatable Modifier)

private struct LiquidMetaballModifier: ViewModifier, Animatable {
    var mainWidth: CGFloat
    var mainHeight: CGFloat
    var mainCornerRadius: CGFloat
    var topEarRadius: CGFloat
    var topOffset: CGFloat
    var mainOffsetX: CGFloat
    var bubbleSeparation: CGFloat
    var targetBubbleDiameter: CGFloat
    var detachedGap: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(mainWidth, mainHeight), AnimatablePair(mainCornerRadius, topEarRadius)),
                AnimatablePair(AnimatablePair(topOffset, mainOffsetX), AnimatablePair(bubbleSeparation, targetBubbleDiameter))
            )
        }
        set {
            mainWidth = newValue.first.first.first
            mainHeight = newValue.first.first.second
            mainCornerRadius = newValue.first.second.first
            topEarRadius = newValue.first.second.second
            topOffset = newValue.second.first.first
            mainOffsetX = newValue.second.first.second
            bubbleSeparation = newValue.second.second.first
            targetBubbleDiameter = newValue.second.second.second
        }
    }

    func body(content: Content) -> some View {
        if bubbleSeparation <= 0.002 {
            Color.clear
        } else {
            Canvas { context, size in
                let mainX = (size.width - mainWidth) / 2.0 + mainOffsetX
                let mainRect = CGRect(x: mainX, y: topOffset, width: mainWidth, height: mainHeight)

                context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                context.addFilter(.blur(radius: 8))
                context.drawLayer { layer in
                    let bleed: CGFloat = (topEarRadius > 0.25 && topOffset <= 2.0) ? 16.0 : 0.0
                    let mainPath = NotchShape.path(
                        in: mainRect,
                        topCornerRadius: topEarRadius,
                        bottomCornerRadius: mainCornerRadius,
                        bleedAboveTop: bleed
                    )
                    layer.fill(mainPath, with: .color(.black))

                    if targetBubbleDiameter > 1.0 {
                        let travel = detachedGap + targetBubbleDiameter
                        let startCenterX = mainRect.maxX - topEarRadius - targetBubbleDiameter / 2.0
                        let bubbleCenterX = startCenterX + bubbleSeparation * travel
                        let bubbleCenterY = mainRect.midY
                        let diameter = targetBubbleDiameter * min(max(bubbleSeparation * 1.15, 0.35), 1.0)
                        let bubbleRect = CGRect(
                            x: bubbleCenterX - diameter / 2.0,
                            y: bubbleCenterY - diameter / 2.0,
                            width: diameter,
                            height: diameter
                        )
                        layer.fill(Path(ellipseIn: bubbleRect), with: .color(.black))
                    }
                }
            }
            .clipped()
        }
    }
}

// MARK: - 5-Bar CoreAnimation WindowServer-Offloaded Visualizer (Zero App CPU Drain)

private final class WaveformContainerView: NSView {
    private let barLayers: [CAGradientLayer] = (0..<5).map { _ in CAGradientLayer() }

    private var currentIsPlaying: Bool = false
    private var currentBarWidth: CGFloat = 1.6
    private var currentSpacing: CGFloat = 1.6
    private var currentMinHeight: CGFloat = 2.5
    private var currentMaxHeight: CGFloat = 12.0
    private var lastTopColor: Color?
    private var lastBottomColor: Color?
    private var hasConfiguredAnimations: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.masksToBounds = false
        layer = rootLayer

        for barLayer in barLayers {
            barLayer.cornerCurve = .continuous
            barLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
            barLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.masksToBounds = true
            rootLayer.addSublayer(barLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: 5.0 * currentBarWidth + 4.0 * currentSpacing,
            height: currentMaxHeight
        )
    }

    override func layout() {
        super.layout()
        layoutBars()
    }

    private func layoutBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let centerY = bounds.height > 0 ? bounds.midY : currentMaxHeight / 2.0
        for (idx, barLayer) in barLayers.enumerated() {
            let x = CGFloat(idx) * (currentBarWidth + currentSpacing)
            barLayer.position = CGPoint(x: x + currentBarWidth / 2.0, y: centerY)
            barLayer.cornerRadius = currentBarWidth / 2.0
            let activeHeight = currentIsPlaying ? barLayer.bounds.height : currentMinHeight
            barLayer.bounds = CGRect(
                x: 0,
                y: 0,
                width: currentBarWidth,
                height: max(activeHeight, currentMinHeight)
            )
        }
        CATransaction.commit()
    }

    func update(
        topColor: Color,
        bottomColor: Color,
        isPlaying: Bool,
        barWidth: CGFloat,
        spacing: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat
    ) {
        let geometryChanged = (currentBarWidth != barWidth)
            || (currentSpacing != spacing)
            || (currentMinHeight != minHeight)
            || (currentMaxHeight != maxHeight)
        let playbackChanged = (currentIsPlaying != isPlaying)

        if geometryChanged {
            currentBarWidth = barWidth
            currentSpacing = spacing
            currentMinHeight = minHeight
            currentMaxHeight = maxHeight
            invalidateIntrinsicContentSize()
            layoutBars()
        }

        if lastTopColor != topColor || lastBottomColor != bottomColor {
            lastTopColor = topColor
            lastBottomColor = bottomColor
            let topCG = NSColor(topColor).cgColor
            let bottomCG = NSColor(bottomColor).cgColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for barLayer in barLayers {
                barLayer.colors = [topCG, bottomCG]
            }
            CATransaction.commit()
        }

        if playbackChanged || geometryChanged || !hasConfiguredAnimations {
            currentIsPlaying = isPlaying
            hasConfiguredAnimations = true
            applyAnimationState()
        }
    }

    private func applyAnimationState() {
        let envelopes: [CGFloat] = [0.70, 0.88, 1.0, 0.88, 0.70]
        let durations: [CFTimeInterval] = [0.82, 0.64, 0.92, 0.58, 0.74]
        let amplitudeCurves: [[CGFloat]] = [
            [0.25, 0.92, 0.45, 0.78, 0.30, 0.25],
            [0.55, 0.30, 0.98, 0.42, 0.84, 0.55],
            [0.85, 0.35, 0.72, 1.00, 0.40, 0.85],
            [0.35, 0.96, 0.48, 0.82, 0.28, 0.35],
            [0.65, 0.28, 0.88, 0.38, 0.95, 0.65]
        ]

        if !currentIsPlaying {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for barLayer in barLayers {
                barLayer.removeAnimation(forKey: "waveformBounce")
                barLayer.bounds = CGRect(x: 0, y: 0, width: currentBarWidth, height: currentMinHeight)
            }
            CATransaction.commit()
            return
        }

        let range = max(currentMaxHeight - currentMinHeight, 0.5)
        for (idx, barLayer) in barLayers.enumerated() {
            barLayer.removeAnimation(forKey: "waveformBounce")
            let values: [NSNumber] = amplitudeCurves[idx].map { frac in
                NSNumber(value: Double(currentMinHeight + range * frac * envelopes[idx]))
            }
            let anim = CAKeyframeAnimation(keyPath: "bounds.size.height")
            anim.values = values
            anim.keyTimes = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
            anim.calculationMode = .cubic
            anim.duration = durations[idx]
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            barLayer.add(anim, forKey: "waveformBounce")
        }
    }
}

private struct WaveformCARepresentable: NSViewRepresentable {
    let topColor: Color
    let bottomColor: Color
    let isPlaying: Bool
    let barWidth: CGFloat
    let spacing: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func makeNSView(context: Context) -> WaveformContainerView {
        let view = WaveformContainerView(frame: NSRect(
            x: 0,
            y: 0,
            width: 5.0 * barWidth + 4.0 * spacing,
            height: maxHeight
        ))
        view.update(
            topColor: topColor,
            bottomColor: bottomColor,
            isPlaying: isPlaying,
            barWidth: barWidth,
            spacing: spacing,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
        return view
    }

    func updateNSView(_ nsView: WaveformContainerView, context: Context) {
        nsView.update(
            topColor: topColor,
            bottomColor: bottomColor,
            isPlaying: isPlaying,
            barWidth: barWidth,
            spacing: spacing,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }
}

private struct HarmonicWaveformView: View {
    let topColor: Color
    let bottomColor: Color
    let isPlaying: Bool
    let barWidth: CGFloat
    let spacing: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        WaveformCARepresentable(
            topColor: topColor,
            bottomColor: bottomColor,
            isPlaying: isPlaying,
            barWidth: barWidth,
            spacing: spacing,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
        .frame(width: 5.0 * barWidth + 4.0 * spacing, height: maxHeight)
    }
}

// MARK: - Native QuickLook Share Picker Button

private struct SharePickerButton: NSViewRepresentable {
    let item: ShelfItem

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .circular
        btn.isBordered = false
        btn.focusRingType = .none
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        btn.title = ""
        btn.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        btn.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.clicked(_:))
        return btn
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.item = item
    }

    func makeCoordinator() -> Coordinator { Coordinator(item: item) }

    @MainActor
    final class Coordinator: NSObject {
        var item: ShelfItem
        init(item: ShelfItem) { self.item = item }

        @objc func clicked(_ sender: NSButton) {
            FileShelfManager.shared.shareItem(item, from: sender)
        }
    }
}

// MARK: - Main IslandView

public struct IslandView: View {
    @ObservedObject var controller: IslandWindowController
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @ObservedObject var batteryMonitor = BatteryMonitor.shared
    @ObservedObject var audioMonitor = AudioDeviceMonitor.shared
    @ObservedObject var shelfManager = FileShelfManager.shared
    @ObservedObject var privacyMonitor = PrivacyMonitor.shared

    @Namespace private var islandNamespace
    @State private var dragOffset: CGFloat = 0
    @State private var isDropTargeted: Bool = false
    @State private var isScrubberHovered: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var airPodsPulse: Bool = false
    @State private var artworkFlipAngle: Double = 0
    @State private var artworkFlipScale: CGFloat = 1.0
    @State private var displayedArtwork: NSImage? = nil
    @State private var artworkFlipTask: Task<Void, Never>? = nil
    @State private var lockLatchAnimated: Bool = false

    public var screenMetrics: ScreenNotchMetrics?

    private var effectiveNotchWidth: CGFloat {
        screenMetrics?.notchWidth ?? controller.notchWidth
    }

    private var effectiveNotchHeight: CGFloat {
        screenMetrics?.notchHeight ?? controller.notchHeight
    }

    private var trackSignature: String {
        "\(nowPlaying.currentTrack.title)-\(nowPlaying.currentTrack.artist)"
    }

    public init(controller: IslandWindowController, screenMetrics: ScreenNotchMetrics? = nil) {
        self.controller = controller
        self.screenMetrics = screenMetrics
    }

    public var body: some View {
        let state = controller.metaballState(for: screenMetrics)
        let activeSpring = controller.lastTransitionSpring.animation
        let isExpandedState = controller.presentationMode.isExpandedMode
        let mainRect = state.mainCanvasRect()

        ZStack(alignment: .top) {
            // Layer 1: Pure Pitch-Black Liquid Metaball Canvas (#000000) + Razor-Sharp Vector Silhouette
            ZStack {
                Color.clear
                    .modifier(
                        LiquidMetaballModifier(
                            mainWidth: state.mainSize.width,
                            mainHeight: state.mainSize.height,
                            mainCornerRadius: state.mainCornerRadius,
                            topEarRadius: state.topEarRadius,
                            topOffset: state.topOffset,
                            mainOffsetX: state.mainOffsetX,
                            bubbleSeparation: state.isSplit ? 1.0 : 0.0,
                            targetBubbleDiameter: max(state.detachedBubbleDiameter, state.mainSize.height),
                            detachedGap: max(state.detachedGap, 6)
                        )
                    )
                    .ignoresSafeArea()

                NotchShape(topCornerRadius: state.topEarRadius, bottomCornerRadius: state.mainCornerRadius)
                    .fill(Color.black)
                    .frame(width: state.mainSize.width, height: state.mainSize.height)
                    .position(x: mainRect.midX, y: mainRect.midY)
            }
            .frame(width: MetaballSplitState.canvasWidth, height: MetaballSplitState.canvasHeight)
            .shadow(
                color: Color.black.opacity(isExpandedState ? 0.45 : (state.isFloatingPill ? 0.34 : 0.0)),
                radius: isExpandedState ? 22 : 10,
                x: 0,
                y: isExpandedState ? 8 : 4
            )

            // Layer 2: Bottom-only Specular Rim Stroke (0.0 across top 40% -> 100% invisible top bezel seam)
            borderHighlightOverlay(state: state, mainRect: mainRect, isExpandedState: isExpandedState)

            // Layer 3: Active Presentation Content clipped strictly inside the silhouette
            ZStack {
                activeMainContent(state: state)
            }
            .frame(width: state.mainSize.width, height: state.mainSize.height)
            .clipShape(NotchShape(topCornerRadius: state.topEarRadius, bottomCornerRadius: state.mainCornerRadius))
            .position(x: mainRect.midX, y: mainRect.midY)

            // Layer 4: Detached Circular Metaball Bubble (Dual Active Activity Split)
            if state.isSplit,
               let bubbleRect = state.detachedCanvasRect(),
               let secondary = state.secondaryActivity {
                detachedBubbleContent(secondary: secondary)
                    .frame(width: bubbleRect.width, height: bubbleRect.height)
                    .clipShape(Circle())
                    .position(x: bubbleRect.midX, y: bubbleRect.midY)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }

            // Layer 5: Hardware Privacy Dots (Green Camera / Orange Mic) in Compact/Idle Trailing Wing
            if privacyMonitor.isAnyActive && !isExpandedState {
                privacyDotsOverlay(state: state, mainRect: mainRect)
            }
        }
        .frame(width: MetaballSplitState.canvasWidth, height: MetaballSplitState.canvasHeight)
        .ignoresSafeArea()
        .offset(x: dragOffset)
        .animation(activeSpring, value: controller.presentationMode)
        .animation(IslandSpringKind.idleStretch.animation, value: controller.isIdleStretched)
        .animation(activeSpring, value: state)
        .onAppear {
            displayedArtwork = nowPlaying.artworkImage
        }
        .onChange(of: trackSignature) { _, newSig in
            if !newSig.isEmpty && newSig != "-" {
                triggerArtwork3DFlip(to: nowPlaying.artworkImage)
            }
        }
        .onChange(of: nowPlaying.artworkImage) { _, newImage in
            if displayedArtwork !== newImage && artworkFlipTask == nil {
                if newImage != nil {
                    triggerArtwork3DFlip(to: newImage)
                } else {
                    displayedArtwork = nil
                }
            }
        }
        .onDrop(of: [.fileURL, .png, .tiff, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .gesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    if !isExpandedState {
                        dragOffset = value.translation.width * 0.22
                    }
                }
                .onEnded { value in
                    if isExpandedState && value.translation.height < -24 {
                        controller.collapse()
                    } else if controller.presentationMode.isTransientMode && abs(value.translation.width) > 30 {
                        controller.dismissTransientAlert()
                    } else if abs(value.translation.width) > 36 && !isExpandedState {
                        HapticEngine.perform(.generic)
                        if value.translation.width < 0 {
                            nowPlaying.nextTrack()
                        } else {
                            nowPlaying.previousTrack()
                        }
                    }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                        dragOffset = 0
                    }
                }
        )
    }

    // MARK: - Zero Top Seam Inner Border Gradient

    @ViewBuilder
    private func borderHighlightOverlay(state: MetaballSplitState, mainRect: CGRect, isExpandedState: Bool) -> some View {
        let isDropActive = isDropTargeted || controller.isDropHovered || controller.presentationMode == .compactDropZone
        let bottomStrokeGradient = LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.40),
                .init(color: Color.white.opacity(0.14), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        Group {
            if isDropActive {
                NotchOpenPerimeterShape(topCornerRadius: state.topEarRadius, bottomCornerRadius: state.mainCornerRadius)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.8, dash: [6, 4]))
                    .frame(width: state.mainSize.width, height: state.mainSize.height)
                    .position(x: mainRect.midX, y: mainRect.midY)
            } else if isExpandedState || state.isFloatingPill {
                NotchShape(topCornerRadius: state.topEarRadius, bottomCornerRadius: state.mainCornerRadius)
                    .stroke(bottomStrokeGradient, lineWidth: 0.5)
                    .frame(width: state.mainSize.width, height: state.mainSize.height)
                    .position(x: mainRect.midX, y: mainRect.midY)
            }
            if state.isSplit && state.isFloatingPill, let bubbleRect = state.detachedCanvasRect() {
                Circle()
                    .stroke(bottomStrokeGradient, lineWidth: 0.5)
                    .frame(width: bubbleRect.width, height: bubbleRect.height)
                    .position(x: bubbleRect.midX, y: bubbleRect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func privacyDotsOverlay(state: MetaballSplitState, mainRect: CGRect) -> some View {
        let isSteadyCompact = !state.isFloatingPill
            && !controller.presentationMode.isPopDownMode
            && !controller.presentationMode.isExpandedMode
            && controller.presentationMode != .idle
        let dotSize: CGFloat = isSteadyCompact ? 5.5 : 6.5
        let dotX: CGFloat = {
            if state.isFloatingPill {
                return mainRect.maxX - 10
            }
            if isSteadyCompact {
                return mainRect.midX + effectiveNotchWidth / 2.0 - 4
            }
            return mainRect.maxX - state.topEarRadius - 10
        }()
        let dotY: CGFloat = {
            if state.isFloatingPill {
                return mainRect.midY
            }
            if controller.presentationMode.isPopDownMode {
                return mainRect.minY + effectiveNotchHeight + 10
            }
            if isSteadyCompact {
                return mainRect.minY + 7
            }
            return mainRect.midY
        }()

        HStack(spacing: 4) {
            if privacyMonitor.isCameraActive {
                Circle()
                    .fill(Color(red: 0.188, green: 0.820, blue: 0.345))
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: Color.green.opacity(0.85), radius: 3)
            }
            if privacyMonitor.isMicActive {
                Circle()
                    .fill(Color(red: 1.0, green: 0.624, blue: 0.039))
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: Color.orange.opacity(0.85), radius: 3)
            }
        }
        .matchedGeometryEffect(id: "privacyDots", in: islandNamespace)
        .position(x: dotX, y: dotY)
        .transition(.scale(scale: 0.2).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    // MARK: - Presentation Mode Router

    @ViewBuilder
    private func activeMainContent(state: MetaballSplitState) -> some View {
        switch controller.presentationMode {
        case .idle:
            idleCapsule
        case .compactMusic:
            compactMusicPill(state: state).transition(.islandContentMorph)
        case .compactTrackChange(let track):
            compactTrackChangePill(track: track, state: state).transition(.islandContentMorph)
        case .compactBattery:
            compactBatteryPill(state: state, isLow: false).transition(.islandContentMorph)
        case .compactLowBattery:
            compactBatteryPill(state: state, isLow: true).transition(.islandContentMorph)
        case .compactLowPowerMode(let enabled):
            compactLowPowerModePill(enabled: enabled, state: state).transition(.islandContentMorph)
        case .compactVolume:
            compactVolumePill(state: state).transition(.islandContentMorph)
        case .compactMute:
            compactMutePill(state: state).transition(.islandContentMorph)
        case .compactAirPods:
            compactAirPodsPill(state: state).transition(.islandContentMorph)
        case .compactUnlock:
            compactUnlockPill(state: state).transition(.islandContentMorph)
        case .compactLockScreen:
            compactLockScreenPill(state: state).transition(.islandContentMorph)
        case .compactAlert(let info):
            compactAlertPill(info: info, state: state).transition(.islandContentMorph)
        case .compactFocus(let info):
            compactFocusPill(info: info, state: state).transition(.islandContentMorph)
        case .compactTimer(let info):
            compactTimerPill(info: info, state: state).transition(.islandContentMorph)
        case .compactDual(let track, _):
            compactDualMainPill(track: track, state: state).transition(.islandContentMorph)
        case .compactBrightness(let level):
            compactBrightnessPill(level: level, state: state).transition(.islandContentMorph)
        case .compactDropZone:
            compactDropZonePill(state: state).transition(.islandContentMorph)
        case .compactShelf(let count):
            compactShelfPill(count: count, state: state).transition(.islandContentMorph)
        case .expandedMusic:
            expandedMusicCard(state: state).transition(.islandCardMorph)
        case .expandedRoutes:
            expandedRoutesCard(state: state).transition(.islandCardMorph)
        case .expandedTimer(let info):
            expandedTimerCard(info: info, state: state).transition(.islandCardMorph)
        case .expandedFileShelf:
            expandedFileShelfCard(state: state).transition(.islandCardMorph)
        }
    }

    // MARK: - Wing & Pop-Down Toast Helpers (Zero Menu Bar Collision)

    @ViewBuilder
    private func compactWingRow<Left: View, Right: View>(
        state: MetaballSplitState,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(spacing: 0) {
            if state.isFloatingPill {
                left()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)

                Spacer(minLength: 8)

                right()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
            } else {
                left()
                    .padding(.leading, 8)
                    .frame(width: 28, height: effectiveNotchHeight, alignment: .leading)

                Color.clear
                    .frame(width: effectiveNotchWidth, height: effectiveNotchHeight)

                right()
                    .padding(.trailing, 8)
                    .frame(width: 28, height: effectiveNotchHeight, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func popDownToastRow<Content: View>(
        state: MetaballSplitState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            if !state.isFloatingPill {
                Color.clear
                    .frame(height: effectiveNotchHeight)
            }
            content()
                .padding(.horizontal, state.isFloatingPill ? 16 : (state.topEarRadius + 12))
                .frame(maxWidth: .infinity)
                .frame(height: state.isFloatingPill ? state.mainSize.height : MetaballSplitState.popDownToastExtraHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func artworkSquircle(size: CGFloat, radius: CGFloat) -> some View {
        let activeArtwork = displayedArtwork ?? nowPlaying.artworkImage
        let specularOpacity = abs(sin(artworkFlipAngle * .pi / 180.0)) * 0.35
        Group {
            if let art = activeArtwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(specularOpacity),
                                Color.white.opacity(specularOpacity * 0.25),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 0.5)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                        .frame(width: size, height: size)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .scaleEffect(artworkFlipScale)
        .rotation3DEffect(
            .degrees(artworkFlipAngle),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.45
        )
        .matchedGeometryEffect(id: "mediaArtwork", in: islandNamespace)
    }

    // MARK: - 1. Idle State (Elastic Micro-Stretch Only, Never Opens Empty Panel)

    private var idleCapsule: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                controller.triggerIdleElasticBounce()
            }
            .onLongPressGesture(minimumDuration: 0.18, pressing: { pressing in
                controller.isIdlePressedBounce = pressing
                if pressing {
                    HapticEngine.perform(.alignment)
                }
            }, perform: {
                controller.triggerIdleElasticBounce()
            })
    }

    // MARK: - 2. Compact Media Wing & Dual Split

    private func compactMusicPill(state: MetaballSplitState) -> some View {
        compactWingRow(state: state) {
            artworkSquircle(size: 18, radius: 5)
        } right: {
            HarmonicWaveformView(
                topColor: nowPlaying.accentTopColor,
                bottomColor: nowPlaying.accentBottomColor,
                isPlaying: nowPlaying.currentTrack.isPlaying,
                barWidth: 1.6,
                spacing: 1.6,
                minHeight: 2.5,
                maxHeight: 12.0
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            controller.isPinned = true
            controller.presentationMode = .expandedMusic
            HapticEngine.perform(.generic)
        }
    }

    private func compactDualMainPill(track: MediaTrack, state: MetaballSplitState) -> some View {
        compactWingRow(state: state) {
            artworkSquircle(size: 18, radius: 5)
        } right: {
            HarmonicWaveformView(
                topColor: nowPlaying.accentTopColor,
                bottomColor: nowPlaying.accentBottomColor,
                isPlaying: track.isPlaying,
                barWidth: 1.6,
                spacing: 1.6,
                minHeight: 2.5,
                maxHeight: 12.0
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            controller.isPinned = true
            controller.presentationMode = .expandedMusic
            HapticEngine.perform(.generic)
        }
    }

    @ViewBuilder
    private func detachedBubbleContent(secondary: SecondaryBubbleKind) -> some View {
        switch secondary {
        case .timer(let timer):
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.22), lineWidth: 2.5)
                    .frame(width: 24, height: 24)
                Circle()
                    .trim(from: 0, to: CGFloat(timer.remainingFraction))
                    .stroke(Color(red: 1.0, green: 0.624, blue: 0.039), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 24, height: 24)
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.624, blue: 0.039))
                    .matchedGeometryEffect(id: "timerIcon", in: islandNamespace)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
            .onTapGesture {
                controller.isPinned = true
                controller.presentationMode = .expandedTimer(timer)
                HapticEngine.perform(.generic)
            }
        }
    }

    private func compactTrackChangePill(track: MediaTrack, state: MetaballSplitState) -> some View {
        popDownToastRow(state: state) {
            HStack(spacing: 10) {
                artworkSquircle(size: 24, radius: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                }
                .id(trackSignature)
                .transition(.asymmetric(
                    insertion: .push(from: .trailing).combined(with: .opacity),
                    removal: .push(from: .leading).combined(with: .opacity)
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

                HarmonicWaveformView(
                    topColor: nowPlaying.accentTopColor,
                    bottomColor: nowPlaying.accentBottomColor,
                    isPlaying: track.isPlaying,
                    barWidth: 2.0,
                    spacing: 2.2,
                    minHeight: 3.0,
                    maxHeight: 16.0
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            controller.isPinned = true
            controller.presentationMode = .expandedMusic
            HapticEngine.perform(.generic)
        }
    }

    // MARK: - 3. Transient Pop-Down HUDs (Zero Menu Bar Overlap)

    private func compactBatteryPill(state: MetaballSplitState, isLow: Bool) -> some View {
        let isCharging = batteryMonitor.currentBattery.isCharging || batteryMonitor.currentBattery.isPluggedIn
        let green = Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
        let red = Color(red: 1.0, green: 0.271, blue: 0.227)     // #FF453A
        let label = isLow ? "Low Battery" : (isCharging ? "Charging" : "On Battery")
        let tint: Color = isLow ? red : (isCharging ? green : .white)
        let timeRemaining = batteryMonitor.currentBattery.timeRemainingFormatted

        return popDownToastRow(state: state) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0.5) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !timeRemaining.isEmpty {
                        Text(timeRemaining)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.60))
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(batteryMonitor.currentBattery.percentage)%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                        .fixedSize()

                    AppleBatteryGlyph(
                        percentage: batteryMonitor.currentBattery.percentage,
                        isCharging: isCharging,
                        isLow: isLow
                    )
                }
            }
        }
    }

    private func compactLowPowerModePill(enabled: Bool, state: MetaballSplitState) -> some View {
        popDownToastRow(state: state) {
            HStack(spacing: 8) {
                Image(systemName: "battery.50")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.yellow)

                Spacer()

                Text(enabled ? "Low Power On" : "Low Power Off")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? .yellow : .white)
                    .fixedSize()
            }
        }
    }

    private func compactVolumePill(state: MetaballSplitState) -> some View {
        let isMuted = audioMonitor.isMuted || audioMonitor.currentVolume == 0
        let red = Color(red: 1.0, green: 0.271, blue: 0.227)
        let pct = Int((audioMonitor.currentVolume * 100).rounded())

        return popDownToastRow(state: state) {
            HStack(spacing: 10) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isMuted ? red : .white)
                    .contentTransition(.symbolEffect(.replace))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.20))
                            .frame(height: 5)
                        Capsule()
                            .fill(isMuted ? red : Color.white.opacity(0.92))
                            .frame(width: max(geo.size.width * CGFloat(audioMonitor.currentVolume), 5), height: 5)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let pct = Float32(min(max(value.location.x / max(geo.size.width, 1), 0), 1))
                                audioMonitor.setVolume(pct)
                                controller.extendTransientAlert(duration: 2.0)
                            }
                            .onEnded { _ in
                                SoundManager.shared.playThrottled("volume", minInterval: 0.08)
                                HapticEngine.perform(.generic)
                            }
                    )
                }
                .frame(height: 16)

                Text("\(pct)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText())
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private var volumeIcon: String {
        let v = audioMonitor.currentVolume
        if audioMonitor.isMuted || v == 0 { return "speaker.slash.fill" }
        if v < 0.33 { return "speaker.wave.1.fill" }
        if v < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func compactMutePill(state: MetaballSplitState) -> some View {
        let red = Color(red: 1.0, green: 0.271, blue: 0.227)
        return popDownToastRow(state: state) {
            HStack(spacing: 8) {
                Image(systemName: audioMonitor.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(audioMonitor.isMuted ? red : .white)
                    .contentTransition(.symbolEffect(.replace))
                Spacer()
                Text(audioMonitor.isMuted ? "Muted" : "Sound")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(audioMonitor.isMuted ? red : .white)
                    .fixedSize()
            }
        }
    }

    private func compactBrightnessPill(level: Int, state: MetaballSplitState) -> some View {
        popDownToastRow(state: state) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.yellow)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.20))
                            .frame(height: 5)
                        Capsule()
                            .fill(Color.yellow)
                            .frame(width: max(geo.size.width * (CGFloat(level) / 100.0), 5), height: 5)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let pct = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                                audioMonitor.setBrightness(Int((pct * 100.0).rounded()))
                                controller.extendTransientAlert(duration: 2.0)
                            }
                            .onEnded { _ in
                                HapticEngine.perform(.generic)
                            }
                    )
                }
                .frame(height: 16)

                Text("\(level)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.numericText())
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    private func compactAirPodsPill(state: MetaballSplitState) -> some View {
        let batteryLevel = audioMonitor.currentHeadphonesBatteryLevel ?? 100
        let ringProgress = CGFloat(min(max(batteryLevel, 0), 100)) / 100.0
        let green = Color(red: 0.188, green: 0.820, blue: 0.345)

        return popDownToastRow(state: state) {
            HStack(spacing: 8) {
                Image(systemName: audioMonitor.currentRouteIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(airPodsPulse ? 1.12 : 0.94)
                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: airPodsPulse)
                    .onAppear { airPodsPulse = true }
                    .onDisappear { airPodsPulse = false }

                Spacer()

                HStack(spacing: 6) {
                    Text(audioMonitor.currentHeadphonesBatteryLevel != nil ? "\(batteryLevel)%" : "Connected")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .fixedSize()

                    ZStack {
                        Circle().stroke(green.opacity(0.24), lineWidth: 2.5).frame(width: 20, height: 20)
                        Circle()
                            .trim(from: 0, to: ringProgress)
                            .stroke(green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                    }
                }
            }
        }
    }

    private func compactLockScreenPill(state: MetaballSplitState) -> some View {
        compactWingRow(state: state) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(lockLatchAnimated ? 0.14 : 0.06))
                    .frame(width: 18, height: 18)
                Image(systemName: lockLatchAnimated ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(lockLatchAnimated ? 1.0 : 0.85)
            }
            .onAppear {
                lockLatchAnimated = false
                withAnimation(.spring(response: 0.36, dampingFraction: 0.7)) {
                    lockLatchAnimated = true
                }
            }
            .onDisappear { lockLatchAnimated = false }
        } right: {
            Circle()
                .fill(Color.orange.opacity(0.55))
                .frame(width: 5, height: 5)
        }
    }

    private func compactUnlockPill(state: MetaballSplitState) -> some View {
        let green = Color(red: 0.188, green: 0.820, blue: 0.345)
        return popDownToastRow(state: state) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(green.opacity(lockLatchAnimated ? 0.85 : 0.2), lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .scaleEffect(lockLatchAnimated ? 1.0 : 0.72)
                    Image(systemName: lockLatchAnimated ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(green)
                        .contentTransition(.symbolEffect(.replace))
                        .scaleEffect(lockLatchAnimated ? 1.08 : 0.88)
                }
                .onAppear {
                    lockLatchAnimated = false
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.65)) {
                        lockLatchAnimated = true
                    }
                }
                .onDisappear { lockLatchAnimated = false }

                Spacer()

                Text("Unlocked")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
    }

    private func compactFocusPill(info: FocusInfo, state: MetaballSplitState) -> some View {
        popDownToastRow(state: state) {
            HStack(spacing: 8) {
                Image(systemName: info.iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.indigo)
                Spacer()
                HStack(spacing: 4) {
                    Text(info.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.isOn ? "On" : "Off")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(info.isOn ? .indigo : .gray)
                }
            }
        }
    }

    private func compactAlertPill(info: SystemAlertInfo, state: MetaballSplitState) -> some View {
        popDownToastRow(state: state) {
            HStack(spacing: 10) {
                Image(systemName: info.iconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(alertColor(info.iconColor))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(info.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !info.subtitle.isEmpty {
                        Text(info.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - 4. Compact & Expanded Timer Live Activity

    private func compactTimerPill(info: TimerInfo, state: MetaballSplitState) -> some View {
        let orange = Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A

        return compactWingRow(state: state) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.24), lineWidth: 2)
                    .frame(width: 18, height: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(info.remainingFraction))
                    .stroke(orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                Image(systemName: "timer")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(orange)
                    .matchedGeometryEffect(id: "timerIcon", in: islandNamespace)
            }
        } right: {
            Text(info.formattedRemaining)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(orange)
                .contentTransition(.numericText(countsDown: true))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            controller.isPinned = true
            controller.presentationMode = .expandedTimer(info)
            HapticEngine.perform(.generic)
        }
    }

    private func expandedTimerCard(info: TimerInfo, state: MetaballSplitState) -> some View {
        let orange = Color(red: 1.0, green: 0.624, blue: 0.039) // #FF9F0A
        let topPad = MetaballSplitState.expandedContentTopPadding(notchHeight: effectiveNotchHeight, isFloatingPill: state.isFloatingPill)

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // Left: Pause/Resume, +1m, Cancel
                HStack(spacing: 8) {
                    Button(action: { TimerManager.shared.togglePause() }) {
                        ZStack {
                            Circle()
                                .fill(orange.opacity(0.22))
                                .frame(width: 40, height: 40)
                            Image(systemName: info.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(orange)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()

                    Button(action: { TimerManager.shared.addMinute() }) {
                        ZStack {
                            Circle()
                                .fill(orange.opacity(0.16))
                                .frame(width: 40, height: 40)
                            Text("+1m")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(orange)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()

                    Button(action: {
                        TimerManager.shared.stopTimer()
                        controller.collapse()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }

                Spacer()

                // Right: Progress ring + Label + Large #FF9F0A Countdown
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .stroke(Color.orange.opacity(0.25), lineWidth: 2)
                                .frame(width: 11, height: 11)
                            Circle()
                                .trim(from: 0, to: CGFloat(info.remainingFraction))
                                .stroke(orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 11, height: 11)
                        }
                        Text(info.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    Text(info.formattedRemaining)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(orange)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .padding(.top, topPad)
            .padding(.horizontal, state.isFloatingPill ? 18 : (state.topEarRadius + 16))
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 5. 1:1 Apple Music Live Activity Card (350 x notchHeight+132)

    private func expandedMusicCard(state: MetaballSplitState) -> some View {
        let rowTopPad = MetaballSplitState.expandedContentTopPadding(notchHeight: effectiveNotchHeight, isFloatingPill: state.isFloatingPill)
        let horizontalPad = state.isFloatingPill ? 18.0 : (state.topEarRadius + 16.0)
        let isPlaying = nowPlaying.currentTrack.isPlaying

        return ZStack(alignment: .topLeading) {
            // Subtle saturated radial halo strictly behind the 56x56 album art (never washing out the #000000 OLED backdrop)
            if (displayedArtwork ?? nowPlaying.artworkImage) != nil {
                RadialGradient(
                    colors: [nowPlaying.glowColor.opacity(0.15), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: 55
                )
                .frame(width: 110, height: 110)
                .offset(x: horizontalPad + 28 - 55, y: rowTopPad + 28 - 55)
                .allowsHitTesting(false)
            }

            VStack(spacing: 8) {
                // Row 1: 56x56 Artwork (with 3D Flip), Track Title & Artist (Push Transition), Ultra-Slim 5-bar Visualizer
                HStack(alignment: .center, spacing: 12) {
                    Button(action: { nowPlaying.activateSourceApp() }) {
                        artworkSquircle(size: 56, radius: 13)
                            .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 2)
                            .scaleEffect(isPlaying ? 1.0 : 0.92)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isPlaying)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()

                    Button(action: { nowPlaying.activateSourceApp() }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nowPlaying.currentTrack.title.isEmpty ? "Not Playing" : nowPlaying.currentTrack.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(nowPlaying.currentTrack.artist.isEmpty ? "Spotify / Apple Music" : nowPlaying.currentTrack.artist)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        }
                        .id(trackSignature)
                        .transition(.asymmetric(
                            insertion: .push(from: .trailing).combined(with: .opacity),
                            removal: .push(from: .leading).combined(with: .opacity)
                        ))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .animation(.spring(response: 0.36, dampingFraction: 0.8), value: trackSignature)

                    HarmonicWaveformView(
                        topColor: nowPlaying.accentTopColor,
                        bottomColor: nowPlaying.accentBottomColor,
                        isPlaying: isPlaying,
                        barWidth: 2.0,
                        spacing: 2.2,
                        minHeight: 3.0,
                        maxHeight: 16.0
                    )
                }

                // Row 2: Inline Timestamp & Continuous Pill Scrubber (NO Knob Circle)
                HStack(spacing: 8) {
                    Text(formatTime(nowPlaying.currentTrack.position))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .contentTransition(.numericText())
                        .frame(width: 34, alignment: .leading)

                    GeometryReader { geo in
                        let trackHeight: CGFloat = (isScrubbing || isScrubberHovered) ? 7.0 : 4.5
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.20))
                                .frame(height: trackHeight)

                            let progress = nowPlaying.currentTrack.duration > 0
                                ? min(max(nowPlaying.currentTrack.position / nowPlaying.currentTrack.duration, 0), 1)
                                : 0

                            Capsule()
                                .fill(Color.white.opacity(0.90))
                                .frame(width: max(geo.size.width * progress, trackHeight), height: trackHeight)
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isScrubbing || isScrubberHovered)
                        .onHover { isScrubberHovered = $0 }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isScrubbing = true
                                    let pct = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                                    nowPlaying.beginInteractiveScrub(to: pct * nowPlaying.currentTrack.duration)
                                }
                                .onEnded { value in
                                    isScrubbing = false
                                    let pct = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                                    nowPlaying.commitInteractiveScrub(to: pct * nowPlaying.currentTrack.duration)
                                }
                        )
                    }
                    .frame(height: 12)

                    let remaining = max(nowPlaying.currentTrack.duration - nowPlaying.currentTrack.position, 0)
                    Text("-\(formatTime(remaining))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .contentTransition(.numericText())
                        .frame(width: 38, alignment: .trailing)
                }

                // Row 3: Centered Playback Controls + Far-Right AirPlay Glyph (.buttonStyle(.plain) only)
                ZStack {
                    HStack(spacing: 34) {
                        Button(action: {
                            HapticEngine.perform(.generic)
                            nowPlaying.previousTrack()
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 30)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()

                        Button(action: {
                            HapticEngine.perform(.generic)
                            nowPlaying.togglePlayPause()
                        }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 36, height: 32)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()

                        Button(action: {
                            HapticEngine.perform(.generic)
                            nowPlaying.nextTrack()
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 30)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }

                    HStack {
                        Spacer()
                        Button(action: {
                            HapticEngine.perform(.generic)
                            controller.isPinned = true
                            controller.presentationMode = .expandedRoutes
                        }) {
                            Image(systemName: "airplayaudio")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.70))
                                .frame(width: 30, height: 30)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                }
            }
            .padding(.top, rowTopPad)
            .padding(.horizontal, horizontalPad)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 6. AirPlay / Audio Route Picker

    private func expandedRoutesCard(state: MetaballSplitState) -> some View {
        let topPad = MetaballSplitState.expandedContentTopPadding(notchHeight: effectiveNotchHeight, isFloatingPill: state.isFloatingPill)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: {
                    HapticEngine.perform(.generic)
                    controller.presentationMode = .expandedMusic
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.70))
                        Text("Audio Output")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(audioMonitor.availableRoutes.prefix(4)) { route in
                    Button(action: { audioMonitor.setOutputRoute(to: route.id) }) {
                        HStack(spacing: 12) {
                            Image(systemName: route.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(route.isDefault ? .black : .white)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(route.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(route.isDefault ? .black : .white)
                                    .lineLimit(1)
                                if let battery = route.batteryText {
                                    Text(battery)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(route.isDefault ? .black.opacity(0.65) : .white.opacity(0.60))
                                }
                            }

                            Spacer()

                            if route.isDefault {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(route.isDefault ? Color.white : Color.white.opacity(0.11))
                        )
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }
        }
        .padding(.top, topPad)
        .padding(.horizontal, state.isFloatingPill ? 18 : (state.topEarRadius + 16))
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 7. Context-Only Drop Zone & Non-Empty File Shelf

    private func compactDropZonePill(state: MetaballSplitState) -> some View {
        popDownToastRow(state: state) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.cyan)
                Spacer()
                Text("Drop files to shelf")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan)
                    .fixedSize()
            }
        }
    }

    private func compactShelfPill(count: Int, state: MetaballSplitState) -> some View {
        compactWingRow(state: state) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 18, height: 18)
        } right: {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
        }
        .contentShape(Rectangle())
        .onTapGesture {
            controller.isPinned = true
            controller.presentationMode = .expandedFileShelf
            HapticEngine.perform(.generic)
        }
    }

    private func expandedFileShelfCard(state: MetaballSplitState) -> some View {
        let topPad = MetaballSplitState.expandedContentTopPadding(notchHeight: effectiveNotchHeight, isFloatingPill: state.isFloatingPill)
        return VStack(spacing: 6) {
            if shelfManager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(isDropTargeted ? .cyan : .white.opacity(0.35))
                    Text("Drop files here")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("Shelf • \(shelfManager.items.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))

                    Spacer()

                    Button(action: { shelfManager.clearAll() }) {
                        Text("Clear")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(shelfManager.items) { item in
                            HStack(spacing: 10) {
                                Image(nsImage: shelfManager.thumbnail(for: item))
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 34, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(item.sizeString)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.52))
                                }

                                Spacer()

                                HStack(spacing: 5) {
                                    Button(action: { shelfManager.copyPath(item) }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.75))
                                            .frame(width: 24, height: 24)
                                            .background(Color.white.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .focusEffectDisabled()

                                    Button(action: { shelfManager.revealInFinder(item) }) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.75))
                                            .frame(width: 24, height: 24)
                                            .background(Color.white.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .focusEffectDisabled()

                                    SharePickerButton(item: item)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Circle())

                                    Button(action: { shelfManager.removeFile(id: item.id) }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.red.opacity(0.85))
                                            .frame(width: 24, height: 24)
                                            .background(Color.red.opacity(0.16))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .focusEffectDisabled()
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onDrag { NSItemProvider(object: item.url as NSURL) }
                            .onTapGesture(count: 2) { shelfManager.openItem(item) }
                        }
                    }
                }
            }
        }
        .padding(.top, topPad)
        .padding(.horizontal, state.isFloatingPill ? 18 : (state.topEarRadius + 16))
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 3D Artwork Flip & Drop Helpers

    private func triggerArtwork3DFlip(to image: NSImage?) {
        artworkFlipTask?.cancel()
        withAnimation(.easeIn(duration: 0.14)) {
            artworkFlipAngle = 90
            artworkFlipScale = 0.86
        }
        artworkFlipTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedArtwork = nowPlaying.artworkImage ?? image
                artworkFlipAngle = -90
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                artworkFlipAngle = 0
                artworkFlipScale = 1.0
            }
            artworkFlipTask = nil
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    Task { @MainActor in
                        shelfManager.addFile(url)
                        controller.isPinned = true
                        controller.presentationMode = .expandedFileShelf
                    }
                }
                accepted = true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage else { return }
                    Task { @MainActor in
                        shelfManager.addDroppedImage(img)
                        controller.isPinned = true
                        controller.presentationMode = .expandedFileShelf
                    }
                }
                accepted = true
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { str, _ in
                    guard let text = str else { return }
                    Task { @MainActor in
                        shelfManager.addTextSnippet(text)
                        controller.isPinned = true
                        controller.presentationMode = .expandedFileShelf
                    }
                }
                accepted = true
            }
        }
        return accepted
    }

    private func alertColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "green": return Color(red: 0.188, green: 0.820, blue: 0.345)
        case "yellow": return .yellow
        case "red": return Color(red: 1.0, green: 0.271, blue: 0.227)
        case "blue": return .blue
        case "orange": return Color(red: 1.0, green: 0.624, blue: 0.039)
        case "purple": return .purple
        case "cyan": return .cyan
        default: return .white
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN, !seconds.isInfinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
