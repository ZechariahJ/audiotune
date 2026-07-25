# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately via GitHub's [Report a vulnerability](https://github.com/ZechariahJ/audiotune/security/advisories/new)
form (Security → Advisories). Include reproduction steps, the affected version,
and your macOS version. Expect an initial response within a few days.

## Supported versions

Only the latest release receives fixes.

## What AudioTune does and doesn't do

Useful context when assessing risk:

- **No network access.** The app makes no network requests: no telemetry, no
  analytics, no auto-update, no crash reporting.
- **One permission.** It requests audio recording (TCC "Microphone"), which is
  what the Core Audio process-tap API requires to capture app audio. It does
  **not** request Accessibility, Input Monitoring, or Screen Recording — the
  global hotkeys use Carbon's `RegisterEventHotKey`, which needs no permission.
- **Audio is never recorded to disk.** Tapped audio exists only inside the
  realtime render callback, where it is scaled and passed straight to the output
  device.
- **Local state** is limited to per-app volume settings (`UserDefaults`) and a
  size-capped diagnostic log at `~/Library/Logs/AudioTune/audiotune.log`, which
  records app names and Core Audio status codes — never audio.

## Verifying a download

Released builds are ad-hoc signed and **not notarized**, so macOS shows an
"unidentified developer" warning on first launch (see the README). If you would
rather not bypass Gatekeeper, build from source — see the README's
"build from source" instructions.

To inspect what you downloaded:

```sh
codesign -dv --verbose=4 /Applications/AudioTune.app
```
