import CoreAudio
import CoreMediaIO
import Foundation

@MainActor
public final class PrivacyMonitor: ObservableObject {
    public static let shared = PrivacyMonitor()

    @Published public private(set) var isMicActive: Bool = false
    @Published public private(set) var isCameraActive: Bool = false
    @Published public private(set) var activeMicDeviceName: String? = nil
    @Published public private(set) var activeCameraDeviceName: String? = nil

    public var onPrivacyStateChanged: ((Bool, Bool) -> Void)?

    private var hardwareMicActive: Bool = false
    private var hardwareCameraActive: Bool = false
    private var manualMicOverride: Bool? = nil
    private var manualCameraOverride: Bool? = nil

    private var audioDevicesListBlock: AudioObjectPropertyListenerBlock?
    private var audioInputListeners: [AudioDeviceID: AudioObjectPropertyListenerBlock] = [:]

    private var cmioDevicesListBlock: CMIOObjectPropertyListenerBlock?
    private var cmioDeviceListeners: [CMIODeviceID: CMIOObjectPropertyListenerBlock] = [:]

    private init() {
        setupAudioHardwareMonitoring()
        setupCameraHardwareMonitoring()
        refreshHardwareStates()
    }

    public var isAnyActive: Bool {
        isMicActive || isCameraActive
    }

    public var statusDescription: String {
        switch (isCameraActive, isMicActive) {
        case (true, true): return "Camera & Mic Active"
        case (true, false): return activeCameraDeviceName.map { "Camera: \($0)" } ?? "Camera Active"
        case (false, true): return activeMicDeviceName.map { "Mic: \($0)" } ?? "Microphone Active"
        case (false, false): return "Privacy Clear"
        }
    }

    // MARK: - Manual Overrides (CLI & Unit Testing)

    public func setMicActive(_ active: Bool) {
        manualMicOverride = active ? true : nil
        recomputePublishedState()
    }

    public func setCameraActive(_ active: Bool) {
        manualCameraOverride = active ? true : nil
        recomputePublishedState()
    }

    public func clearManualOverrides() {
        manualMicOverride = nil
        manualCameraOverride = nil
        recomputePublishedState()
    }

    // MARK: - CoreAudio Microphone Monitoring

    private func setupAudioHardwareMonitoring() {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.rebindAudioInputListeners()
                self?.refreshMicHardwareState()
            }
        }
        audioDevicesListBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            block
        )

        rebindAudioInputListeners()
    }

    private func rebindAudioInputListeners() {
        var runAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        for (deviceID, block) in audioInputListeners {
            AudioObjectRemovePropertyListenerBlock(deviceID, &runAddress, DispatchQueue.main, block)
        }
        audioInputListeners.removeAll()

        for deviceID in enumerateAudioInputDevices() {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshMicHardwareState()
                }
            }
            let status = AudioObjectAddPropertyListenerBlock(deviceID, &runAddress, DispatchQueue.main, block)
            if status == noErr {
                audioInputListeners[deviceID] = block
            }
        }
    }

    private func enumerateAudioInputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else {
            return []
        }

        return devices.filter { deviceID in
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let status = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
            return status == noErr && streamSize > 0
        }
    }

    private func refreshMicHardwareState() {
        var isRunningAny = false
        var activeName: String? = nil

        for deviceID in enumerateAudioInputDevices() {
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning) == noErr, isRunning != 0 {
                isRunningAny = true
                activeName = audioDeviceName(deviceID)
                break
            }
        }

        hardwareMicActive = isRunningAny
        activeMicDeviceName = activeName
        recomputePublishedState()
    }

    private func audioDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let cfStr = name?.takeRetainedValue() else { return nil }
        return cfStr as String
    }

    // MARK: - CoreMediaIO Camera Monitoring

    private func setupCameraHardwareMonitoring() {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.rebindCameraListeners()
                self?.refreshCameraHardwareState()
            }
        }
        cmioDevicesListBlock = block

        CMIOObjectAddPropertyListenerBlock(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            block
        )

        rebindCameraListeners()
    }

    private func rebindCameraListeners() {
        var runAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        for (deviceID, block) in cmioDeviceListeners {
            CMIOObjectRemovePropertyListenerBlock(deviceID, &runAddress, DispatchQueue.main, block)
        }
        cmioDeviceListeners.removeAll()

        for deviceID in enumerateCameraDevices() {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshCameraHardwareState()
                }
            }
            let status = CMIOObjectAddPropertyListenerBlock(deviceID, &runAddress, DispatchQueue.main, block)
            if status == noErr {
                cmioDeviceListeners[deviceID] = block
            }
        }
    }

    private func enumerateCameraDevices() -> [CMIODeviceID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else {
            return []
        }
        return devices
    }

    private func refreshCameraHardwareState() {
        var isRunningAny = false
        var activeName: String? = nil

        for deviceID in enumerateCameraDevices() {
            var isRunning: UInt32 = 0
            var used: UInt32 = 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            if CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &used, &isRunning) == noErr, isRunning != 0 {
                isRunningAny = true
                activeName = cameraDeviceName(deviceID)
                break
            }
        }

        hardwareCameraActive = isRunningAny
        activeCameraDeviceName = activeName
        recomputePublishedState()
    }

    private func cameraDeviceName(_ deviceID: CMIODeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let status = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &used, &name)
        guard status == noErr, let cfStr = name?.takeRetainedValue() else { return nil }
        return cfStr as String
    }

    // MARK: - Unified Reconciliation

    public func refreshHardwareStates() {
        refreshMicHardwareState()
        refreshCameraHardwareState()
    }

    private func recomputePublishedState() {
        let nextMic = manualMicOverride ?? hardwareMicActive
        let nextCam = manualCameraOverride ?? hardwareCameraActive

        let changed = (nextMic != isMicActive) || (nextCam != isCameraActive)
        isMicActive = nextMic
        isCameraActive = nextCam

        if changed {
            onPrivacyStateChanged?(nextMic, nextCam)
        }
    }
}
