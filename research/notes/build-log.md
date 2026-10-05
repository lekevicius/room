# Build log

Wall-clock seconds unless noted. Sections up to Phase 1.5 run 1 are on the first dev machine; later machines have their own heading at the end.

First dev machine (MacBook Pro): Apple M1 Max (10 cores), 64 GB RAM, macOS 27.0.1, Xcode 27.0 (27A266a), CMake from Homebrew. Network: home connection, CDN downloads ~60–90 MB/s.

## CEF (scaffold engine)

`scripts/bootstrap-cef.sh`, CEF `154.0.32+g682c378+chromium-154.0.8037.58`, macOS arm64, `api_version=15400`.

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-01 | Download minimal (132.2 MB) | 2 s | SHA-1 matches pin and CDN index |
| 2026-10-01 | Download standard (307.0 MB), for `tests/` only | 15 s | minimal ships no `tests/`; cefsimple sources taken from standard |
| 2026-10-01 | Extract minimal | 9 s | framework 322 MB on disk, main dylib 233.8 MB |
| 2026-10-01 | Extract `tests/` from standard | 18 s | |
| 2026-10-01 | CMake configure (Unix Makefiles, Release) | 5 s | |
| 2026-10-01 | Build `libcef_dll_wrapper` (-j10) | 24 s | 5.6 MB `.a`, C++20, `-fobjc-arc` |
| 2026-10-01 | Build `cefsimple` | 127 s | validates Xcode 27 toolchain |
| 2026-10-01 | Run `cefsimple` 8 s, quit via AppleEvent | quit < 1 s, exit 0 | 5 helper processes while running |
| 2026-10-01 | Whole script, cold | 201 s | |

## Room.app (Xcode, CEF engine)

`xcodegen && xcodebuild -scheme Room -configuration Debug`, Swift 6.4 / Xcode 27.0. Bundle 324 MB (322 MB of it the CEF framework).

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-01 | Clean Debug build (6 packages, app, 5 helpers, framework copy + ad-hoc sign) | 21 s | |
| 2026-10-01 | No-op rebuild | 6 s | framework copy skipped via stamp |
| 2026-10-01 | Touch `AppDelegate.swift`, rebuild | 3 s | |
| 2026-10-01 | CI spec (`xcodegen/ci.yml`, no engine), clean build, CEF dist hidden | 18 s | proves the compile-only CI path has no CEF dependency |
| 2026-10-01 | `scripts/smoke-launch.sh` ×5 (launch, 5 s idle, AppleEvent quit) | quit 0.24 / 0.33 / 0.27 / 0.25 / 0.27 s | exit 0, 0 helpers left, 0 crash reports; 3 helpers while idle (gpu-process, NetworkService, StorageService), all from `Room Helper.app` |
| 2026-10-02 | `scripts/smoke-launch.sh` ×4 at HEAD, after the Chromium build | quit 1.54 / 1.32 / 0.37 / 0.44 s | exit 0, 0 helpers left, 0 crash reports; slower and noisier than the 0.23–0.33 s of the night before; not investigated (Phase 1.4 shutdown spike measures quit under load) |

## Chromium checkout (fork base)

`scripts/chromium-checkout.sh`: depot_tools `fetch --nohooks chromium` (full history), tag `154.0.8037.58` (= commit `a654841425914cbb703a2931e07b70a83aedbafd`, the same Chromium commit CEF 154.0.32 was built from), `gclient sync -D --nohooks`, `gclient runhooks`.

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-01 | `git clone` depot_tools | < 1 min | |
| 2026-10-01 | `fetch --nohooks chromium` | 3133 s (52 min) | 29.6 M objects, ~57 GB received at 50–70 MB/s; includes initial DEPS sync for `main`; tag came with the clone |
| 2026-10-02 | `git checkout tags/154.0.8037.58` | 23 s | |
| 2026-10-02 | `gclient sync -D --nohooks` | 93 s | |
| 2026-10-02 | `gclient runhooks` | 283 s | |
| 2026-10-02 | Checkout size | 113 GB total | `src/.git` 66 GB, `src/third_party` 40 GB |
| 2026-10-02 | `gn gen out/dev` (`Engine/roomcore/args/dev.gn`) | 6 s | 34,264 targets from 4,989 files; first attempt failed on `safe_browsing_mode=0` (see dev.gn) |
| 2026-10-02 | `xcodebuild -downloadComponent MetalToolchain` | 19 s | 839 MB; Xcode 27 does not install the Metal toolchain by default and ANGLE's shader step needs it (first build attempt failed after 70 s, 1,387/76,659 steps) |

## Chromium first component build (`out/dev`, `autoninja -C out/dev chrome`)

Siso (default driver), local only, 10 concurrent clang jobs. Target `chrome`: 76,659 steps, 46,865 object files; `out/dev` 8.1 GB, 518 component dylibs, `Chromium.app` 111 MB.

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-02 | Clean build, run 1 (stopped) | 12,806 s (3 h 33 min) | 40,147 objects. **Ran at nice +5**: zsh's `BG_NICE` renices `&` jobs; ~450 objects/min for the first 30 min, then ~130/min in V8/Blink |
| 2026-10-02 | Clean build, run 2 (resumed at nice 0) | 3,006 s (50 min) | remaining ~6,700 objects + links; 176 objects/min measured over 10 min |
| 2026-10-02 | **Clean build total** | **15,812 s (4 h 24 min)** | vs. 1.3–2 h estimate in `chromium-fork.md`. Even at nice 0 the 10 clang jobs used ~630% CPU of 10 cores; cause not isolated (needs `sudo powermetrics`/fs_usage). Load average stayed 330–430. A Google Chrome renderer used ~1.4 cores throughout |
| 2026-10-02 | Touch `chrome/browser/ui/browser.cc`, rebuild | 27 s | |
| 2026-10-02 | Touch `content/browser/web_contents/web_contents_impl.cc`, rebuild | 39 s | |
| 2026-10-02 | No-op rebuild | 4 s | |
| 2026-10-02 | Launch `Chromium.app` (fresh profile, mock keychain) | ~30 s to first helper on first launch | window + 12 helpers; quit via SIGTERM, no processes left |

Rule for long builds: start them from `bash` (`bash -c 'nohup … &'`), never zsh `&`, and check `ps -o nice` once.

## Phase 1.4 (CEF inside the card)

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-02 | Debug incremental build after an EngineCEF/App change | 10–40 s | load 30–90; `RoomCEFBrowser.mm` (1.4k lines ObjC++) dominates |
| 2026-10-02 | Release build (`xcodebuild -configuration Release`), incremental | 21 s | bundle 324 MB |
| 2026-10-02 | `scripts/sign-and-notarize.sh` signing pass (Developer ID, hardened runtime, timestamp) | 6.7 s | 8 dylibs, framework, 5 helpers, app |
| 2026-10-02 | Notarization zip (`ditto -c -k`) | — | 144 MB; submission blocked: no `notarytool` credential profile |
| 2026-10-02 | Quit with 10 loaded pages (AppleEvent) ×3 | 0.54 / 0.66 / 0.60 s | load 35–40; 0 helpers left |

## Phase 1.5 (RoomCore embryo)

Branded fork in a fresh `out/dev` (the vanilla Phase 1.1 build moved to `out/vanilla`), `scripts/roomcore-apply.sh` + `autoninja -C out/dev chrome`, started from bash at nice 0.

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-02 | `gn gen out/dev` with branding args | 9 s | 34,265 targets |
| 2026-10-02 | Clean build, run 1 (stopped by hand, laptop closed) | 3,010 s (50 min) | 17,224 of 70,495 steps, 12,651 objects; load 30→260 (Zen, Arc, Claude running), ~250–460 objects/min. Resume with the same command; the clean-build total is the sum of the runs |

## Mac mini (M4), from 2026-10-02

Mac16,10, Apple M4 (4 performance + 6 efficiency cores), 24 GB RAM, internal SSD 460 GB (22 GB free), macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Metal toolchain installed, Homebrew xcodegen/cmake/gh. Wired Ethernet (en0). Chromium lives in an APFS sparse bundle (`/Volumes/JL4/Chromium.sparsebundle`, 350 GB max, mounted at `/Volumes/Chromium`, Spotlight off) on a 4 TB SanDisk Extreme Pro USB SSD formatted exFAT; every Chromium number below carries that disk-image + USB overhead. Background apps during the session: Claude, VS Code, ChatGPT/Codex, Obsidian, Hermes, 1Password; idle load average 4–5.

### Setup (`docs/setup.md`)

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-02 | Tools (§1) | — | already present: Homebrew, xcodegen, cmake, gh (logged in), Metal toolchain, `Developer ID Application: Jonas Lekevicius (N56PMJ99UT)` in the keychain; no `notarytool` profile `room` |
| 2026-10-02 | `scripts/bootstrap-cef.sh`, cold | 199 s | concurrent with the Chromium fetch below. Minimal 3 s download + 8 s extract, standard 14 s + 16 s (`tests/`), configure 3 s, wrapper 20 s, cefsimple 125 s; cefsimple ran with 5 helpers, quit 1 s, exit 0 |
| 2026-10-02 | `xcodegen` | 0.04 s | |
| 2026-10-02 | Clean Debug build, scheme Room | 23.5 s | M1 Max: 21 s |
| 2026-10-02 | `scripts/smoke-launch.sh` ×3 | quit 0.18 / 0.18 / 0.19 s | exit 0, 3 helpers while idle, 0 left, 0 crash reports; load 5–6 |

