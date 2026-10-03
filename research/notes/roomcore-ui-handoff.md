# RoomCore Chrome UI handoff — 2026-10-03

The six-package compatibility investigation is concluded. It produced real
Chrome UI probes, three narrow crash fixes, and concrete Chapter3 ownership
requirements. It did **not** build the product toolbar, permission/download
manager, docked DevTools or a finished browser API.

The [agreed scope](roomcore-ui-compatibility-scope.md) caps each path at an
initial drive plus two source-backed rounds. The
[full results](roomcore-ui-compatibility-results.md) retain failed fixtures,
callback evidence, exact package hashes and source references.

| Package | Established in the spike | Remaining implementation / acceptance |
|---|---|---|
| Autofill/passwords | Address save/update use real Chrome bubbles and accept/cancel callbacks. Fixed missing Room-window lookup and card-handler registration crashes. Local card cancel/accept each callback1. Actual address suggestion controller generates3rows. | Password save/update presentation stops at missing ToolbarButtonProvider. Suggestion **fill is unverified**: probe keyDown bypassed raw-key popup listeners. Card **owner-close is unverified**: third bubble setup failed. Address final-tab exit also failed; update with another tab retained passed. Persistence, keyboard routing and native focus need acceptance. |
| Permissions/devices/connections | Web USB/HID/Serial/fake Bluetooth cancel; USB owner close removes chooser. Local/loopback network prompts enforce deny, allow, grant reuse and reset; loopback grant survives tab close. Fixed extension-origin chooser crash to safe NotFoundError. | Safe extension rejection is not a chooser. Need extension identity/container hosting, grant display/revoke and origin/profile ownership. Real USB/HID/Serial/Bluetooth connection/unplug/pairing and macOS privacy remain hardware/native work. |
| Print/DevTools | Actual Chrome print preview produces1displayed page, cancels/reopens, exports49,366-byte one-page PDF from the preview pipeline. | Native printer/Save-to-PDF destination and focus unverified. Docking is blocked by absent DevtoolsUIController/ContentsContainerView; a DevToolsWindow exists but no functional docked or undocked frontend pass is claimed. |
| Extensions | Real MV3 popup is visible, active, Room-owned and document-focused; resizes66×80→374×266; explicit close and owner close destroy targets. | action.openPopup still rejects missing toolbar. Need real action/container/view-model ownership, anchor/focus restoration, install/update decisions, site access and side-panel host. Those latter contracts are source-mapped, not implemented. |
| Media/capture | Generated VP8 playback, muted/audible state, fake camera/mic permission and capture-stop callbacks. Screen-picker cancel. Video PiP590×332 and document PiP320×180; document PiP closes with its owner. | Persistent recording/sharing indicator and reachable stop UI are missing. Fullscreen unsupported. Output selector API disabled in this build. Real capture, media keys, output hardware and licensed playback remain unverified. |
| Downloads/files | Real input/open/save/folder sheets cancel; input/filesystem picker closes with owner. Download destination cancel emits cancelled download. Existing completion/cancel bytes retained. | Pending-download close still auto-confirms interruption: needs a real asynchronous decision. Persistent progress/retry/cancel/reveal UI, chosen-file grants/revoke, overwrite and native focus need implementation/acceptance. |

## What changed in the engine

1. **Address bubbles:** existing Chrome AutofillBubbleHandler plus a private
   Room anchor adapter; UI patch0011 resolves Room-owned windows for legacy
   callers and guards an optional Chrome-only post-save promo.
2. **Local card crash:** register that handler during Room window construction.
   Payment controllers look it up through window user data, bypassing the
   legacy getter. No additional upstream patch.
3. **Extension chooser crash:** patch0012 replaces a BrowserView dereference
   with the nullable registered toolbar provider. Ordinary Chrome's getter
   already uses that lookup; missing containers follow existing cancellation.
   There is no Room hook at the crashing extension-specific call site.

All other additions in this pass are private CLI diagnostics/fixtures and
measurements. Public ObjC headers and original patches0001–0005 are unchanged.
No shutdown scheduling/watchdog/grace experiments were resumed.

## Chapter3 should provide these shared contracts

- **Window/tab/origin ownership:** stable native parent and anchor geometry,
  focus restoration, navigation/destruction cancellation and trusted identity.
- **Decision lifecycle:** pending/accept/deny/dismiss/owner-lost outcomes,
  exactly-once completion where a decision survives, with explicit handling
  when Chrome destroys a controller rather than sending a user decision.
- **Retained Chrome content:** real extension container and DevTools content
  host; reuse Chrome popup/preview controllers with explicit sizing/lifetime.
- **Persistent activity:** observe downloads, capture, audible/muted state and
  grants; provide stop/cancel/revoke even when the originating tab is hidden.

These are implementation contracts, not newly exported API methods. Avoid
turning visibility stubs true or registering a fake global toolbar to bypass
prerequisite checks. A no-crash rejection is a boundary, not feature support.

## Verification and identities

Latest production-fix baseline: navigation12.168s;10loaded external pages
quit0.694s,25helpers/0left,0newcrashreports,exit0,load45.859. The earlier card
fix separately passed navigation17.169s/quit4.840s with26helpers/0left/0crashes.
These are serial acceptance samples, not performance rankings or a B-19 fix.

Final Chromium: cbc9414a6affa56c5ef03b46a265b4dab74ae785; apply0applied/12already.
Final guard build19s/2steps; GN checks for Room and the patched chooser target,
Swift typecheck and strict ad-hoc signature pass. Main8522d6f is reconciled;
protected direct-main source diff contains only App/RoomCore. All changes stay
within the authorized scope. Exact receipts/binary hashes are in the
`roomcore-ui-*-checkpoint.json` files, especially the final connections manifest.

The existing600-second zero-idle audit belongs to its recorded pre-UI package;
this pass changes no production network policy or automatic startup work.
No new latest-binary idle audit is claimed. B-19 concurrent teardown and the
historical Mac mini TLS attribution remain separate open items.
