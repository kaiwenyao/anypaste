#!/bin/bash
#
# Packages AnyPaste.app and publishes it as a GitHub release.
#
#   Scripts/release.sh 1.0.0
#
# Assets (version-independent names so /releases/latest/download/ always works):
#   install-anypaste-macos.sh
#   AnyPaste-macos.zip
#   AnyPaste-macos.zip.sha256
#
set -Eeuo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: Scripts/release.sh <version, e.g. 1.0.0>}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "version must look like 1.2.3, got: $VERSION" >&2
    exit 1
fi
REPO="kaiwenyao/anypaste"
TAG="v$VERSION"

bash Scripts/build.sh

APP="build/DerivedData/Build/Products/Release/AnyPaste.app"

# The release tag and the version embedded in the app must agree, otherwise the
# in-app update check would keep reporting the wrong newest version.
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || true)
APP_BUILD=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist" 2>/dev/null || true)
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "release version $VERSION does not match the built app version ${APP_VERSION:-unknown}." >&2
    echo "Bump CFBundleShortVersionString in AnyPaste/Info.plist, run python3 Scripts/gen_project.py, then retry." >&2
    exit 1
fi
case "$APP_BUILD" in
    ''|*[!0-9]*)
        echo "CFBundleVersion must be a positive integer, got: ${APP_BUILD:-missing}" >&2
        exit 1
        ;;
esac
if [ "$APP_BUILD" -le 0 ]; then
    echo "CFBundleVersion must be a positive integer, got: $APP_BUILD" >&2
    exit 1
fi

STAGE="build/release"

rm -rf "$STAGE"
mkdir -p "$STAGE"

ditto "$APP" "$STAGE/AnyPaste.app"
codesign --force --deep --sign - "$STAGE/AnyPaste.app" >/dev/null 2>&1
codesign --verify --deep --strict "$STAGE/AnyPaste.app"

# The distributed app must stay ad-hoc signed. The installer re-signs it with
# each user's own persistent identity, which is what lets TCC keep the
# Accessibility grant across updates. Never sign the release with a local
# Developer/certificate identity: other users' TCC records would not match it.
asset_requirement=$(codesign -d -r- "$STAGE/AnyPaste.app" 2>/dev/null \
    | sed -n 's/^#\{0,1\} designated => //p')
case "$asset_requirement" in
    *cdhash*) ;;
    *)
        echo "release app must be ad-hoc signed, got: ${asset_requirement:-unknown}" >&2
        exit 1
        ;;
esac

ditto -c -k --sequesterRsrc --keepParent "$STAGE/AnyPaste.app" "$STAGE/AnyPaste-macos.zip"
shasum -a 256 "$STAGE/AnyPaste-macos.zip" | awk '{print $1"  AnyPaste-macos.zip"}' \
    > "$STAGE/AnyPaste-macos.zip.sha256"

cp dist/install-anypaste-macos.sh "$STAGE/install-anypaste-macos.sh"
chmod +x "$STAGE/install-anypaste-macos.sh"

cat > "$STAGE/notes.md" <<EOF
## AnyPaste $VERSION (macOS)

Install:

\`\`\`bash
curl -fL --proto '=https' --proto-redir '=https' \\
  -o install-anypaste-macos.sh \\
  https://github.com/${REPO}/releases/latest/download/install-anypaste-macos.sh \\
  && bash install-anypaste-macos.sh
\`\`\`

- Universal binary (Apple Silicon + Intel), macOS 13+
- The installer creates a persistent local signing identity and trusts it once; the Accessibility grant is preserved across future updates (no Apple Developer account needed)
- Updating from an older ad-hoc signed version asks for one final Accessibility approval; later updates reuse the identity
- Update with the installer; do not drag the zip app over /Applications
- Settings → Permissions & Diagnostics explains the version/build numbers and can check GitHub for a newer release
- ⌘W closes the focused window without quitting; ⌘Q quits AnyPaste
- AnyPaste appears in the Dock by default; turn the Dock icon off in Settings → General
- Press ⌃⇧V to type the clipboard into any app
EOF

gh release create "$TAG" \
    --repo "$REPO" \
    --title "AnyPaste $VERSION" \
    --notes-file "$STAGE/notes.md" \
    "$STAGE/AnyPaste-macos.zip" \
    "$STAGE/AnyPaste-macos.zip.sha256" \
    "$STAGE/install-anypaste-macos.sh"

echo "== verifying published assets =="
for asset in install-anypaste-macos.sh AnyPaste-macos.zip AnyPaste-macos.zip.sha256; do
    if curl -fsIL --proto '=https' --proto-redir '=https' \
        "https://github.com/${REPO}/releases/latest/download/$asset" >/dev/null; then
        echo "  ok  $asset"
    else
        echo "  FAIL $asset" >&2
        exit 1
    fi
done

echo "released $TAG"
