# Setting up a development machine

Everything needed to build Room on a fresh Mac. Steps are idempotent; a
Claude Code session can run all of them except the ones marked **(user)**,
which need a password, a GUI login or an Apple account.

## Requirements

- Apple silicon Mac, macOS 26 or later, Xcode 27 (launched once, license accepted).
- Disk: ~200 GB free on an APFS volume for Chromium (checkout 113 GB with
  full history, `out/dev` ~10 GB), plus a few GB for CEF and Room builds.
  The Chromium location is configurable (below), so it can be another drive.
- A fast, unmetered connection: the Chromium fetch is ~57 GB.

## 1. Tools

```bash
xcode-select -p                                   # must point at Xcode.app, not CommandLineTools
xcodebuild -downloadComponent MetalToolchain      # Chromium's ANGLE needs it; Xcode 27 does not ship it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"   # if no Homebrew (user: needs the login password)
brew install xcodegen cmake gh
```

depot_tools is cloned by `scripts/chromium-checkout.sh` into `~/depot_tools`.
Chromium's build brings its own clang, Python, Siso and GN.

## 2. Repository

```bash
gh auth login        # (user) or an SSH key added to GitHub
git clone git@github.com:lekevicius/room.git ~/Code/room
```

Clone into `~/Code/room` if possible: Claude Code's per-project memory is
keyed by path, and docs use repo-relative paths only, so any path works.

## 3. CEF (the Chapter 1–2 engine)

```bash
scripts/bootstrap-cef.sh     # ~3–4 min: pinned CEF 154.0.32 into Engine/cef/dist, wrapper, cefsimple check
xcodegen
xcodebuild -scheme Room -configuration Debug -derivedDataPath build/DerivedData build
scripts/smoke-launch.sh      # launches Room.app on CEF and quits it
```

## 4. Chromium checkout and RoomCore (the fork)

Where Chromium goes is per machine: copy `local.env.example` to `local.env`
(gitignored) and set `CHROMIUM_ROOT` (default `~/chromium`). The volume must
be APFS: Chromium needs symlinks, Unix permissions and clones, which exFAT
lacks. If the big drive is exFAT, put an APFS sparse bundle on it and set
`CHROMIUM_IMAGE`; the scripts attach it when it is not mounted:

```bash
hdiutil create -type SPARSEBUNDLE -fs APFS -size 350g -volname Chromium /Volumes/<drive>/Chromium.sparsebundle
hdiutil attach /Volumes/<drive>/Chromium.sparsebundle -nobrowse -owners on
mdutil -i off /Volumes/Chromium      # no Spotlight indexing of millions of sources
```

Never unplug the drive while the image is attached.

Long steps: start them from `bash` with `nohup`, never zsh `&` (zsh's
`BG_NICE` renices background jobs; Phase 1.1 lost hours to it), and log
timings in `research/notes/build-log.md` under a heading for this machine.

```bash
mkdir -p build && bash -c 'nohup scripts/chromium-checkout.sh > build/chromium-checkout.log 2>&1 &'
#   fetch (~50 min at 60 MB/s), checkout of tag 154.0.8037.58, gclient sync, runhooks
scripts/roomcore-apply.sh
#   symlinks Engine/roomcore/room as $CHROMIUM_SRC/room, creates the `room`
#   branch with Engine/roomcore/patches applied, branding placeholders,
#   out/dev/args.gn, gn gen
bash -c 'nohup scripts/roomcore-build.sh > build/roomcore-build.log 2>&1 &'
#   clean component build of `chrome` (Room.app + RoomCore.framework): hours.
#   Under ~32 GB RAM add ROOM_BUILD_JOBS=6 (inside the bash -c): ten parallel
#   Blink compiles swap on a 24 GB Mac mini (4 h 15 min at 6 jobs)
scripts/roomcore-package.sh   # stage the framework, build Room.app on RoomCore (scheme "Room (RoomCore)")
#   and the embryo host (scheme "RoomCore Host", build/roomcore-host)
```

