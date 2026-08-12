#!/usr/bin/env bash
# online-verify.sh — download a fresh release asset to a temp dir and RUN it
# WITHOUT installing, to check the published CI build works on this device.
# Fails (exit 1) if the asset is the wrong arch (e.g. an x86-64 host build).
#
# Usage:
#   bash online-verify.sh [VERSION]        # e.g. bash online-verify.sh v0.4.9
#   bash online-verify.sh                  # prompts: latest / list / specific
#   bash online-verify.sh --list           # list releases and exit
#   bash online-verify.sh --latest/--yes   # verify latest, no prompt
#   bash online-verify.sh --help
# Env:   FRESH_INSTALL_REPO=user/fresh     # release repo (default tushardan29-web/Fresh-TUI-Termux)
#
set -euo pipefail

REPO=${FRESH_INSTALL_REPO:-tushardan29-web/Fresh-TUI-Termux}
ARCH=aarch64
ASSET="fresh-editor-${ARCH}-linux-android.tar.xz"
GH="https://github.com/$REPO"
API="https://api.github.com/repos/$REPO"

command -v curl    >/dev/null || { echo "need: curl"; exit 1; }
command -v python3 >/dev/null || { echo "need: python3"; exit 1; }
command -v file    >/dev/null || { echo "need: file"; exit 1; }

normtag()    { case "$1" in v[0-9]*) echo "$1";; [0-9]*) echo "v$1";; *) echo "$1";; esac; }
list_versions() {
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
    curl -fsSL "$API/releases/latest" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null \
      || git ls-remote --tags "$GH.git" 2>/dev/null \
      | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+' | sed 's#refs/tags/##' | sort -V | tail -1
}

TAG=""; LIST_ONLY=0; LATEST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --list|-l) LIST_ONLY=1; shift ;;
        --latest|--yes|-y) LATEST=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) TAG=$(normtag "$1"); shift ;;
    esac
done
if [ "$LIST_ONLY" = "1" ]; then
    echo "Releases on $REPO (newest first):"; list_versions; exit 0
fi

if [ -z "$TAG" ]; then
    L=$(get_latest || true)
    if [ "$LATEST" = "1" ] || [ ! -t 0 ]; then
        TAG="$L"; [ -z "$TAG" ] && { echo "could not determine latest version of $REPO"; exit 1; }
        echo "(non-interactive: using latest $TAG)"
    else
        echo "Latest is ${L:-unknown}. Recent releases:"; list_versions | head -8
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
    || { echo "download failed — no asset for $TAG? Run 'bash online-verify.sh --list'."; exit 1; }
echo "Extracting (to $TMP, not installing)..."
tar -xJf "$TMP/$ASSET" -C "$TMP"
BIN_PATH="$TMP/fresh-editor-x/fresh"

echo "Binary: $(file -b "$BIN_PATH")"
if file "$BIN_PATH" | grep -q "x86-64"; then
    echo "ERROR: published asset is x86-64 (not Android aarch64)." >&2
    echo "CI is building the host target. Fix .github/workflows/termux-release.yml:" >&2
    echo '  cargo build --release --bin fresh --target aarch64-linux-android' >&2
    echo "  and package from .../target/aarch64-linux-android/release/fresh" >&2
    exit 1
fi

echo "Running --version (no install)..."
"$BIN_PATH" --version
echo "online-verify PASS — published build runs on $(uname -m) under $(uname -s)"
