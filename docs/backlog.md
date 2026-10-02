# Backlog

Open items that belong to no current phase, with where they are expected to
land. Phases pull from here; when an item is done or dropped, strike it and
say where (commit or progress-log date). Dogfooding friction (Phase 2.9)
is appended at the end as it happens.

Owner: **user** = needs a password, an Apple account or a decision only the
user can make; otherwise any session.

| # | Item | Source | Lands in | Owner |
|---|---|---|---|---|
| B-1 | Measure whether the card mask costs an extra WindowServer composite of Chromium's IOSurface (Instruments Metal System Trace / Animation Hitches, mask on vs. off, `research/spikes/phase-1.4/scroll.html`). Frames are fine (120 fps); this is power. Fallback: `RoundedCornersF` on the web contents layer in RoomCore | Phase 1.4, 1.6 | Chapter 5 | user enables Developer mode (`sudo DevToolsSecurity -enable`), then any session |
| B-2 | RoomCore memory summed over all processes, comparable to CEF's 670 MB baseline / +242–327 MB per hidden page | Phase 1.5 | 3.1 | |
| B-3 | ~220 `ssl_client_socket_impl.cc handshake failed … net_error -107` lines per ten-site RoomCore run without failed pages; find the hosts (net-log) | Phase 1.5 | 3.1 (with the network audit) | |
| B-4 | Notarization credential profile: `xcrun notarytool store-credentials room --apple-id <id> --team-id N56PMJ99UT` | Phase 1.4 | before the first notarized build | **user** |
| B-5 | Team-signed keychain check on RoomCore: `scripts/sign-and-notarize.sh <app> --no-notarize`, launch twice, no prompt on the second launch; first launch over the ad-hoc "Room Safe Storage" item asks once | Phase 1.5 | 3.1 | **user** at the prompt |
| B-6 | Passkey entitlement (`com.apple.developer.web-browser.public-key-credential`) request to Apple | PLAN §4, §7 | before Chapter 4 | **user** |
| ~~B-7~~ | ~~CI on GitHub~~ — done 2026-10-03: pushed; the dark-inactive snapshot check failed on the headless runner (material contrast 5 levels, backdrop-dependent) and now checks the card hairline there; run 37070516086 green | Phase 1.1 | — | |
| B-8 | `scripts/quit-timing.sh` quits through an AppleEvent, which needs Automation permission for the calling process; give it the spike's `NSApp.terminate` path as an option (Phase 1.5 used a scratch script) | Phase 1.5 | next time quit is measured | |
| B-9 | Own-window snapshots miss Chromium's GPU layer; page-in-card evidence needs an external capture (computer-use with Room granted, or Screen Recording for the shell) | Phase 1.4 | tooling, as needed | **user** grants |
| B-10 | Chromium on an APFS sparse bundle on an exFAT USB SSD on the Mac mini: the userspace exFAT driver (`UVFSService`) and the image add I/O overhead; an APFS-formatted external volume would remove it | Phase 1.5 | when the drive can be reformatted | **user** |
| B-11 | ⌘S is page-first (Phase 1.6) so web editors keep it; revisit after dogfooding if pages swallow it too often | Phase 1.6 | 2.9 review | |
| B-12 | Search suggestions default (on, with the off switch) and the default engine before the first-run choice (DuckDuckGo): confirm with the user | Phase 1.6 | 2.4 / 2.8 | **user** decision |
| B-13 | CEF discards lose back/forward history (no navigation-entry serialisation); RoomCore's session service fixes it | Phase 1.6 (2.3 spec) | 3.7 | |
