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

Pending. A 60-second switch-only smoke run is in progress; it cannot qualify
as the required final audit. Do not disable Widevine on-demand availability
merely to remove startup component-update traffic.

### Suppression implementation and short verification

Switches disable background networking (including Safe Browsing updates),
component extensions, sync, time queries, AIM, search preconnect, model
execution/download features, and PreemptiveSodaDownload. Chromium's developer
field-trial config enables the last feature on Mac despite its source default.
It caused SODA icnkogojpkfjeajonkmlplionaamopkf and English pack
oegebmmcimckjhkhbggblnkjloogjdfg to download through explicit on-demand calls.
Disabling it removed the last five requests from the 30-second policy smoke.
Final short smoke: 0 requests, 0 connections, 0 DNS, 14 events, 28.764 s event
span, 30 s idle, 43 s process, exit 0. The 600-second audit is still pending.

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
