#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

install_nft_bin() {
    local src_bin="$1"
    mkdir -p "$ROOTFS_DIR/usr/sbin"
    install -m 0755 "$src_bin" "$ROOTFS_DIR/usr/sbin/nft"
}

CACHED_NFT="$CACHE_DIR/nftables/nft"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_NFT" ]; then
    install_nft_bin "$CACHED_NFT"
    log "Using cached nft ($(du -h "$ROOTFS_DIR/usr/sbin/nft" | cut -f1))"
    exit 0
fi

setup_musl_headers
NFT_PREFIX="$BUILD_DIR/nft-prefix"
mkdir -p "$NFT_PREFIX"

# 1. libmnl
MNL_TB="$DL_DIR/libmnl-${LIBMNL_VERSION}.tar.bz2"
MNL_URL="https://www.netfilter.org/projects/libmnl/files/libmnl-${LIBMNL_VERSION}.tar.bz2"
MNL_SRC="$BUILD_DIR/libmnl-${LIBMNL_VERSION}"
download_file "$MNL_URL" "$MNL_TB"
[ -d "$MNL_SRC" ] || tar -xf "$MNL_TB" -C "$BUILD_DIR"
if [ ! -f "$NFT_PREFIX/lib/libmnl.a" ]; then
    log "Building libmnl ${LIBMNL_VERSION} (static musl)..."
    cd "$MNL_SRC"
    ./configure \
        --prefix="$NFT_PREFIX" \
        --enable-static \
        --disable-shared \
        CC="musl-gcc $MUSL_INC_FLAGS" \
        CFLAGS="-Os -ffunction-sections -fdata-sections"
    make -j"$JOBS"
    make install
fi

# 2. libnftnl
NFTNL_TB="$DL_DIR/libnftnl-${LIBNFTNL_VERSION}.tar.xz"
NFTNL_URL="https://www.netfilter.org/projects/libnftnl/files/libnftnl-${LIBNFTNL_VERSION}.tar.xz"
NFTNL_SRC="$BUILD_DIR/libnftnl-${LIBNFTNL_VERSION}"
download_file "$NFTNL_URL" "$NFTNL_TB"
[ -d "$NFTNL_SRC" ] || tar -xf "$NFTNL_TB" -C "$BUILD_DIR"
if [ ! -f "$NFT_PREFIX/lib/libnftnl.a" ]; then
    log "Building libnftnl ${LIBNFTNL_VERSION} (static musl)..."
    cd "$NFTNL_SRC"
    PKG_CONFIG_PATH="$NFT_PREFIX/lib/pkgconfig" \
    ./configure \
        --prefix="$NFT_PREFIX" \
        --enable-static \
        --disable-shared \
        CC="musl-gcc $MUSL_INC_FLAGS" \
        CFLAGS="-Os -ffunction-sections -fdata-sections"
    make -j"$JOBS"
    make install
fi

# 3. nftables (nft)
NFT_TB="$DL_DIR/nftables-${NFTABLES_VERSION}.tar.xz"
NFT_URL="https://www.netfilter.org/projects/nftables/files/nftables-${NFTABLES_VERSION}.tar.xz"
NFT_SRC="$BUILD_DIR/nftables-${NFTABLES_VERSION}"
download_file "$NFT_URL" "$NFT_TB"
[ -d "$NFT_SRC" ] || tar -xf "$NFT_TB" -C "$BUILD_DIR"

cd "$NFT_SRC"
log "Configuring nftables ${NFTABLES_VERSION} (static musl)..."
PKG_CONFIG_PATH="$NFT_PREFIX/lib/pkgconfig" \
./configure \
    --prefix="$NFT_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-python \
    --disable-man-doc \
    --disable-debug \
    --without-cli \
    --with-mini-gmp \
    CC="musl-gcc $MUSL_INC_FLAGS" \
    CPPFLAGS="-I$NFT_PREFIX/include" \
    CFLAGS="-Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-static -no-pie -Wl,--gc-sections -L$NFT_PREFIX/lib"

log "Compiling nft (static musl)..."
make -j"$JOBS"

NFT_BIN="$NFT_SRC/src/nft"
[ -f "$NFT_BIN" ] || die "nft binary not found after make"
strip --strip-all "$NFT_BIN" 2>/dev/null || true
assert_static_elf "$NFT_BIN"

mkdir -p "$CACHE_DIR/nftables"
install -m 0755 "$NFT_BIN" "$CACHED_NFT"
install_nft_bin "$CACHED_NFT"

log "nft installed ($(du -h "$ROOTFS_DIR/usr/sbin/nft" | cut -f1))"
