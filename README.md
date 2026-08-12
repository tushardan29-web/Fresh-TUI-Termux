# Fresh for Termux

[![Release](https://img.shields.io/github/v/release/tushardan29-web/Fresh-TUI-Termux)](https://github.com/tushardan29-web/Fresh-TUI-Termux/releases)
[![CI](https://github.com/tushardan29-web/Fresh-TUI-Termux/actions/workflows/termux-release.yml/badge.svg)](https://github.com/tushardan29-web/Fresh-TUI-Termux/actions/workflows/termux-release.yml)

[**Fresh**](https://github.com/sinelaw/fresh) is a modern terminal text editor.
The official builds crash on older Android kernels — this project makes Fresh
run on Termux, with ready-made installers, a GitHub Actions release pipeline,
and in-app self-updates.

## Why the official builds crash

The official musl builds use the `faccessat2` syscall (Linux 5.8+). On older
Android kernels (e.g. 4.19), the seccomp policy answers with
**SIGSYS / "Bad system call"** instead of `ENOSYS`, so the graceful fallback
never runs and fresh dies at startup.

This repo builds fresh for Android instead: Termux-native binaries (bionic)
with five small compatibility patches, verified under strace before install.

## Features

- **One-command install** — prebuilt aarch64 Android binaries from GitHub
  releases, no compiler needed (`install.sh`)
- **Build-from-source** — patches + build with the Termux Rust toolchain,
  verified under strace before install (`update.sh`)
- **Automated release pipeline** — GitHub Actions cross-compiles every
  upstream release weekly (and on demand) and publishes it
- **In-app self-update** — the patched binary can update itself from this
  repo's releases (`fresh --cmd update`)
- **Soft-run mode** — run the editor without installing anything
  (`online-verify.sh --run`)

## Requirements

- Termux with: `git`, `curl`, `file`, `python3`
- For source builds only: `rust` (cargo), `clang`, `libclang`, `strace`
  (`pkg install rust clang libclang strace`)
- aarch64 device (all modern Android phones/tablets)

## Install

### Option A — prebuilt release (fastest, no build)

```bash
bash ~/projects/fresh-termux/install.sh
```

Interactive menu asks what to install from; <kbd>1</kbd> = prebuilt release.
Or skip the menu:

```bash
bash ~/projects/fresh-termux/install.sh --yes      # latest release, no prompts
bash ~/projects/fresh-termux/install.sh v0.4.9     # specific version
bash ~/projects/fresh-termux/install.sh --list     # see available versions
```

Installs to `$PREFIX/bin/fresh`, keeps the previous binary as a backup.

### Option B — build from source (Termux toolchain)

```bash
bash ~/projects/fresh-termux/install.sh --original   # latest official fresh, patched for Android
bash ~/projects/fresh-termux/install.sh --source     # rebuild the cached source
```

First compile takes ~20 min (fat-LTO release build); later builds are
incremental (~seconds) and share `~/.cache/fresh-termux/target`.

Or use the updater directly:

```bash
bash ~/projects/fresh-termux/update.sh            # update to latest
bash ~/projects/fresh-termux/update.sh 0.4.9      # specific version
bash ~/projects/fresh-termux/update.sh --force    # rebuild current version
```

## Try before installing (soft run)

```bash
bash ~/projects/fresh-termux/online-verify.sh --run          # latest, no install
bash ~/projects/fresh-termux/online-verify.sh --run v0.4.9   # specific version
```

Downloads to `~/.cache/fresh-termux/online-<tag>`, checks the architecture,
then launches the real editor in your terminal. Exit with `:q` or Ctrl-C.
Nothing on the system changes.

To only sanity-check the published binary:

```bash
bash ~/projects/fresh-termux/online-verify.sh --yes
# online-verify PASS — published build runs on aarch64 under Linux
```

## Updating

| Situation | Command |
|---|---|
| Fast update to the latest release | `bash ~/projects/fresh-termux/install.sh --yes` |
| Rebuild current source after a patch change | `bash ~/projects/fresh-termux/update.sh --force` |
| Let fresh check for updates itself | `fresh --cmd update` (needs a build with `FRESH_UPDATE_REPO` — see below) |

### Automatic self-update ring

When the device build is done with the fork endpoint baked in, updates are
fully automatic:

```
upstream releases v0.4.10
        │  weekly cron
        ▼
GitHub Actions builds & publishes to tushardan29-web/Fresh-TUI-Termux
        │
        ▼
device: fresh --cmd update  →  download → verify → install
```

To enable it, build once with:

```bash
FRESH_TERMUX_REPO=tushardan29-web/Fresh-TUI-Termux \
FRESH_UPDATE_REPO=tushardan29-web/Fresh-TUI-Termux \
  bash ~/projects/fresh-termux/update.sh
```

## GitHub Actions release pipeline

`.github/workflows/termux-release.yml` runs **weekly** (Mon 04:17 UTC) and on
**workflow_dispatch** (manual "Run workflow" button). Each run:

1. Reads the latest upstream release tag of `sinelaw/fresh`
2. Skips if this repo already published that tag
3. Clones the exact upstream tag, applies the Android patches
4. Cross-compiles `aarch64-linux-android` (NDK r27b + bionic)
5. Publishes release `v0.4.x` with asset
   `fresh-editor-aarch64-linux-android.tar.xz`
   (layout `fresh-editor-x/fresh` — exactly what fresh's in-app updater expects)

No secrets or configuration needed. If a run publishes a broken release,
delete the tag + release on GitHub and re-run.

## The 5 patches (`termux/patch.sh`)

| # | What | Why |
|---|------|-----|
| 1 | `kernel_writable()`: `faccessat(..., AT_EACCESS)` → `faccessat(..., 0)` | avoids the fatal `faccessat2` syscall on old kernels |
| 2 | `fresh-plugin-runtime`: `bindgen` for `target_os = "android"` | rquickjs has no prebuilt Android bindings (same pattern as FreeBSD/NetBSD) |
| 3 | ureq TLS: `platform-verifier` → `rustls-webpki-roots` + `RootCerts::WebPki` | the platform verifier needs the Android JVM and panics in a Termux CLI |
| 4 | `trash` + `arboard` patched copies via `[patch.crates-io]` | crates have no Android platform module; use freedesktop/X11/Wayland backends |
| 5 | (fork builds) `endpoint.rs` `REPO` → `FRESH_UPDATE_REPO` | in-app updater checks the fork's releases |

Patches 1–4 are asserted against the Cargo.lock-resolved code; if upstream
drifts, `patch.sh` fails loudly instead of silently mispatching.

## Files

| File | Purpose |
|---|---|
| `install.sh` | Install fresh: prebuilt release, current source, or official repo (interactive menu) |
| `update.sh` | Source updater: fetch tag → patch → build → strace-verify → install |
| `online-verify.sh` | Check / soft-run the published build without installing (`--run`) |
| `termux/patch.sh` | The 5 Android patches (shared by update.sh and CI) |
| `termux/build.sh` | cargo release build (shared target dir, fat LTO) |
| `termux/verify.sh` | strace the binary: no SIGSYS / faccessat2, UI renders |
| `termux/run_pty.py` | headless PTY harness used by verify.sh |
| `.github/workflows/termux-release.yml` | CI pipeline: build + package + release |

## Notes

- **aarch64 only** for now (armv7 needs a matrix row + `armv7-linux-androideabi`
  target).
- GitHub Actions is free for public repos only.
- The workflow skips publishing when this repo already has the upstream
  version — after a partially-failed run, delete the tag + release first.
- Cross-compiled NDK binaries are normal Android executables; Termux is the
  target client.

## Full GitHub setup walkthrough

See **[INSTRUCTIONS.md](INSTRUCTIONS.md)** for creating the repo, pushing,
running the workflow, and troubleshooting the CI pipeline.
