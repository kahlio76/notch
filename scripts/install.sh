#!/bin/bash
# Builds Notch, installs it to /Applications and ~/.notch/bin, wires up the
# Claude Code hooks (backing up settings.json first) and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=/Applications/Notch.app

pkill -x Notch 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Notch" "$APP/Contents/MacOS/Notch"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.kahlio76.notch</string>
  <key>CFBundleName</key><string>Notch</string>
  <key>CFBundleExecutable</key><string>Notch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Notch reads and controls Spotify, and switches the Mac between dark and light.</string>
  <key>NSAudioCaptureUsageDescription</key><string>Notch listens to Spotify's output to animate the equalizer. Nothing is recorded.</string>
</dict></plist>
PLIST
# A real identity keeps macOS's Automation approvals across rebuilds.
IDENTITY=$(security find-identity -p codesigning -v | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)
codesign --force --sign "${IDENTITY:--}" "$APP"

mkdir -p ~/.notch/bin
chmod 700 ~/.notch
cp "$BIN/notch-hook" ~/.notch/bin/notch-hook
codesign --force --sign "${IDENTITY:--}" ~/.notch/bin/notch-hook

python3 -I "$PWD/scripts/hooks.py" install
open "$APP"
