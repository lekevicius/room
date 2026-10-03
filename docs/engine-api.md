# Engine API mapping

Every member of the Swift `Engine` protocols (`Packages/Engine`) against the CEF 154 call or handler `EngineCEF` uses in Phase 1.4, and the Chromium 154 code `RoomCore` wraps in Chapter 3. The ArcCore column names the closest member in Dia's `ArcCore.framework` headers (`research/repos/arccore-headers/`, study only) so the RoomCore ObjC API stays the same shape; it is a pointer, not a spec.

This table is the Chapter 3 checklist: a row is done when its RoomCore column is implemented and the `FakeEngine` behavior for it still holds.

Legend: **CEF: not available** = CEF 154 has no public API; the CEF engine returns `nil`, throws `EngineError.notSupported`, or emulates as described. *Emulated* = works on CEF through a workaround (JavaScript, DevTools protocol, re-creation) with the cost noted. CEF handler names are the C++ classes in `Engine/cef/dist/current/include/`; "CDP" is the DevTools protocol, sent from CEF with `CefBrowserHost::ExecuteDevToolsMethod` (or `SendDevToolsMessage`) and read back through `CefDevToolsMessageObserver`.

Threading: every protocol is `@MainActor`. CEF calls most handlers on the browser UI thread, which is the main thread on macOS; `CefRequestHandler::GetAuthCredentials` runs on the IO thread (`cef_request_handler.h:153`) and must hop to main; the rest of the handlers used here, including all of `CefDownloadHandler`, run on the UI thread. Chromium's UI thread is the main thread.

## `EngineApplication`

| Engine | CEF (Phase 1.4) | Chromium / RoomCore (Chapter 3) | ArcCore |
|---|---|---|---|
| `initialize(_:)` | `CefScopedLibraryLoader::LoadInMain` → `CefInitialize(CefMainArgs, CefSettings, CefApp)`; `root_cache_path` = `userDataDirectory`; `log_file`; `locale`; `--use-mock-keychain` via `CefApp::OnBeforeCommandLineProcessing` | `ChromeMain`/`content::ContentMain` with `ChromeMainDelegate`, user-data-dir switch, host `NSApplication` conforming to `CrAppProtocol` | `ArcBrowserApplication initialize:` (`ArcBrowserApplicationConfiguration`) |
| `run()` | `CefRunMessageLoop()` then `CefShutdown()` | `BrowserMainRunner::Run` (the `ChromeMain` message loop) | `run` |
| `tryToTerminate(_:)` | `CefBrowserHost::TryCloseBrowser` on each browser (runs beforeunload; `false` = wait for `DoClose`/`OnBeforeClose`), then `CefQuitMessageLoop()`; `completion(false)` when a beforeunload dialog answers "stay" | `BrowserCloseManager::StartClosingBrowsers` / `chrome::AttemptExit` semantics; beforeunload via `UnloadController` | `tryToTerminate:` (`ArcTerminateDecision` cancel/now/later) |
| `isTerminating` (added in 2.3) | `true` from `tryToTerminate` until the last `OnBeforeClose` (or a beforeunload "stay"): the tab controller then treats `webContentsDidClose` as engine-initiated and leaves the entry alone | `browser_shutdown::IsTryingToQuit()` | — (`applicationWillTerminate` on the delegate) |
| `features` | the `EngineConfiguration.features` passed in; merged into `--enable-features` / `--disable-features` in `OnBeforeCommandLineProcessing` (done in Phase 1.2; CEF cannot query `base::FeatureList` back) | `base::FeatureList` from the same switches; `FeatureList::IsEnabled` for queries | `isFeatureEnabled:` / `setFeatureEnabled:enabled:` |
| `profiles` | list kept by `CEFApplication`: one `CefRequestContext` per created profile | `ProfileManager::GetLoadedProfiles()` | `availableBrowserContextAttributes`, `getBrowserContext:type:` |
| `createProfile(name:)` | `CefRequestContext::CreateContext(CefRequestContextSettings{cache_path = <root_cache_path>/Room Profile <name>}, handler)`; resume on `CefRequestContextHandler::OnRequestContextInitialized`. `cache_path` must be a **direct** child of `root_cache_path` (deeper paths silently become an off-the-record profile; measured in Phase 1.4) | `ProfileManager::CreateProfileAsync(path, callback)` (profile dir under user-data-dir) | `createBrowserContext:type:completion:error:`, `loadBrowserContext:type:completion:` |

## `Profile`

