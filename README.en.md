<h1 align="center">DYNAMIC // ISLAND</h1>

<p align="center">
  <strong>Zero-Latency Native SystemAperture Engine for macOS</strong><br>
  Reverse-engineered Apple Dynamic Island 1:1. Hardware integration with Liquid Retina XDR Notch and external displays. Pure Swift / SwiftUI / AppKit. 0% Idle CPU.
</p>

<p align="center">
  <a href="README.md"><strong>[ РУССКИЙ ]</strong></a> &nbsp;&bull;&nbsp; <a href="README.en.md"><strong>[ ENGLISH ]</strong></a>
</p>

<p align="center">
  <a href="#03--build-and-installation">
    <img src="https://img.shields.io/badge/BUILD-SWIFT_PM-E6DFD3?style=for-the-badge&labelColor=18181B&logo=swift&logoColor=E6DFD3" alt="Build Swift PM" />
  </a>
  <a href="#04--cli-and-ipc-control">
    <img src="https://img.shields.io/badge/CLI-IPC_CONTROL-E6DFD3?style=for-the-badge&labelColor=18181B&logo=gnubash&logoColor=E6DFD3" alt="CLI Control" />
  </a>
  <a href="https://github.com/paradoxiicalie/dynamic-island/releases">
    <img src="https://img.shields.io/badge/RELEASES-DOWNLOAD_APP-E6DFD3?style=for-the-badge&labelColor=18181B&logo=apple&logoColor=E6DFD3" alt="Download Release" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ARCHITECTURE-ZERO--LATENCY%20EVENT--DRIVEN-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Architecture" />
  <img src="https://img.shields.io/badge/RESOURCES-0%25%20IDLE%20CPU%20%7C%20LOW%20RAM-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Resources" />
  <img src="https://img.shields.io/badge/PLATFORM-macOS%2014.0%2B%20(SONOMA%20%2F%20SEQUOIA)-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Platform" />
  <img src="https://img.shields.io/badge/HARDWARE-APPLE%20SILICON%20%2B%20INTEL-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="Hardware" />
  <img src="https://img.shields.io/badge/LICENSE-MIT-27272A?style=for-the-badge&labelColor=09090B&color=E4E4E7" alt="License" />
</p>

---

### 01 // CONCEPT

**DYNAMIC // ISLAND** is an uncompromising system-level implementation of Apple's SystemAperture architecture for macOS.

