#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DL_DIR="${DL_DIR:-$BUILD_DIR/dl}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
ROOTFS_DIR="${ROOTFS_DIR:-$BUILD_DIR/rootfs}"

LINUX_VERSION="${LINUX_VERSION:-6.6.63}"
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"
DROPBEAR_VERSION="${DROPBEAR_VERSION:-2024.86}"
WIREGUARD_TOOLS_VERSION="${WIREGUARD_TOOLS_VERSION:-1.0.20210914}"

JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

export ROOT_DIR BUILD_DIR DL_DIR OUT_DIR ROOTFS_DIR JOBS
export LINUX_VERSION BUSYBOX_VERSION DROPBEAR_VERSION WIREGUARD_TOOLS_VERSION

mkdir -p "$BUILD_DIR" "$DL_DIR" "$OUT_DIR" "$ROOTFS_DIR"

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

    for dir in linux asm-generic; do
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
