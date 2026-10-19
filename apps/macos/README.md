# TapoCam for macOS

SwiftUI app: live view (RTSP via ffmpeg, VideoToolbox decode), HD/SD, auto-reconnect, pan/tilt pad and arrow keys,
presets, privacy / LED / motion / flip / night-vision toggles, siren, calibrate, reboot, snapshots
(`~/Pictures/TapoCam`) and recordings without re-encoding (`~/Movies/TapoCam`).

Needs `brew install ffmpeg python`. On first connect the app installs pytapo into
`~/Library/Application Support/TapoCam/venv`. Passwords are stored in the Keychain.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| Arrow keys | Pan / tilt |
| ⇧⌘S | Snapshot |
| ⇧⌘R | Start / stop recording |
| ⌘R | Reconnect |
| ⌘, | Camera settings |

## Build

```sh
./build-app.sh                # → dist/TapoCam.app (native arch)
UNIVERSAL=1 ./build-app.sh    # arm64 + x86_64, as shipped
./build-app.sh --install      # also copies it to /Applications
```
