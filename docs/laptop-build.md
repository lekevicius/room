# Building Room.app on the laptop during the week

Two ways. The first needs no Chromium build: the laptop links the Swift app against a `RoomCore.framework` copied from the Mac mini (the fork is 155.0.8059.36 with 23 patches there, built on 2026-10-06). The second rebuilds the fork on the laptop (hours, once; then `//room` incrementals of a minute). For app-level changes during the week, the first is enough: the framework does not change when `App/` or `Packages/` change.

The Mac mini is `eve@eve.local` (192.168.1.64) and the repository there is `/Users/eve/Code/room`. Everything below runs on the laptop in its own clone of the repository, on `main`.

## A. No Chromium build: copy the staged framework

1. Pull `main` and generate the project:

```bash
git pull --ff-only && xcodegen
```

2. Copy one staged framework from the Mac mini. The release framework is the one to use (367 MB, static, what the DMG ships, no DCHECKs, a renderer starts in 0.03 s); the component one (931 MB, 518 dylibs, `DCHECK_ALWAYS_ON`) is only for engine work and is not needed on the laptop.

```bash
mkdir -p build/roomcore-release && rsync -a --delete eve@eve.local:/Users/eve/Code/room/build/roomcore-release/RoomCore.framework build/roomcore-release/
```

3. Build Room.app over it. `ROOMCORE_STAGE` points the project at the copied framework; the two empty settings turn off the component-build link flags (a static framework has no `libchrome_dll`). `Debug` gives the DEBUG app with the spike runner, fixtures and `-RoomStateDirectory`; `Release` gives the product app. The `EngineRoomCore` package compiles against `build/roomcore/RoomCore.framework` whatever `ROOMCORE_STAGE` says (its `-F` is fixed in `Package.swift`), so that path must be the same framework: on the laptop an old stage from 2026-10-02 was there and the build failed with "cannot find type 'RoomPermissionRequest'" (laptop checks, 2026-10-06). Once:

```bash
[[ -e build/roomcore ]] && mv build/roomcore build/roomcore-stale-$(date +%F); mkdir -p build/roomcore && ln -s ../roomcore-release/RoomCore.framework build/roomcore/RoomCore.framework
```

```bash
xcodebuild -project Room.xcodeproj -scheme "Room (RoomCore)" -configuration Debug -derivedDataPath build/roomcore-release/DerivedData ROOMCORE_STAGE="$PWD/build/roomcore-release" ROOMCORE_COMPONENT_LDFLAGS= ROOMCORE_LIBRARY_PATH= build
```

The app is `build/roomcore-release/DerivedData/Build/Products/Debug/Room.app` (or `Release/Room.app`), ad-hoc signed by the embed phase, so it runs with the mock keychain (no prompt, no access to the login keychain's cookies and passwords: for real accounts use the signed DMG).

A Debug app copied from the Mac mini instead of built here runs, but its spikes find their `file://` fixtures through `#filePath` (`SpikeRunner.pagesDirectory`, the fixtures' `phase25Page`), i.e. under `/Users/eve/Code/room`: on the laptop those pages are error pages (the spaces fixture's 50 "loaded" pages took 14 renderers instead of 52, and the tour's audio, popups, keys and tabs steps failed on missing elements). Spikes on HTTP fixtures or real sites (palettemeasure, tabsmeasure, sidebar snapshots) are unaffected; for the rest build the Debug app here (step 3, 28 s).

4. Launch it on a scratch state, never on the real one unless you mean to:

```bash
build/roomcore-release/DerivedData/Build/Products/Debug/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-week -RoomEngineDirectory /tmp/room-week/engine -RoomSidebarFixture demo
```

5. Iterate: edit `App/` or `Packages/`, rerun step 3 (Xcode's incremental build; the framework copy is stamped and not recopied). Unit tests as usual: `CI=1 swift test --package-path Packages/<name>`; the window tier through the `Room` scheme.

What does not work this way: anything that changes `//room` or a patch (that needs the fork built), and `scripts/roomcore-package.sh` itself (it stages from `out/dev` or `out/release`, which the laptop lacks until section B). The spike wrappers (`scripts/run-spike.sh`, `scripts/grand-tour.sh`, `scripts/tabs-measure.sh`, `scripts/sidebar-snapshots.sh`) take `ROOM_APP=build/roomcore-release/DerivedData/Build/Products/Debug/Room.app` and otherwise need only the repository and `scripts/test-servers.sh`; `scripts/netlog-check.sh` sources `scripts/lib/chromium-env.sh` and wants a `local.env` (the laptop's existing one is fine; it only reads the annotations file from the checkout when present).

Refreshing the framework later (after a `//room` change on the Mac mini): rerun step 2, then step 3; the embed phase notices the new binary's mtime.

## B. Building the fork on the laptop

Only if you want `//room` changes to build locally. `scripts/roomcore-rebase.sh` does not help a checkout that is merely behind: it compares the tag it is given with the pin in `CHROMIUM_TAG` and, once the repository is pinned, says "nothing to rebase" (found 2026-10-07). A stale checkout catches up with the scripts a new machine uses:

```bash
cd "$CHROMIUM_SRC" && git checkout --detach && git branch -m room room-old && rm -f room; cd -
bash -c 'nohup sh -c "scripts/chromium-checkout.sh && scripts/roomcore-apply.sh && scripts/roomcore-build.sh" > build/laptop-fork-setup.log 2>&1 &'
```

The first line parks the old `room` branch (its patches are files in the repository; `roomcore-apply.sh` refuses a branch with commits outside the series) and removes a `src/room` link that points at another clone or worktree (the apply script refuses that too and relinks it to this repository). The second fetches the pinned tag, checks it out, syncs DEPS (`gclient` downloads the clang roll and deps) and runs the hooks, applies the series on a new `room` branch, writes `out/dev/args.gn`, and starts the clean build (64 GB: the default job count is fine; Phase 1.5's clean build on this laptop took 4 h 24 min, partly at reduced priority). When it ends, `scripts/roomcore-package.sh` stages and builds both apps as on the Mac mini; then `build/roomcore` is the component stage again, not the link to the release framework from section A step 3. Timings: `research/notes/build-log.md`, "Laptop fork setup".

## The signed build

The product build for the week is the DMG the Mac mini made (`build/sparkle-3.9/Room-0.1.0-1.dmg`, notarized): copy it with

```bash
scp eve@eve.local:/Users/eve/Code/room/build/sparkle-3.9/Room-0.1.0-1.dmg ~/Downloads/
```

Its first launch asks for the login keychain once ("Room Safe Storage"; Always Allow); it uses the real state directory (`~/Library/Application Support/Room`), real cookies and passwords. A Debug app from section A and the DMG's app do not share the password store (the mock key against the keychain's).
