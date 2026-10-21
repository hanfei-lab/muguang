#!/bin/bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_PATH="${MUGUANG_BUILD_DIR:-"$SOURCE_ROOT/work/build"}"
mkdir -p "$BUILD_PATH"
BUILD_PATH="$(cd "$BUILD_PATH" && pwd -P)"
if [ "$(uname -m)" = arm64 ]; then TEST_TARGET=arm64-apple-macos11.0; else TEST_TARGET=x86_64-apple-macos10.15; fi
xcrun swiftc -target "$TEST_TARGET" -module-cache-path "$BUILD_PATH/module-cache" "$SOURCE_ROOT/Sources/Core.swift" "$SOURCE_ROOT/Tests/CoreTests.swift" -o "$BUILD_PATH/CoreTests"
"$BUILD_PATH/CoreTests"
xcrun swiftc -target "$TEST_TARGET" -module-cache-path "$BUILD_PATH/module-cache" "$SOURCE_ROOT/Sources/Core.swift" \
    "$SOURCE_ROOT/Sources/DisplayEngine.swift" "$SOURCE_ROOT/Tests/DisplayTests.swift" \
    -framework AppKit -framework CoreGraphics -o "$BUILD_PATH/DisplayTests"
"$BUILD_PATH/DisplayTests"
xcrun swiftc -target "$TEST_TARGET" -module-cache-path "$BUILD_PATH/module-cache" \
    "$SOURCE_ROOT/Sources/Core.swift" "$SOURCE_ROOT/Sources/DisplayEngine.swift" "$SOURCE_ROOT/Sources/DisplayRecovery.swift" \
    "$SOURCE_ROOT/Tests/RecoveryTests.swift" -framework AppKit -framework CoreGraphics -o "$BUILD_PATH/RecoveryTests"
"$BUILD_PATH/RecoveryTests"
xcrun swiftc -target "$TEST_TARGET" -module-cache-path "$BUILD_PATH/module-cache" \
    "$SOURCE_ROOT/Sources/LoginSupport.swift" "$SOURCE_ROOT/Tests/LoginSupportTests.swift" -o "$BUILD_PATH/LoginSupportTests"
"$BUILD_PATH/LoginSupportTests"
