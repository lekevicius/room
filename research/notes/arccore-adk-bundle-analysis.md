# ArcCore / ADK: what the installed Arc and Dia bundles reveal

Date: 2026-10-01. Source: direct inspection of `/Applications/Arc.app` (1.160.0) and `/Applications/Dia.app` (1.51.0) on this Mac with `otool`, `nm`, `strings`, `codesign`, `plutil`. The ArcCore public headers shipped inside Dia were copied to `research/repos/arccore-headers/` for study (proprietary; do not redistribute, do not copy code; API *shape* is what we learn from).

## 1. The big picture

The Browser Company's "ADK" (Arc Development Kit) is **not** a Chromium fork with a modified Chromium UI. It is:

1. A Chromium fork compiled into a single framework, `ArcCore.framework` (bundle id `company.thebrowser.browser.framework`), with the usual Chromium helper apps inside it.
2. A hand-written plus code-generated **Objective-C API layer** (`arc/browser/objcpp/*.h`, 204 headers, ~7,000 lines) exported from that framework via an umbrella header and a `module.modulemap`, so Swift imports it as `import ArcCore`.
3. A completely separate **Swift app** (`Dia`, `Arc` executables, ~130-160 MB each) that owns the `NSApplication`, all windows, and the whole UI, and talks to Chromium only through that ObjC API.

So Arc and Dia are literally "a Swift Mac app that embeds a Chromium framework through a WebKit-style API". That is exactly the shape we want.

Evidence:
- `Dia.app/Contents/MacOS/Dia` links `@executable_path/../Frameworks/ArcCore.framework/Versions/A/ArcCore`, plus AppKit, SwiftUI, Combine, GRDB, Lottie, Sparkle, Sentry. No other Chromium pieces.
- `ArcCore.framework/Versions/A/` contains `ArcCore` (binary), `Headers/ArcCore.h` + `Headers/arc/browser/objcpp/`, `Modules/module.modulemap`, `Helpers/` (Browser Helper.app, Browser Helper (GPU).app, Browser Helper (Renderer).app, Browser Helper (Alerts).app, `app_mode_loader`, plus "Aperitif" AI helper variants in Dia), `Libraries/` (libvk_swiftshader, libvulkan, MEIPreload, PrivacySandboxAttestations…), `Resources/` (`chrome_100_percent.pak`, locale `.lproj`s, DevTools).
- ArcCore in Dia 1.51 is Chromium `154.0.8037.93` (`Chrome/154.0.8037.93` UA string, `SCMRevision … refs/branch-heads/8037`), built with Xcode 26.5 / macOS 26.5 SDK. Arc 1.160 ships an older ArcCore (7922 = Chromium ~140), and Arc's copy has **no Headers directory** (headers are stripped in Arc; Dia shipped them, probably by accident).
- Framework size: ~330 MB. Dia.app total 1.3 GB (includes MLX models etc.), Arc.app 850 MB.

## 2. The API surface (the engine/UI boundary they chose)

Top-level objects (all `NS_SWIFT_UI_ACTOR`, i.e. main-actor-isolated for Swift):

