#!/bin/bash
#
# Machine-checkable acceptance run for an installed AnyPaste.
#
#   Scripts/verify.sh
#
# Momentarily quits and relaunches AnyPaste so the end-to-end test runs through
# LaunchServices; TCC attributes Accessibility to the app, not to this shell.
#
set -uo pipefail

APP="${APP_PATH:-/Applications/AnyPaste.app}"
BIN="$APP/Contents/MacOS/AnyPaste"
STATE_DIR="${ANYPASTE_STATE_DIR:-$HOME/Library/Application Support/AnyPaste}"
LOGIN_KEYCHAIN=$(security default-keychain -d user 2>/dev/null | sed 's/^[[:space:]]*"//; s/"$//')
failures=0

pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; failures=$((failures + 1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }

quit_app() {
    osascript -e 'tell application id "com.anypaste.mac" to quit' >/dev/null 2>&1 || true
    local i=0
    while pgrep -x AnyPaste >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
        sleep 0.25
        i=$((i + 1))
    done
    if pgrep -x AnyPaste >/dev/null 2>&1; then
        pkill -x AnyPaste >/dev/null 2>&1 || true
        sleep 1
    fi
}

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

requirement=$(/usr/bin/codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^#\{0,1\}[[:space:]]*designated => //p')
case "$requirement" in
    *"certificate leaf"*|*"certificate root"*)
        pass "signature requirement is certificate based (stable across updates)"
        ;;
    *cdhash*)
        if [ "${ALLOW_ADHOC:-0}" = "1" ]; then
            warn "signature requirement is ad-hoc (allowed by ALLOW_ADHOC=1; the Accessibility grant will not survive updates)"
        else
            fail "signature requirement is ad-hoc (run the installer without --sign adhoc)"
        fi
        ;;
    *)
        fail "signature requirement: ${requirement:-unknown}"
        ;;
esac

# 2b. persistent local identity (what makes the grant survive updates)
if [ -s "$STATE_DIR/signing-identity" ]; then
    fingerprint=$(tr -d '[:space:]' < "$STATE_DIR/signing-identity")
    if [ -n "$fingerprint" ] && [ -n "$LOGIN_KEYCHAIN" ] \
        && security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -qi "$fingerprint"; then
        pass "signing identity $fingerprint is valid for code signing"
    else
        fail "signing identity ${fingerprint:-missing} is not trusted or not in the login Keychain"
    fi

    if [ -s "$STATE_DIR/signing-certificate.pem" ]; then
        if security verify-cert -L -c "$STATE_DIR/signing-certificate.pem" -p codeSign >/dev/null 2>&1; then
            pass "signing certificate is trusted for code signing"
        else
            fail "signing certificate is not trusted for code signing"
        fi
    else
        warn "signing-certificate.pem is missing; cannot verify certificate trust"
    fi
else
    warn "no saved signing identity at $STATE_DIR (installed by another user, or ad-hoc)"
fi

if [ -s "$STATE_DIR/signing-requirement" ]; then
    saved_requirement=$(tr -d '\r\n' < "$STATE_DIR/signing-requirement")
    if [ "$requirement" = "$saved_requirement" ]; then
        pass "installed requirement matches the saved signing identity"
    else
        fail "installed requirement does not match the saved signing identity"
    fi
else
    warn "no saved signing requirement at $STATE_DIR"
fi

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

# 5. functional self test. Accessibility itself is proven by the LaunchServices
#    e2e run below: TCC attributes permission to the responsible process, and a
#    binary launched directly from this shell is attributed to the shell, which
#    would report axTrusted=false even when AnyPaste is allowed.
self_out=$("$BIN" --self-test --skip-accessibility-check 2>/dev/null)
if printf '%s' "$self_out" | grep -q '^  "ok" : true'; then
    pass "--self-test ok (functional)"
else
    fail "--self-test failed"
    printf '%s\n' "$self_out" | tail -20
fi

# 6. end to end typing through LaunchServices (the normal app launch path).
log_dir="$HOME/Library/Logs/AnyPaste"
e2e_result="$log_dir/e2e-last.json"
rm -f "$e2e_result"
quit_app
open "$APP" --args --e2e-test --delay=1 >/dev/null 2>&1 || true
tries=0
while [ ! -f "$e2e_result" ] && [ "$tries" -lt 40 ]; do
    sleep 0.25
    tries=$((tries + 1))
done
if [ -f "$e2e_result" ] && grep -q '"ok" : true' "$e2e_result"; then
    pass "--e2e-test typed the sample exactly (via LaunchServices)"
else
    reason=""
    if [ -f "$e2e_result" ]; then
        reason=$(sed -n 's/.*"reason" : "\(.*\)".*/\1/p' "$e2e_result" | head -1)
    fi
    fail "--e2e-test failed (${reason:-no result file})"
    [ -f "$e2e_result" ] && tail -10 "$e2e_result"
fi

# The e2e run exits by design; restore the normal instance.
open "$APP" >/dev/null 2>&1 || true
tries=0
while ! pgrep -x AnyPaste >/dev/null 2>&1 && [ "$tries" -lt 20 ]; do
    sleep 0.25
    tries=$((tries + 1))
done

# 7. running instance
if pgrep -x AnyPaste >/dev/null 2>&1; then
    pass "app is running (pid $(pgrep -x AnyPaste | head -1))"
else
    fail "app is not running"
fi

# 8. crash reports
crashes=$(/bin/ls -t "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -c '^AnyPaste' || true)
[ "${crashes:-0}" -eq 0 ] && pass "no crash reports" || fail "$crashes crash report(s) found"

# 9. Dock entry. The app shows a Dock icon by default; a user preference may
#    legitimately turn it off, in which case the check does not apply.
dock_pref=$(/usr/bin/defaults read com.anypaste.mac anypaste.showInDock 2>/dev/null || true)
if [ "$dock_pref" = "0" ] || [ "$dock_pref" = "false" ]; then
    warn "Dock icon disabled by preference (anypaste.showInDock=false); skipped"
else
    sleep 1
    asn=$(/usr/bin/lsappinfo find bundleID=com.anypaste.mac 2>/dev/null | head -1)
    if [ -n "$asn" ] \
        && /usr/bin/lsappinfo info -only ApplicationType "$asn" 2>/dev/null | grep -q 'type="Foreground"'; then
        pass "Dock icon visible (activation policy regular)"
    else
        fail "Dock icon missing (activation policy not regular)"
    fi
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "RESULT: all checks passed"
    exit 0
fi
echo "RESULT: $failures check(s) failed"
exit 1
