# RoomCore — the Chromium fork

`RoomCore.framework` is Chromium (pinned tag `154.0.8037.58`) with Room's
code in `//room` and a handful of small patches, exporting an Objective-C API
the Swift app links against. Phase 1.5 is the embryo: application bootstrap,
profiles, one `WebContents` with a native view, a `Browser` bound to the
host's window through a stub `BrowserWindow`, and a clean quit.

## Layout

| Path | What |
|---|---|
| `room/` | `//room`, symlinked into the checkout as `$CHROMIUM_SRC/room` (location per machine: `local.env`) |
| `room/core/` | the public ObjC API (`public/RoomCore.h` umbrella, `module.modulemap`) and its ObjC++ implementation; `room_core.exports` lists the classes an official (static) framework exports |
| `room/browser/` | `RoomBrowserWindow`, Chrome's `BrowserWindow` for a host-owned `NSWindow` |
| `room/branding/BRANDING` | product name Room, bundle id `app.room.desktop` (helpers `.helper*`) |
| `room/build/config.gni` | `room_framework_name = "RoomCore"`; the GN arg `room_enable_spikes` (default false, true in `args/dev.gn`) gating the `-RoomSpike` hooks and the diagnostic executables |
| `room/build/BUILD.gn` | `//room/build:buildflags` (`BUILDFLAG(ROOM_ENABLE_SPIKES)`) |
| `patches/` | quilt-style patches, applied in `series` order, one commit each on the `room` branch |
| `chromium_src/` | Brave-style shadow sources (empty) |
| `args/dev.gn` | GN args of `out/dev` (component build, branding) |
| `args/release.gn` | GN args of `out/release` (official static build, ThinLTO, dSYMs, `chrome_pgo_phase = 0`; 3.1b) |
| `tools/gen_browser_window_stubs.py` | regenerates `room_browser_window_stubs.cc` from the checked-out headers |

## Patches

| Patch | Why |
|---|---|
| `0001-framework-name-roomcore` | the framework is `RoomCore.framework` (binary `RoomCore`): `chrome_framework_name`, `kFrameworkName`, the helpers' `dlopen` path, and (3.1b-2) libaperitif's install name in `content/public/app/BUILD.gn`, which the official build's Aperitif helpers verify |
| `0002-keychain-room-safe-storage` | the OSCrypt keychain item is `Room Safe Storage` / `Room`, never Chromium's |
| `0003-browser-window-factory-hook` | `BrowserWindow::CreateBrowserWindow` asks `//room` first, so a `Browser` created for a Room window gets a `RoomBrowserWindow` |
| `0004-link-room-core` | `chrome_dll` depends on `//room/core`, so the API is inside the framework; (3.1b-2) the official build's export list gains `room/core/room_core.exports` (the public classes) and its export-order check reads it too |
| `0005-read-anything-without-side-panel` | Read Anything treats a browser without a side panel as legitimate (upstream only exempts its WebUI browser and tests) |

The original five patches are unchanged by background hardening. Additional
factory/anchor hooks keep their implementations in `//room`; narrow upstream
guards cover call sites that offer no Room hook:

| Patch | Why |
|---|---|
| `0006-component-update-scheduler-hook` | disable automatic checks while preserving explicit on-demand component updates |
| `0007-demand-cdm-factory-hooks` | observe an actual EME request and CDM registration without public ObjC API changes |
| `0008-fedcm-anchor-hook` | supply native bubble/modal parents without pretending Cocoa content is a Views WebView |
| `0009-sad-tab-factory-hook` | contain renderer loss in a Cocoa fallback; SadTab::Create otherwise directly constructs a BrowserView-dependent controller |
| `0011-browser-window-lookup-hook` | Room window lookup for legacy autofill callers; guard the optional Chrome-only address-save promo |
| `0012-extension-chooser-toolbar-guard` | extension-origin chooser uses the nullable registered toolbar provider; reject safely when no extension container exists instead of dereferencing a missing BrowserView |

