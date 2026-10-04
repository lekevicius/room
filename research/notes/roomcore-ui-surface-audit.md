# RoomCore Chrome UI surface audit — 2026-10-03

The active work is bounded by the user-approved
[UI compatibility scope](roomcore-ui-compatibility-scope.md), including six
work packages, stopping rules and completion criteria. This wider inventory
does not expand that Goal automatically.

The original 18 drives are a crash-path sample, not a complete Chrome UI audit.
This inventory expands the scope after the user's request for permissions,
downloads, extension popups, autofill, print preview, docked DevTools, media,
USB and connections. It is a source audit plus existing runtime evidence;
**no new runtime feature passes are claimed by this document.**

Source: pinned Chromium154.0.8037.58, local room HEAD920768ef9a67a, and Room
branch HEAD800cb7f. Local uncommitted patch0011 concerns shutdown workers, not
these UI surfaces. Source entry points below are relative to Chromium `src`.
The status refers to RoomCore, not the concurrently developed CEF product UI.

## Existing architecture decision

PLAN.md §4 already says to retain Chromium Views initially for autofill,
print preview, web-modal dialogs, DevTools docking and PDF. Room replaces the
outer window, toolbar/sidebar, permission presentation, downloads and extension
container. The engineering task is to make those ownership boundaries work;
it does not require rewriting every Chrome dialog in Swift.

The current transparent Views modal parent and permission anchor are useful
parts of that bridge. They do not supply Chrome's toolbar, tab content splitter,
capture indicators, chooser lifecycle or every controller registered on a
BrowserWindowInterface. A method returning null without crashing in one test
does not prove a supported feature.

## Concrete source findings

| Finding | Source / implication | Runtime qualification |
|---|---|---|
| Address-save/update bubbles dereference a missing handler | `chrome/browser/ui/autofill/address_bubbles_controller.cc` ShowSaveBubble/ShowUpdateBubble call `GetAutofillBubbleHandler()->Show...`; Room's implementation returns null | Source-confirmed unsafe boundary if reached. The earlier form-submit probe did not verify this bubble; not yet a reproduced crash |
| Download UI and pending-download close confirmation are missing | Room `GetDownloadBubbleUIController()` returns null; `ConfirmBrowserCloseWithPendingDownloads()` invokes its callback with true without asking | Byte-transfer and cancellation probes passed. Product download UI and user consent to interrupt downloads did not |
| Docked DevTools has a separate content-host contract | `chrome/browser/devtools/devtools_window.cc` Show invokes `DevtoolsUIController::From(browser)->UpdateDevtools` only if present. The controller's constructor takes `ContentsContainerView` objects and manages DevTools WebViews/focus | Room has no such controller implementation. A working CDP socket proves neither a visible frontend nor docking |
| Web and extension device choosers take different UI paths | `chrome/browser/ui/views/permissions/chooser_bubble_ui.cc`: web chooser computes an anchor/native parent; extension chooser dereferences `BrowserView::GetBrowserViewForBrowser(...)->toolbar_button_provider()` | Existing permission-anchor fix may help web choosers, but that is untested. Extension path has an additional BrowserView dependency |
| Print preview is its own modal WebContents | `chrome/browser/printing/print_preview_dialog_controller.cc`: chrome://print, modal host sizing and ShowConstrainedWebDialog | Dispatching IDC_PRINT without a crash did not verify preview generation, cancellation or output |
| Fullscreen remains deliberately unsupported | RoomExclusiveAccessContext reports CanUserEnterFullscreen=false and EnterFullscreen is empty | Existing runtime request rejects. This also affects video, pointer/keyboard lock and chooser/security transitions |
| Permission types exceed notification/geolocation | `components/permissions/request_type.h` includes camera/mic, PTZ, capture control, local/loopback network, clipboard, MIDI, storage, fonts, locks and window management | Only notification/geolocation denial callbacks were previously measured; platform/build gates must be checked for each remaining type |

## Inventory and acceptance boundaries

“Partial” means the specific existing probe passed; the remaining items are
not accepted. “Undriven” means no retained RoomCore runtime proof, even if
Chromium already implements the underlying feature.

