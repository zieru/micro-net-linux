#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

find_syslinux_file() {
    local name="$1"
    for dir in \
        /usr/lib/ISOLINUX \
        /usr/lib/syslinux/modules/bios \
        /usr/lib/syslinux/mbr \
        /usr/lib/syslinux/bios \
        /usr/lib/syslinux \
        /usr/share/syslinux \
        /usr/lib/EXTLINUX; do
        if [ -f "$dir/$name" ]; then
            echo "$dir/$name"
            return 0
        fi
    done
    return 1
}

IMG_PATH="$OUT_DIR/mini-linux.img"
VDI_PATH="$OUT_DIR/mini-linux.vdi"
ISO_PATH="$OUT_DIR/mini-linux.iso"
IMG_MNT="$BUILD_DIR/img-mnt"
ISO_ROOT="$BUILD_DIR/iso-root"

LOOP_DEV=""
cleanup() {
    set +e
    if mountpoint -q "$IMG_MNT" 2>/dev/null; then
        sudo umount "$IMG_MNT"
    fi
    if [ -n "$LOOP_DEV" ]; then
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ==============================================================================
# Part A: Build 64 MB Zero-Initramfs Raw Disk Image (.img) + Optional .vdi
# ==============================================================================
log "Creating 64 MB zero-initramfs disk image: $IMG_PATH..."
rm -f "$IMG_PATH" "$VDI_PATH"
truncate -s 64M "$IMG_PATH"

printf 'label: dos\nstart=2048, type=83, bootable\n' | sfdisk "$IMG_PATH" >/dev/null

LOOP_DEV="$(sudo losetup -fP --show "$IMG_PATH")"
[ -n "$LOOP_DEV" ] || die "Failed to attach loop device"
PART_DEV="${LOOP_DEV}p1"

# Wait briefly if kernel partition node takes a moment
for _ in 1 2 3 4 5; do
    [ -b "$PART_DEV" ] && break
    sleep 0.3
done
[ -b "$PART_DEV" ] || die "Partition $PART_DEV did not appear"

sudo mke2fs -t ext4 -O ^64bit,^metadata_csum -L MINILINUX -m 1 -q "$PART_DEV"

mkdir -p "$IMG_MNT"
sudo mount "$PART_DEV" "$IMG_MNT"

sudo cp -a "$ROOTFS_DIR/." "$IMG_MNT/"
sudo chown -hR 0:0 "$IMG_MNT"

sudo mkdir -p "$IMG_MNT/boot/extlinux"
sudo tee "$IMG_MNT/boot/extlinux/extlinux.conf" >/dev/null << 'EOF'
PROMPT 1
TIMEOUT 20
DEFAULT sda

LABEL sda
    MENU LABEL Mini-Linux 128MB (Disk /dev/sda1 - VirtualBox/SATA)
    LINUX /boot/bzImage
    APPEND root=/dev/sda1 rw rootwait console=tty0 console=ttyS0,115200 quiet

LABEL vda
    MENU LABEL Mini-Linux 128MB (Disk /dev/vda1 - KVM/VirtIO VPS)
    LINUX /boot/bzImage
    APPEND root=/dev/vda1 rw rootwait console=tty0 console=ttyS0,115200 quiet
EOF

sudo extlinux --install "$IMG_MNT/boot/extlinux"

MBR_BIN="$(find_syslinux_file mbr.bin)" || die "Syslinux mbr.bin not found"
sudo umount "$IMG_MNT"
sudo dd if="$MBR_BIN" of="$LOOP_DEV" bs=440 count=1 conv=notrunc status=none
sync

sudo losetup -d "$LOOP_DEV"
LOOP_DEV=""

log "Disk image ready: $IMG_PATH ($(du -h "$IMG_PATH" | cut -f1))"

if command -v qemu-img >/dev/null 2>&1; then
    qemu-img convert -f raw -O vdi "$IMG_PATH" "$VDI_PATH"
    log "VirtualBox VDI ready: $VDI_PATH ($(du -h "$VDI_PATH" | cut -f1))"
fi

# ==============================================================================
# Part B: Build Zero-Initramfs Custom ISO (.iso)
# ==============================================================================
log "Staging Custom ISO tree in $ISO_ROOT..."
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT"
cp -a "$ROOTFS_DIR/." "$ISO_ROOT/"

# Embed compressed disk image inside ISO so `install-to-disk` works offline
mkdir -p "$ISO_ROOT/boot/isolinux"
gzip -c -9 "$IMG_PATH" > "$ISO_ROOT/boot/mini-linux.img.gz"

ISOLINUX_BIN="$(find_syslinux_file isolinux.bin)" || die "isolinux.bin not found"
LDLINUX_C32="$(find_syslinux_file ldlinux.c32)" || die "ldlinux.c32 not found"

cp "$ISOLINUX_BIN" "$ISO_ROOT/boot/isolinux/isolinux.bin"
cp "$LDLINUX_C32" "$ISO_ROOT/boot/isolinux/ldlinux.c32"

for mod in menu.c32 libutil.c32; do
    if mod_path="$(find_syslinux_file "$mod")"; then
        cp "$mod_path" "$ISO_ROOT/boot/isolinux/$mod"
    fi
done

cat > "$ISO_ROOT/boot/isolinux/isolinux.cfg" << 'EOF'
PROMPT 1
TIMEOUT 30
DEFAULT live

LABEL live
    MENU LABEL Mini-Linux 128MB (Zero-Initramfs ISO /dev/sr0)
    KERNEL /boot/bzImage
    APPEND root=/dev/sr0 rootfstype=iso9660 ro rootwait console=tty0 console=ttyS0,115200 quiet

LABEL vda
    MENU LABEL Boot Installed Disk (/dev/vda1 - KVM/VirtIO)
    KERNEL /boot/bzImage
    APPEND root=/dev/vda1 rw rootwait console=tty0 console=ttyS0,115200 quiet

LABEL sda
    MENU LABEL Boot Installed Disk (/dev/sda1 - VirtualBox/SATA)
    KERNEL /boot/bzImage
    APPEND root=/dev/sda1 rw rootwait console=tty0 console=ttyS0,115200 quiet
EOF

XORRISO_HYBRID_ARGS=()
if ISOHDPFX_BIN="$(find_syslinux_file isohdpfx.bin)"; then
    XORRISO_HYBRID_ARGS=(-isohybrid-mbr "$ISOHDPFX_BIN")
fi

log "Generating bootable hybrid ISO: $ISO_PATH..."
sudo chown -hR 0:0 "$ISO_ROOT"
sudo xorriso -as mkisofs \
    -o "$ISO_PATH" \
    -R -J \
    -V "MINILINUX" \
    -b boot/isolinux/isolinux.bin \
    -c boot/isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    "${XORRISO_HYBRID_ARGS[@]+"${XORRISO_HYBRID_ARGS[@]}"}" \
    "$ISO_ROOT"
sudo chown "$(id -u):$(id -g)" "$ISO_PATH"
sudo rm -rf "$ISO_ROOT"

log "ISO ready: $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"
