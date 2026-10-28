import AppKit

@main
struct DynamicIslandApp {
    @MainActor
    static func main() {
        let args = CommandLine.arguments

        if args.contains("--toggle") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.toggle"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--battery") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.batteryAlert"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--unlock") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.unlock"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--lock") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.apple.screenIsLocked"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--airpods") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.airpods"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if let alertIdx = args.firstIndex(of: "--alert"), alertIdx + 1 < args.count {
            let title = args[alertIdx + 1]
            let subtitle = alertIdx + 2 < args.count ? args[alertIdx + 2] : ""
            let icon = alertIdx + 3 < args.count ? args[alertIdx + 3] : "bell.fill"
            let color = alertIdx + 4 < args.count ? args[alertIdx + 4] : "white"
            let userInfo: [String: String] = [
                "title": title,
                "subtitle": subtitle,
                "icon": icon,
                "color": color
            ]
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.alert"),
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--expand-music") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.expandMusic"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--expand-battery") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.expandBattery"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--expand-timer") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.expandTimer"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--routes") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.expandRoutes"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if let timerIdx = args.firstIndex(of: "--timer"), timerIdx + 1 < args.count, let sec = Int(args[timerIdx + 1]) {
            let label = timerIdx + 2 < args.count ? args[timerIdx + 2] : "Timer"
            let userInfo: [String: String] = [
                "seconds": String(sec),
                "label": label
            ]
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.timer"),
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--stop-timer") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.stopTimer"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if let focusIdx = args.firstIndex(of: "--focus"), focusIdx + 1 < args.count {
            let name = args[focusIdx + 1]
            let isOn = focusIdx + 2 < args.count ? (args[focusIdx + 2].lowercased() != "off" && args[focusIdx + 2].lowercased() != "false") : true
            let userInfo: [String: String] = [
                "name": name,
                "isOn": isOn ? "true" : "false"
            ]
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.focus"),
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
            return
        }

        if let brightIdx = args.firstIndex(of: "--brightness"), brightIdx + 1 < args.count, let lvl = Int(args[brightIdx + 1]) {
            let userInfo: [String: String] = ["level": String(lvl)]
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.brightness"),
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--shelf") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.fileShelf"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        if let addIdx = args.firstIndex(of: "--shelf-add"), addIdx + 1 < args.count {
            let path = args[addIdx + 1]
            let userInfo: [String: String] = ["path": path]
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.shelfAdd"),
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
            return
        }

        if let privIdx = args.firstIndex(of: "--privacy"), privIdx + 1 < args.count {
            let mode = args[privIdx + 1].lowercased()
            let micActive = (mode == "mic" || mode == "both" || mode == "on")
            let camActive = (mode == "camera" || mode == "both")
            let userInfo: [String: String] = [
                "mic": micActive ? "true" : "false",
                "camera": camActive ? "true" : "false"
            ]
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.privacy"),
                object: nil,
                userInfo: userInfo,
                deliverImmediately: true
            )
            return
        }

        if args.contains("--collapse") {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.alexey.dynamicisland.collapse"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
