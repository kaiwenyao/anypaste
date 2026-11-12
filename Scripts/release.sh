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
REPO="kaiwenyao/anypaste"
TAG="v$VERSION"

bash Scripts/build.sh

APP="build/DerivedData/Build/Products/Release/AnyPaste.app"
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
- ⌘W closes the focused window without quitting; ⌘Q quits AnyPaste
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
