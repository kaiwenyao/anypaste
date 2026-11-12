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

state="$HOME/Library/Application Support/AnyPaste"
fingerprint=""
if [ -s "$state/signing-identity" ]; then
    fingerprint=$(tr -d '[:space:]' < "$state/signing-identity")
fi

rm -rf "/Applications/AnyPaste.app" "$HOME/Applications/AnyPaste.app"
rm -rf "$HOME/Library/Logs/AnyPaste" "$state"
defaults delete com.anypaste.mac >/dev/null 2>&1 || true

if [ -n "$fingerprint" ]; then
    login_keychain=$(security default-keychain -d user 2>/dev/null | sed 's/^[[:space:]]*"//; s/"$//')
    if [ -n "$login_keychain" ]; then
        security delete-certificate -Z "$fingerprint" -t "$login_keychain" >/dev/null 2>&1 || true
    fi
fi
security delete-keychain "$HOME/Library/Keychains/anypaste-signing.keychain-db" >/dev/null 2>&1 || true

echo "AnyPaste removed."
