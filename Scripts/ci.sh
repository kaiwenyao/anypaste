#!/bin/bash
#
# Headless CI checks: generated project, universal build, bundle contract and
# the menu/shortcut diagnostics. Does not require Accessibility permission.
#
set -Eeuo pipefail

cd "$(dirname "$0")/.."

echo "== AnyPaste CI =="

echo "-- shell syntax"
for script in Scripts/*.sh dist/*.sh; do
    bash -n "$script"
done

echo "-- installer signing contract"
installer="dist/install-anypaste-macos.sh"
grep -q '^SIGN_MODE="local"' "$installer" || {
    echo "installer must default to the persistent local identity" >&2
    exit 1
}
grep -q 'security add-trusted-cert' "$installer" || {
    echo "installer must trust its certificate for code signing" >&2
    exit 1
}
grep -q 'security find-identity -v -p codesigning' "$installer" || {
    echo "installer must verify the identity is usable for code signing" >&2
    exit 1
}
grep -q 'signing-requirement' "$installer" || {
    echo "installer must save and enforce the designated requirement" >&2
    exit 1
}
grep -q -- '-R "=' "$installer" || {
    echo "installer must verify the saved requirement before replacing the app" >&2
    exit 1
}
bash "$installer" --help >/dev/null

echo "-- generated Xcode project is current"
project_files=(
    "AnyPaste.xcodeproj/project.pbxproj"
    "AnyPaste.xcodeproj/xcshareddata/xcschemes/AnyPaste.xcscheme"
)
before=$(shasum -a 256 "${project_files[@]}")
python3 Scripts/gen_project.py >/dev/null
after=$(shasum -a 256 "${project_files[@]}")
if [ "$before" != "$after" ]; then
    echo "AnyPaste.xcodeproj was stale; run: python3 Scripts/gen_project.py" >&2
    exit 1
fi

echo "-- build (universal, ad-hoc signed for distribution)"
bash Scripts/build.sh

APP="build/DerivedData/Build/Products/Release/AnyPaste.app"
BIN="$APP/Contents/MacOS/AnyPaste"

echo "-- bundle contract"
plutil -lint "$APP/Contents/Info.plist"
bundle_id=$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")
[ "$bundle_id" = "com.anypaste.mac" ] || {
    echo "unexpected bundle id: $bundle_id" >&2
    exit 1
}
ui_element=$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")
[ "$ui_element" = "true" ] || {
    echo "LSUIElement = $ui_element" >&2
    exit 1
}

archs=$(lipo -archs "$BIN")
case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *)
        echo "not a universal binary: $archs" >&2
        exit 1
        ;;
esac
echo "architectures: $archs"

codesign --verify --deep --strict "$APP"

echo "-- headless self-test"
self_out=$("$BIN" --self-test --skip-accessibility-check 2>/dev/null)
printf '%s\n' "$self_out"
printf '%s' "$self_out" | grep -q '"ok" : true'

echo "CI checks passed"