* **Zero-Latency Event-Driven Core (0% Idle CPU):** Complete elimination of polling loops. All interactions are interrupt-driven via direct IOKit power source kernel events (`IOPSNotificationCreateRunLoopSource`), low-level CoreAudio HAL listeners, and distributed notification pipelines (`NSDistributedNotificationCenter` with immediate delivery).
* **Monolithic Capsule Rendering:** Root container bounded by `GeometryReader` with a monolithic black capsule fixed at `CGWindowLevelForKey(.screenSaverWindow) + 5`. Prevents clipping artifacts, light gaps, or orphaned text elements during spring transitions (`.spring(response: 0.42, dampingFraction: 0.82)`).
* **Physical Notch and External Display Adaptation:** Automatically samples Liquid Retina XDR notch geometry via `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. When connected to external displays without a notch, it seamlessly transforms into a floating island with calibrated menu bar offsets.
* **High Information Density Interface:** Strict brutalist monochrome aesthetics matching iPhone 15/16 Pro physical behavior, augmented by real-time media color extraction.

---

### 02 // ARCHITECTURE AND MODULES

#### [ NOW PLAYING AND PALETTE EXTRACTION ]
* **Bidirectional IPC (Spotify and Apple Music):** Executes pre-compiled `NSAppleScript` bytecode in-memory without script recompilation overhead.
* **Dual-Anchor Artwork Color Extraction:** Analyzes artwork pixel buffers to extract top and bottom luminance-saturation anchor coordinates, rendering an authentic linear vertical gradient across the visualizer bars.
* **6-Bar Spectrum Analyzer:** Waveform bars pinned to a common baseline (`alignment: .bottom`) with 2.8 pt width, 1.4 pt corner radius, and independent spring dynamics matching iOS 18.
* **Expanded Music Card (348 pt):** High-resolution album artwork, interactive timeline scrubber with seek capability, playback controls, and rapid output switching.
* **Intelligent Insertion Delay Buffer:** 60-millisecond transition gate on track change and screen wake prevents layout clipping and accidental drops to idle state.

#### [ AUDIO ROUTING AND AIRPODS INTEGRATION ]
* **Hardware CoreAudio Listener:** Intercepts system audio route changes in real time.
* **Route Controller:** Slide-out sheet listing active audio devices (AirPods Pro, AirPods Max, internal speakers, external DACs).
* **Battery Level Indicators:** Live battery percentage telemetry for connected headphones and charging cases.

#### [ DROP SHELF // FILE DRAWER ]
* **Drag-and-Drop into the Physical Notch:** Dragging any file from Finder, desktop, or web browser directly into the notch illuminates a neon targeting boundary.
* **Persistent File Tray:** Retains dropped files with filename, size, and QuickLook thumbnail.
* **One-Click Actions:** Copy absolute path (`Copy Path`), reveal in Finder (`Reveal`), dispatch to macOS Share Sheet / AirDrop, or dismiss.
* **Bidirectional Transfer:** Drag files directly out of the notch shelf into Telegram, Slack, Mail, Xcode, or terminal sessions.

#### [ LOCK SCREEN AND BIOMETRIC AUTH ]
* **Lock Screen State Detection:** Subscribes to `com.apple.screenIsLocked` to collapse into a minimal padlock pill.
* **Touch ID / Apple Watch Unlock:** Unlocking transitions the pill into an expanded green "Unlocked" pill accompanied by authentic Apple haptic acoustic feedback (`unlock.caf`).

#### [ BATTERY, MAGSAFE AND POWER CONSUMPTION ]
* **IOKit Power Source Kernel Hooks:** Zero CPU overhead battery level and charging state notifications.
* **MagSafe Connection Alerts:** Fluid charging banner with battery percentage and Apple charging chime (`chime.caf`).
* **Critical Battery Warnings:** Alerts triggered at 20% and 10% remaining battery thresholds.

#### [ LIVE ACTIVITIES // SPLIT ISLAND ]
* **Multi-Activity State:** When media playback and a countdown timer run simultaneously, the island divides into two autonomous interactive capsules.
* **Leading Segment:** Album thumbnail and 3-bar miniature equalizer.
* **Trailing Segment:** Timer glyph and live second-by-second countdown timestamp.
* **Independent Hit Testing:** Tapping the leading bubble expands the music player; tapping the trailing bubble expands the timer controller.

#### [ HARDWARE PRIVACY INDICATORS ]
* Integrated hardware privacy dots (green indicator for FaceTime HD camera, orange indicator for microphone), positioned precisely within the physical bezel next to the optical lens.

---

### 03 // BUILD AND INSTALLATION

#### [ EXPIRATION LIFECYCLE: MAC VS IOS ]

| Platform | Installation Method | Validity Duration | Requires 7-day Re-signing? |
| :--- | :--- | :--- | :---: |
| **macOS** | **Local Build (Swift PM / Binary)** | **PERMANENT (FOREVER)** | **NO** |
| **macOS** | **Installed in /Applications** | **PERMANENT (FOREVER)** | **NO** |
| iOS | Free Apple ID (Sideloadly / AltStore) | 7 Days | **YES (Auto-resign required)** |
| iOS | Paid Apple Developer Account ($99/yr) | 365 Days | Annually |

> [!IMPORTANT]
> **The application on Mac runs permanently.** Unlike iOS, macOS does not impose a 7-day provisioning profile expiration on locally compiled native software. Once compiled and placed in `/Applications`, DynamicIsland runs 24/7 indefinitely without periodic refreshes or re-signing steps.

---

#### Building From Source (Swift Package Manager)

1. Clone the repository:
   ```bash
   git clone https://github.com/paradoxiicalie/dynamic-island.git
   cd dynamic-island
   ```
2. Execute the automated installer script:
   ```bash
   ./scripts/install.sh
   ```
   *The script builds a release binary via `swift build -c release`, packages `DynamicIsland.app` with all `.caf` audio resources, copies it to `/Applications`, and relaunches the daemon.*

---

#### Launch at Login Registration

To ensure the daemon starts automatically upon system reboot:
* Click the island icon in the macOS Menu Bar.
* Toggle **«Запуск при входе» / Launch at Login** (confirmed active).
* *Or via System Settings:* Navigate to *System Settings → General → Login Items* and add `DynamicIsland.app`.

---

#### 04 // CLI AND IPC CONTROL

The island can be manipulated via CLI flags from Terminal, Raycast, Alfred, or automated scripts:

| CLI Flag | Function | Command Example |
| :--- | :--- | :--- |
| `--toggle` | Toggle between compact and expanded states | `DynamicIsland --toggle` |
| `--collapse` | Force-collapse island to compact mode | `DynamicIsland --collapse` |
| `--expand-music` | Expand media player card | `DynamicIsland --expand-music` |
| `--expand-battery` | Expand battery status card | `DynamicIsland --expand-battery` |
| `--expand-timer` | Expand timer controller | `DynamicIsland --expand-timer` |
| `--routes` | Open audio output and AirPods sheet | `DynamicIsland --routes` |
| `--shelf` | Toggle Drop Shelf file drawer | `DynamicIsland --shelf` |
| `--shelf-add <path>` | Add specified file to Drop Shelf | `DynamicIsland --shelf-add ~/Downloads/document.pdf` |
| `--timer <sec> [label]` | Start countdown timer for given duration | `DynamicIsland --timer 300 "Focus"` |
| `--stop-timer` | Reset and stop active timer | `DynamicIsland --stop-timer` |
| `--battery` | Trigger MagSafe connection banner | `DynamicIsland --battery` |
| `--unlock` | Trigger Touch ID biometric unlock banner | `DynamicIsland --unlock` |
| `--lock` | Enter lock screen pill state | `DynamicIsland --lock` |
| `--airpods` | Trigger AirPods connected banner | `DynamicIsland --airpods` |
| `--alert <title> [sub] [icon] [color]` | Display custom alert with SF Symbol | `DynamicIsland --alert "Build" "Succeeded" checkmark.circle green` |
| `--focus <name> [on\|off]` | Trigger Focus Mode status change | `DynamicIsland --focus "Coding" on` |
| `--brightness <0..100>` | Display brightness adjustment HUD | `DynamicIsland --brightness 80` |
| `--privacy <mic\|camera\|both\|off>` | Configure hardware privacy indicators | `DynamicIsland --privacy camera` |

---

### 05 // TECHNICAL STACK

```text
[ ARCHITECTURE ]       Zero-Latency Event-Driven, Monolithic Geometry Lock, Notch-Native
[ RUNTIME & UI ]       Swift 5.10+, SwiftUI, AppKit (NSPanel, NSWindow.Level, CGWindowLevel)
[ KERNEL & HARDWARE ]  IOKit (IOPSNotificationCreateRunLoopSource), CoreAudio HAL, AVFoundation
[ MEDIA INTEROP ]      Compiled AppleScript Bytecode (Spotify & Apple Music), DistributedNotificationCenter
[ SOUND SYNTHESIS ]    Apple CoreAudio CAF Engine (Hardware Alert Acoustic Profiles)
[ COLOR EXTRACTION ]   Dual-Anchor Luminance & Saturation Color Extractor (RGB Gradient Fitting)
[ RESOURCE PROFILE ]   0% Idle CPU Usage, Zero Background Polling Loops, < 45 MB RSS Memory
[ PLATFORMS ]          macOS 14.0+ (Sonoma), macOS 15.0+ (Sequoia) | Apple Silicon (M1/M2/M3/M4) & Intel
```

---

### 06 // LICENSE

Distributed under the **MIT** License. See [LICENSE](LICENSE) for details.
