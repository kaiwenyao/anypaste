#!/bin/bash
#
# AnyPaste for macOS — installer
#
# Downloads the latest release, verifies its SHA-256, signs the app with a
# persistent local code-signing identity (no Apple Developer account needed)
# and installs it into /Applications.
#
# The identity lives in the login Keychain and is reused for every update, so
# macOS can keep the Accessibility grant across versions. The downloaded app is
# ad-hoc signed; only this installer re-signs it with the user's local identity.
#
# Compatible with the macOS system Bash 3.2.
#
set -Eeuo pipefail

# Ignore caller-controlled executable search paths.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077

REPO="kaiwenyao/anypaste"
BASE_URL=""   # resolved at runtime (see resolve_base)
ASSET_ZIP="AnyPaste-macos.zip"
ASSET_SUM="AnyPaste-macos.zip.sha256"

PRODUCT="AnyPaste"
BUNDLE_ID="com.anypaste.mac"
EXECUTABLE="AnyPaste"
CERT_CN="AnyPaste Local Signing"
MIN_MACOS_MAJOR=13

PREFIX="/Applications"
PREFIX_SET=0
LAUNCH=1
SIGN_MODE="local"     # local (default, persistent identity) | adhoc (explicit, re-grant)
RESET_IDENTITY=0
LANG_MODE="auto"
LOCAL_SOURCE=""
MODE="install"

work=""
backup_dir=""

# Signing globals set by ensure_identity / sign_app.
IDENTITY_FP=""
SIGN_KEYCHAIN=""
SIGN_RESULT=""
SIGNED_FINGERPRINT=""

# --------------------------------------------------------------------------
# messaging
# --------------------------------------------------------------------------

