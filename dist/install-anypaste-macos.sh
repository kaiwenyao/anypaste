#!/bin/bash
#
# AnyPaste for macOS — installer
#
# Downloads the latest release, verifies its SHA-256, signs the app with a
# persistent local identity (no Apple Developer account needed) and installs it
# into /Applications.
#
# Compatible with the macOS system Bash 3.2.
#
set -Eeuo pipefail

REPO="kaiwenyao/anypaste"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
ASSET_ZIP="AnyPaste-macos.zip"
ASSET_SUM="AnyPaste-macos.zip.sha256"

PRODUCT="AnyPaste"
BUNDLE_ID="com.anypaste.mac"
EXECUTABLE="AnyPaste"
CERT_CN="AnyPaste Local Signing"
MIN_MACOS_MAJOR=13

PREFIX="/Applications"
LAUNCH=1
SIGN_MODE="auto"      # auto | local | adhoc
LANG_MODE="auto"
LOCAL_SOURCE=""
MODE="install"

work=""
backup_dir=""

# --------------------------------------------------------------------------
# messaging
# --------------------------------------------------------------------------

msg() {
    local key="$1"
    local en cn
    case "$key" in
        usage)
            en="Usage: install-anypaste-macos.sh [--no-launch] [--prefix DIR] [--sign auto|local|adhoc] [--app PATH] [--uninstall] [--lang en|zh-CN] [--help]"
            cn="用法:install-anypaste-macos.sh [--no-launch] [--prefix 目录] [--sign auto|local|adhoc] [--app 本地.app或zip] [--uninstall] [--lang en|zh-CN] [--help]"
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
            en="[3/5] Signing with a local identity (no Apple account required)…"
            cn="[3/5] 正在用本地签名身份签名(无需 Apple 开发者账号)…"
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
        usage_tip)
            en="Use ⌃⇧V to type the clipboard into any app. Change the shortcut in Settings."
            cn="在任何应用里按 ⌃⇧V 即可把剪贴板内容逐字输入;快捷键可在设置里修改。"
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
            en="The downloaded app bundle is invalid; nothing was installed."
            cn="下载的应用包无效,未安装任何内容。"
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
        adhoc_fallback)
            en="Local signing identity unavailable; the app was signed ad-hoc. macOS may ask for Accessibility again after each update."
            cn="本地签名身份不可用,已改用 ad-hoc 签名。此情况下每次更新后系统可能要求重新授权。"
            ;;
        uninstall_done)
            en="AnyPaste has been removed."
            cn="AnyPaste 已卸载。"
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

keychain_path() {
    printf '%s\n' "$HOME/Library/Keychains/anypaste-signing.keychain-db"
}

state_dir() {
    printf '%s\n' "$HOME/Library/Application Support/AnyPaste"
}

identity_works() {
    local fingerprint="$1" kc="$2" probe rc
    probe=$(mktemp "${TMPDIR:-/tmp}/anypaste-probe.XXXXXX")
    cp /bin/echo "$probe" 2>/dev/null || { rm -f "$probe"; return 1; }
    if run_with_timeout 30 codesign --force --sign "$fingerprint" --keychain "$kc" "$probe" >/dev/null 2>&1; then
        rc=0
    else
        rc=1
    fi
    rm -f "$probe"
    return "$rc"
}

ensure_identity() {
    local kc state password fingerprint tmp p12pass
    kc=$(keychain_path)
    state=$(state_dir)

    mkdir -p "$state"
    chmod 700 "$state"

    if [ ! -f "$state/signing-keychain-password" ]; then
        openssl rand -hex 24 > "$state/signing-keychain-password"
    fi
    chmod 600 "$state/signing-keychain-password"
    password=$(cat "$state/signing-keychain-password")

    if [ ! -f "$kc" ]; then
        security create-keychain -p "$password" "$kc" >/dev/null 2>&1 || return 1
        security set-keychain-settings -lut 21600 "$kc" >/dev/null 2>&1 || true
    fi
    security unlock-keychain -p "$password" "$kc" >/dev/null 2>&1 || return 1

    if [ -s "$state/signing-identity" ]; then
        fingerprint=$(cat "$state/signing-identity")
        if identity_works "$fingerprint" "$kc"; then
            printf '%s\n' "$fingerprint"
            return 0
        fi
    fi

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/anypaste-cert.XXXXXX")
    cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no

[dn]
CN = $CERT_CN
O = AnyPaste Local Signing

[v3]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
EOF

    if ! openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
        -config "$tmp/cert.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 1
    fi

    fingerprint=$(openssl x509 -in "$tmp/cert.pem" -noout -fingerprint -sha1 2>/dev/null | sed 's/.*=//; s/://g')
    if [ -z "$fingerprint" ]; then
        rm -rf "$tmp"
        return 1
    fi

    p12pass=$(openssl rand -hex 16)
    if ! openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -name "$CERT_CN" -out "$tmp/identity.p12" -passout "pass:$p12pass" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 1
    fi

    if ! security import "$tmp/identity.p12" -k "$kc" -P "$p12pass" \
        -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 1
    fi

    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "$password" "$kc" >/dev/null 2>&1 || true

    printf '%s\n' "$fingerprint" > "$state/signing-identity"
    rm -rf "$tmp"
    printf '%s\n' "$fingerprint"
}

