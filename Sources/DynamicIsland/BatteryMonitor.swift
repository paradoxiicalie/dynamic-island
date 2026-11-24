import Foundation
import IOKit.ps

@MainActor
public final class BatteryMonitor: ObservableObject {
    public static let shared = BatteryMonitor()

    @Published public private(set) var currentBattery: BatteryInfo = .empty

    private var pollTimer: Timer?
    private var lastPluggedInState: Bool?
    private var lastLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var lastWarnedLowPercentage: Int?
    private var runLoopSource: CFRunLoopSource?
    private var powerStateObserver: NSObjectProtocol?

    public var onPluggedInStateChanged: ((Bool) -> Void)?
    public var onLowBatteryWarning: ((Int) -> Void)?
    public var onLowPowerModeChanged: ((Bool) -> Void)?

    private init() {
        updateBatteryStatus()
        setupPowerSourceNotification()
        setupLowPowerModeObserver()
        startMonitoring()
    }

    private func setupPowerSourceNotification() {
        let loop = CFRunLoopGetCurrent()
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.updateBatteryStatus()
            }
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(loop, source, .defaultMode)
        }
    }

    private func setupLowPowerModeObserver() {
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                if enabled != self.lastLowPowerMode {
                    self.lastLowPowerMode = enabled
                    self.updateBatteryStatus()
                    self.onLowPowerModeChanged?(enabled)
                }
            }
        }
    }

    public func startMonitoring() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBatteryStatus()
            }
        }
        pollTimer?.tolerance = 15.0
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            runLoopSource = nil
        }
        if let observer = powerStateObserver {
            NotificationCenter.default.removeObserver(observer)
            powerStateObserver = nil
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

            // Ensure we read the internal Mac battery first when enumerating power sources
            if let type = desc[kIOPSTypeKey] as? String, type != kIOPSInternalBatteryType {
                continue
            }

            let curCap = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percentage = maxCap > 0 ? Int((Double(curCap) / Double(maxCap)) * 100.0) : curCap
            let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let powerState = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            let isPluggedIn = (powerState == kIOPSACPowerValue)
            let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

            var timeFormatted = ""
            if isCharging, let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int, timeToFull > 0 {
                let hours = timeToFull / 60
                let mins = timeToFull % 60
                timeFormatted = hours > 0 ? "\(hours)h \(mins)m to full" : "\(mins)m to full"
            } else if !isPluggedIn, let timeRemaining = desc[kIOPSTimeToEmptyKey] as? Int, timeRemaining > 0 {
                let hours = timeRemaining / 60
                let mins = timeRemaining % 60
                timeFormatted = hours > 0 ? "\(hours)h \(mins)m left" : "\(mins)m left"
            }

            let newInfo = BatteryInfo(
                percentage: percentage,
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                isLowPowerMode: isLowPower,
                timeRemainingFormatted: timeFormatted
            )

            if let prevPlugged = lastPluggedInState, prevPlugged != isPluggedIn {
                if isPluggedIn {
                    lastWarnedLowPercentage = nil
                }
                onPluggedInStateChanged?(isPluggedIn)
            }

            if !isPluggedIn && lastPluggedInState != nil {
                if percentage <= 10 && lastWarnedLowPercentage != 10 {
                    lastWarnedLowPercentage = 10
                    onLowBatteryWarning?(percentage)
                } else if percentage <= 20 && percentage > 10 && lastWarnedLowPercentage == nil {
                    lastWarnedLowPercentage = 20
                    onLowBatteryWarning?(percentage)
                }
            }

            lastPluggedInState = isPluggedIn
            lastLowPowerMode = isLowPower
            currentBattery = newInfo
            break
        }
    }
}
