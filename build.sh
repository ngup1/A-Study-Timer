#!/bin/bash
# Builds StudyTimer.app next to this script.
set -e
cd "$(dirname "$0")"
APP="StudyTimer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Some Command Line Tools installs ship both module.modulemap and bridging.modulemap,
# each defining SwiftBridging, which breaks `import SwiftUI`. Hide the duplicate.
FLAGS=()
SWIFT_INC="$(xcode-select -p)/usr/include/swift"
if [ -f "$SWIFT_INC/module.modulemap" ] && [ -f "$SWIFT_INC/bridging.modulemap" ]; then
  mkdir -p .build
  : > .build/empty.modulemap
  printf '{"version":0,"case-sensitive":"false","roots":[{"type":"file","name":"%s","external-contents":"%s"}]}\n' \
    "$SWIFT_INC/bridging.modulemap" "$(pwd)/.build/empty.modulemap" > .build/vfs.yaml
  FLAGS=(-vfsoverlay .build/vfs.yaml)
fi

swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 "${FLAGS[@]}" main.swift -o "$APP/Contents/MacOS/StudyTimer"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Study Timer</string>
  <key>CFBundleDisplayName</key><string>Study Timer</string>
  <key>CFBundleIdentifier</key><string>local.studytimer</string>
  <key>CFBundleExecutable</key><string>StudyTimer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $(pwd)/$APP"

# `./build.sh install` also copies the app to /Applications and relaunches it.
if [ "$1" = "install" ]; then
  pkill -x StudyTimer 2>/dev/null || true
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  open "/Applications/$APP"
  echo "Installed /Applications/$APP"
fi
