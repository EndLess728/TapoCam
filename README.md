# TapoCam

Watch and control **TP-Link Tapo** pan/tilt cameras over your local Wi-Fi from **Windows**, **macOS** and **Android TV**: live view, pan/tilt, presets and camera settings, with no cloud and no Tapo app in the loop.

> Not affiliated with or endorsed by TP-Link. "Tapo" and "TP-Link" are trademarks of their respective owners.

## Apps

| App | Folder | Built with | Output |
|---|---|---|---|
| Windows | [`apps/windows`](apps/windows) | C#, WPF (.NET 8), ffmpeg, embedded Python + pytapo | Installer and portable ZIP (x64) |
| macOS | [`apps/macos`](apps/macos) | Swift, SwiftUI, ffmpeg, pytapo | Universal app (DMG) |
| Android TV | [`apps/android`](apps/android) | Kotlin, Media3 ExoPlayer, ONVIF | APK |

| Feature | Windows | macOS | Android TV |
|---|:-:|:-:|:-:|
| Live view (RTSP), HD/SD switch, auto-reconnect | ✅ | ✅ | ✅ |
| Pan/tilt (hold to repeat, arrow keys / D-pad) | ✅ | ✅ | ✅ |
| Presets: go to, save, delete | ✅ | ✅ | ✅ |
| Privacy mode, status LED, motion detection, image flip, night vision | ✅ | ✅ | — |
| Siren, motor calibration, reboot | ✅ | ✅ | — |
| Snapshots and recordings (no re-encode) | ✅ | ✅ | — |
| Finds the camera on your LAN | ✅ | ✅ | ✅ |
| Sound | — | — | ✅ |

The desktop apps talk to the camera's local Tapo API through [pytapo](https://github.com/JurajNyiri/pytapo) (via the shared bridge in [`shared/tapo_helper.py`](shared/tapo_helper.py)). The Android TV app only needs the Camera Account and uses ONVIF for pan/tilt and presets.

## Install

Download the files from the latest [**Release**](../../releases/latest).

### Windows 10/11 (x64)

Run `TapoCam-x.y.z-windows-setup.exe` (installs per-user, no admin needed), or unzip `TapoCam-x.y.z-windows-x64.zip` anywhere and run `TapoCam.exe`. ffmpeg and Python are bundled, so there's nothing else to install. The app isn't code-signed, so SmartScreen may warn the first time: click **More info → Run anyway**.

### macOS 14 Sonoma or later

1. `brew install ffmpeg python`. On first connect the app installs pytapo into `~/Library/Application Support/TapoCam/venv`.
2. Open `TapoCam-x.y.z-macOS.dmg` and drag **TapoCam** to **Applications**.
3. The app isn't notarized: open it once, then **System Settings → Privacy & Security → Open Anyway**, or run
   `xattr -dr com.apple.quarantine /Applications/TapoCam.app`.

### Android TV 6.0 or later

Sideload `TapoCam-x.y.z-android-tv.apk`:

```sh
adb connect <tv-ip>:5555
adb install -r TapoCam-x.y.z-android-tv.apk
```

Or use [`apps/android/scripts/install-tv.sh`](apps/android/scripts/install-tv.sh) to build, install and push the camera login in one go.

## Camera setup

1. Tapo app → camera → ⚙ → **Advanced Settings → Camera Account**: create a username and password. This is used for video (RTSP) and, on Android TV, ONVIF controls.
2. In TapoCam's settings, enter the camera's IP (or click **Find**) and that Camera Account.
3. Desktop only: also enter your **Tapo app password** to enable pan/tilt and camera settings. It's stored in the macOS Keychain or encrypted with Windows DPAPI, and only ever sent to the camera.

Tested with a Tapo C200-class pan/tilt camera. Other Tapo cameras that pytapo supports should work; fixed cameras get live view, snapshots and recording.

## Build from source

| App | Command | Needs |
|---|---|---|
| Windows | `cd apps/windows; .\build.ps1 [-Installer]` | .NET 8 SDK, Python 3.12, Inno Setup 6 for the installer |
| macOS | `cd apps/macos && ./build-app.sh [--install]` | Xcode 15+ / Swift 5.10 |
| Android TV | `cd apps/android && ./gradlew assembleRelease` | JDK 17, Android SDK |

See each app's README for details.

## Releases

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds all three apps on every push and pull request (download them from the run's artifacts). Pushing a tag publishes a GitHub Release with every build attached and a changelog grouped from the commit messages since the previous tag:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

Use [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, …) so changes land in the right section.

## Repository layout

```
apps/
  windows/   WPF app, build.ps1 (bundles ffmpeg + Python), Inno Setup installer
  macos/     SwiftUI app, build-app.sh
  android/   Android TV app (Gradle)
shared/
  tapo_helper.py   JSON-over-stdio bridge to pytapo, used by both desktop apps
```
