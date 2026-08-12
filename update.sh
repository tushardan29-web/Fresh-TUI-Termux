#!/usr/bin/env bash
# Fresh updater for Termux/Android.
#
# Downloads the latest fresh source (default: sinelaw/fresh), applies the
# Termux compatibility patches, builds, verifies under strace, and installs
# over /data/data/com.termux/files/usr/bin/fresh (backing up the previous
# binary). Reuses a shared cargo target dir so successive versions only
# recompile what changed.
#
# Usage: bash update.sh [VERSION]        e.g. bash update.sh 0.4.8
#        bash update.sh --force          rebuild current version (code changed)
# Env:   FRESH_TERMUX_REPO=user/fresh    clone/patch source from a fork
#        FRESH_UPDATE_REPO=user/fresh    also rewrite in-app update-check repo
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REPO=${FRESH_TERMUX_REPO:-sinelaw/fresh}
WORK="${HOME}/.cache/fresh-termux"
BIN="$TERMUX_PREFIX/bin/fresh"
VER=${1:-}
FORCE=0
if [ "$VER" = "--force" ]; then
    FORCE=1
    VER=${2:-}
fi

command -v curl >/dev/null || { echo "need: curl"; exit 1; }
command -v python3 >/dev/null || { echo "need: python3"; exit 1; }
command -v git >/dev/null || { echo "need: git"; exit 1; }
command -v cargo >/dev/null || { echo "need: cargo (pkg install rust)"; exit 1; }

installed=$($BIN --version 2>/dev/null | awk '{print $2}' || echo none)
echo "installed: fresh $installed"

if [ -z "$VER" ]; then
    VER=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' 2>/dev/null \
        || git ls-remote --tags "https://github.com/$REPO" 2>/dev/null | grep -o 'refs/tags/v[0-9.]*$' \
        | sed 's/refs\/tags\/v//' | sort -V | tail -1)
fi
if [ -z "$VER" ]; then echo "could not determine latest version"; exit 1; fi
echo "latest:   fresh $VER"
if [ "$FORCE" = "0" ] && [ "$installed" = "$VER" ]; then
    echo "already up to date."
    exit 0
fi

mkdir -p "$WORK/src"
SRC="$WORK/src/v$VER"
if [ ! -d "$SRC/.git" ]; then
    echo "== cloning $REPO @ v$VER"
    git clone --depth 1 --branch "v$VER" "https://github.com/$REPO" "$SRC"
fi

echo "== patching"
bash "$DIR/termux/patch.sh" "$SRC"

echo "== building (shared target dir: $WORK/target)"
CARGO_TARGET_DIR="$WORK/target" bash "$DIR/termux/build.sh" "$SRC"

echo "== verifying"
bash "$DIR/termux/verify.sh" "$WORK/target/release/fresh" "$WORK/verify-$$"

echo "== installing"
cp "$BIN" "$WORK/fresh.prev.bin" 2>/dev/null || true
cp "$WORK/target/release/fresh" "$BIN"
chmod 755 "$BIN"
rm -f "${HOME}/.config/fresh/logs/init.crashes"
echo "== done: $($BIN --version)"
echo "previous binary kept at $WORK/fresh.prev.bin"