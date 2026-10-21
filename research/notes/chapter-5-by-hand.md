# Chapter 5 — by hand

Since 2026-10-21 sessions verify their own work (AGENTS.md "Testing"). This file has two parts: what the sessions ran themselves, one result line per check, and the short list of steps that need the user (accounts, the real state and other browsers, hardware this Mac lacks, macOS prompts, the 120 Hz runs, taste). The current DMG goes at the top.

## The current DMG

- Build 14: `build/sparkle-14/Room-0.1.0-14.dmg` (2026-10-19).

## For the user

(At most ten steps per phase; the 120 Hz runs, B-16, B-20 and B-21, need the built-in panel as the main display.)

Phase 5.0:
1. **Computer use for the dev id** (5.0a): approve `app.room.desktop.dev` when the planner asks (`request_access`); every Debug build is that id since 5.0a and the session grants held only `app.room.desktop`. Until then the click checks below wait. **Requested by the planner 2026-10-21 after 5.0a: declined**; no further request tonight; the loop's click checks run by spike hooks where they can and otherwise wait here.
3. **5.0a's five click checks** (until the dev id is granted; the app is `build/roomcore-release/DerivedData/Build/Products/Debug/Room.app`, test servers up, each on its own `-RoomStateDirectory /tmp/room-5/<name>`): (a) Restore Sidebar…: launch with `-RoomSidebarFixture spaces`, ⌘Q, relaunch, Delete Space… on the second space, let the toast expire, Help ▸ Restore Sidebar… ▸ the newest backup ▸ Restore: the space is back and a "before restore" backup exists; (b) B-106: Settings ▸ Downloads ▸ "Ask where to save each download" on, then ⌘T `127.0.0.1:8766/download?name=asked.bin&size=200000`: a save panel; (c) B-107 video: `http://127.0.0.1:8776/phase-3.7/pip.html` ▸ Video PiP, open a second tab, the overlay's back-to-tab button: the pip tab is selected and shown; (d) B-108: drag the sidebar's edge 100 pt wider: the selected pill follows; (e) B-109: click a Today row's × without moving the pointer: the next row shows its ×. A grant for `app.room.desktop.dev` lets a session run all five instead.
2. **macOS's questions for the new id** (5.0a): the Debug apps are a new app to TCC, so the first camera, microphone, location and Bluetooth use asks again ("Room" from `build/roomcore*/…/Debug/Room.app`); answer them once when they appear (the B-62 and B-26 runs need Bluetooth and Location answered).

## Run by the sessions

(One line per check: the step, how it was run, the result or the backlog row.)

- **Loop step 0, permissions (2026-10-21, laptop, the user present):** Debug app over the release engine (build/roomcore-release, built 2026-10-19), throwaway state /tmp/room-step0, `chromesurfaces2 -RoomSpikeOnly permissions`: notifications popover answered (denied, remembered after reload); camera+microphone popover answered, macOS's question answered by the user, page result `camera: granted`; geolocation `popover=false`, state stays `prompt` (macOS Location Services for this build not granted; B-26's location stays a user step).
- **Loop step 0, B-62 (same app and night):** `pageservices -RoomSpikeOnly bluetooth`: chooser opened (448×444 over Room), cancel gives `NotFoundError`, quit clean, **no main-thread hang**; `pageservices -RoomSpikeOnly serial`: chooser opened (448×468), cancel `NotFoundError`, clean. The hang of 2026-10-06 does not reproduce with the machine's Bluetooth authorization answered: 5.4b needs no B-62 engine attempt; a real Bluetooth/serial device stays the user's hardware step.
- **5.0a, the dev bundle id (2026-10-21, laptop):** `PlistBuddy` on all five products: the Debug apps over both engines and the Debug host `app.room.desktop.dev`, the Release app and host `app.room.desktop`; a Debug launch with no flags ran as `app.room.desktop.dev` on `~/Library/Application Support/Room Dev` (its `SingletonLock` there, socket under `$TMPDIR/app.room.desktop.dev.*`, none in the real root) and quit by pid. Beside a Release Room: not possible tonight (the user's Room not running; a Release app on a throwaway state would open the real engine root); the handoff is Chromium's singleton on the engine root, which the two never share.
- **5.0a, live sites (`scripts/live-check.sh`):** delfi.lt, 15min.lt, dailymail.com, a YouTube watch page, blocker off then on per site: 0 failures on the dev build and on the release framework (`spike-results.md` "Phase 5.0a": e.g. 15min 47/44 requests blocked and 116 of 116 list-matched elements hidden, the Cookiebot banners on delfi and 15min gone through the Cookie List, YouTube's consent answered by autoconsent and `#movie_player` present).
- **5.0a, B-106 (step 34):** `-RoomSpike downloadprompt` on both builds: a save panel as a sheet for the step's typed URL and for a link; not reproduced. The pass's own state saved `askWhereToSave: false` with one download that asked the host: the setting was off at the time (likely set in the other Room, both `app.room.desktop` then). The Settings click path stays a click check (below).
- **5.0a, B-107 (steps 51–53):** `media -RoomSpikeOnly backtotab`: video PiP's back to tab (the overlay's own path) selects and shows the opener on dev; the document panel's Back to Tab button on dev and release; step 53's link loads now that `test-servers.sh` serves :8776. Real sites (Spotify's miniplayer, YouTube's button) stay the user's daily use.
- **5.0a, B-108 and B-109:** `-RoomSpike sidebarfixes` on both builds: the pill follows a resize (284 → 404 pt with the rows); after a close the row that slid under a still pointer is hovered with its ×.
- **5.0a, B-100:** `grand-tour.sh --only palettemeasure,import`: 65/65 on dev and on the release framework.
- **5.0a, pending computer use (planner, once `app.room.desktop.dev` is granted):** Restore Sidebar… (step 8, the setup note's pattern); the Settings ▸ Downloads switch then a typed download (B-106); the video overlay's back-to-tab button on the release framework (B-107); a real edge drag (B-108) and a close with the pointer resting (B-109). Not run in 5.0a: the grant held only `app.room.desktop`, and the session's attempt to give a copy of the Debug app that id (re-signed) was refused by the permission system.

