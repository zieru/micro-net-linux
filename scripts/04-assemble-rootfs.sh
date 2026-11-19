#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log "Assembling rootfs in $ROOTFS_DIR..."

mkdir -p \
    "$ROOTFS_DIR/dev" \
    "$ROOTFS_DIR/proc" \
    "$ROOTFS_DIR/sys" \
    "$ROOTFS_DIR/run" \
    "$ROOTFS_DIR/tmp" \
    "$ROOTFS_DIR/var" \
    "$ROOTFS_DIR/mnt" \
    "$ROOTFS_DIR/boot" \
    "$ROOTFS_DIR/root/.ssh" \
    "$ROOTFS_DIR/etc/dropbear" \
    "$ROOTFS_DIR/etc/wireguard" \
    "$ROOTFS_DIR/etc/ssl/certs" \
    "$ROOTFS_DIR/usr/local/bin"

chmod 0700 "$ROOTFS_DIR/root" "$ROOTFS_DIR/root/.ssh" "$ROOTFS_DIR/etc/dropbear" "$ROOTFS_DIR/etc/wireguard"
chmod 1777 "$ROOTFS_DIR/tmp"

# Copy repository rootfs templates & scripts
cp -a "$ROOT_DIR/rootfs/." "$ROOTFS_DIR/"

# Ensure permissions on scripts
chmod 0755 "$ROOTFS_DIR/etc/init.d/"*
chmod 0755 "$ROOTFS_DIR/usr/share/udhcpc/default.script"
chmod 0755 "$ROOTFS_DIR/usr/sbin/save-config"
chmod 0755 "$ROOTFS_DIR/usr/sbin/install-to-disk"
chmod 0755 "$ROOTFS_DIR/usr/sbin/check-readiness"

# Account files (/etc/passwd, /etc/group, /etc/shadow)
ROOT_PASSWORD="${ROOT_PASSWORD:-minilinux}"
if command -v openssl >/dev/null 2>&1; then
    HASH="$(openssl passwd -6 "$ROOT_PASSWORD")"
else
    # Fallback SHA-512 hash for "minilinux"
    HASH='$6$minilinux$DUKRHaOrYuOc.RJ0FNZGLYFI2Dq35zNhI6fOCqAdfrH.SaWd1Ly64rD8HF2X7rJ7CKu4e21Mz.9oPVgbgjdsi0'
fi

cat > "$ROOTFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
EOF

cat > "$ROOTFS_DIR/etc/group" << 'EOF'
root:x:0:
tty:x:5:
nogroup:x:65534:
EOF

cat > "$ROOTFS_DIR/etc/shadow" << EOF
root:${HASH}:19000:0:99999:7:::
nobody:*:19000:0:99999:7:::
EOF

chmod 0644 "$ROOTFS_DIR/etc/passwd" "$ROOTFS_DIR/etc/group"
chmod 0600 "$ROOTFS_DIR/etc/shadow"

# Root CA Certificates for TLS / VLESS REALITY / HTTPS
CA_DEST="$ROOTFS_DIR/etc/ssl/certs/ca-certificates.crt"
if [ -s /etc/ssl/certs/ca-certificates.crt ]; then
    cp /etc/ssl/certs/ca-certificates.crt "$CA_DEST"
elif [ -s /etc/pki/tls/certs/ca-bundle.crt ]; then
    cp /etc/pki/tls/certs/ca-bundle.crt "$CA_DEST"
else
    download_file "https://curl.se/ca/cacert.pem" "$CA_DEST"
fi
chmod 0644 "$CA_DEST"
ln -sf certs/ca-certificates.crt "$ROOTFS_DIR/etc/ssl/cert.pem"

# Copy kernel bzImage into /boot for EXTLINUX / disk installs
[ -s "$OUT_DIR/bzImage" ] || die "Missing $OUT_DIR/bzImage. Run 01-build-kernel.sh first."
cp "$OUT_DIR/bzImage" "$ROOTFS_DIR/boot/bzImage"

log "Rootfs assembled successfully ($(du -sh "$ROOTFS_DIR" | cut -f1))"