msg() {
    local key="$1"
    local en cn
    case "$key" in
        usage)
            en="Usage: install-anypaste-macos.sh [--no-launch] [--prefix DIR] [--sign local|adhoc] [--reset-identity] [--app PATH] [--uninstall] [--lang en|zh-CN] [--help]"
            cn="用法:install-anypaste-macos.sh [--no-launch] [--prefix 目录] [--sign local|adhoc] [--reset-identity] [--app 本地.app或zip] [--uninstall] [--lang en|zh-CN] [--help]"
            ;;
        downloading)
            en="[1/5] Downloading the latest AnyPaste build…"
            cn="[1/5] 正在下载最新 AnyPaste 安装包…"
            ;;
        verifying)
            en="[2/5] Verifying checksum and app bundle…"
            cn="[2/5] 正在校验 SHA-256 与应用包…"
            ;;
        signing)
            en="[3/5] Signing the app locally…"
            cn="[3/5] 正在本地签名…"
            ;;
        installing)
            en="[4/5] Installing into %s…"
            cn="[4/5] 正在安装到 %s…"
            ;;
        done)
            en="[5/5] AnyPaste is installed."
            cn="[5/5] AnyPaste 安装完成。"
            ;;
        permission)
            en="Grant Accessibility in System Settings → Privacy & Security → Accessibility when macOS asks. AnyPaste needs it to type text into other apps."
            cn="macOS 提示时,请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 AnyPaste —— 它需要该权限才能向其它应用逐字输入文字。"
            ;;
        permission_retained)
            en="The signing identity was reused, so your existing Accessibility grant should continue to work. If macOS still reports it as missing, toggle AnyPaste off and on once in System Settings → Privacy & Security → Accessibility."
            cn="签名身份已复用,原有辅助功能授权应继续有效。若系统仍提示未授权,请在“系统设置 → 隐私与安全性 → 辅助功能”里把 AnyPaste 关闭再打开一次。"
            ;;
        migration_permission)
            en="This update moves AnyPaste from an ad-hoc signature to a persistent local identity. macOS needs ONE final Accessibility approval: enable AnyPaste in System Settings → Privacy & Security → Accessibility. Future updates reuse this identity and will not ask again."
            cn="本次更新把 AnyPaste 从 ad-hoc 签名切换为持久本地身份。macOS 需要最后一次辅助功能授权:请在“系统设置 → 隐私与安全性 → 辅助功能”中勾选 AnyPaste。以后升级会复用该身份,不再要求重复授权。"
            ;;
        usage_tip)
            en="Use ⌃⇧V to type the clipboard into any app. Change the shortcut in Settings."
            cn="在任何应用里按 ⌃⇧V 即可把剪贴板内容逐字输入;快捷键可在设置里修改。"
            ;;
        keychain_prompt)
            en="Creating a 10-year self-signed code-signing certificate in your login Keychain. macOS may request Keychain access or a trust confirmation once; this identity is reused on future updates."
            cn="正在登录钥匙串中创建 10 年期自签代码签名证书。macOS 可能请求一次钥匙串访问或信任确认;以后升级会复用该身份。"
            ;;
        verify_failed)
            en="Checksum verification failed. The download was corrupted or tampered with; nothing was installed."
            cn="SHA-256 校验失败:下载文件损坏或被篡改,未安装任何内容。"
            ;;
        download_failed)
            en="Download failed. Check your network and try again."
            cn="下载失败,请检查网络后重试。"
            ;;
        bundle_invalid)
            en="The downloaded app bundle is invalid or has the wrong bundle identifier; nothing was installed."
            cn="下载的应用包无效或 bundle identifier 不匹配,未安装任何内容。"
            ;;
        signing_failed)
            en="Signing with the persistent identity failed; nothing was installed. Unlock the login Keychain and retry. Do not delete the signing state unless you accept re-granting Accessibility; use --sign adhoc only as a last resort."
            cn="使用持久身份签名失败,未安装任何内容。请解锁登录钥匙串后重试。除非接受重新授权辅助功能,否则不要删除签名状态;仅作为最后手段使用 --sign adhoc。"
            ;;
        trust_failed)
            en="macOS did not trust the signing certificate for code signing, so nothing was installed. Unlock the login Keychain, re-run, and approve the trust prompt. Use --sign adhoc only if you accept re-granting Accessibility after updates."
            cn="macOS 未将该证书加入代码签名信任,因此未安装任何内容。请解锁登录钥匙串后重试,并允许系统信任提示。仅当你接受每次升级后重新授权时,才使用 --sign adhoc。"
            ;;
        keychain_locked)
            en="The login Keychain is locked or the signing key is not accessible. Unlock the login Keychain in Keychain Access and run the installer again."
            cn="登录钥匙串已锁定,或签名私钥不可访问。请在“钥匙串访问”中解锁登录钥匙串后重新运行安装器。"
            ;;
        identity_failed)
            en="Could not create the local signing identity; nothing was installed. Check that the login Keychain is unlocked and try again."
            cn="无法创建本地签名身份,未安装任何内容。请确认登录钥匙串已解锁后重试。"
            ;;
        identity_interrupted)
            en="A previous signing-identity creation was interrupted. Re-run with --reset-identity to create a new identity (this requires re-granting Accessibility once)."
            cn="上一次签名身份创建被中断。请使用 --reset-identity 重新创建身份(需要重新授权一次辅助功能)。"
            ;;
        identity_missing)
            en="The saved signing identity is missing or unusable, but a saved requirement exists. To protect your Accessibility grant, nothing was installed. Restore the original certificate and private key, or re-run with --reset-identity (requires one re-grant)."
            cn="已保存的签名身份缺失或不可用,但存在已保存的 requirement。为保护辅助功能授权,未安装任何内容。请恢复原证书和私钥,或使用 --reset-identity(需要重新授权一次)。"
            ;;
        identity_ambiguous)
            en="Multiple AnyPaste signing identities are trusted in the login Keychain, so the installer cannot safely choose one. Inspect them in Keychain Access, or re-run with --reset-identity (requires one re-grant)."
            cn="登录钥匙串中存在多个受信任的 AnyPaste 签名身份,安装器无法安全选择。请在“钥匙串访问”中检查,或使用 --reset-identity(需要重新授权一次)。"
            ;;
        legacy_identity_unusable)
            en="The legacy AnyPaste signing identity in anypaste-signing.keychain-db is unavailable or untrusted. Restore its certificate/key, or re-run with --reset-identity (requires one re-grant)."
            cn="旧版 anypaste-signing.keychain-db 中的 AnyPaste 签名身份不可用或未受信任。请恢复其证书/私钥,或使用 --reset-identity(需要重新授权一次)。"
            ;;
        legacy_state_archived)
            en="An incomplete legacy signing state was found and archived; a new login-Keychain identity will be created."
            cn="检测到不完整的旧版签名状态,已归档;将创建新的登录钥匙串身份。"
            ;;
        continuity_failed)
            en="The new app does not satisfy the saved signing requirement, so installation stopped to protect permission continuity. Restore the original signing identity, or re-run with --reset-identity (requires one re-grant)."
            cn="新应用不满足已保存的签名 requirement,为保护授权连续性已停止安装。请恢复原签名身份,或使用 --reset-identity(需要重新授权一次)。"
            ;;
        identity_change_warning)
            en="Warning: the installed AnyPaste was signed by a different identity (possibly another macOS user). Replacing it will change the signature and require re-granting Accessibility once. Use the account that installed AnyPaste to preserve the grant."
            cn="警告:已安装的 AnyPaste 由另一张证书签名(可能是另一个 macOS 用户安装的)。替换后会改变签名,需要重新授权一次辅助功能。请用最初安装 AnyPaste 的系统用户执行更新,以保留授权。"
            ;;
        adhoc_warning)
            en="Signed ad-hoc as requested. This does not preserve the Accessibility grant: macOS may ask you to re-enable AnyPaste after each update. Re-run without --sign adhoc to use the persistent identity."
            cn="已按请求使用 ad-hoc 签名。此方式不会保留辅助功能授权:每次升级后 macOS 可能要求重新勾选。若要使用持久身份,请不要加 --sign adhoc。"
            ;;
        deprecated_auto)
            en="--sign auto is deprecated; using the persistent local identity (same as --sign local)."
            cn="--sign auto 已废弃;改为使用持久本地身份(等同 --sign local)。"
            ;;
        duplicate_install)
            en="Both /Applications/AnyPaste.app and ~/Applications/AnyPaste.app exist; updating /Applications. Remove the extra copy to avoid launching the wrong one."
            cn="/Applications/AnyPaste.app 与 ~/Applications/AnyPaste.app 同时存在;将更新 /Applications。请移除多余副本,避免启动错误的应用。"
            ;;
        reset_done)
            en="The previous signing identity was removed. A new identity will be created; macOS will ask for Accessibility once."
            cn="已移除旧签名身份。将创建新身份;macOS 会要求重新授权一次辅助功能。"
            ;;
        macos_too_old)
            en="AnyPaste requires macOS 13 or later."
            cn="AnyPaste 需要 macOS 13 或更新版本。"
            ;;
        no_root)
            en="Run this script as your desktop user, without sudo."
            cn="请以当前桌面用户运行本脚本,不要使用 sudo。"
            ;;
        arch_unsupported)
            en="Unsupported CPU architecture; AnyPaste ships for Apple Silicon and Intel."
            cn="不支持的 CPU 架构;AnyPaste 支持 Apple Silicon 与 Intel。"
            ;;
        not_writable)
            en="%s is not writable; installing into ~/Applications instead."
            cn="%s 不可写,改为安装到 ~/Applications。"
            ;;
        quit_failed)
            en="A running AnyPaste did not quit. Quit it manually and run this installer again."
            cn="正在运行的 AnyPaste 未能退出,请手动退出后重新运行安装器。"
            ;;
        uninstall_done)
            en="AnyPaste has been removed, including its local signing identity."
            cn="AnyPaste 已卸载,本地签名身份也已移除。"
            ;;
        failed)
            en="Installation failed. Nothing was left half-installed."
            cn="安装失败,未留下半装状态。"
            ;;
        *)
            return 1
            ;;
    esac
    case "$LANG_MODE" in
        zh-CN) printf '%s\n' "$cn" ;;
        *) printf '%s\n' "$en" ;;
    esac
}

say() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[1;36m'; fi
    msg "$1"
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[0m'; fi
}

sayf() {
    local key="$1"; shift
    local text
    text=$(msg "$key")
    # shellcheck disable=SC2059
    printf "$text\n" "$@"
}

warn() {
    msg "$1" >&2
}

die() {
    warn "$1"
    exit 1
}

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

run_with_timeout() {
    local seconds="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$seconds"; kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local watchdog=$!
    local rc=0
    wait "$pid" 2>/dev/null || rc=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return "$rc"
}

cleanup() {
    local status=$?
    if [ -n "$work" ] && [ -d "$work" ]; then
        rm -rf "$work" 2>/dev/null || true
    fi
    return "$status"
}

select_language() {
    [ "$LANG_MODE" = "auto" ] || return 0
    local preference="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    if [ -z "$preference" ] || [ "$preference" = "C" ] || [ "$preference" = "POSIX" ]; then
        preference=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')
    fi
    case "$preference" in
        *zh*) LANG_MODE="zh-CN" ;;
        *) LANG_MODE="en" ;;
    esac
}

macos_major() {
    sw_vers -productVersion 2>/dev/null | cut -d. -f1
}

# Resolve the newest release tag through the API and download from that
# immutable tag URL. Falling back to /releases/latest/download covers rate
# limits; the direct tag URL avoids stale CDN redirects for "latest".
resolve_base() {
    local tag=""
    if command -v curl >/dev/null 2>&1; then
        tag=$(curl --fail --silent --show-error --location --max-time 20 \
            --proto '=https' --proto-redir '=https' \
            "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
            | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    fi
    if [ -n "$tag" ]; then
        printf 'https://github.com/%s/releases/download/%s\n' "$REPO" "$tag"
    else
        printf 'https://github.com/%s/releases/latest/download\n' "$REPO"
    fi
}

fetch() {
    curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 600 --retry 2 --retry-max-time 120 \
        --output "$2" "$1"
}

quit_running() {
    if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        local i=0
        while pgrep -x "$EXECUTABLE" >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
            sleep 0.25
            i=$((i + 1))
        done
        if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
            pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
            sleep 1
        fi
        if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
            die quit_failed
        fi
    fi
}

# --------------------------------------------------------------------------
# local signing identity (no Apple Developer account required)
# --------------------------------------------------------------------------

login_keychain() {
    local kc
    kc=$(security default-keychain -d user 2>/dev/null | sed 's/^[[:space:]]*"//; s/"$//')
    if [ -z "$kc" ]; then
        kc="$HOME/Library/Keychains/login.keychain-db"
    fi
    printf '%s\n' "$kc"
}

legacy_keychain_path() {
    printf '%s\n' "$HOME/Library/Keychains/anypaste-signing.keychain-db"
}

state_dir() {
    printf '%s\n' "$HOME/Library/Application Support/AnyPaste"
}

is_fingerprint() {
    case "$1" in
        ""|*[!0-9A-Fa-f]*) return 1 ;;
    esac
    [ "${#1}" -eq 40 ]
}

