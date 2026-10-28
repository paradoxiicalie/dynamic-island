import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var islandController: IslandWindowController!
    private var distributedHandlers: [String: (Notification) -> Void] = [:]

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background/accessory agent (no Dock icon, unobtrusive system HUD)
        NSApp.setActivationPolicy(.accessory)

        // Initialize Dynamic Island
        islandController = IslandWindowController.shared

        // Setup Menu Bar Extra
        setupStatusBar()

        // Setup CLI / IPC notification observers
        setupDistributedNotifications()
    }

    private func registerNotification(name: String, handler: @escaping (Notification) -> Void) {
        distributedHandlers[name] = handler
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNote(_:)),
            name: NSNotification.Name(name),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleDistributedNote(_ note: Notification) {
        Task { @MainActor [weak self] in
            self?.distributedHandlers[note.name.rawValue]?(note)
        }
    }

    private func setupDistributedNotifications() {
        registerNotification(name: "com.alexey.dynamicisland.toggle") { [weak self] _ in
            self?.toggleExpanded()
        }

        registerNotification(name: "com.alexey.dynamicisland.batteryAlert") { [weak self] _ in
            self?.islandController.triggerBatteryAlert()
        }

        registerNotification(name: "com.alexey.dynamicisland.unlock") { [weak self] _ in
            self?.islandController.triggerUnlockAlert()
        }

        registerNotification(name: "com.alexey.dynamicisland.airpods") { [weak self] _ in
            self?.islandController.showTransientAlert(mode: .compactAirPods, duration: 3.2)
        }

        registerNotification(name: "com.alexey.dynamicisland.alert") { [weak self] notification in
            let info = notification.userInfo
            let title = info?["title"] as? String ?? "Alert"
            let subtitle = info?["subtitle"] as? String ?? ""
            let icon = info?["icon"] as? String ?? "bell.fill"
            let color = info?["color"] as? String ?? "white"
            self?.islandController.triggerCustomAlert(title: title, subtitle: subtitle, icon: icon, color: color)
        }

        registerNotification(name: "com.alexey.dynamicisland.expandMusic") { [weak self] _ in
            self?.islandController.isPinned = true
            self?.islandController.presentationMode = .expandedMusic
        }

        registerNotification(name: "com.alexey.dynamicisland.expandBattery") { [weak self] _ in
            self?.islandController.isPinned = true
            self?.islandController.presentationMode = .expandedBattery
        }

        registerNotification(name: "com.alexey.dynamicisland.expandRoutes") { [weak self] _ in
            self?.islandController.isPinned = true
            self?.islandController.presentationMode = .expandedRoutes
        }

        registerNotification(name: "com.alexey.dynamicisland.expandTimer") { [weak self] _ in
            if let current = TimerManager.shared.activeTimer {
                self?.islandController.isPinned = true
                self?.islandController.presentationMode = .expandedTimer(current)
            }
        }

        registerNotification(name: "com.alexey.dynamicisland.timer") { [weak self] notif in
            guard let info = notif.userInfo, let secStr = info["seconds"] as? String, let sec = Int(secStr) else { return }
            let label = info["label"] as? String ?? "Timer"
            TimerManager.shared.startTimer(seconds: sec, label: label)
            if let current = TimerManager.shared.activeTimer {
                self?.islandController.presentationMode = .compactTimer(current)
            }
        }

        registerNotification(name: "com.alexey.dynamicisland.stopTimer") { [weak self] _ in
            TimerManager.shared.stopTimer()
            self?.islandController.collapse()
        }

        registerNotification(name: "com.alexey.dynamicisland.focus") { [weak self] notif in
            guard let info = notif.userInfo, let name = info["name"] as? String else { return }
            let isOn = (info["isOn"] as? String) == "true"
            let focus = FocusInfo(name: name, iconName: "moon.fill", isOn: isOn)
            self?.islandController.showTransientAlert(mode: .compactFocus(focus), duration: 2.8)
        }

        registerNotification(name: "com.alexey.dynamicisland.brightness") { [weak self] notif in
            guard let info = notif.userInfo, let lvlStr = info["level"] as? String, let lvl = Int(lvlStr) else { return }
            self?.islandController.triggerBrightnessAlert(level: lvl)
        }

        registerNotification(name: "com.alexey.dynamicisland.fileShelf") { [weak self] _ in
            self?.islandController.toggleFileShelf()
        }

        registerNotification(name: "com.alexey.dynamicisland.shelfAdd") { [weak self] notif in
            guard let info = notif.userInfo, let path = info["path"] as? String else { return }
            let url = URL(fileURLWithPath: path)
            FileShelfManager.shared.addFile(url)
            self?.islandController.isPinned = true
            self?.islandController.presentationMode = .expandedFileShelf
        }

        registerNotification(name: "com.alexey.dynamicisland.privacy") { notif in
            if let info = notif.userInfo {
                let mic = (info["mic"] as? String) == "true"
                let cam = (info["camera"] as? String) == "true"
                PrivacyMonitor.shared.setMicActive(mic)
                PrivacyMonitor.shared.setCameraActive(cam)
            }
        }

        registerNotification(name: "com.alexey.dynamicisland.collapse") { [weak self] _ in
            self?.islandController.collapse()
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "capsule.bottomhalf.filled", accessibilityDescription: "Dynamic Island")
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Dynamic Island (Active)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Toggle Expanded View", action: #selector(toggleExpanded), keyEquivalent: "i")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let alertItem = NSMenuItem(title: "Simulate Charging Alert", action: #selector(simulateCharging), keyEquivalent: "b")
        alertItem.target = self
        menu.addItem(alertItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleExpanded() {
        if islandController.presentationMode == .expandedMusic || islandController.presentationMode == .expandedBattery {
            islandController.presentationMode = NowPlayingManager.shared.currentTrack.isPlaying ? .compactMusic : .idle
        } else {
            let hasMusic = NowPlayingManager.shared.currentTrack.isPlaying || !NowPlayingManager.shared.currentTrack.title.isEmpty
            islandController.presentationMode = hasMusic ? .expandedMusic : .expandedBattery
        }
    }

    @objc private func simulateCharging() {
        islandController.triggerBatteryAlert()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
