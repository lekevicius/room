# Backlog

Open items that belong to no current phase, with where they are expected to
land. Phases pull from here; when an item is done or dropped, strike it and
say where (commit or progress-log date). Dogfooding friction (Phase 2.9)
is appended at the end as it happens.

Owner: **user** = needs a password, an Apple account or a decision only the
user can make; otherwise any session.

| # | Item | Source | Lands in | Owner |
|---|---|---|---|---|
| ~~B-1~~ | ~~Card mask composite cost~~ — done 2026-10-03: no extra WindowServer GPU work (2.89 vs 2.88 ms/frame, same pass count); `spike-results.md` "Card mask composite cost" | Phase 1.4, 1.6 | — | |
| B-2 | RoomCore memory summed over all processes, comparable to CEF's 670 MB baseline / +242–327 MB per hidden page | Phase 1.5 | 3.1 | |
| B-3 | ~220 `ssl_client_socket_impl.cc handshake failed … net_error -107` lines per ten-site RoomCore run without failed pages; find the hosts (net-log) | Phase 1.5 | 3.1 (with the network audit) | |
| ~~B-4~~ | ~~Notarization credential profile~~ — done 2026-10-03: profile `room` stored by the user; `notarytool history --keychain-profile room` works | Phase 1.4 | — | |
| ~~B-5~~ | ~~Team-signed keychain check on RoomCore~~ — done 2026-10-03: Developer ID signing of the component build 25.8 s, `codesign --verify` passes (Gatekeeper: Unnotarized Developer ID); first launch asked once for "Room Safe Storage", second launch no prompt and the page loaded; Quit from the Room menu exited cleanly, no crash report | Phase 1.5 | — | |
| B-6 | Passkey entitlement (`com.apple.developer.web-browser.public-key-credential`): dedicated request form linked from the entitlement's documentation page, Account Holder only. On hold: the user is still deciding the product name and bundle id, which the request names | PLAN §4, §7 | before Chapter 4 | **user** |
| ~~B-7~~ | ~~CI on GitHub~~ — done 2026-10-03: pushed; the dark-inactive snapshot check failed on the headless runner (material contrast 5 levels, backdrop-dependent) and now checks the card hairline there; run 37070516086 green | Phase 1.1 | — | |
| B-8 | `scripts/quit-timing.sh` quits through an AppleEvent, which needs Automation permission for the calling process; give it the spike's `NSApp.terminate` path as an option (Phase 1.5 used a scratch script) | Phase 1.5 | next time quit is measured | |
| B-9 | Own-window snapshots miss Chromium's GPU layer; page-in-card evidence needs an external capture (computer-use with Room granted, or Screen Recording for the shell) | Phase 1.4 | tooling, as needed | **user** grants |
| B-10 | Chromium on an APFS sparse bundle on an exFAT USB SSD on the Mac mini: the userspace exFAT driver (`UVFSService`) and the image add I/O overhead; an APFS-formatted external volume would remove it | Phase 1.5 | when the drive can be reformatted | **user** |
| B-11 | ⌘S is page-first (Phase 1.6) so web editors keep it; revisit after dogfooding if pages swallow it too often | Phase 1.6 | 2.9 review | |
| ~~B-12~~ | ~~Suggestion defaults~~ — decided 2026-10-03 by the user: search suggestions on by default (off switch in Settings), default engine Google until the first-run choice; ROADMAP 2.4 updated | Phase 1.6 | — | |
| B-13 | CEF discards lose back/forward history (no navigation-entry serialisation); RoomCore's session service fixes it | Phase 1.6 (2.3 spec) | 3.7 | |
| B-14 | RoomCore's Crashpad database is `~/Library/Application Support/Chromium/Crashpad` (seen on the signed build's `chrome_crashpad_handler` command line): brand the crash-reporter paths with the rest of the user-data layout | Phase 1.5 follow-up | 3.1 | |
| B-15 | `SidebarStore.deleteSpace` deletes the space's pinned entries and Today tabs; spec §B moves them to the Archive. When 4.1 adds the Archive, route space deletion through it (and give Delete Space an undo toast until then, 2.5) | Phase 2.1 | 4.1 (toast in 2.5) | |
