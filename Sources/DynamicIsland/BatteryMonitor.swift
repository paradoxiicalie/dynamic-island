import Foundation
import IOKit.ps

@MainActor
public final class BatteryMonitor: ObservableObject {
    public static let shared = BatteryMonitor()

    @Published public private(set) var currentBattery: BatteryInfo = .empty
    @Published public private(set) var recentEvent: String? = nil

    private var pollTimer: Timer?
    private var lastPluggedInState: Bool?
    private var runLoopSource: CFRunLoopSource?

    public var onPluggedInStateChanged: ((Bool) -> Void)?
    public var onLowBatteryWarning: ((Int) -> Void)?

    private init() {
        updateBatteryStatus()
        setupPowerSourceNotification()
        startMonitoring()
    }

    private func setupPowerSourceNotification() {
        let loop = CFRunLoopGetCurrent()
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.updateBatteryStatus()
            }
        }, context).takeRetainedValue()

        CFRunLoopAddSource(loop, runLoopSource, .defaultMode)
    }

    public func startMonitoring() {
        pollTimer?.invalidate()
        // Event-driven IOKit handles real-time updates with zero CPU.
        // Fallback timer runs once every 60s for battery conservation.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBatteryStatus()
            }
        }
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            runLoopSource = nil
        }
    }

    public func updateBatteryStatus() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for powerSource in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, powerSource)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let curCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percentage = maxCap > 0 ? Int((Double(curCap) / Double(maxCap)) * 100) : curCap
            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let powerState = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            let isPluggedIn = (powerState == kIOPSACPowerValue)

            var timeFormatted = ""
            if let timeRemaining = desc[kIOPSTimeToEmptyKey] as? Int, timeRemaining > 0 {
                let hours = timeRemaining / 60
                let mins = timeRemaining % 60
                timeFormatted = "\(hours)h \(mins)m remaining"
            }

            let newInfo = BatteryInfo(
                percentage: percentage,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                timeRemainingFormatted: timeFormatted
            )

            if let prevPlugged = lastPluggedInState, prevPlugged != isPluggedIn {
                onPluggedInStateChanged?(isPluggedIn)
            }
            if !isPluggedIn && (percentage == 20 || percentage == 10) && lastPluggedInState != nil {
                onLowBatteryWarning?(percentage)
            }
            lastPluggedInState = isPluggedIn
            self.currentBattery = newInfo
            break
        }
    }
}
