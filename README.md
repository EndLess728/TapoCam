# TapoCam

Native macOS app to watch and control TP-Link Tapo cameras over local Wi-Fi.

- Live view (RTSP via ffmpeg), HD/SD switch, auto-reconnect
- Pan/tilt pad (hold to repeat) and arrow keys, adjustable step
- Presets: go to, save current view, delete
- Privacy mode, status LED, motion detection, image flip, night vision (auto/on/off)
- Siren, motor calibration, reboot
- Snapshots → `~/Pictures/TapoCam`, recordings (no re-encode) → `~/Movies/TapoCam`
- Finds the camera on your LAN automatically

## Requirements

`brew install ffmpeg python` — on first connect the app installs [pytapo](https://github.com/JurajNyiri/pytapo)
into `~/Library/Application Support/TapoCam/venv`.

## Setup

1. Tapo app → camera → ⚙︎ → Advanced Settings → **Camera Account**: create a username/password (video).
2. In TapoCam settings, enter the camera IP (or click **Find**), that camera account, and your **Tapo app
   password** (pan/tilt & settings). Passwords are stored in the macOS Keychain.

## Build

```sh
./scripts/build_app.sh            # → build/TapoCam.app
./scripts/build_app.sh --install  # also copies to /Applications
```
