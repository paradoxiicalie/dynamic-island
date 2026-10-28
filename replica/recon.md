# Recon Map: Alcove (Dynamic Island for macOS)
**Target:** Alcove (`com.henrikruscon.Alcove`)  
**Scope:** Re-engineer core Dynamic Island mechanics (HUD, Notch integration, Now Playing, Battery, Gestures) into a custom, modern macOS native application.

---

## 1. Executive Architecture & Core Mechanism

### A. Window & Notch Rendering Engine
- **Window Class:** `NSPanel` (Borderless, non-activating, floating window).
- **Window Level:** `CGWindowLevelKey.mainMenuWindow` or `NSWindow.Level.statusBar + 1` (`.floating`).
- **Collection Behavior:** `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- **Hardware Notch Detection:** Reads `NSScreen.main?.auxiliaryTopLeftArea` / `safeAreaInsets.top`. If safe area height > 0, anchors inside the physical notch; otherwise renders a simulated black rounded capsule (`forceSimulatedNotch`).
- **Interaction Model:**
  - **Idle State:** Sits snugly around notch or minimal pill (width ~160-200pt, height ~32pt).
  - **Compact Indicator State:** Left icon (album art / battery symbol), right waveform / percentage.
  - **Hover / Click Expanded State:** Drops down into a full card widget with spring physics (`CASpringAnimation` / SwiftUI `.spring(response:dampingFraction:)`).

### B. Now Playing / Phone Music Integration
- **Mac Player Bridge:**
  - AppleScript / ScriptingBridge for Spotify (`com.spotify.client`) and Apple Music (`com.apple.Music`).
  - Private framework integration: `MediaRemote.framework` (`MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteRegisterForNowPlayingNotifications`) for system-wide media detection (Safari, YouTube, podcasts, system audio).
- **Phone Playback Sync ("как с телефона если играет"):**
  - **Spotify Connect:** When music is played on the iPhone via Spotify, the macOS Spotify desktop client acts as a synced endpoint. AppleScript / Spotify notifications continuously mirror track title, artist, album art, position, and play state in real time.
  - **macOS AirPlay Receiver:** Ventura+ acts as an AirPlay 2 target. When routing iPhone audio to Mac, `MediaRemote` receives the remote metadata.

### C. Battery & Power Notifications
- **API:** `IOKit.ps` (`IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription`).
- **Monitored Metrics:**
  - State of Charge (`CurrentCapacity / MaxCapacity * 100`).
  - Power state: Battery Power vs AC Power (Charging).
  - Low Battery Threshold (configurable, default 10% or 20%).
  - Low Power Mode detection.
  - Bluetooth battery levels via `IOPSCopyPowerSourcesList` (AirPods, Magic Mouse/Keyboard).

---

## 2. Screen & State Inventory

| ID | State / Screen | Presentation | Purpose | Key Components |
|---|---|---|---|---|
| **S01** | Notch Idle | Top-center minimal pill | Blends with hardware notch or floats seamlessly | Black capsule, status dots |
| **S02** | Compact Now Playing | Left/Right pill wings | Shows active playback at a glance | Album thumbnail (left), Animated audio bars (right) |
| **S03** | Compact Battery Alert | Expands pill briefly | Event-driven notification for plug-in / low battery | Battery icon with lightning bolt, percentage pill |
| **S04** | Expanded Music Card | Dropdown card (~340x160pt) | Rich controls, scrubber, album art | High-res artwork, Title/Artist marquee, Play/Pause, Skip, Scrubber, Volume slider |
| **S05** | Expanded Battery Card | Dropdown card (~260x100pt) | Power status & peripheral battery breakdown | Mac battery circle, Charging speed/time remaining, Connected AirPods levels |
| **S06** | Settings Window | Native macOS Preferences window | Customization of thresholds, notch dimensions, behavior | Sidebar tabs (General, Battery, Connectivity, Sound, Now Playing) |

---

## 3. Gestures & Micro-Interactions

- **Hover Expansion:** Expands automatically on cursor dwell (~150ms delay to prevent accidental triggers).
- **Swipe-to-Skip:** Horizontal two-finger trackpad swipe over the island triggers `Next Track` / `Previous Track`.
- **Swipe-to-Dismiss:** Quick upward swipe collapses island back to idle.
- **Haptics:** Uses `NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)` on click and state transitions.

---

## 4. Inferred Data Model

```
MediaTrack {
  id: String
  title: String
  artist: String
  album: String
  artworkURL: URL?
  duration: Double
  elapsedTime: Double
  isPlaying: Bool
  source: .spotify | .appleMusic | .system
}

BatteryStatus {
  percentage: Int
  isCharging: Bool
  isPluggedIn: Bool
  isLowPowerMode: Bool
  timeRemainingMinutes: Int?
}

IslandConfiguration {
  notchWidth: CGFloat (default: 180)
  notchHeight: CGFloat (default: 34)
  expandOnHover: Bool (default: true)
  hoverDelay: Double (default: 0.15)
  showBatteryPercentage: Bool (default: true)
  hapticsEnabled: Bool (default: true)
}
```
