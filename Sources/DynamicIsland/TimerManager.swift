import Foundation

@MainActor
public final class TimerManager: ObservableObject {
    public static let shared = TimerManager()

    @Published public private(set) var activeTimer: TimerInfo? = nil

    private var countdownTimer: Timer?

    public var onTimerTick: ((TimerInfo) -> Void)?
    public var onTimerEnded: ((TimerInfo) -> Void)?

    private init() {}

    public func startTimer(seconds: Int, label: String = "Timer") {
        countdownTimer?.invalidate()
        let info = TimerInfo(totalSeconds: seconds, remainingSeconds: seconds, label: label, isPaused: false)
        self.activeTimer = info
        self.onTimerTick?(info)

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
                    self.activeTimer = current
                    self.onTimerEnded?(current)
                    self.stopTimer()
                }
            }
        }
    }

    public func togglePause() {
        guard var current = activeTimer else { return }
        current.isPaused.toggle()
        activeTimer = current
        onTimerTick?(current)
    }

    public func stopTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        activeTimer = nil
    }
}
