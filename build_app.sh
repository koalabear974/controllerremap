#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="ControllerRemap"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building release..."
swift build -c release

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
cp "Sources/ControllerRemap/Info.plist" "$CONTENTS/Info.plist"

echo ""
echo "Done! Double-click: $APP_BUNDLE"
echo "(First launch may show an 'unidentified developer' warning — right-click → Open to bypass)"
