#!/usr/bin/env bash
# Build a Termux/Android fresh binary. Run from a patched source checkout.
# Usage: bash build.sh [SOURCE_DIR]
set -euo pipefail

ROOT=${1:-$(pwd)}
cd "$ROOT"

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
if [ -z "${LIBCLANG_PATH:-}" ] && [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/lib" ]; then
    export LIBCLANG_PATH="$PREFIX/lib"
fi

echo "== cargo build --release --bin fresh (target dir: $CARGO_TARGET_DIR)"
cargo build --release --bin fresh
echo "== built: $CARGO_TARGET_DIR/release/fresh"