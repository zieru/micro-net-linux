#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

REQUIRED_CMDS=(
    musl-gcc
    make
    bc
    flex
    bison
    xorriso
    extlinux
    sfdisk
    mke2fs
    openssl
    curl
    tar
    gzip
    cargo
    git
)

for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' is not installed."
done

rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"

"$ROOT_DIR/scripts/01-build-kernel.sh"
"$ROOT_DIR/scripts/02-build-busybox.sh"
"$ROOT_DIR/scripts/03-build-x-ui-agent.sh"
"$ROOT_DIR/scripts/03b-build-wireguard.sh"
"$ROOT_DIR/scripts/03c-build-e2fsprogs.sh"
"$ROOT_DIR/scripts/03d-build-htop.sh"
"$ROOT_DIR/scripts/03e-build-tinyssh.sh"
"$ROOT_DIR/scripts/03f-build-nftables.sh"
"$ROOT_DIR/scripts/04-assemble-rootfs.sh"
"$ROOT_DIR/scripts/05-pack-images.sh"

echo ""
echo "=== Build Selesai ==="
ls -lh "$OUT_DIR"
