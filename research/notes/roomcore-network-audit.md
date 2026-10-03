# RoomCore background network audit — 2026-10-03

## Before

Fixed app copy from the command-hook build before network changes.
Fresh profile, about:blank, no CDP, idle-complete 600, whole process 608 s,
exit 0 without watchdog. Raw evidence netlog-idle-before (local ignored).

# RoomCore NetLog summary

Events: 86379; event span: 601.361 s.
Network request attempts: 62; unique request sources: 62; connection attempts: 86.

| Host | Attempts | Traffic annotation / component | Chromium file | Initiator |
|---|---:|---|---|---|
| accounts.google.com | 1 | gaia_auth_list_accounts | google_apis/gaia/gaia_auth_fetcher.cc | not an origin |
| android.clients.google.com | 1 | gcm_checkin | google_apis/gcm/engine/checkin_request.cc | not an origin |
| android.clients.google.com | 8 | gcm_registration | google_apis/gcm/engine/registration_request.cc | not an origin |
| clients2.google.com | 1 | network_time_component | components/network_time/network_time_tracker.cc | not an origin |
| edgedl.me.gvt1.com | 22 | update_client | components/update_client/net/network_impl.cc | not an origin |
| safebrowsing.googleapis.com | 1 | safe_browsing_v5_update | components/safe_browsing/core/browser/db/v5_update_protocol_manager.cc | not an origin |
| update.googleapis.com | 27 | update_client | components/update_client/net/network_impl.cc | not an origin |
| www.google.com | 1 | aim_eligibility_fetch | components/omnibox/browser/aim_eligibility_service.cc | not an origin |

TLS failures (SSL_CONNECT end, negative net_error):

- None.

DNS resolver requests:

- accounts.google.com: 1
- android.clients.google.com: 1
- clients2.google.com: 1
- edgedl.me.gvt1.com: 1
- safebrowsing.googleapis.com: 1
- update.googleapis.com: 1
- www.google.com: 3

Observed zero network: False. Validate duration and clean shutdown against the runner receipt; an empty or short log alone is not a pass.


## After

Completed 2026-10-03 07:28:58 EEST. Fixed-copy app with the committed network
policy, fresh profile, about:blank, no CDP. Host idle markers span 600.0275 s
and report idle-complete 600; whole process 605 s, exit 0, no watchdog.
The complete flushed NetLog contains 18 events spanning 598.411 s (event span
is not the idle timer). **0 HTTP requests, 0 connections, 0 DNS, 0 TLS errors.**
The after host/component request list is empty. Raw netlog-idle-after evidence
is retained locally; the fixed app copy predates only the Crashpad-path change
and the host feature-readiness/download checks, which do not alter this policy.

| Measurement | Before | After |
|---|---:|---:|
| Required idle seconds completed | 600 | 600 |
| Whole process seconds | 608 | 605 |
| HTTP attempts / request sources | 62 / 62 | 0 / 0 |
| Connection attempts | 86 | 0 |
| DNS requests | 9 | 0 |
| TLS errors | 0 | 0 |
| Clean exit / watchdog | 0 / absent | 0 / absent |

### Suppression implementation and short verification

Switches disable background networking (including Safe Browsing updates),
component extensions, sync, time queries, AIM, search preconnect, model
execution/download features, and PreemptiveSodaDownload. Chromium's developer
field-trial config enables the last feature on Mac despite its source default.
It caused SODA icnkogojpkfjeajonkmlplionaamopkf and English pack
oegebmmcimckjhkhbggblnkjloogjdfg to download through explicit on-demand calls.
Disabling it removed the last five requests from the 30-second policy smoke.
Final short smoke: 0 requests, 0 connections, 0 DNS, 14 events, 28.764 s event
span, 30 s idle, 43 s process, exit 0. The full audit result is above.

Gaia browser-account networking uses a Room ChromeSigninClient through the
existing per-profile factory seam. Chrome cloud-policy invalidation channels
use the existing null-provider factory seam. These are upstream APIs named
for tests, without test-only behavior; no test context or fake is linked.
Website requests, Google website sign-in and website push use separate paths.
Their complete functional acceptance is not established by idle silence.

