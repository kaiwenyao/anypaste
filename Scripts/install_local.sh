#!/bin/bash
#
# Installs the locally built app into /Applications using the same installer
# logic as the public one-liner (checksum step is skipped for local builds).
#
set -Eeuo pipefail

cd "$(dirname "$0")/.."

APP="build/DerivedData/Build/Products/Release/AnyPaste.app"
[ -d "$APP" ] || { echo "build first: Scripts/build.sh" >&2; exit 1; }

exec bash dist/install-anypaste-macos.sh --app "$APP" "$@"
