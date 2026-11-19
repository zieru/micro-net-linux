#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

install_e2fsprogs_bins() {
    local src_dir="$1"
    mkdir -p "$ROOTFS_DIR/sbin"
    install -m 0755 "$src_dir/resize2fs" "$ROOTFS_DIR/sbin/resize2fs"
    install -m 0755 "$src_dir/e2fsck" "$ROOTFS_DIR/sbin/e2fsck"
    ln -sf e2fsck "$ROOTFS_DIR/sbin/fsck.ext4"
}

CACHED_DIR="$CACHE_DIR/e2fsprogs"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_DIR/resize2fs" ] && [ -s "$CACHED_DIR/e2fsck" ]; then
    install_e2fsprogs_bins "$CACHED_DIR"
    log "Using cached e2fsprogs (resize2fs + e2fsck)"
    exit 0
fi

setup_musl_headers

E2FS_TARBALL="$DL_DIR/e2fsprogs-${E2FSPROGS_VERSION}.tar.xz"
E2FS_URL="https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v${E2FSPROGS_VERSION}/e2fsprogs-${E2FSPROGS_VERSION}.tar.xz"
E2FS_SRC="$BUILD_DIR/e2fsprogs-${E2FSPROGS_VERSION}"

download_file "$E2FS_URL" "$E2FS_TARBALL"

if [ ! -d "$E2FS_SRC" ]; then
    log "Extracting e2fsprogs-${E2FSPROGS_VERSION}..."
    tar -xf "$E2FS_TARBALL" -C "$BUILD_DIR"
fi

cd "$E2FS_SRC"
log "Configuring e2fsprogs ${E2FSPROGS_VERSION} (static musl: resize2fs + e2fsck)..."
./configure \
    --disable-nls \
    --disable-uuidd \
    --disable-fsck \
    --disable-e2initrd-helper \
    --disable-debugfs \
    --disable-imager \
    --enable-relative-symlinks \
    CC="musl-gcc $MUSL_INC_FLAGS" \
    CFLAGS="-Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-static -no-pie -Wl,--gc-sections"

# Note: --disable-resizer only disables debugfs's resizer, not resize2fs; build libs + e2fsck + resize2fs
make -j"$JOBS" libs
make -j"$JOBS" -C e2fsck e2fsck
make -j"$JOBS" -C resize resize2fs

strip --strip-all e2fsck/e2fsck resize/resize2fs 2>/dev/null || true
assert_static_elf e2fsck/e2fsck
assert_static_elf resize/resize2fs

mkdir -p "$CACHED_DIR"
install -m 0755 e2fsck/e2fsck "$CACHED_DIR/e2fsck"
install -m 0755 resize/resize2fs "$CACHED_DIR/resize2fs"
install_e2fsprogs_bins "$CACHED_DIR"

log "e2fsprogs installed (resize2fs=$(du -h "$ROOTFS_DIR/sbin/resize2fs" | cut -f1), e2fsck=$(du -h "$ROOTFS_DIR/sbin/e2fsck" | cut -f1))"
