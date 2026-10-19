#!/bin/bash
# Builds TapoCam.app into ./dist.
#   ./build-app.sh              native arch
#   UNIVERSAL=1 ./build-app.sh  arm64 + x86_64 (what CI ships)
#   ./build-app.sh --install    also copies it to /Applications
# VERSION / BUILD_NUMBER override the bundle version (CI sets them).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

ARGS=(-c release)
[[ "${UNIVERSAL:-}" == 1 ]] && ARGS+=(--arch arm64 --arch x86_64)
swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/TapoCam"

APP=dist/TapoCam.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TapoCam"
cp ../../shared/tapo_helper.py "$APP/Contents/Resources/"

ICONSET=dist/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift scripts/make-icon.swift dist/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s dist/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) dist/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" dist/icon_1024.png

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>TapoCam</string>
  <key>CFBundleDisplayName</key><string>TapoCam</string>
  <key>CFBundleIdentifier</key><string>com.endless.TapoCam</string>
  <key>CFBundleExecutable</key><string>TapoCam</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>TapoCam connects to your Tapo camera on the local network.</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/TapoCam.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/TapoCam.app"
fi