| Family | UI Room must handle | Current evidence | Next discriminating drive |
|---|---|---|---|
| Site permissions | Requesting and embedding origin, allow/deny/dismiss, one-time/persistent where supported, quiet prompts, settings/revocation | Partial: notification/geolocation Deny callbacks; anchor bridge exists | Drive each request class; close/navigate tab while pending; verify one completion and correct stored permission |
| Camera/microphone | Combined/separate grants, input selection, denied/unavailable/in-use errors, macOS privacy state, active indicator and stop | Undriven | Synthetic capture plus real denial path; real hardware/OS consent separately, no automatic grant of actual camera/mic |
| Screen/window/tab capture | Source picker, audio option, cancel, persistent sharing indicator, stop/switch source, captured tab closing, OS screen-recording consent | Undriven | Picker open/cancel with no capture; then synthetic/controlled capture lifecycle; real screen acceptance separately |
| Video playback | Controls, seek, codecs actually built, captions, fullscreen, renderer/GPU loss | Partial: page loading; no dedicated video acceptance | Local generated clip; duration/frames/seek; separate native fullscreen transition and restoration |
| Audio and Media Session | Audible/muted state, per-tab mute, media keys, play/pause/seek metadata, output-device selection and disconnect | Partial: WAV clock and muted48kHz Web Audio clock advance | Compare engine audible/mute/session state with actual controls; output picker cancel/change; audible hardware check remains separate |
| Picture-in-picture | Video PiP and document PiP window ownership, controls, return to tab, closure and origin display | Undriven | Both APIs; close owner, navigate owner, return and resize; preserve independent window lifetime |
| DRM | Provisioning, unsupported/error state, protected playback and its media controls | Partial: on-demand Widevine MediaKeys; no licensed playback | Authorized licensed sample; verify actual playback rather than accepting MediaKeys creation as playback |
| USB / HID / Serial / Bluetooth | Device chooser, filters, pairing where applicable, connect/disconnect, remembered grants and revoke, extension-origin variants | Undriven; source paths located | First empty/fake-device chooser cancel and tab-close; then a deliberate test device connect/unplug/revoke. Never send arbitrary commands to attached devices |
| Network connections and security | Local/loopback-network permission, offline/DNS/TLS errors, proxy/server auth, client-certificate picker, site security/details and revocation | Partial: HTTP Basic cancel/supply and bad-cert leave; laptop TLS errors attributed | Controlled fixtures for other paths; client-cert chooser cancel; inspect effective local-network feature flags. Ordinary WebSocket/WebTransport connections do not imply a new per-connection UI |
| Cast / remote playback | Deliberately initiated receiver discovery, route picker, connection failure/status and stop | Undriven; product support decision needed | Open/cancel without discovering unrelated devices; later explicit test receiver. Qualify discovery traffic separately from zero-idle policy |
| Downloads | Destination/save sheet, progress, pause/resume/cancel, retry/interruption, reveal/open, multiple-download permission, dangerous-file handling, close confirmation | Partial:26-byte download and cancellation at131072/33554432bytes, no residual file; current close stub auto-confirms | Close with active download and assert explicit decision; destination cancel; interruption/resume; controlled danger-state fixture, not a malicious download |
| Uploads and filesystem access | Open/multiple/folder/save pickers, drag/drop, persistent read/write grants, overwrite, revoked/stale handles | Undriven | Ordinary file input versus File System Access APIs; isolated temp files, cancel/save/overwrite and tab destruction |
| Autofill and passwords | Field suggestion popup; address/card save/update; password save/update/generate; account selection; local reauthentication | Partial: form submitted; neither saved data nor bubbles accepted | Fresh synthetic address/password fixtures; explicitly open actual controllers, accept/cancel/update, reopen and fill; local-card test without payments/account upload |
| Passkeys and identity | WebAuthn authenticator selection, platform/security-key paths, cancellation, FedCM account/consent UI | Partial: FedCM passive/active parent paths survive; no account/token exchange | Virtual authenticator and controlled RP/IdP; cancel, tab destruction and result delivery. Hardware key/Touch ID separate |
| Extensions | Action popup anchored to Room, focus/resize/close, install/update permission consent, site access, options/management, commands, side panel and device requests | Partial: MV3 worker/content and tabs/windows lifecycle; action.openPopup reaches missing-toolbar error | Actual action popup first; then consent, side panel, extension-origin chooser and uninstall while popup open |
| Printing and documents | Chrome print preview, settings, destination, PDF generation, system print panel, cancel; embedded/full-page PDF viewer and download | Partial: IDC_PRINT survives only | Open real preview, assert generated pages, cancel and reopen; save PDF to temp and inspect pages. Page.printToPDF is not proof of preview UI |
| DevTools | Embedded frontend, right/bottom/left docking, splitter geometry, undock/redock, inspected tab mapping, keyboard focus and close | Undriven; CDP test infrastructure is separate | Local page, open/inspect/evaluate, dock/resize/undock/redock, switch/close inspected tab; no remote debugging port in ordinary product operation |
| Web dialogs and page controls | JS alerts/prompts/beforeunload, select/date/color menus, context menu/spelling, eye dropper, focus restoration | Partial: JS callbacks/beforeunload cancellation and date trigger; not all native controls | Each transient surface with move/resize/tab switch/close; assert expected result exactly once |
| Navigation and window UI | New window/popup adoption, blocked popup affordance, status-link text, find, zoom, external-protocol consent | Partial: Chrome fallback popups, find400 matches and zoom transitions; native product routing unfinished | Route all dispositions into Room, opener lifetime and popup close; protocol-launch cancel; find keyboard routing |
| Exclusive access / multi-display | Fullscreen origin/escape UI, pointer/keyboard lock escape, window-placement permission and display selection | Unsupported fullscreen; rest undriven | Explicit rejected-state contract until implemented; then enter/exit/Escape/navigation loss and monitor removal |
| Notifications and recovery | Notification click/action routing to correct tab/profile; renderer crash, hung-page wait/close, process loss and recovery | Partial: permission denial and renderer crash/reload fallback | Controlled notification delivery/click acceptance; hung-renderer fixture with bounded recovery, no suppression of watchdogs |
| Other browser surfaces | Translate, site-data controls, storage access, local fonts, idle/sensor permissions, web-app install, reader/save-page, extension-backed WebUI | Mostly undriven; some optional/product-scoped | Check enabled desktop paths and decide supported/explicitly unavailable individually; no silent success from stubs |