# Signs the app, preferring the persistent local identity. Prints the mode used.
sign_app() {
    local app="$1"
    local kc state fingerprint

    kc=$(keychain_path)
    state=$(state_dir)

    if [ "$SIGN_MODE" != "adhoc" ]; then
        if fingerprint=$(ensure_identity) && [ -n "$fingerprint" ]; then
            if run_with_timeout 90 codesign --force --sign "$fingerprint" --keychain "$kc" \
                --identifier "$BUNDLE_ID" --timestamp=none "$app" >/dev/null 2>&1; then
                if run_with_timeout 60 codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
                    codesign -d -r- "$app" 2>/dev/null | sed -n 's/^designated => //p' > "$state/signing-requirement" || true
                    printf 'local\n'
                    return 0
                fi
            fi
        fi
        if [ "$SIGN_MODE" = "local" ]; then
            return 1
        fi
        warn adhoc_fallback
    fi

    run_with_timeout 60 codesign --force --deep --sign - "$app" >/dev/null 2>&1 || return 1
    run_with_timeout 60 codesign --verify --deep --strict "$app" >/dev/null 2>&1 || return 1
    printf 'adhoc\n'
}

# --------------------------------------------------------------------------
# install / uninstall
# --------------------------------------------------------------------------

install_app() {
    local source_zip=""
    local staged="$work/staged/$PRODUCT.app"
    local destination_dir="$PREFIX"
    local destination="$PREFIX/$PRODUCT.app"
    local sign_result=""

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
    /usr/bin/codesign --verify --deep --strict "$staged" >/dev/null 2>&1 || die bundle_invalid

    say signing
    xattr -dr com.apple.quarantine "$staged" >/dev/null 2>&1 || true
    if sign_result=$(sign_app "$staged"); then
        :
    else
        run_with_timeout 60 codesign --force --deep --sign - "$staged" >/dev/null 2>&1 || die failed
        /usr/bin/codesign --verify --deep --strict "$staged" >/dev/null 2>&1 || die failed
        sign_result="adhoc"
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

    sayf installing "$destination_dir"
    quit_running

    if [ -e "$destination" ]; then
        backup_dir="$destination_dir/.${PRODUCT}-previous-$$.app"
        rm -rf "$backup_dir"
        mv "$destination" "$backup_dir" || die failed
    fi

    if ! ditto "$staged" "$destination" >/dev/null 2>&1; then
        rm -rf "$destination" 2>/dev/null || true
        if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
            mv "$backup_dir" "$destination" || true
            backup_dir=""
        fi
        die failed
    fi

    if ! /usr/bin/codesign --verify --deep --strict "$destination" >/dev/null 2>&1; then
        rm -rf "$destination" 2>/dev/null || true
        if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
            mv "$backup_dir" "$destination" || true
            backup_dir=""
        fi
        die failed
    fi

    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir" || true
        backup_dir=""
    fi

    xattr -dr com.apple.quarantine "$destination" >/dev/null 2>&1 || true

    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$destination" >/dev/null 2>&1 || true

    say done
    msg permission
    msg usage_tip
    if [ "$sign_result" = "adhoc" ] && [ "$SIGN_MODE" = "local" ]; then
        warn adhoc_fallback
    fi

    if [ "$LAUNCH" = "1" ]; then
        open "$destination" >/dev/null 2>&1 || true
    fi
}

uninstall_app() {
    local kc state password destination
    kc=$(keychain_path)
    state=$(state_dir)

    quit_running

    destination="$PREFIX/$PRODUCT.app"
    [ -d "$destination" ] || destination="$HOME/Applications/$PRODUCT.app"

    rm -rf "$destination" 2>/dev/null || true
    rm -rf "$HOME/Library/Logs/AnyPaste" 2>/dev/null || true
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

    password=""
    if [ -f "$state/signing-keychain-password" ]; then
        password=$(cat "$state/signing-keychain-password")
    fi
    rm -rf "$state" 2>/dev/null || true

    if [ -f "$kc" ]; then
        if [ -n "$password" ]; then
            security unlock-keychain -p "$password" "$kc" >/dev/null 2>&1 || true
        fi
        run_with_timeout 30 security delete-keychain "$kc" >/dev/null 2>&1 || true
    fi

    msg uninstall_done
}

# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --no-launch) LAUNCH=0 ;;
        --prefix) PREFIX="$2"; shift ;;
        --sign) SIGN_MODE="$2"; shift ;;
        --app) LOCAL_SOURCE="$2"; shift ;;
        --lang) LANG_MODE="$2"; shift ;;
        --uninstall) MODE="uninstall" ;;
        --help|-h) select_language; msg usage; exit 0 ;;
        *) select_language; msg usage >&2; exit 2 ;;
    esac
    shift
done

select_language

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
    install_app
fi
