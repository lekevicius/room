# RoomCore — the Chromium fork

`RoomCore.framework` is Chromium (pinned tag `154.0.8037.58`) with Room's
code in `//room` and a handful of small patches, exporting an Objective-C API
the Swift app links against. Phase 1.5 is the embryo: application bootstrap,
profiles, one `WebContents` with a native view, a `Browser` bound to the
host's window through a stub `BrowserWindow`, and a clean quit.

## Layout

| Path | What |
|---|---|
| `room/` | `//room`, symlinked into the checkout as `~/chromium/src/room` |
| `room/core/` | the public ObjC API (`public/RoomCore.h` umbrella, `module.modulemap`) and its ObjC++ implementation |
| `room/browser/` | `RoomBrowserWindow`, Chrome's `BrowserWindow` for a host-owned `NSWindow` |
| `room/branding/BRANDING` | product name Room, bundle id `com.lekevicius.room` (helpers `.helper*`) |
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
and adds `@loader_path/Libraries` to the framework binary; the helpers already
search that directory. The Swift host is the Xcode target `RoomCoreHost`
(scheme "Room (RoomCore)", sources in `App/RoomCore`), built into
`build/roomcore/DerivedData` because the CEF target also produces a
`Room.app`.

## Rebasing

Patches apply with `git apply`; after moving to a new tag, re-run
`tools/gen_browser_window_stubs.py` to pick up `BrowserWindow` changes (a
changed signature is a compile error in the stubs file).
