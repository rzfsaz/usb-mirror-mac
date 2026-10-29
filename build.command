#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/USB Mirror.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 Source/main.swift -o "$APP/Contents/MacOS/USBMirror" -framework Cocoa -framework SwiftUI -framework AVFoundation -framework CoreMediaIO
cp Source/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Selesai: $APP"