| ObjC class | Chromium concept | Notes |
|---|---|---|
| `ArcBrowserApplication` | the browser process (`BrowserMainParts`/`BrowserProcess`) | `initialize:(ArcBrowserApplicationConfiguration*)` with argc/argv, profile path, app id, session restoration policy; `run` (runs Chromium's main loop, i.e. Chromium drives `NSApplication`); `tryToTerminate:`; create/load/delete browser contexts; feature flags; import from other browsers; task manager; histograms; GPU log; encryption key; ad-block lists; URL loader. |
| `ArcBrowserContext` | `Profile` | preferences, history, downloads, extensions, bookmarks model (full CRUD + observer), favicons (favicon service read/write), cookies, local storage, site/content settings, autocomplete controller factory, page content extraction, import, `createWebContents:`. |
| `ArcBrowser` | `Browser` (the thing extensions' `chrome.tabs`/`chrome.windows` see) | `setWindow:(NSWindow*)`, create/take ownership of web contents, omnibox `autocomplete:` (full Chromium `AutocompleteController` with inline autocomplete, keywords, deletable matches), extension action/popup plumbing, session restore of tabs, cookies. One per window. |
| `ArcWebContents` | `content::WebContents` + tab helpers | navigation controller, back/forward list, find, zoom, print/save, JS execution, capture (viewport/full page/region), discard/freeze votes, PDF controller, media session + PiP, DevTools (incl. raw CDP), translate, color filter/scheme, stylesheet injection (Boosts), thumbnails, accessibility tree, `nativeView`, `createPaneHostView`/`attachToPaneHostView:`. Observable properties: title, url, favicon (`NSImage`), isLoading, loadProgress, themeColor, rootBackgroundColor, canGoBack/Forward, state (alive/discarded/frozen), audible/muted, tabTraits, errorStatus, hasDirtyTextField… |

Delegates the Swift side implements (this list is effectively "every piece of Chrome UI that must be rebuilt natively"):

- `ArcWebContentsUIDelegate` (258 lines): activate/select, close, **new web contents (popups / target=_blank) with disposition**, fullscreen enter/exit, pointer lock, status text (link hover), **context menu** (`ArcMenuModel` tree given to you; you build the `NSMenu`), **address/credential/credit-card save prompts** (autofill + password manager UI is native), JS alert/confirm/prompt, beforeunload, security state changes, **permission requests** (`ArcPermissionRequest` list + quiet UI reason, completion with response type), overscroll/swipe nav hooks, **extension install/uninstall consent**, audible/mute state, WebUI dialogs, auxiliary windows, external protocol dialog, HTTP auth login dialog, blocked popups, consumed keys (keyboard shortcut arbitration), translate bubble/progress/error, hung renderer dialog, process gone / render view ready, high background CPU, DevTools toolbox placement, PDF rendered, WebUI shown, confirm infobars.
- `ArcWebContentsNavigationDelegate`: `decidePolicyForNavigationAction:` (link activated / form / back-forward / reload; disposition) – used for Air Traffic Control-style routing.
- `ArcBrowserDelegate`: extension popups (`didOpenExtensionPopup:webContents:` + resize/close), toolbar actions list, new/restored web contents, fullscreen state, tab groups bridge for the `chrome.tabGroups` extension API, extension permission requests.
- `ArcBrowserContextDelegate`: show/close DevTools, extension permission prompt, session restore lifecycle.
- `ArcBrowserContextDownloadsDelegate`: created/updated/removed, `onDeterminingFilename` (you choose the path).
- `ArcBrowserContextExtensionsDelegate`, `ArcBrowserContextHistoryDelegate`, `ArcBrowserContextPreferencesObserver`, `ArcBookmarkModelObserver`, `ArcWebContentsMediaSessionDelegate`, `ArcWebContentsDevToolsDelegate`, `ArcImportDelegate`, `ArcAccessibilityObserver`, `ArcNotificationCenter`.

Also notable:
- `ArcBrowserApplication.h` includes `CrAppProtocol` / `CrAppControlProtocol`: the Swift app's `NSApplication` subclass must implement Chromium's `isHandlingSendEvent` protocol (copied from `//base/message_loop/message_pump_apple.h`). This is a known requirement for embedding Chromium's message pump in a Cocoa app (CEF has the same requirement: `CefAppProtocol`).
- `ArcWebContentsConfiguration`: `transparentBackground`, `initiallyHidden`, `forcedViewSize`, `initiallyMuted`, `disallowAutoplay`, `forceDisplayPDFInline`, `disallowContextMenus`. Hidden web contents are used for background scraping.
- `ArcBrowserType`: Normal, Popup, AppPopup, PictureInPicture (document PiP).
- Extensions: `installExtensionFromWebstore:unattended:`, `installExtensionFromUnpackedPath:`, pinned order, commands, toolbar actions with icons, popups delivered as `ArcWebContents` for the host to show in an `NSPopover`. So the Chrome Web Store install flow works in their fork.
- Omnibox: they expose Chromium's real `AutocompleteController` (history, bookmarks, search suggest, keyword search, tab match, inline autocomplete). This is a big feature we would otherwise have to rebuild.
- Translate (Chrome's translate component), password manager, autofill, PDF viewer, print, DevTools (with CDP), session service, tab discarding/freezing all exist and are exposed.
- The newer headers have comments like "auto-generated from `web_contents.mojom` … `//arc/bindings:objc_copy_artifacts`": they moved to generating the ObjC bindings from mojom IDL. For us, hand-written ObjC++ is fine at first.
- `Resources/arc/services/*/public/mojom/*.mojom-c_api.h` show a C API for out-of-process AI services ("Aperitif"). Irrelevant for v1.

## 3. UI stack used by the Swift apps

From undefined symbols in `Dia` and `Arc` binaries:
- AppKit classes used: `NSWindow`, `NSWindowController`, `NSPanel`, `NSViewController`, `NSView`, `NSVisualEffectView`, `NSCollectionView` (+ layouts), `NSOutlineView`, `NSTableView`, `NSSplitView(Controller)`, `NSStackView`, `NSScrollView`, `NSTextField`, `NSToolbar(Item)`, `NSPopover`, `NSMenu(Item)`, `NSMenuItemBadge`.
- SwiftUI: ~1,500-1,600 symbol references in each binary. Internal Swift modules in Dia include `ARCUI` (their design system), `TabSurface`, `Motion`, `UnboxingUI`, `Preferences`, `AssistantPanelUIBase`, plus `SwiftSoup`, `Fuzi` (HTML/XML parsing), `Highlightr`, `EventSource`, `MLX*`, `OpenTelemetryApi`, `Datadog`.
- Libraries: GRDB (SQLite) for app state, Lottie for animations, Sparkle 2.9.4 for updates (`SUFeedURL` appcast), Sentry for crashes.
- So: **AppKit shell + SwiftUI content** hybrid. `NSVisualEffectView` for the blurred window material. Not pure SwiftUI, not pure AppKit.

## 4. Signing / entitlements

- Dia.app: Developer ID, hardened runtime (`flags=0x10000(runtime)`), entitlements: `com.apple.developer.web-browser.public-key-credential` (passkeys/WebAuthn as a browser), `com.apple.developer.associated-domains`, camera, audio-input, location, keychain-access-groups. **No App Sandbox** (as expected for a Chromium browser).
- Renderer and GPU helper apps: only `com.apple.security.cs.allow-jit`.
- `LSMinimumSystemVersion` 14.0.

## 5. Lessons for our project

1. The architecture is proven at scale: Swift app + Chromium framework behind an ObjC API, with *all* browser UI (dialogs, prompts, menus, popups, bubbles) delegated to the host. We should build the same boundary. The ADK header list is an excellent checklist of what the host must implement for a complete daily-driver browser.
2. The non-trivial value of a real Chromium fork over CEF is visible in the headers: omnibox `AutocompleteController`, extensions with Web Store install + action popups + commands, password manager / autofill save prompts, translate, session service, tab discard/freeze, PDF controller, media session / PiP, DevTools CDP. Whether CEF's Chrome bootstrap exposes enough of these is the central engine decision (see `cef.md`).
3. Their Chromium is built with the current Xcode and tracks Chromium stable closely (Dia 1.51 on Chromium 154 = current stable as of Oct 2026). A one-person fork must plan for a 4-week rebase cadence.
4. Hybrid AppKit + SwiftUI is what the best-looking Mac browser team chose; we don't need to be purists.
5. GRDB + Sparkle + Sentry is a sane, boring stack for a Mac app and we can adopt the same.
