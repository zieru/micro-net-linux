#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DL_DIR="${DL_DIR:-$BUILD_DIR/dl}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
ROOTFS_DIR="${ROOTFS_DIR:-$BUILD_DIR/rootfs}"
CACHE_DIR="${CACHE_DIR:-$BUILD_DIR/cache}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

LINUX_VERSION="${LINUX_VERSION:-6.6.63}"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"
WIREGUARD_TOOLS_VERSION="${WIREGUARD_TOOLS_VERSION:-1.0.20210914}"
E2FSPROGS_VERSION="${E2FSPROGS_VERSION:-1.47.1}"
NCURSES_VERSION="${NCURSES_VERSION:-6.5}"
HTOP_VERSION="${HTOP_VERSION:-3.3.0}"
TINYSSH_VERSION="${TINYSSH_VERSION:-20250501}"
RELEASE_VERSION="${RELEASE_VERSION:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 0.1.0)}"
RELEASE_VERSION="${RELEASE_VERSION#v}"
X_UI_AGENT_REPO="${X_UI_AGENT_REPO:-https://github.com/zieru/3x-ui.git}"
X_UI_AGENT_BRANCH="${X_UI_AGENT_BRANCH:-rust-agent}"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

export ROOT_DIR BUILD_DIR DL_DIR OUT_DIR ROOTFS_DIR CACHE_DIR FORCE_REBUILD JOBS
export LINUX_VERSION BUSYBOX_VERSION WIREGUARD_TOOLS_VERSION E2FSPROGS_VERSION
export NCURSES_VERSION HTOP_VERSION TINYSSH_VERSION RELEASE_VERSION
export X_UI_AGENT_REPO X_UI_AGENT_BRANCH

mkdir -p \
    "$BUILD_DIR" \
    "$DL_DIR" \
    "$OUT_DIR" \
    "$ROOTFS_DIR" \
    "$CACHE_DIR/kernel" \
    "$CACHE_DIR/busybox" \
    "$CACHE_DIR/x-ui-agent" \
    "$CACHE_DIR/wireguard" \
    "$CACHE_DIR/e2fsprogs" \
    "$CACHE_DIR/htop" \
    "$CACHE_DIR/tinyssh" \
    "$CACHE_DIR/ccache"

log() {
    echo "[build] $*"
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

download_file() {
    local url="$1"
    local dest="$2"
    if [ -s "$dest" ]; then
        log "Using cached $(basename "$dest")"
        return 0
    fi
    log "Downloading $url..."
    local tmp="${dest}.part"
    curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"
    mv "$tmp" "$dest"
}

setup_musl_headers() {
    local inc="$BUILD_DIR/musl-inc"
    mkdir -p "$inc"

    for dir in linux asm-generic mtd scsi sound video misc; do
        if [ -d "/usr/include/$dir" ]; then
            ln -sfn "/usr/include/$dir" "$inc/$dir"
        fi
    done

    if [ -d /usr/include/x86_64-linux-gnu/asm ]; then
        ln -sfn /usr/include/x86_64-linux-gnu/asm "$inc/asm"
    elif [ -d /usr/include/asm ]; then
        ln -sfn /usr/include/asm "$inc/asm"
    fi

    export MUSL_INC_FLAGS="-isystem $inc"
}

assert_static_elf() {
    local bin="$1"
    [ -f "$bin" ] || die "Expected binary not found: $bin"
    if command -v readelf >/dev/null 2>&1; then
        if readelf -l "$bin" 2>/dev/null | grep -q "INTERP"; then
            die "Binary $bin is dynamically linked (expected static ELF)!"
        fi
    fi
}
