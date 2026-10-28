import AppKit
import AudioToolbox
import CoreAudio
import Foundation

public struct AudioRoute: Identifiable, Equatable, Sendable {
    public var id: AudioDeviceID
    public var name: String
    public var iconName: String
    public var batteryText: String?
    public var isDefault: Bool
}

@MainActor
public final class AudioDeviceMonitor: ObservableObject {
    public static let shared = AudioDeviceMonitor()

    @Published public private(set) var currentVolume: Float32 = 0.5
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var currentDeviceName: String = "Internal Speakers"
    @Published public private(set) var isHeadphones: Bool = false
    @Published public private(set) var availableRoutes: [AudioRoute] = []

    public var onVolumeChanged: ((Float32) -> Void)?
    public var onMuteChanged: ((Bool) -> Void)?
    public var onDeviceChanged: ((String, Bool) -> Void)?

    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var currentDeviceID: AudioDeviceID = 0
    private var cachedAirPodsBattery: String? = nil

    private init() {
        updateCurrentDevice()
        setupListeners()
        updateVolume()
        updateMute()
        updateAvailableRoutes()
        fetchAirPodsBatteryAsync()
    }

    public var currentRouteIcon: String {
        if currentDeviceName.isEmpty {
            return "laptopcomputer"
        }
        return Self.iconForDevice(name: currentDeviceName)
    }

    public static func iconForDevice(name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("max") && lower.contains("airpods") {
            return "airpodsmax"
        }
        if lower.contains("pro") && lower.contains("airpods") {
            return "airpodspro"
        }
        if lower.contains("airpods") {
            return "airpods"
        }
        if lower.contains("beats") || lower.contains("sony") || lower.contains("bose") || lower.contains("headphones") {
            return "headphones"
        }
        if lower.contains("macbook") || lower.contains("динамики") || lower.contains("internal") || lower.contains("speakers") || lower.contains("built-in") {
            return "laptopcomputer"
        }
        if lower.contains("va24e") || lower.contains("display") || lower.contains("hdmi") || lower.contains("asus") || lower.contains("monitor") {
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
                self.updateCurrentDevice()
                self.setupVolumeAndMuteListeners()
                self.updateVolume()
                self.updateMute()
                self.updateAvailableRoutes()
                if oldName != self.currentDeviceName {
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

        // Listen for new/removed audio hardware
        var devicesListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        devicesListListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateAvailableRoutes()
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

        guard status == noErr else { return }
        self.currentDeviceID = defaultOutputDeviceID

        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        withUnsafeMutablePointer(to: &name) { pointer in
            _ = AudioObjectGetPropertyData(
                defaultOutputDeviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                pointer
            )
        }

        let nameString = name as String
        self.currentDeviceName = nameString
        self.isHeadphones = nameString.localizedCaseInsensitiveContains("AirPods") ||
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
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        _ = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        var routes: [AudioRoute] = []

        for deviceID in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let sStatus = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
            if sStatus != noErr || streamSize == 0 {
                continue
            }

            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            withUnsafeMutablePointer(to: &name) { pointer in
                _ = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, pointer)
            }

            let deviceName = name as String
            let isDefault = (deviceID == currentDeviceID)
            let icon = Self.iconForDevice(name: deviceName)
            var battery: String? = nil
            if icon == "airpodspro" || icon == "airpodsmax" || icon == "airpods" {
                battery = cachedAirPodsBattery
            }

            routes.append(AudioRoute(
                id: deviceID,
                name: deviceName,
                iconName: icon,
                batteryText: battery,
                isDefault: isDefault
            ))
        }

        // Sort so active route or AirPods are first
        self.availableRoutes = routes.sorted {
            if $0.isDefault { return true }
            if $1.isDefault { return false }
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
            self.currentDeviceID = deviceID
            updateCurrentDevice()
            setupVolumeAndMuteListeners()
            updateVolume()
            updateAvailableRoutes()
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    private func fetchAirPodsBatteryAsync() {
        Task.detached(priority: .background) {
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType"]
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
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

                    var batterySummary: String? = nil
                    if let ear = leftBat ?? rightBat, let caseB = caseBat {
                        batterySummary = "\(ear) Футляр: \(caseB)"
                    } else if let ear = leftBat ?? rightBat {
                        batterySummary = "\(ear)"
                    } else if let single = singleBat {
                        batterySummary = "\(single)"
                    }

                    if let summary = batterySummary {
                        await MainActor.run {
                            self.cachedAirPodsBattery = summary
                            self.updateAvailableRoutes()
                        }
                    }
                }
            } catch {
                // Ignore background profiler errors
            }
        }
    }

    private func setupVolumeAndMuteListeners() {
        guard currentDeviceID != 0 else { return }

        // Volume Listener
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        volumeListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateVolume()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            currentDeviceID,
            &volAddress,
            DispatchQueue.main,
            volumeListenerBlock!
        )

        // Mute Listener
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        muteListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateMute()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            currentDeviceID,
            &muteAddress,
            DispatchQueue.main,
            muteListenerBlock!
        )
    }

    public func updateVolume() {
        guard currentDeviceID != 0 else { return }

        var volume: Float32 = 0
        var volSize = UInt32(MemoryLayout<Float32>.size)
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            currentDeviceID,
            &volAddress,
            0,
            nil,
            &volSize,
            &volume
        )

        if status == noErr {
            let previousVol = self.currentVolume
            self.currentVolume = volume
            if abs(previousVol - volume) > 0.005 {
                self.onVolumeChanged?(volume)
            }
        }
    }

    public func updateMute() {
        guard currentDeviceID != 0 else { return }

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            currentDeviceID,
            &muteAddress,
            0,
            nil,
            &muteSize,
            &muted
        )

        if status == noErr {
            let isMutedNow = (muted != 0)
            let prevMuted = self.isMuted
            self.isMuted = isMutedNow
            if prevMuted != isMutedNow {
                self.onMuteChanged?(isMutedNow)
            }
        }
    }
}
