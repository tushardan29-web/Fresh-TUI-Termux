#!/usr/bin/env bash
# Fresh for Termux/Android — apply the Android compatibility patches to a
# fresh source checkout, in place. Idempotent (safe to re-run).
#
# Usage: bash patch.sh [SOURCE_DIR]      (default: current dir)
#
# Optional env:
#   FRESH_UPDATE_REPO=user/fresh   rewrite the built-in update-check repo
#                                  (for a fork that publishes its own releases)
set -euo pipefail

ROOT=${1:-$(pwd)}
cd "$ROOT"

echo "== fresh-termux patch.sh: $(pwd)"

# ---------------------------------------------------------------- 1/4
# kernel_writable: call faccessat with flag 0 instead of AT_EACCESS.
# musl/libc route flagged faccessat through the faccessat2 syscall (Linux
# 5.8+); on old Android kernels the seccomp policy SIGSYS-kills the process
# instead of returning ENOSYS, so the fallback never runs ("Bad system call"
# crash). Passing 0 uses the classic faccessat syscall everywhere.
F=crates/fresh-editor/src/model/filesystem.rs
if grep -q "libc::AT_EACCESS" "$F"; then
    python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """            libc::faccessat(
                libc::AT_FDCWD,
                c_path.as_ptr(),
                libc::W_OK,
                libc::AT_EACCESS,
            )"""
new = """            libc::faccessat(
                libc::AT_FDCWD,
                c_path.as_ptr(),
                libc::W_OK,
                0,
            )"""
if old in s:
    open(p, "w").write(s.replace(old, new))
    print("patched kernel_writable (AT_EACCESS -> 0)")
else:
    print("WARNING: kernel_writable pattern changed upstream; patch needs review")
    sys.exit(1)
PY
else
    echo "kernel_writable: already patched"
fi

# ---------------------------------------------------------------- 2/4
# rquickjs-sys ships no pre-generated bindings for aarch64-linux-android;
# Termux has libclang, so use the project's own bindgen pattern (the same
# one it uses for FreeBSD/NetBSD).
P=crates/fresh-plugin-runtime/Cargo.toml
if ! grep -q 'target_os = "android"' "$P"; then
    cat >> "$P" <<'EOF'

# Termux/Android: no pre-generated rquickjs bindings -> generate with bindgen.
[target.'cfg(target_os = "android")'.dependencies]
rquickjs = { workspace = true, features = ["bindgen"] }
EOF
    echo "patched fresh-plugin-runtime (bindgen on android)"
else
    echo "fresh-plugin-runtime: already patched"
fi

# ---------------------------------------------------------------- 3/6
# rustls-platform-verifier panics on Termux ("Expect rustls-platform-verifier
# to be initialized") — it requires the Android JVM, which a CLI process has
# no access to. Switch TLS to bundled Mozilla webpki-roots:
#   * manifests: ureq feature platform-verifier -> rustls-webpki-roots
#     (heals any stale/bare variants left by earlier patch revisions)
#   * fresh-update/src/net.rs: RootCerts::PlatformVerifier -> RootCerts::WebPki
# NOTE: this must run BEFORE the `cargo fetch` in section 4 — a stale
# feature entry breaks resolution and would abort the script.
for F in crates/fresh-editor/Cargo.toml crates/fresh-update/Cargo.toml; do
    if grep -q 'ureq' "$F"; then
        python3 - "$F" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
m = re.search(r'ureq\s*=\s*\{[^}]*\}', s, re.S)
if not m:
    print(f"WARNING: ureq dep not found in {p}; patch needs review")
    sys.exit(1)
blk = m.group(0)
if '"rustls-webpki-roots"' not in blk:
    blk2 = re.sub(r',\s*"platform-verifier"', '', blk)
    blk2 = re.sub(r',\s*"webpki-roots"', '', blk2)
    blk2 = blk2.replace('"rustls"', '"rustls", "rustls-webpki-roots"', 1)
    open(p, 'w').write(s[:m.start()] + blk2 + s[m.end():])
    print(f"patched {p}: ureq tls -> rustls-webpki-roots")
