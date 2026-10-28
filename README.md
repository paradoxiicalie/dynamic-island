# Dynamic Island for macOS

Native macOS implementation of Apple iOS Dynamic Island architecture, tailored for MacBook notch displays (Liquid Retina XDR) and standard external monitors. Implemented entirely in Swift, SwiftUI, and AppKit with direct system framework bindings (`IOKit`, `CoreAudio`, `AVFoundation`) and zero third-party dependencies.

---

## Overview

The application creates an interactive, fluid layer directly beneath and adjacent to the MacBook display notch. When media is active or system events occur (power connection, lock/unlock, volume/brightness adjustments, active countdown timers), the island expands outward from the notch hardware with spring-physics animations, presenting live status indicators and interactive controls.

---

## Core Capabilities

### Now Playing and Color Extraction
- Direct AppleScript and IPC integration with Spotify and Apple Music.
- Real-time color extraction from album artwork: derives top and bottom color anchors to render a dynamic linear gradient across the visualizer bars.
- 6-bar dynamic waveform spectrum analyzer with authentic Apple bottom alignment and continuous animation.
- Expanded music controller (348 pt card) with high-resolution artwork, interactive scrubber timeline with seek support, playback controls, and route switcher.
- Automatic track change notification banner with title and artist slide-in.

### Audio Route Manager and AirPods Integration
- Real-time CoreAudio device change listener detecting connected headphones and speakers.
- Dedicated Route Sheet displaying connected AirPods Pro, AirPods Max, and external outputs.
- Per-device battery status indicators and one-click output switching via CoreAudio.

### Drop Shelf (File Drawer)
- Interactive drop target: dragging any file over the physical notch activates a cyan highlight ring.
- Persistent file holding tray supporting Finder items, browser downloads, and desktop files.
- Per-item actions: Copy Path, Reveal in Finder, Share / AirDrop, Remove.
- Bidirectional drag-and-drop: drag files out of the notch directly into Telegram, Slack, Mail, or Finder.

### Lock Screen and Authentication
- System lock screen integration displaying a padlock status pill during active screen lock.
- Touch ID and password authentication detection: triggers an unlock banner with Apple audio feedback and synchronized geometry transitions.

### Battery and MagSafe Monitoring
- Hardware power status monitoring via kernel IOKit notifications (`IOPSNotificationCreateRunLoopSource`) with zero CPU polling overhead.
- MagSafe connect/disconnect audio-visual alerts with authentic charging chime.
- Low-battery warning alerts at 20% and 10% thresholds.

### Volume and Brightness HUD
- Notch-integrated liquid capsule replacement for legacy macOS square HUD overlays.
- Dynamic speaker and brightness glyphs with proportional linear progress indicators.

### Dual Live Activities (Split Island)
- Multi-activity presentation mode when media playback and a countdown timer run simultaneously.
- Leading bubble: album artwork and compact 3-bar equalizer.
- Trailing bubble: timer glyph and live countdown timestamp.
- Independent tap targets: clicking the leading wing expands the music card; clicking the trailing wing expands the timer controller.

### Hardware Privacy Indicators
- Visual privacy dots (green for camera, orange for microphone) embedded directly inside the notch bezel, aligned with the physical camera sensor.

### Native Sound Engine
- Integrated `.caf` audio feedback for system alerts (`chime.caf`, `unlock.caf`, `lock.caf`, `low-battery.caf`, `volume.caf`).

---

## Architecture and Performance

- **Zero Idle CPU Consumption**: No continuous polling loops during idle states; all system interactions are interrupt-driven via kernel event sources and distributed notifications (`NSDistributedNotificationCenter` with immediate delivery).
- **Pre-compiled AppleScript Bytecode**: Media query scripts are compiled into memory on initialization to prevent repeated script compilation costs during playback tracking.
- **Continuous Geometry Synchronization**: Root view utilizes `GeometryReader` with a monolithic black background capsule locked to window frame bounds, preventing orphaned text or clipped borders during view transitions.
- **Window Level Hierarchy**: Positioned at `CGWindowLevelForKey(.screenSaverWindow) + 5` with `NSWindow.CollectionBehavior` flags (`canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`), ensuring visibility above full-screen spaces and lock screens.