normalize_fp() {
    printf '%s\n' "$1" | tr '[:lower:]' '[:upper:]'
}

read_state_fp() {
    local dir="$1" raw
    [ -s "$dir/signing-identity" ] || return 1
    raw=$(tr -d '[:space:]' < "$dir/signing-identity" 2>/dev/null || true)
    is_fingerprint "$raw" || return 1
    normalize_fp "$raw"
}

identity_is_trusted() {
    local fp="$1" kc="$2"
    [ -n "$fp" ] || return 1
    security find-identity -v -p codesigning "$kc" 2>/dev/null | grep -qi "$fp"
}

identity_probe() {
    local fp="$1" kc="$2" probe rc
    probe=$(mktemp "${TMPDIR:-/tmp}/anypaste-probe.XXXXXX") || return 1
    cp /bin/echo "$probe" 2>/dev/null || { rm -f "$probe"; return 1; }
    if run_with_timeout 30 codesign --force --sign "$fp" --keychain "$kc" "$probe" >/dev/null 2>&1; then
        rc=0
    else
        rc=1
    fi
    rm -f "$probe"
    return "$rc"
}

trust_identity() {
    local cert="$1" kc="$2" fp="$3" i=0
    [ -s "$cert" ] || return 1
    identity_is_trusted "$fp" "$kc" && return 0
    # User-domain trust is what TCC and codesign consult. It may prompt for the
    # login Keychain password or a SecurityAgent confirmation, once.
    run_with_timeout 180 security add-trusted-cert -r trustRoot -p codeSign \
        -k "$kc" "$cert" >/dev/null 2>&1 || true
    while [ "$i" -lt 10 ]; do
        if identity_is_trusted "$fp" "$kc"; then
            return 0
        fi
        sleep 0.2
        i=$((i + 1))
    done
    return 1
}

# Prints one "fingerprint|CN" record per valid identity in the keychain.
identities_by_cn() {
    local kc="$1" out
    out=$(security find-identity -v -p codesigning "$kc" 2>/dev/null \
        | sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-Fa-f]\{40\}\) "\(.*\)"$/\1|\2/p' || true)
    printf '%s\n' "$out" | grep -F "|$CERT_CN" | cut -d'|' -f1 || true
}

count_identities_by_cn() {
    local kc="$1" count
    count=$(identities_by_cn "$kc" | grep -c . 2>/dev/null || true)
    printf '%s\n' "${count:-0}"
}

archive_state() {
    local state suffix f
    state=$(state_dir)
    [ -d "$state" ] || return 0
    suffix=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo legacy)
    for f in signing-identity signing-requirement signing-certificate.pem signing-creating signing-trusted signing-keychain-password; do
        if [ -e "$state/$f" ]; then
            mv -f "$state/$f" "$state/$f.legacy-$suffix" 2>/dev/null || true
        fi
    done
}

delete_certs_by_cn() {
    local kc="$1" hashes h
    [ -f "$kc" ] || return 0
    hashes=$(security find-certificate -c "$CERT_CN" -Z "$kc" 2>/dev/null \
        | sed -n 's/^SHA-1 hash: //p' || true)
    # shellcheck disable=SC2086
    for h in $hashes; do
        run_with_timeout 30 security delete-certificate -Z "$h" -t "$kc" >/dev/null 2>&1 || true
    done
}

