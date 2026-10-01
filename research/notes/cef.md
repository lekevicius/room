# CEF (Chromium Embedded Framework) as the engine for a Swift/AppKit macOS browser

Research date: 2026-10-01. Sources: CEF repo clone at `research/repos/cef` (master @ ff57d4e, 2026-09-29, tracks Chromium 154.0.8037.0), the in-repo docs (`research/repos/cef/docs/*.md`, which is where the old Bitbucket wiki now lives; the Bitbucket wiki clone at `research/repos/cef-wiki` is a stub that only says "moved"), the Spotify CDN index (`https://cef-builds.spotifycdn.com/index.json`), the official 154.0.32 macOS arm64 minimal distribution (downloaded and inspected), GitHub issues via the API, and the Chrome VersionHistory API.

Repo file paths below are relative to `research/repos/cef/`.

---

## 1. Summary & verdict

**Verdict: CEF is a viable but constrained fit. The single most important fact for this project is that on macOS a browser hosted inside your own NSView (`CefWindowInfo::SetAsChild`) is always an *Alloy-style* browser. Chrome-style (full Chrome UI layer) browsers are only available on macOS through CEF's own Views framework, which creates its own NSWindow.** This is enforced in code, not just documented:

- `include/internal/cef_types_mac.h:150-155`: "Alloy style will always be used if |windowless_rendering_enabled| is true or if |parent_view| is provided." (The Windows/Linux headers lack the `parent_view` clause.)
- `libcef/browser/browser_host_create.cc:231-237`: `#if BUILDFLAG(IS_MAC) if (allow_chrome_style && chrome_child_window::HasParentHandle(new_window_info)) { // Chrome style is not supported with native parent on MacOS. See issue #3294. allow_chrome_style = false; }`
- `tests/ceftests/chrome_child_window_unittest.cc:7-9`: "Chrome style browsers created with a native parent window ... Not supported on MacOS."
- Issue #3294 ("chrome: Add support for embedded non-Views windows", open since 2022-03): the maintainer explains the macOS blocker — Chrome's `NativeWidgetMac`/`NativeWidgetMacNSWindowHost` owns an NSWindow, and the CEF API hands you an NSView; he floats a "placeholder NSView + `addChildWindow`" idea but it has not been implemented in 4.5 years. His 2024-05-09 closing remark: "This is fully supported (all platforms) with Alloy style."

What this means concretely:

- **What you get (Alloy style, Chrome bootstrap):** a real Chromium `WebContents` with Chrome's tab helpers attached (`libcef/browser/alloy/browser_platform_delegate_alloy.cc:206` calls `TabHelpers::AttachTabHelpers`), so autofill/password-manager *logic*, history/visited links, PDF viewer, printing, spellcheck, WebRTC, DevTools, find, zoom, downloads, JS dialogs, file choosers, context menus, cookies/profiles all work; extensions installed in the profile run their content scripts and service workers in Alloy browsers (the `chrome_browser_extensions` patch adds "minimal support for tabs API with Alloy style browsers").
- **What you lose vs. Chrome:** everything anchored to a Chrome `Browser`/`BrowserWindow` object: permission bubbles (default is IGNORE, you must implement `OnShowPermissionPrompt`), autofill/password *save* bubbles (patched to silently no-op when there is no BrowserWindow, `patch/patches/chrome_autofill_bubble_3796.patch`), extension action popups/toolbar, Translate bubble, print preview (default-disabled in Alloy, `--enable-print-preview` re-enables), download bubble (unhandled downloads are *cancelled* in Alloy unless you implement `CefDownloadHandler`), `chrome://extensions`, `chrome://settings` and most other WebUI pages (allow-list in `libcef/browser/alloy/alloy_browser_host_impl.cc:66-93`), zoom/status bubbles, Chrome's tab discarding / Memory Saver. You rebuild all of that UI in Swift, which is arguably what a custom-chrome browser wants to do anyway — but it is a large surface and some pieces (extension popups, Web Store install, Google sign-in/sync) have no good substitute.
- **Build/distribution is easy:** no Chromium build; the official arm64 binary (minimal: 132 MB download, ~322 MB framework on disk, 234 MB main dylib) is linked via a small C++ wrapper; you provide an app bundle with 5 helper apps and sign/notarize with JIT entitlements.
- **Cadence:** CEF 154.0.32 stable (2026-09-29) tracks Chromium 154.0.8037.58, which is the exact build Chrome Stable is serving on macOS today (49.5% of users on .58). CEF only follows *even* milestones; with Chrome's new two-week milestone cadence (since M153, Sept 2026) you are at most one milestone (~2 weeks) behind, then jump.

**Main risks**