else:
    print(f"{p}: ureq tls already rustls-webpki-roots")
PY
    fi
done
N=crates/fresh-update/src/net.rs
if grep -q 'RootCerts::PlatformVerifier' "$N"; then
    sed -i 's/ureq::tls::RootCerts::PlatformVerifier/ureq::tls::RootCerts::WebPki/' "$N"
    echo "patched $N: RootCerts::PlatformVerifier -> RootCerts::WebPki"
else
    echo "$N: already webpki"
fi

# ---------------------------------------------------------------- 4/6
# trash + arboard crates have no Android platform module. Patch local copies
# (taken from the exact Cargo.lock-resolved versions) so Android uses their
# freedesktop/X11/Wayland backends, wired via [patch.crates-io].
cargo fetch >/dev/null 2>&1 || { echo "cargo fetch failed (network? corrupt lock?)"; exit 1; }
mkdir -p patches
for name in trash arboard; do
    ver=$(grep -A2 "name = \"$name\"" Cargo.lock | sed -n 's/^version = "\(.*\)"/\1/p' | head -1)
    if [ -z "$ver" ]; then
        echo "no Cargo.lock entry for $name"; exit 1
    fi
    dst="patches/$name"
    if [ -d "$dst" ] && grep -q "version = \"$ver\"" "$dst/Cargo.toml" 2>/dev/null; then
        echo "$name: patch copy already present (v$ver)"
    else
        src=$(find "$HOME/.cargo/registry/src" -maxdepth 2 -type d -name "$name-$ver" 2>/dev/null | head -1)
        if [ -z "$src" ]; then
            echo "registry source for $name-$ver not found; run cargo fetch first"; exit 1
        fi
        rm -rf "$dst"
        cp -r "$src" "$dst"
    fi
    # Idempotent: only rewrite a file when the android exclusion is still
    # present (sed -i on unchanged files dirties cargo's fingerprints and
    # forces a full fat-LTO relink on the next build).
    if [ "$name" = "trash" ]; then
        for f in "$dst/src/lib.rs" "$dst/Cargo.toml"; do
            if grep -q ', not(target_os = "android")' "$f"; then
                sed -i 's/, not(target_os = "android")//g' "$f"
            fi
        done
    else
        for f in "$dst/src/platform/mod.rs" "$dst/src/lib.rs" "$dst/Cargo.toml"; do
            if grep -q 'target_os = "android", ' "$f"; then
                sed -i 's/target_os = "android", //g' "$f"
            fi
            if grep -q 'target_os="android", ' "$f"; then
                sed -i 's/target_os="android", //g' "$f"
            fi
        done
    fi
    echo "patched $name v$ver (android backend enabled)"
done
if ! grep -q '\[patch.crates-io\]' Cargo.toml; then
    cat >> Cargo.toml <<'EOF'

[patch.crates-io]
trash = { path = "patches/trash" }
arboard = { path = "patches/arboard" }
EOF
    echo "wired [patch.crates-io]"
else
    echo "[patch.crates-io] already wired"
fi

# ---------------------------------------------------------------- 5/6
# (fork only) point the built-in updater at a custom repo.
if [ -n "${FRESH_UPDATE_REPO:-}" ]; then
    E=crates/fresh-update/src/endpoint.rs
    if grep -q "pub const REPO: &str = \"sinelaw/fresh\";" "$E"; then
        sed -i "s|pub const REPO: &str = \"sinelaw/fresh\";|pub const REPO: \&str = \"$FRESH_UPDATE_REPO\";|" "$E"
        echo "endpoint: updates now checked against $FRESH_UPDATE_REPO"
    else
        echo "WARNING: endpoint.rs REPO const changed upstream; set it manually"
    fi
fi

echo "== patch.sh done"