### Chromium checkout (`scripts/chromium-checkout.sh`, tag 154.0.8037.58)

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-02 | `git clone` depot_tools | < 10 s | |
| 2026-10-02 | `fetch --nohooks chromium` | 3,442 s (57 min) | server announced ~75 GiB (laptop: ~57 GB); started at ~10 MiB/s, ~63 MiB/s after 5 min; 29.6 M objects. Laptop: 52 min |
| 2026-10-02 | `git checkout tags/154.0.8037.58` | 48 s | laptop 23 s |
| 2026-10-02 | `gclient sync -D --nohooks` | 129 s | laptop 93 s |
| 2026-10-02 | `gclient runhooks` | 291 s | laptop 283 s |
| 2026-10-02 | Checkout size | 113 GB | on the sparse bundle |
| 2026-10-02 | `scripts/roomcore-apply.sh` (symlink, `room` branch + 4 patches, branding, args) | 123 s | `gn gen out/dev` 17 s of it (34,266 targets from 4,992 files); the rest is the branch checkout and patch commits on the disk image |

### RoomCore clean build (`scripts/roomcore-build.sh`, `out/dev`, target `chrome`)

Started 2026-10-02 19:13:04 from bash with nohup, nice 0, load 4.0.

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-02 | Run 1, 10 local jobs (default), stopped by hand | 6,449 s (1 h 47 min) | 33,551 of 63,686 steps (22,311 C++ objects). ~750 steps/min for the first 16 min (load 39), ~370/min to 46 min, ~280/min to 76 min, then **~66/min**: in Blink each clang held 0.7–2.2 GB, siso 2.6 GB, 8.3 GB in the memory compressor, 0.9 GB swap, `kernel_task` at 130% CPU, each clang at ~50% CPU, load 99. Other apps held ~6 GB (OrbStack 1.4 GB, DaisyDisk 1.0 GB, Zen, Codex, Claude). 24 GB is not enough for 10 parallel Blink compiles |
| 2026-10-02 | Run 2, `ROOM_BUILD_JOBS=6` (`-local_jobs=6`), resumed 21:01:15 | 8,308 s (2 h 18 min) | 21,825 steps, stopped by the first `//room` compile error with 1,932 steps left. 6 clangs at ~82% CPU each, `kernel_task` ~12%, swap flat at 0.8 GB, load 9–14; ~80 steps/min in Blink core, 110–155/min later, ~280/min at the peak; 6.5 s average per C++ object in Blink |
| 2026-10-02 | `//room` objects alone (8 files, `-j 6`), after fixes | ~30 s | three fixes: explicit `@synthesize` (`-Wobjc-missing-property-synthesis`), `CreateBrowserWindow()` instead of the now-private `Browser::Create`, no Android-only `CanResize` stub |
| 2026-10-02 | Run 3, `ROOM_BUILD_JOBS=6`, resumed 23:23:37 | 527 s | remaining 1,539 steps incl. all links; success |
| 2026-10-02 | **Clean build total** | **15,284 s (4 h 15 min)** | 6,449 + 8,308 + 527 s, plus ~1 min compiling `//room` alone; 63,686 steps. M1 Max 64 GB vanilla: 15,812 s (4 h 24 min, partly at nice +5). `out/dev` 8.1 GB, 518 component dylibs, `Room.app` 111 MB (`RoomCore.framework` inside) |

Takeaway for 24 GB machines: build with `ROOM_BUILD_JOBS=6`; at 10 jobs the Blink phase spends most of its time compressing and swapping memory.

### RoomCore embryo on the Mac mini (Phase 1.5)

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-02 | `scripts/roomcore-build.sh` after a `//room` change (incl. the apply no-op ~25 s) | 44–63 s wall (build part); 71 s total | load 5–7 |
| 2026-10-02 | `scripts/roomcore-package.sh` (stage framework + 518 dylibs, sign helpers ad hoc, xcodegen, host build) | 10 s | framework staged 916 MB (copy, not clone: the out dir is on the disk image, the stage on the internal disk), `libchrome_dll.dylib` 152 MB, `Room.app` 917 MB; host link 3.7–3.9 s |
| 2026-10-03 | `-RoomSpike nav` (example.com → Wikipedia, back, forward, reload) | 12.2–18.2 s whole run | all states correct; `nativeView` = `WebContentsViewCocoa` in the window, 991×758; exit 0 |
| 2026-10-03 | `-RoomSpike open10`, ten typical sites to `ready` | 12 / 12 / 12 s (load 8–13); 16 / 14 / 34 s (load 15–69) | 24–35 helper processes; browser process RSS 329–443 MB |
| 2026-10-03 | Quit with 10 pages (`NSApp.terminate`, the ⌘Q path), "end" line to process exit ×6 | 0.31 / 0.18 / 0.26 s (load 8–13); 0.34 / 0.55 / 3.24 s (load 15, 16, 69) | exit 0, 0 crash reports; one `code-sign-clone-cleanup` helper (Chrome deleting its code-sign clone of the app) exits 1.4 s after the browser |
| 2026-10-03 | Quit by SIGTERM after real mouse/scroll input in the page | 0.06 s | 0 helpers left after 2 s, 0 crash reports |

### Phase 3.1a on the Mac mini (2026-10-04)

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-04 | `scripts/roomcore-apply.sh` after the PR #1 merge (six new patches 0006–0009, 0011, 0012 committed on `room`) | ~2 min | "patches: 6 applied, 5 already on the room branch"; the second run "patches: 0 applied, 11 already on the room branch" in 21 s |
| 2026-10-04 | `scripts/roomcore-build.sh` (`ROOM_BUILD_JOBS=6`), first build after the merge (patches in `chrome/`, `content/`, `base/` untouched since 0010 is parked; `//room` +1,600 lines) | **91 s** build part | load 4.3 → 7.4; component build, so only the touched objects and their dylibs relink |
| 2026-10-04 | `scripts/roomcore-package.sh` | 99 s | stage 5.8 s (916 MB, 518 dylibs), host build 92.8 s (first build of the branch's host spikes); `Room.app` 919 MB |
| 2026-10-04 | `scripts/roomcore-build.sh` after the spike gate, BRANDING `app.room.desktop`, `args/dev.gn` (`gn gen` by the apply step) and the bootstrap edits | 112 s build part | load 5.2 → 5.5 |
| 2026-10-04 | `scripts/roomcore-build.sh` after a one-file `//room` edit (real path of the data root) | 47 s build part | load 6.0 → 6.7 |
| 2026-10-04 | `scripts/roomcore-package.sh` building both RoomCore targets | stage 4.8–8.5 s; host 7.4 s, Room.app on RoomCore 12.3–19.6 s (incremental) | Room.app on RoomCore 945 MB |

### Phase 3.1b on the Mac mini (2026-10-04): the official release build

`Engine/roomcore/args/release.gn` (`is_official_build=true`, `is_component_build=false`, `is_debug=false`, `symbol_level=1`, `enable_dsyms=true`, codecs, Widevine, `enable_updater=false`, branding, no `room_enable_spikes`); `gn args --list` shows `use_thin_lto = true` already implied, `is_cfi = false`, `use_lld = true`. Changed from the ROADMAP's list: **`chrome_pgo_phase = 0`** (the first `gn gen` failed: the official build wants `chrome/build/pgo_profiles/chrome-mac-arm-8037-….profdata`, which gclient downloads only with `custom_vars` `checkout_pgo_profiles`). `gn gen out/release`: 35,311 targets from 4,985 files in 13.1 s. Target `chrome`: **57,703 steps** (`third_party/ninja/ninja -C out/release -t commands chrome | wc -l`).

Started **17:54:44** from bash with nohup (`ROOM_BUILD_JOBS=6 ROOM_OUT_DIR=out/release ROOM_GN_ARGS=release.gn scripts/roomcore-build.sh`, pid 72579, log `build/roomcore-release-build.log`), nice 0, load 5.0. Siso prints only dots without a terminal; the step count is the number of lines in `out/release/siso_metrics.json` (one per finished step). The session's measurements ran beside it (load 11–49; the concurrent watchdog harness pushed load to 160 for 5 min).

| Wall clock | Elapsed | Steps done / 57,703 | Rate since previous | Load (1 min) | Notes |
|---|---|---|---|---|---|
| 18:06 | 0:12 | 10,311 (17.9 %) | — | ~10 | mostly cheap steps (codegen, stamps, copies) |
| 18:23 | 0:28 | 18,661 (32.3 %) | 491/min | 29 | |
| 18:53 | 0:59 | 25,799 (44.7 %) | 238/min | 15 | pageouts 54,246, swap 1.59 of 2 GB used |
| 19:02 | 1:08 | 26,649 (46.2 %) | 94/min | 76 | the concurrent watchdog harness (3 hosts × 10 pages) ran 18:56–19:01 |
| 19:19 | 1:25 | 28,135 (48.8 %) | 87/min | 26 | the serial watchdog harness ran 19:03–19:18 |

Other steps this session (component build, beside the release build):

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-04 | `scripts/roomcore-package.sh --app-only` after the `xcodegen/roomcore.yml` stage settings | 32.9 s | stage 12.1 s, Room.app on RoomCore 20.6 s; component link unchanged (`-lchrome_dll` by default) |
| 2026-10-04 | `scripts/roomcore-sign.sh` (Developer ID, clone of the Debug app) | 31.4 s signing, 92 s with the clone | 945 MB app, 518 dylibs signed 8 at a time |
| 2026-10-04 | Notarization zip (`ditto -c -k`) + `notarytool submit --wait` | 44 s + 134 s | 290 MB; Accepted (41d74c9a-dc7b-4fec-aaf7-f2ae65a8905b), stapled |
| 2026-10-04 | Sparkle DMG (`hdiutil create -fs HFS+ -format UDZO`) | 14.1 s | 339,023,043 bytes |
| 2026-10-04 | `swiftc -O scripts/lib/room-ae.swift` (first use of the wrappers) | 1.3 s | `build/tools/room-ae` |

The 3.1b run's end (from its own `siso_metrics.1.json`, finish times relative to Siso's start at 17:54:45; the session had ended, the machine was otherwise idle):