Camera permission is not screen-sharing permission. WebUSB/WebHID/Serial/
Bluetooth selection is not the generic allow/deny prompt. Local-network access
is distinct from a device grant and from macOS privacy authorization. A
notification permission prompt is distinct from notification delivery/click UI.

NFC, ChromeOS smart-card and ChromeOS web-printing entries in the shared enum
are not automatically Mac requirements. XR, sensor, web-app and service-backed
features also require effective build/feature checks. Chrome account/sync,
surveys/promotions and automatic background service discovery are not made
Room requirements merely because Chrome has UI for them. No account/payment
cloud feature is re-enabled by this audit.

## Shared integration work

1. **Anchors and transient ownership:** map tab/window/origin to a stable
   native parent and anchor rectangle, convert coordinates, update on resize,
   restore focus, close on navigation/destruction. Preserve trusted origin UI.
2. **Decisions and choosers:** distinguish pending/accepted/denied/dismissed;
   complete once, cancel on owner destruction, isolate profile grants, expose
   revoke/settings. A null handler or auto-confirm is not an implementation.
3. **Embedded Chrome content:** host print/PDF/DevTools WebContents and the
   necessary Views controllers with explicit sizing, focus and ownership.
   Reuse frontends; adapt the host contract.
4. **Persistent activity UI:** downloads, recording, sharing and device/media
   sessions outlive their opening bubble. Keep status and stop/cancel/revoke
   reachable when their tab is hidden; clean up on navigation/profile close.
5. **OS integration:** separate browser grants from macOS privacy, Keychain,
   file/print panels, notifications and media controls. Engine plumbing alone
   cannot prove these native interactions work.

