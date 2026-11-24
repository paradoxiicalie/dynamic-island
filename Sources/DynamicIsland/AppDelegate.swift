import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var islandController: IslandWindowController!
    private var distributedHandlers: [String: (Notification) -> Void] = [:]

    private var toggleItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var soundsItem: NSMenuItem!
    private var hapticsItem: NSMenuItem!
    private var hoverExpandItem: NSMenuItem!
    private var modeMenuItems: [IslandDisplayMode: NSMenuItem] = [:]

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        islandController = IslandWindowController.shared
        setupStatusBar()
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
            SoundManager.shared.play("chime")
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
            self?.islandController.triggerBatteryAlert()
        }

        registerNotification(name: "com.alexey.dynamicisland.expandRoutes") { [weak self] _ in
            self?.islandController.isPinned = true
            self?.islandController.presentationMode = .expandedRoutes
        }

        registerNotification(name: "com.alexey.dynamicisland.expandTimer") { [weak self] _ in
            guard let timer = TimerManager.shared.activeTimer else { return }
            self?.islandController.isPinned = true
            self?.islandController.presentationMode = .expandedTimer(timer)
        }

        registerNotification(name: "com.alexey.dynamicisland.timer") { [weak self] notif in
            guard let info = notif.userInfo, let secStr = info["seconds"] as? String, let sec = Int(secStr) else { return }
            let label = info["label"] as? String ?? "Timer"
            TimerManager.shared.startTimer(seconds: sec, label: label)
            self?.islandController.reconcileBaselineMode()
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

        registerNotification(name: "com.alexey.dynamicisland.lowPower") { [weak self] notif in
            let enabled = (notif.userInfo?["enabled"] as? String) == "true"
            self?.islandController.triggerLowPowerAlert(enabled: enabled)
        }

        registerNotification(name: "com.alexey.dynamicisland.displayMode") { [weak self] notif in
            if let raw = notif.userInfo?["mode"] as? String, let mode = IslandDisplayMode(rawValue: raw) {
                self?.islandController.displayMode = mode
            }
        }

        registerNotification(name: "com.alexey.dynamicisland.fileShelf") { [weak self] _ in
            self?.islandController.toggleFileShelf()
        }

        registerNotification(name: "com.alexey.dynamicisland.dropZone") { [weak self] _ in
            self?.islandController.showTransientAlert(mode: .compactDropZone, duration: 3.0)
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
        menu.delegate = self

        let titleItem = NSMenuItem(title: "Dynamic Island • Активен", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Развернуть остров", action: #selector(toggleExpanded), keyEquivalent: "i")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let timerSubmenu = NSMenu(title: "Таймер")
        for preset in TimerManager.presetDurations {
            let item = NSMenuItem(title: preset.label, action: #selector(startTimerPreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = preset.seconds
            item.representedObject = preset.label
            timerSubmenu.addItem(item)
        }
        let timerParent = NSMenuItem(title: "Таймер", action: nil, keyEquivalent: "")
        timerParent.submenu = timerSubmenu
        menu.addItem(timerParent)

        let modeSubmenu = NSMenu(title: "Режим отображения")
        for mode in IslandDisplayMode.allCases {
            let item = NSMenuItem(title: mode.localizedTitle, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modeMenuItems[mode] = item
            modeSubmenu.addItem(item)
        }
        let modeParent = NSMenuItem(title: "Режим отображения", action: nil, keyEquivalent: "")
        modeParent.submenu = modeSubmenu
        menu.addItem(modeParent)

        menu.addItem(.separator())

        hoverExpandItem = NSMenuItem(title: "Раскрытие при наведении", action: #selector(toggleHoverExpand), keyEquivalent: "")
        hoverExpandItem.target = self
        menu.addItem(hoverExpandItem)

        soundsItem = NSMenuItem(title: "Звуковые эффекты", action: #selector(toggleSounds), keyEquivalent: "")
        soundsItem.target = self
        menu.addItem(soundsItem)

        hapticsItem = NSMenuItem(title: "Тактильный отклик", action: #selector(toggleHaptics), keyEquivalent: "")
        hapticsItem.target = self
        menu.addItem(hapticsItem)

        launchAtLoginItem = NSMenuItem(title: "Запуск при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Завершить", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    public func menuWillOpen(_ menu: NSMenu) {
        toggleItem.title = islandController.isExpanded ? "Свернуть остров" : "Развернуть остров"
        launchAtLoginItem.state = LoginItemHelper.isEnabled ? .on : .off
        soundsItem.state = SoundManager.shared.isEnabled ? .on : .off
        hapticsItem.state = HapticEngine.isEnabled ? .on : .off
        hoverExpandItem.state = islandController.hoverToExpand ? .on : .off
        for (mode, item) in modeMenuItems {
            item.state = (islandController.displayMode == mode) ? .on : .off
        }
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = IslandDisplayMode(rawValue: raw) {
            islandController.displayMode = mode
        }
    }

    @objc private func toggleHoverExpand() {
        islandController.hoverToExpand.toggle()
    }

    @objc private func toggleSounds() {
        _ = SoundManager.shared.toggleEnabled()
    }

    @objc private func toggleHaptics() {
        HapticEngine.isEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItemHelper.toggle()
    }

    @objc private func startTimerPreset(_ sender: NSMenuItem) {
        let label = sender.representedObject as? String ?? "Timer"
        TimerManager.shared.startTimer(seconds: sender.tag, label: label)
        islandController.reconcileBaselineMode()
    }

    @objc private func toggleExpanded() {
        islandController.toggleExpansion()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