| Elapsed | Steps finished | Notes |
|---|---|---|
| 0:30 | 19,406 | |
| 1:00 | 26,013 | |
| 2:00 | 31,018 | |
| 3:00 | 40,845 | |
| 4:00 | 53,655 | |
| 4:24:33 (22:19) | — | **framework link starts** (`solink obj/chrome/chrome_framework_shared_library/RoomCore`, ThinLTO, `thinlto-cache` in the out directory) |
| 4:42:38 (22:37) | 57,373 | framework link done; **build fails** at 4 h 42 min 39.6 s with 1 failed step, 354 remaining: `//chrome:verify_libraries_chrome_helper_app_aperitif_alerts` (below) |

### Phase 3.1b-2 on the Mac mini (2026-10-04): the release build finished

**The framework link fit in 24 GB.** Siso's metrics for the link step: wall **1,092 s (18 min 12 s)**, `max_rss` **7,305,510,912 bytes (6.80 GiB)**, user 3,816 s, sys 108 s, 1.58 M major faults; started 22:19:18 with every compile finished (no other step beside it). The largest `max_rss` of the whole build is `v8_context_snapshot_generator`'s link (6.98 GiB, 445 s); the largest compile is Blink's `document.o` at 2.92 GiB. `vm_stat` pageouts 55,877 at 19:18 and 59,923 at 23:07 (+4,046 over the rest of the build, the link included; not sampled during the link itself); swapouts 359,844 at both.

**The one failed step.** The Aperitif helpers verify their load commands (`chrome/tools/build/mac/verify_dynamic_libraries.py`, official non-component builds only): "Room Helper (Aperitif Alerts)" linked `@executable_path/../Frameworks/Room Framework.framework/Versions/154.0.8037.58/Libraries/libaperitif.dylib` where `@executable_path/../../../../Libraries/libaperitif.dylib` is expected. `content/public/app/BUILD.gn` builds libaperitif's install name from `"$chrome_product_full_name Framework.framework"`, and `chrome/BUILD.gn`'s `installnametool -change` (patch 0001 renames `$chrome_framework_name` to `RoomCore`) looks for `RoomCore.framework`, so the change never matched. Fixed in patch 0001 (the `content/public/app/BUILD.gn` hunk: the install name from `room_framework_name`).