reset_identity() {
    local state login legacy fp
    state=$(state_dir)
    login=$(login_keychain)
    legacy=$(legacy_keychain_path)

    if fp=$(read_state_fp "$state"); then
        run_with_timeout 30 security delete-certificate -Z "$fp" -t "$login" >/dev/null 2>&1 || true
        if [ -f "$legacy" ]; then
            run_with_timeout 30 security delete-certificate -Z "$fp" -t "$legacy" >/dev/null 2>&1 || true
        fi
    fi
    delete_certs_by_cn "$login"
    if [ -f "$legacy" ]; then
        delete_certs_by_cn "$legacy"
    fi
    archive_state
    rm -f "$state/signing-creating" 2>/dev/null || true
    say reset_done
}

create_identity() {
    local login state tmp fingerprint p12pass
    login=$(login_keychain)
    state=$(state_dir)

    [ -f "$login" ] || die keychain_locked
    if [ -e "$state/signing-creating" ]; then
        die identity_interrupted
    fi

    tmp="$work/identity"
    rm -rf "$tmp"
    mkdir -p "$tmp" || die identity_failed
    : > "$state/signing-creating" 2>/dev/null || die identity_failed

    say keychain_prompt

    cat > "$tmp/cert.cnf" <<EOF
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3

[dn]
CN = $CERT_CN
O = AnyPaste Local Signing

[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
EOF

    if ! openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
        -config "$tmp/cert.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi

    fingerprint=$(openssl x509 -in "$tmp/cert.pem" -noout -fingerprint -sha1 2>/dev/null \
        | sed 's/.*=//; s/://g')
    if ! is_fingerprint "$fingerprint"; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi
    fingerprint=$(normalize_fp "$fingerprint")

    p12pass=$(openssl rand -hex 24 2>/dev/null || true)
    if [ -z "$p12pass" ]; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi
    if ! openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -name "$CERT_CN" -out "$tmp/identity.p12" -passout "pass:$p12pass" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1; then
        rm -f "$state/signing-creating"
        die identity_failed
    fi

    if ! run_with_timeout 120 security import "$tmp/identity.p12" -k "$login" -P "$p12pass" \
        -T /usr/bin/codesign >/dev/null 2>&1; then
        unset p12pass
        rm -f "$state/signing-creating"
        die identity_failed
    fi
    unset p12pass

    # Write the fingerprint/certificate before requesting trust so an
    # interrupted trust prompt can be resumed without creating a second identity.
    if ! printf '%s\n' "$fingerprint" > "$state/signing-identity.tmp" 2>/dev/null \
        || ! mv -f "$state/signing-identity.tmp" "$state/signing-identity" 2>/dev/null; then
        rm -f "$state/signing-creating" "$state/signing-identity.tmp"
        die identity_failed
    fi
    if ! cp "$tmp/cert.pem" "$state/signing-certificate.pem.tmp" 2>/dev/null \
        || ! mv -f "$state/signing-certificate.pem.tmp" "$state/signing-certificate.pem" 2>/dev/null; then
        rm -f "$state/signing-creating" "$state/signing-certificate.pem.tmp"
        die identity_failed
    fi
    rm -f "$state/signing-creating"

    if ! trust_identity "$state/signing-certificate.pem" "$login" "$fingerprint"; then
        die trust_failed
    fi
    if ! identity_probe "$fingerprint" "$login"; then
        die keychain_locked
    fi

    IDENTITY_FP="$fingerprint"
    SIGN_KEYCHAIN="$login"
}

ensure_identity() {
    local login state legacy fp password count
    login=$(login_keychain)
    state=$(state_dir)

    mkdir -p "$state" 2>/dev/null || die identity_failed
    chmod 700 "$state" 2>/dev/null || true
    legacy=$(legacy_keychain_path)

    if fp=$(read_state_fp "$state"); then
        # Legacy standalone-keychain identity from the old --sign local flow.
        if [ -f "$state/signing-keychain-password" ] && [ -f "$legacy" ]; then
            password=$(cat "$state/signing-keychain-password" 2>/dev/null || true)
            if [ -n "$password" ] \
                && run_with_timeout 30 security unlock-keychain -p "$password" "$legacy" >/dev/null 2>&1 \
                && identity_is_trusted "$fp" "$legacy" \
                && identity_probe "$fp" "$legacy"; then
                IDENTITY_FP="$fp"
                SIGN_KEYCHAIN="$legacy"
                return 0
            fi
            die legacy_identity_unusable
        fi

        # Normal login-Keychain identity.
        if [ ! -s "$state/signing-certificate.pem" ]; then
            count=$(count_identities_by_cn "$login")
            if [ "${count:-0}" -eq 1 ]; then
                security find-certificate -c "$CERT_CN" -p "$login" > "$state/signing-certificate.pem" 2>/dev/null || true
            fi
        fi
        [ -s "$state/signing-certificate.pem" ] || die identity_missing
        if ! identity_is_trusted "$fp" "$login"; then
            trust_identity "$state/signing-certificate.pem" "$login" "$fp" || die trust_failed
        fi
        if ! identity_probe "$fp" "$login"; then
            die keychain_locked
        fi
        IDENTITY_FP="$fp"
        SIGN_KEYCHAIN="$login"
        return 0
    fi

    # No usable identity state. Never silently replace an identity that was
    # protecting an existing grant.
    if [ -s "$state/signing-requirement" ]; then
        die identity_missing
    fi
    if [ -e "$state/signing-creating" ]; then
        die identity_interrupted
    fi
    if [ -f "$state/signing-keychain-password" ]; then
        archive_state
        warn legacy_state_archived
    fi

    # Recover an identity whose state directory was removed but whose trusted
    # certificate still lives in the login Keychain.
    count=$(count_identities_by_cn "$login")
    if [ "${count:-0}" -eq 1 ]; then
        fp=$(identities_by_cn "$login" | head -1)
        security find-certificate -c "$CERT_CN" -p "$login" > "$state/signing-certificate.pem" 2>/dev/null || true
        if [ -s "$state/signing-certificate.pem" ] && identity_probe "$fp" "$login"; then
            printf '%s\n' "$fp" > "$state/signing-identity"
            IDENTITY_FP="$fp"
            SIGN_KEYCHAIN="$login"
            return 0
        fi
        rm -f "$state/signing-identity" "$state/signing-certificate.pem"
        die identity_missing
    elif [ "${count:-0}" -gt 1 ]; then
        die identity_ambiguous
    fi

    create_identity
}

# Signs the staged app. Sets SIGN_RESULT and SIGNED_FINGERPRINT; returns
# non-zero on failure. Never falls back from local to ad-hoc.
sign_app() {
    local app="$1" state requirement saved
    state=$(state_dir)

    if [ "$SIGN_MODE" = "local" ]; then
        ensure_identity || return 1
        [ -n "$IDENTITY_FP" ] || return 1
        [ -n "$SIGN_KEYCHAIN" ] || SIGN_KEYCHAIN=$(login_keychain)

        if ! run_with_timeout 90 codesign --force --sign "$IDENTITY_FP" --keychain "$SIGN_KEYCHAIN" \
            --identifier "$BUNDLE_ID" --timestamp=none "$app" >/dev/null 2>&1; then
            return 1
        fi
        if ! run_with_timeout 60 codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
            return 1
        fi

        requirement=$(codesign -d -r- "$app" 2>/dev/null \
            | sed -n 's/^#\{0,1\}[[:space:]]*designated => //p' | head -1 || true)
        case "$requirement" in
            ""|*cdhash*) die continuity_failed ;;
            *certificate*) ;;
            *) die continuity_failed ;;
        esac

        if [ -s "$state/signing-requirement" ]; then
            saved=$(tr -d '\r\n' < "$state/signing-requirement" 2>/dev/null || true)
            if [ -n "$saved" ] \
                && ! run_with_timeout 60 codesign --verify --strict -R "=$saved" "$app" >/dev/null 2>&1; then
                die continuity_failed
            fi
        fi

        printf '%s\n' "$requirement" > "$state/signing-requirement.tmp" 2>/dev/null || die signing_failed
        mv -f "$state/signing-requirement.tmp" "$state/signing-requirement" 2>/dev/null || die signing_failed

        SIGN_RESULT="local"
        SIGNED_FINGERPRINT="$IDENTITY_FP"
        return 0
    fi

    if ! run_with_timeout 60 codesign --force --deep --sign - "$app" >/dev/null 2>&1; then
        return 1
    fi
    if ! run_with_timeout 60 codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
        return 1
    fi
    SIGN_RESULT="adhoc"
    SIGNED_FINGERPRINT=""
    return 0
}

