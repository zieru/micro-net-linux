#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

CACHED_WG="$CACHE_DIR/wireguard/wg"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_WG" ]; then
    mkdir -p "$ROOTFS_DIR/usr/bin"
    install -m 0755 "$CACHED_WG" "$ROOTFS_DIR/usr/bin/wg"
    log "Using cached WireGuard CLI ($(du -h "$ROOTFS_DIR/usr/bin/wg" | cut -f1))"
    exit 0
fi

setup_musl_headers

WG_TARBALL="$DL_DIR/wireguard-tools-${WIREGUARD_TOOLS_VERSION}.tar.xz"
WG_URL="https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-${WIREGUARD_TOOLS_VERSION}.tar.xz"
WG_SRC="$BUILD_DIR/wireguard-tools-${WIREGUARD_TOOLS_VERSION}"

download_file "$WG_URL" "$WG_TARBALL"

if [ ! -d "$WG_SRC" ]; then
    log "Extracting wireguard-tools-${WIREGUARD_TOOLS_VERSION}..."
    tar -xf "$WG_TARBALL" -C "$BUILD_DIR"
fi

cd "$WG_SRC/src"
log "Compiling static wg CLI (musl)..."
make clean >/dev/null 2>&1 || true

# Pass CFLAGS/LDFLAGS via environment so Makefile's `CFLAGS +=` flags remain active
CFLAGS="-Os -ffunction-sections -fdata-sections" \
LDFLAGS="-static -Wl,--gc-sections" \
make -j"$JOBS" \
    CC="musl-gcc $MUSL_INC_FLAGS" \
    WITH_BASHCOMPLETION=no \
    WITH_WGQUICK=no \
    WITH_SYSTEMDUNITS=no \
    wg

strip --strip-all wg 2>/dev/null || true
install -m 0755 wg "$CACHED_WG"

mkdir -p "$ROOTFS_DIR/usr/bin"
install -m 0755 "$CACHED_WG" "$ROOTFS_DIR/usr/bin/wg"

log "WireGuard CLI installed: $ROOTFS_DIR/usr/bin/wg ($(du -h "$ROOTFS_DIR/usr/bin/wg" | cut -f1))"
