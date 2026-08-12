# INSTRUCTIONS — GitHub setup, Actions pipeline & troubleshooting

This folder is the *harness only*: install/update/verify scripts, Android
patches, and a GitHub Actions workflow. It does **not** contain the fresh
source — the workflow fetches the exact upstream tag each run, so your GitHub
repo can be a plain, small, public repository. (A fork of `sinelaw/fresh` also
works; neither their source nor a fork relationship is required.)

## 1. What you end up with

- A public GitHub repo (`tushardan29-web/Fresh-TUI-Termux`) holding these files.
- A workflow `termux-release` that runs **weekly** (Mon 04:17 UTC) and **on
  demand** (`workflow_dispatch`). Each run:
  1. reads the latest upstream release tag of `sinelaw/fresh`,
  2. skips if this repo already published that tag,
  3. clones the exact upstream tag and applies the 5 Android patches,
  4. cross-compiles `aarch64-linux-android` (NDK r27b, bionic),
  5. publishes a release (tag matches upstream, e.g. `v0.4.9`) with asset
     `fresh-editor-aarch64-linux-android.tar.xz`
     (layout `fresh-editor-x/fresh` — what fresh's in-app updater expects).
- Termux devices that install those binaries (`install.sh`) or build locally
  (`update.sh`).

## 2. Create the GitHub repo

1. https://github.com/new — name it `Fresh-TUI-Termux`, visibility **Public**
   (free Actions minutes only for public repos).
2. Do **not** add a README, license, or .gitignore at creation — they're here
   already; GitHub's own would create a merge conflict on push.

## 3. Push this folder

```bash
cd ~/projects/fresh-termux
git init -b main
git add .
git commit -m "Termux/Android build: patches + release automation"
git branch -M main

# option A — HTTPS + personal access token (no gh CLI)
git remote add origin https://github.com/tushardan29-web/Fresh-TUI-Termux.git
git push -u origin main
# username: tushardan29-web, password: a PAT
# (github.com/settings/tokens → classic token → scope: repo AND workflow)

# option B — GitHub CLI (easiest)
pkg install gh
gh auth login          # follow the prompt, choose HTTPS
gh repo create Fresh-TUI-Termux --public --source . --push
```

> Note: the token needs the **workflow** scope too, or GitHub rejects pushes
> that touch `.github/workflows/` ("refusing to allow a Personal Access Token
> to create or update workflow ...").

Verify: `git ls-remote origin` shows `main`, and the repo page lists
`update.sh`, `install.sh`, `online-verify.sh`, `termux/`, `.github/workflows/`,
`README.md`.

## 4. Run the Actions workflow

1. https://github.com/tushardan29-web/Fresh-TUI-Termux → **Actions** tab →
   **termux-release**.
2. **Run workflow** (green button) → confirm. (A push does *not* auto-trigger
   it; only the weekly cron and the manual button do — that's intentional.)
3. Watch the run (~30–45 min: rust toolchain, NDK, quickjs bindgen, fat-LTO
   release build).

If it fails, see the troubleshooting table in §7.

## 5. Verify the first artifact on a device

The published binary comes from the exact same patched source as a device
build, plus patch 5 (`FRESH_UPDATE_REPO`) baked in — so smoke-test it before
trusting it in the auto-update ring:

```bash
# quick sanity check (arch + runs):
bash ~/projects/fresh-termux/online-verify.sh --yes
#   online-verify PASS — published build runs on aarch64 under Linux

# full strace check (no SIGSYS, no faccessat2, UI renders):
curl -fL -o /tmp/f.tar.xz \
  https://github.com/tushardan29-web/Fresh-TUI-Termux/releases/download/v0.4.9/fresh-editor-aarch64-linux-android.tar.xz
tar xJf /tmp/f.tar.xz -C /tmp
bash ~/projects/fresh-termux/termux/verify.sh /tmp/fresh-editor-x/fresh

# or soft-run the editor itself, nothing installed:
bash ~/projects/fresh-termux/online-verify.sh --run
```

Install it for real:

```bash
bash ~/projects/fresh-termux/install.sh --yes
```

## 6. Point a device at this repo (self-update ring, recommended)

Build once with the fork endpoint baked in:

```bash
FRESH_TERMUX_REPO=tushardan29-web/Fresh-TUI-Termux \
FRESH_UPDATE_REPO=tushardan29-web/Fresh-TUI-Termux \
  bash ~/projects/fresh-termux/update.sh
```

From then on: `upstream releases v0.4.10` → weekly CI publishes it → the
device's in-app updater (`fresh --cmd update`) downloads, verifies and
installs `fresh-editor-aarch64-linux-android.tar.xz`.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `Run workflow` button greyed out / workflow not listed | Settings → Actions → "Allow all actions and reusable workflows" |
| Push rejected: "without `workflow` scope" | regenerate the PAT with the `workflow` scope, or use `gh auth login` |
| `error[E0463]: can't find crate for 'std'` | upstream's `rust-toolchain.toml` pins a channel that lacks the target; the workflow's "Add Android target to active toolchain" step handles it — make sure it ran (check its log line) |
| `failed to find tool "aarch64-linux-android-ar"` | NDK r23+ has no per-ABI ar symlinks — workflow must use `llvm-ar`/`llvm-ranlib` (already configured) |
| `bits/libc-header-start.h file not found` in bindgen | clang needs the bionic sysroot — workflow sets `BINDGEN_EXTRA_CLANG_ARGS="--target=aarch64-linux-android24 --sysroot=<NDK>/sysroot"` |
| Released asset is x86-64 | CI built the host target — `cargo build` must pass `--target aarch64-linux-android` and package from `target/aarch64-linux-android/release/fresh` |
| Release created but asset missing / wrong name | asset must be exactly `fresh-editor-aarch64-linux-android.tar.xz`; delete tag + release, re-run |
| Workflow skips ("Already published v0.4.9") after a bad release | delete the tag **and** the release on GitHub, then re-run |
| `fresh --cmd update` on device can't reach the repo | verify patch 5 took: `strings $(which fresh) | grep -i tushardan29`; repo must be public |
| Device `update.sh` verify fails after a CI build change | ensure the device repo is current: `git -C ~/projects/fresh-termux pull` |

## 8. Maintenance

- **Nothing new upstream:** weekly runs exit "Already published vX — nothing
  to do"; you can always re-run manually.
- **Upstream code drift** (patches stop matching): `termux/patch.sh` fails
  loudly with a "pattern changed upstream; patch needs review" message —
  update the corresponding section, commit, re-run the workflow.
- **armv7 (32-bit) devices:** add `armv7-linux-androideabi` to the workflow's
  `targets:` + `CC_*`/linker env vars and the asset name; the in-app updater
  derives the asset name from the TARGET_TRIPLE, so keep the triple consistent
  (`fresh-editor-armv7-linux-androideabi.tar.xz` → layout `fresh-editor-x/fresh`).
- **Local-only flow** (no GitHub): `bash ~/projects/fresh-termux/update.sh`
  builds on-device; first compile ~20 min, later builds ~seconds.

## Files

| File | Purpose |
|---|---|
| `update.sh` | Source updater: fetch tag → patch → build → strace-verify → install |
| `install.sh` | Installer: prebuilt release / current source / official repo (interactive menu, `--yes`, `--list`) |
| `online-verify.sh` | Check or soft-run the published build without installing (`--run`) |
| `termux/patch.sh` | 5 Android patches (shared by update.sh and CI) |
| `termux/build.sh` | cargo release build (shared CARGO_TARGET_DIR, fat LTO) |
| `termux/verify.sh` | strace: no SIGSYS, no faccessat2, UI renders |
| `termux/run_pty.py` | headless PTY harness used by verify.sh |
| `.github/workflows/termux-release.yml` | CI pipeline (compare → fetch → patch → build → package → release) |