| Engine | CEF (Phase 1.4) | Chromium / RoomCore (Chapter 3) | ArcCore |
|---|---|---|---|
| `name` | stored by `CEFProfile` | `Profile::GetBaseName()` / `ProfileAttributesEntry::GetLocalProfileName()` | `userVisibleName` |
| `createWebContents(_:)` | `CefBrowserHost::CreateBrowserSync(CefWindowInfo::SetAsChild(parentView, rect), client, "", CefBrowserSettings, nullptr, requestContext)` — Alloy style is forced for child windows (`cef.md` §1). `initiallyHidden` → create under a hidden parent view (`CefWindowInfo::hidden` is honored only for CEF-created top-level windows and `SetAsChild` resets it; `WasHidden()` is windowless-only); `transparentBackground` → **CEF: not available** through settings (a windowed browser with `background_color` alpha 0 falls back to `CefSettings.background_color`, then opaque white) — *emulated* with CDP `Emulation.setDefaultBackgroundColorOverride`; `initiallyMuted` → `CefBrowserHost::SetAudioMuted(true)` after creation; `disallowAutoplay` → `--autoplay-policy=document-user-activation-required` (process-wide only: *partially available*) | `content::WebContents::Create(CreateParams{browser_context, initially_hidden})`; tab helpers via `TabHelpers::AttachTabHelpers` (private with a closed friend list in `tab_helpers.h`: needs a one-line friend patch or a Chrome tab-creation path); background via `RenderWidgetHostView::SetBackgroundColor`; autoplay via `WebPreferences.autoplay_policy` override | `createWebContents:` (`ArcWebContentsConfiguration`: `initiallyHidden`, `transparentBackground`, `initiallyMuted`, `disallowAutoplay`) |
| `downloadsDelegate` | `CefDownloadHandler` on the client: `CanDownload` (allow), `OnBeforeDownload` → `willBeginDownload` → `CefBeforeDownloadCallback::Continue(path, false)` (no delegate or `nil` → not continued = cancelled; Alloy cancels unhandled downloads), `OnDownloadUpdated` → `didUpdateDownload` | `DownloadManagerDelegate::DetermineDownloadTarget` (→ `willBeginDownload`), `download::DownloadItem::Observer::OnDownloadUpdated`, `DownloadManager::Observer::OnDownloadCreated` | `ArcBrowserContextDownloadsDelegate` (`onDeterminingFilename:…completion:`, `onDownloadUpdated:`) |
| `pauseDownload/resumeDownload/cancelDownload(id:)` | `CefDownloadItemCallback::Pause/Resume/Cancel` (kept per id from `OnDownloadUpdated`) | `download::DownloadItem::Pause/Resume/Cancel` via `DownloadManager::GetDownloadByGuid` | `ArcDownloadItem pause`, `resume`, `cancel:` |
| `favicon(for:)` | **CEF: not available** (no favicon database API); returns `nil`. The app's favicon cache (Phase 2.1) stores what `WebContents.favicon` delivered | `favicon::FaviconService::GetFaviconImageForPageURL` | `favicon:completion:` |
| `clearSiteData(_:for:)` | cookies: `CefCookieManager::DeleteCookies(url, "", cb)` from `CefRequestContext::GetCookieManager`; cache: `CefRequestContext::ClearHttpCache` (all origins only); storage: *emulated* with CDP `Storage.clearDataForOrigin` (needs a live browser in the profile); auth: `ClearHttpAuthCredentials`; permissions: `SetContentSetting`/`SetWebsiteSetting` reset per type, `ClearCertificateExceptions` | `content::BrowsingDataRemover::RemoveWithFilter` (`BrowsingDataFilterBuilder` for one origin) with `chrome_browsing_data_remover` data types; `HostContentSettingsMap::ClearSettingsForOneType` | `clearSiteDataAndReload:` (on `ArcWebContents`), `setContentSettingsForOrigin:…`, `deleteAllCookies:` |
| `history` | **CEF: not available** → `nil` (Chapter 2 keeps a local FTS table) | `history::HistoryService` (`HistoryServiceFactory`) | `ArcBrowserContext.history` (`ArcBrowserContextHistory`) |
| `bookmarks` | **CEF: not available** → `nil` | `bookmarks::BookmarkModel` (`BookmarkModelFactory`) | `getBookmarksTree`, `addBookmark:…`, `ArcBookmarkModelObserver` |
| `extensions` | **CEF: not available** → `nil` (Alloy loads content scripts from `--load-extension` but has no action popups, toolbar or Web Store install; `cef.md` §2) | `extensions::ExtensionRegistry`, `ExtensionService`, `ExtensionActionManager`; popups as `WebContents` | `ArcBrowserContext.extensions` (`ArcBrowserContextExtensions`) |
| `makeAutocompleteController()` | **CEF: not available** → `nil` (Chapter 2 palette uses its own providers) | `AutocompleteController` with `ChromeAutocompleteProviderClient` | `createAutocompleteControllerWithProviders:` |

## `WebContents`

