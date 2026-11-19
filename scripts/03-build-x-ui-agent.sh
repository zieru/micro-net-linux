#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

install_agent_bin() {
    local src_bin="$1"
    mkdir -p "$ROOTFS_DIR/usr/local/bin" "$ROOTFS_DIR/etc/x-ui-agent"
    chmod 0700 "$ROOTFS_DIR/etc/x-ui-agent"
    install -m 0755 "$src_bin" "$ROOTFS_DIR/usr/local/bin/x-ui-agent-rs"
}

CACHED_AGENT="$CACHE_DIR/x-ui-agent/x-ui-agent-rs"
if [ "$FORCE_REBUILD" != "1" ] && [ -s "$CACHED_AGENT" ]; then
    install_agent_bin "$CACHED_AGENT"
    log "Using cached x-ui-agent-rs ($(du -h "$ROOTFS_DIR/usr/local/bin/x-ui-agent-rs" | cut -f1))"
    exit 0
fi

command -v cargo >/dev/null 2>&1 || die "cargo is required to build x-ui-agent-rs"

AGENT_SRC="$BUILD_DIR/3x-ui-agent"
if [ ! -d "$AGENT_SRC/.git" ]; then
    log "Cloning ${X_UI_AGENT_REPO} (branch ${X_UI_AGENT_BRANCH})..."
    rm -rf "$AGENT_SRC"
    git clone --depth 1 --branch "$X_UI_AGENT_BRANCH" "$X_UI_AGENT_REPO" "$AGENT_SRC"
else
    log "Updating ${AGENT_SRC}..."
    git -C "$AGENT_SRC" fetch --depth 1 origin "$X_UI_AGENT_BRANCH"
    git -C "$AGENT_SRC" checkout -f FETCH_HEAD
fi

if command -v rustup >/dev/null 2>&1; then
    rustup target add x86_64-unknown-linux-musl >/dev/null 2>&1 || true
fi

log "Compiling x-ui-agent-rs (static musl, embedded shoes)..."
cd "$AGENT_SRC/rust-agent"
cargo build --release --target x86_64-unknown-linux-musl --bin x-ui-agent-rs

BUILT_BIN="$AGENT_SRC/rust-agent/target/x86_64-unknown-linux-musl/release/x-ui-agent-rs"
strip --strip-all "$BUILT_BIN" 2>/dev/null || true
assert_static_elf "$BUILT_BIN"

mkdir -p "$CACHE_DIR/x-ui-agent"
install -m 0755 "$BUILT_BIN" "$CACHED_AGENT"
install_agent_bin "$CACHED_AGENT"

log "x-ui-agent-rs installed ($(du -h "$ROOTFS_DIR/usr/local/bin/x-ui-agent-rs" | cut -f1))"
