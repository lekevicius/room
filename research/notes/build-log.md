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
baseline-shutdown-worker-start. Concurrent B-16 remains a separate open gate.


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
