#!/bin/bash
# Builds the Android TV app and installs it on a TV over adb.
#   ./scripts/install-tv.sh 192.168.0.124
# Optionally push the camera login so you don't have to type it with the remote:
#   ./scripts/install-tv.sh 192.168.0.124 192.168.0.108 <camera-account-user> <camera-account-password>
set -euo pipefail
cd "$(dirname "$0")/.."
TV="${1:?usage: install-tv.sh <tv-ip> [camera-ip user password]}"
[[ "$TV" == *:* ]] || TV="$TV:5555"

./gradlew assembleRelease -q
adb connect "$TV" >/dev/null
adb -s "$TV" install -r app/build/outputs/apk/release/app-release.apk
if [[ $# -ge 4 ]]; then
  adb -s "$TV" shell am start -n com.endless.tapocam/.MainActivity \
    --es host "$2" --es user "$(printf %q "$3")" --es password "$(printf %q "$4")" >/dev/null
else
  adb -s "$TV" shell am start -n com.endless.tapocam/.MainActivity >/dev/null
fi
echo "TapoCam running on $TV"
