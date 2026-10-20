#!/bin/bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="${1:-"$SOURCE_ROOT/../暮光.app"}"
BUILD_PATH="${MUGUANG_BUILD_DIR:-"$SOURCE_ROOT/work/build"}"
mkdir -p "$BUILD_PATH" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
BUILD_PATH="$(cd "$BUILD_PATH" && pwd -P)"
HELPER_PATH="$APP_PATH/Contents/Library/LoginItems/MuguangLoginHelper.app"
mkdir -p "$HELPER_PATH/Contents/MacOS"
SDK_PATH="$(xcrun --show-sdk-path)"
for ARCH_NAME in x86_64 arm64; do
    if [ "$ARCH_NAME" = x86_64 ]; then MIN_VERSION=10.15; else MIN_VERSION=11.0; fi
    xcrun swiftc -O -whole-module-optimization -sdk "$SDK_PATH" \
        -target "$ARCH_NAME-apple-macos$MIN_VERSION" -module-cache-path "$BUILD_PATH/module-cache" \
        "$SOURCE_ROOT"/Sources/*.swift -o "$BUILD_PATH/Muguang-$ARCH_NAME" \
        -framework AppKit -framework CoreGraphics -framework ServiceManagement
    xcrun swiftc -O -whole-module-optimization -sdk "$SDK_PATH" \
        -target "$ARCH_NAME-apple-macos$MIN_VERSION" -module-cache-path "$BUILD_PATH/module-cache" \
        "$SOURCE_ROOT/Sources/LoginSupport.swift" "$SOURCE_ROOT/LoginHelper/main.swift" \
        -framework AppKit -o "$BUILD_PATH/MuguangLoginHelper-$ARCH_NAME"
done
xcrun lipo -create "$BUILD_PATH/Muguang-x86_64" "$BUILD_PATH/Muguang-arm64" -output "$APP_PATH/Contents/MacOS/Muguang"
cp "$SOURCE_ROOT/Info.plist" "$APP_PATH/Contents/Info.plist"
xcrun lipo -create "$BUILD_PATH/MuguangLoginHelper-x86_64" "$BUILD_PATH/MuguangLoginHelper-arm64" -output "$HELPER_PATH/Contents/MacOS/MuguangLoginHelper"
cp "$SOURCE_ROOT/LoginHelper/Info.plist" "$HELPER_PATH/Contents/Info.plist"
xcrun swift -module-cache-path "$BUILD_PATH/module-cache" "$SOURCE_ROOT/MakeIcon.swift" "$BUILD_PATH"
cp "$BUILD_PATH/AppIcon.icns" "$APP_PATH/Contents/Resources/MuguangIcon-v021.icns"
rm -f "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$HELPER_PATH"
codesign --force --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf 'Built: %s\n' "$APP_PATH"
