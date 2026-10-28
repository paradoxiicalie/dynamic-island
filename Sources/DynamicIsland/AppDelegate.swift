import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var islandController: IslandWindowController!

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

    private func setupDistributedNotifications() {
        let center = DistributedNotificationCenter.default()

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.toggle"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toggleExpanded()
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.batteryAlert"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.triggerBatteryAlert()
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.unlock"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.triggerUnlockAlert()
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.airpods"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.showTransientAlert(mode: .compactAirPods, duration: 3.2)
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.alert"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                let info = notification.userInfo
                let title = info?["title"] as? String ?? "Alert"
                let subtitle = info?["subtitle"] as? String ?? ""
                let icon = info?["icon"] as? String ?? "bell.fill"
                let color = info?["color"] as? String ?? "white"
                self?.islandController.triggerCustomAlert(title: title, subtitle: subtitle, icon: icon, color: color)
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.expandMusic"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.isPinned = true
                self?.islandController.presentationMode = .expandedMusic
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.expandBattery"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.isPinned = true
                self?.islandController.presentationMode = .expandedBattery
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.expandRoutes"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.isPinned = true
                self?.islandController.presentationMode = .expandedRoutes
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.expandTimer"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let current = TimerManager.shared.activeTimer {
                    self?.islandController.isPinned = true
                    self?.islandController.presentationMode = .expandedTimer(current)
                }
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.timer"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor [weak self] in
                guard let info = notif.userInfo, let secStr = info["seconds"] as? String, let sec = Int(secStr) else { return }
                let label = info["label"] as? String ?? "Timer"
                TimerManager.shared.startTimer(seconds: sec, label: label)
                if let current = TimerManager.shared.activeTimer {
                    self?.islandController.presentationMode = .compactTimer(current)
                }
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.stopTimer"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                TimerManager.shared.stopTimer()
                self?.islandController.collapse()
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.focus"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor [weak self] in
                guard let info = notif.userInfo, let name = info["name"] as? String else { return }
                let isOn = (info["isOn"] as? String) == "true"
                let focus = FocusInfo(name: name, iconName: "moon.fill", isOn: isOn)
                self?.islandController.showTransientAlert(mode: .compactFocus(focus), duration: 2.8)
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.brightness"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor [weak self] in
                guard let info = notif.userInfo, let lvlStr = info["level"] as? String, let lvl = Int(lvlStr) else { return }
                self?.islandController.triggerBrightnessAlert(level: lvl)
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.fileShelf"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.toggleFileShelf()
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.shelfAdd"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor [weak self] in
                guard let info = notif.userInfo, let path = info["path"] as? String else { return }
                let url = URL(fileURLWithPath: path)
                FileShelfManager.shared.addFile(url)
                self?.islandController.isPinned = true
                self?.islandController.presentationMode = .expandedFileShelf
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.privacy"),
            object: nil,
            queue: .main
        ) { notif in
            Task { @MainActor in
                if let info = notif.userInfo {
                    let mic = (info["mic"] as? String) == "true"
                    let cam = (info["camera"] as? String) == "true"
                    PrivacyMonitor.shared.setMicActive(mic)
                    PrivacyMonitor.shared.setCameraActive(cam)
                }
            }
        }

        center.addObserver(
            forName: NSNotification.Name("com.alexey.dynamicisland.collapse"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.islandController.collapse()
            }
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
