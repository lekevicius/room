# macOS UI stack for a Swift browser chrome around Chromium

Date: 2026-10-01. Target: macOS 26 Tahoe + macOS 27; dev machine macOS 27.0.1 / Xcode 27 / Swift 6.4. Visual target: Dia/Arc (see `visual-reference.md`). Engine boundary assumptions come from `arccore-adk-bundle-analysis.md` (what Dia actually ships).

Where a claim is from a source it is linked. Where it is a judgment call it says so. "Unknown" means I could not find a source.

---

## 1. Recommendations (summary)

1. **AppKit shell, SwiftUI only for leaf content.** `NSWindow`/`NSWindowController`, `NSSplitView`, the sidebar list (`NSOutlineView` or `NSCollectionView`), the browser-view container, key handling, menus, popovers, panels: AppKit. SwiftUI (via `NSHostingView`) for self-contained, low-churn leaf surfaces: settings, onboarding, the palette's result rows, toasts. This is what Dia ships (AppKit outline/collection views plus ~1,500 SwiftUI symbol refs, per bundle inspection) and matches The Browser Company's public statement that SwiftUI on Mac "consistently regressed performance" ([Josh Miller, May 2025](https://x.com/joshm/status/1927466374781079799), via [mjtsai](https://mjtsai.com/blog/2025/05/30/arc-and-dia/)). Do **not** build the sidebar in SwiftUI `List`/`OutlineGroup`: multi-select drag, cross-section moves and context-menu state are still the weak spots in 2026 ([mjtsai, June 2026](https://mjtsai.com/blog/2026/06/19/swiftui-in-appleos-27/), [pfandrade WWDC27 update](https://pfandrade.me/blog/swiftui-mac-assed-wwdc27-update/)).
2. **Dia look = full-size-content window + `NSVisualEffectView` (behind-window, `.sidebar`/`.underWindowBackground`) + an inset "card" `NSView` whose layer clips the Chromium view.** Treat *"does `masksToBounds` on an ancestor layer clip Chromium's remote `CALayerHost`?"* as the first spike of the project; it is the one visual question no public source answers (section 3.4). Use macOS 26 `NSGlassEffectView` only for floating elements (palette, toasts, hover sidebar), not as the window material.
3. **Traffic lights: leave them where AppKit puts them**, hide the title, and lay the sidebar out *around* them (Tahoe moved them: 14pt buttons at 23pt pitch vs 12pt/20pt before). Repositioning via `standardWindowButton(_:)` is the single biggest source of visual bugs in Arc clones ([luna-browser #46](https://github.com/ziadmyassine/luna-browser/issues/46), [terum PR #214](https://github.com/ryanliu-terum/terum-skills/pull/214)). If you must offset them, do it in one `TrafficLightLayoutManager` that re-applies on title change, fullscreen transitions and appearance changes.
4. **Keyboard: let Chromium see the key first, then route unhandled keys to `NSApp.mainMenu.performKeyEquivalent`.** This is Chromium's own model (renderer first, then redispatch to `-[NSApp sendEvent:]`) and the CEF `OnPreKeyEvent`/`OnKeyEvent` contract. Keep a reserved-shortcut set (⌘W, ⌘T, ⌘L, ⌘Q…) that never reaches the page.
5. **Palette: in-window overlay view (not an `NSPanel`) anchored to the sidebar address field**, custom `NSTextField` + `NSTableView`, async providers merged by a single scorer. If the engine is a Chromium fork, expose Chromium's `AutocompleteController` like Dia does; if CEF, build the six providers listed in section 5.
6. **Persistence: GRDB.swift (SQLite, WAL, FTS5).** Dia ships GRDB. SwiftData still has threading/perf problems in 2026 ([mjtsai, SwiftData in appleOS 27](https://mjtsai.com/blog/2026/06/23/swiftdata-in-appleos-27/)). Session state is a normal set of tables written in one transaction, debounced, with a JSON snapshot as the second-tier backup.
7. **Distribution: Developer ID + hardened runtime + notarytool + Sparkle 2 (EdDSA). No App Sandbox.** Helper bundles need `com.apple.security.cs.allow-jit` only (that is all Chrome and Dia ship). A sandboxed app cannot even set itself as default browser ([Apple DTS](https://developer.apple.com/forums/thread/731555)), so the sandbox question is closed.
8. **Tooling: one thin `.xcodeproj` (XcodeGen-generated is fine) + local Swift packages for all code**, Swift 6 language mode with `MainActor` default isolation in UI modules, engine behind a protocol so CEF and a fork are interchangeable.

---

## 2. UI framework decision

### 2.1 What experienced Mac developers say (2025-2026)

- **The Browser Company (Arc → Dia).** Arc's chrome was SwiftUI (not Chromium Views) ([HN](https://news.ycombinator.com/item?id=36871796)). For Dia they announced "sunsetting our use of TCA and SwiftUI to make Dia lightweight, snappy, and responsive" ([Fatbobman weekly #86](https://fatbobman.com/en/weekly/issue-086/)), and Josh Miller: "On Mac, we now use AppKit exclusively. We found that any use of SwiftUI (on Mac specifically) consistently regressed performance" ([tweet](https://x.com/joshm/status/1927466374781079799)). Our own inspection of Dia 1.51 shows that "exclusively" is marketing: the binary references `NSOutlineView`, `NSCollectionView`, `NSSplitViewController`, `NSVisualEffectView`, `NSPopover`, `NSPanel` *and* ~1,500 SwiftUI symbols, with internal modules `ARCUI`, `TabSurface`, `Motion` (`arccore-adk-bundle-analysis.md` §3). Read it as: the hot path (tab list, window, web-content hosting) is AppKit; SwiftUI survives in leaves.
- **Michael Tsai's June 2026 roundup on SwiftUI in appleOS 27** ([link](https://mjtsai.com/blog/2026/06/19/swiftui-in-appleos-27/)): Rosyna Keller: SwiftUI "only calculates what to show in the App menu once" and "you can't grab the AppKit reference as SwiftUI owns the lifecycle"; John Siracusa: window-fits-content sizing "bugs galore, changing in each minor macOS release"; Luc Vandal: crashes with `.reorderable()` when rows contain `if #available` or `.popover`; Harshil Shah: for "building containers, displaying massive collections of data, and custom layouts, UIKit still remains streets ahead."
- **Paulo Andrade, "Mac-assed app with SwiftUI, WWDC27 update"** ([link](https://pfandrade.me/blog/swiftui-mac-assed-wwdc27-update/)): improvements (`\.backgroundProminence`, `.onDragSessionUpdated`, `.reorderable`) but still no way to know a context menu is open, keyboard-navigation gaps, toolbar ergonomics; verdict: "serious Mac application development still requires either accepting limitations or supplementing with lower-level APIs."
- **SwiftUI List drag-and-drop history** ([mjtsai, Feb 2024](https://mjtsai.com/blog/2024/02/13/dragging-from-a-list-with-swiftui/)): `.onMove` never worked with multi-selection (Marco Arment); Apple's own Shortcuts app cannot drag items into sidebar folders; "flickering" and "weird side effects" (Helge Heß).
- **Performance anecdotes**: Alin Panaitiu's Grila calendar ("SwiftUI is convenient, but slow", [link](https://notes.alinpanaitiu.com/SwiftUI-is-convenient,-but-slow)): 1-2 s latency from `@ObservedObject` fan-out and binding cascades; AppKit would have updated views in place. The Sequoia regression thread on HN ([link](https://news.ycombinator.com/item?id=41139144)) turned out to be the app's own `Equatable` bug, which is itself the point: SwiftUI perf on Mac depends on invisible diffing rules.
- **Open-source Swift browsers** (details in section 9): Beam (2020-22) was SwiftUI+AppKit hybrid; Ora and Nook are SwiftUI-first on WebKit and target macOS 15/26; Luna is Swift 6 pure AppKit on WebKit; cmux (terminal, not browser, but the closest Arc-style sidebar in AppKit) is pure Swift+AppKit with ~50 local SPM packages ([cmux architecture](https://skills.cat/skills/manaflow-ai/cmux/cmux-architecture)) and still hit sidebar drag auto-scroll bugs ([cmux #9381](https://github.com/manaflow-ai/cmux/issues/9381)).
- **Orion (Kagi)**: WebKit, "built to feel native to the Mac" ([Kagi blog](https://blog.kagi.com/orion)). No public developer notes on their AppKit/SwiftUI split were found. Unknown.

### 2.2 What macOS 26/27 SwiftUI actually gives us

- New drag/drop stack, all **available on macOS 26+**: `.reorderable()` + `.reorderContainer(for:in:)`, `.dragContainer(for:)` (multi-item drags from selection), `.dragConfiguration(DragConfiguration(allowMove:))`, `.dropConfiguration`, `.dragPreviewsFormation(.stack)` ([WWDC26 session 271](https://developer.apple.com/videos/play/wwdc2026/271/)). Lists now accept drops into reorderable content even without a `.reorderableItem` representation.
- `.onDragSessionUpdated` (session visibility from drag start) ([pfandrade](https://pfandrade.me/blog/swiftui-mac-assed-wwdc27-update/)).
- Still missing vs AppKit: filtering which sub-region of a row starts a drag; knowing a context menu is open; `NSMenu`-level dynamic menu validation; stable multi-select `onMove`; and the `.reorderable()` crash reports above are from June 2026, i.e. this API is one release old.

### 2.3 Decision

**AppKit window + AppKit sidebar + AppKit browser container; SwiftUI leaves via `NSHostingView`.**

Concretely:

| Surface | Framework | Why |
|---|---|---|
| `NSWindow` subclass, window controller, split layout | AppKit | full-size content, titlebar, traffic lights, fullscreen, tabbing, key routing all live here |
| Sidebar tree (pinned grid, folders, open tabs) | AppKit `NSOutlineView` (view-based, `NSTableRowView` subclass) or `NSCollectionView` with compositional layout | native multi-select, `NSDraggingSession` with per-row drag-image, drop onto folders, inline rename via `NSTextField` in the cell, `validateMenuItem`, arrow/type-select keyboard nav, `NSTableView.animateMoves` |
| Address field in sidebar | AppKit `NSTextField` subclass (field editor control) | caret/selection/IME behavior, completions |
| Browser card container | AppKit `NSView` (layer-backed) | hosts the Chromium `NSView`; clipping and shadow are layer properties |
| Palette overlay, toasts, downloads list rows, settings, onboarding | SwiftUI in `NSHostingView` | low churn, animation-friendly, easy to iterate; `NSHostingView.sizingOptions` to avoid layout fights |
| Browser view inside SwiftUI (if ever) | `NSViewRepresentable` | only for previews/dev tools; never for the main card |

Pitfalls to design around:
- `NSHostingView` inside an AppKit layout: set `sizingOptions = [.intrinsicContentSize]` or pin constraints explicitly; hosting views that change intrinsic size on every state change trigger AppKit layout passes (one of the common perf regressions people attribute to "SwiftUI on Mac").
- Do not put the Chromium view under a SwiftUI parent that re-identifies (`.id()`) on state change: the `NSView` gets torn down and the renderer resizes/repaints.
- Animations: AppKit implicit layer animations (`NSAnimationContext` + `allowsImplicitAnimation`, `CASpringAnimation`) are display-driven and run at the panel's native rate; for custom frame-driven animation use `NSView.displayLink(target:selector:)` (macOS 14+) which follows ProMotion ([Apple docs](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:))). Never animate with `Timer`.
- Reduce Motion: check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and shorten/skip card and sidebar animations.

---

## 3. Achieving the Dia look (concrete APIs and caveats)

### 3.1 Window configuration

```swift
let w = NSWindow(contentRect: r,
                 styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                 backing: .buffered, defer: false)
w.titlebarAppearsTransparent = true
w.titleVisibility = .hidden
w.toolbarStyle = .unifiedCompact   // only matters if you attach an NSToolbar; we don't
w.isMovableByWindowBackground = true
w.tabbingMode = .disallowed        // plus NSWindow.allowsAutomaticWindowTabbing = false at launch
w.collectionBehavior = [.fullScreenPrimary, .managed]
w.backgroundColor = .clear          // the effect view below provides the material
w.isOpaque = false
```

Docs: [`titlebarAppearsTransparent`](https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent), [`titleVisibility`](https://developer.apple.com/documentation/appkit/nswindow/titlevisibility), [`toolbarStyle`](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle), [`isMovableByWindowBackground`](https://developer.apple.com/documentation/appkit/nswindow/ismovablebywindowbackground), [`tabbingMode`](https://developer.apple.com/documentation/appkit/nswindow/tabbingmode).

Make `isMovableByWindowBackground` only true for the sidebar background: override `mouseDownCanMoveWindow` to return `false` in the card container and in rows, otherwise drags on tabs will move the window.

### 3.2 Window-wide material

- **Base layer: `NSVisualEffectView`** as the window's content view (or the first subview filling it), `blendingMode = .behindWindow`, `material = .sidebar` (Dia's neutral look) or `.underWindowBackground` (slightly flatter), `state = .followsWindowActiveState`. Apple's guidance: pick materials by semantic role, "Don't select materials based on the apparent colors they impart"; behind-window blending "makes your entire window stand out above other windows"; AppKit already uses it for sheets and popovers ([NSVisualEffectView docs](https://developer.apple.com/documentation/appkit/nsvisualeffectview)). `.hudWindow` is for dark HUD panels; not for this.
- **Vibrancy for text**: only leaf views should return `allowsVibrancy = true`; standard `NSTextField` labels already do. Use `labelColor`/`secondaryLabelColor`, not custom grays, so vibrancy blends correctly ([same doc](https://developer.apple.com/documentation/appkit/nsvisualeffectview)).
- **macOS 26 interaction**: WWDC25 "Build an AppKit app with the new design" (session 310) says system sidebars now "render as floating glass panes" and tells you to *remove* legacy `NSVisualEffectView`s from `NSSplitViewItem` sidebars, set `NSSplitViewItem.automaticallyAdjustsSafeAreaInsets = true` so content extends under the floating sidebar, and use `NSBackgroundExtensionView` when you do not want content under the sidebar ([session](https://developer.apple.com/videos/play/wwdc2025/310/), [notes](https://wwdcnotes.com/documentation/wwdc25-310-build-an-appkit-app-with-the-new-design/)). That is the *system* sidebar look (glass pane floating over content). Dia's look is the opposite: a flat, window-wide material with the *content* floating as a card. So we do **not** use `NSSplitViewController` sidebar items with their automatic glass; we use a plain `NSSplitView` (or manual layout) over our own effect view. This also sidesteps the automatic safe-area/corner adaptation machinery.
- **Liquid Glass where it fits**: `NSGlassEffectView` (macOS 26+): `contentView`, `cornerRadius`, `tintColor`, `style`, `effectIsInteractive`; group several in an `NSGlassEffectContainerView` (`spacing`) to merge shapes and cut render passes ([NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview), [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)). SwiftUI equivalents: `.glassEffect(_:in:)` and `GlassEffectContainer(spacing:)` ([docs](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)). Good for: the hover-revealed sidebar overlay, the palette, toasts, the downloads popover body. Not for the window background (it is an element material, not a window material, and it is expensive to blur a large area with dynamic content under it). Luna advertises "a real Liquid Glass sidebar" on macOS 26 — that is the floating-pane look.
- **Per-space tint (Arc)**: cheapest is a `CAGradientLayer` (or `NSGradient` draw) in a plain `NSView` *above* the effect view at 10-25% alpha, animated with `CABasicAnimation` on `colors` when the space changes. `NSGlassEffectView.tintColor` is the Liquid Glass way if the sidebar is itself glass. Keep the gradient behind vibrant text; test contrast in both appearances.
- **Light/dark**: use dynamic `NSColor`s (asset catalog or `NSColor(name:dynamicProvider:)`), observe `effectiveAppearance` via KVO on the window's content view and re-derive the tint; set `window.appearance = nil` so it follows the system. `NSVisualEffectView` and `NSGlassEffectView` adapt automatically.

### 3.3 Traffic lights

- Tahoe changed geometry: controls are 14pt at a 23pt pitch (measured via `standardWindowButton` on 26.6.2) versus 12pt/20pt on macOS 11-15; the reserved width grew from 68 to 76px ([terum PR #214](https://github.com/ryanliu-terum/terum-skills/pull/214)). Any hard-coded inset will be wrong on one of the two OS lines.
- Default position (with `.fullSizeContentView` + transparent titlebar) is fine for the Dia layout: sidebar header gets a top inset of ~38-40pt and a left inset computed *from the buttons' actual frames* (`standardWindowButton(.zoomButton)!.frame.maxX`), not a constant.
- If you insist on moving them (Arc does, to sit them in the sidebar row): there is no public API; people re-frame the buttons in `layoutIfNeeded`/`windowDidResize` and it drifts after fullscreen, after `title` changes (AppKit rebuilds the titlebar), after appearance changes, and with the "mini window" ([luna-browser #46](https://github.com/ziadmyassine/luna-browser/issues/46): "the #1 source of visual bugs in Arc-style browsers"; keep one `TrafficLightLayoutManager`, unit-test six window states). Also from that issue: with Auto Layout in the content view, `minSize`/`contentMinSize` are ignored; constrain the content view instead.
- Hide them in fullscreen? AppKit auto-hides the titlebar with `.fullScreenPrimary`; the buttons move with it. Do not hide/reshow them manually.

### 3.4 The inset page card and clipping Chromium

**Desired**: web content in a rounded rect (10-12pt, continuous curve), inset 8pt top/right/bottom, hairline border at ~6-8% label color, soft shadow.

**How Chromium puts pixels on screen on macOS**: the GPU process renders into IOSurfaces and a `CALayer` tree; the browser process's `ui::AcceleratedWidgetMac` takes the hosting `NSView`'s backing layer and adds sublayers; for out-of-process trees it creates a `CALayerHost` with a `CAContextID` (remote layer) ([display_ca_layer_tree.mm](https://chromium.googlesource.com/chromium/src/+/HEAD/ui/accelerated_widget_mac/display_ca_layer_tree.mm), [JxBrowser write-up](https://teamdev.com/jxbrowser/blog/cross-process-rendering-using-calayer/)). So the Chromium view is a layer-hosting `NSView` whose content is composited by the window server from another process.

**What that means for clipping** (judgment, not sourced): the remote layer is still a node in the window's layer tree, and `masksToBounds` + `cornerRadius` on an *ancestor* layer is applied by the render server to everything beneath it, including `CALayerHost` content. So `container.wantsLayer = true; container.layer!.cornerRadius = 12; container.layer!.cornerCurve = .continuous; container.layer!.masksToBounds = true` with the Chromium `NSView` as a subview *should* produce the card. Dia visibly ships exactly this (white rounded card with Chromium content, `visual-reference.md`), and ArcCore exposes `createPaneHostView`/`attachToPaneHostView:` (host-owned pane views) — but nothing public says whether they clip in AppKit or inside Chromium's compositor. **No public issue or doc confirms or denies that ancestor masking works with Chromium's remote layer; treat it as unknown and spike it in week 1.**

Known facts to design around:
- `masksToBounds` kills the layer's own shadow. Put the shadow on a sibling layer behind the card (same frame, `shadowPath` set) or on the container's superlayer; the border goes on the clipped layer (`borderWidth`/`borderColor`) or as a separate 1px overlay layer so Chromium can't paint over it.
- Electron solved the same problem *inside Chromium*: `WebContentsView.setBorderRadius()` is implemented with `views::View::SetClipPath()` (an `ash::RoundedRectCutoutPathBuilder` path, minimum 32×32, radius ≤ half the view) and `gfx::RoundedCornersF` on the web view holder; clicks in the cut-out corners still hit the page ([Electron commit](https://ayakael.net/mirrors/electron/commit/778d3098a0f0bfc00015d54263674318f4adf6b1), [View docs](https://electronjs.org/docs/latest/api/view)). Chromium's compositor therefore already knows how to round its own output layer; if the AppKit mask fails or performs badly, the fallback is a small Chromium-side patch (fork) or asking for `ui::Layer::SetRoundedCornerRadius` on the web contents' layer through whatever engine API we own. Electron also ships `-electron-corner-smoothing` CSS for continuous corners ([RFC](https://github.com/electron/rfcs/blob/main/text/0012-corner-smoothing.md)) — only relevant if we round in Chromium.
- Hit testing: an AppKit layer mask is visual only; mouse events in the corner triangles still reach the Chromium view. Irrelevant at 12pt radius.
- Performance: a single rounded mask on a large layer is a standard window-server operation; the thing to measure is whether the GPU process output path falls off its fast path (an IOSurface layer that can be scanned out directly vs needing a composite). Measure with Quartz Debug "flash screen updates" and `CA::Transaction` timing in Instruments after the spike.
- Resizing: Chromium resizes asynchronously; during live window resize the card edge may expose the window material for a frame. Dia/Arc show the card's background color under the page (ArcCore exposes `rootBackgroundColor`/`themeColor` per web contents) — set the container layer's `backgroundColor` to the page's root background so resize gaps are invisible.

### 3.5 Typography and icons

SF Pro via `NSFont.systemFont(ofSize:weight:)`/`preferredFont(forTextStyle:)`; 13pt regular for rows, semibold for space names (matches `visual-reference.md`). SF Symbols via `NSImage(systemSymbolName:accessibilityDescription:)` with `NSImage.SymbolConfiguration(pointSize:weight:)`; set `isTemplate` so vibrancy tints them. On macOS 26 controls scale globally; the session recommends Auto Layout over hard-coded heights and `NSView.prefersCompactControlSizeMetrics` for compatibility ([WWDC25 310 notes](https://wwdcnotes.com/documentation/wwdc25-310-build-an-appkit-app-with-the-new-design/)).

---

## 4. Window and sidebar behaviors

### 4.1 Hidden sidebar with edge hover-reveal

- Orion's implementation (as described in their feedback forum) adds an `NSTrackingArea` covering the window, reveals when the cursor is within ~5px of the left edge, and uses *private* `NSSplitView` methods `_uncollapseWithOverlayArrangedView:animated:` / `_collapseArrangedView:animated:` ([orionfeedback thread](https://orionfeedback.org/d/684-sidebar-openclose-on-hover/97)). Do not depend on private API.
- Recommended: when collapsed, the card fills the window; a 6-8pt `NSView` strip at the left edge owns an `NSTrackingArea` (`.mouseEnteredAndExited`, `.activeInKeyWindow`). On enter (after ~150 ms dwell) present the sidebar as an **overlay view** added *above* the card in the content view (glass via `NSGlassEffectView`, with shadow on a backing layer), animated with a spring on `frame.origin.x`. Collapse on `mouseExited` of the overlay (with ~300 ms grace), on key window loss, and when the palette closes.
- Chromium's `NSView` receives `mouseMoved`/`mouseExited` for its own area and will not forward them; put the tracking areas on views that are siblings *above* it, or use `NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved])` to observe the pointer position regardless of which view is under it. Global monitors are unnecessary (we only care inside our window).
- A child `NSPanel` (`window.addChildWindow(_, ordered: .above)`) is the alternative if z-ordering against the Chromium layer proves unreliable; it costs a second window (its own vibrancy/behind-window blend, which can look different from the main window) and complicates fullscreen. Try in-window first.

### 4.2 Fullscreen, multiple windows, Stage Manager, tabbing

- Fullscreen: `.fullScreenPrimary`; `NSWindowDelegate.window(_:willUseFullScreenPresentationOptions:)` to keep the menu bar auto-hidden; re-layout the sidebar header inset when the titlebar hides (`windowDidEnterFullScreen`). Keep the card inset in fullscreen or let it bleed to zero — Dia keeps it.
- Multiple windows: one `NSWindowController` per window, each with its own `ArcBrowser`-equivalent/CEF browser list; the sidebar model is per-window view state over a shared tab store.
- Disable window tabbing (`tabbingMode = .disallowed`, `NSWindow.allowsAutomaticWindowTabbing = false`) so ⌘T is ours and "Show Tab Bar" never appears.
- Stage Manager needs nothing special for standard windows. Unknown: no source discussing Stage Manager quirks with non-opaque full-size-content windows was found.

### 4.3 Keyboard routing between AppKit and Chromium

The model Chromium itself uses on macOS ([chromium.org OS X keyboard handling](https://www.chromium.org/developers/os-x-keyboard-handling/)):
1. The key arrives at `-[NSApp sendEvent:]`, which calls `performKeyEquivalent:` down the view chain; Chromium's `RenderWidgetHostViewMac` intercepts and sends the event to the renderer by IPC *before* the menu sees it.
2. A blocklist of reserved shortcuts (⌘W etc.) never reaches the renderer.
3. If the page does not consume the event, Chromium **redispatches** it to `-[NSApp sendEvent:]` with a flag preventing loops, so menu key equivalents and system shortcuts (⌘`) fire.

CEF exposes the same two hooks: `CefKeyboardHandler::OnPreKeyEvent(browser, event, os_event, &is_keyboard_shortcut)` ("called before a keyboard event is sent to the renderer… if the event will be handled in OnKeyEvent() as a keyboard shortcut set is_keyboard_shortcut to true and return false") and `OnKeyEvent(browser, event, os_event)` ("called after the renderer and JavaScript in the page has had a chance to handle the event") ([cef_keyboard_handler.h](https://third-party-mirror.googlesource.com/cef/+/refs/heads/master/src/include/cef_keyboard_handler.h)). `os_event` is the `NSEvent`. ArcCore's equivalent is the "consumed keys (keyboard shortcut arbitration)" delegate (`arccore-adk-bundle-analysis.md`).

Design:
- Reserved set handled in `OnPreKeyEvent` (return true): ⌘T/⌘L/⌘W/⌘N/⌘Q/⌘,/⌘⇧] etc., plus ⌘1-9 for space/tab switching. The page never sees them.
- Everything else goes to the page; in `OnKeyEvent` call `NSApp.mainMenu?.performKeyEquivalent(with: osEvent)` once and stop. Do **not** re-send through `NSApp.sendEvent` from a CEF callback: cmux/agentmux found that a re-sent event re-enters the browser view and loops when nothing is focused ([agentmux PR #3737](https://github.com/agentmuxai/agentmux/pull/3737)). Normalize the event for non-Latin IMEs before menu dispatch (`charactersIgnoringModifiers` vs `characters`), as cmux had to ([cmux PR #2032](https://github.com/manaflow-ai/cmux/pull/2032); Apple thread on [key equivalent matching with non-US layouts](https://developer.apple.com/forums/thread/729242)).
- Build the main menu in code (`NSMenu`/`NSMenuItem` with `keyEquivalent`/`keyEquivalentModifierMask`), validate with `NSMenuItemValidation`. SwiftUI `.commands` is not an option in an AppKit shell and has the "computed once" problem anyway.
- Because Chromium runs its own message pump inside `NSApplication`, the `NSApplication` subclass must implement `CrAppProtocol`/`CefAppProtocol` (`isHandlingSendEvent`) — present in both ArcCore headers and CEF.

---

## 5. Command palette / omnibox design

### 5.1 Presentation

- Arc/Dia: ⌘T/⌘L focus a field; results drop down *inside the window*. That is an in-window overlay `NSView` (glass or solid material, shadow), not a global launcher. `NSPanel` tricks (`.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`, cycling `NSApp.setActivationPolicy`) are only needed for Spotlight/Raycast-style palettes that must not activate the app ([multi.app](https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette), [fazm floating-panel notes](https://fazm.ai/blog/swiftui-floating-panel)). Keep that in reserve for a later "quick open from anywhere" feature.
- Components: `NSTextField` subclass (field editor delegate for ↑/↓/⏎/⎋/⇥ via `control(_:textView:doCommandBy:)`), inline-autocomplete by setting the field's string and selecting the completed suffix (Chromium behavior), and an `NSTableView` (or SwiftUI `List` in an `NSHostingView` — fine here, it is a read-only list) for results. Highlight matched ranges with `NSAttributedString`.
- First responder: when the overlay opens, Chromium's view resigns first responder; on close, restore focus to the web view (`window.makeFirstResponder(browserView)`) so page keyboard focus returns.

### 5.2 Suggestions

Chromium's `AutocompleteController` is **not** exposed by CEF. The ADK (Dia) *does* expose it, with history, bookmarks, search suggest, keyword search, tab match and inline autocomplete (`arccore-adk-bundle-analysis.md` §2). So:

- **If the engine is a fork**: expose `AutocompleteController` through the ObjC layer like ArcCore does and skip most of this section. It gives Chrome-quality ranking for free.
- **If CEF**: build it. Providers (each an `async` function returning `[Match]` for a query, cancellable via `Task`):
  1. *Verbatim*: "Search <engine> for q" or navigate if `q` parses as a URL/host (heuristics: contains `.` and no spaces, or `localhost`, or scheme).
  2. *Open tabs* (switch-to-tab): fuzzy over title+URL of all windows/spaces.
  3. *History*: SQLite FTS5 over `title`, `url` (with `trigram` tokenizer so mid-word matches work), ranked by a frecency score (visit count × recency decay, Firefox-style; see [Firefox urlbar docs](https://firefox-source-docs.mozilla.org/browser/urlbar/)) plus FTS rank.
  4. *Bookmarks/pinned*: same index, boosted.
  5. *Search suggest*: OpenSearch JSON `["q", ["s1","s2",...]]` from the user's engine: Google `https://suggestqueries.google.com/complete/search?client=firefox&q=` (undocumented but universal, [growthrocks](https://growthrocks.com/glossary/googles-query-suggest-api/)), DuckDuckGo `https://duckduckgo.com/ac/?q=&type=list`, Kagi `https://kagi.com/api/autosuggest?q=` ([Kagi feedback](https://kagifeedback.org/d/2763-support-of-rich-search-suggestions)). Debounce 100-150 ms, cancel in-flight on each keystroke, cap at 5. Respect a "no network suggestions" privacy toggle.
  6. *Commands*: "New space", "Toggle sidebar", "Clear history"… from a static registry with fuzzy match.
- Merge: a single scorer assigns each match a numeric relevance (Chromium uses 0-1500 bands; mimic: verbatim URL 1400, open tab 1200, history exact-prefix 1100-1300 by frecency, bookmarks 1000+, suggest 600-900, commands 500-1300 depending on prefix), stable-sort, dedupe by normalized URL, keep 8.
- Fuzzy library: [Ifrit](https://github.com/ukushu/Ifrit) (MIT, pure Swift, async, `AttributedString` highlights; the maintained successor of the archived [fuse-swift](https://github.com/krisk/fuse-swift)); [FuzzyMatch](https://swiftpackageregistry.com/ordo-one/FuzzyMatch) if latency over tens of thousands of entries matters. Use fuzzy only for tabs/commands; use FTS5 for history (fuzzy over 100k history rows per keystroke is wasteful).
- Inline autocomplete only from history/bookmarks with a strong prefix match on host (`gith` → `github.com`), never from search suggest.

---

## 6. Persistence

### 6.1 Store choice

- **GRDB.swift**: SQLite with a typed query interface, WAL, `ValueObservation` for reactive UI, and first-class FTS3/4/5 virtual-table support ([GRDB FullTextSearch doc](https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md), [GRDB](https://github.com/groue/GRDB.swift)). It is what Dia links (`arccore-adk-bundle-analysis.md` §3). 2026 comparisons land on "GRDB for anything data-heavy, SwiftData for simple apps that stay simple" ([pistack comparison](https://www.pistack.xyz/posts/2026-08-11-grdb-swiftdata-core-data-swift-persistence-comparison/)).
- **SwiftData**: iOS/macOS 27 fixed some gaps (enum predicates, compound queries) but `ModelActor` "continues to sometimes run code on the main thread" (Matt Massicotte) and `propertiesToFetch` "does not work" (Mohammad Azam) ([mjtsai, June 2026](https://mjtsai.com/blog/2026/06/23/swiftdata-in-appleos-27/)). Nook uses it and had to build "generation coalescing", JSON backups and atomic write pipelines around it ([Nook persistence wiki](https://deepwiki.com/nook-browser/Nook/3.3-persistence-architecture-and-swiftdata)). No FTS. Not for a browser.
- **Core Data**: works, FTS via Spotlight only, verbose. No.
- **Plain JSON**: fine for settings and as a backup snapshot of session state, not as the primary store (no partial writes, no indexing).

### 6.2 Schema sketch (one GRDB database, WAL)

`space(id, name, color, sortOrder)`, `tab(id, spaceId, parentFolderId?, kind pinned|folder|open, title, url, faviconId?, sortOrder, lastActiveAt, sessionBlob)`, `window(id, frame, activeSpaceId, sidebarState)`, `history_visit(id, urlId, visitedAt, transition)`, `history_url(id, url, title, visitCount, lastVisitAt, frecency)`, `history_fts` (FTS5 external-content table over `history_url(title,url)`, `tokenize='trigram'`), `favicon(id, pageHost, pngBlob, sha256, updatedAt)`, `download(...)`, `kv(key, json)`.

### 6.3 Crash-safe session restore

- Every structural change (open/close/move/rename/space switch) mutates the in-memory store and schedules a **debounced** write (250-500 ms, flush immediately on quit, window close, and `applicationWillTerminate`). Each write is one SQLite transaction (all-or-nothing); WAL gives durability without fsync-per-keystroke. Keep a monotonically increasing `generation` so a stale async write never overwrites a newer one (the pattern Nook landed on).
- Navigation state (back/forward lists) comes from the engine (`sessionBlob` per tab): CEF has no serialized navigation entries; a fork can expose `NavigationController` entries like Chrome's session service does. With CEF, store URL + title + scroll offset only.
- "Unclean exit" flag: set `running=1` in `kv` at launch, clear on clean quit; at next launch, if set, restore silently (it is a browser; always restore) but keep the previous session as `session_backup.json` so "Restore previous session" is possible after a bad write.
- Second-tier backup: after each successful write, also dump the session (tabs/spaces/windows) to a JSON file via `Data.write(options: .atomic)`. Firefox rewrites its recovery file roughly every 15 s ([search summary](https://supasidebar.com/blog/restore-tabs-after-browser-crash)); SQLite + JSON every few hundred ms is cheaper than it sounds for a few hundred rows.
- Tab discarding: persist tabs the moment they are created; discarded tabs keep their row and lose their engine object.

### 6.4 Favicons and history indexing

- Favicons: CEF `CefDisplayHandler::OnFaviconURLChange` → `CefBrowserHost::DownloadImage` (max 64px, PNG); ArcCore exposes a favicon service directly. Store PNG blobs keyed by host, dedupe by SHA-256, serve to the sidebar through an in-memory `NSCache<NSString, NSImage>`. Fall back to a letter tile. Re-fetch at most daily.
- History: insert `history_visit` per committed main-frame navigation (skip reloads/back-forward for frecency, record them as visits), update `history_url.visitCount/lastVisitAt/frecency` in the same transaction; FTS5 external-content triggers keep `history_fts` in sync. Rebuild `frecency` lazily (daily decay job).

---

## 7. Distribution and signing

### 7.1 Sandbox situation (settled)

- **App Sandbox: no.** Two independent blockers:
  1. Under App Sandbox all processes must be started by launchd, and Chromium helper processes crash on launch when they cannot look up service ports by parent PID — the recurring Mac App Store problem for CEF apps ([CEF forum: MAS compatibility](https://magpcss.org/ceforum/viewtopic.php?f=6&t=16215), [chromium-discuss](https://groups.google.com/a/chromium.org/g/chromium-discuss/c/wns7LkMPdCM)).
  2. A sandboxed app cannot change application bindings: `NSWorkspace.setDefaultApplication(...)` fails with `NSOSStatusErrorDomain -54 (permErr)`; Apple DTS (Quinn): "If your app is sandboxed, this is not expected to work. The App Sandbox prevents apps from changing application bindings" ([Apple forums](https://developer.apple.com/forums/thread/731555)). A browser that cannot become the default browser is not a browser.
  Dia ships without App Sandbox (`arccore-adk-bundle-analysis.md` §4). Mac App Store distribution is therefore off the table; Developer ID only.
- **Chromium's own sandbox: yes.** CEF helper executables link the `cef_sandbox` static library and call `cef_sandbox_initialize()` before loading the framework, which seatbelt-sandboxes renderer/GPU/utility processes ([cef_sandbox_mac.h](https://cef-builds.spotifycdn.com/docs/126.2/cef__sandbox__mac_8h.html)). This is unrelated to App Sandbox and must stay on.

### 7.2 Hardened runtime and entitlements

Apple only notarizes apps with the hardened runtime; exceptions are per-executable entitlements, and Apple's own guidance is "opt for the narrowest set" ([Configuring the hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)). The three JIT-related exceptions form a hierarchy; set only one ([Apple forums](https://developer.apple.com/forums/thread/776290)).

What Chrome itself ships (ground truth):
- `chrome/app/helper-renderer-entitlements.plist`: `com.apple.security.cs.allow-jit = true` — nothing else ([source](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/app/helper-renderer-entitlements.plist)).
- `chrome/app/helper-gpu-entitlements.plist`: `com.apple.security.cs.allow-jit = true` ([source](https://chromium.googlesource.com/chromium/src/+/lkgr/chrome/app/helper-gpu-entitlements.plist)).
- `chrome/app/app-entitlements.plist` (main app): `device.audio-input`, `device.bluetooth`, `device.camera`, `device.print`, `device.usb`, `personal-information.location`, `personal-information.photos-library` ([source](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/app/app-entitlements.plist)). No JIT in the browser process.
- Dia: main app has `com.apple.developer.web-browser.public-key-credential` (passkeys/WebAuthn), `associated-domains`, camera, audio-input, location, keychain-access-groups; **Renderer and GPU helpers: only `allow-jit`** (`arccore-adk-bundle-analysis.md` §4).

Older CEF-forum advice (2019-era) used `allow-jit` + `allow-unsigned-executable-memory` + `disable-library-validation` on helpers and the maintainer said "the number of required entitlements will decrease over time" ([CEF forum: notarization](https://www.magpcss.org/ceforum/viewtopic.php?f=6&t=16481&start=10)). It has: current Chrome/Dia need `allow-jit` only.

Recommended entitlement files:

```
App.entitlements (main app, browser process)
  com.apple.security.device.audio-input            true
  com.apple.security.device.camera                 true
  com.apple.security.personal-information.location true
  com.apple.security.device.print                  true   (only if print is supported)
  com.apple.security.device.usb                    true   (WebUSB; optional)
  com.apple.security.device.bluetooth              true   (WebBluetooth; optional)
  com.apple.developer.web-browser.public-key-credential  true  (passkeys; needs a profile from Apple)

Helper (Renderer).entitlements, Helper (GPU).entitlements
  com.apple.security.cs.allow-jit                  true

Helper.entitlements, Helper (Plugin).entitlements, Helper (Alerts).entitlements
  (none)  -- add allow-jit to Plugin only if a plugin process runs V8
```

Do **not** add `disable-library-validation`: all Mach-Os are signed with the same Team ID, so library validation passes. Do not add `allow-unsigned-executable-memory` (superset, weaker). CEF's binary distribution produces five helper variants (`Helper`, `Helper (GPU)`, `Helper (Renderer)`, `Helper (Plugin)`, `Helper (Alerts)`) from `CEF_HELPER_APP_SUFFIXES` in `tests/cefsimple/CMakeLists.txt.in` ([source](https://github.com/chromiumembedded/cef/blob/master/tests/cefsimple/CMakeLists.txt.in)); ArcCore has the same set under `Frameworks/ArcCore.framework/Helpers/`.

Signing order (inside-out, every step `--options runtime --timestamp`): helper apps (each with its entitlements) → dylibs in the framework (`libEGL`, `libGLESv2`, `libvk_swiftshader`, …) → `Chromium Embedded Framework.framework` → Sparkle's XPC services/`Autoupdate`/`Updater.app` inside `Sparkle.framework` (Sparkle's `codesign` recommendations) → the app. Then `xcrun notarytool submit App.dmg --keychain-profile <p> --wait` and `xcrun stapler staple`. Ship a DMG (Sparkle docs assume "notarized and Developer ID signed disk image").

### 7.3 Sparkle 2

- `generate_keys` once (private EdDSA key in Keychain, public key base64 to `SUPublicEDKey`); `SUFeedURL` in Info.plist; archive each release (`.dmg`/`.zip`) into a folder and run `generate_appcast`, which signs, builds delta updates and prunes old entries ([Sparkle docs](https://sparkle-project.org/documentation/)). Appcast must be HTTPS with modern TLS; any static host works — GitHub Releases for archives + GitHub Pages or Cloudflare Pages/R2 for `appcast.xml` is a common pattern (cmux, many OSS apps ship Sparkle + GitHub), but Sparkle's docs do not specifically bless GitHub. Non-sandboxed apps may delete Sparkle's XPC services to save space.
- Updates replace a ~400 MB bundle (Chromium framework). Delta updates matter; keep the framework path stable across versions so `generate_appcast` deltas stay small.

### 7.4 Default browser, URL handling, Continuity

- Info.plist: `CFBundleURLTypes` with `http`, `https` (and `file`? no — Finder opens HTML through document types): `CFBundleDocumentTypes` for `public.html`, `public.xhtml` as Viewer. Chrome's `shell_integration_mac.mm` registers for `http`, `https` and (only on macOS < 26.4) `UTTypeHTML` ([source](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/shell_integration_mac.mm)) — the HTML content-type registration was dropped for 26.4+, reason not stated; copy Chrome.
- Set default: `NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { error in … }` and again for `https` (macOS 12+, [docs](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:))). macOS shows a system confirmation ("Use X as default?") from `CoreServicesUIAgent`; it can appear *behind* our window, so Chrome finds `com.apple.coreservices.uiagent` in `NSWorkspace.shared.runningApplications` and calls `activate(options: .activateAllWindows)` after calling the API ([same source](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/shell_integration_mac.mm)). `LSSetDefaultHandlerForURLScheme` is deprecated; do not use.
- Check default: `NSWorkspace.shared.urlForApplication(toOpen: URL(string:"http://example.com")!)` and compare bundle identifiers (Chrome does the same).
- Prompt UX: at first launch show an in-sidebar card ("Make Room your default browser" → calls the API → system dialog), never a modal; re-ask at most once after 7 days; add "Set as default…" in Settings and the app menu.
- Receiving URLs: implement `NSApplicationDelegate.application(_:open:)` (`[URL]`, macOS 10.13+); this covers `open -a`, Finder, other apps and `kAEGetURL`. Do **not** also register an `NSAppleEventManager` handler for `kInternetEventClass/kAEGetURL`: registering it suppresses `application(_:open:)` ([Apple forums](https://developer.apple.com/forums/thread/703029), [floschliep](https://medium.com/@floschliep/url-routing-on-macos-c53a06f0a984)). URLs can arrive before `applicationDidFinishLaunching` finishes and before the engine is up; queue them.
- Handoff: publish `NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)` with `webpageURL` for the active tab and accept it in `application(_:continue:restorationHandler:)`. Optional; needs an iOS counterpart to be useful. Universal links on macOS only apply to the app's *own* associated domains (Dia carries `associated-domains`); irrelevant for v1.

### 7.5 Crash reporting

- Swift side: Sentry Apple SDK captures Mach exceptions, signals, unhandled ObjC/C++ exceptions, app hangs; macOS lacks session replay, screenshots, watchdog terminations ([Sentry macOS features](https://docs.sentry.io/platforms/apple/guides/macos/features/)). Dia links Sentry.
- Chromium side: CEF uses Crashpad, configured by `crash_reporter.cfg` in `App.app/Contents/Resources` (`ProductName`, `ProductVersion`, `ServerURL`, `BrowserCrashForwardingEnabled` — when true, browser-process crashes go to the system crash reporter/`~/Library/Logs/DiagnosticReports`) ([cef_crash_util.h](https://third-party-mirror.googlesource.com/cef/+/refs/heads/master/src/include/cef_crash_util.h), [crash_reporting.cc](https://third-party-mirror.googlesource.com/cef/+/refs/heads/master/src/libcef/common/crash_reporting.cc)). Point `ServerURL` at Sentry's minidump ingestion endpoint ([Sentry Native/Crashpad docs](https://docs.sentry.io/platforms/native/configuration/backends/crashpad)); whether CEF's multipart POST format is accepted as-is by Sentry's minidump endpoint is **unverified** — test with one forced renderer crash. Keep `BrowserCrashForwardingEnabled=true` so Sentry's in-process handler owns browser-process crashes and Crashpad owns helper crashes (two handlers in one process fight).
- Symbolication: upload dSYMs for the app and all helpers; Chromium symbols are huge — ship Breakpad `.sym` for the framework only if you build it yourself.

---

## 8. Toasts, downloads, popovers, permission prompts

- **Toast** (Arc's "Copied URL" pill at the sidebar bottom): a SwiftUI view in an `NSHostingView` pinned to the sidebar's bottom, `.glassEffect(.regular.tint(...))` capsule on macOS 26, spring in/out, auto-dismiss 2 s, one at a time (queue), `accessibilityLabel` announced via `NSAccessibility.post(element:notification: .announcementRequested)`. Honor Reduce Motion (fade only).
- **Downloads**: `NSPopover` (`behavior = .transient`) from the sidebar's download icon, content = SwiftUI list of `NSProgress`-backed rows (CEF `CefDownloadHandler::OnBeforeDownload/OnDownloadUpdated`; ArcCore `ArcBrowserContextDownloadsDelegate` incl. `onDeterminingFilename`). Row actions: "Show in Finder" (`NSWorkspace.shared.activateFileViewerSelecting`), open, cancel. Mirror progress on the icon (ring) and bounce the Dock on completion (`NSApp.requestUserAttention(.informationalRequest)`, only if not frontmost).
- **Native vs custom popovers**: `NSPopover` with a SwiftUI content controller gives the system arrow, dismissal and accessibility for free; use it for downloads, site info, extension popups (ArcCore hands extension popups to the host as web contents "for the host to show in an `NSPopover`"). Use a custom overlay only for the palette (needs to be in-window and sized to the sidebar width).
- **Permission prompts**: CEF `CefPermissionHandler::OnShowPermissionPrompt(browser, prompt_id, requesting_origin, requested_permissions, callback)` — return `true` and keep the callback; `OnRequestMediaAccessPermission` likewise for camera/mic; returning `false` lets the Chrome runtime draw its own bubble, which we do not want in a custom chrome ([permission_handler_ctocpp.h](https://third-party-mirror.googlesource.com/cef/+/refs/heads/master/src/libcef_dll/ctocpp/permission_handler_ctocpp.h)). Show an `NSPopover` anchored to the address field (or the tab row when the sidebar is collapsed) with Allow / Block / "Allow this time"; persist decisions per origin in our DB *and* answer the callback. ArcCore's `ArcWebContentsUIDelegate` delivers the same thing as an `ArcPermissionRequest` list with a "quiet UI" hint.
- **Chromium-originated popups** (`window.open`, `target=_blank`): CEF `OnBeforePopup` (deny and open as a tab in our model, or create a dedicated popup window); ArcCore `newWebContents…withDisposition`. Always route through our tab model so popups get a sidebar row.
- **JS dialogs**: `CefJSDialogHandler` → `NSAlert` as a sheet on the window, or an in-card overlay to keep the Dia aesthetic.

---

## 9. Tooling, concurrency, module layout

### 9.1 Project

- **Xcode project + local Swift packages.** cmux (Swift/AppKit, Sparkle, notarized) composes "roughly fifty local Swift Package Manager modules" under `Packages/macOS|iOS|Shared` with a thin `cmux.xcodeproj` ([cmux architecture](https://skills.cat/skills/manaflow-ai/cmux/cmux-architecture), [repo](https://github.com/manaflow-ai/cmux)). Ora generates its project with XcodeGen (`project.yml`) ([the-ora/browser](https://github.com/the-ora/browser)). Tuist is heavier and aimed at large teams/caching ([Tuist](https://docs.tuist.dev/guides/start/new-project)). Recommendation: XcodeGen-generated `.xcodeproj` (so the project file is never hand-edited and diffs are readable) with one app target, five helper targets, and everything else as local SPM packages. Pure SwiftPM cannot produce an `.app` with helper bundles, entitlements and framework embedding; the CEF/Chromium framework is built by CMake/GN outside Xcode and copied in by a script phase.
- CEF bindings: the only Swift binding ([lvsti/cef.swift](https://github.com/lvsti/cef.swift)) stops at Chrome 95/Swift 4.2 — dead. Write our own thin ObjC++ bridge (the ArcCore shape: `NS_SWIFT_UI_ACTOR` ObjC classes over C++), or Rust+UniFFI like browsermux ([possibilities/browsermux](https://github.com/possibilities/browsermux)). ObjC++ is the shorter path for one person.

### 9.2 Swift 6 strict concurrency

- All of AppKit is `@MainActor`. Compile UI packages with `-default-isolation MainActor` (Swift 6.2+ "approachable concurrency"); model/engine packages stay `nonisolated` by default with explicit `@MainActor` on stores observed by UI. The `Observation` framework (`@Observable`) replaces Combine for store → view updates in both AppKit (`withObservationTracking`) and SwiftUI.
- CEF callbacks arrive on CEF's UI thread, which on macOS *is* the main thread (CEF requires the browser UI thread to be the main thread when integrated with `NSApplication`'s run loop). Wrap C++ callback entry points with `MainActor.assumeIsolated { … }` and make every callback-handler class `@MainActor`. ArcCore annotates all its classes `NS_SWIFT_UI_ACTOR` for exactly this reason.
- Known friction: subclassing ObjC types (`NSView`, `NSTableRowView`) in a MainActor-default module is fine; subclassing `NSObject` delegates that AppKit calls from background threads (rare: `NSURLSession`, `NSFileCoordinator`) needs `nonisolated` + `MainActor.assumeIsolated`. `Sendable` conformance for engine value types (URL, tab snapshots) should be the rule; never pass `NSView` across isolation boundaries.
- Swift 6 enforces that overrides cannot be *more* isolated than the superclass declaration; this bites when wrapping third-party ObjC delegates — keep them in a small `nonisolated` shim module.

### 9.3 Testing

- Unit tests (Swift Testing) for the store, palette scorer, session persistence (GRDB in-memory DB), key routing policy, traffic-light geometry. These are the high-value tests.
- Snapshot tests for sidebar rows/toasts in light/dark (e.g. pointfree `swift-snapshot-testing`) to catch material/vibrancy regressions across macOS 26/27.
- XCUITest on macOS uses the same `XCUIApplication`/`XCUIElement` model as iOS; set `accessibilityIdentifier` on every control; wait with `waitForExistence`/`XCTNSPredicateExpectation`, never `sleep` ([tessl xctest-mac notes](https://tessl.io/registry/testland/xcuitest-suite/files/references/macos.md)). The Chromium view is reachable only through Chromium's accessibility tree (CEF exposes it when accessibility is enabled); keep XCUITests to smoke flows (launch, open tab, palette, set default prompt) and run them nightly, not per-commit.

### 9.4 Module layout

```
Packages/
  Engine/            protocol Engine, WebContents, BrowserContext, NavigationDelegate, UIDelegate,
                     PermissionRequest, Download… (pure Swift, no AppKit types except NSView/NSImage)
  EngineCEF/         ObjC++ bridge to CEF; implements Engine
  EngineArcLike/     (later) bridge to a Chromium fork with the same shape
  Model/             GRDB schema, migrations, Space/Tab/History/Favicon records, FTS, frecency
  Store/             @Observable app state: windows, spaces, tabs, selection; session persistence
  Omnibox/           providers, scorer, suggest clients, Ifrit matching
  UIKitCore/         NSWindow subclass, window controller, materials, traffic lights, key router,
                     NSMenu builder, hover-reveal
  Sidebar/           NSOutlineView-based tree, drag/drop, rename, context menus
  Card/              browser container view, clipping/shadow, resize handling
  Palette/           overlay + text field + results (SwiftUI rows)
  Chrome/            toasts, downloads popover, permission popovers, JS dialogs
  Settings/          SwiftUI settings window
  Infra/             Sparkle wrapper, Sentry wrapper, default-browser, URL ingestion, logging
App/                 AppDelegate, main menu, composition root
Helpers/             Helper, Helper (GPU), Helper (Renderer), Helper (Plugin), Helper (Alerts)
```

Dependency rule: `UI* → Store → Model`, `UI* → Engine (protocol only)`, `EngineCEF → Engine`, nothing depends on `EngineCEF` except `App`. The ArcCore delegate list (`arccore-adk-bundle-analysis.md` §2) is the checklist of what `Engine` must eventually expose.

---

## 10. Reference projects (what to borrow)

| Project | Stack | Borrow | URL |
|---|---|---|---|
| Dia / ArcCore (installed, inspected) | Swift app, AppKit shell + SwiftUI leaves, GRDB, Sparkle, Sentry, Lottie; Chromium fork behind ObjC API | The engine/UI boundary (delegate list), entitlements (helpers: `allow-jit` only), `NSVisualEffectView` window, GRDB | `research/notes/arccore-adk-bundle-analysis.md` |
| Beam (beamlegacy) | Swift, SwiftUI + AppKit, WebKit; dev stopped Nov 2022, open-sourced | `BrowserTab.swift` message-handler pattern, test target layout (`BeamTests`, `BeamUITests`, `BeamCoreTests`), fastlane | https://github.com/beamlegacy/beam (the `beamapp/beam` URL 404s; this is the archive) |
| Ora | Swift 5.9, SwiftUI + AppKit, WebKit, XcodeGen, GPL-3, macOS 15+ | `project.yml` structure, vendored SplitView, URL suggestions/quick launcher | https://github.com/the-ora/browser |
| Nook | SwiftUI + AppKit, WebKit, SwiftData, macOS 26, GPL-3; "manager"-based (`BrowserManager`) | Spaces/sidebar model, command palette, split view; its persistence pain is the argument *against* SwiftData | https://github.com/nook-browser/Nook, https://deepwiki.com/nook-browser/Nook/3.3-persistence-architecture-and-swiftdata |
| Luna | Swift 6, pure AppKit, WebKit, macOS 26, GPL-3; Liquid Glass sidebar; Chrome-extension support | Traffic-light manager design and window-state matrix (issue #46), Command Bar | https://github.com/ziadmyassine/luna-browser |
| cmux | Swift + AppKit terminal with vertical tabs/sidebar, ~50 local SPM packages, Sparkle, notarized | Package layering, sidebar drag/auto-scroll fixes, IME-safe menu dispatch (PR #2032) | https://github.com/manaflow-ai/cmux |
| browsermux | Swift/AppKit + Rust (UniFFI) + CEF, recursive panes, sandboxed helpers | How to pin an official CEF build with CMake and host "native Chromium views" from Swift; keyboard "command mode" | https://github.com/possibilities/browsermux |
| Chromium `shell_integration_mac.mm` | — | Exact default-browser API usage and the CoreServicesUIAgent activation trick | https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/shell_integration_mac.mm |
| Chromium entitlement plists | — | Ground truth for helper entitlements | https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/app/ |
| Electron border-radius commit | — | Chromium-side rounded corners as fallback | https://ayakael.net/mirrors/electron/commit/778d3098a0f0bfc00015d54263674318f4adf6b1 |
| ChatGPT Atlas / OWL | Chromium in a separate process from the Swift UI, Mojo IPC | Architectural idea only (out-of-process Chromium); OpenAI's post is 403 to fetch, summary via ByteByteGo | https://blog.bytebytego.com/p/the-architecture-behind-atlas-openais |
| multi.app palette post | AppKit `NSPanel` | Only if we later add a global launcher | https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette |
| Ifrit | Swift fuzzy search | Tabs/commands matching | https://github.com/ukushu/Ifrit |
| GRDB FTS doc | — | History index | https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md |
| WWDC25 310, WWDC26 271 | — | New-design AppKit APIs; SwiftUI reorder APIs on macOS 26 | https://developer.apple.com/videos/play/wwdc2025/310/, https://developer.apple.com/videos/play/wwdc2026/271/ |

Not found / not useful: Orion developer notes on their UI stack (none public); SigmaOS/Sidekick engineering posts (nothing substantive surfaced); a Swift-native CEF binding newer than Chrome 95.

---

## 11. Risks and unknowns

1. **Clipping Chromium's remote layer** (section 3.4): no public source confirms ancestor `masksToBounds` clips `CALayerHost` content, or what it costs. Spike first. Fallback: Chromium-side `SetClipPath`/`RoundedCornersF` (requires a fork or a CEF patch).
2. **Hover-reveal over a layer-hosting Chromium view**: z-order and mouse-tracking fights are plausible; fallback is a child `NSPanel`.
3. **Traffic-light geometry across 26.x/27.x minor releases** (14pt/23pt today). Never hard-code; derive from `standardWindowButton` frames; re-layout on title/fullscreen/appearance changes.
4. **CEF vs fork for the omnibox and session state**: CEF has no `AutocompleteController` and no serialized navigation entries; a fork does (Dia proves it). The palette and restore quality depend on this engine decision (see `cef.md`).
5. **Crash-report plumbing**: whether CEF's Crashpad multipart upload is accepted by Sentry's minidump endpoint unverified.
6. **Passkey entitlement**: `com.apple.developer.web-browser.public-key-credential` requires requesting the capability from Apple; lead time unknown.
7. **Sparkle delta size** with a ~330 MB Chromium framework: measure; if deltas are still >100 MB, consider shipping the framework as a separately updated bundle (Sparkle 2 supports updating external bundles).
8. **SwiftUI leaves on macOS 27**: `.reorderable()` crash reports (June 2026) and focus-system complaints mean any SwiftUI we do use must avoid drag/drop and complex focus; keep it to static/leaf content.
9. **Stage Manager / non-opaque full-size windows**: no documented issues found, but also no evidence; verify shadows and snapping manually.
10. **Default-browser confirmation dialog ordering**: known to appear behind the app; copy Chrome's `CoreServicesUIAgent` activation.
