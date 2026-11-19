#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

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

yes "" | make oldconfig >/dev/null

log "Compiling BusyBox..."
make -j"$JOBS" \
    HOSTCC=gcc \
    CC="musl-gcc $MUSL_INC_FLAGS" \
    EXTRA_CFLAGS="-Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-static -Wl,--gc-sections"

make CONFIG_PREFIX="$ROOTFS_DIR" install
strip --strip-all "$ROOTFS_DIR/bin/busybox" 2>/dev/null || true
log "BusyBox installed to $ROOTFS_DIR ($(du -h "$ROOTFS_DIR/bin/busybox" | cut -f1))"