A supported empty optimization-guide manifest override prevents the global
manifest broker's independent startup fetch. Patch 0006 adds one scheduler
factory hook: //room selects an on-demand-only scheduler. There is no existing
pref/switch/factory for disabling automatic checks while retaining component
registration; --disable-component-update removes Widevine registration too.
The original five patch files are unchanged. Explicit component updates stay
available; Widevine first-use download still needs runtime verification.

Network-policy build 16 s (2 steps), ad-hoc package passed. Post-change nav
23.598 s; ten loaded pages, quit 4.240 s at load1 38.39, 26 helpers observed,
0 left after unchanged 5 s grace, 0 new crash reports, exit 0.

### Initial Widevine first-use probe — gap reproduced

Auxiliary -RoomSpike widevine requests com.widevine.alpha with cenc and H.264
video capability on a trusted loopback page, fresh profile. It returns
NotSupportedError (supported=false); 37 s process, exit 0. NetLog has only the
2 loopback page/favicon requests, 4 connections, no external request or CDM
fetch. Before-policy profile contains WidevineCdm/4.10.3112.0, so the original
automatic updater did provision it. Registration is preserved but is not a
first-use trigger. **This initial run demonstrated missing demand provisioning.**
The follow-up below adds a request-driven CDM hook and verifies the result.

### Demand-only Widevine provisioning — verified 2026-10-03

Patch 0007 adds three tiny hooks: Content's EME client factory, Chrome's frame
interface binder, and CDM registration notification with public CdmInfo.
Existing capability observers do not report the requested key-system name;
using them as the demand signal would fetch Widevine for unrelated keys.
Content directly constructs the EME client and keeps CdmRegistryImpl private.
The notification hook avoids importing that private header or weakening GN
visibility. All policy, request coalescing, timeout and implementation live in
//room. Original patches 0001–0006 and public ObjC headers are unchanged.

The document-scoped service accepts no URL/component ID, checks active frame,
trustworthy origin and encrypted-media permission policy, and only provisions
Widevine. It waits for normal registration, uses public MaybeThrottle with
Chromium cooldown, and observes actual CDM registration before allowing Blink
to retry its ordinary capability checks. Failed provisioning is bounded to
60 s with a 1-minute retry cooldown. No startup task is scheduled.

| Final build probe | Evidence |
|---|---|
| Fresh Widevine request | EME access and MediaKeys creation true in 6.812202 s; Widevine 4.10.3050.0; process 44 s, exit 0 |
| Request-triggered traffic | update.googleapis.com 2, edgedl.me.gvt1.com 1; all update_client; first external request 0.001 s after EME request, download +0.197 s, completion ping +4.093 s; 2 loopback requests; 0 TLS errors |
| Already installed, next launch | MediaKeys created in 2.098724 s; process 31.122 s, exit 0; 4 loopback requests (including restored prior fixture URL), **0 external requests** |
| Unrelated key com.room.unsupported | NotSupportedError in 0.002342 s; process 30 s, exit 0; 2 loopback requests, **0 external requests**, no CDM installation |
| Forced updater DNS failure, fresh profile | NotSupportedError after 60.162963 s, process 65.524 s, exit 0; positive-CDM assertion deliberately fails; bounded failure, not a playback success |

Evidence directories: feature-widevine-final, feature-cdm-installed-final,
feature-cdm-negative-final, feature-cdm-offline-final. NetLogs retained locally.
Receipts identify parent 2ea76e8; these tests exercise the pending 0007/room_cdm
working-tree change. Provisioning and CDM instantiation are verified; a licensed
stream and user-facing DRM error/permission UI remain Chapter 3 acceptance.

Final callback-refined build idle audit: netlog-idle-cdm-final, fresh profile,
about:blank, requested and completed 600 s idle, exit 0, no watchdog. The
flushed log has **0 HTTP requests, 0 connections, 0 DNS, 0 TLS errors**.
The after host/component request list remains empty with demand-CDM enabled.

Post-FedCM complete audit (fixed app code 2a04498, netlog-idle-fedcm): requested
and completed 600 s idle, 610 s whole process, exit 0, no watchdog. Complete
NetLog 18 events / 603.051 s event span; **0 HTTP, 0 connections, 0 DNS, 0 TLS**.
The after host/component list is still empty. This binary predates only the
subsequent tab-editability/extension probe change, not any network policy.
