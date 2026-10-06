# Room — development plan

A macOS-only browser: Chromium engine, browser chrome written in Swift/AppKit, Arc/Zen feature set, Dia-level visual polish. This document turns the research in `research/notes/` into decisions and a phased plan. Date: 2026-10-01.

Read order if you only have ten minutes: §1 (decision), §2 (architecture), §5 (phases), §7 (risks).

---

## 1. The decision: build our own "ADK"

### 1.1 What the research established

1. **Arc and Dia are a Swift/AppKit app linking a Chromium fork packaged as a framework with an Objective-C API.** `Dia.app` ships `ArcCore.framework` (Chromium 154) with 204 public ObjC headers: `ArcBrowserApplication` (browser process), `ArcBrowserContext` (Profile), `ArcBrowser` (Chrome's `Browser` bound to an `NSWindow`), `ArcWebContents` (tab with a native `NSView`), and delegates for every piece of Chrome UI (context menus, permissions, JS dialogs, password/autofill save prompts, extension popups, translate, downloads, DevTools…). The Swift side owns all windows and views. Josh Miller's "ADK" is exactly this. Details: `research/notes/arccore-adk-bundle-analysis.md`, `research/notes/arc-dia-architecture.md`.
2. **CEF cannot give us Chrome's features inside our own window on macOS.** A CEF browser hosted in an `NSView` is forced to "Alloy style" (enforced in `browser_host_create.cc`, open issue #3294 since 2022). Alloy keeps the engine (rendering, DevTools, PDF, spellcheck, downloads, find, profiles, extension content scripts) but loses everything anchored to a Chrome `Browser`: extension action popups and toolbar, Chrome Web Store installs, `chrome://extensions`, password/autofill save bubbles, Translate, print preview by default, tab discarding, and the omnibox `AutocompleteController`. Details: `research/notes/cef.md`.
3. **A Chromium fork with a native window is feasible for a small team only with a tiny patch surface.** Web content hosting in AppKit is the easy part (`WebContents::GetNativeView()` is an `NSView`; Opera 2013, Arc/Dia, Phi all do it). The hard part is implementing `BrowserWindow` (74 pure virtuals + 24 from `ui::BaseWindow`) and the long tail of Views-anchored bubbles. Cost: 1.3–2 h clean component build on this M1 Max, 3–6 h for an official/LTO build; Chrome now ships a milestone every two weeks (since M153, Sept 2026) with weekly security refreshes. Details: `research/notes/chromium-fork.md`.
4. **UI stack: AppKit shell, SwiftUI only in leaves.** The Browser Company publicly reversed SwiftUI on Mac for performance; Dia's binary confirms AppKit outline/collection views with SwiftUI leftovers. GRDB for persistence, Sparkle 2 for updates, Developer ID + hardened runtime, no App Sandbox (a sandboxed app cannot set itself as default browser, and Chromium helpers cannot launch under it). Details: `research/notes/macos-ui-stack.md`.
5. **The product spec is precise.** Zen's source and Arc's help center give exact behaviors for pinned/essential/today entries, spaces, the palette, split view, hover reveal, toasts and a full shortcut table. Details: `research/notes/feature-spec.md`.

### 1.2 Decision

**Destination: a Chromium fork compiled into `RoomCore.framework` that exports an Objective-C API modeled on ArcCore's surface, consumed by a Swift/AppKit app (`Room.app`).** This is the only route that keeps extensions (with popups and Web Store installs), password manager, autofill, Chrome's omnibox ranking, session service, tab discarding, PDF, print preview, Translate and DevTools while putting 100% of the chrome in native code.

**Scaffold: start the Swift app on CEF behind an `Engine` protocol, and retire CEF once RoomCore reaches parity.** Reasons:

- The UI is what you care most about, and CEF needs no Chromium build: a page renders inside a Swift window in days, so sidebar/spaces/palette/split/design work starts in week 1 and can be dogfooded by week 6.
- The `Engine` protocol is designed from the ArcCore headers, so the CEF bridge and the RoomCore bridge implement the same Swift-facing API. The throwaway is only the CEF bridge itself (~2 weeks), not UI code.
- RoomCore's long pole (build infrastructure, `BrowserWindow` implementation, delegate plumbing) runs in parallel and does not block UI iteration. If RoomCore slips, we still have a working, if feature-capped, browser.
- Hard gate at the end of Phase 2: when RoomCore shows a `Browser`-backed tab in the Swift shell with an extension popup working, CEF is deleted. We do not maintain two engines.

The alternative, fork-only from day one, saves ~2 weeks of bridge work but means 4–6 weeks before the first pixel of UI can be judged against real web content. I recommend against it, but it is a legitimate choice if you would rather not touch CEF at all.

### 1.3 Non-goals for v1

AI features, Boosts, Easels/Notes, sync/accounts, Windows, mobile, Mac App Store, Little Arc windows, themes marketplace. (Full list: feature spec §J.)

---

## 2. Architecture

### 2.1 Process and bundle layout

```
Room.app/Contents/
  MacOS/Room                             Swift/AppKit app = Chromium browser process
  Frameworks/RoomCore.framework/         Chromium fork (Phase 2+); until then
                                         "Chromium Embedded Framework.framework"
    Versions/A/RoomCore                  the Chromium dylib
    Versions/A/Headers/room/*.h          public ObjC API (umbrella RoomCore.h)
    Versions/A/Modules/module.modulemap  → `import RoomCore` from Swift
    Versions/A/Helpers/Room Helper*.app  Renderer / GPU / Plugin / Alerts helpers
    Versions/A/Resources/*.pak, *.lproj, DevTools
  Frameworks/Sparkle.framework, GRDB, Sentry
```

The app's `NSApplication` subclass implements Chromium's `CrAppProtocol` (`isHandlingSendEvent`), and `main` hands the run loop to the engine (`RoomApplication.run`), exactly as ArcCore and CEF require. All engine callbacks arrive on the main thread; every engine ObjC class is `NS_SWIFT_UI_ACTOR`.

### 2.2 Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Room.app (Swift, AppKit shell, SwiftUI leaves)               │
│  App · UIKitCore (window, materials, key router, menus)      │
│  Sidebar · Card · Palette · Chrome (toasts, popovers, dialogs)│
│  Store (@Observable state, session) · Model (GRDB) · Omnibox │
├──────────────────────────────────────────────────────────────┤
│ Engine (Swift protocol: Application, Profile, Browser,       │
│         WebContents, delegates — shaped like ArcCore)        │
├───────────────────────────┬──────────────────────────────────┤
│ EngineCEF (ObjC++ bridge, │ EngineRoomCore (Swift wrapper    │
│ Phase 1 only)             │ over RoomCore.framework ObjC API)│
├───────────────────────────┴──────────────────────────────────┤
│ CEF binary distribution    │ RoomCore.framework              │
│ (Spotify CDN, no build)    │ = Chromium fork + //room/ ObjC++│
└──────────────────────────────────────────────────────────────┘
```

Dependency rule: UI → Store → Model; UI → Engine (protocol only); nothing but `App` depends on a concrete engine.

### 2.3 The Engine API (what RoomCore must export)

Modeled on ArcCore's headers (`research/repos/arccore-headers/`, study only; we write our own). Minimum surface, in the order we need it:

| Object | Wraps | Phase 1 (CEF) | Phase 2+ (RoomCore) |
|---|---|---|---|
| `RoomApplication` | browser process, main loop, feature flags, profile registry | CefInitialize/CefRunMessageLoop | BrowserMainParts; `run`, `tryToTerminate`, create/load/delete profiles |
| `RoomProfile` | `Profile` | `CefRequestContext` per space-container | prefs, history service, downloads, extensions, bookmarks model, favicon service, cookies, content settings, autocomplete controller factory |
| `RoomBrowser` | Chrome `Browser` bound to an `NSWindow` | not available (CEF has none) | tab strip model owner; extension actions/popups; `autocomplete:`; session restore |
| `RoomWebContents` | `WebContents` + tab helpers | `CefBrowser` in `SetAsChild` NSView | `nativeView`, navigation controller, back/forward list, find, zoom, print, capture, discard/freeze, DevTools (+CDP), PDF, media session, observable title/url/favicon/loading/themeColor/audible/state |
| `UIDelegate` | everything Chrome would draw | JS dialogs, popups, permissions, context menu, downloads, auth, cert errors, fullscreen, file chooser | plus password/address/card save prompts, extension install consent, translate, hung renderer, WebUI dialogs, infobars, status text, consumed keys |
| `NavigationDelegate` | policy per navigation | `OnBeforeBrowse` | `decidePolicyForNavigationAction` (space routing, Peek) |

Rule for the ObjC boundary: only Foundation/AppKit types and C structs cross it. Never `std::` or `base::` types (Chromium's libc++ uses ABI namespace `__Cr`, incompatible with Xcode's).

### 2.4 Window and view structure (Dia look)

- `NSWindow` with `.fullSizeContentView`, transparent titlebar, hidden title, tabbing disallowed, `isMovableByWindowBackground` only on the sidebar.
- Content view: `NSVisualEffectView` (behind-window, `.sidebar` material) + a low-alpha gradient layer for the space tint.
- Left: sidebar (AppKit `NSOutlineView`, view-based rows; drag/drop, inline rename, context menus). Address field is an `NSTextField` subclass in the sidebar header.
- Right: the **card**: a layer-backed `NSView` with `cornerRadius 10` (continuous), inset 6pt top/right/bottom (both measured from Dia in Phase 1.3; first guess was 12/8), `masksToBounds`, 1px hairline border, shadow on a sibling layer; the engine's `NSView` is its subview. Container background = page `rootBackgroundColor` so live resize never shows the material.
- Overlays (in-window views above the card): palette, hover-revealed sidebar, Peek, toasts, MRU switcher. `NSGlassEffectView` for these on macOS 26+.
- Traffic lights stay where AppKit puts them; the sidebar header lays out around their actual frames (Tahoe moved them; never hard-code). The window carries an empty `.unified` `NSToolbar`: that alone makes AppKit place the buttons where Dia has them (19,19 instead of 9,9 in a bare titlebar), without touching their frames (Phase 1.3).
- Keyboard: engine sees keys first (reserved set excluded), unhandled keys go once to `NSApp.mainMenu.performKeyEquivalent`.

### 2.5 Data

GRDB (SQLite, WAL) for *our* model: spaces, entries (essential/pinned/folder/today/split group), per-entry stored URL/title/favicon/custom icon, windows, archive, favicon cache, routing rules, settings. Debounced single-transaction writes with a generation counter, JSON snapshot backup, rolling backups. Browsing history, cookies, passwords, extensions live in the engine's profile (Chromium's own stores), not in ours.

### 2.6 Repository layout

```
room/
  PLAN.md, README.md, .gitignore
  project.yml                    XcodeGen → Room.xcodeproj (never hand-edited)
  App/                           AppDelegate, main.swift, menus, composition root
  Packages/                      local SwiftPM packages (Engine, EngineRoomCore, Model, Store,
                                 Omnibox, UIKitCore, Sidebar, Card, Palette, Chrome,
                                 Settings, Infra)
  Engine/roomcore/               fork: //room GN targets, patches/, chromium_src/, gn args,
                                 build + sign + package scripts (Chromium checkout lives
                                 outside the repo, e.g. ~/chromium/src, with //room symlinked)
  Design/                        design tokens, reference screenshots, specs
  research/                      notes/ (reports), screenshots/, repos/ (gitignored clones)
  scripts/                       bootstrap, sign, notarize, appcast
```

---

## 3. Product scope for v1 (summary of the spec)

The authoritative spec is `research/notes/feature-spec.md`. Headline behaviors:

- **Sidebar as one tree**: Essentials grid (≤12, per profile) → space title → Pinned (folders allowed) → separator with "Clear" → Today tabs → footer. A permanent entry stores a URL and is navigated in place; "changed" dot + hover reset; ⌘W on a permanent entry = unload + reset + switch, never remove.
- **Spaces**: per-space pinned/today lists, color theme tinting the window, emoji/symbol icon, optional separate profile (cookie jar); dots/icons in the footer; ⌃1–9, ⌘⌥←/→, two-finger swipe; routing rules for external links.
- **Palette**: ⌘T (new) and ⌘L (edit current) open the same centered overlay; no new-tab page; groups: top hit, open tabs, pinned/essentials, history, search, commands; site-search keywords; inline URL completion.
- **Split view**: ≤4 panes, one group row in the sidebar, drag-to-split, ⌘⌥G/V/H/U, focus follows click.
- **Sidebar hide/reveal**: ⌘S; 4px left-edge hover band with 150ms dwell reveals a floating overlay; ⌘⌥S pins it.
- **Footer**: downloads button (progress ring, fly-in animation) · space icons · "+" menu. Toasts rise from the sidebar bottom (Copy URL ⌘⇧C, Markdown ⌘⇧⌥C, Tabs closed · Undo, etc.).
- **Lifecycle**: unloaded-on-launch except the selected tab; auto-archive Today tabs after 12h (configurable); discard on idle/memory pressure; Archive view; crash-safe session restore.
- **Peek**: off-site links from permanent entries open in an overlay card; ⌘O expands.
- Full shortcut table: spec §G.

---

## 4. Engineering decisions (settled)

| Topic | Decision | Why |
|---|---|---|
| Engine | Chromium fork → `RoomCore.framework` (ObjC API); CEF only as Phase 1 scaffold. **Confirmed in Phase 1.6:** the RoomCore embryo (5 patches + `//room`) renders and quits cleanly from the Swift host; Chapter 3 continues from it (`research/notes/chapter-1-review.md`) | §1 |
| Fork base | Vanilla Chromium release tags via depot_tools; borrow ungoogled-chromium-macos toolchain/signing scripts (BSD) as reference; no Helium code (GPL-3) | git history makes rebases `git rebase`-able; keep licensing clean |
| Patch strategy | Brave-style: all our code in `//room/`; `chromium_src/` shadow headers where needed; raw patches only for factory redirects (`browser_window_factory.cc` → `RoomBrowserWindow`) and tiny hooks | smallest rebase surface |
| What we replace vs keep | Replace: window, tab strip, sidebar, omnibox view, find bar, status bubble, infobars, permission prompt, downloads UI, extensions container, JS dialogs. Keep Views initially for: autofill popup, print preview, web-modal dialogs, DevTools docking, PDF; anchor Views bubbles by rect; move them native one by one later | the `ShowXxxBubble` long tail is where projects stall |
| Build config | Dev: `is_component_build=true symbol_level=0 blink_symbol_level=0 is_debug=false`; Release: static, `is_official_build=true`, ThinLTO, `proprietary_codecs=true ffmpeg_branding="Chrome" enable_widevine=true enable_updater=false`. **Amended in Phase 1.1:** `safe_browsing_mode=0` fails `gn gen` on M154 (Chrome targets depend on Safe Browsing); keep the default (1), compiled in but inert without an API key; revisit with `//room` patches only if the binary-size or privacy cost matters | Measured in Phase 1.1: first clean dev build 4 h 24 min on the M1 Max (partly at reduced priority; see `build-log.md`), incremental 27–39 s. **Amended in Phase 1.5:** on the 24 GB M4 Mac mini the clean branded build took 4 h 15 min with 6 local jobs (`ROOM_BUILD_JOBS=6`); at the default 10 jobs Blink compiles swap and throughput drops ~10×, so machines under ~32 GB build with fewer jobs; `//room`-only rebuilds 45–63 s. Release builds nightly on a Mac mini or Depot runner. **Amended in 3.1b-2 (2026-10-05):** the official build (`args/release.gn`: `is_official_build`, ThinLTO implied, `chrome_pgo_phase=0`, `symbol_level=1`, dSYMs) links on the 24 GB Mac mini: clean 4 h 43 min at 6 jobs, the framework link 18 min at 6.80 GiB; Room.app 382 MB, DMG 176 MiB. The laptop is not required for releases. **Amended 2026-10-06 (Chapter 4 spec):** app-side work builds over the staged release framework in minutes on either Mac (`docs/laptop-build.md` §A), and a product DMG costs minutes while `//room` is unchanged (`roomcore-package.sh --release`, `roomcore-sign.sh`, `sparkle-package.sh`); 4.1b measures the incremental official build after a `//room` change, which decides whether `//room` changes reach the DMG per phase or only at 4.9. **Measured 2026-10-06 (4.1b):** 8 min 5 s wall (404 s of build: 13 `//room/core` objects and the ThinLTO link at 353 s, 8.58 GiB), plus 79 s to package, 82 s to sign and notarize, 9 s for the DMG; so in Chapters 4 and 5 a DMG follows every engine step as well as every phase |
| Chromium cadence | Track Stable (2-week milestones) with an automated rebase script; fall back to Extended Stable (8 weeks) + weekly security backports if rebases cost >1 day each. **Decided 2026-10-06 (3.8):** Stable. The two measured rebases cost ~5.5 min (154.0.8037.58 → .98: 1 conflict, 0 API fixes) and ~18 min of active work (.98 → 155.0.8059.36: 1 context conflict, 17 offset refreshes, 5 `//room` API fixes, 1 new stub) plus the build (near-clean 2 h 49 min with an outage; clean ~4 h 15 min at 6 jobs): the build dominates, the 24 hooks did not churn (2 conflicts in 48 replays), so the fallback's trigger is nowhere near. Confirmed when 3.9's tour is green on 155; revisited if a milestone ever costs a day of hand work. Confirmed 2026-10-06 on the tour below: 3.9-2's full grand tour on 155.0.8059.36, light 505 / 6 and dark 505 / 6 of 511, every failure a row (B-53, B-56) or the dev build's DCHECK condition (B-76); rebase 2 cost ~18 min of hand work, a 4 h 34 min clean build and a 17 min verify (`build-log.md` "Rebase 2's full cost"). **Amended 2026-10-06 (Chapter 4 spec; the user's decision):** during Chapters 4 and 5 there is no scheduled rebase: those chapters are app work, a milestone costs two nights of machine time (the dev build, then the official build), and a Stable two weeks old is acceptable for a while; a rebase happens only when the user asks for one (a security release) or a phase cannot proceed without it, as a night with no session attached. Per-milestone rebases resume in 6.4 | security first; one person; measured in `build-log.md` "Rebase …" |
| Google services | **Confirmed 2026-10-06 (the user):** no translate key (B-63), no password generation without Sync (B-72), Enhanced Spell Check hidden (B-74), extensions' own requests are theirs (B-68); nothing special-cased for any vendor (B-69: no native messaging hosts registered; 1Password and the rest work as ordinary extensions). Original: Own API keys for geolocation only; Safe Browsing off (non-commercial-only API; personal use OK later); Translate via Chromium's translate element (works in unbranded builds, not guaranteed); Chrome Web Store installs (works in unbranded builds, as in Brave/Vivaldi); no Chrome Sync (not available to third parties since 2021) | legal matrix in fork report §6 |
| Widevine | Build with `enable_widevine=true`; CDM fetched by Chromium's component updater; verify empirically; document manual CDM copy from Chrome as fallback | license is free but gated |
| UI framework | AppKit for window, sidebar, card, address field, menus, key routing, palette rows; SwiftUI (`NSHostingView`) for settings, onboarding, toasts, downloads rows, forms | TBC's experience; drag/drop/multi-select maturity. Palette rows moved to AppKit 2026-10-03 (2.6): SwiftUI laid out eight new rows in ~12 ms on a query's first keystroke, over a frame; the user: no need for full SwiftUI, Arc moved away from it too. **Amended in 2.6a:** the rows were not the main cost (AppKit rows alone: 22.2 → 22.0 ms); the first key after idle runs on an efficiency core, and the query plus AppKit's display pass at E-core speed is most of it (`spike-results.md` 2.6a). The decision stands: AppKit rows made later keys cheaper and the first key 7.5 ms on a performance core |
| State | `@Observable` stores on `MainActor`; custom MVVM, no state-diffing on hot paths (tab list) | TBC's Dia lesson |
| Persistence | GRDB + FTS5; JSON snapshot backup | Dia ships GRDB; SwiftData still has threading problems in 2026 |
| Testing | unit tier in CI; window tests local only; screenshots for eyes, not assertions (CLAUDE.md "Testing", 2026-10-03) | three of four red CI runs were runner display size or contrast, none a bug; implementer sessions lost time driving the UI through computer-use |
| Concurrency | Swift 6, UI packages compiled with MainActor default isolation; engine callbacks wrapped in `MainActor.assumeIsolated` | CEF/Chromium UI thread is the main thread |
| Distribution | Developer ID, hardened runtime, notarytool, DMG, Sparkle 2 (EdDSA, full-app updates, deltas measured later), Sentry + Crashpad | no App Sandbox possible |
| Entitlements | Main app: camera, audio-input, location, print, (usb/bluetooth optional), passkeys `web-browser.public-key-credential` (request from Apple early). Renderer/GPU helpers: `com.apple.security.cs.allow-jit` only | ground truth from Chrome's and Dia's plists |
| Default browser | `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` + Chrome's CoreServicesUIAgent activation trick; `application(_:open:)` for URLs | fork report §7, UI report §7.4 |
| Project tooling | XcodeGen `project.yml` + local SwiftPM packages; CMake for CEF wrapper; GN/siso for RoomCore; scripts for sign/notarize/appcast | reproducible, diff-able |
| Name | "Room" (working name); avoid any "Chrom*" in product/framework names | Google trademark |
| Identity | Product name **Room**; bundle id **`app.room.desktop`** (decided 2026-10-04, applied in 3.1a; was `com.lekevicius.room` through Chapter 2). **Amended in 3.9 (B-46, the planner's provisional choice; the user may object):** the helpers take Chromium's own suffixes under it (`app.room.desktop.helper` for the base, GPU and plugin helpers, `.helper.renderer`, `.framework.AlertNotificationService`); the `.helper.gpu`, `.helper.plugin`, `.helper.alerts` ids were the CEF helpers', deleted with CEF, and matching them on RoomCore would take a `chrome/BUILD.gn` patch the patch policy does not justify; engine framework **`RoomCore.framework`** (CEF's `Chromium Embedded Framework.framework` until Chapter 3) | the user's decision; domain owned by the author |
| Minimum macOS | **26 (Tahoe)**; dev machine runs 27; built with Xcode 27 | `NSGlassEffectView` for overlays requires 26 |
| Keychain | **Added in Phase 1.6.** RoomCore's OSCrypt item is "Room Safe Storage" (patch 0002). Team-signed builds use the login keychain; ad-hoc builds pass `--use-mock-keychain` (a new code identity per build makes macOS prompt on every read, and the cookie store holds every navigation until the prompt is answered). CEF builds always use the mock keychain (Phase 1.4) | Phase 1.5 finding |
| Network calls | **Added in Phase 1.6.** No request the user did not ask for (CLAUDE.md). Chromium's launch-time requests (component updater, `accounts.google.com`, `google.com/async`) are audited and disabled in Chapter 3.1, by prefs/switches first and `//room` hooks second; Widevine's CDM download is the one deliberate exception, on first use | Phase 1.5 net-log |
| Main menu | **Decided 2026-10-04 (Chapter 3 spec).** The host owns `NSApp.delegate` and the whole menu bar (2.8's `MainMenuTable`); Chrome's `AppController` is not installed: 3.2 adds a small factory hook and `RoomAppController`, which implements only what Chrome calls (command dispatch, extension commands, `windowDidBecomeMain` without menu bridges). The hidden Bookmarks item goes with it | Phase 1.5 crash; 2.8 made the host's menu the one source of shortcuts |
| Hybrid UI in Chapter 3 | Chrome's Views bubbles for autofill, passwords, FedCM, device choosers, print preview and web-modal dialogs stay, anchored on the host's site button or field rect through the hardening branch's modal host; native replacements are Chapter 5 work by measured annoyance. The 2.6 delegate surfaces stay native | PR #1 measured what each bubble needs; the `ShowXxxBubble` long tail is where projects stall (fork report §4.4) |
| Patch policy | Tiny factory redirects and anchor hooks only; `//base` or `//content` patches need a reproducible failure on the release build (patch 0010 parked, B-40); spike hooks and diagnostics compile only with `room_enable_spikes=true` | rebase cost (risk 1) |
| Engine selection | `App` picks `EngineCEF` or `EngineRoomCore` by the `ROOM_ENGINE` build setting from 3.1 until 3.9 deletes CEF; the same spikes run on both. **3.9:** CEF deleted; `ROOM_ENGINE` is `roomcore` by default and `none` for the engine-free Room target CI builds (`NoEngineApplication`) | the Chapter 2 app is the acceptance harness for RoomCore |
| Engine work in app chapters | **Added 2026-10-06 (Chapter 4 spec).** In Chapters 4 and 5 `//room` and `EngineRoomCore` change only in the engine steps the ROADMAP names (each one `//room` incremental, package, baseline); no new patch (the series stays 23; a phase that needs one records a user row and does the alternative; the one allowed exception is incognito, 4.8b, which the user ranked above the rule); the `Engine` protocol is frozen for the chapter except the members the spec lists, each with its `FakeEngine` counterpart and an `engine-api.md` row; numbers and crashes are judged on the release framework (`ROOM_TOUR_APP`) and the dev tour on correctness; every phase adds its tour step and ends with a by-hand list of at most ten steps | the Chapter 3 closing's three changes; the user's rule: no needless four-hour rebuild |
| Library, archive, backups | **Added 2026-10-06 (Chapter 4 spec; the user chose the sidebar).** The Library lives in the sidebar: ⇧⌘L swaps the spaces view for an AppKit view with Archive, Downloads and History sections (⌘Y lands on History), items open or restore on their own with no Library pages to navigate between; the Archive is a table in Room's database (schema v7) that Today tabs age into (a sweep every 10 min and at launch, spec §A.7) and that space deletion routes through; rolling backups copy the database (`VACUUM INTO` on Arc's schedule) and the JSON snapshot drops the navigation states (B-73) | spec §H; B-15, B-59, B-66, B-73 |
| Import | **Added 2026-10-06 (Chapter 4 spec).** Room's own readers for bookmarks (Chrome-family JSON, Safari plist, Netscape HTML), Arc's `StorableSidebar.json` and history (SQLite copies through GRDB, then `ProfileHistory.import`); passwords through Chrome's CSV importer in `//room`; no cookie import; Chromium's `ImporterHost` unused | upstream has no Chrome-to-Chromium importer; Safari's files need an open panel's grant either way |
| Routing | **Added 2026-10-06 (Chapter 4 spec).** Rules in Room's database, evaluated by the host on external opens and on cross-space link opens; the default external target is the most recent space; no engine member | spec §B |
| Reader mode | **Added 2026-10-06 (Chapter 4 spec).** The DOM Distiller script run in the isolated world, rendered in a Room-owned page with the tokens; no `//room` change; Chrome's reading-mode quality accepted as "basic" | 4.7b; the isolated world reads the DOM (B-55 hides only page globals) |
| Windows and incognito | **Added 2026-10-06 (Chapter 4 spec).** Arc's model: spaces, pinned entries and essentials shared live across windows; Today tabs per window (`entry.windowID`, schema v9: v7 is 4.1's Archive, v8 4.2's routing table), archived when their window closes; a page lives in one window's `RoomBrowser` and moves when selected elsewhere (one engine member); incognito is the engine's off-the-record profile in its own window with nothing persisted; popups stay Today tabs, document picture-in-picture gets a floating window | spec §J's per-window Today tabs; B-50, B-51; 3.2a's `RoomBrowser` per (window, profile) |

---

## 5. Chapters and phases

Development is organized into Chapters (broad arcs) and Phases (units with exit criteria). The roadmap is `ROADMAP.md`; Chapters 1–5 are specified in detail there (each as the previous one closed); Chapter 6 gets its spec after the UI and UX iteration that follows Chapter 5.

| # | Chapter | End state |
|---|---|---|
| 1 | Foundations | A page in a Dia-looking Room window on both CEF and a RoomCore embryo; spikes answered; build costs measured |
| 2 | The sidebar browser (CEF) | Usable for light browsing with the full sidebar/spaces/palette/split model; dogfooded on RoomCore (3.9) |
| 3 | RoomCore | The fork framework implements the whole `Engine` API; CEF deleted; scripted rebases |
| 4 | A complete browser | Extensions UX, passwords, archive, routing, Peek, import, settings, multi-window |
| 5 | Polish | Dia-level motion, visuals, accessibility, performance, input |
| 6 | Ship | Release pipeline, updates, crash loop, rebase operations, onboarding, public release |

## 6. Next steps

Chapters 1–3 are closed (`research/notes/chapter-1-review.md`, `chapter-2-review.md`, `chapter-3-review.md`). The Chapter 4 and 5 specs are written (ROADMAP, 2026-10-06) while the user's week of use continues on the 155 release build. Before the Chapter 4 loop: the week's notes as backlog rows, the decision form, the import fixtures (ROADMAP Chapter 4 "Before the loop"); then Chapters 4 and 5, the user's UI and UX iteration, and Chapter 6's spec. Open items that belong to no phase are in `docs/backlog.md`.

## 7. Risks and unknowns (ranked)

Re-ranked at the end of Chapter 3 (2026-10-06; the Chapter 2 ranking and reasoning are in `research/notes/chapter-2-review.md`, the Chapter 3 evidence per row in `research/notes/chapter-3-review.md`).

| # | Risk | Mitigation / spike |
|---|---|---|
| 1 | Rebase and build cost at a 2-week cadence: measured at 5.5 and ~18 min of hand work per rebase, 2 conflicts in 48 patch replays, but a night of machine time per milestone (clean dev build 4 h 34 min, official 4 h 15 min at 6 jobs) and release-only checks the dev build never runs (B-77) | `scripts/roomcore-rebase.sh` (3.8); the official build per milestone from Chapter 4 on; 23 hooks, none widened; Stable confirmed |
| 2 | Memory: ten loaded pages 4.8 GB on the release build against CEF's 3.6 GB (19 renderers for ten pages; a discarded page's renderer lingers, B-56); at rest 0.56 GB against 0.85 | The week's real tab counts; host-driven discarding with Chromium's blockers (3.7b); the renderer count per page and B-56 are 5.4's levers |
| 3 | Main-thread budget: tab switching p95 20.9 ms on the release build at 60 Hz against the 16 ms bound (median 12.9); no 120 Hz measurement yet | 5.4 with the laptop's four runs (B-16, B-18, B-20, B-21) as inputs; B-53's profile (the hide/show path, the dev DCHECKs) |
| 4 | Hybrid Views bubbles (passwords, autofill, print preview, translate, FedCM, choosers) look like Chrome inside a Dia-looking window; the translate bubble sits off its anchor | Accepted through the week; the friction rows decide which goes native first in Chapter 5 |
| 5 | `BrowserWindow` and `BrowserView` assumptions in Chrome UI code: three CHECKs met in `//room` without a patch in Chapter 3, one new pure virtual per milestone | 58 real members, 38 logged stubs; `tools/gen_browser_window_stubs.py` per rebase; first-hit logs stay |
| 6 | Unrequested network calls: every Chrome feature Chapter 3 enabled brought one request its phase found (leak check, ranker, Autofill queries, update pings); with suggestions on Chrome polls every ~100 ms (B-64) | Room's code 0, the engine 0 over launch, idle, browse, quit on dev and release (3.1b-2, 3.9); the net-log stays a per-phase step |
| 7 | Dev-build renderer DCHECKs on live sites (Blink layout, one `//net`): 9–10 minidumps per tour on the component build, 0 on release (B-76) | A condition for every dev number and by-hand pass; crashes and numbers judged on the release framework (`ROOM_TOUR_APP`) |
| 8 | Google-service dependencies the user decides: translate needs an API key (B-63), password generation needs Sync (B-72), Enhanced Spell Check (B-74), the Web Store's "Switch to Chrome?" banner, extensions' own requests (B-68) | Provisional choices recorded per row; Chapter 4.4's Settings copy states each |
| 9 | Widevine licensed playback on a real service | Demand-only CDM verified on a test stream (3.1b); the user's by-hand step on the signed 155 build; manual CDM copy as the fallback |
| 10 | Keychain and signing identity: the "Room Safe Storage" item belongs to the old identity, so the signed build prompts once | By hand once; signing 10 s, notarization 70 s, scripted (`roomcore-sign.sh`) |
| 11 | Passkey entitlement lead time | Unblocked by the identity; the user files it |
| 12 | Sparkle update size: the full DMG is 178 MiB | Full-app updates at first; the EdDSA signature by hand (the login keychain); deltas measured in Chapter 6 |
| 13 | Crashpad → Sentry: RoomCore's dumps stay under the data root with no upload URL; the app process reports behind its opt-in | 6.3 |
| 14 | Shutdown watchdog (B-38): not reproduced quiet on two release builds (0 in 89 + 20 quits); 11 of 12 under build load on the component build | Patch 0010 stays parked until a release-build reproduction |

Retired in Chapter 3: the tour passing by skipping (B-44: `PageDriver` and checks that require each result line; the rule that a check shaped by the old engine lies, after B-55, B-75 and the crash count B-76), launch time growing with the state (B-42: `quick_check`, then schema v6 at 12 ms), the CEF caps and the single-maintainer dependency on CEF (CEF deleted in 3.9).

Retired in Chapter 1: rounded-corner clipping (pixel-exact, 120 fps, and no extra WindowServer GPU work with the mask: 2.89 vs 2.88 ms per frame, measured 2026-10-03), overlay/palette z-order over the web view (green in Phase 1.4), traffic-light geometry drift (AppKit's own placement, six-state tests).

## 8. What is in `research/`

- `notes/arccore-adk-bundle-analysis.md` — direct inspection of Arc/Dia bundles; the ADK API surface; entitlements; UI stack evidence.
- `notes/arc-dia-architecture.md` — everything The Browser Company has published about ADK/EDK, Swift+Chromium, the TCA/SwiftUI reversal, current status after the Atlassian acquisition.
- `notes/cef.md` — CEF 154 on macOS: Alloy-only in an NSView, feature matrix, embedding model with file pointers, packaging, pitfalls.
- `notes/chromium-fork.md` — build costs, patch strategies (ungoogled/Helium/Brave/Vivaldi/Thorium), the `BrowserWindow` boundary surface by surface, Swift-in-GN, Google services/legal matrix, signing/updates, effort estimates.
- `notes/macos-ui-stack.md` — AppKit vs SwiftUI in 2026, the Dia look in concrete APIs, clipping question, key routing, palette design, GRDB schema, entitlements, Sparkle, reference projects.
- `notes/feature-spec.md` — the v1 product spec (sections A–J) with Zen file:line and Arc doc citations.
- `notes/visual-reference.md` + `screenshots/` — Dia/Arc/Zen window captures and the design synthesis.
- `repos/` (gitignored) — CEF source + docs, Zen desktop source, ArcCore public headers (proprietary; study only).
