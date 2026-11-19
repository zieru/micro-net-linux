#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

install_tinyssh_bins() {
    local src_dir="$1"
    mkdir -p "$ROOTFS_DIR/usr/sbin" "$ROOTFS_DIR/etc/tinyssh" "$ROOTFS_DIR/root/.ssh"
    chmod 0700 "$ROOTFS_DIR/etc/tinyssh" "$ROOTFS_DIR/root/.ssh"
    install -m 0755 "$src_dir/tinysshd" "$ROOTFS_DIR/usr/sbin/tinysshd"
    install -m 0755 "$src_dir/tinysshd-makekey" "$ROOTFS_DIR/usr/sbin/tinysshd-makekey"
}

CACHED_DIR="$CACHE_DIR/tinyssh"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_DIR/tinysshd" ] && [ -s "$CACHED_DIR/tinysshd-makekey" ]; then
    install_tinyssh_bins "$CACHED_DIR"
    log "Using cached TinySSH ($(du -h "$ROOTFS_DIR/usr/sbin/tinysshd" | cut -f1))"
    exit 0
fi

setup_musl_headers

TS_TARBALL="$DL_DIR/tinyssh-${TINYSSH_VERSION}.tar.gz"
TS_URL="https://github.com/janmojzis/tinyssh/archive/refs/tags/${TINYSSH_VERSION}.tar.gz"
TS_SRC="$BUILD_DIR/tinyssh-${TINYSSH_VERSION}"

download_file "$TS_URL" "$TS_TARBALL"
if [ ! -d "$TS_SRC" ]; then
    log "Extracting tinyssh-${TINYSSH_VERSION}..."
    tar -xf "$TS_TARBALL" -C "$BUILD_DIR"
fi

cd "$TS_SRC"
log "Compiling TinySSH ${TINYSSH_VERSION} (static musl)..."
echo "musl-gcc $MUSL_INC_FLAGS -Os -ffunction-sections -fdata-sections -Wall" > conf-cc 2>/dev/null || true
echo "musl-gcc -static -no-pie -Wl,--gc-sections" > conf-ld 2>/dev/null || true

make -j"$JOBS" \
    CC="musl-gcc $MUSL_INC_FLAGS" \
    CFLAGS="-Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-static -no-pie -Wl,--gc-sections"

TINY_BIN="$(find . -type f -name tinysshd -perm -111 | head -n 1)"
MAKEKEY_BIN="$(find . -type f -name tinysshd-makekey -perm -111 | head -n 1)"
[ -n "$TINY_BIN" ] || die "tinysshd binary not found after make"
[ -n "$MAKEKEY_BIN" ] || die "tinysshd-makekey binary not found after make"

strip --strip-all "$TINY_BIN" "$MAKEKEY_BIN" 2>/dev/null || true
assert_static_elf "$TINY_BIN"
assert_static_elf "$MAKEKEY_BIN"

mkdir -p "$CACHED_DIR"
install -m 0755 "$TINY_BIN" "$CACHED_DIR/tinysshd"
install -m 0755 "$MAKEKEY_BIN" "$CACHED_DIR/tinysshd-makekey"
install_tinyssh_bins "$CACHED_DIR"

log "TinySSH installed ($(du -h "$ROOTFS_DIR/usr/sbin/tinysshd" | cut -f1))"