Engine-level checks (from PR #1, merged in 3.1a), all on the packaged host
(`ROOM_APP` overrides the app path): `scripts/roomcore-baseline.sh <new-dir>`
(nav assertions, then the ten-page clean quit), `scripts/roomcore-features.sh`
(the 18 feature drives on loopback fixtures from `scripts/roomcore-fixtures.py`),
`scripts/roomcore-netlog.sh` (launch, 600 s idle, quit, NetLog) summarised by
`scripts/roomcore-netlog-summary.py <netlog.json>` (requests by host and Chromium
traffic annotation; TLS failures through source dependencies). The shutdown
diagnostics use `scripts/roomcore_process_observer.py` and
`scripts/roomcore_thread_observer.py` (libproc through `ctypes`, read-only;
Python 3 from the Command Line Tools, no packages) from
`scripts/roomcore-shutdown-local.py`; `python3 scripts/tests/test_roomcore_netlog.py`
tests the summariser.

Release (3.1b): `Engine/roomcore/args/release.gn` (official, static, ThinLTO,
dSYMs, no PGO profile unless gclient's `checkout_pgo_profiles` is on) builds
into `out/release`; on the Mac mini a clean build is 4 h 43 min at 6 jobs, the
framework's ThinLTO link 18 min at 6.8 GiB (it fits in 24 GB; 3.1b-2). The
internal disk needs ~5 GB free for packaging (stage, dSYMs, two apps):

```bash
bash -c 'ROOM_BUILD_JOBS=6 ROOM_OUT_DIR=out/release ROOM_GN_ARGS=release.gn nohup scripts/roomcore-build.sh > build/roomcore-release-build.log 2>&1 &'
#   progress: wc -l out/release/siso_metrics.json (one line per finished step)
#   against `third_party/ninja/ninja -C out/release -t commands chrome | wc -l`
scripts/roomcore-package.sh --release   # build/roomcore-release: static framework, Release
#   Room.app and the host, ad hoc (mock keychain), the shipped binaries' dSYMs beside them
#   (2.2 GB); ROOM_TEAM_SIGN=1 signs Room.app in place, ROOM_NOTARIZE=1 also notarizes;
#   CONFIGURATION=Debug builds the DEBUG app (spike runner) over the release engine
scripts/roomcore-sign.sh [Room.app] [--no-notarize]   # Developer ID + notarization
#   (ROOM_SIGN_COPY=<dir> signs a clone, leaving the ad-hoc product alone)
scripts/roomcore-cold-launch.py <Room.app> <new-dir> [3]   # process start to first page loaded
#   (any configuration; scratch state and --user-data-dir, never the real data root)
scripts/sparkle-package.sh <signed Room.app> build/sparkle   # DMG, EdDSA signature, appcast entry
#   (ROOM_SPARKLE_UNSIGNED=1: DMG and an unsigned entry, no keychain access)
scripts/roomcore-watchdog.sh <new-dir> [20]   # B-38: both shutdown harnesses N times
#   (ROOM_APP=build/roomcore-release/DerivedData-host/Build/Products/Release/Room.app runs
#   them on the release build; ROOM_WATCHDOG_PRUNE=1 deletes clean runs' profiles)
```

The spike wrappers talk to Room by pid (`scripts/lib/room-process.sh`,
`scripts/lib/room-ae.swift`, compiled on first use into `build/tools`), never
by bundle id: three builds share `app.room.desktop` (B-47).

The full Chromium history is needed (the `room` branch is rebased onto new
tags); do not use `--no-history`.

## 5. Signing (user)

Identity (PLAN §4): bundle id `app.room.desktop` for Room.app on either
engine and the embryo host; the CEF helpers are `app.room.desktop.helper`,
`.helper.gpu`, `.helper.renderer`, `.helper.plugin`, `.helper.alerts`; the
RoomCore framework's helpers take Chromium's own suffixes under the same id
(`.helper`, `.helper.renderer`, `.framework.AlertNotificationService`). The
defaults domain is `app.room.desktop` (it was `com.lekevicius.room` through
Chapter 2).

Ad-hoc builds get a new code identity per build, so the login keychain asks
for the password whenever Chromium reads its Safe Storage item. Signing with
the team identity avoids that and is needed for the notarization pipeline.

1. Xcode ▸ Settings ▸ Accounts: sign in with the Apple ID of team
   `N56PMJ99UT`; under Manage Certificates add "Apple Development" and, if it
   is not imported from the old Mac (Keychain Access ▸ export as .p12),
   "Developer ID Application".
2. Notarization credentials (once):
   `xcrun notarytool store-credentials room --apple-id <id> --team-id N56PMJ99UT`
3. Check: `security find-identity -v -p codesigning` lists
   `Developer ID Application: Jonas Lekevicius (N56PMJ99UT)`.
4. Sparkle's EdDSA update-signing key (2.8b). The key pair was generated on
   the Mac mini on 2026-10-04 with Sparkle's `generate_keys` (in the resolved
   package: `Packages/Integration/.build/artifacts/sparkle/Sparkle/bin/`); the
   private key is in that Mac's login keychain (account `ed25519`), the public
   key is `SPARKLE_PUBLIC_ED_KEY` in `xcodegen/base.yml`. On the machine that
   signs releases: `generate_keys -x sparkle-private-key` on the Mac mini,
   move the file privately, `generate_keys -f sparkle-private-key` there, then
   delete the file. Never commit it; losing it means a new key and a release
   that every installed copy must take by hand.
5. Update feed and crash reports: `ROOM_UPDATE_FEED_URL` (a `.invalid`
   placeholder until the product name and domain are settled, B-6) and
   `ROOM_SENTRY_DSN` (empty until a Sentry project exists) in
   `xcodegen/base.yml` are the one place for both.

## 6. Reference material (optional)

`research/repos/` is gitignored. Recreate what a task needs:

```bash
git clone https://bitbucket.org/chromiumembedded/cef.git research/repos/cef
git clone https://github.com/zen-browser/desktop research/repos/zen-desktop
# ArcCore headers (proprietary, study only, never copy code), if Dia is installed:
mkdir -p research/repos/arccore-headers
cp -R /Applications/Dia.app/Contents/Frameworks/ArcCore.framework/Versions/A/Headers/ research/repos/arccore-headers/
```

Arc, Dia and Zen installed in `/Applications` serve as visual references
(`research/notes/visual-reference.md`).

## Machine facts worth knowing

- Apple Developer team: `N56PMJ99UT` (Jonas Lekevicius). Signing identities
  are the user's; never handle credentials directly.
- The user types on Colemak: test keyboard shortcuts with real key events.
- Screen captures of Chromium's GPU layer need an external capture (Screen
  Recording permission); the app's own `CGWindowListCreateImage` misses it.
