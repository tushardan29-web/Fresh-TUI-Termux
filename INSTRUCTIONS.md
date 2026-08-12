# INSTRUCTIONS — pushing this repo to GitHub and setting up the build

This folder is the *harness only*: updater script, Android patches, and a
GitHub Actions workflow. It does **not** contain the fresh source code — the
workflow fetches the exact upstream tag each run, so your GitHub repo can be a
plain, small, public repository (a fork of `sinelaw/fresh` also works; neither
their source nor a fork relationship is required).

## 0. What you end up with

- A public GitHub repo (e.g. `YOURNAME/fresh-termux`) holding these files.
- A GitHub Actions workflow `termux-release` that, weekly *and* on demand:
  1. reads the latest upstream release tag of `sinelaw/fresh`,
  2. skips if this repo already published that tag,
  3. cross-compiles fresh for `aarch64-linux-android` (NDK + bionic),
  4. applies the same Android patches used on the device,
  5. publishes release `v0.4.7` (tag matches upstream) with asset
     `fresh-editor-aarch64-linux-android.tar.xz` (layout `fresh-editor-x/fresh`,
     matching what fresh's in-app updater expects).
- A Termux device that can either build locally from this harness or download
  those GitHub-built binaries.

## 1. Create the GitHub repo

1. Go to https://github.com/new — or the **+** menu → **New repository**.
2. Name: `fresh-termux`. Visibility: **Public** (free Actions minutes only for
   public repos).
3. Do **not** add a README, license, or .gitignore (you have them here —
   adding GitHub's own would create a merge conflict on push).

## 2. Push this folder

The repo already has `.gitignore`, so `git add .` is safe (no logs, no build
artifacts). Then:

```bash
cd ~/projects/fresh-termux
git init -b main
git add .
git commit -m "Termux/Android build: patches + release automation"
git branch -M main

# option A — HTTPS + personal access token (no gh CLI)
git remote add origin https://github.com/YOURNAME/fresh-termux.git
git push -u origin main
# on username prompt: YOURNAME, on password: a Personal Access Token
# (github.com/settings/tokens → Generate classic token → scope: repo)

# option B — GitHub CLI (easiest)
pkg install gh
gh auth login          # follow the prompt, choose HTTPS
gh repo create fresh-termux --public --source . --push
```

Verify: `git ls-remote origin` shows `main`, and github.com/YOURNAME/fresh-termux
lists the files above (`update.sh`, `termux/`, `.github/workflows/`, `README.md`,
`INSTRUCTIONS.md`).

## 3. Run the Actions workflow

1. https://github.com/YOURNAME/fresh-termux → **Actions** tab.
   The `termux-release` workflow appears automatically (a first push doesn't
   auto-trigger it; that's fine).
2. Open **termux-release** → **Run workflow** (green button) → **Run workflow**
   again to confirm.
3. Watch the run (~30–45 min: rust toolchain download, NDK, quickjs bindgen,
   fat-LTO release build).

## 4. Verify the first artifact

When the run finishes (green ✓), a release `v0.4.7` is created with the asset
`fresh-editor-aarch64-linux-android.tar.xz`. Smoke-test it on the device before
trusting it:

```bash
# on the device, in a temp dir
cd ~/.cache/fresh-termux
curl -L -O https://github.com/YOURNAME/fresh-termux/releases/download/v0.4.7/fresh-editor-aarch64-linux-android.tar.xz
tar xJf fresh-editor-aarch64-linux-android.tar.xz
ls -l fresh-editor-x/fresh          # bionic ELF, ~38 MB — should match local build size
file fresh-editor-x/fresh
fresh-editor-x/fresh --version
bash ~/projects/fresh-termux/termux/verify.sh fresh-editor-x/fresh   # strace + render check
```

The build comes from the exact same patched source as the device build
(patches 1–4), plus patch 5 (`FRESH_UPDATE_REPO`) baked in, so in-app updates
will point at your repo.

## 5. Point the device at your repo (optional, recommended)

Build locally from your repo instead of upstream, and bake the updater endpoint:

```bash
FRESH_TERMUX_REPO=YOURNAME/fresh-termux \
FRESH_UPDATE_REPO=YOURNAME/fresh-termux \
  bash ~/projects/fresh-termux/update.sh
```

From then on the ring is closed:
`upstream releases v0.4.8` → weekly CI publishes it to your repo → the device's
in-app updater (`fresh --cmd update`) pulls and unpacks it
(`fresh-editor-aarch64-linux-android.tar.xz` → `fresh-editor-x/fresh`).

## 6. Maintenance

- **Nothing new upstream:** weekly runs exit with "Already published v0.4.7 —
  nothing to do". Run on demand anytime via **Run workflow**.
- **Partially failed CI run** (release published, build failed, retry won't
  republish because the tag exists): delete the tag + release on GitHub →
  **Run workflow** again. Deleting a release does not reset the tag; delete both
  from github.com/YOURNAME/fresh-termux → Releases → ⋯ → **Delete**, and
  **Tags** → ⋯ → **Delete**.
- **Upstream code drift** (new fresh release changes the code the patches
  touch): `termux/patch.sh` fails loudly (asserts a signature before patching)
  instead of silently mispatching. Fix by updating the corresponding section,
  then re-run the workflow.
- **ARM (32-bit) devices:** add `armv7-linux-androideabi` to the
  `targets:`/`CC_*`/asset-name/target-triple spots (the updater builds the asset
  name from the TARGET_TRIPLE, so the triple must stay consistent).
- **Local-only flow** (no GitHub): `bash ~/projects/fresh-termux/update.sh`
  builds on-device; first compile ~20 min, subsequent runs ~seconds.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Run workflow` button greyed out / workflow not listed | Settings → Actions → enable "Allow all actions and reusable workflows" |
| Push rejected (non-fast-forward) | You added a README on github.com during creation; `git pull --rebase origin main` then push |
| Workflow fails in "Fetch upstream source" | tag mismatch — check the `Compare upstream` log line; upstream releases without tags won't be picked up |
| Release created but asset missing / wrong name | updater expects exactly `fresh-editor-aarch64-linux-android.tar.xz`; rename or re-run (delete tag+release first) |
| `fresh --cmd update` on device can't reach the repo | verify the `FRESH_UPDATE_REPO` patch took: `strings $(which fresh) | grep -i yourname`; repo must be public |

## Files

| File | Purpose |
|---|---|
| `update.sh` | Device-side updater: fetch tag → patch → build → verify → install |
| `termux/patch.sh` | 5 Android patches (see README table); used by both update.sh and CI |
| `termux/build.sh` | cargo release build (shared CARGO_TARGET_DIR, opt-size, fat LTO) |
| `termux/verify.sh` | strace the binary: no SIGSYS, no faccessat2, UI renders |
| `termux/run_pty.py` | headless PTY harness used by verify.sh |
| `.github/workflows/termux-release.yml` | the CI pipeline (build + package + release) |