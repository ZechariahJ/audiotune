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

## Install

### Option A — download the prebuilt app

1. Grab `AudioTune.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move `AudioTune.app` to `/Applications`.
3. **First launch only:** because the app isn't notarized, macOS blocks it once.
   Either:
   - Open it, then go to **System Settings → Privacy & Security**, scroll down,
     and click **"Open Anyway"**, **or**
   - run this in Terminal to clear the download flag:
     ```sh
     xattr -dr com.apple.quarantine /Applications/AudioTune.app
     ```
4. The first time you move a volume slider, macOS asks for **audio-recording**
   permission — click **Allow** (this is what lets AudioTune tap app audio).

> Why the warning? AudioTune is open-source and ad-hoc signed, not notarized
> through Apple's paid program. The warning is about *distribution*, not safety —
> the code is all in this repo. It works identically once past the first launch.

### Option B — build from source (no Gatekeeper prompt)

Needs the Swift toolchain (Xcode or Command Line Tools). Locally-built apps
aren't quarantined, so there's no warning:

```sh
git clone https://github.com/ZechariahJ/audiotune.git
cd audiotune
./build.sh            # -> AudioTune.app (ad-hoc signed, local use)
open AudioTune.app
```

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
