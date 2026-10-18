# Room's privacy posture

What Room sends over the network, and what it does not. Written 2026-10-18,
when the website's "0 requests when idle" section came off the page at the
user's request: the measurement holds, but it was too much of the pitch.
The practical promise is simpler: Room asks the network for nothing you did
not cause. Each claim below names its evidence; update it when the evidence
changes.

## What Room does not do

- **No analytics or telemetry.** The app has no analytics SDK (CLAUDE.md "No
  analytics, no network calls the user did not ask for"), and the idle audit
  below shows the engine reporting nothing either.
- **No Google account or Sync.** There is no sign-in, so no password Sync and
  no password generation (B-72), and no translation, which would need a Google
  API key (B-63).
- **No background calls from the engine.** Stock Chromium, left idle on a blank
  page for 600 s, made 62 requests: component updates 49, account and device
  check-ins 10, network time, Safe Browsing and search 3. Room made 0 HTTP
  requests, 0 connections and 0 DNS lookups in the same run
  (`roomcore-network-audit.md`, 2026-10-03). Every engine step since then has
  re-run a net-log, and every one shows 0 engine requests (PLAN §7 #8).
- **No third-party crash service.** Crash reports go to a self-hosted collector
  once 6.3 exists (B-105), and only when the user turns them on.

## What Room sends when you ask

- **Pages you open**, and whatever those pages load. With the built-in blocker
  on (the default), ads and trackers on EasyList and EasyPrivacy are not loaded
  (B-30).
- **Search suggestions**, when the switch is on (off sends nothing). Chrome's
  suggestion provider asks the search engine about every 100 ms while you type:
  34 requests for three typed queries, against 3 for Room's earlier client,
  which asked once per pause (B-64). The user chose to keep Chrome's provider
  (2026-10-18); the switch is the control.
- **Widevine's CDM**, fetched from Google's component updater on the first
  encrypted-media request only, never at launch (patch 0007's demand hook,
  verified 2026-10-03: 3 requests at first use, 0 afterwards).
- **Blocker lists.** The bundled lists ship with the app. "Update lists
  automatically" is off by default; Update Now, or turning that switch on,
  fetches each list from its publisher. Optional lists (uBlock's, URLhaus,
  lists by URL) and uBlock's scriptlets are downloaded when you add them.
- **Updates.** Sparkle checks the feed (`updates.room.app`, 6.2) as the update
  settings say.

## What others send through Room

- **Extensions** make their own requests on their own schedule: Dark Reader
  fetches its blog feed, 1Password talks to its servers. These carry the
  extension's origin, are not Room's or the engine's, and Settings ▸ Extensions
  says so (B-68). The tour counts them apart from the engine's.
- **Pages' own scripts** can do what the web allows; the blocker and the site
  panel's permissions are the controls.

## How it is checked

`scripts/roomcore-netlog.sh` records launch, 600 s idle and quit, and
`scripts/roomcore-netlog-summary.py` lists the requests by host and traffic
annotation. `scripts/netlog-check.sh` ran with the blocker on: 0 engine hosts
beyond the test pages and 0 bytes from Room's own process (2026-10-18). An engine
step that adds a request either has a user action behind it or is a bug.
