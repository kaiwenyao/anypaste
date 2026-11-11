#!/bin/bash
#
# Builds AnyPaste.app (universal: arm64 + x86_64) and ad-hoc signs it.
#
set -Eeuo pipefail

cd "$(dirname "$0")/.."
mkdir -p build

CONFIG="${1:-Release}"

xcodebuild -project AnyPaste.xcodeproj -scheme AnyPaste -configuration "$CONFIG" \
    -derivedDataPath build/DerivedData build >build/xcodebuild.log 2>&1 || {
    echo "build failed; last lines of build/xcodebuild.log:" >&2
    tail -40 build/xcodebuild.log >&2
    exit 1
}

APP="build/DerivedData/Build/Products/$CONFIG/AnyPaste.app"
[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }

codesign --force --deep --sign - "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP"

echo "built: $APP"
lipo -info "$APP/Contents/MacOS/AnyPaste" | sed 's/^/  /'