restore_backup() {
    rm -rf "$destination" 2>/dev/null || true
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        mv "$backup_dir" "$destination" 2>/dev/null || true
        backup_dir=""
    fi
}

# --------------------------------------------------------------------------
# install / uninstall
# --------------------------------------------------------------------------

install_app() {
    local source_zip=""
    local staged="$work/staged/$PRODUCT.app"
    local state destination_dir destination sign_result signed_fp
    local had_install=0 had_requirement=0 installed_matches_identity=0 installed_was_adhoc=0
    local installed_req installed_fp requirement

    state=$(state_dir)

    # Keep the existing install path: TCC records are tied to the app, and a
    # stable path avoids surprises on machines where /Applications was not
    # writable during the first install.
    destination_dir="$PREFIX"
    if [ "$PREFIX_SET" = "0" ] && [ ! -d "/Applications/$PRODUCT.app" ] \
        && [ -d "$HOME/Applications/$PRODUCT.app" ]; then
        destination_dir="$HOME/Applications"
    fi
    destination="$destination_dir/$PRODUCT.app"
    [ -d "$destination" ] && had_install=1
    [ -s "$state/signing-requirement" ] && had_requirement=1

    if [ -n "$LOCAL_SOURCE" ]; then
        if [ -d "$LOCAL_SOURCE" ]; then
            mkdir -p "$work/staged"
            ditto "$LOCAL_SOURCE" "$staged" >/dev/null 2>&1 || die bundle_invalid
        elif [ -f "$LOCAL_SOURCE" ]; then
            source_zip="$LOCAL_SOURCE"
        else
            die download_failed
        fi
    else
        say downloading
        BASE_URL=$(resolve_base)
        fetch "$BASE_URL/$ASSET_ZIP" "$work/$ASSET_ZIP" || die download_failed
        fetch "$BASE_URL/$ASSET_SUM" "$work/$ASSET_SUM" || die download_failed
        source_zip="$work/$ASSET_ZIP"
    fi

    say verifying
    if [ -n "$source_zip" ]; then
        local expected actual
        expected=""
        if [ -f "$source_zip.sha256" ]; then
            expected=$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$source_zip.sha256" | head -1)
        elif [ -f "$work/$ASSET_SUM" ]; then
            expected=$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$work/$ASSET_SUM" | head -1)
        fi
        [ -n "$expected" ] || die verify_failed
        actual=$(shasum -a 256 "$source_zip" | awk '{print $1}')
        [ "$actual" = "$expected" ] || die verify_failed

        mkdir -p "$work/staged"
        ditto -x -k "$source_zip" "$work/staged" >/dev/null 2>&1 || die bundle_invalid
    fi

    [ -x "$staged/Contents/MacOS/$EXECUTABLE" ] || die bundle_invalid
    plutil -lint "$staged/Contents/Info.plist" >/dev/null 2>&1 || die bundle_invalid
    bundle_id=$(plutil -extract CFBundleIdentifier raw "$staged/Contents/Info.plist" 2>/dev/null || true)
    [ "$bundle_id" = "$BUNDLE_ID" ] || die bundle_invalid
    /usr/bin/codesign --verify --deep --strict "$staged" >/dev/null 2>&1 || die bundle_invalid

    say signing
    xattr -dr com.apple.quarantine "$staged" >/dev/null 2>&1 || true
    if ! sign_app "$staged"; then
        die signing_failed
    fi
    sign_result="$SIGN_RESULT"
    signed_fp="$SIGNED_FINGERPRINT"

    if [ "$had_install" = "1" ] && [ -n "$signed_fp" ]; then
        installed_req=$(codesign -d -r- "$destination" 2>/dev/null \
            | sed -n 's/^#\{0,1\}[[:space:]]*designated => //p' | head -1 || true)
        installed_fp=""
        case "$installed_req" in
            *cdhash*)
                # The installed copy is ad-hoc: this update is the one-time
                # migration to the persistent identity.
                installed_was_adhoc=1
                ;;
            *certificate*)
                installed_fp=$(printf '%s\n' "$installed_req" \
                    | sed -E 's/.*certificate (leaf|root) = H"([0-9A-Fa-f]*)".*/\2/p' | head -1 || true)
                if [ -n "$installed_fp" ] \
                    && [ "$(normalize_fp "$installed_fp")" = "$(normalize_fp "$signed_fp")" ]; then
                    # The installed app already uses this identity; losing the
                    # state file must not turn this into a re-grant prompt.
                    installed_matches_identity=1
                elif [ -n "$installed_fp" ]; then
                    warn identity_change_warning
                fi
                ;;
        esac
    fi

    if [ ! -w "$destination_dir" ]; then
        mkdir -p "$destination_dir" 2>/dev/null || true
    fi
    if [ ! -w "$destination_dir" ]; then
        warn not_writable
        destination_dir="$HOME/Applications"
        destination="$destination_dir/$PRODUCT.app"
        mkdir -p "$destination_dir"
    fi

    if [ "$PREFIX_SET" = "0" ] && [ -d "/Applications/$PRODUCT.app" ] \
        && [ -d "$HOME/Applications/$PRODUCT.app" ]; then
        warn duplicate_install
    fi

    sayf installing "$destination_dir"
    quit_running

    if [ -e "$destination" ]; then
        backup_dir="$destination_dir/.${PRODUCT}-previous-$$.app"
        rm -rf "$backup_dir"
        mv "$destination" "$backup_dir" || die failed
    fi

    if ! ditto "$staged" "$destination" >/dev/null 2>&1; then
        restore_backup
        die failed
    fi

    if ! /usr/bin/codesign --verify --deep --strict "$destination" >/dev/null 2>&1; then
        restore_backup
        die failed
    fi

    if [ "$sign_result" = "local" ] && [ -s "$state/signing-requirement" ]; then
        requirement=$(tr -d '\r\n' < "$state/signing-requirement" 2>/dev/null || true)
        if [ -n "$requirement" ] \
            && ! /usr/bin/codesign --verify --strict -R "=$requirement" "$destination" >/dev/null 2>&1; then
            restore_backup
            die continuity_failed
        fi
    fi

    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir" || true
        backup_dir=""
    fi

    xattr -dr com.apple.quarantine "$destination" >/dev/null 2>&1 || true

    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$destination" >/dev/null 2>&1 || true

    say done

    case "$sign_result" in
        adhoc)
            warn adhoc_warning
            msg permission
            ;;
        *)
            if [ "$installed_was_adhoc" = "1" ]; then
                msg migration_permission
            elif [ "$had_install" = "1" ] && [ "$had_requirement" = "1" ]; then
                msg permission_retained
            elif [ "$had_install" = "1" ] && [ "$installed_matches_identity" = "1" ]; then
                msg permission_retained
            elif [ "$had_install" = "1" ]; then
                msg migration_permission
            else
                msg permission
            fi
            ;;
    esac
    msg usage_tip

    if [ "$LAUNCH" = "1" ]; then
        open "$destination" >/dev/null 2>&1 || true
    fi
}

