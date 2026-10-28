# Dynamic Island for macOS (Notch & Liquid Retina XDR)

A native, zero-CPU implementation of Apple's **iOS Dynamic Island** (SystemAperture) reverse-engineered directly from iPhone 15 Pro hardware and crafted for the MacBook notch and external displays.

Built purely in **Swift, SwiftUI, and AppKit** with direct kernel event callbacks (`IOKit`, `CoreAudio`, `AVFoundation`).

---

## ✨ Features & Capabilities

### 1. 🎵 Now Playing & Artwork Gradient Visualizer
- **Spotify & Apple Music Support:** Instant song metadata updates with 0% CPU consumption via pre-compiled bytecode scripts.
- **Dynamic Artwork Gradient Waveform:** 6-bar bottom-aligned spectrum visualizer (`Capsule`) tinted with a real-time vertical linear gradient derived from the upper and lower halves of the current album artwork.
- **Compact & Expanded Cards:** 
  - Hover or click to expand into a 348pt card with high-resolution artwork, live interactive scrubber bar, playback controls, and song color theme.
  - Interactive track seeking, previous/next, and play/pause.
  - Automatic slide-in track change announcement pill.

### 2. 🎧 Audio Route Switcher & AirPods Modal
- Tapping the audio route icon opens the dedicated **iOS AirPlay/Route Switcher Card**.
- Live detection of connected audio devices:
  - **AirPods Pro / AirPods Max / Mac Speakers** with authentic glyphs.
  - Interactive volume sliders per device.
  - One-click output switching via CoreAudio.

### 3. 📂 Drop-to-Shelf ("Drop to Notch" / File Tray)
- Drag any file from Finder, Desktop, or Browser over the notch: the island animates with a glowing cyan dashed border.
- Dropping files reveals the **Drop Shelf**:
  - Displays system file icons (`NSWorkspace.shared.icon(forFile:)`) and formatted file sizes.
  - Actions per item: **Copy Path**, **Reveal in Finder**, **AirDrop / Share Sheet**, and **Remove**.
  - **Draggable Out:** Drag files directly from the notch shelf into Telegram, Mail, Slack, or Finder.

### 4. ⏱️ Split Island (Dual Live Activities)
- When music is playing AND a timer is active, the notch seamlessly splits:
  - **Left Bubble:** Mini album art + live 3-bar animated equalizer.
  - **Right Bubble:** Native orange timer icon + `MM:SS` countdown.
- Independent tap targets: tapping the left expands Music; tapping the right expands the Timer card.

### 5. 🔋 Battery & MagSafe Monitoring
- Visual MagSafe charging alert with authentic Apple charging chime.
- Real-time percentage display with low battery alerts (at 20% and 10%).
- Backed by kernel run loop notifications (`IOPSNotificationCreateRunLoopSource`) with 0 polling overhead.

### 6. 🔆 iOS-Style Brightness & Volume HUD
- Replaces macOS's legacy square bezel with an authentic liquid pill directly inside the notch.
- Smooth capsule progress indicators for display brightness and audio volume.

### 7. 🟢 Privacy Indicator Dot
- Embedded hardware privacy dots inside the notch capsule (green for camera, orange for microphone) aligned with the physical MacBook camera sensor.

### 8. 🔊 Authentic Apple Sound Engine
- Integrated native `.caf` audio feedback (`chime.caf`, `unlock.caf`, `lock.caf`, `low-battery.caf`, `volume.caf`).

---

## ⚡ Zero-CPU & Power Efficiency Architecture

Designed to run **24/7 without draining battery**:
- **0.0% CPU when Idle:** No polling timers running during idle.
- **Compiled AppleScript Bytecode:** Scripts are compiled once (`NSAppleScript.compileAndReturnError`) and stored in memory.
- **Display Sleep Detection:** Waveform timers and observers suspend instantly when the Mac screen goes to sleep (`screensDidSleepNotification`).
- **Floating Panel Level:** Rendered above full-screen apps and lock screens using `CGWindowLevelForKey(.screenSaverWindow) + 5`.

---

## 🛠️ Project Structure

```
dynamic-island-clone/
├── Package.swift
├── README.md
├── .gitignore
├── Resources/
│   ├── chime.caf
│   ├── unlock.caf
│   ├── lock.caf
│   ├── low-battery.caf
│   └── volume.caf
└── Sources/
    └── DynamicIsland/
        ├── DynamicIslandApp.swift       # App entry point & CLI IPC dispatcher
        ├── AppDelegate.swift            # Menu bar item, IPC notification router
        ├── IslandWindowController.swift  # Notch window geometry & lifecycle manager
        ├── IslandView.swift             # SwiftUI presentation engine & spring animations
        ├── NowPlayingManager.swift      # Spotify & Music.app IPC, color palette extractor
        ├── AudioDeviceMonitor.swift     # CoreAudio routing & volume control
        ├── BatteryMonitor.swift         # IOKit kernel power source listener
        ├── FileShelfManager.swift       # File shelf tray, drag-and-drop provider
        ├── TimerManager.swift           # Live Countdown timer & stopwatch engine
        ├── SoundManager.swift           # Audio playback engine for Apple .caf sounds
        ├── PrivacyMonitor.swift         # Microphone & camera state observer
        └── Models.swift                 # Data types, presentation modes & contracts
```

---

## 🚀 Installation & Running

### Building from Source:
```bash
# Build release binary
swift build -c release

# Install to /Applications
cp .build/release/DynamicIsland /Applications/DynamicIsland.app/Contents/MacOS/DynamicIsland
```

### Launching:
- Launch directly via Finder or Spotlight (`DynamicIsland.app`).
- To launch as a background daemon:
```bash
/Applications/DynamicIsland.app/Contents/MacOS/DynamicIsland &
```

### Launch at Login (Permanent 24/7):
1. Open **System Settings** -> **General** -> **Login Items**.
2. Click `+` and select `/Applications/DynamicIsland.app`.

---

## ⌨️ CLI & Automation Commands

Send instant commands to the running notch from Terminal, Raycast, or Shortcuts:
- Toggle expand/collapse: `DynamicIsland --toggle`
- Expand Music: `DynamicIsland --expand-music`
- Expand Audio Routes: `DynamicIsland --routes`
- Open Drop Shelf: `DynamicIsland --shelf`
- Add file to Shelf: `DynamicIsland --shelf-add "/path/to/file"`
- Start Timer: `DynamicIsland --timer 300 "Sprint"`
- Brightness HUD: `DynamicIsland --brightness 80`
- Privacy Dot: `DynamicIsland --privacy mic` / `DynamicIsland --privacy off`
- Battery alert: `DynamicIsland --battery`
