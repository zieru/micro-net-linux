#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

install_terminfo_minimal() {
    local ti_dest="$ROOTFS_DIR/usr/share/terminfo"
    mkdir -p "$ti_dest/l" "$ti_dest/v" "$ti_dest/x"
    for entry in l/linux v/vt100 x/xterm x/xterm-256color; do
        for base in "$CACHE_DIR/htop/terminfo" /lib/terminfo /usr/share/terminfo; do
            if [ -f "$base/$entry" ]; then
                cp -f "$base/$entry" "$ti_dest/$entry"
                mkdir -p "$CACHE_DIR/htop/terminfo/$(dirname "$entry")"
                cp -f "$base/$entry" "$CACHE_DIR/htop/terminfo/$entry"
                break
            fi
        done
    done
}

install_htop_bin() {
    local src_bin="$1"
    mkdir -p "$ROOTFS_DIR/usr/bin"
    install -m 0755 "$src_bin" "$ROOTFS_DIR/usr/bin/htop"
    install_terminfo_minimal
}

CACHED_HTOP="$CACHE_DIR/htop/htop"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_HTOP" ]; then
    install_htop_bin "$CACHED_HTOP"
    log "Using cached htop ($(du -h "$ROOTFS_DIR/usr/bin/htop" | cut -f1))"
    exit 0
fi

setup_musl_headers

NC_TARBALL="$DL_DIR/ncurses-${NCURSES_VERSION}.tar.gz"
NC_URL="https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"
NC_SRC="$BUILD_DIR/ncurses-${NCURSES_VERSION}"
NC_PREFIX="$BUILD_DIR/ncurses-prefix"

download_file "$NC_URL" "$NC_TARBALL"
if [ ! -d "$NC_SRC" ]; then
    log "Extracting ncurses-${NCURSES_VERSION}..."
    tar -xf "$NC_TARBALL" -C "$BUILD_DIR"
fi

if [ ! -f "$NC_PREFIX/lib/libncurses.a" ]; then
    log "Building ncurses ${NCURSES_VERSION} (static musl)..."
    cd "$NC_SRC"
    ./configure \
        --prefix="$NC_PREFIX" \
        --without-shared \
        --with-normal \
        --without-debug \
        --without-ada \
        --without-cxx \
        --without-cxx-binding \
        --without-manpages \
        --without-progs \
        --without-tests \
        --disable-db-install \
        --with-default-terminfo-dir=/usr/share/terminfo \
        CC="musl-gcc $MUSL_INC_FLAGS" \
        CFLAGS="-Os -ffunction-sections -fdata-sections"
    make -j"$JOBS"
    make install.libs install.includes
fi

HT_TARBALL="$DL_DIR/htop-${HTOP_VERSION}.tar.xz"
HT_URL="https://github.com/htop-dev/htop/releases/download/${HTOP_VERSION}/htop-${HTOP_VERSION}.tar.xz"
HT_SRC="$BUILD_DIR/htop-${HTOP_VERSION}"

download_file "$HT_URL" "$HT_TARBALL"
if [ ! -d "$HT_SRC" ]; then
    log "Extracting htop-${HTOP_VERSION}..."
    tar -xf "$HT_TARBALL" -C "$BUILD_DIR"
fi

cd "$HT_SRC"
log "Configuring htop ${HTOP_VERSION} (static musl)..."
./configure \
    --disable-unicode \
    --disable-sensors \
    --disable-openvz \
    --disable-vserver \
    --disable-ancient-vserver \
    --disable-pcp \
    --disable-capabilities \
    --disable-hwloc \
    CC="musl-gcc $MUSL_INC_FLAGS" \
    CFLAGS="-Os -ffunction-sections -fdata-sections -I$NC_PREFIX/include" \
    LDFLAGS="-static -no-pie -Wl,--gc-sections -L$NC_PREFIX/lib"

log "Compiling htop (static musl)..."
make -j"$JOBS"

strip --strip-all htop 2>/dev/null || true
assert_static_elf htop

mkdir -p "$CACHE_DIR/htop"
install -m 0755 htop "$CACHED_HTOP"
install_htop_bin "$CACHED_HTOP"

log "htop installed ($(du -h "$ROOTFS_DIR/usr/bin/htop" | cut -f1))"
