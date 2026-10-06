# Backlog decisions — a form

The questions the backlog leaves to you, one per row, with the planner's provisional choice marked `(P)`. Tick a box or write in the blank; `docs/backlog.md` has the full context for each id. When you are done, a session reads this file and applies the answers (the row is updated, the provisional choice confirmed or replaced, the code or doc changed where the answer needs it).

## Decisions the chapter already runs on provisionally

**B-46 — RoomCore helper bundle ids.** Chromium's suffixes under `app.room.desktop` (`.helper`, `.helper.renderer`, `.framework.AlertNotificationService`) instead of PLAN's `.helper.gpu`/`.plugin`/`.alerts`.
- [ ] Keep Chromium's suffixes; PLAN stays amended `(P)`
- [ ] Patch `chrome/BUILD.gn`'s helper templates to PLAN's names (one more patch to carry)
- Notes: ________________________________________________

**B-48 — disk layout on the Mac mini.** `build/` holds 30–45 GB (staging, DerivedData, evidence, tour runs); the internal disk had 13–90 GB free during the chapter.
- [ ] Leave it; sessions keep 10 GB free by deleting regenerable output `(P)`
- [ ] Move `build/` to the external SSD (`/Volumes/JL4` or the Chromium volume) with a symlink; say which: ________
- [ ] Move only DerivedData and the staged frameworks; keep evidence and tour runs internal
- Notes: ________________________________________________

**B-63 — translation.** Chrome offers to translate only with a Google API key configured; the element script itself is Google's.
- [ ] No key, no offer; a Chapter 4 Settings item states it `(P)`
- [ ] Use a Google API key (yours; it also enables other Google services unless each is turned off: list them before enabling): ________
- [ ] A `//room` override that loads the translate element without a key (outside the patch policy; needs the user's say-so)
- Notes: ________________________________________________

**B-66 — history older than 90 days.** Chromium keeps 90 days; the 3.5 import left older Chapter 2 visits out and 3.9 wrote them to `history-archive.json` beside `Room.sqlite` before dropping the tables.
- [ ] Keep the JSON as an archive nobody reads yet; 4.1's Library may read it `(P)`
- [ ] Delete the archive; 90 days is enough
- [ ] Patch Chromium's retention (a `//components/history` behaviour change: against the patch policy)
- Notes: ________________________________________________

**B-68 — extensions' own network requests.** An installed extension talks to its own servers (Dark Reader's blog feed, uBO's lists) on its own schedule.
- [ ] Theirs; Settings ▸ Extensions says so in one line `(P)`
- [ ] Block extension-originated requests while the switch "extensions may use the network" is off (a Chapter 4 feature)
- Notes: ________________________________________________

**B-69 — native messaging hosts.** 1Password's extension looks for its desktop app through native messaging host manifests under Chrome's and Chromium's directories; Room registers none, so 1Password shows no popup without an account.
- [ ] None registered in Chapter 3; decide in Chapter 4.5 with the extensions UX `(P)`
- [ ] Read Chrome's directory (`~/Library/Application Support/Google/Chrome/NativeMessagingHosts`) so hosts installed for Chrome work in Room
- [ ] Read Chromium's directory only
- Notes: ________________________________________________

**B-72 — password generation.** M154 offers generated passwords only while password Sync is active; Room has no Sync.
- [ ] No generation in Chapter 3; revisit with Chapter 4's passwords work `(P)`
- [ ] A `//room` behaviour hook that enables generation without Sync (one patch in `//components/password_manager`, against the patch policy; your call)
- Notes: ________________________________________________

**B-74 — "Use Enhanced Spell Check".** Chrome's context menu offers Google's spelling service (the text goes to Google).
- [ ] Hide the item `(P)`
- [ ] Keep it (it only acts when chosen)
- Notes: ________________________________________________

## Measurements and checks only you can do

**B-16, B-18, B-20, B-21 — the 120 Hz numbers on the laptop.** The sidebar scroll, the tab switch, the palette and the space switch were all measured at 60 Hz on the Mac mini.
- [ ] I will run them (the laptop session prompt in `docs/laptop-session-prompt.md` does it)
- [ ] Skip until Chapter 5.4
- Notes: ________________________________________________

**B-26 — location.** Allow Room in System Settings ▸ Privacy & Security ▸ Location Services, then `permissions.html` should read "granted" after Allow.
- [ ] Done; it reads: ________
- [ ] Not now
- Notes: ________________________________________________

**B-32 — the drag band at the card's top with the sidebar hidden.** A press in the top 5 % of the card drags the window after 3 pt; a text selection started there moves the window instead.
- [ ] Fine as it is
- [ ] Skip selectable text (the band only where the page has no selection under the pointer)
- [ ] Shrink the band to ______ pt
- Notes: ________________________________________________

**B-10 — the external drive.** The Chromium checkout lives in an APFS sparse bundle on an exFAT SSD; reformatting the SSD to APFS removes the image and the userspace exFAT driver's overhead.
- [ ] Reformat when convenient (I will say when)
- [ ] Leave it
- Notes: ________________________________________________

## Product questions a later chapter cannot cheaply revisit

**B-27 — zoom per host or per tab.** Chrome's default (and RoomCore's today): zooming one page zooms every open page of that host at once.
- [ ] Per host, as Chrome `(P)`
- [ ] Per tab, with a per-host default (Chapter 4.4 Settings)
- Notes: ________________________________________________

**B-64 — search suggestions' request cadence.** With suggestions on, Chrome's `SearchProvider` sends a request about every 100 ms while typing (34 for a 120-keystroke run); Room's own client sent one per pause (3).
- [ ] Chrome's provider as it is; the switch is the privacy control `(P)`
- [ ] Throttle to one request per pause in `//room` (a `SearchProvider` delay setting; check it is a pref, not a patch)
- [ ] Keep Room's own suggest client instead of Chrome's provider
- Notes: ________________________________________________

**B-49 — the fullscreen exit hint.** Chrome's "Press Esc to exit" bubble is Views anchored on a `BrowserView`; Room shows nothing on tab fullscreen, pointer lock or keyboard lock.
- [ ] A small host banner in Chapter 4 `(P)`
- [ ] Nothing (Esc works)
- Notes: ________________________________________________

**B-45 / clone cleanup, B-58 toasts, B-60 client certificates, B-71 extension device chooser.** Chrome surfaces Room turns off or keeps as Chrome's: no question unless you want one of them native sooner than Chapter 4/5.
- Notes: ________________________________________________

## Accounts, keys and services (Chapter 2's open items)

**The passkey entitlement** (`com.apple.developer.web-browser.public-key-credential`, Account Holder).
- [ ] Filed on: ________
- [ ] Not yet

**The Sentry project and DSN** (`ROOM_SENTRY_DSN` in `xcodegen/base.yml`).
- [ ] DSN: ________
- [ ] No Sentry for now

**The update feed URL** (`ROOM_UPDATE_FEED_URL`) and where the appcast will be hosted.
- [ ] URL: ________
- [ ] Not yet

**The Sparkle EdDSA key** (in the Mac mini's login keychain, account `ed25519`): `scripts/sparkle-package.sh` needs your "Always Allow" once; the release machine needs the key exported and imported.
- [ ] Done on the Mac mini
- [ ] Exported to the laptop (`generate_keys -x`, then `-f` there)
- [ ] Not yet

**Widevine on a real service** (Netflix or Spotify Web with an account, the signed 155 build).
- [ ] Plays: ________ (service, result)
- [ ] Not tried

**1Password with an account** (3.6b: the popup needs an account or the desktop app).
- [ ] Works / does not: ________
- [ ] Not tried
