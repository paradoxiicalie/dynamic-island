import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import IOKit.ps

public struct AudioRoute: Identifiable, Equatable, Sendable {
    public var id: AudioDeviceID
    public var name: String
    public var iconName: String
    public var batteryText: String?
    public var batteryLevel: Int?
    public var isBluetooth: Bool
    public var isDefault: Bool
}

@MainActor
public final class AudioDeviceMonitor: ObservableObject {
    public static let shared = AudioDeviceMonitor()

    @Published public private(set) var currentVolume: Float32 = 0.5
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var currentDeviceName: String = "Internal Speakers"
    @Published public private(set) var isHeadphones: Bool = false
    @Published public private(set) var currentBrightness: Int = 80
    @Published public private(set) var currentHeadphonesBatteryLevel: Int? = nil
    @Published public private(set) var currentHeadphonesBatteryText: String? = nil
    @Published public private(set) var availableRoutes: [AudioRoute] = []

    public var onVolumeChanged: ((Float32) -> Void)?
    public var onMuteChanged: ((Bool) -> Void)?
    public var onDeviceChanged: ((String, Bool) -> Void)?
    public var onBrightnessChanged: ((Int) -> Void)?

    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var listenedDeviceID: AudioDeviceID = 0
    private var currentDeviceID: AudioDeviceID = 0
    private var hasCompletedInitialSync: Bool = false
    private var lastBluetoothProfileDate: Date = .distantPast

    private var displayServicesHandle: UnsafeMutableRawPointer?

    private init() {
        updateCurrentDevice()
        setupListeners()
        updateVolume(notify: false)
        updateMute(notify: false)
        setupBrightnessMonitor()
        updateAvailableRoutes()
        fetchAirPodsBatteryAsync()
        hasCompletedInitialSync = true
    }

    public var currentRouteIcon: String {
        if currentDeviceName.isEmpty { return "laptopcomputer" }
        return Self.iconForDevice(name: currentDeviceName, isBluetooth: isHeadphones)
    }

    public static func iconForDevice(name: String, isBluetooth: Bool = false) -> String {
        let lower = name.lowercased()
        if lower.contains("max") && lower.contains("airpods") { return "airpodsmax" }
        if lower.contains("pro") && lower.contains("airpods") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") || lower.contains("sony") || lower.contains("bose") ||
            lower.contains("headphones") || isBluetooth {
            return "headphones"
        }
        if lower.contains("macbook") || lower.contains("динамики") || lower.contains("internal") ||
            lower.contains("speakers") || lower.contains("built-in") {
            return "laptopcomputer"
        }
        if lower.contains("va24e") || lower.contains("display") || lower.contains("hdmi") ||
            lower.contains("asus") || lower.contains("monitor") {
            return "display"
        }
        return "laptopcomputer"
    }

    private func setupListeners() {
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        defaultDeviceListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let oldName = self.currentDeviceName
                let oldID = self.currentDeviceID
                self.updateCurrentDevice()
                self.setupVolumeAndMuteListeners()
                self.updateVolume(notify: false)
                self.updateMute(notify: false)
                self.updateAvailableRoutes()
                if self.isHeadphones {
                    self.fetchAirPodsBatteryAsync()
                }
                if self.hasCompletedInitialSync && (oldName != self.currentDeviceName || oldID != self.currentDeviceID) {
                    self.onDeviceChanged?(self.currentDeviceName, self.isHeadphones)
                }
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main,
            defaultDeviceListenerBlock!
        )

