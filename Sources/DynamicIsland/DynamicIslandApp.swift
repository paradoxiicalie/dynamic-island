import AppKit

@main
struct DynamicIslandApp {
    private static func post(_ name: String, userInfo: [String: String]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(name),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    @MainActor
    static func main() {
        let args = CommandLine.arguments

        if args.contains("--toggle") { post("com.alexey.dynamicisland.toggle"); return }
        if args.contains("--battery") { post("com.alexey.dynamicisland.batteryAlert"); return }
        if args.contains("--unlock") { post("com.alexey.dynamicisland.unlock"); return }
        if args.contains("--lock") { post("com.apple.screenIsLocked"); return }
        if args.contains("--airpods") { post("com.alexey.dynamicisland.airpods"); return }
        if args.contains("--expand-music") { post("com.alexey.dynamicisland.expandMusic"); return }
        if args.contains("--expand-battery") { post("com.alexey.dynamicisland.expandBattery"); return }
        if args.contains("--expand-timer") { post("com.alexey.dynamicisland.expandTimer"); return }
        if args.contains("--routes") { post("com.alexey.dynamicisland.expandRoutes"); return }
        if args.contains("--stop-timer") { post("com.alexey.dynamicisland.stopTimer"); return }
        if args.contains("--shelf") { post("com.alexey.dynamicisland.fileShelf"); return }
        if args.contains("--drop-zone") { post("com.alexey.dynamicisland.dropZone"); return }
        if args.contains("--collapse") { post("com.alexey.dynamicisland.collapse"); return }

        if let alertIdx = args.firstIndex(of: "--alert"), alertIdx + 1 < args.count {
            post("com.alexey.dynamicisland.alert", userInfo: [
                "title": args[alertIdx + 1],
                "subtitle": alertIdx + 2 < args.count ? args[alertIdx + 2] : "",
                "icon": alertIdx + 3 < args.count ? args[alertIdx + 3] : "bell.fill",
                "color": alertIdx + 4 < args.count ? args[alertIdx + 4] : "white"
            ])
            return
        }

        if let timerIdx = args.firstIndex(of: "--timer"), timerIdx + 1 < args.count, let sec = Int(args[timerIdx + 1]) {
            let label = timerIdx + 2 < args.count ? args[timerIdx + 2] : "Timer"
            post("com.alexey.dynamicisland.timer", userInfo: ["seconds": String(sec), "label": label])
            return
        }

        if let focusIdx = args.firstIndex(of: "--focus"), focusIdx + 1 < args.count {
            let name = args[focusIdx + 1]
            let isOn = focusIdx + 2 < args.count ? (args[focusIdx + 2].lowercased() != "off" && args[focusIdx + 2].lowercased() != "false") : true
            post("com.alexey.dynamicisland.focus", userInfo: ["name": name, "isOn": isOn ? "true" : "false"])
            return
        }

        if let brightIdx = args.firstIndex(of: "--brightness"), brightIdx + 1 < args.count, let lvl = Int(args[brightIdx + 1]) {
            post("com.alexey.dynamicisland.brightness", userInfo: ["level": String(lvl)])
            return
        }

        if let lowPowerIdx = args.firstIndex(of: "--low-power"), lowPowerIdx + 1 < args.count {
            let mode = args[lowPowerIdx + 1].lowercased()
            let enabled = (mode == "on" || mode == "true" || mode == "1")
            post("com.alexey.dynamicisland.lowPower", userInfo: ["enabled": enabled ? "true" : "false"])
            return
        }

        if let modeIdx = args.firstIndex(of: "--mode"), modeIdx + 1 < args.count {
            post("com.alexey.dynamicisland.displayMode", userInfo: ["mode": args[modeIdx + 1].lowercased()])
            return
        }

        if let addIdx = args.firstIndex(of: "--shelf-add"), addIdx + 1 < args.count {
            post("com.alexey.dynamicisland.shelfAdd", userInfo: ["path": args[addIdx + 1]])
            return
        }

        if let privIdx = args.firstIndex(of: "--privacy"), privIdx + 1 < args.count {
            let mode = args[privIdx + 1].lowercased()
            let micActive = (mode == "mic" || mode == "both" || mode == "on")
            let camActive = (mode == "camera" || mode == "both")
            post("com.alexey.dynamicisland.privacy", userInfo: [
                "mic": micActive ? "true" : "false",
                "camera": camActive ? "true" : "false"
            ])
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
