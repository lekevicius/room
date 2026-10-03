# RoomCore feature-drive plan — 2026-10-03

Run each feature in a fresh host process so the stub logger's first-hit
suppression does not conceal a feature's dependencies. Keep stub logging
on. Start with `scripts/roomcore-package.sh` (ad hoc, mock keychain), then
`-RoomSpike nav`, `open10`, and three ten-page quit measurements. Re-run that
baseline after each engine fix. No feature is green merely because its page
loaded or its request was suppressed.

`scripts/roomcore-features.sh <name>` starts loopback HTTP/HTTPS fixtures and
launches **RoomCoreHost**, product `Room.app`, with `-RoomSpike <name>`.
It supplies `-RoomSpikeBaseURL`, `-RoomSpikeSecureURL`, `-RoomSpikeCDPPort`,
`-RoomSpikeOutput`, a fresh `-RoomUserDataDir`, and `--use-mock-keychain`.
The HTTP fixture serves the original `research/spikes/phase-1.4/` pages.
CDP is a host-spike control channel only; it adds nothing to the public ObjC
API. Missing private command hooks are explicit failures. Net-log idle runs
have no CDP port, HTTP fixture, extension, or externally loaded start page.

## Drives and acceptance

| Feature / host argument | Trigger | Evidence required beyond survival | Current preparation |
|---|---|---|---|
| `popups` | HTTP `popups.html`; user-gesture CDP clicks on target=_blank and window.open; date showPicker | new contents/window ownership, select/date/color popup anchoring before/after moving host; clean close | clicks + date driver; native select/color and ownership review pending |
| `dialogs` | same page; alert, confirm, prompt; CDP dismisses through Page.handleJavaScriptDialog | one callback each, correct cancelled values, no stranded modal; beforeunload separately | three dialog calls prepared |
| `keys` | HTTP `keys.html`; focus textarea, Input.dispatchKeyEvent | page log plus real AppKit Cmd+A/C/V/Z and reserved Cmd+T/L/W, Colemak layout; no duplicate dispatch | page-event driver prepared; native routing pending |
| `audio` | HTTP `audio.html`; play generated WAV 2 s, pause | currentTime advances; audio process survives; audible state/stub hits; repeat with Web Audio | media-element driver prepared; oscillator pending |
| `scroll` | HTTP `scroll.html`; rAF scroll 3 s | frames/time/scrollY plus real wheel event and card clipping | rAF driver prepared |
| `transparent` | HTTP `transparent.html`; CDP transparent default background | external composite capture shows material, no blank/torn native surface | override + CSS observation prepared |
| `corners` | HTTP `corners.html` | native capture at all card corners/hairline and resize | page ready; external capture required |
| `band` | HTTP `band.html`; page clicks at y=8 and 34 | native pointer test in 52 pt toolbar band; recorded page coordinates | CDP page coordinates only; native hit testing pending |
| `form` | HTTP `form.html`; fill name/email/street/test credentials and submit | save prompt path, completion/cancel; revisit form, type R, inspect autocomplete anchoring | submit prepared; bubbles/dropdown pending |
| `extension` | --load-extension original MV3 fixture; load HTTP form | content marker, service worker, chrome.tabs/windows, action popup, chrome://extensions; any unsupported surface named | content-marker prepared; browser surfaces pending |
| `downloads` | local attachment with Content-Disposition | actual file byte count (26 bytes), completion/cancel, download surface stub hits | attachment click prepared |
| `permissions` | Notification.requestPermission and geolocation on trusted loopback | prompt shown, denial/dismissal completes request; camera/mic policy separately without granting capture | request trigger prepared; native cancellation pending |
| `auth` | /auth sends HTTP 401 Basic challenge; fixture credentials room/spike | native auth UI and cancel path; supplied fixture credentials load page | navigation/prompt observation prepared |
| `certificate` | HTTPS fixture with untrusted self-signed local cert (no ignore-certificate-errors) | security interstitial rendered; leave/back works; error attributed to fixture | navigation/interstitial observation prepared |
| `find` | private spike selector dispatches IDC_FIND, IDC_FIND_NEXT to owned BrowserWindowInterface | real Chrome find path, nonnull find UI/helper, matches and close | private hook and FindBarOwner implemented; drive survives |
| `zoom` | private selector IDC_ZOOM_PLUS/MINUS/NORMAL | page scale changes then resets; no crash in location/zoom bubble | private command hook implemented |
| `print` | private selector IDC_PRINT (not Page.printToPDF) | Chrome print/preview/native dialog and cancel completes | private command hook implemented |
| `fullscreen` | requestFullscreen with user gesture, then exitFullscreen | fullscreen element + real native window transition, toolbar restored, exit callback | page driver prepared; current context may reject |

`review-required` and `prompt-observation` are deliberately unresolved
results, not functional passes. CDP dialog cancellation also does not prove
native dialog UI. The component build has `is_debug=false`, but DCHECKs are active in this
non-official build: the modal-host drive hit a fatal NativeWidgetMac DCHECK.
Preserve checks; do not disable them to make a feature pass.

## Surface result format

For each run retain host.log, spike.txt, receipt.txt, server.log, build SHA,
exit status, duration, and crash report delta. Copy the curated findings into
`spike-results.md`:

| Feature | Chrome call site/path | Window members needed | Fix / fallback | Runtime result |
|---|---|---|---|---|
| all 18 | measured matrix in spike-results.md | per-feature first-hit logs retained | three crash fixes committed | 17 drives completed; fullscreen rejected; UI acceptance gaps remain |

On CHECK/crash: capture the first failing Chrome call site and full stack,
inspect the requested window member, fix the narrowest //room hook, rebuild,
rerun that feature and nav/open10/quit. A raw patch is a last resort; record
why neither pref/switch nor //room hook suffices. One commit per fix, push at
least every three fixes. Never edit //room while a compiler is using it.

## Network audit

`scripts/roomcore-netlog.sh <new-directory>`: fresh profile, `about:blank`,
600 seconds idle after host launch, NSApp.terminate, wait for exit, parse a
complete JSON NetLog. No network-suppression switches in the runner. Compare
identical before/after runs. Also capture open10 with --log-net-log to explain
B-3; ten-site page traffic is intentional and must not be mixed with idle.

The summary joins URL_REQUEST_START_JOB hosts to Chromium traffic annotation
hashes (`tools/traffic_annotation/summary/annotations.xml`). It reports
request attempts (redirects count separately), unique request sources, DNS
requests, connection attempts/preconnects, and SSL_CONNECT failures joined
through NetLog source dependencies. Unknown/ambiguous hosts and annotation
IDs stay explicit. An empty/short/invalid log or an early process exit is
never a ten-minute pass. Pref/switch first, //room hook second; preserve an
on-demand-only Widevine CDM path.

## Exit gates

1. Baseline nav + ten loaded pages + clean quit still passes after fixes.
2. All 18 drives completed, real UI gaps/fallbacks named; per-feature stub table.
3. Clean launch + >=600 idle seconds + clean exit; zero URL requests, DNS and
   connection attempts in final summary. Before/after lists versioned.
4. B-3 TLS failures counted by host/component/error; no candidate guesses.
5. Handler command line proves branded Crashpad database.
6. Five patch hashes match baseline or each change is justified.
7. `git diff main -- Packages App ROADMAP.md` contains App/RoomCore only;
   no merge/main push. Finish with a PR and an honest gate-by-gate report.
