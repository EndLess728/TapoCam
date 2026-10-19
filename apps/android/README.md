# TapoCam for Android TV

Live view (Media3 ExoPlayer RTSP, with sound toggle and HD/SD), pan/tilt by holding the D-pad, and ONVIF presets
(go to / save / long-press to delete). Press **OK** for the menu.

Only the Camera Account is needed: controls use ONVIF on port 2020. Privacy / LED / night-vision toggles are desktop-only
(they need the Tapo app login).

## Build and install

```sh
./gradlew assembleRelease                                                # → app/build/outputs/apk/release/app-release.apk
./scripts/install-tv.sh 192.168.0.124                                    # build + install on a TV over adb
./scripts/install-tv.sh 192.168.0.124 192.168.0.108 <user> <password>    # also push the camera login
```

The release APK is signed with the debug key so it can be sideloaded. The launcher banner is rendered by
[`scripts/make-banner.swift`](scripts/make-banner.swift).
