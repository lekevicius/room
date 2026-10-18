# Backlog decisions — the form's record

The user answered the backlog's open questions twice: in chat on 2026-10-06 ("most defaults are fine", the Chapter 4 questions in ROADMAP Chapter 4 "Before the loop"), and through an interactive form on 2026-10-18. This page keeps the second set of answers. Each one has been applied to its row in `docs/backlog.md` and, where it changed a plan, to `PLAN.md` §4/§7, `ROADMAP.md` Chapter 5 "Decided 2026-10-18" and Chapter 6. The next set of questions gets a new form.

## 2026-10-18

**Before Chapter 5 starts**
- How Chapter 5 begins: as written. The user's daily-use notes come next, then a checklist pass on a fresh build.
- Rebase: once, the night before 5.4b.
- B-97: the drag out wins; URL drags come back through ⌥-drag or the address field (5.5).
- B-98: several incognito windows, as Chrome (5.6).
- B-62: the user does the laptop run; 5.4b attempts a fix only if it still hangs.

**Product calls**
- B-11: ⌘S stays page-first.
- B-32: remove the card's drag band entirely; the sidebar's areas are enough. In use, a double-click at the card's top (YouTube's search field) zoomed the window.
- 5.7's order: only the password bubble annoys.
- B-88: keep Chrome's All Site Data page, no line needed. Review Room's branding in Chrome's surfaces instead (new B-103).
- B-91: Save As… already shows the native dialog in use (closed).
- B-89: the overflow button becomes "…".
- B-94: hide the article's first heading when it repeats the title.
- B-49: no fullscreen banner.
- B-27: zoom per site.
- B-64: Chrome's suggestion provider as it is. Drop the website's "0 requests idle" section; the privacy posture goes in a note (`research/notes/privacy-posture.md`).
- B-65: take the best history match. The user noticed something else more: arrow keys do not put the selected suggestion's URL in the field, as Arc does (new B-102).

**Blocker, licence, going public**
- Licence: MPL-2.0.
- Repository: public with the first public beta (6.6), after a clean-up (new B-104).
- B-30's missing filter types: fold into Chapter 5 where the planner sees fit; ship as is, and add filter types only where they unlock whole classes of pages.
- Malware lists: URLhaus joins the catalogue as optional. Downloads are the user's choice; good defaults first.
- B-77: generate the export order automatically before the next official build.
- Merged branches and worktrees: deleted (local and remote, 2026-10-18).

**Machines, CI, accounts**
- B-93: drop GitHub CI for now; verify locally.
- B-48: move `build/` to the external SSD, in its own APFS sparse image beside the Chromium one.
- B-10: the SSD holds only the Chromium sparse bundle; reformat any time (the image is copied off first).
- B-46: keep Chromium's helper suffixes.
- Sparkle: the EdDSA key goes to the laptop too, read from `local.env` (`ROOM_SPARKLE_ED_KEY`, `docs/setup.md` §5).
- Updates: DMGs on GitHub Releases, the feed at `updates.room.app` (bundles from GitHub, or S3).
- Crash reports: no third-party service; find a simple self-hosted collector (new B-105).
- Passkey entitlement: the first release ships without it; requested within a month.

**Checks**
- Chapter 4 by-hand pass: ten days of daily use, but not the list. Wanted: a checklist artifact with boxes and comments, the blocker's steps included, on a fresh build.
- 120 Hz: left to 5.1b.
- B-26: Location turned on in System Settings (closed).
- B-86: not tried.
- Widevine: **fails on Netflix**, which asks to turn on protected content, already on (new B-101).
- 1Password: works signed in.

**Struck:** B-51 (picture-in-picture returns later as its own item), B-67, B-70, B-61, B-63, B-68, B-69, B-72, B-76, B-52; also B-11, B-26, B-27, B-46, B-49, B-64, B-88, B-91, B-93 as decided above.