uninstall_app() {
    local state login legacy fp destination
    state=$(state_dir)
    login=$(login_keychain)
    legacy=$(legacy_keychain_path)

    quit_running

    destination="$PREFIX/$PRODUCT.app"
    [ -d "$destination" ] || destination="$HOME/Applications/$PRODUCT.app"

    rm -rf "$destination" 2>/dev/null || true
    rm -rf "$HOME/Applications/$PRODUCT.app" 2>/dev/null || true
    rm -rf "$HOME/Library/Logs/AnyPaste" 2>/dev/null || true
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

    if fp=$(read_state_fp "$state"); then
        run_with_timeout 30 security delete-certificate -Z "$fp" -t "$login" >/dev/null 2>&1 || true
        if [ -f "$legacy" ]; then
            run_with_timeout 30 security delete-certificate -Z "$fp" -t "$legacy" >/dev/null 2>&1 || true
        fi
    fi
    delete_certs_by_cn "$login"
    if [ -f "$legacy" ]; then
        delete_certs_by_cn "$legacy"
    fi

    rm -rf "$state" 2>/dev/null || true

    if [ -f "$legacy" ]; then
        run_with_timeout 30 security delete-keychain "$legacy" >/dev/null 2>&1 || true
    fi

    msg uninstall_done
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --no-launch) LAUNCH=0 ;;
        --prefix) PREFIX="$2"; PREFIX_SET=1; shift ;;
        --sign) SIGN_MODE="$2"; shift ;;
        --reset-identity) RESET_IDENTITY=1 ;;
        --app) LOCAL_SOURCE="$2"; shift ;;
        --lang) LANG_MODE="$2"; shift ;;
        --uninstall) MODE="uninstall" ;;
        --help|-h) select_language; msg usage; exit 0 ;;
        *) select_language; msg usage >&2; exit 2 ;;
    esac
    shift
done

select_language

case "$SIGN_MODE" in
    local|adhoc) ;;
    auto)
        warn deprecated_auto
        SIGN_MODE="local"
        ;;
    *)
        msg usage >&2
        exit 2
        ;;
esac

if [ "$(id -u)" -eq 0 ]; then
    die no_root
fi

case "$(uname -m)" in
    arm64|x86_64) : ;;
    *) die arch_unsupported ;;
esac

if [ "$MODE" = "install" ]; then
    major=$(macos_major)
    if [ -n "$major" ] && [ "$major" -lt "$MIN_MACOS_MAJOR" ]; then
        die macos_too_old
    fi
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/anypaste-install.XXXXXX")
trap cleanup EXIT INT TERM
trap 'exit 130' INT TERM

if [ "$MODE" = "uninstall" ]; then
    uninstall_app
else
    if [ "$RESET_IDENTITY" = "1" ]; then
        reset_identity
    fi
    install_app
fi
