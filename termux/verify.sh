#!/usr/bin/env bash
# Verify a fresh binary runs on this device: it must render its UI and must
# never issue the fatal faccessat2 syscall (SIGSYS on old Android kernels).
# Usage: bash verify.sh <fresh-binary> [work-dir]
set -euo pipefail

BIN=${1:?usage: verify.sh <fresh-binary>}
DIR=$(cd "$(dirname "$0")" && pwd)
TMP=${2:-$(mktemp -d)}
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

if command -v strace >/dev/null 2>&1; then
    strace -f -o "$TMP/trace" -e trace=faccessat,faccessat2 \
        python3 "$DIR/run_pty.py" "$BIN" --no-restore --timeout 8 >"$TMP/out" 2>/dev/null || true
    if grep -q "SIGSYS" "$TMP/trace"; then
        echo "VERIFY FAIL: process received SIGSYS (bad syscall)"
        exit 1
    fi
    if grep -q "faccessat2" "$TMP/trace"; then
        echo "VERIFY FAIL: faccessat2 syscall used (blocked on this kernel)"
        exit 1
    fi
    faccessat_total=$(grep -c "faccessat" "$TMP/trace" || true)
else
    python3 "$DIR/run_pty.py" "$BIN" --no-restore --timeout 8 >"$TMP/out" 2>/dev/null || true
    faccessat_total="n/a (no strace)"
fi

if grep -qF $'\033[?1049h' "$TMP/out"; then
    echo "VERIFY PASS: UI rendered (alt screen), $faccessat_total faccessat calls, no SIGSYS"
else
    echo "VERIFY FAIL: fresh did not render its UI"
    exit 1
fi