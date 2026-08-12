#!/usr/bin/env bash
# install.sh — install the fresh TUI on Termux/Android from one of three sources.
#
#   [1] Prebuilt GitHub release (tushardan29-web/Fresh-TUI-Termux) — fast, no
#       compiler needed; downloads the aarch64 Android asset to $PREFIX/bin/fresh.
#   [2] Current source on this device (~/.cache/fresh-termux/src) — rebuilt
#       locally with the Termux Android patches and installed (~20 min first time).
#   [3] Original fresh repo (sinelaw/fresh) — downloads the latest official
#       source, patches it for this system's architecture, builds and installs.
#
# Run with no args (in a terminal) to choose interactively. The previous
# binary is always backed up to <BIN>.prev.bin.<pid> (option 1) or
# ~/.cache/fresh-termux/fresh.prev.bin (options 2/3).
#
# Usage:
#   bash install.sh                  # interactive source menu (tty)
#   bash install.sh --release        # force prebuilt release (default non-tty)
#   bash install.sh --source         # force build from current cached source
#   bash install.sh --original       # force build from sinelaw/fresh (latest)
#   bash install.sh --list           # list releases on the prebuilt repo
#   bash install.sh --latest|--yes   # prebuilt: use latest, no prompts
#   bash install.sh v0.4.9           # prebuilt: specific release
#   bash install.sh --help
# Env: FRESH_INSTALL_REPO=user/fresh   # prebuilt release repo
#      FRESH_INSTALL_BIN=/p/fresh     # install location
#      FRESH_TERMUX_REPO=user/fresh   # source repo for --source/--original
#      FRESH_UPDATE_REPO=user/fresh   # bake in-app updater endpoint for builds
#
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
REPO=${FRESH_INSTALL_REPO:-tushardan29-web/Fresh-TUI-Termux}
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN="${FRESH_INSTALL_BIN:-$TERMUX_PREFIX/bin/fresh}"

command -v curl >/dev/null 2>&1 || { echo "need: curl"; exit 1; }

ARCH=aarch64                                # aarch64 Termux-on-Android only for now
ASSET="fresh-editor-${ARCH}-linux-android.tar.xz"
GH="https://github.com/$REPO"
API="https://api.github.com/repos/$REPO"

# ---- helpers ---------------------------------------------------------------
normtag() { case "$1" in v[0-9]*) echo "$1";; [0-9]*) echo "v$1";; *) echo "$1";; esac; }
list_versions() {
    command -v python3 >/dev/null 2>&1 || { git ls-remote --tags "$GH.git" 2>/dev/null | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+' | sed 's#refs/tags/##' | sort -rV | head -10; return; }
    curl -fsSL "$API/releases?per_page=10" \
      | python3 -c 'import json,sys
try:
    for r in json.load(sys.stdin): print(r["tag_name"])
except Exception: pass
' 2>/dev/null \
      || git ls-remote --tags "$GH.git" 2>/dev/null \
      | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+' | sed 's#refs/tags/##' | sort -rV | head -10
}
get_latest() {
    command -v python3 >/dev/null 2>&1 || { git ls-remote --tags "$GH.git" 2>/dev/null | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+' | sed 's#refs/tags/##' | sort -V | tail -1; return; }
    curl -fsSL "$API/releases/latest" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null \
      || git ls-remote --tags "$GH.git" 2>/dev/null \
      | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+' | sed 's#refs/tags/##' | sort -V | tail -1
}

# ---- arg parse -------------------------------------------------------------
TAG=""; MODE=""; LIST_ONLY=0; LATEST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --list|-l)         LIST_ONLY=1; shift ;;
        --release|-r)      MODE=release; shift ;;
        --source|-s)       MODE=source; shift ;;
        --original|-o)     MODE=original; shift ;;
        --latest|--yes|-y) MODE=release; LATEST=1; shift ;;
        -h|--help)         sed -n '2,28p' "$0"; exit 0 ;;
        *)                 MODE=release; TAG=$(normtag "$1"); shift ;;
    esac
