#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$SCRIPT_DIR/build/SomaFMMinimal.app"
CONTENTS_DIR="$APP_DIR/Contents"
if SDK_PATH=$(xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null); then
    :
else
    SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$CONTENTS_DIR/MacOS"
swiftc \
    -sdk "$SDK_PATH" \
    -swift-version 5 \
    -o "$CONTENTS_DIR/MacOS/SomaFMMenuBar" \
    "$SCRIPT_DIR"/Sources/SomaFMMenuBar/*.swift \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework AppKit \
    -framework MediaPlayer
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
