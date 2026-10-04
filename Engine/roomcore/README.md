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
| `room/core/` | the public ObjC API (`public/RoomCore.h` umbrella, `module.modulemap`) and its ObjC++ implementation |
| `room/browser/` | `RoomBrowserWindow`, Chrome's `BrowserWindow` for a host-owned `NSWindow` |
| `room/branding/BRANDING` | product name Room, bundle id `app.room.desktop` (helpers `.helper*`) |
| `room/build/config.gni` | `room_framework_name = "RoomCore"` |
| `patches/` | quilt-style patches, applied in `series` order, one commit each on the `room` branch |
| `chromium_src/` | Brave-style shadow sources (empty) |
| `args/dev.gn` | GN args of `out/dev` (component build, branding) |
| `tools/gen_browser_window_stubs.py` | regenerates `room_browser_window_stubs.cc` from the checked-out headers |

## Patches

| Patch | Why |
|---|---|
| `0001-framework-name-roomcore` | the framework is `RoomCore.framework` (binary `RoomCore`): `chrome_framework_name`, `kFrameworkName`, and the helpers' `dlopen` path |
| `0002-keychain-room-safe-storage` | the OSCrypt keychain item is `Room Safe Storage` / `Room`, never Chromium's |
| `0003-browser-window-factory-hook` | `BrowserWindow::CreateBrowserWindow` asks `//room` first, so a `Browser` created for a Room window gets a `RoomBrowserWindow` |
| `0004-link-room-core` | `chrome_dll` depends on `//room/core`, so the API is inside the framework |
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
scripts/roomcore-package.sh        # stage build/roomcore/RoomCore.framework, build the Swift host, ad-hoc sign
scripts/sign-and-notarize.sh build/roomcore/DerivedData/Build/Products/Debug/Room.app --no-notarize
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
(GN leaves only linker signatures). Ad-hoc builds run with
`--use-mock-keychain` (a new code identity per build would prompt for the
login password on every read of "Room Safe Storage", and navigations wait on
the cookie store until it is answered); team-signed builds use the keychain.

Things Chrome expects of a browser window that the host does not provide are
met inside `//room`: `RoomLocationBar`, `RoomExclusiveAccessContext`, a hidden
Bookmarks menu item (`RoomCrApplication -setMainMenu:`), and
`TearDownPreBrowserWindowDestruction()` in `~RoomBrowserWindow`. The Swift host is the Xcode target `RoomCoreHost`
(scheme "Room (RoomCore)", sources in `App/RoomCore`), built into
`build/roomcore/DerivedData` because the CEF target also produces a
`Room.app`.

## Rebasing

Patches apply with `git apply`; after moving to a new tag, re-run
`tools/gen_browser_window_stubs.py` to pick up `BrowserWindow` changes (a
changed signature is a compile error in the stubs file).