done

if [ "$LIST_ONLY" = "1" ]; then
    echo "Releases on $REPO (newest first):"
    list_versions
    exit 0
fi

# ---- interactive source selection ------------------------------------------
if [ -z "$MODE" ]; then
    if [ ! -t 0 ]; then
        MODE=release
        echo "(non-interactive: defaulting to prebuilt release; use --source/--original to build)"
    else
        echo "Install fresh for Termux from:"
        echo "  [1] Prebuilt GitHub release ($REPO) — fast, no build"
        echo "  [2] Current source on this device  — rebuild with Android patches"
        echo "  [3] Original fresh repo (sinelaw/fresh) — download latest, patch for this arch, build"
        printf 'Choose [1-3, Enter=1]: '
        read -r choice
        case "$choice" in
            2) MODE=source ;;
            3) MODE=original ;;
            *) MODE=release ;;
        esac
        echo "-> $MODE"
    fi
fi

# ---- build-from-source paths (delegate to update.sh) ------------------------
if [ "$MODE" = "source" ]; then
    echo "== building from current source (cached in ~/.cache/fresh-termux/src) =="
    bash "$DIR/update.sh" --force
    exit $?
fi
if [ "$MODE" = "original" ]; then
    echo "== downloading latest official fresh (sinelaw/fresh) and patching for $ARCH =="
    FRESH_TERMUX_REPO=sinelaw/fresh bash "$DIR/update.sh"
    exit $?
fi

# ---- prebuilt release path --------------------------------------------------
if [ -z "$TAG" ]; then
    L=$(get_latest || true)
    if [ "$LATEST" = "1" ] || [ ! -t 0 ]; then
        TAG="$L"; [ -z "$TAG" ] && { echo "could not determine latest version of $REPO"; exit 1; }
        echo "(using latest $TAG)"
    else
        echo "Latest is ${L:-unknown}. Recent releases:"
        list_versions | head -8
        printf '\nPick version? <Enter>=latest, v0.4.9/0.4.9 to pin, l=list more: '
        read -r reply
        case "$reply" in
            ""|latest|LATEST) TAG="$L" ;;
            l|list|L)          list_versions; printf 'Enter version: '; read -r reply; TAG=$(normtag "$reply") ;;
            *)                 TAG=$(normtag "$reply") ;;
        esac
        [ -z "$TAG" ] && { echo "no version selected"; exit 1; }
        echo "selected: $TAG"
    fi
fi

echo "release: $TAG  (asset: $ASSET)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "Downloading from $GH/releases/download/${TAG}/$ASSET ..."
curl -fL "$GH/releases/download/${TAG}/$ASSET" -o "$TMP/$ASSET" \
    || { echo "download failed — no asset for $TAG? Run 'bash install.sh --list' or publish it via CI."; exit 1; }
echo "Extracting ..."
tar -xJf "$TMP/$ASSET" -C "$TMP"
BIN_PATH="$TMP/fresh-editor-x/fresh"

echo "Binary: $(file -b "$BIN_PATH")"
if file "$BIN_PATH" | grep -q "x86-64"; then
    echo "ERROR: asset is x86-64, not Android/aarch64." >&2
    echo "CI is building the host target. Fix .github/workflows/termux-release.yml:" >&2
    echo '  cargo build --release --bin fresh --target aarch64-linux-android' >&2
    echo "  and package from .../target/aarch64-linux-android/release/fresh" >&2
    exit 1
fi

echo "Installing -> $BIN"
mkdir -p "$(dirname "$BIN")"
cp "$BIN" "$BIN.prev.bin.$$" 2>/dev/null || true
cp -f "$BIN_PATH" "$BIN"
chmod 755 "$BIN"
rm -f "${HOME}/.config/fresh/logs/init.crashes" 2>/dev/null || true   # clear stale crash-fuse
echo "installed: $($BIN --version)"
echo "previous binary kept at $BIN.prev.bin.$$"