| Run | Start | Wall | Steps | Result |
|---|---|---|---|---|
| 1 (3.1b) | 17:54:44 | 4 h 42 min 39.6 s | 57,373 | failed: the verify step above |
| 2 | 22:52:16 | 7 min 06 s (Siso's graph load and `gn gen` after the BUILD.gn change; libaperitif relinked with the new install name) | 6 | failed: `verify_libraries_chrome_helper_app_aperitif_renderer`, same message. The helpers were not relinked: libaperitif's `.TOC` (exports only) did not change, so Siso's restat skipped every dependent link. After run 2 the (Aperitif) and (Aperitif GPU) helper binaries were gone from their `obj/` directories (removed by Siso); the other two (`obj/chrome/chrome_helper_app_aperitif_{alerts,renderer}_executable/…`) were deleted by hand to force the relink (an incremental-only problem: a clean build links the helpers after libaperitif) |
| 3 | 23:05:23 | **48 s** | 336 | **succeeded** |
| 4 | 23:36:39 | 7 min 03 s | 27 | after patch 0004's export list (the Swift app could not link the official framework: its exports list hid the public classes): the framework relinked in **329 s at `max_rss` 8,089,092,096 bytes (7.53 GiB)** (ThinLTO cache from run 1), then failed at `verify_chrome_framework_order` ("unexpected export: '_OBJC_CLASS_$_RoomApplication'") |
| 5 | 23:46:57 | **78 s** | 3 | succeeded after 0004's order-check list |

**Clean build total: 4 h 42 min 40 s (run 1) + 48 s (run 3) = 4 h 43 min 28 s** of build work at 6 jobs, with the framework link 18 min of it (a clean build with the final series links the framework once, with the export list; runs 2, 4 and 5 are the fixes' incremental cost: 7 min 06 s + 7 min 03 s + 78 s). All five runs together: 4 h 58 min 55 s of build wall clock. The run-1 time includes the 3.1b session's measurements beside it for its first 1 h 25 min (load to 160 for 5 min; step rate fell from ~150 to ~70 a minute then). PLAN §7 risk 1: the Mac mini can build and link the official release build; ROADMAP's "the laptop does release builds" is a preference, not a necessity.

Other steps this session:

| Date | Step | Time | Notes |
|---|---|---|---|
| 2026-10-04 | `scripts/roomcore-apply.sh` after amending 0001 (the branch rebuilt in a scratch index, `git reset --keep`) | 26.0 s | "11 applied, 0 already"; only `content/public/app/BUILD.gn` changed on disk; second run "0 applied, 11 already" in 25.3 s |
| 2026-10-04 | `scripts/roomcore-build.sh` (`out/dev`) after the `//room` network defaults and the 0001 change (`gn gen` regenerates) | 63 s build part, 95 s total | load 4.7 |
| 2026-10-04 | `scripts/roomcore-package.sh` (`out/dev`, both targets) | 62.5 s | stage 17.8 s, host 24.4 s, app 20.2 s |
| 2026-10-04 | `scripts/roomcore-apply.sh` after 0004's two amendments | ~26 s each | "8 applied, 3 already" (0004–0012 recommitted; only `chrome/BUILD.gn` changed on disk), then "0 applied, 11 already" |
| 2026-10-04 | `scripts/roomcore-build.sh` (`out/dev`) after the 0004 GN change | 48 s build part | the export list applies only to non-component builds: nothing relinked |
| 2026-10-04 | `scripts/roomcore-package.sh --release` (Release; first success) | 107 s | stage 3.1 s (364 MB framework, copied across volumes), 15 dSYMs 2.2 GB, host 14.5 s, app 89.8 s; Room.app 382 MB, ad hoc. The first attempt filled the internal disk copying all 128 dSYMs (3.6 GB) |
| 2026-10-04 | `CONFIGURATION=Debug scripts/roomcore-package.sh --release --app-only` | 37 s | the DEBUG spike runner over the release framework, 392 MB |
| 2026-10-04 | `scripts/roomcore-sign.sh` (clone of the Release app, Developer ID) | 9.3 s signing | 382 MB |
| 2026-10-04 | Notarization zip + `notarytool submit --wait` | 61.3 s in the service | 161 MB zip; Accepted (bfee631a-5b17-4400-80f0-25433022a0a7), stapled |
| 2026-10-05 | Sparkle DMG (`hdiutil`, UDZO) of the signed copy | 8.1 s | 184,497,802 bytes |

### Phase 3.2a on the Mac mini (2026-10-05)

`out/dev`, `ROOM_BUILD_JOBS=6`, nothing else building; `out/release` untouched (stale since the `//room` edits).

| Step | Time | Notes |
|---|---|---|
| `scripts/roomcore-apply.sh` with patches 0014 and 0015 added | ~25 s | "2 applied, 11 already"; the run after: "0 applied, 13 already" |
| `gn check out/dev '//room/*'` | 7.4 s | header dependencies OK |
| `scripts/roomcore-build.sh` (`//room/browser` and `//room/core` rewritten, two patched Chromium files) | **77 s** build part | load 4.0 → 6.5; no warnings |
| `scripts/roomcore-build.sh` (the fullscreen exit fix in `//room`) | **45 s** | load 4.1 → 3.7 |
| `scripts/roomcore-package.sh` (both targets) | 30 s | host 8.6 s, app 16.2 s |
| `scripts/roomcore-package.sh --app-only` / `--host-only` (spike changes) | 8–17 s each | |


### Phase 3.2b on the Mac mini (2026-10-05)

`out/dev`, `ROOM_BUILD_JOBS=6`, nothing else building; `out/release` untouched (stale since the `//room` edits).

| Step | Time | Notes |
|---|---|---|
| `scripts/roomcore-apply.sh` with patch 0013 inserted | ~20 s | "3 applied, 11 already" (0014 and 0015 recommitted behind 0013); the run after: "0 applied, 14 already" |
| `scripts/roomcore-build.sh`: patch 0013 (`app_controller_mac.mm`, `chrome_browser_main_mac.mm`), `room_app_controller.mm` new, `//room/core` and `//room/browser` edits | **79 s** build part | load 2.2 → 4.9; compiled on the first attempt |
| rebuild: the Apple-event reply fix, the crash-mark commit | 46 s | load 4.0 → 4.9 |
| rebuild: `RoomCrApplication.h` comment | 47 s | |
| `gn check out/dev '//room/*'` | 8 s | three missing deps (`app_controller_mac`, `lifetime`, `browser_active_state_manager`) added; then OK |
| rebuild after the GN deps (the last engine change) | 48 s | |
| `scripts/roomcore-package.sh` | 37 s first (Swift: host 15.7 s, app 15.1 s), 17–19 s later | framework 924 MB staged, 518 dylibs |
| `xcodebuild -scheme Room` (CEF, for the keys comparison) | 13 s | incremental |

### Phase 3.3a on the Mac mini (2026-10-05)

`out/dev`, `ROOM_BUILD_JOBS=6`, nothing else building; `out/release` untouched (stale).

| Step | Time | Notes |
|---|---|---|
| `scripts/roomcore-apply.sh` with patch 0016 appended | ~10 s | "1 applied, 14 already"; the runs after: "0 applied, 15 already" |
| build 1: patch 0016 (`chrome_content_browser_client_navigation_throttles.cc`), `//room/core` (throttle, observers, public API) | failed | 15 errors: auto-synthesised `RoomNavigationAction` properties (`-Wobjc-missing-property-synthesis`), `blink::mojom::Referrer` incomplete, `SadTabHelper::FromWebContents` absent, `SECURE_WITH_POLICY_INSTALLED_CERT` gone in M154, `::mojom` namespace |
| build 2 (fixed) | **55 s** build part | load 3.6 |
| rebuild: unhide the hidden contents' view | 54 s | |
| rebuild: Views modal host at Browser creation (after a `-Wshadow` failure) | 57 s | |
| rebuild: discard log line | 49 s | |
| rebuild: `WebContentsDiscard` disabled | 43 s | |
| `gn check out/dev '//room/*'` | 7 s | three deps added (`//chrome/browser/favicon`, `//chrome/browser/translate`, `//components/favicon/content`); then OK |
| rebuild after the GN deps (the last engine change) | 29 s | |
| `scripts/roomcore-package.sh` | 27–40 s (`--app-only` 15–25 s) | the first Swift failure was `createWebContentsInitiallyHidden:`'s import name (NS_SWIFT_NAME added) |
| `xcodebuild -scheme Room` (CEF app) | ~60 s first, then incremental | Engine/Tabs/EngineCEF changes |
| `xcodebuild test -scheme Room` (window tier) | ~4 min | 453 tests |

### Phase 3.3b on the Mac mini (2026-10-05)

`out/dev`, `ROOM_BUILD_JOBS=6`, nothing else building; `out/release` untouched (still 3.1b-2's //room).

| Step | Time | Notes |
|---|---|---|
| `scripts/roomcore-build.sh` (apply: "0 applied, 15 already") build 1: `room_web_contents_tools.mm` (find, capture, print, DevTools), main-world scripts for devtools: pages, the DevTools key forward | failed | `viz::CopyOutputBitmapWithMetadata` incomplete (header and `//components/viz/common` dep added) |
| build 2 | **73 s** | load 4.6 → 4.9 |
| build 3: the modal anchor ordered above the host window | **55 s** | load 4.5 |
| build 4: `processGone` (`PrimaryMainFrameRenderProcessGone`) | failed | `TERMINATION_STATUS_INTEGRITY_FAILURE` is Windows-only |
| build 5 (the last engine change) | **54 s** | load 3.8 |
| `scripts/roomcore-package.sh` | 25–40 s each (Swift: host 5 s, app 10–15 s) | first Swift failure: `devToolsWebContents` imported as `devTools` (NS_SWIFT_NAME added) |
| `CONFIGURATION=Release scripts/roomcore-package.sh --app-only` (Release app over the dev framework) | ~90 s | the release framework (`build/roomcore-release`, 3.1b-2) cannot run today's app: `RoomCoreApplication.applicationDelegate` → unrecognized selector (3.2b API) |
| `scripts/roomcore-package.sh --release --app-only` | 65 s Swift | built, crashes at launch for the reason above (two crash reports, 06:59) |

## RoomCore background hardening — M1 Max laptop, 2026-10-03

64 GB RAM, default Siso job count, existing `out/dev` resumed from the prior
17,224/70,495-step run (3,010 s). Source symlink points to the isolated
`bg/roomcore-hardening` worktree; five existing patches unchanged.

| Local time (Europe/Vilnius) | Elapsed | Progress / result | Priority / load |
|---|---|---|---|
| 2026-10-03 02:28:07 | start | resumed `autoninja -C out/dev chrome`; Siso recalculates remaining total after regeneration | build and Siso nice 0, default jobs; load 20.59 / 45.70 / 49.30 |
| 2026-10-03 02:46:19 | 18 m 12 s | 5,385 / 51,154 remaining-run graph steps (Siso recalculated total); still compiling V8/media | nice 0; load 440.95 / 443.86 / 348.54; 10 logical CPUs, 68,719,476,736 bytes RAM |
| 2026-10-03 03:09:20 | 41 m 13 s | 11,755 / 47,624 graph steps; compiling Blink core/platform, no failure/completion marker | nice 0; load 504.45 / 476.79 / 436.47 |
| 2026-10-03 03:28:06 | 59 m 58.68 s | hourly sample recovered from log: 14,381 / 47,505 graph steps, Blink CSS | load not sampled at exactly one hour |
| 2026-10-03 03:34:28 | 1 h 6 m 20.83 s | 14,904 / 47,504 graph steps, Blink SVG/style; no failure/completion marker | build/Siso nice 0; load 505.28 / 499.28 / 484.07 |
| 2026-10-03 03:59:22 | 1 h 31 m 15.27 s | 17,002 / 47,361 graph steps, Blink bindings/payments; no failure/completion marker | build/Siso nice 0; load 426.61 / 458.57 / 474.10 |
| 2026-10-03 04:24:22 | 1 h 56 m 15.32 s | 21,458 / 46,951 graph steps, Views/permissions/download components; no failure/completion marker | build/Siso nice 0; load 490.11 / 490.62 / 486.98 |
| 2026-10-03 04:28:05 | 1 h 59 m 58.49 s | hourly sample recovered from log: 22,159 / 46,860 graph steps; second hour +7,778 completed steps | load not sampled at exactly two hours |
| 2026-10-03 04:49:29 | 2 h 21 m 22.26 s | 27,080 / 44,307 graph steps, extensions/web apps/autocomplete; no failure/completion marker | build/Siso nice 0; load 490.20 / 482.00 / 477.36 |
| 2026-10-03 05:14:23 | 2 h 46 m 15.72 s | 34,961 / 40,924 graph steps, Chrome enterprise/UI components; no failure/completion marker | build/Siso nice 0; load 492.17 / 482.50 / 479.04 |
| 2026-10-03 05:28:07 | 2 h 59 m 59.50 s | hourly sample recovered from log: 37,004 / 40,556 graph steps; third hour +14,845 completed steps | load not sampled at exactly three hours |
| 2026-10-03 05:39:26 | 3 h 11 m 18.86 s | 38,955 / 39,975 graph steps, Chrome WebUI/preloading components; no failure/completion marker | build/Siso nice 0; load 480.14 / 481.37 / 485.62 |
| 2026-10-03 05:41:37 | 3 h 13 m 30 s | **Build succeeded**, 39,698 executed graph steps; 39,084 local, 614 noexec, 45,805 skipped; **11,610 s resumed**, **14,620 s cumulative (4 h 3 m 40 s)** | nice 0; Siso localexec capacity **10**, action pool 10; retry 0; final load 404.72 / 462.97 / 478.30 |

Total clean branded time must add 3,010 s from the earlier partial run to
this resumed build; do not call the resumed wall time a clean-build total.


Build completion was observed at the 06:04 scheduled poll; compiler processes
had exited and system load had fallen to 29.13 / 33.90 / 121.27. No compiler
failures or retries occurred. The five patches and //room sources remained
unchanged throughout the resumed build.

### Laptop baseline after completed component build (2026-10-03)

| Check | Laptop result | Mac mini comparison |
|---|---|---|
| Package/sign | 518 component dylibs, 916 MB staged, 917 MB app; stage 5.3 s, cold host build 20.8 s; deep/strict ad-hoc signature valid | 518 dylibs; 916 MB; package about 10 s |
| nav | 14.209 s whole process; exit 0; load/back/forward/reload URLs and history flags correct; reload KVO observed; native view 1034×788 in window | 12.2–18.2 s whole process; 991×758 native view |
| open10 | ready 15 s, process 18.358 s, 10 pages, 0 loading at ready, exit 0; load 17.1 / 28.3 / 108.9 | ready 12 s at load 8–13 |
| ten-page quit, valid samples | 0.493 / 0.471 s; 27 / 29 helpers observed, 0 left after grace, 0 new crash reports, exit 0; load1 23.18 / 38.50 | 0.18–0.55 s at load 8–16 |
| ten-page quit, rejected sample | third attempt had 1 of 10 pages still loading after 63 s; script correctly failed the fixture instead of reporting it as a valid ten-loaded-page timing; process exited 0 | no directly matching failure recorded |

Raw laptop evidence: `research/notes/baseline-laptop-initial/` (local,
ignored). Quit raw runs: `/var/folders/z5/3xy83w8n657_xdt33yw7g_8w0000gn/T/roomcore-quit-pvi8xptc`.
Baseline nav and two ten-loaded-page clean quits pass; external-page timeout
is explicitly retained as a rejected sample. Added per-page diagnostics and
explicit warning-level stderr logging to subsequent spikes: the first-hit
stub logger was compiled in, but Chromium's default stderr configuration did
not print its WARNING messages in the initial captures.

Post-modal-fix laptop baseline: nav 11.935 s; ten loaded pages, quit 0.442 s
at load1 32.85, 28 helpers observed, 0 left, no new crash reports, exit 0.
Raw evidence: `baseline-modal-final` and `roomcore-quit-auqwxlkm` in TMPDIR.

## Background hardening follow-up — 2026-10-03 laptop

Default jobs/nice 0 retained. Network-policy last incremental 16 s / 2 steps;
Crashpad incremental 18 s / 2 steps. Ad-hoc packaging valid, 518 dylibs,
916 MB framework, 918 MB host after feature driver additions. One pre-build
apply-script failure was a pipefail/SIGPIPE false negative, not a compiler
failure; corrected history consumption, one retry succeeded (0 applied,
6 already). Original five patches unchanged; sixth scheduler hook justified
in roomcore-network-audit.md. No outside-//room compiler failure/retry.

Post-network baseline nav 23.598 s, ten-page quit 4.240 s, load1 38.39,
26 helpers/0 remaining/0 crash reports. Post-Crashpad nav 19.676 s,
ten-page quit 2.591 s, load1 43.40, 26 helpers/0 remaining/0 crash reports.
Network before/after: 600 s idle each; 62→0 HTTP requests, 86→0 connections,
9→0 DNS. Final feature regression has 18 clean process exits; fullscreen
unsupported and native UI acceptance gaps remain (spike-results.md).

Demand-CDM follow-up: //room API adjustments failed before compiling; the
first link then exposed the missing direct Blink platform/media dependency.
That dependency fixed the link in 18 s. GN check exposed a private Content
header; replace it with a public-CdmInfo callback hook instead of weakening
visibility. Final incremental 27 s / 15 steps, load 30.52 / 27.26 / 26.54;
GN header check passes. Package 518 dylibs, 918 MB app, valid ad-hoc signature.

FedCM follow-up: anchor/probe build 24 s / 4 steps; after exposing the separate
primary-widget dependency, context initialization build 28 s / 3 steps at
load 14.91 / 15.50 / 19.78. Direct GN dependency declaration recheck took
12 s / 0 actions. GN check for all //room targets passes. Passive bubble and
active loading modal probe 18 s, exit 0. Post-change nav 12.447 s, ten-page
quit 0.635 s, load1 28.40, 27 helpers / 0 remaining / 0 new crashes, exit 0.

Tab-editability fix: 22 s / 6 steps at load 14.85 / 16.81 / 19.68; GN check
all //room targets passes. Extension tabs count 1→2→1 and popup create/remove
pass (24 s process, exit 0). Post-change nav 11.570 s; ten-page quit 0.534 s,
load1 12.39, 24 helpers / 0 left / 0 new crash reports, exit 0.

Explicit native activation: 20 s / 2 steps, load 9.42 / 14.28 / 17.62.
Extension lifecycle/action probe 18 s, exit 0; AppKit active/key/main true.
Post-change nav 11.419 s; ten-page quit 0.549 s, load1 11.05, 26 helpers /
0 remaining / 0 new crashes, exit 0.

Renderer-crash containment: first incremental failed inside //room on deprecated
NSBox.borderType after 19 s; corrected to borderWidth=0. Final 22 s / 3 steps,
load 21.29 / 34.83 / 46.76, nice 0/default jobs; GN check all //room passes.
Ad-hoc strict package valid, 518 dylibs, 916 MB framework, 918 MB host (12 s
host build). Intentional crash/reload probe 39 s, exit 0. Post-fix nav 21.170 s;
ten loaded pages quit 0.554 s at load1 18.00, 26 helpers / 0 left / 0 new
crash reports, exit 0. No diagnostic sampling. Evidence: baseline-sadtab-build,
feature-renderer-crash, baseline-sadtab and TMPDIR roomcore-quit-_y_gjafd.

## Shutdown worker startup correction — 2026-10-03, laptop

Explicit standalone room_worker_shutdown_probe: initial Room-only compile
failure (SDK/constructor mismatch), corrected6.74s/2steps. It uses existing
out/dev component libraries. Patch0010 Chrome+probe rebuild30.66s/15steps,
Chromium7ac71cfacf83f. Packaging stage4.4s + host13s, strict signature valid.
Probe: entry after shutdown background/QoS9 → default/QoS25; normal entry9
unchanged, probe exit2 →0. No browser hang is asserted by this diagnostic.
Required real-site serial baseline: nav20.447s; ten loaded pages quit3.083s,
load29.759,26helpers/0left/0crashes,exit0. Details: shutdown investigation and
baseline-shutdown-worker-start. Concurrent B-38 remains a separate open gate.


## 2026-10-03 — bounded UI pass, autofill

Deferred shutdown candidate archived before source edits; accepted10-patch
Chromium restored, Room rebased onto main2239107 without protected source
changes. Probe build first failed on a capturing BindOnce lambda; correction
built56s/69steps. First repair compile corrected raw_ptr-set iteration, then
built27s/36steps. Missing direct ToolbarButtonProvider GN dependency corrected.
Second/final runtime repair adds window lookup hook and optional promo guard:
Chromium2f06f6d7533a5,63s/5steps,nice0/default jobs,out/dev reused, completion
load34.09/30.55/33.18. GN room dependency check passes. Packaging stage5s,
host10.3s,518dylibs,916MBframework/918MBapp,strict ad-hoc signature valid.
Required baseline nav15.105s,ten loaded real pages quit2.933s,28helpers/0left,
0newcrashes,exit0,load1 20.385. Address callback results and final-tab exit
failure are separately qualified in roomcore-ui-compatibility-results.md.


## 2026-10-03 — embedded UI diagnostic checkpoint

Private print/DevTools hooks only; no production/network/patch changes.
Initial build31s/13steps,load31.15/39.85/34.79,GNpass,package3.7+15.2s.
Print export hook missing RefCountedMemory include failed one compile;
correction25s/2steps,load55.47/48.95/40.62,GNpass,package4.4+8.5s,strict
ad-hoc signature valid. Host stand-in typecheck and shell syntax pass.
Print29s initial driver failure on cancel-CDP race, corrected29s/exit0:
two rendered one-page previews, both cancel/reopen,49,366-byte one-page A4
PDF1.4 output from real preview pipeline. DevTools9s/exit0,window exists
but no docking controller; concrete Chapter3 blocker. Results/identities
in roomcore-ui-compatibility-results.md and embedded-checkpoint.json.


## 2026-10-03 — synthetic media UI checkpoint

Private diagnostic changes only; public API, original patches and production
media/network policy unchanged. Build34s/2steps,load56.72/50.34/44.80; GN and
stand-in Swift typecheck pass, strict ad-hoc package valid (host14.2s).
Camera deny18s, mic deny8s, combined fake capture/indicator/stop12s, screen
picker cancel14s, all exit0. Generated VP8/WebM3,951bytes, initial4frames and
verified8frames; video PiP590×332 in12s/exit0. Document PiP320×180 opens/closes
and owning-tab closure removes its identified target in9s/exit0. Initial
size-after-close and ambiguous CDP target-count observations are retained as
probe limitations/failures, with bounded source-backed host corrections.
Muted WebAudio48kHz/0.405333s has engine muted+audible state3. No real camera,
mic or screen captured. Existing baseline/audit identities are not relabeled.


## 2026-10-03 — direct MV3 popup diagnostic

Existing out/dev, default jobs, private CLI probe only:33s/13steps, load55.25/40.12/42.55. GN dependency check passes. Package stage4.4s/host18.7s, strict signature valid. Real popup lifecycle drive18s/exit0, details in roomcore-ui-compatibility-results.md. No production behavior or network-policy change.


## 2026-10-03 — native file and download diagnostic

Initial compile failed after29.67s at a probe-only static/member DownloadManager call. Corrected build26s/2steps, load49.85/50.86/45.11; GN/Swift checks pass. Package stage4.8s/host14.3s, strict signature valid. File input20s, filesystem13s, download-close boundary10s, destination cancel11s; all exit0. Production code/policy unchanged; see UI results for unsupported close-decision UI.


## 2026-10-03 — local card registration fix and bounded autofill diagnostics

Probe38s/2steps; production registration fix29s/2steps,load113.41/98.40/75.07; final private diagnostic32s/2steps,load89.16/91.45/80.38. GN/stand-in Swift/strict signature pass after explicit probe dependency and Swift expression corrections. Baseline after production fix:nav17.169s;10loaded external pages quit4.840s,load72.982,26helpers0left0newcrashes,exit0. Card crash7s/139 before fix; cancel/accept repair19s/0. Final owner setup failed11s/0, not a lifetime pass. Address suggestion final19s/0 generates3rows but selection remains unverified due keyDown vs rawKeyDown probe boundary. See UI results and exact identity manifest.


## 2026-10-03 — extension chooser guard and final UI checkpoint

Connection diagnostic29s/2steps,load42.39/56.80/68.49. Local/loopback permission19s/exit0; USB chooser owner cleanup11s/exit0. Extension-origin USB crashes6s/exit139 at BrowserView::toolbar_button_provider. Patch0012 nullable-provider guard: first compile11.15s failed due removed transitive BaseWindow include; one corrected retry19s/2steps,load21.81/35.26/53.95. Both GN checks and strict ad-hoc package pass,host8.8s. Regression18s/exit0 safely rejects NotFoundError. Required baseline nav12.168s,10loaded external pages quit0.694s,25helpers0left0newcrashes,exit0,load45.859; no sampling,original5s grace. Apply0/12. See roomcore-ui-handoff.md and exact connection manifest.


## 2026-10-05 — Phase 3.4a (Mac mini M4, `out/dev`, 6 jobs)

Series 15 → 21 (patches 0017–0022): `scripts/roomcore-apply.sh` "6 applied, 15 already", then "0 applied, 21 already". Builds (`scripts/roomcore-build.sh`, the six patched Chrome files and the new `//room` sources): 48.6 s failed (nullability region in `RoomProfile.h`), 45.5 s failed (13 steps; an undeclared command id), 31.3 s failed (`GURL::host()` is a `string_view` in M154), 55 s, 57 s (a public property renamed), 48 s (`BrowsingDataRemover` observer registration), 43 s (toast features). `gn check '//room/*'` OK. Package (`scripts/roomcore-package.sh`) 27 s; Swift builds host 7–11 s, app 9–11 s. Load 3.5–5.


## 2026-10-05 — Phase 3.4b (Mac mini M4, `out/dev`, 6 jobs)

Series 21 → 22 (patch 0023, `views/external_protocol_dialog.cc`): `scripts/roomcore-apply.sh` "1 applied, 21 already", then "0 applied, 22 already" (also at the session's end). Builds (`scripts/roomcore-build.sh`; the new `room_page_dialogs.mm`, `room_page_state.mm`, the patched Chrome file, then `//room` only): 52 s failed (an `@selector` in a `constexpr`, a missing internal import), 60 s, 52 s (the capture observer removed at exit), 46 s (the dialog answer ordering), 45 s (`RoomProfile`'s keep-alive), 56 s (the camera+microphone prompt fix, media session), 45 s (URL copies in two blocks). Load 3.5–9 (Swift builds and spikes beside them). `scripts/roomcore-package.sh` 13 runs: framework stage ~5 s, Swift host 0.1–15.5 s, app 8.4–14.8 s; `--stage-only` does not re-embed the framework in the apps (the first dialogs rerun used the old framework; use a full or `--app-only` package after an engine build). Disk: 45 GB free on the internal drive, 205 GB on the Chromium volume; nothing deleted.

## 2026-10-05 — Phase 3.5 (Mac mini M4, `out/dev`, 6 jobs)

Series unchanged at 22 (no patch): `scripts/roomcore-apply.sh` "0 applied, 22 already" at every build and at the session's end. `//room` builds (`scripts/roomcore-build.sh`; new `room_history.mm`, `room_autocomplete.mm`, `public/RoomOmnibox.h`, the location bar and window members): three failed compiles (~45–55 s each: `room_init…` initializers outside ARC's init family and a delegate property without `@synthesize`; `SetFocusToLocationBar` regenerated out of the stubs without a declaration; `GURL::host()` is a `std::string_view` now), then 59, 51, 54 (the `NS_SWIFT_NAME` fix) and 52 s (`IsLocationBarVisible`). Packaging (`scripts/roomcore-package.sh`): framework staged in 4.2 s (925 MB, 518 dylibs), host 7.4 s, app 10.5–10.8 s; `--app-only` reruns 8.9–10.5 s. Stubs 41 → 39 (`SetFocusToLocationBar`, `IsLocationBarVisible` real).

## 2026-10-05 — Phase 3.6a (Mac mini M4, `out/dev`, 6 jobs)

Series 22 → 24 (0024 `views/extensions/extension_install_dialog_view.cc`, 0025 `extensions/chrome_extensions_browser_client.cc`): `scripts/roomcore-apply.sh` "2 applied, 22 already", then "0 applied, 24 already" at every later build. Builds (`scripts/roomcore-build.sh`): 51 s failed (the two patched Chrome files compiled; `room_extensions.mm` without `@synthesize`), then `room_extensions.o` alone three times (an incomplete `OneShotEvent`, a manifest description, a block type), 53 s, 44 s (the pin DCHECK), 39 s (the ping-less update config), 75 s (the shortcut manager; load 7, a 600 s net-log beside it). `scripts/roomcore-package.sh` nine runs: framework staged ~5 s (925 MB, 518 dylibs), Swift host 5.8–6.7 s, app 10.3–19.8 s. Disk: 45 GB free on the internal drive; nothing deleted (evidence net-logs in `build/evidence-3.6a`, ~0.3 GB).

## 2026-10-05 — Phase 3.6b (Mac mini M4, `out/dev`, 6 jobs)

Series unchanged at 24 (no patch): `scripts/roomcore-apply.sh` "0 applied, 24 already" at every build and at the end. `//room` builds (`scripts/roomcore-build.sh`; new `room_extension_popups.mm`, the browser window's `IsToolbarVisible`, stubs regenerated 39 → 38): 81 s (first, compiled clean), 47 s (popup focus), 46 s (the side panel guard), 47 s (auto-resize on the primary main frame). `scripts/roomcore-package.sh`: two full runs (host 7.9 s, app 13.7–13.9 s), six `--app-only` (app 13.9–14 s; one failed on a spike's `type(of:)` shadowing). Disk: 50 GB free on the internal drive; nothing deleted.

## 2026-10-05 — Phase 3.7a (Mac mini M4, `out/dev`, 6 jobs)

Series unchanged at 24 (no patch): `scripts/roomcore-apply.sh` "0 applied, 24 already" at every build. `//room` builds (`scripts/roomcore-build.sh`; `RoomToolbarButtonProvider` and the bubble anchor, the delegate member, then the leak-check default and the popup close on window move, then the `ui-passwords` probe): 63 s, 76 s, one failed compile (a `WeakPtr` assigned to `auto*`), 52 s. `scripts/roomcore-package.sh`: four full runs (framework staged ~6 s, host 6.7 s, app 13.7–17.9 s; one failed on a spike's `type(of:)` shadowing), three `--app-only` (13.7 s). Disk: 46 GB free on the internal drive; nothing deleted.

## 2026-10-05 — Phase 3.7b (Mac mini M4, `out/dev`, 6 jobs)

Series unchanged at 24 (no patch): `scripts/roomcore-apply.sh` "0 applied, 24 already" at every build and at the end. `//room` builds (`scripts/roomcore-build.sh`; navigation state, discard blockers, auto-discardable, the memory-pressure listener, `ShowTranslateBubble` real with the stubs regenerated 38 → 37, then the spike-only PM probes): one failed compile (a `base::span` from `NSData`: `base::apple::NSDataToSpan`), then **48 s** and **53 s**. `scripts/roomcore-package.sh`: two full runs (framework staged ~6 s, host 10–13 s, app 18–21 s), two `--app-only` (12 s). Swift package tests: Model 89, Store 35, Tabs 63, Engine 58 (`CI=1 swift test`, seconds each); `scripts/persistence-kill-test.sh 100 300` 71.5 s; `xcodebuild test -scheme Room` (window tier) ~6 min, 491 tests. Disk: 41 GB free on the internal drive (evidence `build/evidence-3.7b` 336 MB, mostly two copies of the 50k state); nothing deleted.

## Rebase 154.0.8037.58 → 154.0.8037.98 (Mac mini M4, 2026-10-05)

The first rebase, by hand with `scripts/roomcore-rebase.sh`'s pieces as they were written (Phase 3.8, session 3.8-1): Chrome's Stable refresh on the same milestone. Checkout `/Volumes/Chromium/chromium/src` (APFS sparse bundle on the USB SSD), `out/dev` (component, `room_enable_spikes`), 6 jobs, load 4–6 before the build.

| Step | Wall | Notes |
|---|---|---|
| Fetch `154.0.8037.98` | 1 s | the tag was already in the checkout (b859317bf11f); 380 upstream commits after .58 (an ancestor: the same release branch), 393 files, +6,933 −1,759 |
| `--dry-run` | 33 s | of which ~25 s are `git status` and the scratch-index replay on the disk image |
| Predict (patched files changed upstream) | 4–5 s | 2 of 32 patched files: `fedcm_account_selection_view_desktop.cc` +45 −24 (0008), `chooser_bubble_ui.cc` +71 −34 (0012); `browser_window.h` and `base_window.h` unchanged |
| Replay of the series in a scratch index | 8 s, then 11 s | first run: 10 patches through, stopped at 0012 (1 conflicting hunk); after the fix: 23 as written, 1 with offsets (0008, +21 lines), 0 merged |
| Hand fix of 0012 | ~1 min | read upstream's change (92300d69b6811), edited the merged file, header paragraph |
| Switch (`git reset --keep`, patch files refreshed, pin) | 4 s | `room` = `de850ddb28f14`; 0008 refreshed (hunk offsets, index lines), 0012 rewritten |
| `gclient sync -D --nohooks --revision src@b859317bf11f` | 35 s | DEPS rolls: V8, ANGLE, Dawn, WebRTC (git) and two CIPD packages; gclient printed nothing but one harmless git error from the gclient root; the four deps checked at their new revisions, `src` still on `room` |
| `gclient runhooks` | 33 s | toolchain unchanged |
| Stubs (`gen_browser_window_stubs.py --write`) | 0 s | 37 stubs, **no diff** |
| `roomcore-apply.sh` + `gn gen out/dev` | 51 s | "0 applied, 24 already"; gn gen 19.5 s (34,289 targets from 4,993 files); a second `roomcore-apply.sh` with the pin file: "0 applied, 24 already" (33 s) |
| **Up to the build** | **~5.5 min** wall from the first run (19:22:09) to the build's start (19:28:20), the conflict included; ~2 min 15 s of script steps after the fix | |

Conflicts:

| Patch | File | Hunk | Upstream change | Resolution |
|---|---|---|---|---|
| 0012 extension-chooser-toolbar-guard | `chrome/browser/ui/views/permissions/chooser_bubble_ui.cc` | `ShowDeviceChooserDialogForExtension`: the extensions-toolbar lookup (`BrowserView::GetBrowserViewForBrowser(browser)->toolbar_button_provider()->GetExtensionsContainerViews()`) | 92300d69b6811 "[M154] permissions: Harden the device chooser dialog against fullscreen drops (3/4)": a new `DropFullscreenForChooserDialog()` re-validates the browser and tab after the fullscreen drop and returns a `ChooserDialogHost`; the toolbar lookup moved after it and gained its own `if (!browser_view) return base::DoNothing();` | the hook moved with the call site: `ToolbarButtonProvider::From(host->browser)` (null-checked) replaces upstream's BrowserView lookup and its null check; the include hunks unchanged (context only). Patch header records it. With upstream's new null check a Room Browser is already rejected without 0012 (Room's provider returns no extensions container), so 0012 is a candidate to drop: the planner's call (B-61) |
| 0008 fedcm-anchor-hook | `fedcm_account_selection_view_desktop.cc` | both hunks | 228a7223a5246 "[M154] [FedCM] Guard against reentrancy UAF …" added 21 lines above the hooks | none needed (applied with offsets); the patch file refreshed so it is exact against .98 |

Stub diff: none (37 stubs, 58 real members). `browser_window.h` did not change between the two tags.

Build: started 2026-10-05 19:28:20 from bash with nohup (`ROOM_BUILD_JOBS=6 scripts/roomcore-build.sh`, pid 70841, log `build/roomcore-rebase-1-build.log`; siso began at 19:28:53, load 6.0). What it rebuilds (siso's `siso_explain`, ~6,300 dirty steps listed by 19:39): 3,681 steps below `v8/include/v8-version.h` (every V8 embedder: Blink's bindings, gin, extensions), 802 below `v8/src/objects/source-text-module.h`, 274 below V8's `flag-definitions.h`, 271 below `ui/views/view.h`, 226 below ANGLE's `Caps.h`, 125 below Dawn's `Toggles.h`, the rest small; `chrome/VERSION` regenerates the version headers and the framework moves to `Versions/154.0.8037.98`. A security refresh is not a small incremental here: its DEPS roll V8, so most of Blink's bindings recompile. Steps finished: 1,081 at 7.5 min, 1,217 at 11 min (V8's Torque objects first).

### Prediction for 155.0.8059.36 (3.8-2), from 154.0.8037.98

Measured without checking 155 out: `git fetch origin refs/tags/155.0.8059.36` took **74 s** (the pack grew 3.6 MB: the objects were mostly in the checkout already; .34 and .35 came along), then `scripts/roomcore-rebase.sh --dry-run 155.0.8059.36` beside the running build (it reads the object store only), saved in `build/roomcore-rebase/dry-run-155.0.8059.36.txt`. Upstream: 9,099 commits not in .98, 26,604 files changed; DEPS +262 −251; **clang rolls** (`llvmorg-24-init-3796` → `-7747`), so the 155 build is a clean build (4 h 15 min at 6 jobs in Phase 1.5) after a `gclient sync` that downloads the new toolchain and the rolled deps.

Patched files changed upstream (+/−): 0001 `chrome/BUILD.gn` +17 −5 and `content/public/app/BUILD.gn` +1 −0; 0002 `keychain_password_mac.mm` +25 −50; 0003 `browser_window_factory.cc` +2; 0004 `chrome/BUILD.gn` (as 0001); 0005 `read_anything_side_panel_controller.cc` +5 −39; 0006 `browser_process_impl.cc` +5 −5; 0007 `chrome_browser_interface_binders.cc` +1 −11, `media_factory.cc` +1 −3 (`cdm_registry_impl.cc` unchanged); 0008 `fedcm_account_selection_view_desktop.cc` +7 −2; 0011 `browser_view.cc` +83 −75 (`address_bubbles_controller.cc` unchanged); 0013 `app_controller_mac.mm` +4 −1; 0014 `browser_navigator.cc` +35 −11; 0015 and 0022 `browser_web_contents_delegate.cc` +12 −6; 0016 and 0021 `chrome_content_browser_client_navigation_throttles.cc` +9 −1; 0017 `permission_prompt_factory.cc` +13 −7; 0019 `chrome_download_manager_delegate.cc` +64 −20; 0023 `external_protocol_dialog.cc` +1; 0024 `extension_install_dialog_view.cc` +5 −3; 0025 `chrome_extensions_browser_client.cc` +21 −6. Unchanged: 0009, 0012, 0018, 0020's files. 21 of the 32 patched files changed; `chrome/browser/ui/views/frame/` changed in 67 files (+2,869 −592, 3 added, none removed), but the one hook there (0003) only gained context.

The replay (dry run; a conflicting patch is left out and the replay goes on): **1 conflict**, 0001 in `content/public/app/BUILD.gn` (upstream added a blank line right where 0001 adds its `room_framework_name` import: context only); 5 apply as written, 17 with offsets (refreshed by the run), 1 merges cleanly three ways (0014).

Compile-level predictions (not visible to the replay): `browser_window.h` +8 −13: a new pure virtual `GetAcceleratorProvider()` (a new stub, 37 → 38), `ConfirmBrowserCloseWithPendingDownloads` takes `DownloadCloseType` (new `chrome/browser/ui/download_close_type.h`) instead of `UnloadController::DownloadCloseType`: it is a **real** member (`room_browser_window.h`/`.mm`), a hand fix; ten includes left the header (`browser.h`, `browser_close_manager.h`, `chrome_signin_helper.h`, `bookmark_bar.h`, `unload_controller.h`, `exclusive_access_bubble_type.h`, `page_action_icon_type.h`, `partial_translate_bubble_model.h`, `tab_search.mojom.h`, `window_feature_controller.h`), so `//room` files that reached them through `browser_window.h` need their own includes. `//room` includes 382 Chromium headers: none is gone in 155, 57 changed. The 3.7b APIs to watch (`serialized_navigation_entry.h`, `cannot_discard_reason.h`, `discard_eligibility_policy.h`, `memory_pressure_listener.h`, `translate_bubble_controller.h`) are unchanged; the six `*ForTesting` seams exist in 155 in as many files as in 154.

### Rebase 154.0.8037.58 → 154.0.8037.98: verify (eve, 2026-10-05)

- build: 1940 s (/Users/eve/Code/room/build/roomcore-rebase-1-build-2.log)
- package: 25 s
- baseline: 32 s (/Users/eve/Code/room/build/baseline/rebase-154.0.8037.98-223920)
  - BASELINE FAILED:     raise RuntimeError(f'ten-page fixture incomplete: {result}')
  - nav: {"nav_exit": 0, "nav_seconds": 16.19, "nav_assertions": "passed"}
  - quits: 
- tour: 841 s (/Users/eve/Code/room/build/grand-tour/20261005-223952-roomcore)
  - Totals: light 293 passed, 5 failed.

What the record above does not say (3.8-2, written by hand):

- **The build, two segments.** Segment 1: siso 19:28:53 → ~21:45:24 (the log's last write), **2 h 16 min 31 s**, 9,468 steps, cut off by a power outage (pid 70841, `build/roomcore-rebase-1-build.log`). Segment 2: restarted by the planner from bash with nohup, siso 21:56:46 → 22:29:06, **1940 s (32 min 20 s)**, "The build has finished successfully" (`build/roomcore-rebase-1-build-2.log`; siso resumed from its deps log, so the steps lost when the power went were redone here). Compile wall **2 h 48 min 51 s** over both segments, the outage's lost work included, the 11 min dark gap excluded. A clean, uninterrupted number for this rebase is unknown. The `--verify` state files pointed at the first log and the dead pid: `build-log-path` was edited to the second log and `build-pid` emptied by hand (the script has no option for a log path); the "build: 1940 s" line is segment 2 only.
- **`--verify` attempts.** Five runs, the fifth complete: (1) 22:32 baseline failed (below) while the rebase-2 replay ran beside it; (2) 22:34 exited at once: rebase 2 had already written `build/roomcore-rebase/current` = 155.0.8059.36, and `--verify` read the current rebase's state (no build log there; an empty log also tripped `set -e`): `--verify <tag>` added, the empty-log case fixed; (3) 22:35 and (4) 22:37 baseline failed again, and `--verify` stopped there without the tour: a failed baseline is now recorded (`BASELINE FAILED`) and the tour still runs; (5) 22:38:55 → 22:53:53, the record above.
- **Baseline.** nav passed (16.2 s; also 16.1–17.1 s in attempts 1–4). The three ten-page quits did not run: the external corpus's ready check failed four times out of four on `https://stackoverflow.com/questions` still loading 3 s after every page had stopped (`loading=true`, title "Newest Questions - Stack Overflow"; the host log shows Cloudflare's Turnstile challenge script `challenges.cloudflare.com/.../turnstile/...`; Reddit answered with its own `js_challenge` redirect and loaded). A site behind a bot challenge, not the tag: the same build's tour `quittiming` (the tour's own corpus) quit three times, **0.60 / 0.69 / 0.63 s** (load 9.0 / 13.8 / 16.0), 0 helpers left, 0 crash reports. No new crash report in `~/Library/Logs/DiagnosticReports` over the session (the newest is 17:37). Stub hits over the tour: one `CreateSadTab` (the crash step, as in 3.3b).
- **Tour** (`build/grand-tour/20261005-223952-roomcore`, light, 14.0 min, load 7–16): layout **154 / 1**, sidebar **25 / 0** (layout + sidebar 179 / 1; 3.3a: 165 / 15 with the activation failures), tabs **37 / 3** (3.7b: 38 / 2), chrome **77 / 1** (3.4b: 73 / 5). Every failure attributed: layout `popups` "alert as a sheet, completed": the sheet appears and is answered, the check then reads `popups.html`'s `window.__alerted` from the isolated world (B-55's page-global read; 3.4b moved the chrome spikes to the `#log` mirror, not this check; the layout section had not run on RoomCore since 3.3a); tabs: Discard Background Pages' renderers 15 → 16 (B-56), switching median **16.31 ms** and p95 **24.50 ms** (B-53; 3.7b: 15.29 / 23.79; the median now misses 16 ms by 2 %, under load 7–16); chrome26b: the helper crash-report count is 0 for the killed renderer (the CEF-shaped count: Crashpad writes under the data root). No failure is new with the tag.

**Rebase 1's full cost** (154.0.8037.58 → 154.0.8037.98, a same-milestone security refresh): hand time **~5.5 min** (19:22:09 → 19:28:20, the conflict's ~1 min fix included); sync **35 s** + runhooks **33 s** (inside the 5.5 min); build **2 h 16 min 31 s + 32 min 20 s** (two segments around a power outage; the clean number unknown; a near-clean rebuild: the DEPS roll V8, ANGLE, Dawn, WebRTC); verify **15.0 min** (package 25 s, baseline 32 s, tour 841 s; the four failed attempts another ~6 min); conflicts **1** (0012, hook moved with its call site) + **1** offsets refresh (0008); API fixes in `//room` **0**; stub diff **none** (37 stubs). Wall from the first run to the verified build: 3 h 32 min including the 11 min outage gap.

## Rebase 154.0.8037.98 → 155.0.8059.36 (Mac mini M4, 2026-10-05)

The second rebase, by `scripts/roomcore-rebase.sh` (Phase 3.8, session 3.8-2): the next milestone. Checkout `/Volumes/Chromium/chromium/src` (APFS sparse bundle on the USB SSD), `out/dev`, 6 jobs. Run as `--no-build` so the `//room` hand fixes could land before the compile (as in rebase 1); the build then started with the planner's command. Rebase 1's `--verify` ran between the first stop and `--continue` (22:34–22:54), so the wall below is not the cost.

| Step | Wall | Notes |
|---|---|---|
| `--dry-run` | 33 s | identical to the saved one (`build/roomcore-rebase/dry-run-155.0.8059.36.txt`, diffed: no change): 1 conflict (0001), 5 as written, 17 offsets, 1 merged |
| Run 1: fetch, predict, replay | 45 s (22:33:09 → 22:33:54) | tag present; predict 17 s (21 of 32 patched files changed upstream; `browser_window.h` +8 −13); replay 2 s, stopped at 0001, exit 2 |
| Hand fix of 0001 | ~1.5 min (file written 22:35:26) | `content/public/app/BUILD.gn`: the import kept with the other imports, upstream's blank line after it |
| `--continue --no-build` | 5 min 15 s (23:03:10 → 23:08:25) | 0001 rewritten from the resolved files, replay 11 s (6 as written, 17 offsets, 1 merged: 0014), switch 20 s, sync **122 s**, runhooks **59 s**, stubs 1 s, apply + gn gen 53 s |
| `gclient sync -D --nohooks --revision src@7d556ce232b8` | 122 s | the gclient root's harmless "not a git repository" line again; `src` stayed on `room` |
| `gclient runhooks` | 59 s | **clang rolled**: `third_party/llvm-build/Release+Asserts/cr_build_revision` = `llvmorg-24-init-7747-g62397f8b-27` (154: `-3796`); dsymutil re-downloaded |
| Stubs | 1 s | **38** stubs (37 → 38): `GetAcceleratorProvider()` returning nullptr (`build/roomcore-rebase/155.0.8059.36/stubs.diff`: one declaration in `room_browser_window.h`, one stub in `room_browser_window_stubs.cc`) |
| `roomcore-apply.sh` + `gn gen out/dev` | 53 s | "0 applied, 24 already", pin `155.0.8059.36`; 35,999 targets from 5,005 files; a second `roomcore-apply.sh` after the fixes: "0 applied, 24 already" |
| `//room` API fixes, syntax-only pass, `gn check` | ~11 min by hand (the `DownloadCloseType` fix ~3 min before `--continue`; 23:08:25 → 23:15:14 after it) | below |
| **Rebase 2 by hand and script, to the build** | **~18 min active** (script 6 min, hand ~12 min); 42 min wall 22:33:09 → 23:15:14 with rebase 1's verify inside | |

Result: `git describe --tags` = `155.0.8059.36-24-g1d9f6efbb0463`; `refs/heads/room` = the tag (`7d556ce232b82`) + the 24 patch commits (0001 `efc7b01c34336` … 0025 `1d9f6efbb0463`).

Conflicts and fixes:

| Patch | File | Hunk | Upstream change | Fix |
|---|---|---|---|---|
| 0001 framework-name-roomcore | `content/public/app/BUILD.gn` | the `room_framework_name` import in `if (is_mac)` | a blank line added after `import("//chrome/version.gni")`, where 0001 adds its import | context only: the import stays after `version.gni`, the blank line after it; the patch file rewritten by `--continue` (no header change) |
| 0014 navigator-browser-for-disposition-hook | `chrome/browser/ui/navigator/browser_navigator.cc` | the hook at the top of `GetBrowserAndTabForDisposition` | a `should_trigger_session_restore` local added before the `switch` | merged three ways by the script: the hook sits after the new local, before the `switch` (checked in the checkout); refreshed |
| 0002, 0003, 0004, 0005, 0007, 0008, 0011, 0013, 0015, 0016, 0017, 0019, 0021, 0022, 0023, 0024, 0025 | (each patch's files) | all | context moved | none: applied with offsets, patch files refreshed (0011's refresh also reorders its two files by path; content unchanged). 0003's hook in `browser_window_factory.cc` (+2 upstream; `views/frame/` changed in 67 files) only moved |
| 0001 (after the fix), 0006, 0009, 0012, 0018, 0020 | | | | applied as written |

API changes fixed in `//room` (the smallest change each; none widens a patch):

| File | Symbol | Upstream | Fix |
|---|---|---|---|
| `room/browser/room_browser_window.h`, `.mm` | `ConfirmBrowserCloseWithPendingDownloads(int, DownloadCloseType, …)` (a real member) | `browser_window.h` takes `::DownloadCloseType` from the new `chrome/browser/ui/download_close_type.h` and no longer includes `unload_controller.h` (where `UnloadController::DownloadCloseType` is now an alias) | the override names `DownloadCloseType` |
| `room/core/room_browser.mm` (spike probe `download-close-decision`) | `UnloadController::DownloadCloseType::kBrowserShutdown` | as above | `DownloadCloseType::kBrowserShutdown` |
| `room/browser/room_exclusive_access_context.cc` | `BrowserWindowFeatures::exclusive_access_manager()` | removed (a35bf7d305056 "Remove the unused exclusive_access_manager() getter from BWF") | `ExclusiveAccessManager::From(browser)` |
| `room/browser/BUILD.gn` | include of `chrome/browser/ui/views/autofill/autofill_bubble_handler_impl.h` (`gn check`) | the header moved into its own target `//chrome/browser/ui/views/autofill:autofill_bubble_handler_impl`, private to `//chrome/browser/ui` | dep added |
| `room/core/BUILD.gn` | include of `chrome/browser/ui/views/extensions/extension_popup.h` (`gn check`) | the header moved into `//chrome/browser/ui/views/extensions:extension_popup`, private to `//chrome/browser/ui` | dep added |

`gn check out/dev //room/*`: 2 errors (the two includes above), then "Header dependency check OK". The ten includes that left `browser_window.h` raised no error in `//room` in the syntax-only pass (below): no `//room` file names a type it only had from them, as far as that pass could see.

Syntax-only pass before the build (`gn gen --add-export-compile-commands=//room/*`, then each of the 27 `//room` translation units with `clang++ -fsyntax-only -ferror-limit=0` and the build's flags, 6 at a time, 19 s): the flags resolve, but `out/dev`'s generated headers are 154's (mojom bindings, protobuf gencode) and the clang modules (`obj/build/modules/system/module.pcm`) were built by 154's clang. With the module flags removed: 8 files clean (`room_browser_window_stubs.cc` with the new stub, `room_find_bar.cc`, `room_application.mm`, `room_core_version.mm`, `room_cr_application.mm`, `room_history.mm`, `room_profile.mm`, `worker_shutdown_probe.cc`), 19 with errors, every one led by stale generated headers (`mojo::MessageReceiverWithStatus` gone from 155's bindings, "Protobuf C++ gencode is built with an incompatible version"). Errors located in `//room` files: `exclusive_access_manager()` (real, fixed above), `room_page_state.mm`'s `PageServices` and `room_cdm_browser.cc`'s `DocumentService` (cascades: their bases `media_session::mojom::MediaSessionObserver` and `room_cdm.mojom` come from the stale headers). What waits for the build: every `//room` file that includes a regenerated mojom or proto header (19 of 27).

Build: started **2026-10-05 23:15:14** from bash with nohup (`ROOM_BUILD_JOBS=6 scripts/roomcore-build.sh`, pid **54823**, log `build/roomcore-rebase-2-build.log`; siso began 23:15:51, load 4.0). A clean build after the clang roll (Phase 1.5's clean `out/dev`: 4 h 15 min at 6 jobs).

The build's first half hour (`out/dev/siso_metrics.json` lines; 0 failed steps throughout): 899 at 23:16:59, 9,118 at 23:28:12, 10,283 at 23:30:56, 13,685 at 23:37:57, 16,669 at 23:40:36, **19,036 at 23:45:39** (30 min after siso began), 19,485 at 23:46:39; load 14–24 (siso's generators and compiles, the syntax-only pass's three clangs for 51 s). The generator steps come first, so the rate falls from here: Phase 1.5's clean build had 63,686 steps in 4 h 15 min. Expected end **~03:30** (03:00–04:00).

Syntax-only pass again at 23:47 against the half-regenerated `gen/` (with the fixes in): **19 of 27 `//room` files clean** (all of `room/browser/` but `room_browser_window.mm`; in `room/core/`: `room_app_controller`, `room_application`, `room_context_menu`, `room_core_version`, `room_cr_application`, `room_downloads`, `room_extensions`, `room_history`, `room_network_policy`, `room_page_dialogs`, `room_page_prompts`, `room_permissions`, `room_profile`, `room_web_contents_tools`; the diagnostics probe). The 8 that wait for the build (each still includes a 154 generated header: `autofill_driver.mojom.h`, `message_port.mojom.h`, `translate.mojom.h`, `print.mojom.h`, `room_cdm.mojom.h`, `url_restriction.pb.h`): `room_browser_window.mm`, `room_autocomplete.mm`, `room_browser.mm`, `room_cdm_browser.cc`, `room_cdm_renderer.cc`, `room_extension_popups.mm`, `room_page_state.mm`, `room_web_contents.mm`. Their only errors located in `//room` are `room_cdm_browser.cc`'s `DocumentService` cascade from the stale `room_cdm.mojom.h`; everything else is in the stale headers or cascades from them.
