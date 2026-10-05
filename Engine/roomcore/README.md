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
| `0013-app-controller-hook` | (3.2b) `AppController.sharedController` returns `//room`'s `RoomAppController` (a separate `NSObject`, not a subclass: termination, the keep-alive, the last profile, command dispatch to the active Room Browser, the main window's Browser; every other AppController message logged on its first hit and answered with zero), and `ChromeBrowserMainPartsMac::PreCreateThreads` creates it and skips the NSApp-delegate CHECKs and Chrome's main menu: NSApp's delegate is the host's |
| `0014-navigator-browser-for-disposition-hook` | (3.2a) `GetBrowserAndTabForDisposition()` asks `//room` first: from a Room Browser the popup, window and picture-in-picture dispositions stay in that Browser (the host places the contents), off-the-record is cancelled until Chapter 4.8; Chrome would otherwise create a Browser, hence a BrowserView, per popup |
| `0015-target-url-hook` | (3.2a) `BrowserWebContentsDelegate::UpdateTargetURL` hands the hovered link of a Room page to `//room` (the host's status pill); Chrome's own path static_casts every status bubble to `StatusBubbleViews` |
| `0016-navigation-throttle-hook` | (3.3a) `CreateAndAddChromeThrottlesForNavigation` calls `//room` last, which adds `RoomNavigationThrottle` to the primary main frame of Room pages: the host's navigation policy (`decidePolicy`, Peek) asked at `WillStartRequest`/`WillRedirectRequest` with the exact navigation kind (`WasInitiatedByLinkClick`: a link, never `window.location`; B-33). Throttles are added only by the ContentBrowserClient |

| `0017-permission-prompt-factory-hook` | (3.4a) `CreatePermissionPrompt` (the Views factory `ChromePermissionsClient::CreatePrompt` calls) asks `//room` first: Room pages whose delegate answers prompts get `RoomPermissionPrompt` (the host's popover answers on Chrome's `PermissionRequestManager`); the manager's own view factory is test-only |
| `0018-context-menu-hook` | (3.4a) `ChromeWebContentsViewDelegateViewsMac::ShowMenu` hands the built `RenderViewContextMenu` of a Room page to `//room`, which keeps it until the host's NSMenu selects one of Chrome's commands or cancels; the view delegate is created by Chrome's ContentBrowserClient before RoomCore wraps the page |
| `0019-download-target-hook` | (3.4a) `ChromeDownloadManagerDelegate::DetermineDownloadTarget` asks `//room` first: a new download of a profile whose host set a downloads delegate goes where the host says (no Save panel, no danger verdict); the delegate is owned by `DownloadCoreServiceImpl`, its replacement setter test-only |
| `0020-login-handler-hook` | (3.4a) `LoginHandler::Create` (the platform factory) returns `//room`'s `LoginHandler` subclass for Room pages: the host's sign-in sheet instead of the Views dialog, Chrome's auth flow around it unchanged |
| `0021-ssl-error-hook` | (3.4a) `HandleSSLErrorWrapper` (bound into `SSLErrorNavigationThrottle`, patch 0016's file) asks `//room` first: a Room page's certificate error goes to the host's interstitial with Chrome's HSTS-aware verdict (B-24); "Visit anyway" stores `AllowCert` and loads again, "Go back" stops the deferred navigation |
| `0022-file-chooser-hook` | (3.4a) `BrowserWebContentsDelegate::RunFileChooser` (patch 0015's file) asks `//room` first: the host's open panel answers the page's `FileSelectListener` |
| `0023-external-protocol-dialog-hook` | (3.4b) `ExternalProtocolHandler::RunExternalProtocolDialog` (the Views implementation, `views/external_protocol_dialog.cc`) asks `//room` after Chrome's own checks: a Room page's link to another application goes to the host's confirmation (once per scheme), "open" is `LaunchUrlWithoutSecurityCheck`; the only override, `SetDelegateForTesting`, replaces the whole handler |
| `0024-extension-install-dialog-hook` | (3.6a) `ShowExtensionInstallDialogImpl` (the Views implementation behind `ExtensionInstallPrompt::GetDefaultShowDialogCallback()`) asks `//room` first: an install prompt of a profile whose host answers installs (the Web Store's "Add to Chrome", a CRX, new permissions) goes to the host's consent sheet with Chrome's permission lines, answered on the same `DoneCallback`. The Web Store creates its prompt through `ExtensionsBrowserClient::CreateInstallPrompt`, and the static default callback has no override but `ScopedTestDialogAutoConfirm` (answers without asking) |
| `0025-extension-update-allowed-hook` | (3.6a) `ChromeExtensionsBrowserClient::IsBackgroundUpdateAllowed` asks `//room` first: true only inside the host's `checkForUpdates` (a `CheckNow` whose checks start synchronously), so an extension update check happens only on the host's daily timer. Room's policy passes `--disable-background-networking`, which otherwise refuses every extension update check, and which other services read too (variations, translate, the intranet redirect detector) |

Patch `0010-shutdown-worker-start-priority` (PR #1) is parked in `patches/parked/` (B-40; the README there says why and when it comes back). The series has twenty-four patches (0001–0009, 0011–0025). Each 3.4a/3.4b hook applies only to pages (or profiles) whose host delegate implements the member; the embryo host, which implements few, keeps Chrome's own UI and its drives still exercise it.

3.4b took the rest of Chrome's page UI without patches, through seams Chrome already has (`room/core/room_page_dialogs.mm`, `room_page_state.mm`): each Room page's `TabModalDialogManager` is recreated with a `//room` delegate (alert, confirm, prompt), `AppModalDialogManager::SetNativeDialogFactory` takes beforeunload (close, reload, quit), the page's `TabDialogs` is wrapped for the hung-page question, an `InfoBarManager::Observer` and a `TranslateBubbleFactory` hand over infobars and the translate offer, a `MediaStreamCaptureIndicator::Observer` and a `MediaSessionObserver` give the capture state and the media session. Only the external protocol dialog, a static with no override but a test delegate, needed a hook (0023).

3.5 took Chrome's history and omnibox without patches (B-61's seam check: every member is a public API of a keyed service or an existing `BrowserWindow`/`LocationBar` override): `room/core/room_history.mm` over `HistoryService` (queries on a `CancelableTaskTracker`; the Chapter 2 import through `AddPagesWithDetails` plus a `HistoryDBTask` for the earlier visits), `room/core/room_autocomplete.mm` over `AutocompleteController` with `ChromeAutocompleteProviderClient` (one controller per provider set) and `TemplateURLService` for Room's search engine; `RoomBrowserWindow::SetFocusToLocationBar` and `IsLocationBarVisible` are real (`IDC_FOCUS_LOCATION` → `RoomLocationBar::FocusLocation` → the host), `RoomLocationBar::GetLocationBarModel` returns the Browser's own model.

3.6a took Chrome's extension system for the host's Settings ▸ Extensions (`room/core/room_extensions.mm`, public `RoomExtensions.h`). B-61's seam check: the installed list, enable/disable/reload/uninstall, unpacked loads, options pages, actions and the pinned order are public keyed-service APIs (`ExtensionRegistry`, `ExtensionRegistrar`, `UnpackedInstaller`, `ExtensionActionManager`/`ExtensionActionDispatcher`, `ToolbarActionsModel`); uninstall consent needs no hook (the host is asked before `UninstallExtension`; Chrome's `ExtensionUninstallDialog` stays only behind `chrome://extensions`' own Remove); Chrome's post-install dialog is turned off through `ExtensionInstallUI::disable_ui_for_tests(true)` (named for tests, no test behaviour; its follow-up dereferences a `BrowserView` toolbar); Chrome's extension update schedule needs no change of its own (its scheduled checks reach the gate and are refused); update_client's event pings (the uninstall ping Chrome sends for every Web Store extension removed) are off through a `ChromeUpdateClientConfig` subclass without a ping URL, installed with the protected `SetChromeUpdateClientConfigFactoryForTesting` (no test behaviour); Chrome Apps' `AppShortcutManager` file work is off through `AppShortcutManager::SuppressShortcutsForTesting()` (it created `~/Applications/Chromium Apps.localized` at the first uninstall). Two hooks were needed (0024 install prompt, 0025 update gate), justified in their headers.

3.6b took action popups, `action.openPopup`, extension commands and the side panel answer without a patch (B-61's seam check, `room/core/room_extension_popups.mm`): `ExtensionsContainer` is user data Chrome looks up on the Browser (`ExtensionsContainer::From`), so `//room` registers its own on each Room Browser with `ui::ScopedUnownedUserData`, as `WebUIBrowserWindow` does; popups are `ExtensionViewHostFactory::CreatePopupHost` hosts with a `//room` `ExtensionView` (public extension API) handed to the host; `RoomBrowserWindow::IsToolbarVisible` is a `BrowserWindow` override; the commands registry subclasses `ExtensionKeybindingRegistry` (public, as Android's does) and is asked from the existing `PreHandleKeyboardEvent` override; side panels stay off through `SidePanelService`'s own options and observer (Chrome's open path would dereference a null `SidePanelUI`). Patch 0012 is unchanged: the extension-origin device chooser anchors on `ToolbarButtonProvider::GetExtensionsContainerViews` (Views), which a Room container is not (B-71).

3.7a took Chrome's password manager and autofill bubbles without a patch (B-61's seam check: `ToolbarButtonProvider` is user data Chrome looks up on the Browser, `ToolbarButtonProvider::From`, which `ToolbarView` registers; the password bubble's only gate is that lookup): `RoomToolbarButtonProvider` (`room/browser/room_browser_window.mm`, replacing PR #1's private `RoomAutofillAnchors`) is registered on every non-headless Room Browser with `ui::ScopedUnownedUserData` and answers every `GetBubbleAnchor` with the window's Views bubble anchor; `RoomBrowserWindow::GetBubbleAnchor` places that anchor at the host's site button, asked through `RoomBrowserWindowClient::GetBubbleAnchorRect` → the active page's `-webContentsBubbleAnchorRect:` (public delegate member) whenever a bubble asks and when the window moves or resizes. Its other members return null and log their first hit; the extensions container stays null (no fake container: the hardening review's finding 3, B-71). The suggestion popups (`PopupViewViews`) need no provider; Chrome closes them on its browser widget's bounds change, which a Room window is not, so `RoomBrowserWindow` closes them on move and resize (`AutofillClient::HideSuggestions(kWidgetChanged)`). Password leak checks are off by default through the pref's default value (`PrefService::SetDefaultPrefValue`, in the network policy's services callback). Patch 0011 (PR #1) still owns the window lookup for the autofill bubble handler; the series stays 24.

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
met inside `//room`: `RoomLocationBar`, `RoomExclusiveAccessContext` (tab
fullscreen through the host's delegate since 3.2a), `RoomFindBar` (inert: find
is the host's), and `TearDownPreBrowserWindowDestruction()` in
`~RoomBrowserWindow`. What Chrome expects of its `AppController` is
`RoomAppController` (`room/core/room_app_controller.mm`, patch 0013); the host
owns NSApp's delegate (`RoomApplication.applicationDelegate`) and the whole
menu bar, so the hidden Bookmarks item the embryo needed is gone (3.2b).
`RoomCrApplication -terminate:` asks the host's `applicationShouldTerminate:`
before Chrome's close path; `-[RoomApplication tryToTerminateWithCompletion:]`
is that close path with beforeunload and a cancel (`completion(NO)`). A Browser `//room` did not create gets a headless
`RoomBrowserWindow` (no NSWindow, a log line), never Chrome's BrowserView.
After a change to `tools/browser_window_real_members.txt`, regenerate the
stubs with `tools/gen_browser_window_stubs.py $CHROMIUM_SRC
tools/browser_window_real_members.txt --write room`. Two Xcode targets link the staged framework (`xcodegen/roomcore.yml`; all
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
