#!/bin/bash
#
# Removes AnyPaste, its preferences, logs and the local signing identity.
#
set -Eeuo pipefail

cd "$(dirname "$0")/.."

if [ -f dist/install-anypaste-macos.sh ]; then
    bash dist/install-anypaste-macos.sh --uninstall
    exit $?
fi

osascript -e 'tell application id "com.anypaste.mac" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x AnyPaste >/dev/null 2>&1 || true

rm -rf "/Applications/AnyPaste.app" "$HOME/Applications/AnyPaste.app"
rm -rf "$HOME/Library/Logs/AnyPaste" "$HOME/Library/Application Support/AnyPaste"
defaults delete com.anypaste.mac >/dev/null 2>&1 || true
security delete-keychain "$HOME/Library/Keychains/anypaste-signing.keychain-db" >/dev/null 2>&1 || true

echo "AnyPaste removed."
