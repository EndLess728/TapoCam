# TapoCam for Windows

WPF (.NET 8) port of the macOS app with the same features: live view, HD/SD, pan/tilt pad (hold to repeat) and arrow
keys, presets, privacy / LED / motion / flip / night-vision toggles, siren, calibrate, reboot, snapshots and recordings.

- Video and recording run through a bundled `ffmpeg.exe` (same pipeline as the Mac app).
- Camera controls go through [`shared/tapo_helper.py`](../../shared/tapo_helper.py) and pytapo, using a bundled embedded
  Python. Running a dev build without the bundle, the app falls back to a venv in `%APPDATA%\TapoCam\venv` created from the
  system Python (`py` launcher or `python` on PATH).
- Settings live in `%APPDATA%\TapoCam\settings.json`; passwords are encrypted with DPAPI for the current Windows user.
- Snapshots → `Pictures\TapoCam`, recordings → `Videos\TapoCam`.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| Arrow keys | Pan / tilt |
| Ctrl+Shift+S | Snapshot |
| Ctrl+Shift+R | Start / stop recording |
| Ctrl+R or F5 | Reconnect |
| Ctrl+, | Camera settings |

## Build

On Windows with the .NET 8 SDK and Python 3.12:

```powershell
.\build.ps1                    # → dist\TapoCam (self-contained, with ffmpeg + Python bundled)
.\build.ps1 -Installer         # also → out\TapoCam-<version>-windows-setup.exe (needs Inno Setup 6)
dotnet run --project TapoCam   # quick dev run (uses ffmpeg / Python from PATH)
```

The project also compiles on macOS/Linux (`dotnet build TapoCam`) thanks to `EnableWindowsTargeting`, which is handy for
checking changes, but it only runs on Windows.

The app icon (`TapoCam/Assets/TapoCam.ico`) is rendered from [`apps/macos/scripts/make-icon.swift`](../macos/scripts/make-icon.swift).