These are Chapter3 design inputs, not additions to public ObjC headers in
this branch. Existing Engine protocol coverage must be reconciled during that
design; generic page delegates alone do not express every chooser/session.

## Bounded next spike batch

Priority now shifts from repeated shutdown stress to missing UI boundaries.
Use one fixture and one bounded host process per row; retain failures and stop
to inspect the first missing contract. Do not label a private test-hook action
as a product control. Keep B-38 separately open.

1. Address save/update and suggestions: reach the confirmed null-handler
   boundary deliberately; implement the smallest existing-hook bridge if needed.
2. Device choosers: web USB/HID/Serial and Bluetooth empty/fake cancel;
   extension-origin variant separately. No real device connection by default.
3. Real print preview and docked DevTools: count them as separate embedded
   frontend/ownership tests, not command-dispatch/CDP connectivity tests.
4. Extension action popup: actual content visible in owned host with focus,
   close and resize. Inventory side-panel/consent gaps separately.
5. Camera/mic and screen-share deny/cancel, then controlled media/PiP and
   persistent indicator lifecycle. Native/real-device acceptance stays marked.
6. Download close decision and file chooser cancellation; verify callbacks
   and preserved files, not just process survival.

Each engine fix still requires rebuild, its focused regression and the real
nav/ten-page clean-quit baseline. Source-only rows remain undriven until that
specific behavior is observed. AGENTS prohibits accessibility/computer-use;
native click/focus/visual acceptance is explicitly retained for reviewer use.

## Source index

Deeply inspected call sites: the seven findings above, plus
`chrome/browser/devtools/devtools_ui_controller.h`,
`chrome/browser/media/webrtc/desktop_media_picker_factory_impl.cc`, and Room's
`room_location_bar.cc`, `room_exclusive_access_context.cc` and window stubs.
Other entry points located for the next drives (not full implementations audited):

- Permissions: `components/permissions/request_type.h`,
  `chrome/browser/ui/views/permissions/permission_prompt_factory.cc`.
- Capture/output: `chrome/browser/media/webrtc/permission_bubble_media_access_handler.cc`,
  `system_media_capture_permissions_mac.mm`, `media_stream_capture_indicator.cc`,
  `chrome/browser/ui/views/select_audio_output/select_audio_output_dialog.cc`.
- PiP/Cast: `chrome/browser/picture_in_picture/picture_in_picture_window_manager.cc`,
  `chrome/browser/ui/media_router/media_router_ui.cc`.
- Devices: `chrome/browser/usb/web_usb_chooser_desktop.cc`,
  `chrome/browser/serial/web_serial_chooser_desktop.cc`,
  `chrome/browser/hid/chrome_hid_delegate.cc`,
  `chrome/browser/ui/bluetooth/chrome_bluetooth_chooser_controller.cc`.
- Downloads/files: `chrome/browser/download/bubble/download_bubble_ui_controller.cc`,
  `chrome/browser/file_select_helper.cc`,
  `chrome/browser/file_system_access/chrome_file_system_access_permission_context.cc`.
- Autofill/passwords: `chrome/browser/ui/autofill/autofill_popup_controller_impl.cc`,
  `chrome/browser/ui/passwords/manage_passwords_ui_controller.cc`.
- Authentication/security: `chrome/browser/ui/views/webauthn/authenticator_request_dialog_view.cc`,
  `chrome/browser/ssl/ssl_client_certificate_selector.h`,
  `chrome/browser/ui/views/page_info/page_info_bubble_view.cc`.
- Extensions: `chrome/browser/ui/views/extensions/extension_popup.cc`.
- Other UI: `chrome/browser/renderer_context_menu/render_view_context_menu.cc`,
  `chrome/browser/external_protocol/external_protocol_handler.cc`,
  `chrome/browser/ui/views/hung_renderer_view.cc`.

Official API context: [USB chooser and prior grants](https://developer.chrome.com/docs/capabilities/usb),
[DevTools customization](https://developer.chrome.com/docs/devtools/customize),
[local-network permission](https://developer.chrome.com/blog/local-network-access).
The pinned checkout governs implementation; published rollout descriptions do
not prove which local feature flags are enabled.
