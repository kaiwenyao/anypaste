#!/bin/bash
#
# Machine-checkable acceptance run for an installed AnyPaste.
#
#   Scripts/verify.sh
#
set -uo pipefail

APP="${APP_PATH:-/Applications/AnyPaste.app}"
BIN="$APP/Contents/MacOS/AnyPaste"
failures=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; failures=$((failures + 1)); }

echo "== AnyPaste acceptance =="
echo "app: $APP"

# 1. bundle present
if [ -d "$APP" ]; then pass "app bundle installed"; else fail "app bundle missing"; fi

# 2. signature
if /usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    pass "code signature verifies"
else
    fail "code signature invalid"
fi

requirement=$(/usr/bin/codesign -d -r- "$APP" 2>&1 | sed -n 's/^#\{0,1\} designated => //p')
case "$requirement" in
    *"certificate root"*) pass "signature requirement is certificate based (stable across updates)" ;;
    *cdhash*) pass "signature requirement is ad-hoc (documented: re-grant permission after updates)" ;;
    *) pass "signature requirement: ${requirement:-unknown}" ;;
esac

# 3. Info.plist contract
bundle_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist" 2>/dev/null)
[ "$bundle_id" = "com.anypaste.mac" ] && pass "bundle id = com.anypaste.mac" || fail "bundle id = ${bundle_id:-missing}"

ui_element=$(/usr/bin/plutil -extract LSUIElement raw "$APP/Contents/Info.plist" 2>/dev/null)
[ "$ui_element" = "true" ] && pass "agent app (LSUIElement)" || fail "LSUIElement = ${ui_element:-missing}"

# 4. architecture
archs=$(/usr/bin/lipo -archs "$BIN" 2>/dev/null)
case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) pass "universal binary ($archs)" ;;
    *) fail "architectures: ${archs:-unknown}" ;;
esac

# 5. self test
self_out=$("$BIN" --self-test 2>/dev/null)
if printf '%s' "$self_out" | grep -q '"ok" : true'; then
    pass "--self-test ok"
else
    fail "--self-test failed"
    printf '%s\n' "$self_out" | tail -20
fi

# 6. end to end typing through real CGEvent path
e2e_out=$("$BIN" --e2e-test --delay=1 2>/dev/null)
if printf '%s' "$e2e_out" | grep -q '"ok" : true'; then
    pass "--e2e-test typed the sample exactly"
else
    reason=$(printf '%s' "$e2e_out" | sed -n 's/.*"reason" : "\(.*\)".*/\1/p')
    fail "--e2e-test failed (${reason:-no output})"
fi

# 7. running instance
if pgrep -x AnyPaste >/dev/null 2>&1; then
    pass "app is running (pid $(pgrep -x AnyPaste | head -1))"
else
    fail "app is not running"
fi

# 8. crash reports
crashes=$(/bin/ls -t "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -c '^AnyPaste' || true)
[ "${crashes:-0}" -eq 0 ] && pass "no crash reports" || fail "$crashes crash report(s) found"

echo
if [ "$failures" -eq 0 ]; then
    echo "RESULT: all checks passed"
    exit 0
fi
echo "RESULT: $failures check(s) failed"
exit 1