| Engine | CEF (Phase 1.4) | Chromium / RoomCore (Chapter 3) | ArcCore |
|---|---|---|---|
| `nativeView` | a `CEFPageView` owned by `CEFWebContents`; the `SetAsChild` parent (bridge container) sits inside it and `CefBrowserHost::GetWindowHandle()` (CEF's `CefBrowserHostView`) inside that. Keeps the view stable across the emulated `discard()` | `WebContents::GetNativeView()` (`gfx::NativeView` → `NSView`) | none exported; ArcCore hands out the view through its view classes |
| `uiDelegate` / `navigationDelegate` | weak references on `CEFWebContents`; the `CefClient` handlers below forward to them | `WebContentsDelegate` + `WebContentsObserver` implementations in `//room/core` forward to the ObjC delegates | `setUIDelegate:`, `setNavigationDelegate:` |
| `load(_:transition:fromAddressBar:)` | `CefFrame::LoadURL` on `GetMainFrame()`; `transition` cannot be set — **CEF: transition not available**: CEF always sends `PAGE_TRANSITION_TYPED \| PAGE_TRANSITION_FROM_ADDRESS_BAR` (`libcef/browser/frame_host_impl.cc`), so `fromAddressBar` is effectively always `true` | `NavigationController::LoadURLWithParams(LoadURLParams{transition_type = PageTransitionFromInt(type \| PAGE_TRANSITION_FROM_ADDRESS_BAR)})` | `navigationController` (`ArcWebContentsNavigationController`), `ArcPageTransition` |
| `goBack()` / `goForward()` | `CefBrowser::GoBack` / `GoForward` | `NavigationController::GoBack` / `GoForward` | `navigationController` |
| `reload()` / `reloadIgnoringCache()` | `CefBrowser::Reload` / `ReloadIgnoreCache` | `NavigationController::Reload(ReloadType::NORMAL / BYPASSING_CACHE, true)` | `navigationController` |
| `stop()` | `CefBrowser::StopLoad` | `WebContents::Stop()` | `stop` |
| `title` | `CefDisplayHandler::OnTitleChange` | `WebContents::GetTitle()`; `WebContentsObserver::TitleWasSet` | `title` |
| `url` | `CefDisplayHandler::OnAddressChange` (main frame) | `WebContents::GetVisibleURL()`; `NavigationEntryCommitted` / `DidStartNavigation` | `url` |
| `favicon` | `CefDisplayHandler::OnFaviconURLChange` → `CefBrowserHost::DownloadImage(url, true, 16*scale, false, CefDownloadImageCallback)` → `NSImage` | `favicon::ContentFaviconDriver` + `FaviconDriverObserver::OnFaviconUpdated` | `favicon` |
| `isLoading` | `CefLoadHandler::OnLoadingStateChange(isLoading, …)` | `WebContents::IsLoading()`; `WebContentsObserver::DidStartLoading/DidStopLoading` | `isLoading` |
| `loadProgress` | `CefDisplayHandler::OnLoadingProgressChange` | `WebContents::GetLoadProgress()`; `WebContentsObserver::LoadProgressChanged` | `loadProgress` |
| `canGoBack` / `canGoForward` | `CefLoadHandler::OnLoadingStateChange(…, canGoBack, canGoForward)` | `NavigationController::CanGoBack/CanGoForward` | `canGoBack`, `canGoForward` |
| `themeColor` | **CEF: not available** — *emulated*: read `meta[name=theme-color]` with JavaScript after `OnLoadEnd` (misses later script changes unless a `MutationObserver` reports back) | `WebContents::GetThemeColor()`; `WebContentsObserver::DidChangeThemeColor` | `themeColor` |
| `rootBackgroundColor` | **CEF: not available** — *emulated*: `getComputedStyle(document.documentElement).backgroundColor` (falling back to `body`) after `OnLoadEnd` | `WebContents::GetBackgroundColor()`; `WebContentsObserver::OnBackgroundColorChanged` | `rootBackgroundColor` |
| `securityState` | `CefBrowserHost::GetVisibleNavigationEntry()->GetSSLStatus()`: `IsSecureConnection`, `GetCertStatus`, `GetContentStatus` (mixed content), read on `OnLoadingStateChange`/`OnLoadEnd` (no change event) | `chrome_security_state::GetSecurityLevel(web_contents)` / `GetVisibleSecurityState(web_contents)` (`chrome/browser/ssl/chrome_security_state_util.h`; `SecurityStateTabHelper` is gone in M154); `WebContentsObserver::DidChangeVisibleSecurityState` | `webContents:didChangeVisibleSecurityState:` (`ArcSecureContext`) |
| `isAudible` | *Partially available*: Alloy calls `CefAudioHandler::GetAudioParameters` each time the page becomes audible (driven by `OnAudioStateChanged`); returning `false` skips capture (sound keeps playing) and gives a native "became audible" edge but no "stopped" edge. Returning `true` captures the stream (`mute_source = true`: the speakers go silent) and `OnAudioStreamStarted/Stopped` track audibility with a 2 s debounce — unusable. "Stopped" is *emulated* by polling `HTMLMediaElement` state with JavaScript (misses Web Audio); spike in Phase 1.4 | `WebContents::IsCurrentlyAudible()`; `WebContentsObserver::OnAudioStateChanged` | `webContents:didChangeAudibleState:` |
| `isMuted` | `CefBrowserHost::SetAudioMuted` / `IsAudioMuted` | `WebContents::SetAudioMuted` / `IsAudioMuted`; `WebContentsObserver::DidUpdateAudioMutingState` | `webContents:didChangeMuteState:` |
| `state` (`alive/discarded/frozen/closed`) | `alive`/`closed`; `discarded` via the emulated `discard()`; `frozen` *emulated* with CDP `Page.setWebLifecycleState{state: frozen\|active}` | `resource_coordinator::TabLifecycleUnitSource` / `performance_manager` discard and freezing votes; `WebContents::WasDiscarded()` | `state` (`ArcWebContentsState`), `emitFreezingVote:` |
| `zoomFactor` | `CefBrowserHost::SetZoomLevel` / `GetZoomLevel` (level ↔ factor via `log(factor)/log(1.2)`) | `zoom::ZoomController::SetZoomLevel`; `blink::ZoomFactorToZoomLevel` | `zoomFactor`, `setZoomFactor:` |
| `find(_:forward:matchCase:)` / `findResult` | `CefBrowserHost::Find(text, forward, matchCase, findNext)`; results from `CefFindHandler::OnFindResult(identifier, count, selectionRect, activeMatchOrdinal, finalUpdate)` | `find_in_page::FindTabHelper::StartFinding`; `FindResultObserver::OnFindResultAvailable` | `find:forward:matchCase:findMatch:completion:` |
| `stopFind(clearSelection:)` | `CefBrowserHost::StopFinding(clearSelection)` | `FindTabHelper::StopFinding(find_in_page::SelectionAction)` | `stopFind` |
| `discard()` | **CEF: not available** — *emulated*: `CloseBrowser(true)` and keep URL/title; the next `load`/`reload` re-creates the browser (back/forward list is lost) | `TabLifecycleUnitExternal::DiscardTab` / `WebContents::SetWasDiscarded` path (keeps the navigation entries) | `discard` |
| `close()` | `CefBrowserHost::CloseBrowser(false)` (runs beforeunload); `CefLifeSpanHandler::DoClose` must return `true` and remove the host view (returning `false` sends `performClose:` to the hosting NSWindow); `OnBeforeClose` → `webContentsDidClose` | `WebContents::ClosePage()` → `WebContentsDelegate::CloseContents` | `close(foregroundCommit:)` |
| `captureViewport()` | *emulated*: CDP `Page.captureScreenshot` (PNG) — the windowed view is an `IOSurface` layer that `cacheDisplay` cannot read | `RenderWidgetHostView::CopyFromSurface` | `captureViewport:` |
| `devTools` → `DevTools.open(in:)` / `inspectElement(at:in:)` / `close()` / `isOpen` | **Not via `ShowDevTools`**: on CEF 154 macOS DevTools is always Chrome style and Chrome style refuses a native parent (`DCHECK`, crash; #3294). Docked = our own Alloy browser in `hostView` loading `devtools://devtools/bundled/devtools_app.html?ws=127.0.0.1:<port>/devtools/page/<Target.getTargetInfo targetId>` (needs `remote_debugging_port` + `--remote-allow-origins=devtools://devtools`; Debug builds); inspect = CDP `DOM.getNodeForLocation` + `Common.Revealer.reveal` in the front-end. Without the port: `ShowDevTools` with an empty `CefWindowInfo` (CEF's own top-level window), `CloseDevTools`, `HasDevTools` | `DevToolsWindow` is Views-docked; RoomCore hosts the frontend `WebContents` itself through `DevToolsUIBindings` + `DevToolsAgentHost`, `inspect_element` via `DevToolsWindow::InspectElement` logic | `devTools` (`ArcWebContentsDevTools`: `open`, `close`, `inspectElementAt:`, `toolboxWebContents`) |
| `executeJavaScript(_:)` | *emulated*: CDP `Runtime.evaluate{expression, returnByValue: true, awaitPromise: true}` (`CefFrame::ExecuteJavaScript` returns no result); 0.21 ms median round trip. The bridge assigns message ids itself: results can arrive synchronously inside `ExecuteDevToolsMethod` | main world needs CDP `Runtime.evaluate` or a `//room` hook: `RenderFrameHost::ExecuteJavaScript` is limited to chrome:// and devtools:// pages and `ExecuteJavaScriptInIsolatedWorld` cannot target the main world (`render_frame_host.h`); isolated-world evaluation suffices for our own scripts that only read the DOM | `executeJavascript:completion:` |
| `print()` | `CefBrowserHost::Print()` (system print panel; Alloy has no print preview unless `--enable-print-preview`) | `printing::StartPrint` / `PrintViewManager::PrintPreviewNow` (print preview stays Views, `PLAN.md` §4) | `print` |

## `DevTools`

Covered in the `WebContents.devTools` row. The host view is ours (Phase 1.4 `DevToolsPaneView`, Phase 2.6 resizable pane), never a Chromium-owned window.

## `WebContentsUIDelegate`

The engine must never show its own UI for these except where "engine shows its own" is stated; defaults (protocol extension) are the "no UI" behavior.

| Engine | CEF (Phase 1.4) | Chromium / RoomCore (Chapter 3) | ArcCore |
|---|---|---|---|
| `didCreate(_:targetURL:disposition:)` | `CefLifeSpanHandler::OnBeforePopup` (gives `target_disposition`, `user_gesture`; set `windowInfo.SetAsChild` on a temporary parent, return `false`) → `OnAfterCreated` → wrap in `CEFWebContents` and deliver; re-parent the view when the app places it (`cef.md` §3) | `WebContentsDelegate::AddNewContents(source, new_contents, target_url, disposition, features, user_gesture, …)` | `webContents:didCreateNewWebContent:targetURL:disposition:` |
| `webContentsDidRequestEnterFullscreen(_:origin:)` / `…ExitFullscreen` | `CefDisplayHandler::OnFullscreenModeChange(fullscreen)` (Alloy resizes the view; the app enters window fullscreen) | `WebContentsDelegate::EnterFullscreenModeForTab` / `ExitFullscreenModeForTab`; `ExclusiveAccessContext` | `webContentsDidRequestEnterFullscreen:withDisplayId:requestingOrigin:`, `webContentsDidRequestExitFullscreen:` |
| `didChangeStatusText(_:)` | `CefDisplayHandler::OnStatusMessage` | `WebContentsDelegate::UpdateTargetURL` (hovered link); status bubble text from `LoadingStateChanged` | `webContents:didChangeStatusText:` |
| `willShowContextMenu(_:for:)` → `MenuModel.select/cancel` | `CefContextMenuHandler::OnBeforeContextMenu` (edit `CefMenuModel`), `RunContextMenu(params, model, callback)`: return `true` and call `CefRunContextMenuCallback::Continue(commandId, flags)` / `Cancel`; returning `false` shows CEF's native `NSMenu` runner. `ContextMenuElement` from `CefContextMenuParams` | `WebContentsDelegate::HandleContextMenu(RenderFrameHost&, ContextMenuParams)`; model from `RenderViewContextMenu` (`ui::SimpleMenuModel`), commands via `ExecuteCommand(id, flags)` | `webContents:willShowContextMenu:withElement:` (`ArcMenuModel`, `ArcContextMenuElementInfo`) |
| `runJavaScriptAlert/Confirm/Prompt` | `CefJSDialogHandler::OnJSDialog(origin_url, dialog_type, message, default_prompt, callback, suppress)` → `CefJSDialogCallback::Continue(success, input)` | `JavaScriptDialogManager::RunJavaScriptDialog` (RoomCore's own manager returned from `WebContentsDelegate::GetJavaScriptDialogManager`) | `willRunJavaScriptAlertPanel/ConfirmPanel/TextInputPanel:…completion:` |
| `runBeforeUnloadDialogForReload(_:completion:)` | `CefJSDialogHandler::OnBeforeUnloadDialog(message_text, is_reload, callback)` | `JavaScriptDialogManager::RunBeforeUnloadDialog(web_contents, rfh, is_reload, callback)` | `runJavaScriptApplicationModalBeforeUnloadPanel:…completion:` |
| `webContentsDidDismissJavaScriptDialogs(_:)` | `CefJSDialogHandler::OnResetDialogState` / `OnDialogClosed` | `JavaScriptDialogManager::CancelDialogs` | `webContentsWillCloseJavaScriptPanel:`, `webContentsCloseJavaScriptApplicationModalBeforeUnloadPanel:` |
| `willAskForPermission(_:quietReason:completion:)` | `CefPermissionHandler::OnShowPermissionPrompt(prompt_id, origin, requested_permissions bitmask, callback)` → `CefPermissionPromptCallback::Continue(CEF_PERMISSION_RESULT_ACCEPT/DENY/DISMISS)` (no "this time" result: `grantedOnce` maps to accept); camera/mic via `OnRequestMediaAccessPermission(browser, frame, origin, requested_permissions, callback)` → `CefMediaAccessCallback::Continue(allowed_permissions bitmask)` / `Cancel()`. `quietReason` is always `nil` (no quiet UI in CEF) | `permissions::PermissionPrompt` created through `PermissionsClient::CreatePrompt` (RoomCore's `ChromePermissionsClient` override; `PermissionPrompt::Factory` is a callback typedef) for `PermissionRequestManager`; `Delegate::Accept/AcceptThisTime/Deny/Dismiss/Ignore(const PromptOptions&)`; quiet UI from `PermissionUiSelector::QuietUiReason` (`components/permissions/prediction_service/permission_ui_selector.h`) | `webContents:willAskForPermission:withRequests:withQuietUIReason:completion:` |
| `webContentsDidDismissPermissionPrompt(_:)` | `CefPermissionHandler::OnDismissPermissionPrompt(prompt_id, result)` | `PermissionPrompt` destroyed by `PermissionRequestManager` | `webContentsClosePermission:` |
| `didReceiveAuthChallenge(_:completion:)` | `CefRequestHandler::GetAuthCredentials(origin_url, isProxy, host, port, realm, scheme, callback)` → `CefAuthCallback::Continue(user, pass)` / `Cancel` (called on the IO thread: hop to main) | `ContentBrowserClient::CreateLoginDelegate` → RoomCore `LoginHandler` delegate (Chrome's is Views) | `showWebLoginDialog:` (`ArcWebLoginDialog`) |
| `didFailCertificateCheck(_:completion:)` | `CefRequestHandler::OnCertificateError(cert_error, request_url, ssl_info, callback)` → `CefCallback::Continue` / `Cancel` (return `false` = cancel immediately) | Chrome shows the in-page `SSLBlockingPage` interstitial (`SSLErrorHandler`); the delegate call needs a `//room` hook in `ChromeContentBrowserClient::AllowCertificateError`, or the delegate is reduced to "interstitial shown" | none (Arc keeps Chrome's interstitial) |
| `runFileChooser(_:completion:)` | `CefDialogHandler::OnFileDialog(mode, title, default_file_path, accept_filters, accept_extensions, accept_descriptions, callback)` → `CefFileDialogCallback::Continue(paths)` / `Cancel`; returning `false` shows CEF's `NSOpenPanel` | `WebContentsDelegate::RunFileChooser(rfh, FileSelectListener, FileChooserParams)` (Chrome's `FileSelectHelper` uses `ui::SelectFileDialog`, already native `NSOpenPanel`) | none (Chrome's native panel) |
| `isReservedKeyEvent(_:)` | `CefKeyboardHandler::OnPreKeyEvent(event, os_event, is_keyboard_shortcut)`: return `true` to swallow, then `NSApp.mainMenu.performKeyEquivalent` | `WebContentsDelegate::PreHandleKeyboardEvent` returning `KeyboardEventProcessingResult::HANDLED` | none (Arc reserves through its key router) |
| `handleUnhandledKeyEvent(_:)` | `CefKeyboardHandler::OnKeyEvent(event, os_event)` with the `NSEvent` | `WebContentsDelegate::HandleKeyboardEvent(source, NativeWebKeyboardEvent)` (`os_event` is the `NSEvent`) | none |
| `didConsumeKey(_:)` | **CEF: not available** (no ack for page-handled keys); never called | `RenderWidgetHost::InputEventObserver::OnInputEventAck` with `blink::mojom::InputEventResultState::kConsumed` | `webContents:didConsumeKey:withModifierFlags:underlyingEventType:` |
| `didChangeAudible(_:)` | see `isAudible` (emulated) | `WebContentsObserver::OnAudioStateChanged` | `webContents:didChangeAudibleState:` |
| `didChangeMuted(_:)` | fired by `CEFWebContents` when `isMuted` is set (CEF has no change event) | `WebContentsObserver::DidUpdateAudioMutingState` | `webContents:didChangeMuteState:` |
| `didChangeSecurityState(_:)` | fired when the `securityState` read on `OnLoadingStateChange` differs | `WebContentsObserver::DidChangeVisibleSecurityState` | `webContents:didChangeVisibleSecurityState:` |
| `processGone(_:)` | `CefRequestHandler::OnRenderProcessTerminated(status, error_code, error_string)` (`cef_termination_status_t`) | `WebContentsObserver::PrimaryMainFrameRenderProcessGone(base::TerminationStatus)` | `webContentsProcessGone:` (+ `ArcWebContentsTerminationStatus`) |
| `webContentsDidClose(_:)` | `CefLifeSpanHandler::OnBeforeClose` (also after `window.close()`, which arrives as `DoClose`) | `WebContentsDelegate::CloseContents` | `webContents:didCloseWithSessionID:` |

## `NavigationDelegate`

| Engine | CEF (Phase 1.4) | Chromium / RoomCore (Chapter 3) | ArcCore |
|---|---|---|---|
| `decidePolicy(for:) -> Disposition` | `CefRequestHandler::OnBeforeBrowse(frame, request, user_gesture, is_redirect)` for main-frame navigations (`.ignore` → return `true` to cancel; another tab disposition → cancel and open via `didCreate`); `CefRequestHandler::OnOpenURLFromTab(target_url, target_disposition, user_gesture)` for ⌘/middle-click; `CefLifeSpanHandler::OnBeforePopup` for `window.open`. `NavigationAction.kind` from `CefRequest::GetTransitionType` (`TT_LINK`, `TT_FORM_SUBMIT`, `TT_FORWARD_BACK_FLAG`, `TT_RELOAD`) | a `//room` `content::NavigationThrottle` (`WillStartRequest`/`WillRedirectRequest`) for current-tab navigations; `WebContentsDelegate::OpenURLFromTab(source, OpenURLParams{disposition})` for dispositions | `ArcWebContentsNavigationDelegate webContents:decidePolicyForNavigationAction:` |

## Value types

| Engine | CEF | Chromium | ArcCore |
|---|---|---|---|
| `Disposition` | `cef_window_open_disposition_t` (`CEF_WOD_CURRENT_TAB`, `…NEW_FOREGROUND_TAB`, `…NEW_BACKGROUND_TAB`, `…NEW_POPUP`, `…NEW_WINDOW`, `…SAVE_TO_DISK`, `…OFF_THE_RECORD`, `…IGNORE_ACTION`, `…NEW_PICTURE_IN_PICTURE`; `SINGLETON_TAB`, `SWITCH_TO_TAB` and `NEW_SPLIT_VIEW` map to `.newForegroundTab`, `UNKNOWN` to `.currentTab`) | `WindowOpenDisposition` (`ui/base/window_open_disposition.h`) | `ArcWebContentsNavigationDisposition` (adds `SplitView`, `LittleArc`) |
| `NavigationAction` (`url`, `referrer`, `kind`, `transition`, `disposition`, `isUserGesture`, `isRedirect`) | `CefRequest` (`GetURL`, `GetReferrerURL`, `GetTransitionType`) + `OnBeforeBrowse`'s `user_gesture`/`is_redirect` | `NavigationHandle` (`GetURL`, `GetReferrer`, `GetPageTransition`, `HasUserGesture`, `WasServerRedirect`) | `ArcNavigationAction` (`url`, `referrer`, `navigationType`, `navigationDisposition`) |
| `PageTransition` | `cef_transition_type_t` (read-only on CEF requests) | `ui::PageTransition` (`LINK`, `TYPED`, `AUTO_BOOKMARK`, `GENERATED`, `KEYWORD`, `FORM_SUBMIT`, `RELOAD`) | `ArcPageTransition` |
| `PermissionRequest.Kind` | `cef_permission_request_types_t` bits (`CEF_PERMISSION_TYPE_CAMERA_STREAM`, `…MIC_STREAM`, `…GEOLOCATION`, …; at `CEF_API_VERSION` 15400 bit 25 is `…LOCAL_NETWORK_ACCESS_DEPRECATED`; it, `…LOCAL_NETWORK` and `…LOOPBACK_NETWORK` → `.localNetworkAccess`); camera/mic via `cef_media_access_permission_types_t` (`…DEVICE_VIDEO_CAPTURE`, `…DEVICE_AUDIO_CAPTURE`; `…DESKTOP_VIDEO_CAPTURE` and `…DESKTOP_AUDIO_CAPTURE` → `.displayCapture`) | `permissions::RequestType` | `ArcPermissionRequestType` |
| `PermissionResponse` | `cef_permission_request_result_t` (`ACCEPT`, `DENY`, `DISMISS`, `IGNORE`); no "this time" | `permissions::PermissionAction` (`GRANTED`, `GRANTED_ONCE`, `DENIED`, `DISMISSED`) | `ArcPermissionResponseType` |
| `PermissionQuietReason` | none | `permissions::PermissionUiSelector::QuietUiReason` | `ArcPermissionQuietUiReason` |
| `MenuModel` / `MenuItem` | `CefMenuModel` (`GetCommandIdAt`, `GetTypeAt` → `MENUITEMTYPE_COMMAND/CHECK/RADIO/SEPARATOR/SUBMENU`, `GetLabelAt`, `IsEnabledAt`, `IsCheckedAt`, `GetGroupIdAt`, `GetAcceleratorAt`, `GetSubMenuAt`) | `ui::MenuModel` (`RenderViewContextMenu`'s `SimpleMenuModel`), command ids `IDC_CONTENT_CONTEXT_*` | `ArcMenuModel`, `ArcMenuItemModel` |
| `ContextMenuElement` | `CefContextMenuParams` (`GetXCoord/GetYCoord`, `GetPageUrl`, `GetFrameUrl`, `GetLinkUrl`, `GetSourceUrl`, `GetMediaType`, `GetSelectionText`, `IsEditable`, `GetMisspelledWord`, `GetDictionarySuggestions`); link text: **CEF: not available** | `content::ContextMenuParams` (`link_text` included) | `ArcContextMenuElementInfo` |
| `DownloadItem` | `CefDownloadItem` (`GetId`, `GetURL`, `GetSuggestedFileName`, `GetFullPath`, `GetMimeType`, `GetReceivedBytes`, `GetTotalBytes`, `GetCurrentSpeed`, `IsInProgress/IsComplete/IsCanceled/IsInterrupted`, `IsPaused` (API 14400+), `GetStartTime`); `canResume`: **CEF: not available** (tracked by `EngineCEF` from its own calls) | `download::DownloadItem` (`GetGuid`, `GetState`, `IsPaused`, `CanResume`, …) | `ArcDownloadItem` |
| `SecurityState` | `CefSSLStatus` (`IsSecureConnection`, `GetCertStatus`, `GetContentStatus`) | `security_state::SecurityLevel` + `VisibleSecurityState` | `ArcSecureContext` (`ArcSecureContextState` `None/Secure/Insecure`) |
| `AuthChallenge` | `GetAuthCredentials` arguments | `net::AuthChallengeInfo` | `ArcWebLoginDialog` |
| `CertificateError` | `OnCertificateError` arguments: `cef_errorcode_t`, `CefSSLInfo::GetX509Certificate` → DER chain | `net::SSLInfo`, `net_error` | none |
| `FileChooserRequest` | `OnFileDialog` arguments (`FILE_DIALOG_OPEN/OPEN_MULTIPLE/OPEN_FOLDER/SAVE`) | `blink::mojom::FileChooserParams` | none |
| `KeyEventInfo` | none (see `didConsumeKey`) | `input::NativeWebKeyboardEvent` fields | `didConsumeKey:withModifierFlags:underlyingEventType:` arguments |
| `TerminationStatus` | `cef_termination_status_t` (`TS_ABNORMAL_TERMINATION`, `TS_PROCESS_WAS_KILLED`, `TS_PROCESS_CRASHED`, `TS_PROCESS_OOM`, `TS_LAUNCH_FAILED`, `TS_INTEGRITY_FAILURE`) | `base::TerminationStatus` | `ArcWebContentsTerminationStatus` |
| `FindResult` | `OnFindResult(identifier, count, selectionRect, activeMatchOrdinal, finalUpdate)` | `find_in_page::FindNotificationDetails` | `ArcFindCompletion` arguments |
| `WebContentsConfiguration` | see `createWebContents` row | `WebContents::CreateParams` + RoomCore settings | `ArcWebContentsConfiguration` |
| `SiteDataTypes` | see `clearSiteData` row | `chrome_browsing_data_remover::DataType` masks | none |
| `EngineFeatures` | `--enable-features` / `--disable-features` | `base::FeatureList` | `ArcFeature` |

## CEF gaps summary (inputs to Phase 1.4 and the Chapter 2 caps)

Not available on CEF, with the CEF engine's behavior:

1. `Profile.history`, `bookmarks`, `extensions`, `makeAutocompleteController()` → `nil` (expected; RoomCore-only).
2. `Profile.favicon(for:)` → `nil`; the app caches favicons itself.
3. `WebContents.load` transition/`fromAddressBar` → ignored.
4. `themeColor`, `rootBackgroundColor` → emulated with JavaScript; `isAudible` → native "became audible" edge from `GetAudioParameters` (returning `false`), "stopped" polled with JavaScript (accuracy and cost measured in Phase 1.4).
5. `discard()` → emulated by closing the browser (back/forward list lost); `.frozen` → emulated with CDP `Page.setWebLifecycleState`.
6. `captureViewport()`, `executeJavaScript(_:)`, per-origin storage clearing, `transparentBackground` (`Emulation.setDefaultBackgroundColorOverride`) → emulated over the DevTools protocol.
7. `didConsumeKey` → never called; `ContextMenuElement.linkText` → `nil`; `DownloadItem.canResume` → tracked by `EngineCEF`; `PermissionResponse.grantedOnce` → accept (remembered per CEF's session); `quietReason` → always `nil`; `disallowAutoplay` → process-wide only; `initiallyHidden` → hidden parent view only.

RoomCore-side open points: certificate errors (interstitial vs. delegate), DevTools hosting (`DevToolsWindow` is Views-docked), main-world `executeJavaScript`, and attaching tab helpers (`TabHelpers::AttachTabHelpers` is friend-gated) need `//room` code beyond plain delegates.

## Review

2026-10-02: every row checked against the CEF 154 headers/libcef source, the Chromium 154.0.8037.58 checkout and the ArcCore headers (a separate review pass, ~83 rows). 19 corrections applied (signatures, enum names, M154 renames such as `chrome_security_state::GetSecurityLevel`, and four CEF "not available" claims that turned out emulatable or partial). Not verified by reading code: runtime claims marked *emulated* (Phase 1.4 measures them) and DevTools hosting through `DevToolsUIBindings` (Chapter 3 design).

2026-10-02 (Phase 1.4, implementation): five rows corrected from running code — `createProfile` cache path (must be a direct child of the root), `nativeView` (an owned host view), DevTools (no `SetAsChild`; docked front-end over the debugging port), `executeJavaScript` (message ids), `close()` (`DoClose` must return `true`). Also found: Alloy loads ⌘-click links in the current browser unless `OnOpenURLFromTab` cancels (the CEF engine opens new contents itself); `tryToTerminate` waits for every `OnBeforeClose` (including un-adopted popups, via `RoomCEFBrowser.didCloseNotification`).

## RoomCore background hardening (2026-10-03 component build)

The original feature drives do not cover the full Chrome UI contract. See
[the expanded UI surface audit](../research/notes/roomcore-ui-surface-audit.md)
for missing chooser, capture/session, autofill, extension, print-preview and
DevTools-hosting boundaries. This is Chapter 3 design input; no public ObjC API
is added by the audit.

The existing public ObjC headers remain unchanged. Private `-RoomSpike` host
commands exercise Chrome find/zoom/print without becoming product API.
RoomBrowserWindow now supplies a Views-backed modal parent, permission bubble
anchor, FindBarOwner, and FedCM bubble/modal anchors with a primary Views
context. Tab editability reflects the live model; explicit activation makes
NSApp active before making its window key. Native product UI still needs the Chapter 3 contracts
listed in research/notes/spike-results.md.

RoomCore startup policy suppresses automatic Chrome-account, cloud-policy,
component-update, Safe Browsing update, model/speech-download, search-preconnect
and time-query traffic. Ordinary page networking remains active. Component
registration and explicit update APIs remain available. A page request for
`com.widevine.alpha` provisions Widevine on demand through a document-scoped
internal Mojo service; installed CDMs are reused without an update request.
The service checks the active document, trustworthy origin and encrypted-media
policy, coalesces requests, and bounds failed provisioning to 60 seconds.
Fresh-profile MediaKeys creation is verified; licensed playback remains unverified.
See roomcore-network-audit.md under
research/notes for switches, hooks, measurements and scope limitations.
Crashpad uses `<selected user-data directory>/Crashpad`; callers omitting the
data directory retain Chromium's existing default. The Room host supplies its
Room/RoomCore root.

Serial quit is verified, but concurrent teardown remains an open reliability
issue; see research/notes/roomcore-shutdown-investigation.md. Diagnostic
sampling is opt-in and its timings are identified separately from baselines.

Renderer loss is contained by a Cocoa crash fallback for Room-owned pages,
using SadTabHelper's existing renderer-ready lifetime. Reload removes it and
restores the page in the component probe. This introduces no public API;
Chapter 3 still needs crash status, accessible retry and reporting UI.
