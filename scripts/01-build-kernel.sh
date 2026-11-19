#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

CACHED_BZIMAGE="$CACHE_DIR/kernel/bzImage"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_BZIMAGE" ]; then
    cp "$CACHED_BZIMAGE" "$OUT_DIR/bzImage"
    log "Using cached kernel bzImage ($(du -h "$OUT_DIR/bzImage" | cut -f1))"
    exit 0
fi

KERNEL_MAJOR="${LINUX_VERSION%%.*}"
KERNEL_TARBALL="$DL_DIR/linux-${LINUX_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${LINUX_VERSION}.tar.xz"
KERNEL_SRC="$BUILD_DIR/linux-${LINUX_VERSION}"
FRAG="$ROOT_DIR/configs/kernel-mini-x86_64.config"

download_file "$KERNEL_URL" "$KERNEL_TARBALL"

if [ ! -d "$KERNEL_SRC" ]; then
    log "Extracting linux-${LINUX_VERSION}..."
    tar -xf "$KERNEL_TARBALL" -C "$BUILD_DIR"
fi

cd "$KERNEL_SRC"
log "Configuring Linux ${LINUX_VERSION} (tinyconfig + mini-x86_64 fragment)..."
make ARCH=x86_64 tinyconfig
./scripts/kconfig/merge_config.sh -m .config "$FRAG"
make ARCH=x86_64 olddefconfig

# Assert critical options survived olddefconfig
REQUIRED_Y=(
    CONFIG_64BIT
    CONFIG_BLOCK
    CONFIG_MSDOS_PARTITION
    CONFIG_WIREGUARD
    CONFIG_ISO9660_FS
    CONFIG_EXT4_FS
    CONFIG_EXT4_USE_FOR_EXT2
    CONFIG_OVERLAY_FS
    CONFIG_VIRTIO_BLK
    CONFIG_VIRTIO_NET
    CONFIG_E1000
    CONFIG_ATA_PIIX
    CONFIG_SATA_AHCI
    CONFIG_BLK_DEV_SR
    CONFIG_TCP_CONG_BBR
    CONFIG_TUN
    CONFIG_ADVISE_SYSCALLS
    CONFIG_FUTEX
    CONFIG_EPOLL
    CONFIG_KEYBOARD_ATKBD
    CONFIG_UNIX98_PTYS
)

for sym in "${REQUIRED_Y[@]}"; do
    if ! grep -q "^${sym}=y$" .config; then
        die "Mandatory kernel option $sym=y is missing from .config!"
    fi
done

if grep -q "^CONFIG_BLK_DEV_INITRD=y$" .config; then
    die "CONFIG_BLK_DEV_INITRD must remain disabled for zero-initramfs build!"
fi

KERNEL_CC="gcc"
if command -v ccache >/dev/null 2>&1; then
    KERNEL_CC="ccache gcc"
    log "ccache enabled for kernel compilation (CCACHE_DIR=${CCACHE_DIR:-default})"
fi

log "Compiling Linux bzImage using ${JOBS} threads..."
make -j"$JOBS" ARCH=x86_64 CC="$KERNEL_CC" bzImage

cp arch/x86/boot/bzImage "$OUT_DIR/bzImage"
cp arch/x86/boot/bzImage "$CACHED_BZIMAGE"
log "Kernel ready: $OUT_DIR/bzImage ($(du -h "$OUT_DIR/bzImage" | cut -f1))"
