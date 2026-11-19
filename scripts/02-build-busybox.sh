#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

CACHED_BB_TAR="$CACHE_DIR/busybox/busybox-rootfs.tar.gz"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_BB_TAR" ]; then
    tar -xzf "$CACHED_BB_TAR" -C "$ROOTFS_DIR"
    log "Using cached BusyBox rootfs ($(du -h "$ROOTFS_DIR/bin/busybox" | cut -f1))"
    exit 0
fi

setup_musl_headers

BB_TARBALL="$DL_DIR/busybox-${BUSYBOX_VERSION}.tar.bz2"
BB_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
BB_SRC="$BUILD_DIR/busybox-${BUSYBOX_VERSION}"
FRAG="$ROOT_DIR/configs/busybox-mini.fragment"

download_file "$BB_URL" "$BB_TARBALL"

if [ ! -d "$BB_SRC" ]; then
    log "Extracting busybox-${BUSYBOX_VERSION}..."
    tar -xf "$BB_TARBALL" -C "$BUILD_DIR"
fi

cd "$BB_SRC"
log "Configuring BusyBox ${BUSYBOX_VERSION} (static musl)..."
make defconfig

while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [ -z "$line" ] && continue

    key="${line%%=*}"
    val="${line#*=}"

    sed -i -E "/^${key}=/d; /^# ${key} is not set$/d" .config
    if [ "$val" = "n" ]; then
        echo "# ${key} is not set" >> .config
    else
        echo "${key}=${val}" >> .config
    fi
done < "$FRAG"

{ yes "" 2>/dev/null || true; } | make oldconfig >/dev/null

log "Compiling BusyBox..."
BB_MAKE_ARGS=(
    HOSTCC=gcc
    CC="musl-gcc $MUSL_INC_FLAGS"
    EXTRA_CFLAGS="-Os -ffunction-sections -fdata-sections"
    EXTRA_LDFLAGS="-static -no-pie -Wl,--gc-sections"
)
make -j"$JOBS" "${BB_MAKE_ARGS[@]}"

BB_STAGE="$BUILD_DIR/busybox-stage"
rm -rf "$BB_STAGE"
mkdir -p "$BB_STAGE"
make "${BB_MAKE_ARGS[@]}" CONFIG_PREFIX="$BB_STAGE" install
strip --strip-all "$BB_STAGE/bin/busybox" 2>/dev/null || true
assert_static_elf "$BB_STAGE/bin/busybox"

tar -czf "$CACHED_BB_TAR" -C "$BB_STAGE" .
cp -a "$BB_STAGE/." "$ROOTFS_DIR/"
log "BusyBox installed to $ROOTFS_DIR ($(du -h "$ROOTFS_DIR/bin/busybox" | cut -f1))"
