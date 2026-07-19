# AudioTune

Per-app volume control for macOS, in the menu bar. No kernel extension, no audio
driver — it uses the modern Core Audio process-tap API (macOS 14.4+) to tap each
app's audio, mute its direct output, and re-render it through a private aggregate
device at an adjustable per-app gain.

## Features

- **Per-app volume sliders** in the menu bar, live as you drag
- **Per-app mute**
- **Master channel** — one slider/mute scaling every app
- **Pin** apps to keep them in the main menu (vs. the "All apps" submenu)
- **Persistent** — levels are remembered per app (by bundle id) across launches
- **Auto-attach** — a saved level re-applies the moment an app starts playing
- **Follows your output device** — rebuilds taps when you switch headphones/speakers
- **Launch at Login** toggle

## Requirements

- macOS 14.4 or later (Apple Silicon or Intel)
- Swift toolchain (Xcode or Command Line Tools)

## Build & run

```sh
./build.sh            # debug build -> AudioTune.app (ad-hoc signed, local use)
open AudioTune.app
```

The first time you adjust an app's volume, macOS asks for audio-recording
permission — click **Allow** (required for the tap API).

## Distribution (code-signing + notarization)

Ad-hoc signing only runs on the machine that built it. To share the app you need
an **Apple Developer Program** membership and a **Developer ID Application**
certificate. Then:

```sh
# One-time: store notary credentials as a keychain profile
xcrun notarytool store-credentials audiotune-notary \
    --apple-id "you@example.com" --team-id "TEAMID" \
    --password "app-specific-password"

# Build signed (hardened runtime) + notarize + staple
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh release
./notarize.sh
```

See `notarize.sh` for the full prerequisite list.

## Layout

| File | Role |
|---|---|
| `AppDelegate.swift` | Menu, state, master/reset, login item, device listener |
| `AudioProcessMonitor.swift` | Enumerates Core Audio process objects → app roster |
| `ProcessTap.swift` | Tap + aggregate device + realtime gain render callback |
| `AppVolumeRowView.swift` | A menu row: icon, name, slider, mute, pin |
| `SettingsStore.swift` | Persisted per-app + master settings (UserDefaults) |
| `LoginItem.swift` | Launch-at-login via SMAppService |
| `CoreAudioHW.swift` | Default output device helpers |

Debug log: `~/Documents/audiotune/audiotune.log`.
