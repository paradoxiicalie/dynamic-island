import AppKit
import SwiftUI

public struct IslandView: View {
    @ObservedObject var nowPlaying = NowPlayingManager.shared
    @ObservedObject var batteryMonitor = BatteryMonitor.shared
    @ObservedObject var audioMonitor = AudioDeviceMonitor.shared
    @ObservedObject var shelfManager = FileShelfManager.shared
    @ObservedObject var privacyMonitor = PrivacyMonitor.shared

    @Binding var presentationMode: IslandPresentationMode
    public var notchWidth: CGFloat = 180
    public var notchHeight: CGFloat = 32

    // Audio bar animation states matching authentic Apple SystemAperture
    @State private var compactBars: [CGFloat] = [4, 8, 14, 16, 11, 5]
    @State private var expandedBars: [CGFloat] = [7, 15, 22, 14, 6]
    @State private var waveformTimer: Timer?

    // Touch & Hold (Long-press) physics matching iOS rubber-band compression
    @State private var isPressed: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDropTargeted: Bool = false

    public init(presentationMode: Binding<IslandPresentationMode>, notchWidth: CGFloat = 180, notchHeight: CGFloat = 32) {
        self._presentationMode = presentationMode
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Solid Apple true-black background capsule strictly locked to current window frame
                RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                    .fill(Color.black)

                // 2. Active presentation content strictly clipped inside the capsule
                ZStack {
                    switch presentationMode {
                    case .idle:
                        idleCapsule
                    case .compactMusic:
                        compactMusicPill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactTrackChange(let track):
                        compactTrackChangePill(track: track)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactBattery:
                        compactBatteryPill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactLowBattery:
                        compactLowBatteryPill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactVolume:
                        compactVolumePill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactMute:
                        compactMutePill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactAirPods:
                        compactAirPodsPill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactUnlock:
                        compactUnlockPill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactLockScreen:
                        compactLockScreenPill
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactAlert(let info):
                        compactAlertPill(info: info)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactFocus(let info):
                        compactFocusPill(info: info)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactTimer(let info):
                        compactTimerPill(info: info)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactDual(let track, let timer):
                        compactDualPill(track: track, timer: timer)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .compactBrightness(let level):
                        compactBrightnessPill(level: level)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    case .expandedMusic:
                        expandedMusicCard
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    case .expandedBattery:
                        expandedBatteryCard
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    case .expandedRoutes:
                        expandedRoutesCard
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    case .expandedTimer(let info):
                        expandedTimerCard(info: info)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    case .expandedFileShelf:
                        expandedFileShelfCard
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                    .stroke(isDropTargeted ? Color.cyan : Color.white.opacity(0.10), style: isDropTargeted ? StrokeStyle(lineWidth: 2, dash: [6, 4]) : StrokeStyle(lineWidth: 0.5))
            )
            .overlay(
                Group {
                    if privacyMonitor.isAnyActive && !isCardExpanded {
                        Circle()
                            .fill(privacyMonitor.isCameraActive ? Color.green : Color.orange)
                            .frame(width: 6.5, height: 6.5)
                            .shadow(color: (privacyMonitor.isCameraActive ? Color.green : Color.orange).opacity(0.85), radius: 3)
                            .offset(x: 18, y: 0)
                    }
                }
            )
            .shadow(
                color: isCardExpanded ? Color.black.opacity(0.55) : Color.clear,
                radius: isCardExpanded ? 24 : 0,
                x: 0,
                y: isCardExpanded ? 8 : 0
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .offset(x: dragOffset)
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.82), value: presentationMode)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isPressed)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            var handled = false
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            FileShelfManager.shared.addFile(url)
                            presentationMode = .expandedFileShelf
                        }
                    }
                }
                handled = true
            }
            return handled
        }
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    dragOffset = value.translation.width * 0.25
                }
                .onEnded { value in
                    if abs(value.translation.width) > 35 {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        if value.translation.width < 0 {
                            nowPlaying.nextTrack()
                        } else {
                            nowPlaying.previousTrack()
                        }
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            updateWaveformState()
        }
        .onChange(of: presentationMode) { _ in
            updateWaveformState()
        }
        .onChange(of: nowPlaying.currentTrack.isPlaying) { _ in
            updateWaveformState()
        }
    }

    private var isCardExpanded: Bool {
        switch presentationMode {
        case .expandedMusic, .expandedRoutes, .expandedBattery, .expandedTimer, .expandedFileShelf:
            return true
        default:
            return false
        }
    }

    private var currentCornerRadius: CGFloat {
        switch presentationMode {
        case .idle, .compactMusic, .compactTrackChange, .compactBattery, .compactLowBattery, .compactVolume, .compactMute, .compactAirPods, .compactUnlock, .compactLockScreen, .compactAlert, .compactFocus, .compactTimer, .compactDual, .compactBrightness:
            return notchHeight / 2.0
        case .expandedMusic:
            return 38.0 // Refined Apple iOS Dynamic Island corner radius
        case .expandedBattery, .expandedRoutes, .expandedTimer, .expandedFileShelf:
            return 34.0
        }
    }

    // MARK: - 1. Idle Capsule
    private var idleCapsule: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                IslandWindowController.shared.toggleExpansion()
            }
            .onLongPressGesture(minimumDuration: 0.22, pressing: { pressing in
                self.isPressed = pressing
            }, perform: {
                IslandWindowController.shared.toggleExpansion()
            })
    }

    // MARK: - 2. Compact Music Pill (1:1 Apple iOS Dynamic Island)
    private var compactMusicPill: some View {
        HStack(spacing: 8) {
            // Compact Leading: Album Artwork Squircle (22x22, radius 6.5)
            Button(action: {
                activateSourceApp()
            }) {
                Group {
                    if let art = nowPlaying.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                            )
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 22, height: 22)
                            Image(systemName: "music.note")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 8)

            // Middle: Notch Spacer
            Spacer(minLength: notchWidth)

            // Compact Trailing: 6-bar Apple SystemAperture Waveform (Vertically Centered & Ultra-Crisp)
            HStack(spacing: 1.8) {
                ForEach(0..<6, id: \.self) { idx in
                    Capsule()
                        .fill(nowPlaying.waveformGradient)
                        .frame(width: 1.7, height: compactBars[idx])
                        .animation(.easeInOut(duration: 0.16), value: compactBars)
                }
            }
            .padding(.trailing, 11)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap on the notch displays the expanded info card
            IslandWindowController.shared.toggleExpansion()
        }
        .onLongPressGesture(minimumDuration: 0.22, pressing: { pressing in
            self.isPressed = pressing
        }, perform: {
            IslandWindowController.shared.toggleExpansion()
        })
    }

    // MARK: - 2b. Compact Track Change Banner (Apple iOS slide-in title)
    private func compactTrackChangePill(track: MediaTrack) -> some View {
        HStack(spacing: 6) {
            // Leading Left Wing: Artwork + Title & Artist
            HStack(spacing: 7) {
                Group {
                    if let art = nowPlaying.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                            )
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 22, height: 22)
                            Image(systemName: "music.note")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0.5) {
                    Text(track.title)
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(track.artist)
                        .font(.system(size: 9, weight: .medium, design: .default))
                        .foregroundColor(Color.white.opacity(0.68))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 84, alignment: .leading)
            }
            .padding(.leading, 8)

            // Middle: Clear spacer precisely matching the physical notch
            Spacer(minLength: notchWidth)

            // Trailing Right Wing: 6-bar Apple SystemAperture Waveform (Vertically Centered & Ultra-Crisp)
            HStack(spacing: 1.8) {
                ForEach(0..<6, id: \.self) { idx in
                    Capsule()
                        .fill(nowPlaying.waveformGradient)
                        .frame(width: 1.7, height: compactBars[idx])
                        .animation(.easeInOut(duration: 0.16), value: compactBars)
                }
            }
            .padding(.trailing, 11)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            IslandWindowController.shared.toggleExpansion()
        }
    }

    // MARK: - 2c. Compact Lock Screen Pill (Apple iOS Lock Screen)
    private var compactLockScreenPill: some View {
        HStack {
            Image(systemName: "lock.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.85))
                .padding(.leading, 12)

            Spacer(minLength: notchWidth)

            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 4.5, height: 4.5)
                .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. Compact Battery Pill (iOS Style)
    private var compactBatteryPill: some View {
        HStack(spacing: 8) {
            // Compact Leading: Green battery bolt
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 20, height: 20)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            }
            .padding(.leading, 10)

            Spacer(minLength: notchWidth)

            // Compact Trailing: Percentage
            Text("\(batteryMonitor.currentBattery.percentage)%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.green)
                .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            presentationMode = .expandedBattery
        }
    }

    // MARK: - 4. Compact Volume Pill (iOS HUD Replacement)
    private var compactVolumePill: some View {
        HStack(spacing: 10) {
            // Left: Speaker glyph
            Image(systemName: volumeIcon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.leading, 10)

            Spacer(minLength: notchWidth)

            // Right: Volume Bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 50, height: 6)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(50 * CGFloat(audioMonitor.currentVolume), 4), height: 6)
            }
            .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    private var volumeIcon: String {
        let v = audioMonitor.currentVolume
        if v == 0 { return "speaker.slash.fill" }
        if v < 0.33 { return "speaker.wave.1.fill" }
        if v < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - 3b. Compact Low Battery Pill (iOS Warning)
    private var compactLowBatteryPill: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 20, height: 20)
                Image(systemName: "battery.25")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
            }
            .padding(.leading, 10)

            Spacer(minLength: notchWidth)

            Text("\(batteryMonitor.currentBattery.percentage)% Low Battery")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.red)
                .lineLimit(1)
                .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            presentationMode = .expandedBattery
        }
    }

    // MARK: - 4b. Compact Mute Pill
    private var compactMutePill: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(audioMonitor.isMuted ? Color.red.opacity(0.2) : Color.white.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: audioMonitor.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(audioMonitor.isMuted ? .red : .white)
            }
            .padding(.leading, 10)

            Spacer(minLength: notchWidth)

            Text(audioMonitor.isMuted ? "Muted" : "Sound")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(audioMonitor.isMuted ? .red : .white)
                .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 5b. Compact Unlock Pill (FaceID / TouchID Style)
    private var compactUnlockPill: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 20, height: 20)
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            }
            .padding(.leading, 12)

            Spacer(minLength: notchWidth)

            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                Text("Unlocked")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.trailing, 14)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 5c. Compact Alert Pill (Shortcuts / External Automation)
    private func compactAlertPill(info: SystemAlertInfo) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(alertColor(info.iconColor).opacity(0.2))
                    .frame(width: 20, height: 20)
                Image(systemName: info.iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(alertColor(info.iconColor))
            }
            .padding(.leading, 10)

            Spacer(minLength: notchWidth)

            VStack(alignment: .trailing, spacing: 0) {
                Text(info.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !info.subtitle.isEmpty {
                    Text(info.subtitle)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    private func alertColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        default: return .white
        }
    }

    // MARK: - 5. Compact AirPods Pill (iOS Connection Banner)
    private var compactAirPodsPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "airpodspro")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.leading, 12)

            Spacer(minLength: notchWidth)

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 11))
                Text("Connected")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 6. Expanded Music Card (Apple iOS 1:1 Dynamic Island)
    private var expandedMusicCard: some View {
        VStack(spacing: 0) {
            // Top Section: Artwork, Title, Artist, 5-bar Waveform
            HStack(alignment: .center, spacing: 12) {
                // Artwork: 46x46, cornerRadius 11
                Button(action: {
                    activateSourceApp()
                }) {
                    if let art = nowPlaying.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: Color.black.opacity(0.45), radius: 5, x: 0, y: 2)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color(white: 0.16))
                                .frame(width: 46, height: 46)
                            Image(systemName: "music.note")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                // Track and Artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.currentTrack.title.isEmpty ? "Not Playing" : nowPlaying.currentTrack.title)
                        .font(.system(size: 14.5, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(nowPlaying.currentTrack.artist.isEmpty ? "No active media" : nowPlaying.currentTrack.artist)
                        .font(.system(size: 12.5, weight: .regular, design: .default))
                        .foregroundColor(Color.white.opacity(0.60))
                        .lineLimit(1)
                }

                Spacer()

                // Header 5-bar Waveform (Apple signature - Vertically Centered & Crisp)
                HStack(spacing: 2.0) {
                    ForEach(0..<5, id: \.self) { idx in
                        Capsule()
                            .fill(nowPlaying.waveformGradient)
                            .frame(width: 2.0, height: expandedBars[idx])
                            .animation(.easeInOut(duration: 0.18), value: expandedBars)
                    }
                }
                .padding(.trailing, 2)
            }
            .padding(.horizontal, 18)

            Spacer().frame(height: 10)

            // Scrubber Row: Elapsed time, Progress Capsule, Remaining time
            HStack(spacing: 8) {
                Text(formatTime(nowPlaying.currentTrack.position))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.55))
                    .frame(width: 34, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 4.5)

                        let progress = nowPlaying.currentTrack.duration > 0
                            ? min(max(nowPlaying.currentTrack.position / nowPlaying.currentTrack.duration, 0.0), 1.0)
                            : 0.0

                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(geo.size.width * progress, 4.5), height: 4.5)
                    }
                    .frame(height: 4.5)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let pct = min(max(value.location.x / geo.size.width, 0.0), 1.0)
                                let targetTime = pct * nowPlaying.currentTrack.duration
                                nowPlaying.seek(to: targetTime)
                            }
                    )
                }
                .frame(height: 4.5)

                let remaining = max(nowPlaying.currentTrack.duration - nowPlaying.currentTrack.position, 0)
                Text("-\(formatTime(remaining))")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.55))
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 18)

            Spacer().frame(height: 12)

            // Bottom Controls Row: Prev, Bare Play/Pause, Next, Route Picker Button
            HStack {
                Spacer()

                // Center Playback Controls
                HStack(spacing: 32) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            nowPlaying.previousTrack()
                        }

                    Image(systemName: nowPlaying.currentTrack.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            nowPlaying.togglePlayPause()
                        }

                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                            nowPlaying.nextTrack()
                        }
                }

                Spacer()

                // Right Route Glyph (Tapping opens AirPlay / Route Sheet Screenshot 3)
                Image(systemName: audioMonitor.currentRouteIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.70))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        presentationMode = .expandedRoutes
                    }
                    .padding(.trailing, 16)
            }
            .padding(.bottom, 12)
        }
        .padding(.top, notchHeight + 6)
        .frame(width: 348, height: 148 + notchHeight)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height < -15 {
                    IslandWindowController.shared.collapse()
                }
            }
        )
    }

    // MARK: - 8. Expanded Audio Routes Sheet (Apple iOS 1:1 AirPlay Route Picker)
    private var routesCardHeight: CGFloat {
        let count = CGFloat(max(1, audioMonitor.availableRoutes.count))
        return notchHeight + 62 + (count * 44) + ((count - 1) * 6) + 14
    }

    private var expandedRoutesCard: some View {
        VStack(spacing: 8) {
            // Header: Small artwork, Title, Artist, and Close/Back Chevron
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    if let art = nowPlaying.artworkImage {
                        Image(nsImage: art)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(white: 0.16))
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.6)))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(nowPlaying.currentTrack.title.isEmpty ? "No active media" : nowPlaying.currentTrack.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(nowPlaying.currentTrack.artist)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.60))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    presentationMode = .expandedMusic
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.70))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .onTapGesture {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        presentationMode = .expandedMusic
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, notchHeight + 6)

            // Routes List (Matching Screenshot 3)
            VStack(spacing: 6) {
                ForEach(audioMonitor.availableRoutes) { route in
                    HStack(spacing: 12) {
                        Image(systemName: route.iconName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(route.isDefault ? .black : .white)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(route.isDefault ? .black : .white)
                                .lineLimit(1)

                            if let battery = route.batteryText {
                                HStack(spacing: 4) {
                                    Image(systemName: "battery.100")
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Text(battery)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(route.isDefault ? Color.black.opacity(0.65) : Color.white.opacity(0.60))
                            }
                        }

                        Spacer()

                        if route.isDefault {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(route.isDefault ? Color.white : Color.white.opacity(0.12))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture {
                        audioMonitor.setOutputRoute(to: route.id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 348, height: routesCardHeight)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height < -15 {
                    IslandWindowController.shared.collapse()
                }
            }
        )
    }

    // MARK: - 7. Expanded Battery Card (iOS Style)
    private var expandedBatteryCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(batteryMonitor.currentBattery.isCharging ? Color.green.opacity(0.2) : Color.yellow.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: batteryMonitor.currentBattery.isCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(batteryMonitor.currentBattery.isCharging ? .green : .yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(batteryMonitor.currentBattery.isCharging ? "Charging" : "On Battery")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)

                    Text(batteryMonitor.currentBattery.timeRemainingFormatted.isEmpty
                         ? (batteryMonitor.currentBattery.isPluggedIn ? "Connected to Power" : "Discharging")
                         : batteryMonitor.currentBattery.timeRemainingFormatted)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Text("\(batteryMonitor.currentBattery.percentage)%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(batteryMonitor.currentBattery.isCharging ? .green : .white)

                Button(action: {
                    let isPlaying = nowPlaying.currentTrack.isPlaying
                    presentationMode = isPlaying ? .compactMusic : .idle
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Battery Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 7)

                    let pct = min(max(Double(batteryMonitor.currentBattery.percentage) / 100.0, 0.0), 1.0)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: batteryMonitor.currentBattery.isCharging ? [Color.green, Color.mint] : [Color.yellow, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * pct, height: 7)
                }
            }
            .frame(height: 7)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .padding(.top, notchHeight + 6)
        .frame(width: 310, height: 92 + notchHeight)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height < -15 {
                    IslandWindowController.shared.collapse()
                }
            }
        )
    }

    // MARK: - 9. Compact Focus Pill (iOS Focus / Do Not Disturb)
    private func compactFocusPill(info: FocusInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: info.iconName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.indigo)
                .padding(.leading, 12)

            Spacer(minLength: notchWidth)

            HStack(spacing: 4) {
                Text(info.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(info.isOn ? "On" : "Off")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(info.isOn ? .indigo : .gray)
            }
            .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 10. Compact Timer Pill (iOS Live Activity)
    private func compactTimerPill(info: TimerInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.orange)
                .padding(.leading, 12)

            Spacer(minLength: notchWidth)

            Text(info.formattedRemaining)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            presentationMode = .expandedTimer(info)
        }
    }

    // MARK: - 11. Expanded Timer Card (iOS Live Activity Card)
    private func expandedTimerCard(info: TimerInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "timer")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.formattedRemaining)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)

                    Text(info.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.60))
                }

                Spacer()

                // Pause / Resume Button
                Image(systemName: info.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .onTapGesture {
                        TimerManager.shared.togglePause()
                    }

                // Stop / Dismiss Button
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .onTapGesture {
                        TimerManager.shared.stopTimer()
                        IslandWindowController.shared.collapse()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, notchHeight + 6)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.orange)
                        .frame(width: max(geo.size.width * CGFloat(info.progress), 4), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 348, height: 112 + notchHeight)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height < -15 {
                    IslandWindowController.shared.collapse()
                }
            }
        )
    }

    // MARK: - 12. Compact Dual Pill (iOS Split Island: Music + Timer)
    private func compactDualPill(track: MediaTrack, timer: TimerInfo) -> some View {
        HStack(spacing: 8) {
            // Left Half: Music Artwork & Waveform (Tappable to expand Music)
            HStack(spacing: 6) {
                if let art = nowPlaying.artworkImage {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .fill(LinearGradient(colors: [Color.pink, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 20, height: 20)
                        Image(systemName: "music.note")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                HStack(spacing: 1.8) {
                    ForEach(0..<3, id: \.self) { idx in
                        Capsule()
                            .fill(nowPlaying.waveformGradient)
                            .frame(width: 1.7, height: max(compactBars[idx] * 0.75, 3.0))
                            .animation(.easeInOut(duration: 0.16), value: compactBars)
                    }
                }
                .frame(width: 11, height: 16)
            }
            .padding(.leading, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                presentationMode = .expandedMusic
            }

            Spacer(minLength: notchWidth)

            // Right Half: Timer Icon & Countdown (Tappable to expand Timer)
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)

                Text(timer.formattedRemaining)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
            }
            .padding(.trailing, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                presentationMode = .expandedTimer(timer)
            }
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 13. Compact Brightness Pill (iOS HUD Replacement)
    private func compactBrightnessPill(level: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.leading, 10)

            Spacer(minLength: notchWidth)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 50, height: 6)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(50 * (CGFloat(level) / 100.0), 4), height: 6)
            }
            .padding(.trailing, 12)
        }
        .frame(height: notchHeight)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 14. Expanded File Shelf Card ("Drop to Notch" Tray)
    private var expandedFileShelfCard: some View {
        VStack(spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.cyan)

                Text("Drop Shelf")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text("\(shelfManager.items.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.18))
                    .clipShape(Capsule())

                Spacer()

                if !shelfManager.items.isEmpty {
                    Button(action: {
                        shelfManager.clearAll()
                    }) {
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .onTapGesture {
                        IslandWindowController.shared.collapse()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, notchHeight + 6)

            // Files Content
            if shelfManager.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 26))
                        .foregroundColor(Color.white.opacity(0.3))
                    Text("Drag files over the notch to hold or share")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 6) {
                    ForEach(shelfManager.items.prefix(3)) { item in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(item.sizeString)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }

                            Spacer()

                            // Quick Action Buttons
                            HStack(spacing: 6) {
                                // Copy Path
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        shelfManager.copyPath(item)
                                    }

                                // Reveal in Finder
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        shelfManager.revealInFinder(item)
                                    }

                                // AirDrop / Share
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        shelfManager.airDrop(item)
                                    }

                                // Remove
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red.opacity(0.8))
                                    .frame(width: 24, height: 24)
                                    .background(Color.red.opacity(0.15))
                                    .clipShape(Circle())
                                    .onTapGesture {
                                        shelfManager.removeFile(id: item.id)
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onDrag {
                            NSItemProvider(object: item.url as NSURL)
                        }
                        .onTapGesture(count: 2) {
                            shelfManager.openItem(item)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 360)
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height < -15 {
                    IslandWindowController.shared.collapse()
                }
            }
        )
    }

    // MARK: - Actions
    private func activateSourceApp() {
        let appName = nowPlaying.currentTrack.source == .appleMusic ? "Music" : "Spotify"
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/\(appName).app"))
    }

    private var isPlayingMusicActive: Bool {
        switch presentationMode {
        case .compactMusic, .expandedMusic, .compactDual, .compactTrackChange:
            return nowPlaying.currentTrack.isPlaying
        default:
            return false
        }
    }

    private func updateWaveformState() {
        let shouldAnimate = isPlayingMusicActive

        if shouldAnimate {
            if waveformTimer == nil {
                // Immediate burst to lively heights (no 0.16s hesitation)
                compactBars = [
                    CGFloat.random(in: 6...18),
                    CGFloat.random(in: 5...15),
                    CGFloat.random(in: 9...20),
                    CGFloat.random(in: 6...14),
                    CGFloat.random(in: 4...10),
                    CGFloat.random(in: 2.5...5.0)
                ]
                expandedBars = [
                    CGFloat.random(in: 4...10),
                    CGFloat.random(in: 8...18),
                    CGFloat.random(in: 14...24),
                    CGFloat.random(in: 9...19),
                    CGFloat.random(in: 3...8)
                ]
                waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { _ in
                    DispatchQueue.main.async {
                        compactBars = [
                            CGFloat.random(in: 6...18),
                            CGFloat.random(in: 5...15),
                            CGFloat.random(in: 9...20),
                            CGFloat.random(in: 6...14),
                            CGFloat.random(in: 4...10),
                            CGFloat.random(in: 2.5...5.0)
                        ]
                        expandedBars = [
                            CGFloat.random(in: 4...10),
                            CGFloat.random(in: 8...18),
                            CGFloat.random(in: 14...24),
                            CGFloat.random(in: 9...19),
                            CGFloat.random(in: 3...8)
                        ]
                    }
                }
            }
        } else {
            waveformTimer?.invalidate()
            waveformTimer = nil
            withAnimation(.easeInOut(duration: 0.22)) {
                compactBars = [6, 10, 14, 10, 6, 2.5]
                expandedBars = [4, 8, 14, 8, 4]
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN, !seconds.isInfinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