        var devicesListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        devicesListListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateAvailableRoutes()
                self?.fetchAirPodsBatteryAsync()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesListAddress,
            DispatchQueue.main,
            devicesListListenerBlock!
        )

        setupVolumeAndMuteListeners()
    }

    private func deviceTransportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return status == noErr ? transport : 0
    }

    private func isBluetoothTransport(_ transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private func fetchDeviceName(_ deviceID: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
        guard status == noErr, let cfStr = name?.takeRetainedValue() else { return "" }
        return cfStr as String
    }

    private func updateCurrentDevice() {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )
        guard status == noErr, defaultOutputDeviceID != 0 else { return }

        currentDeviceID = defaultOutputDeviceID
        let nameString = fetchDeviceName(defaultOutputDeviceID)
        currentDeviceName = nameString

        let transport = deviceTransportType(defaultOutputDeviceID)
        let bt = isBluetoothTransport(transport)
        isHeadphones = bt ||
            nameString.localizedCaseInsensitiveContains("AirPods") ||
            nameString.localizedCaseInsensitiveContains("Headphones") ||
            nameString.localizedCaseInsensitiveContains("Beats") ||
            nameString.localizedCaseInsensitiveContains("Sony") ||
            nameString.localizedCaseInsensitiveContains("Bose")
    }

    public func updateAvailableRoutes() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return }

        var routes: [AudioRoute] = []

        for deviceID in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) != noErr || streamSize == 0 {
                continue
            }

            let deviceName = fetchDeviceName(deviceID)
            let isDefault = (deviceID == currentDeviceID)
            let bt = isBluetoothTransport(deviceTransportType(deviceID))
            let icon = Self.iconForDevice(name: deviceName, isBluetooth: bt)
            let isWirelessAudio = bt || icon == "airpodspro" || icon == "airpodsmax" || icon == "airpods" || icon == "headphones"

            routes.append(AudioRoute(
                id: deviceID,
                name: deviceName,
                iconName: icon,
                batteryText: isWirelessAudio ? currentHeadphonesBatteryText : nil,
                batteryLevel: isWirelessAudio ? currentHeadphonesBatteryLevel : nil,
                isBluetooth: bt,
                isDefault: isDefault
            ))
        }

        availableRoutes = routes.sorted {
            if $0.isDefault { return true }
            if $1.isDefault { return false }
            if $0.isBluetooth != $1.isBluetooth { return $0.isBluetooth }
            return $0.name < $1.name
        }
    }

    public func setOutputRoute(to deviceID: AudioDeviceID) {
        var devID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &devID
        )
        if status == noErr {
            currentDeviceID = deviceID
            updateCurrentDevice()
            setupVolumeAndMuteListeners()
            updateVolume(notify: false)
            updateMute(notify: false)
            updateAvailableRoutes()
            SoundManager.shared.playThrottled("directions", minInterval: 0.15)
            HapticEngine.perform(.generic)
        }
    }

    // MARK: - Bluetooth & AirPods Battery Telemetry

    private func fetchIOKitAccessoryBattery() -> (Int?, String?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, nil)
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            let type = desc[kIOPSTypeKey] as? String ?? ""
            if type == kIOPSInternalBatteryType { continue }
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int, let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 {
                let pct = min(max(Int(Double(cur) / Double(maxCap) * 100.0), 0), 100)
                return (pct, "\(pct)%")
            }
        }
        return (nil, nil)
    }

    private func fetchAirPodsBatteryAsync() {
        let (ioPct, ioText) = fetchIOKitAccessoryBattery()
        if let pct = ioPct {
            currentHeadphonesBatteryLevel = pct
            currentHeadphonesBatteryText = ioText
            updateAvailableRoutes()
        }

        let now = Date()
        guard isHeadphones, now.timeIntervalSince(lastBluetoothProfileDate) >= 60.0 else {
            return
        }
        lastBluetoothProfileDate = now

        Task.detached(priority: .utility) {
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType"]
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return }

                var leftBat: String?
                var rightBat: String?
                var caseBat: String?
                var singleBat: String?

                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("Left Battery Level:") {
                        leftBat = trimmed.replacingOccurrences(of: "Left Battery Level:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("Right Battery Level:") {
                        rightBat = trimmed.replacingOccurrences(of: "Right Battery Level:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("Case Battery Level:") {
                        caseBat = trimmed.replacingOccurrences(of: "Case Battery Level:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if trimmed.hasPrefix("Battery Level:") {
                        singleBat = trimmed.replacingOccurrences(of: "Battery Level:", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }

                let primaryStr = leftBat ?? rightBat ?? singleBat
                let numericLevel = primaryStr.flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }

                var resolvedSummary: String? = nil
                if let ear = leftBat ?? rightBat, let caseB = caseBat {
                    resolvedSummary = "\(ear) • Case \(caseB)"
                } else if let ear = leftBat ?? rightBat {
                    resolvedSummary = ear
                } else if let single = singleBat {
                    resolvedSummary = single
                }
                let finalSummary = resolvedSummary

                if numericLevel != nil || finalSummary != nil {
                    await MainActor.run {
                        if let numericLevel = numericLevel {
                            self.currentHeadphonesBatteryLevel = numericLevel
                        }
                        if let finalSummary = finalSummary {
                            self.currentHeadphonesBatteryText = finalSummary
                        }
                        self.updateAvailableRoutes()
                    }
                }
            } catch {
                // Ignore profiler errors when Bluetooth daemon is busy
            }
        }
    }

    // MARK: - Volume & Mute CoreAudio Listeners

    private func setupVolumeAndMuteListeners() {
        removeVolumeAndMuteListeners()
        guard currentDeviceID != 0 else { return }

        let targetID = currentDeviceID
        listenedDeviceID = targetID

        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let vBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateVolume(notify: true)
            }
        }
        volumeListenerBlock = vBlock
        AudioObjectAddPropertyListenerBlock(targetID, &volAddress, DispatchQueue.main, vBlock)

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let mBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateMute(notify: true)
            }
        }
        muteListenerBlock = mBlock
        AudioObjectAddPropertyListenerBlock(targetID, &muteAddress, DispatchQueue.main, mBlock)
    }

    private func removeVolumeAndMuteListeners() {
        guard listenedDeviceID != 0 else { return }
        if let vBlock = volumeListenerBlock {
            var volAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(listenedDeviceID, &volAddress, DispatchQueue.main, vBlock)
            volumeListenerBlock = nil
        }
        if let mBlock = muteListenerBlock {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(listenedDeviceID, &muteAddress, DispatchQueue.main, mBlock)
            muteListenerBlock = nil
        }
        listenedDeviceID = 0
    }

    public func updateVolume(notify: Bool = true) {
        guard currentDeviceID != 0 else { return }

        var volume: Float32 = 0
        var volSize = UInt32(MemoryLayout<Float32>.size)
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyData(currentDeviceID, &volAddress, 0, nil, &volSize, &volume)
        if status != noErr {
            var scalarAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
            status = AudioObjectGetPropertyData(currentDeviceID, &scalarAddress, 0, nil, &volSize, &volume)
        }

        if status == noErr {
            let previousVol = currentVolume
            currentVolume = volume
            if notify && hasCompletedInitialSync && abs(previousVol - volume) > 0.005 {
                onVolumeChanged?(volume)
            }
        }
    }

    public func updateMute(notify: Bool = true) {
        guard currentDeviceID != 0 else { return }

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(currentDeviceID, &muteAddress, 0, nil, &muteSize, &muted)
        if status == noErr {
            let isMutedNow = (muted != 0)
            let prevMuted = isMuted
            isMuted = isMutedNow
            if notify && hasCompletedInitialSync && prevMuted != isMutedNow {
                onMuteChanged?(isMutedNow)
            }
        }
    }

    public func setVolume(_ volume: Float32) {
        guard currentDeviceID != 0 else { return }
        var clamped = min(max(volume, 0.0), 1.0)
        let size = UInt32(MemoryLayout<Float32>.size)

        var virtualAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectSetPropertyData(currentDeviceID, &virtualAddress, 0, nil, size, &clamped)
        if status != noErr {
            var scalarAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
            status = AudioObjectSetPropertyData(currentDeviceID, &scalarAddress, 0, nil, size, &clamped)
        }

        if clamped > 0.005 && isMuted {
            var unmute: UInt32 = 0
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(currentDeviceID, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmute)
            isMuted = false
        }

        currentVolume = clamped
    }

    public func setBrightness(_ percentage: Int) {
        let clampedPct = min(max(percentage, 0), 100)
        currentBrightness = clampedPct

        guard let handle = displayServicesHandle,
              let setPtr = dlsym(handle, "DisplayServicesSetBrightness") else {
            return
        }
        typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let setBr = unsafeBitCast(setPtr, to: SetFn.self)
        _ = setBr(CGMainDisplayID(), Float(clampedPct) / 100.0)
    }

    // MARK: - Display Brightness Listener (DisplayServices)

    private func setupBrightnessMonitor() {
        displayServicesHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        readCurrentBrightness(notify: false)

        guard let handle = displayServicesHandle,
              let regPtr = dlsym(handle, "DisplayServicesRegisterForBrightnessChangeNotifications") else {
            return
        }

        typealias RegFn = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, @convention(c) (UnsafeMutableRawPointer?) -> Void) -> Int32
        let reg = unsafeBitCast(regPtr, to: RegFn.self)
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        _ = reg(CGMainDisplayID(), ctx) { rawCtx in
            guard let rawCtx = rawCtx else { return }
            let monitor = Unmanaged<AudioDeviceMonitor>.fromOpaque(rawCtx).takeUnretainedValue()
            Task { @MainActor in
                monitor.readCurrentBrightness(notify: true)
            }
        }
    }

    private func readCurrentBrightness(notify: Bool) {
        guard let handle = displayServicesHandle,
              let getPtr = dlsym(handle, "DisplayServicesGetBrightness") else {
            return
        }

        typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let getBr = unsafeBitCast(getPtr, to: GetFn.self)
        var rawValue: Float = 0
        let status = getBr(CGMainDisplayID(), &rawValue)
        guard status == 0 else { return }

        let pct = min(max(Int((rawValue * 100.0).rounded()), 0), 100)
        let prev = currentBrightness
        currentBrightness = pct
        if notify && hasCompletedInitialSync && abs(prev - pct) >= 1 {
            onBrightnessChanged?(pct)
        }
    }
}
