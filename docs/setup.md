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
#   clean component build of `chrome` (Room.app + RoomCore.framework): hours
scripts/roomcore-package.sh   # stage the framework, build the Swift host (scheme "Room (RoomCore)")
```

The full Chromium history is needed (the `room` branch is rebased onto new
tags); do not use `--no-history`.

## 5. Signing (user)

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
