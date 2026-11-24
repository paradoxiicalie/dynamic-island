import Foundation

@MainActor
public final class TimerManager: ObservableObject {
    public static let shared = TimerManager()

    public static let presetDurations: [(seconds: Int, label: String, shortTitle: String)] = [
        (60, "Quick 1m", "1m"),
        (300, "Focus 5m", "5m"),
        (600, "Break 10m", "10m"),
        (1500, "Pomodoro 25m", "25m")
    ]

    @Published public private(set) var activeTimer: TimerInfo? = nil

    private var countdownTimer: Timer?

    public var onTimerTick: ((TimerInfo) -> Void)?
    public var onTimerEnded: ((TimerInfo) -> Void)?
    public var onTimerStopped: (() -> Void)?

    private init() {}

    public func startTimer(seconds: Int, label: String = "Timer") {
        let clamped = max(1, seconds)
        countdownTimer?.invalidate()
        let info = TimerInfo(totalSeconds: clamped, remainingSeconds: clamped, label: label, isPaused: false)
        activeTimer = info
        onTimerTick?(info)
        SoundManager.shared.playThrottled("haptic", minInterval: 0.1)
        HapticEngine.perform(.generic)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, var current = self.activeTimer else { return }
                guard !current.isPaused else { return }

                if current.remainingSeconds > 1 {
                    current.remainingSeconds -= 1
                    self.activeTimer = current
                    self.onTimerTick?(current)
                } else {
                    current.remainingSeconds = 0
                    self.activeTimer = nil
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.onTimerEnded?(current)
                }
            }
        }
    }

    public func togglePause() {
        guard var current = activeTimer else { return }
        current.isPaused.toggle()
        activeTimer = current
        onTimerTick?(current)
        HapticEngine.perform(.generic)
    }

    public func addMinute() {
        guard var current = activeTimer else { return }
        current.totalSeconds += 60
        current.remainingSeconds += 60
        activeTimer = current
        onTimerTick?(current)
        HapticEngine.perform(.generic)
    }

    public func stopTimer() {
        let wasActive = activeTimer != nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        activeTimer = nil
        if wasActive {
            onTimerStopped?()
        }
    }
}