1. Alloy-only on macOS NSView: no path to Chrome-style UI features without taking Views' NSWindow. Issue #3294 has no owner.
2. Extension UX: loading extensions works (profile-level, `--load-extension` works in non-branded Chromium), but there is no CEF API for installing/managing them (issue #3450, open since 2023), no Web Store install flow outside a Chrome-style window, and no action-popup hosting for Alloy browsers.
3. Single-maintainer project with very frequent Chromium churn; API versioning (`CEF_API_VERSION`) exists since 2025 to decouple app rebuilds from CEF updates, but behaviour changes with each Chromium major.
4. Memory for "hundreds of tabs": no discard/freeze API; each CefBrowser is a WebContents with its own renderer process (site isolation). You must implement tab unloading yourself (destroy browser, keep URL/state).
5. Windowed browsers are opaque (`CefBrowserSettings.background_color` alpha is ignored for windowed browsers → opaque white); vibrancy *behind* web content is only possible with off-screen rendering (OSR), at a performance/complexity cost. Rounded-corner clipping via a parent layer mask is feasible since the content is a CALayer-backed NSView.
6. Security-fix window: CEF stable branches get "broad security fixes for ~2 weeks after entering the stable channel" (`docs/branches_and_building.md`); you must ship every even milestone promptly.

---

## 2. Current versions & cadence

Sources: `https://cef-builds.spotifycdn.com/index.json` (fetched 2026-10-01), `https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions/all/releases`, `docs/branches_and_building.md`, `CHROMIUM_BUILD_COMPATIBILITY.txt`, the distribution's `README.txt`.

| Item | Value |
|---|---|
| Latest macOS arm64 **stable** CEF | `154.0.32+g682c378+chromium-154.0.8037.58`, built 2026-09-29 |
| Chromium it tracks | 154.0.8037.58 |
| Chrome Stable (mac) today | 154.0.8037.58 at 49.5%, .59/.92 ramping, 155.0.8059.26 at 0.5% (started 2026-09-30) → **CEF is on the same build as the bulk of Chrome Stable; zero-day lag** |
| CEF master | tracks `refs/tags/154.0.8037.0` (`CHROMIUM_BUILD_COMPATIBILITY.txt`); master HEAD 2026-09-29 |
| Download sizes (arm64) | standard 307 MB (`.tar.bz2`), minimal 132 MB. Extracted framework 322 MB; main dylib 234 MB; `Libraries/` = `libcef_sandbox.dylib` (68 KB), `libvk_swiftshader.dylib` (16 MB), `libvulkan.dylib`; Resources = `chrome_100/200_percent.pak`, `resources.pak`, `icudtl.dat`, `v8_context_snapshot.arm64.bin`, `gpu_shader_cache.bin`, ~190 `*.lproj` dirs |
| Supported branches (docs table) | Stable 8037/M154 (Sep 2026), Extended 7977/M152 (Aug 2026), LTC 7871/M150 (Jun 2026), LTS 7559/M144 (Dec 2025) |
| Build requirements for 154 (docs) | macOS 12.0+ deployment, 15.6+ build system, Xcode 26.0 / 26.0 SDK; binary distribution CMakeLists says "Xcode 16+ building on macOS 14.5 or newer", CMake 3.21+, C++20 |
| Min deployment target | `LSMinimumSystemVersion` 12.0 in sample plists; distribution README: Xcode 26 requires the versioned `Versions/A` framework layout (CMake/Bazel configs create it) |

Cadence observed in the index for macosarm64 (first stable build date per branch): 144: 2026-01-20 (26 stable builds through 2026-09-13, LTS) · 145: 02-11 · 146: 03-22 · 147: 04-24 · 148: 05-24 · 149: 06-16 · 150: 07-08 (LTC, still refreshed 09-23) · 151: 07-29 · 152: 09-05 (extended, refreshed 09-24) · **153: skipped** · 154: beta 09-09, stable 09-22, latest 09-29.

Policy (from `docs/branches_and_building.md`): "CEF is currently tracking even-numbered Chromium milestone branches (new CEF branch every ~4 weeks)". Stable = every other milestone from M152, "broad security fixes for ~2 weeks after entering the stable channel"; Extended = every fourth milestone from M152, ~8 weeks of fixes; LTC/LTS = every 12th from M160 (every sixth M138–M150), ~9 months. Chrome itself moved to a two-week milestone cadence starting with M153 on 2026-09-08 (`https://developer.chrome.com/blog/chrome-two-week-release`). Net: a CEF-based product is between 0 and ~2 weeks behind Chrome Stable's milestone, and must adopt each even milestone within ~2 weeks of its release to stay patched (or ride an Extended branch for 8 weeks).

Chrome-154 timeline for reference: Chrome 154.0.8037.17 first served to stable (0.5%) 2026-09-09; CEF 154 beta 2026-09-09, CEF 154 stable 2026-09-22 (lag ≈ 13 days from first early-stable serve; same-build parity by 09-29).

---

## 3. Embedding model on macOS

### 3.1 Process/bundle layout (mandatory)

From `docs/general_usage.md` ("Application Layout → MacOS"), the distribution README, and `tests/cefsimple/CMakeLists.txt.in`:

```
MyApp.app/Contents/
  MacOS/MyApp                                   <- browser process (your Swift app)
  Frameworks/Chromium Embedded Framework.framework   <- unversioned (or Versions/A symlinked for Xcode 26)
      Chromium Embedded Framework               <- 234 MB dylib, loaded at runtime via dlopen
      Libraries/libcef_sandbox.dylib, libvk_swiftshader.dylib, libvulkan.dylib, vk_swiftshader_icd.json
      Resources/*.pak, icudtl.dat, v8_context_snapshot.arm64.bin, gpu_shader_cache.bin, *.lproj, Info.plist
  Frameworks/MyApp Helper.app                   <- renderer/utility sub-processes
  Frameworks/MyApp Helper (GPU).app
  Frameworks/MyApp Helper (Renderer).app
  Frameworks/MyApp Helper (Plugin).app
  Frameworks/MyApp Helper (Alerts).app
```

- The five helper variants come from `CEF_HELPER_APP_SUFFIXES` in `cmake/cef_variables.cmake.in:396-402` (`"::", " (Alerts):_alerts:.alerts", " (GPU):_gpu:.gpu", " (Plugin):_plugin:.plugin", " (Renderer):_renderer:.renderer"`) and are built in a loop in `tests/cefsimple/CMakeLists.txt.in:120-160`, each with its own Info.plist (`LSUIElement=1`, `LSFileQuarantineEnabled`, bundle id suffix) from `tests/cefsimple/mac/helper-Info.plist.in`.
- "The single executable structure is supported on Windows and Linux but not on MacOS." (`docs/general_usage.md` "Entry-Point Function"). `CefSettings.browser_subprocess_path` (`include/internal/cef_types.h:218-227`) defaults to `Contents/Frameworks/<app> Helper.app/Contents/MacOS/<app> Helper`; `framework_dir_path` / `main_bundle_path` can relocate the framework.
- Both plists set `LSEnvironment MallocNanoZone=0` (`tests/cefsimple/mac/Info.plist.in`) — keep this.

### 3.2 Bootstrap in the main process

`tests/cefsimple/cefsimple_mac.mm` (204 lines) is the canonical sequence:

1. `CefScopedLibraryLoader library_loader; library_loader.LoadInMain()` — dlopens `../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework` relative to the executable (`libcef_dll/wrapper/cef_scoped_library_loader_mac.mm:17-19`). Required: "Load the CEF framework library at runtime instead of linking directly as required by the macOS sandbox implementation."
2. `CefMainArgs main_args(argc, argv)`.
3. **Before anything touches `NSApp`**: `[SimpleApplication sharedApplication]` where `SimpleApplication : NSApplication <CefAppProtocol>`; it must implement `isHandlingSendEvent`/`setHandlingSendEvent:` and wrap `sendEvent:` in `CefScopedSendingEvent` (`include/cef_application_mac.h:358-392`). The sample `CHECK([NSApp isKindOfClass:[SimpleApplication class]])`. It also overrides `-terminate:` to route quit through `CloseBrowser(false)` on all browsers instead of `exit()` (long comment at `cefsimple_mac.mm:43-77`) — Chromium needs to leave the run loop for orderly shutdown.
4. `CefSettings settings; settings.no_sandbox = !CEF_USE_SANDBOX; ...` then `CefInitialize(main_args, settings, app, nullptr)`; on `false`, `return CefGetExitCode()` (process-singleton relaunch etc.).
5. Set `NSApp.delegate`, load the main menu nib, create browsers from `CefBrowserProcessHandler::OnContextInitialized`.
6. `CefRunMessageLoop()` (blocks; internally runs `[NSApp run]` through Chromium's MessagePumpNSApplication), then `CefShutdown()`.

`tests/cefclient/cefclient_mac.mm:546-640` is the richer variant (`client::RunMain`), including `MainMessageLoopExternalPump` selection and the `validateUserInterfaceItem:` / `commandDispatch:` plumbing (lines 381-522) for Chrome command IDs (`cef_command_ids.h`, e.g. `IDC_FIND`) routed through the responder chain — relevant if you want Cmd-F/zoom menu items to hit Chromium.

### 3.3 Helper process entry point

`tests/cefsimple/process_helper_mac.cc` (37 lines): `CefScopedSandboxContext sandbox_context; sandbox_context.Initialize(argc, argv)` (dlopens `../../../Chromium Embedded Framework.framework/Libraries/libcef_sandbox.dylib` and starts the Seatbelt V2 sandbox, `libcef_dll/wrapper/cef_scoped_sandbox_context_mac.mm`, `libcef_dll/sandbox/sandbox_mac.mm`), then `CefScopedLibraryLoader::LoadInHelper()`, then `return CefExecuteProcess(main_args, nullptr, nullptr)`. Since M138 the sandbox is a dylib, not a static lib (`docs/sandbox_setup.md` "macOS").

### 3.4 Message loop options on macOS

- `CefSettings.multi_threaded_message_loop` — "only supported on Windows and Linux" (`include/internal/cef_types.h:247-252`). **Not available on macOS.** The CEF UI thread *is* your AppKit main thread.
- Default: `CefRunMessageLoop()` owns `[NSApp run]`. Fine for a Swift app as long as you let CEF start the loop (you cannot use `NSApplicationMain`/`@main` naïvely; call `CefRunMessageLoop` from `main`).
- Alternative: `CefSettings.external_message_pump = true` + `CefDoMessageLoopWork()` driven by `CefBrowserProcessHandler::OnScheduleMessagePumpWork`. Reference implementation: `tests/shared/browser/main_message_loop_external_pump_mac.mm` (NSTimer in `NSRunLoopCommonModes` + `NSEventTrackingRunLoopMode`, `[NSApp run]`/`[NSApp stop:]`). The header warns this is "not recommended for most users" (`include/cef_app.h:106-121`).
- `CefSetOSModalLoop`/nested-loop guard: `include/cef_app.h:142-160` (API ≥ 14100) for AppKit modal loops on the UI thread.

### 3.5 Creating a browser inside an NSView (`SetAsChild`)

`tests/cefclient/browser/browser_window_std_mac.mm:670-688`:

```cpp
CefWindowInfo window_info;
window_info.SetAsChild(parent_handle /* NSView* as cef_window_handle_t */, rect);
if (delegate_->UseAlloyStyle()) window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;  // forced on mac anyway
CefBrowserHost::CreateBrowser(window_info, client_handler_, url, settings, extra_info, request_context);
```

`tests/cefclient/browser/root_window_mac.mm:482-662` shows the host side: create `NSWindow`, `[contentView setWantsLayer:YES]` ("necessary to ensure correct layer ordering of all child views and their layers", line 558-563), add native buttons/URL field, then `CreateBrowser(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(contentView), CefRect(0,0,w,h), ...)`. Coordinates passed to CEF are top-left-origin DIPs (`docs/general_usage.md` "Coordinate Systems").

What libcef does with it (`libcef/browser/native/browser_platform_delegate_native_mac.mm:255-337`): creates a `CefBrowserHostView : NSView` (whose `dealloc` destroys the browser), adds it as a subview of your parent with `NSViewWidthSizable|NSViewHeightSizable` autoresizing, then adds Chromium's `web_contents_->GetNativeView()` NSView inside it. `browser->GetHost()->GetWindowHandle()` returns the `CefBrowserHostView` (`CAST_CEF_WINDOW_HANDLE_TO_NSVIEW`, `include/internal/cef_types_mac.h:49-67`). You resize by resizing the parent; `SetBounds`/`Show`/`Hide`/`SetFocus` are no-ops on mac in cefclient ("Cocoa will size the browser for us", `browser_window_std_mac.mm:723-741`). `CefWindowInfo.hidden` creates the view initially hidden.

Popups (`window.open`, target=_blank): `CefLifeSpanHandler::OnBeforePopup` (`include/cef_life_span_handler.h:60-130`) lets you supply a new `windowInfo.SetAsChild(...)`; cefclient parents new popups to a temporary off-screen window first (`tests/cefclient/browser/temp_window_mac.mm`) and re-parents the NSView after creation (`browser_window_std_mac.mm:706-721 ShowPopup`, `root_window_mac.mm:664-672`). Alloy-style openers produce Alloy-style popups (`browser_host_create.cc:209-220`).

Closing: `CloseBrowser(false)` → JS `onbeforeunload` → `DoClose` → OS close → `OnBeforeClose`; mac-specific sequence documented at `cefsimple_mac.mm:43-77` and `docs/general_usage.md` "Browser Life Span". `root_window_mac.mm:1089-1142` shows `windowShouldClose:` + replacing `contentView` to tear down.

### 3.6 Views framework alternative (`CefWindow`/`CefBrowserView`)

`tests/cefsimple/simple_app.cc:110-190`: `CefBrowserView::CreateBrowserView(...)` + `CefWindow::CreateTopLevelWindow(delegate)`; the delegate chooses `GetWindowRuntimeStyle()`/`GetBrowserRuntimeStyle()`. On macOS a Views `CefWindow` is its own `NSWindow` (`NativeWidgetMac`); `CefWindowDelegate` offers frameless, custom titlebar height, traffic-light positioning, `GetParentWindow` (child/menu windows), `WithStandardWindowButtons` (`include/views/cef_window_delegate.h:109-280`). "Chrome style Windows can host both style BrowserViews ... a Chrome style Window can host at most one Chrome style BrowserView but potentially multiple Alloy style BrowserViews" (`include/internal/cef_types_runtime.h:447-456`). This is the **only** way to get Chrome-style browsers on macOS, and it means your sidebar/tab UI would have to be CEF Views (C++) or a separate overlaid NSWindow, not AppKit views in the same window.

### 3.7 Profiles / "spaces"

`CefRequestContext::CreateContext(CefRequestContextSettings, handler)` (`include/cef_request_context.h:121-135`) creates an isolated profile with its own `cache_path` (must be under `CefSettings.root_cache_path`, `include/internal/cef_types.h:283-324`), cookies (`GetCookieManager`), `persist_session_cookies`, `accept_language_list`, content/website settings, Chrome color scheme, media router. Pass it as the last argument to `CreateBrowser`. Default root on mac: `~/Library/Application Support/CEF/User Data`. The `chrome_browser_profiles` patch makes CEF incognito-style Profiles usable; the `signin_allowed_4276` patch (2026-09-29) "defaults new CEF profiles to sign-in disabled. Embedders can opt in per request context via CefPreferenceRegistrar::SetDefaultPreference."

Keychain: `CefSettings.keychain_service_name/keychain_account_name` (CEF_NEXT API) control the OSCrypt Keychain item name used for cookie/password encryption (`cef_types.h:513-528`).

---

## 4. Feature matrix (Chrome bootstrap, Alloy-style browser hosted in an NSView on macOS)

Legend: **Works** = engine behaviour present; **Works, UI yours** = Chromium does the work but any UI must be built in Swift via the callback named; **Chrome-style only** = needs a Views `CefWindow` with a Chrome-style BrowserView; **Not available**.

| Feature | Status (Alloy style, NSView host) | Source |
|---|---|---|
| Rendering, GPU compositing, WebGL, WebRTC, media | Works (Chromium content layer; ANGLE-Metal + SwiftShader fallback) | distribution README; `docs/general_usage.md` |
| Extensions: loading | **Partial.** No CEF API (old `CefRequestContext::LoadExtension` removed in M128). Extensions live in the Chrome Profile; install via `chrome://extensions` (needs a Chrome-style window), enterprise/policy pre-install, or `--load-extension` (works in non-branded Chromium builds; Google removed it only from Chrome-branded builds in M137). `CefSettings.chrome_policy_id` + `chrome_browser_policy` patch enable policy configuration. | issue #3450 (open); #3685 comment 2024-05-03; `patch/patch.cfg` `chrome_browser_policy`; chromium-extensions PSA |
| Extensions: content scripts, service workers, MV3 APIs in Alloy browsers | **Works (mostly).** Alloy browsers get Chrome tab helpers (`TabHelpers::AttachTabHelpers`), and the `chrome_browser_extensions` patch adds `cef::GetAlloyTabById` so `chrome.tabs` can resolve Alloy browsers ("minimal support for tabs API"); window-dependent fields (window id, tab index) are absent. `CefBrowser::GetIdentifier` "is also used as the tabId for extension APIs" (`include/cef_browser.h:128`). Untested by me: `chrome.windows`, `chrome.sidePanel`, `declarativeNetRequest` scope. | `libcef/browser/alloy/browser_platform_delegate_alloy.cc:206`; `patch/patches/chrome_browser_extensions.patch`; `libcef/browser/chrome/extensions/chrome_extension_util.cc` |
| Extension action popups / toolbar icons / side panel UI | **Not available** in Alloy (no toolbar/BrowserWindow). Chrome-style only. You could host `chrome-extension://<id>/popup.html` in your own CefBrowser, but `chrome.action` context (tab association) would need verification. | architecture; issue #3294 |
| `chrome://extensions`, `chrome://settings`, `chrome://downloads`, etc. | **Blocked** in Alloy browsers except an allow-list (accessibility, blob-internals, chrome-urls, credits, gpu, histograms, indexeddb-internals, license, media-internals, net-export, net-internals, network-error(s), print, process-internals, resources, serviceworker-internals, system, terms, theme, tracing, version, webrtc-internals). | `libcef/browser/alloy/alloy_browser_host_impl.cc:66-93, 563-569` |
| Chrome Web Store install flow | **Not available** outside a Chrome-style window (CWS inline install requires the Chrome `Browser`). Not verified whether CWS works even in CEF Chrome-style windows. | inference from above; open question |
| Password manager / autofill | **Engine works, bubbles suppressed.** Tab helpers attach autofill/password managers; the `chrome_autofill_bubble_3796` patch makes save/update bubbles return null when no BrowserWindow ("alloy: Fix autofill crash after form submission", "...during credit card payment"). Whether the in-page autofill *dropdown* renders for Alloy windowed browsers on mac needs a runtime test. OSCrypt/Keychain storage works. | `patch/patch.cfg`; `patch/patches/chrome_autofill_bubble_3796.patch` |
| Google Translate | **No evidence of support.** Only string resources mention translate; no CEF API; translate bubble is BrowserWindow UI. | `grep -rl translate libcef` |
| Spellcheck | **Works.** Switches `--disable-spell-checking`, `--enable-spelling-service`, `--override-spell-check-lang`; `CefBrowserHost::ReplaceMisspelling/AddWordToDictionary`; context menu exposes suggestions. | `libcef/common/cef_switches.cc`; `include/cef_browser.h:678-684`; `include/cef_context_menu_handler.h` |
| PDF viewer | **Works** (MimeHandlerView guest; `--disable-pdf-extension` to turn off). | `libcef/browser/chrome/extensions/chrome_mime_handler_view_guest_delegate_cef.*`; `alloy_browser_host_impl.cc:546-560` |
| Print / print preview | `Print()` works (system dialog). Print preview **default-disabled** in Alloy; `--enable-print-preview` enables it (`chrome_browser_printing_oop_osr`, `mac_print_preview_modal` patches). `PrintToPDF()` available. | `libcef/browser/browser_platform_delegate.cc:540-565`; `include/cef_browser.h:534-548` |
| Widevine / EME DRM | **Built in, CDM downloaded at runtime.** `enable_widevine=true` and host verification are set in official builds; the CDM is **not bundled** in the distribution (no Widevine files), but the dylib contains Chrome's `widevine_cdm_component_installer.cc` ("Registering Widevine CDM", `WidevineCdm`, `com.widevine.alpha`), i.e. Chrome's component-updater download path is compiled in, and CEF exposes `CefComponentUpdater` (API 14600, issue #4087, Feb 2026) to query/trigger it. **Runtime verification required**: that the component actually downloads into the CEF profile on first use, and that Netflix/Spotify accept playback (VMP/UA). Also note 2025 Widevine changes (persistent licenses removed from desktop CDM in M140; new license-service requirements). | `BUILD.gn:257-262`; `tools/gn_args.py:367-375`; `strings` on the 154.0.32 framework; `include/cef_component_updater.h`; issue #4087; Widevine announcements |
| WebRTC / getUserMedia | **Works, UI yours.** `CefPermissionHandler::OnRequestMediaAccessPermission`; Alloy default *denies* unless handled or `--enable-media-stream`. | `include/cef_permission_handler.h:85-103` |
| Screen sharing (getDisplayMedia) picker | **Unverified** — no desktop-media-picker code in libcef; likely needs Chrome-style or custom handling. | open question |
| Media router / Cast | **API present** (`CefMediaRouter` via `CefRequestContext::GetMediaRouter`). Not tested. | `include/cef_media_router.h`; `include/cef_request_context.h:257` |
| Permission prompts (geo, notifications, camera, etc.) | **Works, UI yours.** `OnShowPermissionPrompt(browser, prompt_id, origin, mask, callback)` + `OnDismissPermissionPrompt`. Alloy default = IGNORE because "the Views prompt would dereference a null BrowserWindowInterface". | `include/cef_permission_handler.h:105-140`; `libcef/browser/permission_prompt.cc:277-326` |
| Find in page | **Works, UI yours.** `CefBrowserHost::Find/StopFinding` + `CefFindHandler`. | `include/cef_browser.h:550-569` |
| Zoom | **Works.** `SetZoomLevel/GetZoomLevel`; Chrome zoom bubble is Chrome-style only (`chrome_zoom_bubble`). | `include/cef_browser.h:482`; `cef_types.h:737-741` |
| Context menus | **Works** — native `NSMenu` runner for Alloy (`menu_runner_mac.mm`), customizable via `CefContextMenuHandler`; Chrome's `RenderViewContextMenu` is bypassed for Alloy. | `libcef/browser/native/menu_runner_mac.mm`; `libcef/browser/chrome/chrome_context_menu_handler.cc:355-363` |
| Downloads | **Works, UI yours.** Must implement `CefDownloadHandler` (`OnBeforeDownload`/`OnDownloadUpdated`); unhandled downloads are **cancelled** in Alloy style. | `libcef/browser/download_manager_delegate_impl.cc:460-468`; `include/cef_download_handler.h:112` |
| JS dialogs (alert/confirm/prompt/beforeunload) | **Works** — default native NSAlert runner; override with `CefJSDialogHandler`. | `libcef/browser/native/javascript_dialog_runner_mac.mm` |
| File chooser | **Works** — native NSOpen/SavePanel; override via `CefDialogHandler::OnFileDialog`; `RunFileDialog` API. | `libcef/browser/file_dialog_*`; `include/cef_browser.h:485-506` |
| HTTP auth | **Works, UI yours** via `CefRequestHandler::GetAuthCredentials` (IO thread). In Chrome style the Chrome login prompt wins unless `--disable-chrome-login-prompt` (issue #3603). | `include/cef_request_handler.h:152-165`; `cef_switches.cc` |
| Certificate errors | **Works, UI yours** via `OnCertificateError`; Chrome error pages are enabled by default under the Chrome bootstrap. | `include/cef_request_handler.h:176-185`; issue #3685 |
| Popups / new windows | **Works** via `OnBeforePopup` (+ `OnBeforePopupAborted`); you re-parent into your own NSView. Document PiP opens a default Alloy window unless disabled. | `include/cef_life_span_handler.h:60-130`; #3685 comment 2024-05-02 |
| DevTools in your own NSView | **Works.** `ShowDevTools(windowInfo.SetAsChild(myNSView,...), client, settings, inspect_at)`; "DevTools popups are Chrome style only (cannot be windowless)" — i.e. the DevTools *browser* is created through Chrome's `DevToolsWindow` (`chrome_browser_devtools_osr` patch), native-parent support added in #3600. | `include/cef_browser.h:571-590`; `libcef/browser/devtools/devtools_window_runner.cc` |
| Session/cookie persistence | **Works** with `cache_path`/`root_cache_path`; `persist_session_cookies`. localStorage etc. only persist with a cache path. | `cef_types.h:283-336`; `docs/general_usage.md` "CefSettings" |
| Multiple profiles | **Works** — `CefRequestContext::CreateContext`, per-context cache path, cookies, settings. | `include/cef_request_context.h` |
| Multiple browsers side by side in one NSWindow | **Works** (each `CreateBrowser` adds an NSView under your parent; cefclient only does one per window but nothing restricts it). | `browser_platform_delegate_native_mac.mm:255-337` |
| Hidden browsers (background tabs) | Hide the `CefBrowserHostView` (NSView `hidden`) or remove from the hierarchy; Chromium's `RenderWidgetHostViewMac` stops compositing occluded views. No CEF discard/freeze API; `WasHidden()` is OSR-only. Memory stays resident per browser. | `include/cef_browser.h:700-707`; no `discard` in libcef |
| Tab discarding / Memory Saver | **Not available** (Chrome's TabLifecycleUnit is tied to `TabStripModel`; Alloy browsers are not tabs). Roll your own: destroy browser, keep URL + `GetNavigationEntries` snapshot. | `patch/patches/chrome_browser_extensions.patch` comment "which doesn't exist for an Alloy style browser"; grep |
| Off-screen rendering (transparency, custom compositing) | Available (Alloy only). Mac `cef_accelerated_paint_info_t` carries an IOSurface; sample Metal renderer `tests/shared/browser/osr_renderer_metal.mm`; header comment on `shared_texture_enabled` still says "Currently only supported on Windows (D3D11)" — verify. | `include/internal/cef_types_mac.h:131-183`; `libcef/browser/osr/browser_platform_delegate_osr_mac.mm` |
| Accessibility (VoiceOver) | Works via `SetAccessibilityState`; cefclient detects VoiceOver (`AXEnhancedUserInterface`). | `cefclient_mac.mm:151-161`; `root_window_mac.mm:774-785` |
| Chrome commands (`ExecuteChromeCommand`) | **Chrome-style only.** | `include/cef_browser.h:1037-1056` |
| Task manager, chrome://settings UI, profile menu, sign-in, sync | Chrome-style only / not available; sign-in default-disabled per profile (M154+). | `signin_allowed_4276` patch; `cef_types.h` |

---

## 5. Gaps vs. full Chrome a daily-driver user would notice

1. **No Google account sign-in / Chrome Sync.** CEF never shipped sign-in (no API keys/branding); the 2026-09-29 patch `signin_allowed_4276` sets new profiles to sign-in disabled by default and stops Gaia ListAccounts polling. Bookmarks/history/passwords sync must be your own.
2. **No Chrome Web Store install flow** in an NSView-hosted browser; no chrome://extensions page; no programmatic install API (issue #3450 open since Feb 2023). Realistic path: ship/download CRX or unpacked extensions and load them via `--load-extension` (supported in non-branded builds) or policy (`ExtensionInstallForcelist` via `chrome_policy_id`), and build your own management UI. Extension *popups* and toolbar badges have no host.
3. **No permission bubbles, save-password/address bubbles, translate, zoom/status bubbles, download shelf** — all become Swift UI you write (callbacks exist for permissions, downloads, find, zoom; nothing for translate or password-save decisions beyond what the engine auto-does).
4. **Print preview** off by default in Alloy (system dialog instead) unless `--enable-print-preview`.
5. **Widevine**: CDM not bundled; Chrome's component-installer code is present in the dylib and should fetch it at runtime (`CefComponentUpdater` can trigger/inspect), but VMP/UA acceptance by Netflix is untested. "Enable Widevine CDM host verification and storage ID" is in the official GN args; whether the official binaries are signed in a way Widevine's VMP accepts must be verified empirically (your re-signing of the framework may matter).
6. **Memory management**: no Memory Saver / discarding / freezing; hundreds of live CefBrowsers = hundreds of WebContents and (with site isolation) many renderer processes. You must unload yourself.
7. **Odd Chromium milestones are skipped** (e.g. 153 never shipped); you are up to one milestone behind, and patch support for a stable CEF branch is ~2 weeks after it goes stable.
8. **Google API keys**: default keys were removed years ago; geolocation, safe browsing lookups, spelling service etc. need your own keys (`docs/general_usage.md` / legacy notes).

---

## 6. Swift interop approach

- **Existing bindings are dead.** `lvsti/CEF.swift`: last supported branch 4638 (Chrome 95, 2021), Swift 4.2, x86_64 only, README: "incomplete, untested, and most likely unstable" (104 stars). `SyberToto/CEF.swift` is a fork at the same vintage. No maintained 2024–2026 Swift binding was found.
- **CEF's public ABI is a C API** (`include/capi/*.h`) with a generated C++ wrapper (`libcef_dll_wrapper`). Swift can import the C API directly through a bridging header or a Clang module, but the C API requires manual ref-counting and struct-of-function-pointers vtables (`docs/using_the_capi.md`, 1741 lines) — workable but tedious.
- **Recommended pattern:** an Objective-C++ (`.mm`) framework target that links `libcef_dll_wrapper` and exposes a small ObjC API (`RoomBrowserView: NSView`, delegate protocols for navigation/permissions/downloads/popups, `RoomProfile` wrapping `CefRequestContext`), consumed from Swift. The CEF samples already mix ObjC and C++ in exactly this way: `tests/cefclient/browser/root_window_mac.mm` (ObjC `RootWindowDelegate` + C++ `RootWindowMacImpl`), `browser_window_std_mac.mm`, `tests/shared/browser/main_message_loop_external_pump_mac.mm` (ObjC `EventHandler` calling C++), `tests/cefsimple/cefsimple_mac.mm`. Build with `-fobjc-arc` (cefsimple's `OPTION_USE_ARC`, `tests/cefsimple/CMakeLists.txt.in:91-96`; the `CAST_*` macros in `cef_types_mac.h` are ARC-aware).
- **Swift-specific bootstrap constraints:** `NSApplication` subclass must conform to `CefAppProtocol` (ObjC protocol; a Swift subclass can implement `isHandlingSendEvent`/`setHandlingSendEvent` and reimplement the `CefScopedSendingEvent` save/set/restore in `sendEvent(_:)`), must exist before any `NSApp` access, and `main` must call `CefRunMessageLoop()` instead of `NSApplicationMain`. Override `terminate(_:)` per `cefsimple_mac.mm:43-85`. All CEF handler callbacks arrive on the CEF UI thread == main thread except IO-thread ones (`GetAuthCredentials`, resource handlers) — marshal to main for AppKit.
- **API stability:** define `CEF_API_VERSION=15400` (or similar) to compile against the Stable API and allow swapping CEF binaries without recompiling (`docs/api_versioning.md`); experimental API (default) is tied to the exact CEF build.

---

## 7. Build & packaging

- **No Chromium build required.** Use the Spotify-built binary distribution (standard or minimal). Building Chromium yourself is only needed for custom patches or `cef_sandbox`/bootstrap changes (`docs/branches_and_building.md`, `docs/sandbox_setup.md`).
- **Targets:** the distribution's `CMakeLists.txt` adds `libcef_dll/CMakeLists.txt` → static lib `libcef_dll_wrapper` (generated C++→C glue), plus `tests/cefsimple`, `tests/cefclient`, `tests/ceftests`. Your app links `libcef_dll_wrapper` only; the framework is **not** linked (dlopen at runtime). Mac flow in `tests/cefsimple/CMakeLists.txt.in:86-175`: `add_executable(... MACOSX_BUNDLE)`, `COPY_MAC_FRAMEWORK` (`cmake/cef_macros.cmake.in:219-241`) copies the framework into `Contents/Frameworks` and creates the `Versions/A` symlink layout Xcode 26 wants, then the helper-app loop. Bazel is also supported (experimental, issue #3757). Requirements: CMake ≥ 3.21, C++20, Xcode 16+ on macOS 14.5+ (distribution `CMakeLists.txt:52-55`).
- You can keep an Xcode/SwiftPM project and either vendor the CMake-built `libcef_dll_wrapper.a` + headers, or reproduce the bundle-assembly steps as Xcode build phases.
- **Sandbox:** `-DUSE_SANDBOX=ON` (default) defines `CEF_USE_SANDBOX`; helper `main` must call `cef_sandbox_initialize` before loading the framework; ship `Libraries/libcef_sandbox.dylib` (M138+). Disabling (`settings.no_sandbox = true`) is possible but inappropriate for a daily-driver browser.
- **Code signing / notarization:** the official framework is **ad-hoc, linker-signed** (`codesign -dvv`: `Signature=adhoc`, `TeamIdentifier=not set`, `flags=0x20002(adhoc,linker-signed)`, `Sealed Resources=none`). You must re-sign the framework, its `Libraries/*.dylib`, the five helper apps and the main app with your Developer ID, hardened runtime, and timestamps (inside-out order). The CEF repo contains no entitlement files or signing scripts (grep for `entitlement|codesign|notariz` finds only "Prevent Xcode 11 from doing automatic codesigning" in `cmake/cef_variables.cmake.in:380`). Community practice (consistent with Chromium's own helper entitlements): main app + helpers get `com.apple.security.cs.allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation` (needed because the framework/helpers may not share the exact validation chain), and typically `allow-dyld-environment-variables`; the Renderer helper is the one that needs JIT, GPU helper may not. Add `com.apple.security.device.camera/microphone` + `NSCameraUsageDescription` etc. for WebRTC. Then `notarytool` + staple. Verify the exact entitlement set empirically — it is not documented by CEF.
- Framework resources on macOS are always loaded from the bundle (`locales_dir_path` is ignored on mac; `docs/general_usage.md` "CefSettings"). Only ship the `.lproj` dirs you need to cut size.
- The Windows-only bootstrap/installer machinery (`docs/installer.md`, shared CEF installs, auto-update) does not exist for macOS; you ship the full framework in every build (≈320 MB uncompressed; ~130 MB compressed with minimal + pruned locales is a reasonable estimate, verify).

---

## 8. Pitfalls (macOS-specific)

1. **Alloy forced for NSView hosting** (section 1). Don't plan on any Chrome-UI feature appearing inside your window.
2. **No multi-threaded message loop on macOS**; CEF UI thread is the AppKit main thread. Long CEF callbacks block your UI and vice versa. Nested AppKit modal loops on the UI thread need `CefSetOSModalLoop`/the API-14100 nested-loop flag (`include/cef_app.h:142-160`).
3. **`NSApplication` subclass + `CefAppProtocol` + `terminate:` override are mandatory**; `NSApplicationMain`-style Swift `@main` does not work unmodified.
4. **Layer-backing:** CEF/cefclient set `wantsLayer = YES` on the parent ("necessary to ensure correct layer ordering", `browser_platform_delegate_native_mac.mm:298-301`, `root_window_mac.mm:558-563`). Chromium's content view is a CALayer tree fed by IOSurfaces from the GPU process. Clipping with `layer.cornerRadius` + `masksToBounds` on an ancestor layer should work (same mechanism Electron uses for rounded `BrowserWindow`s), but **web content itself is opaque** — windowed browsers ignore transparent `background_color` ("the default value of opaque white [will] be used", `cef_types.h:436-449`). Vibrancy/blur *behind* page content therefore requires OSR, or accepting an opaque page area within a vibrant chrome. Verify corner clipping on macOS 26 with a prototype; AppKit `NSVisualEffectView` + mask images is the Electron approach.
5. **Occlusion/visibility:** hidden NSViews stop compositing (Chromium `viewDidHide`/occlusion), but nothing frees memory. `CalculateNativeWinOcclusion` discussion in #3685 is Windows-only.
6. **Popups/select dropdowns** are separate NSWindows positioned relative to the view; `NotifyMoveOrResizeStarted` is Windows/Linux only (`include/cef_browser.h:796-801`); moving the parent window while a `<select>` is open may leave it detached (an earlier fix was reverted in #3426).
7. **Focus/key handling:** cefclient forwards `windowDidBecomeKey/ResignKey` to `SetFocus` and relies on Chromium's `CommandDispatcher` for menu items (`cefclient_mac.mm:381-522`); Cmd-F etc. need `commandDispatch:` wiring (issue #3462 history).
8. **Shutdown ordering** is subtle (`cefsimple_mac.mm:43-77`): all browsers must close before `CefQuitMessageLoop`; the `CefBrowserHostView` dealloc destroys the browser, so never let AppKit release it unexpectedly.
9. **Apple Silicon / macOS 26:** official builds are arm64-native; 154 branch requires Xcode 26 SDK and ships the `Versions/A` layout for Xcode 26. A third-party report (Adobe Dreamweaver, an older CEF) shows SIGTRAP crashes in CEF's Rust font bridge (`fontations_ffi`) on macOS 26.4 — likely fixed in current Chromium but worth a soak test on 26.x. Nothing macOS-27-specific found (today is 2026-10-01; Darwin 27.0 is what this machine runs — test early betas each cycle since Chromium tracks SDKs aggressively).
10. **`MallocNanoZone=0`** must be in `LSEnvironment` for main and helper plists.
11. **Minimum macOS 12.0** deployment for 154 (sample plists and docs table).
12. **Document PiP** can't be disabled per-browser; handle `CEF_WOD_NEW_PICTURE_IN_PICTURE` in `OnBeforePopup` or `--disable-features=DocumentPictureInPictureAPI` (#3685 comment).
13. **GCM/Gemini/Lens**: CEF disables several Chrome features by default (`components_gcm_disable` patch; `chrome_main_delegate_cef.cc:375-382` disables `kGlicActorUi`, `kAutofillActorMode`, `kLensOverlay`), so expect divergence from Chrome on anything that depends on Google services.
14. **Single maintainer** (Marshall Greenblatt) and a 117-patch Chromium patch set (`patch/patch.cfg`); regressions after each Chromium roll are common, and the macOS native-parent path is the least-exercised configuration (cefclient defaults to Views + Chrome style).

---

## 9. Comparison with forking Chromium (brief)

A Chromium fork that re-implements `BrowserWindow`/`BrowserView` natively in AppKit would retain the Chrome `Browser` object and therefore everything CEF Alloy style loses on macOS: permission/autofill/password/translate bubbles as data you re-render, extension action popups and `chrome.windows`/`sidePanel` APIs, `chrome://extensions`/settings/downloads WebUI, Chrome Web Store install, Memory Saver/tab discarding and freezing, print preview, screen-share picker, Chrome's own sign-in/sync plumbing (keys permitting), zero milestone lag and odd milestones. The cost is a 30+ GB checkout, multi-hour builds, maintaining patches against Chrome's 2-week cadence, and owning signing/sandbox/entitlements for ~10 helper binaries. CEF gives you most of the engine with none of the build burden but freezes the UI surface at "content layer + tab helpers + your callbacks", and on macOS specifically it cannot put a Chrome-style browser into your NSView. If extension popups, Web Store, Memory Saver, or native vibrancy behind content are must-haves, the fork is the stronger path; if a curated extension set, custom UI for every prompt, and ~2-week engine lag are acceptable, CEF gets a working browser dramatically sooner.

---

## 10. Open questions (need prototypes or maintainer answers)

1. Does the autofill/password **dropdown** (not the bubbles) render for an Alloy windowed browser on macOS? (Patch 3796 only covers bubbles.)
2. Do extension **content scripts and MV3 service workers** run against Alloy browsers with no caveats, and which `chrome.*` APIs fail without a `Browser` window (`chrome.windows`, `chrome.sidePanel`, `chrome.action.openPopup`)? Can `chrome-extension://…/popup.html` be hosted in a CefBrowser with correct tab context?
3. Does `--load-extension`/policy install work with the CEF Chrome bootstrap on macOS (no Chrome-style window ever created)? Any user-data-dir or `chrome_policy_id` prerequisites?
4. **Widevine**: does the CDM component register/download in CEF 154 on macOS (via `CefComponentUpdater`), and do Netflix/Spotify accept playback (VMP, UA)?
5. Rounded-corner masking of the `CefBrowserHostView` under macOS 26 — any hit-testing or IOSurface layer issues?
6. Realistic memory per hidden Alloy browser and process-count behaviour for 100+ browsers across a few `CefRequestContext`s; strategy for an app-level discard.
7. `getDisplayMedia` picker behaviour in Alloy style on macOS.
8. Can a Views `CefWindow` (Chrome style) be driven as a child NSWindow positioned over a placeholder NSView (the maintainer's #3294 idea) well enough to host DevTools/extension popups without owning the main chrome?
9. Exact hardened-runtime entitlement set per helper that passes notarization with the sandbox enabled on macOS 26.
10. Does the CEF Chrome bootstrap create any Chrome-level singletons (process singleton lock, `Local State`) that conflict with running alongside Google Chrome using the same `root_cache_path` conventions? (Default root is `~/Library/Application Support/CEF/User Data` — set your own.)

---

## Key source pointers (quick index)

- Style selection on mac: `libcef/browser/browser_host_create.cc:170-266`; `include/internal/cef_types_mac.h:94-156`; `include/internal/cef_types_runtime.h`
- NSView embedding: `libcef/browser/native/browser_platform_delegate_native_mac.mm:33-120, 255-350`; `tests/cefclient/browser/browser_window_std_mac.mm`; `tests/cefclient/browser/root_window_mac.mm`
- Bootstrap: `tests/cefsimple/cefsimple_mac.mm`; `tests/cefsimple/process_helper_mac.cc`; `tests/cefclient/cefclient_mac.mm`; `include/cef_application_mac.h`; `include/wrapper/cef_library_loader.h`; `include/cef_sandbox_mac.h`
- Message loop: `include/cef_app.h:64-160`; `tests/shared/browser/main_message_loop_external_pump_mac.mm`; `include/internal/cef_types.h:247-265`
- Alloy feature gating: `libcef/browser/permission_prompt.cc`; `libcef/browser/download_manager_delegate_impl.cc:460-468`; `libcef/browser/browser_platform_delegate.cc:540-565`; `libcef/browser/chrome/chrome_context_menu_handler.cc`; `libcef/browser/alloy/alloy_browser_host_impl.cc:60-100, 540-575`; `libcef/browser/alloy/browser_platform_delegate_alloy.cc:180-230`
- Patches: `patch/patch.cfg` (117 entries; notably `chrome_browser_extensions`, `chrome_autofill_bubble_3796`, `chrome_browser_permission_prompt`, `signin_allowed_4276`, `component_updater_4087`, `chrome_browser_policy`)
- Docs: `docs/general_usage.md`, `docs/architecture.md`, `docs/sandbox_setup.md`, `docs/branches_and_building.md`, `docs/api_versioning.md`, `docs/tutorial.md`
- Issues: #3294 (native parent + Chrome style; mac unsupported), #3681 (style/bootstrap split), #3685 (Alloy bootstrap removal M128), #3450 (extension management API), #4087 (component updater), #3603 (auth prompt), #3462 (mac Find shortcuts)
- Downloads: `https://cef-builds.spotifycdn.com/index.html`; Chrome versions: `https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions`
