# Fresh for Termux — local updater + fork build automation

Fresh's official musl builds crash on older Android kernels: the musl `faccessat`
uses the `faccessat2` syscall (Linux 5.8+), and the Android seccomp policy
answers with SIGSYS / "Bad system call" instead of ENOSYS. This repo:

1. **`update.sh`** — a Termux updater: downloads fresh source, patches it for
   Android, builds with the Termux Rust toolchain, verifies under strace, and
   replaces `/data/data/com.termux/files/usr/bin/fresh` (backup kept at
   `~/.cache/fresh-termux/fresh.prev.bin`).
2. **GitHub Actions** (`.github/workflows/termux-release.yml`) — a fork that
   cross-compiles `aarch64-linux-android` builds (Android NDK + bionic) on
   GitHub's free runners, weekly and on demand, and publishes them as release
   asset `fresh-editor-aarch64-linux-android.tar.xz`. Combined with the
   `FRESH_UPDATE_REPO` patch in `termux/patch.sh`, the built fresh can then
   update itself in-app from the fork's releases.

## The 5 patches (termux/patch.sh)

| # | What | Why |
|---|------|-----|
| 1 | `kernel_writable()`: `faccessat(..., AT_EACCESS)` → `faccessat(..., 0)` | avoids the fatal `faccessat2` syscall |
| 2 | `fresh-plugin-runtime`: `bindgen` for `target_os = "android"` | rquickjs has no prebuilt android bindings (same pattern as FreeBSD/NetBSD) |
| 3 | ureq TLS: `platform-verifier` → `rustls-webpki-roots` + `RootCerts::WebPki` | the platform verifier needs the Android JVM and panics in a Termux CLI |
| 4 | `trash` + `arboard` patched copies via `[patch.crates-io]` | crates have no Android platform module; use freedesktop/X11/Wayland backends |
| 5 | (forks only) `endpoint.rs` `REPO` → `FRESH_UPDATE_REPO` | in-app updater checks the fork's releases |

Patches 1–4 are verified against the Cargo.lock-resolved fresh/trash/arboard/ureq
code; if upstream drifts, `patch.sh` fails loudly instead of silently
mispatching, and `update.sh --force` rebuilds the current version if only
patch code changed.

## Local usage (Termux)

```bash
bash ~/projects/fresh-termux/update.sh   # update to latest
bash ~/projects/fresh-termux/update.sh 0.4.8      # specific version
FRESH_TERMUX_REPO=you/fresh-termux bash ~/projects/fresh-termux/update.sh   # from your repo
```

Everything is incremental: builds share `~/.cache/fresh-termux/target`, so
version bumps only recompile what changed.

## GitHub setup (full walkthrough: INSTRUCTIONS.md)

This folder is a harness only — the GitHub repo does **not** need the fresh
source. Create any public repo (fork or new), push this folder, and run the
`termux-release` workflow: it fetches the exact upstream tag, cross-compiles
with the NDK, patches (incl. `FRESH_UPDATE_REPO`), and publishes
`fresh-editor-aarch64-linux-android.tar.xz` as a release matching the upstream
tag. Weekly cron + manual dispatch; skips when already published.

## Making the device self-update from your repo

Build + install once with your repo as source:

```bash
FRESH_TERMUX_REPO=YOURNAME/fresh-termux FRESH_UPDATE_REPO=YOURNAME/fresh-termux \
  bash ~/projects/fresh-termux/update.sh
```

The installed binary then checks your repo's releases: each week the workflow
auto-publishes the new version and the device updates itself via
`fresh --cmd update` (or the built-in update checker).

## Notes / caveats

- Only build for **aarch64** currently (add a matrix row for armv7 + the
  `armv7-linux-androideabi` target if needed).
- GitHub Actions is free for public repos only.
- The workflow skips publishing when this repo already has the upstream version
  (after a partially-failed run, delete the tag + release and re-run).
- Cross-compiled NDK bionic binaries work on Terminal apps only (they're
  normal Android executables; Termux is the target client).