---

## Project Structure

```
dynamic-island-clone/
├── Package.swift
├── README.md
├── .gitignore
├── Resources/
│   ├── chime.caf
│   ├── directions.caf
│   ├── event.caf
│   ├── haptic.caf
│   ├── lock.caf
│   ├── low-battery.caf
│   ├── low-power.caf
│   ├── sleep.caf
│   ├── unlock.caf
│   └── volume.caf
├── Sources/
│   └── DynamicIsland/
│       ├── DynamicIslandApp.swift       # Entry point and CLI IPC dispatcher
│       ├── AppDelegate.swift            # Menu bar item and autostart manager
│       ├── IslandWindowController.swift  # Notch window geometry and lifecycle engine
│       ├── IslandView.swift             # SwiftUI presentation engine and spring transitions
│       ├── NowPlayingManager.swift      # Spotify & Apple Music IPC, artwork palette engine
│       ├── AudioDeviceMonitor.swift     # CoreAudio routing and volume observer
│       ├── BatteryMonitor.swift         # IOKit power source kernel listener
│       ├── FileShelfManager.swift       # Drop-to-notch file holding tray
│       ├── TimerManager.swift           # Live activity countdown and stopwatch engine
│       ├── SoundManager.swift           # Audio playback engine for Apple .caf sounds
│       ├── PrivacyMonitor.swift         # Microphone and camera hardware observer
│       └── Models.swift                 # Data types, presentation modes, and contracts
└── Tests/
    └── DynamicIslandTests/
        └── DynamicIslandTests.swift
```

---

## Build and Installation

### Prerequisites
- macOS 13.0 (Ventura) or later.
- Xcode Command Line Tools (`xcode-select --install`) or Swift 5.9+ toolchain.

### Build from Source
```bash
# Clone the repository
git clone https://github.com/paradoxiicalie/dynamic-island.git
cd dynamic-island

# Compile release binary
swift build -c release

# Install application bundle
cp .build/release/DynamicIsland /Applications/DynamicIsland.app/Contents/MacOS/DynamicIsland
```

### Running
Launch via Spotlight / Applications, or start in background from Terminal:
```bash
/Applications/DynamicIsland.app/Contents/MacOS/DynamicIsland &
```

---

## Menu Bar Controls

The application adds an icon to the macOS menu bar providing:
- **Dynamic Island • Активен**: Status indicator.
- **Развернуть остров / Свернуть остров**: Toggle expanded view (`Command + I`).
- **Запуск при входе**: Toggle launch at login via macOS System Events.
- **Завершить**: Terminate application (`Command + Q`).

---

## CLI and IPC Automation

The running instance can be controlled from Terminal, Raycast, or Shortcuts:

| Command | Action |
| :--- | :--- |
| `DynamicIsland --toggle` | Toggle expanded card view |
| `DynamicIsland --expand-music` | Open expanded music controller |
| `DynamicIsland --routes` | Open audio route switcher |
| `DynamicIsland --shelf` | Open drop-to-notch file tray |
| `DynamicIsland --shelf-add "/path/to/file"` | Add file to holding tray |
| `DynamicIsland --timer 300 "Meeting"` | Start countdown timer (seconds, label) |
| `DynamicIsland --stop-timer` | Stop active timer |
| `DynamicIsland --battery` | Trigger battery status alert |
| `DynamicIsland --unlock` | Trigger authentication unlock banner |
| `DynamicIsland --airpods` | Trigger audio device connection banner |
| `DynamicIsland --brightness 75` | Show brightness HUD indicator (0-100) |
| `DynamicIsland --focus "Work" on` | Show Focus mode indicator |
| `DynamicIsland --privacy mic` | Enable microphone privacy dot |
| `DynamicIsland --privacy off` | Disable privacy indicators |
| `DynamicIsland --collapse` | Force collapse to compact / idle mode |

---

## License

MIT License. Designed and maintained by paradoxiicalie.
