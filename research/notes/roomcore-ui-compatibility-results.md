# RoomCore UI compatibility results — 2026-10-03

Status: **in progress**. This implements the bounded
[scope](roomcore-ui-compatibility-scope.md); it does not claim Chapter 3 UI is
built. The wider [inventory](roomcore-ui-surface-audit.md) is source research,
not runtime acceptance. The old shutdown investigation is deferred (now B-19;
main's B-16 is a separate sidebar item).

## Source isolation and identities

The old shutdown patch0011 candidate is archived under
`research/notes/deferred-shutdown/` and preserved on Chromium branch
`room-deferred-shutdown-0011` at920768ef9a67a. Active Chromium was restored to
the ten accepted patches at7ac71cfacf83f before this pass. Room rebased onto
origin/main2239107; checkpoint cdcb7a1 contains the preserved candidate.
No Chapter2 implementation was changed. New UI patch0011 is a different patch,
`0011-browser-window-lookup-hook.patch`; it is not the deferred scheduler patch.

Autofill tested before commit: Room cdcb7a1 plus UI diff, accepted after rebase as9b08d74; Chromium
2f06f6d7533a515a94386027cc8020775f3aec9e. The update/device package hashes are in feature-ui-autofill-build/identity-update.json.
Save repair2 completed before the host-only update-fixture rebuild; its engine
hashes match, but the old host binary hash was not captured (identity gap). Original public headers and patches0001–0005 stay
unchanged. Existing zero-idle audit belongs to its recorded older package;
no new network-audit claim is made here.

## Package 1 — address bubbles, current checkpoint

| Path | Actual trigger and result | Status and Chapter 3 contract |
|---|---|---|
| Address save | `scripts/roomcore-features.sh autofill-save <new-directory>` invokes Chrome AddressBubblesController with a synthetic local address. Initial run crashed at ShowSaveBubble+104 (SIGSEGV, exit139,15s). First repair still crashed at the same missing-window lookup. Second repair reached SaveAddressProfileView: one owned visible dialog; cancel decision3/count1; accept decision2/count1; tab destruction decision7/ignored/count1. | Bubble/callback repair demonstrated; required serial baseline passes. Final-tab fixture exit remains blocked: after closing the final tab, the process stayed in its main event loop and the90s outer watchdog terminated it (receipt100s,exit143). This is not a clean process pass. Native anchor/focus and saved-profile persistence are unverified. |
| Address update | `scripts/roomcore-features.sh autofill-update <new-directory>`; real UpdateAddressProfileView, owned-dialog count1; cancel and accept each callback1; owner-close ignored callback1. 11s,exit0. A second blank tab keeps final-window termination separate. | Works in spike for presentation/decisions/owner lifetime. Persistent profile updates and native focus remain unverified. |
| Address suggestions | Separate field-popup path; save-bubble callbacks do not prove filling. | Pending. |
| Password save/update | PasswordBubbleViewBase uses ToolbarButtonProvider::From(browser); Room has none. The private autofill anchor adapter is deliberately not a fake global Chrome toolbar. | Pending controlled runtime boundary probe; not supported by the address fix. |
| Local card save | Local synthetic record only; no upload/payment. | Pending. |

Evidence: `feature-ui-autofill-save-initial`,
`feature-ui-autofill-save-repair1`, `feature-ui-autofill-save-repair2`.
The last run completed all three decision paths before its exit failure.
A single1s sample during the wait put main in NSApplication's ordinary event
loop (797 samples), not in a dialog decision or the earlier10s teardown
watchdog. No third address-save engine repair round will be opened. Address-update
then passed with another tab retained; the final-tab exit defect remains
recorded rather than hidden by that fixture distinction.

Required serial baseline `baseline-ui-autofill`: nav15.105s, all10 real pages
loaded, quit2.933s,28helpers observed/0left,0newcrashreports,exit0; load1
20.385. No diagnostic sampling. Final repair build63s/5steps, GN dependency
check passes, package stage5s/host10.3s, strict ad-hoc signature valid.
Host-only update fixture rebuild and stand-in typecheck pass.

### Narrow repair and why a patch is needed

The initial inventory found Room's null GetAutofillBubbleHandler, but the
runtime crash occurs **before** that call: BrowserWindow's legacy lookup
returns only BrowserView, including its tab-collection fallback. A Room tab
therefore yields null despite having a RoomBrowserWindow. Existing window
factory and location-bar anchor hooks cannot change this lookup.

New nullable lookup hook returns the registered Room window only for its own
tabs; Chrome fallback windows keep the original lookup. Room lazily owns the
existing AutofillBubbleHandlerImpl and a private anchor adapter backed by its
existing Views modal parent. It does not register a ToolbarButtonProvider
with nonexistent extension/menu controls. On accept, Chrome's optional iOS
address promotion dereferences AsBrowserView before testing eligibility;
a null/AsBrowserView guard skips that Chrome-toolbar-only promotion. A pref
cannot avoid that earlier dereference. These two tiny upstream changes are
patch0011. All presentation and decision behavior remains Chrome's.

Chapter3 must provide a stable tab/window parent and anchor with resize,
focus restoration, owner-close cancellation and persistent form-data flow.
This spike's direct controller callback does not import/save the synthetic
address into the user's profile.

## Remaining packages

| Package | Current evidence / next bounded drive |
|---|---|
| Device choosers/connections | Web USB/HID/Serial/Bluetooth chooser cancellation passes (table below). Empty filters/fake Bluetooth; cancel only, never select hardware. Extension-origin and local-network gates remain separate. |
| Print preview / DevTools | Real print preview/pages/cancel/reopen/PDF passes; docking has verified missing-controller blocker (below). Native print-panel/focus remains reviewer acceptance. |
| Extension action UI | action.openPopup has a verified toolbar/container blocker. Source map below; direct Chrome ExtensionPopup hosting through the existing Room anchor remains a useful private probe before closing this package. |
| Media/capture | Denial, synthetic capture/stop, generated playback, screen-picker cancel and video PiP measured below. Document PiP also closes with its owner; native activity UI remains a concrete Chapter3 contract. |
| Downloads/file dialogs | Existing bytes/cancel evidence retained; pending-download close decision and picker cancellation/lifetime still to investigate. |

The Goal remains active. Rows marked pending are unfinished, not architectural
blockers or completed investigations.

## Package 2 — web device chooser cancellation

Commands use `scripts/roomcore-features.sh <name> <new-directory>`, current
update-fixture package (identity above). USB/HID/Serial use vendor/product
65535 filters; Bluetooth uses CDP BluetoothEmulation's powered-on fake adapter
and an unmatched name. Nothing selects/connects a device. Each web request
uses a user gesture and its promise settles through Chrome's actual cancel
callback; private Views action invokes the owned dialog's CancelDialog.

| Fixture / evidence directory | Result | Ownership and remaining acceptance |
|---|---|---|
| ui-usb / feature-ui-usb-initial | One visible owned chooser; cancellation rejects NotFoundError; 10s,exit0 | Existing LocationBarBubbleDelegateView parent works. Real grants/revoke/unplug and native focus remain unverified. |
| ui-hid / feature-ui-hid-initial | One visible owned chooser; cancellation resolves empty list,granted=false; 10s,exit0 | Same Chrome chooser parent; HID cancellation correctly differs from USB. Hardware acceptance remains separate. |
| ui-serial / feature-ui-serial-initial | One visible owned chooser; cancellation rejects NotFoundError; 10s,exit0 | No port opened. Device grant lifetime/unplug remains unverified. |
| ui-bluetooth / feature-ui-bluetooth-repair1 | One visible owned chooser, CDP prompt with0devices; cancel rejects NotFoundError;12s,exit0 | Fake adapter only. First setup failed7s because BluetoothEmulation belongs to browser CDP, not page; one source-backed host correction. Native pairing/hardware remains unverified. |

The web entry points converge on chrome::ShowDeviceChooserDialog and
ChooserBubbleUiViewDelegate in chooser_bubble_ui.cc. Its cancel handler is
DeviceChooserContentView::Cancel. The extension-origin branch instead calls
BrowserView::GetBrowserViewForBrowser(browser)->toolbar_button_provider()
without a nullable BrowserView guard, then ShowWidgetForExtension; it has
not been runtime-qualified by these web probes. Chapter3 needs extension
identity/anchor ownership separately from generic web origin UI. Tab-close,
local-network permission and extension-origin probes remain pending.

## Package 3 — embedded frontends

Private probes are `ui-print-preview` and `ui-devtools`, invoked through the
feature runner. Initial diagnostic build: 31 s / 13 steps, load31.15/39.85/34.79;
GN dependency check and strict ad-hoc packaging pass (stage3.7s,host15.2s).
Source parent9b08d74, Chromium2f06f6d7533a5; exact initial package hashes are in
feature-ui-embedded-build/identity.json. No production behavior change.

| Subfeature | Evidence | Status / Chapter3 contract |
|---|---|---|
| Real print frontend/pages | feature-ui-print-preview-initial: chrome://print target; app READY1, page count1, preview display-preview.29s,exit0 but driver fails after Cancel destroys the target/socket before replying. | Corrected verification passes both rendered previews, cancel/reopen and PDF output (final result below). Initial transport failure retained; no Page.printToPDF substitution. |
| Docked DevTools | feature-ui-devtools-initial: actual devtools_app.html target and DevToolsWindow/native window; bitmask10 = window exists + native parent, no controller/no docking.9s,exit0. | **Blocked by verified ownership prerequisite.** DevToolsWindow::Create checks DevtoolsUIController::From(browser), which is null for Room, and sets can_dock=false before creating frontend. No dock/resize/redock/focus pass claimed. Frontend was only interactive/bodyChildren0 when sampled; this is not functional undocked-frontend acceptance. |

Chapter3 must supply an actual inspected-tab/DevTools content host. Chrome's
DevtoolsUIController constructor requires ContentsContainerView objects and
owns DevtoolsWebViewController entries with external focus tracking, resizing
strategy restoration and attach/detach subscriptions. Room's current native
page view does not implement that contract. A null guard or claiming a
controller exists would not create the missing docked content, splitter or
focus behavior. Dock/resize/undock/redock and inspected-tab-close acceptance
therefore depend on that Chapter3 host, with native focus reviewed separately.
No upstream patch or product docking implementation is added by this probe.

## Package 4 — extension action and consent contracts

This package reuses the retained actual MV3 action.openPopup result instead of
repeating the completed tabs/windows controls. Source checked at Chromium
2f06f6d7533a5; the toolbar feature check and absence of Room's extension UI
container remain unchanged.

| Subfeature | Evidence / exact boundary | Chapter3 requirement |
|---|---|---|
| Action popup open, ownership, resize, close, focus | feature-extension-activation/spike.txt (receipt source parent7974cd0 plus activation change later committed as eb55062;18s/exit0): active/key/main/visible window, then real action.openPopup rejects "Browser window has no toolbar." Current Room IsToolbarVisible still returns false. extension_action_api.cc OpenPopupInBrowser checks this before ExtensionsContainer::ShowToolbarActionPopupForAPICall. **Product API blocked**; separate direct-host probe below establishes popup content, ownership, focus state, resize and close. | Implement real ExtensionsContainer/ExtensionsToolbarViewModel delegate and per-action view model; own ExtensionViewHost, anchor, shown/closed callbacks and focus. Turning the toolbar boolean true cannot supply these contracts. |
| Popup content sizing/lifetime | Source-map: ExtensionPopup owns ExtensionViewHost, observes widget/extension registry/tab strip/WebContents, delays showing until load; min25×25,max800×600. | Reuse Chrome view host or supply Room container that preserves extension identity, resize limits, close on unload/tab change, and DevTools inspection lifetime. Native anchor/focus needs reviewer acceptance after hosting exists. |
| Install/update consent | Source-map only: ExtensionInstallPrompt::ShowConfirmation obtains the permission set and icon, checks WasParentDestroyed and completes ABORTED, otherwise invokes ShowDialogCallback with a once completion. | Retain requesting extension/permissions and parent lifetime; expose approve/cancel/abort exactly once. No installation or real permission grant was performed by this audit. |
| Site access / requests | Source-map only: ExtensionsToolbarViewModel::GrantSiteAccess and PermissionsManager observers; PermissionsManager::UpdateUserSiteSetting/GetUserSiteSetting operate on origin settings. | Present extension + current origin + scope, explicit grant/revoke, pending request and navigation changes; keep Chromium permission storage authoritative. No fake global toolbar provider or blanket permission enable. |
| Side panel | Source-map only: SidePanelCoordinator constructor CHECKs GetSidePanel(); lookup uses BrowserElementsViews kSidePanelElementId. Room has no SidePanel host. | Register and own side-panel content/entry lifecycle, geometry, tab/profile association and close/focus. An extension service worker alone cannot provide the content host. |

These are concrete product ownership boundaries, not failures to be bypassed
with more stubs. The action API blocker is verified. Direct ExtensionViewHostFactory::CreatePopupHost
and ExtensionPopup::ShowPopup accept a BrowserWindowInterface and bubble anchor;
the private direct-hosting probe below now passes actual popup content/lifetime.
It does not claim a working action toolbar or bypass the product API gate. Consent/site-access/side-panel items
are explicitly source-map scope, not runtime support claims.

### Print preview final bounded result

`feature-ui-print-preview-repair1`:29s,exit0. Both opens produced a distinct
chrome://print target, READY1/pageCount1/display-preview, then the actual
WebUI Cancel button destroyed that target. First preview exported49,366bytes
from PrintPreviewUI::GetPrintPreviewDataForIndex(COMPLETE_PREVIEW_DOCUMENT_INDEX);
`pdfinfo` confirms one A4 page, PDF1.4, Skia/PDF m154, title RoomCore features,
unencrypted. This is actual preview-pipeline data, not Page.printToPDF and
not an assertion that the native Save-to-PDF panel works. Native view had a
window and parent (both1). Native focus and printer/destination selection
remain reviewer checks; no physical printer used.

One host verification correction handles cancellation racing its CDP reply,
then requires target disappearance; errors are never ignored without that
check. A private CLI-only diagnostic exports the completed preview bytes
without overwriting existing files. It initially failed compilation because
RefCountedMemory was only forward-declared; adding its header built25s/2steps.
GN passes; package stage4.4s/host8.5s, strict signature valid. No production
engine behavior, patch or network policy changed. Existing serial baseline
remains qualified to its original binary; no new baseline is claimed here.

Each new feature run now captures actual host/framework/component SHA256
identities before launch. Committed roomcore-ui-embedded-checkpoint.json
retains both probe identities and outcomes; raw PDF/profile/logs remain in
the ignored feature directory.

## Package 5 — synthetic media and capture

Source parent 2f36864 plus private diagnostic hooks, Chromium 2f06f6d7533a5.
Each raw feature directory includes exact prelaunch binary/source hashes.
The capture acceptance/stop hooks require a loopback page, -RoomSpike and
--use-fake-device-for-media-stream; accept additionally rejects every request
type except camera/microphone. Chromium's macOS system permission wrapper
explicitly treats fake devices as allowed, so no real camera/mic consent or
capture is involved. No production media policy or public API changes.

| Required subfeature | Measured evidence | Status / ownership contract |
|---|---|---|
| Camera denial | feature-ui-camera-initial: one real PermissionRequestManager::Deny; NotAllowedError/Permission denied; 18 s, exit 0 | Works in synthetic spike. Real macOS privacy and camera selection remain hardware/native acceptance. |
| Microphone denial | feature-ui-microphone-initial: one Deny; NotAllowedError/Permission denied; 8 s, exit 0 | Same browser decision path; real mic/output hardware unverified. |
| Capture start, indicator state, stop | feature-ui-capture-initial: one Chrome Accept for combined fake devices; live Fake Default Audio Input + fake_device_0 tracks. Indicator bitmask 3 (audio+video), actual StopMediaCapturing(kUserMedia), both tracks ended and indicator 0. 12 s, exit 0. | Engine state/callbacks work. This is not a persistent recording UI pass. |
| Screen-share cancel | feature-ui-screen-share-initial: DesktopMediaPickerDialogView actually opened; two CancelDialog invocations before asynchronous close, one settled getDisplayMedia rejection (NotAllowedError, Permission denied by user). 14 s, exit 0. | Cancel path works; no source selected and no screen captured. Sharing start/stop indicator and OS screen-recording consent require deliberately authorized native capture. |
| Generated video | feature-ui-video-initial: local canvas → VP8/WebM, 3,951 bytes, 4 decoded frames, playback time 0.252212 s; 15 s, exit 0. | Playback works; generated media only. Does not qualify arbitrary codecs, protected playback or audible hardware. |
| Tab mute / audible state | Same video run: Web Audio runs at 48 kHz, clock 0.410667 s; engine state 3 = muted and currently audible. Stop/close AudioContext follows. | Muting and pre-mute audible state coexist as expected. Room needs observable audible/mute state and per-tab controls; current public embryo exposes neither. |
| Video PiP | Initial entry/exit succeeds; initial reported size 0×0 was sampled after exit. Blink PictureInPictureWindow::OnClose explicitly zeros size. | feature-ui-video-verification1 reads dimensions before exit:590×332, entered/closed true;12s,exit0. Generated VP8 decodes8frames at0.252223s; muted Web Audio48kHz/0.405333s,engine state3. Works in spike. Native focus/return-to-tab controls remain unverified. |
| Document PiP | feature-ui-document-pip-initial: 320×180 window opens and closes; 11 s, exit 0. | First lifetime verification failed its observer setup (8s,exit0,driver failure): three new CDP targets appeared, so a target-count delta did not identify the PiP page. Final verification2 identifies the unique PiP fixture target; pageClosed=true and targetGone=true after owner close (9s,exit0). Native adoption/focus remains separate. Room adoption/focus remains Chapter3. |
| Fullscreen | Existing recorded rejection retained; RoomExclusiveAccessContext::CanUserEnterFullscreen=false and EnterFullscreen is empty. Unchanged by this batch. | Explicit unsupported boundary, not a successful video fullscreen feature. Chapter3 needs origin/escape UI and restoration. |
| Output selection | Actual media-capabilities: selectAudioOutput is undefined, setSinkId is a function. Blink SelectAudioOutput IDL is runtime gated; pinned runtime feature default status is test. | Disabled-feature boundary in this build. If supported later, SelectAudioOutputPickerViews uses CreateMediaPickerDialogWidget with native parent/content view; its dialog returns selection or kUserCancelled exactly once. No actual output device selected. |
| Media keys / OS controls | Source-map: content MediaKeysListenerManagerImpl creates browser singleton SystemMediaControls; ActiveMediaSessionController routes commands and SystemMediaControlsNotifier exports metadata. | Retain Chrome routing with correct active session/tab/profile. Physical keys and macOS Now Playing need native acceptance; setting page metadata alone is not proof. |
| Widevine | Existing on-demand provisioning evidence retained; no repeated download/license test. | Licensed playback remains explicitly outside this pass. |

### Persistent capture UI is a real missing Room contract

MediaStreamCaptureIndicator::UpdateNotificationUserInterface skips ordinary
web tabs on desktop when building its tray icon: Chrome expects their tab
icons to show capture status. Room's host has no capture observer/indicator
and its public embryo has no capture-state/stop API. The private diagnostic
proved the underlying state and stop callbacks, not a visible user control.
Chapter3 must subscribe to capture changes for the correct tab/profile,
retain an indicator when a tab is hidden, expose a reachable stop action,
and clear it on stream end/navigation/owner loss. Screen-sharing sessions
add source identity and OS permission, separately from camera/mic grants.

No native permission was auto-approved, no real device was connected, and no
physical printer or capture source was selected. Native/hardware limitations
remain acceptance work, not reasons to implement additional test stubs.

### Media checkpoint qualification

Media diagnostic build34s/2steps, load56.72/50.34/44.80; GN dependency check,
stand-in Swift typecheck, shell syntax and strict ad-hoc packaging pass.
No production engine fix or upstream patch in this batch, so no new serial
baseline or zero-idle audit is claimed. Initial video PiP size sampling was
a probe error (dimensions read after close resets them); one host correction
measured590×332 before closing. Document PiP owner-lifetime verification
needed two bounded observer rounds: global target-count delta was ambiguous,
then unique content matching proved owned-target destruction. Failed observer
receipt remains retained; no engine repair was made for either probe issue.
Exact identities/outcomes are in roomcore-ui-media-checkpoint.json.

Next work remains address suggestions/password/card boundaries, extension
device chooser and local-network/lifetime checks, direct MV3 popup hosting,
and download-close/file-dialog decisions. The Goal is still in progress.


### Package 4 direct popup — completed bounded probe

`feature-ui-extension-popup-initial`:18s,exit0. Private loopback-only CLI hook
uses the loaded fixture MV3 extension with Chrome's real
ExtensionViewHostFactory::CreatePopupHost and ExtensionPopup::ShowPopup.
The existing Room Views anchor owns its native window. State15 means present,
visible, Room-owned and active; document.hasFocus=true and the actual content
is “Room spike popup.” Changing content size from the fixture default to
360×240 resized the widget client area from66×80 to374×266 (includes Chrome's
popup framing). Explicit close destroyed the target. Reopen created a distinct
target; closing the owner tab destroyed that target too, with another blank
tab retained. Both show callbacks reported shown=1. No repair round needed.

This proves reusable Chrome popup hosting independently of the verified
missing-toolbar action API boundary. Native placement/focus restoration and
keyboard interaction remain reviewer acceptance. Chapter3 still needs real
extension action/container ownership, action identity, origin/site access,
anchor geometry and menu/toolbar routing; a true IsToolbarVisible return alone
is insufficient. No production UI policy or patch changed.

Probe build33s/13steps; GN dependency check and stand-in Swift typecheck pass.
Ad-hoc packaging stage4.4s/host18.7s, strict signature valid. Exact tested
source/binary hashes and receipt are in roomcore-ui-extension-checkpoint.json.
No new serial baseline or idle-audit claim: these are disabled-by-default
private diagnostics, with the existing production fix baseline preserved.

### Main reconciliation at this checkpoint

Rebased onto origin/main8522d6f. The only conflict was independent appended
spike-results.md sections; retained both main's complete Phase2.4a measurements
and RoomCore's modal findings. Engine/roomcore and App/RoomCore were byte-for-byte
unchanged by the rebase against former checkpoint bfbd7c0. Direct-main scope
for Packages, App and ROADMAP contains only App/RoomCore. Historical measurement
source hashes above intentionally retain their pre-rebase identities.