Patch `0010-shutdown-worker-start-priority` (PR #1) is parked in `patches/parked/` (B-40; the README there says why and when it comes back). The series has eleven patches.

No patch is needed for `NSApp`: the host's `NSApplication` subclass inherits
from `RoomCrApplication`, which RoomCore defines as a subclass of Chromium's
`BrowserCrApplication`, so `RegisterBrowserCrApp()` accepts the host's object
unchanged.

## Workflow

```bash
scripts/roomcore-apply.sh          # symlink //room, room branch + patches, branding links, out/dev/args.gn
scripts/roomcore-build.sh          # apply (no-op if unchanged) + autoninja -C out/dev chrome
scripts/roomcore-package.sh        # stage build/roomcore/RoomCore.framework, build Room.app on RoomCore and the embryo host, ad-hoc sign
scripts/roomcore-baseline.sh <dir> # nav assertions + ten-page quit x3 on the embryo host
scripts/sign-and-notarize.sh build/roomcore/DerivedData/Build/Products/Debug/Room.app --no-notarize
# release (3.1b): official static build, packaged and team-signed
bash -c 'ROOM_BUILD_JOBS=6 ROOM_OUT_DIR=out/release ROOM_GN_ARGS=release.gn nohup scripts/roomcore-build.sh > build/roomcore-release-build.log 2>&1 &'
scripts/roomcore-package.sh --release   # build/roomcore-release (ROOM_NOTARIZE=1 notarizes)
scripts/roomcore-sign.sh                # Developer ID + notarization of the release app
```

Start long builds from `bash` (`bash -c 'nohup … &'`), never zsh `&`: zsh's
`BG_NICE` renices background jobs.

`roomcore-package.sh` copies the ~500 component dylibs into
`RoomCore.framework/Versions/<version>/Libraries` (APFS clones, no disk cost)
(APFS clones when the out directory is on the same volume). The framework
binary has no Mach-O header room for another rpath, so the host executable
carries `…/RoomCore.framework/Versions/Current/Libraries` and, in the
component build, links `libchrome_dll` directly (`xcodegen/roomcore.yml`); the
helpers already search that directory. Helper bundles are re-signed ad hoc
(GN leaves only linker signatures). Builds without a
team signature run with `--use-mock-keychain`, decided by `RoomApplication`
from the process's code signature at launch (a new code identity per build
would prompt for the login password on every read of "Room Safe Storage",
and navigations wait on the cookie store until it is answered); team-signed
builds use the keychain.

Things Chrome expects of a browser window that the host does not provide are
met inside `//room`: `RoomLocationBar`, `RoomExclusiveAccessContext`, a hidden
Bookmarks menu item (`RoomCrApplication -setMainMenu:`), and
`TearDownPreBrowserWindowDestruction()` in `~RoomBrowserWindow`. Two Xcode targets link the staged framework (`xcodegen/roomcore.yml`; all
three products are `Room.app`, so each has its own DerivedData):

- `RoomCoreApp`, scheme "Room (RoomCore)": the Chapter 2 app (`App/Sources`)
  on `Packages/EngineRoomCore`, `ROOM_ENGINE=roomcore`, built into
  `build/roomcore/DerivedData`. Launch it with `-RoomStateDirectory <dir>
  -RoomEngineDirectory <dir>/engine` for a throwaway state; the engine data
  root defaults to `~/Library/Application Support/Room/RoomCore`.
- `RoomCoreHost`, scheme "RoomCore Host": the Phase 1.5 embryo host
  (`App/RoomCore`) the engine-level scripts drive, built into
  `build/roomcore-host/DerivedData`. Its feature drives compile only when the
  framework has the spike hooks (`ROOM_SPIKES`, passed by the package script
  when `room_enable_spikes = true`).

The data root holds `Local State`, the profiles (`Room Profile <name>` from
the app, `Default` from Chromium's startup), `RoomCore.log` (unless the host
passes `--enable-logging`/`--log-file`) and `Crashpad/` (handler annotation
`prod=Room_Mac`, no upload URL). The framework's Info.plist carries
`RoomCoreCommit` (the last commit touching `//room`), read into the
`room-commit` crash key beside `room-app-version` and `room-chromium`.

## Rebasing

Patches apply with `git apply`; after moving to a new tag, re-run
`tools/gen_browser_window_stubs.py` to pick up `BrowserWindow` changes (a
changed signature is a compile error in the stubs file).
