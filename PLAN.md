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
- Right: the **card**: a layer-backed `NSView` with `cornerRadius 12`, `cornerCurve .continuous`, `masksToBounds`, hairline border, shadow on a sibling layer; the engine's `NSView` is its subview. Container background = page `rootBackgroundColor` so live resize never shows the material.
- Overlays (in-window views above the card): palette, hover-revealed sidebar, Peek, toasts, MRU switcher. `NSGlassEffectView` for these on macOS 26+.
- Traffic lights stay where AppKit puts them; the sidebar header lays out around their actual frames (Tahoe moved them; never hard-code).
- Keyboard: engine sees keys first (reserved set excluded), unhandled keys go once to `NSApp.mainMenu.performKeyEquivalent`.

### 2.5 Data

GRDB (SQLite, WAL) for *our* model: spaces, entries (essential/pinned/folder/today/split group), per-entry stored URL/title/favicon/custom icon, windows, archive, favicon cache, routing rules, settings. Debounced single-transaction writes with a generation counter, JSON snapshot backup, rolling backups. Browsing history, cookies, passwords, extensions live in the engine's profile (Chromium's own stores), not in ours.

### 2.6 Repository layout

```
room/
  PLAN.md, README.md, .gitignore
  project.yml                    XcodeGen → Room.xcodeproj (never hand-edited)
  App/                           AppDelegate, main.swift, menus, composition root
  Helpers/                       helper app targets (Info.plist, entitlements)
  Packages/                      local SwiftPM packages (Engine, EngineCEF, Model, Store,
                                 Omnibox, UIKitCore, Sidebar, Card, Palette, Chrome,
                                 Settings, Infra)
  Engine/cef/                    pinned CEF version, CMake for libcef_dll_wrapper, scripts
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
| Engine | Chromium fork → `RoomCore.framework` (ObjC API); CEF only as Phase 1 scaffold | §1 |
| Fork base | Vanilla Chromium release tags via depot_tools; borrow ungoogled-chromium-macos toolchain/signing scripts (BSD) as reference; no Helium code (GPL-3) | git history makes rebases `git rebase`-able; keep licensing clean |
| Patch strategy | Brave-style: all our code in `//room/`; `chromium_src/` shadow headers where needed; raw patches only for factory redirects (`browser_window_factory.cc` → `RoomBrowserWindow`) and tiny hooks | smallest rebase surface |
| What we replace vs keep | Replace: window, tab strip, sidebar, omnibox view, find bar, status bubble, infobars, permission prompt, downloads UI, extensions container, JS dialogs. Keep Views initially for: autofill popup, print preview, web-modal dialogs, DevTools docking, PDF; anchor Views bubbles by rect; move them native one by one later | the `ShowXxxBubble` long tail is where projects stall |
| Build config | Dev: `is_component_build=true symbol_level=0 blink_symbol_level=0 is_debug=false`; Release: static, `is_official_build=true`, ThinLTO, `proprietary_codecs=true ffmpeg_branding="Chrome" enable_widevine=true enable_updater=false`. **Amended in Phase 1.1:** `safe_browsing_mode=0` fails `gn gen` on M154 (Chrome targets depend on Safe Browsing); keep the default (1), compiled in but inert without an API key; revisit with `//room` patches only if the binary-size or privacy cost matters | 1.5–2 h dev builds locally; release builds nightly on a Mac mini or Depot runner |
| Chromium cadence | Track Stable (2-week milestones) with an automated rebase script; fall back to Extended Stable (8 weeks) + weekly security backports if rebases cost >1 day each | security first; one person |
| Google services | Own API keys for geolocation only; Safe Browsing off (non-commercial-only API; personal use OK later); Translate via Chromium's translate element (works in unbranded builds, not guaranteed); Chrome Web Store installs (works in unbranded builds, as in Brave/Vivaldi); no Chrome Sync (not available to third parties since 2021) | legal matrix in fork report §6 |
| Widevine | Build with `enable_widevine=true`; CDM fetched by Chromium's component updater; verify empirically; document manual CDM copy from Chrome as fallback | license is free but gated |
| UI framework | AppKit for window, sidebar, card, address field, menus, key routing; SwiftUI (`NSHostingView`) for settings, onboarding, palette rows, toasts, downloads rows | TBC's experience; drag/drop/multi-select maturity |
| State | `@Observable` stores on `MainActor`; custom MVVM, no state-diffing on hot paths (tab list) | TBC's Dia lesson |
| Persistence | GRDB + FTS5; JSON snapshot backup | Dia ships GRDB; SwiftData still has threading problems in 2026 |
| Concurrency | Swift 6, UI packages compiled with MainActor default isolation; engine callbacks wrapped in `MainActor.assumeIsolated` | CEF/Chromium UI thread is the main thread |
| Distribution | Developer ID, hardened runtime, notarytool, DMG, Sparkle 2 (EdDSA, full-app updates, deltas measured later), Sentry + Crashpad | no App Sandbox possible |
| Entitlements | Main app: camera, audio-input, location, print, (usb/bluetooth optional), passkeys `web-browser.public-key-credential` (request from Apple early). Renderer/GPU helpers: `com.apple.security.cs.allow-jit` only | ground truth from Chrome's and Dia's plists |
| Default browser | `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` + Chrome's CoreServicesUIAgent activation trick; `application(_:open:)` for URLs | fork report §7, UI report §7.4 |
| Project tooling | XcodeGen `project.yml` + local SwiftPM packages; CMake for CEF wrapper; GN/siso for RoomCore; scripts for sign/notarize/appcast | reproducible, diff-able |
| Name | "Room" (working name); avoid any "Chrom*" in product/framework names | Google trademark |
| Identity | Product name **Room**; bundle id prefix **`com.lekevicius.room`** (helpers `com.lekevicius.room.helper`, `.helper.gpu`, `.helper.renderer`, `.helper.plugin`, `.helper.alerts`); engine framework **`RoomCore.framework`** (CEF's `Chromium Embedded Framework.framework` until Chapter 3) | recorded in Phase 1.1; domain owned by the author |
| Minimum macOS | **26 (Tahoe)**; dev machine runs 27; built with Xcode 27 | `NSGlassEffectView` for overlays requires 26 |

---

## 5. Chapters and phases

Development is organized into Chapters (broad arcs) and Phases (units with exit criteria). The roadmap is `ROADMAP.md`; only Chapter 1 is specified in detail there, and each later chapter gets its spec when the previous one closes.

| # | Chapter | End state |
|---|---|---|
| 1 | Foundations | A page in a Dia-looking Room window on both CEF and a RoomCore embryo; spikes answered; build costs measured |
| 2 | The sidebar browser (CEF) | Daily-drivable for light use with the full sidebar/spaces/palette/split model |
| 3 | RoomCore | The fork framework implements the whole `Engine` API; CEF deleted; scripted rebases |
| 4 | A complete browser | Extensions UX, passwords, archive, routing, Peek, import, settings, multi-window |
| 5 | Polish | Dia-level motion, visuals, accessibility, performance, input |
| 6 | Ship | Release pipeline, updates, crash loop, rebase operations, onboarding, public release |

## 6. Next steps

Chapter 1, Phase 1.1 in `ROADMAP.md`: repository skeleton, XcodeGen project with helper targets, CEF bootstrap script, Chromium checkout and first background build.

## 7. Risks and unknowns (ranked)

| # | Risk | Mitigation / spike |
|---|---|---|
| 1 | Rounded-corner clipping of Chromium's layer-hosted view fails or is slow | Spike B week 1; fallback is a Chromium-side `SetClipPath`/`RoundedCornersF` in RoomCore (what Electron does) |
| 2 | `BrowserWindow` replacement is more entangled than the interface suggests (callers using `AsBrowserView()`) | Count call sites on the pinned tag before step 2 of Phase 2; keep Views for secondary UI anchored by rect; implement natively one surface at a time |
| 3 | Rebase cost at a 2-week Chromium cadence | Keep every line of ours in `//room/` + `chromium_src/`; scripted rebase; Extended Stable fallback; TBC manages weekly bumps for Arc with the same shape |
| 4 | Build time/iteration speed | Component builds (minutes incremental); keep engine API changes rare; UI iterates in Xcode without rebuilding Chromium |
| 5 | Widevine CDM does not download or Netflix rejects playback | Verify in Phase 2; manual CDM copy fallback; apply for the license early |
| 6 | Chrome Web Store tightens access for non-Chrome brands | Keep unpacked/CRX install path and own management UI |
| 7 | Hover-reveal overlay / palette z-order over the web view | Spike B; fallback child `NSPanel` |
| 8 | Traffic-light geometry drift across macOS 26/27 | Derive from `standardWindowButton` frames; one layout manager; six-state test |
| 9 | Passkey entitlement lead time | Request from Apple in Phase 0 |
| 10 | Sparkle delta size with a ~330 MB framework | Measure; full-app updates acceptable at first |
| 11 | Crashpad → Sentry minidump format | One forced renderer crash test in Phase 2 |
| 12 | Single-maintainer dependencies (CEF) | Only matters during Phase 1; RoomCore removes it |

---

## 8. What is in `research/`

- `notes/arccore-adk-bundle-analysis.md` — direct inspection of Arc/Dia bundles; the ADK API surface; entitlements; UI stack evidence.
- `notes/arc-dia-architecture.md` — everything The Browser Company has published about ADK/EDK, Swift+Chromium, the TCA/SwiftUI reversal, current status after the Atlassian acquisition.
- `notes/cef.md` — CEF 154 on macOS: Alloy-only in an NSView, feature matrix, embedding model with file pointers, packaging, pitfalls.
- `notes/chromium-fork.md` — build costs, patch strategies (ungoogled/Helium/Brave/Vivaldi/Thorium), the `BrowserWindow` boundary surface by surface, Swift-in-GN, Google services/legal matrix, signing/updates, effort estimates.
- `notes/macos-ui-stack.md` — AppKit vs SwiftUI in 2026, the Dia look in concrete APIs, clipping question, key routing, palette design, GRDB schema, entitlements, Sparkle, reference projects.
- `notes/feature-spec.md` — the v1 product spec (sections A–J) with Zen file:line and Arc doc citations.
- `notes/visual-reference.md` + `screenshots/` — Dia/Arc/Zen window captures and the design synthesis.
- `repos/` (gitignored) — CEF source + docs, Zen desktop source, ArcCore public headers (proprietary; study only).
