#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

setup_musl_headers

DB_TARBALL="$DL_DIR/dropbear-${DROPBEAR_VERSION}.tar.bz2"
DB_URL="https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VERSION}.tar.bz2"
DB_SRC="$BUILD_DIR/dropbear-${DROPBEAR_VERSION}"

download_file "$DB_URL" "$DB_TARBALL"

if [ ! -d "$DB_SRC" ]; then
    log "Extracting dropbear-${DROPBEAR_VERSION}..."
    tar -xf "$DB_TARBALL" -C "$BUILD_DIR"
fi

cd "$DB_SRC"
cp "$ROOT_DIR/configs/dropbear-localoptions.h" localoptions.h

log "Configuring Dropbear ${DROPBEAR_VERSION} (static musl)..."
./configure \
    --disable-zlib \
    --disable-pam \
    --disable-lastlog \
    --disable-utmp \
    --disable-utmpx \
    --disable-wtmp \
    --disable-wtmpx \
    CC="musl-gcc $MUSL_INC_FLAGS" \
    CFLAGS="-Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-static -Wl,--gc-sections"

log "Compiling Dropbear multi-binary..."
make -j"$JOBS" PROGRAMS="dropbear dbclient dropbearkey scp" MULTI=1 STATIC=1

mkdir -p "$ROOTFS_DIR/usr/sbin" "$ROOTFS_DIR/usr/bin"
install -m 0755 dropbearmulti "$ROOTFS_DIR/usr/sbin/dropbearmulti"
strip --strip-all "$ROOTFS_DIR/usr/sbin/dropbearmulti" 2>/dev/null || true

ln -sf dropbearmulti "$ROOTFS_DIR/usr/sbin/dropbear"
ln -sf ../sbin/dropbearmulti "$ROOTFS_DIR/usr/bin/dbclient"
ln -sf ../sbin/dropbearmulti "$ROOTFS_DIR/usr/bin/ssh"
ln -sf ../sbin/dropbearmulti "$ROOTFS_DIR/usr/bin/dropbearkey"
ln -sf ../sbin/dropbearmulti "$ROOTFS_DIR/usr/bin/scp"

log "Dropbear installed ($(du -h "$ROOTFS_DIR/usr/sbin/dropbearmulti" | cut -f1))"
