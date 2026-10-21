# Mac mini session prompt — the move back, the disk, and the Chapter 5 loop

Written 2026-10-21 after Room's first public release (build 20, from the laptop). Paste the block below into a fresh Claude Code session on the **Mac mini** (`eve@eve.local`, repository `/Users/eve/Code/room`), in the desktop app, auto permission mode, Opus. Part A runs with the user at the Mac (about 20 minutes); after it the session runs unattended.

```
You are continuing Room's development on the Mac mini (user `eve`, 24 GB,
repository /Users/eve/Code/room) after a stretch on the M1 Max laptop. You
do three things, in order: (A) with the user present, everything that would
otherwise stop an unattended run for a permission; (B) the disk work the
backlog has waited on (B-10, B-48); (C) the Chapter 5 loop from where the
laptop paused, per docs/chapter-loop-prompt.md adapted to this machine.

Rules that hold throughout: AGENTS.md (commits small, prefixed, never an
attribution trailer; push at the end of a phase or session). Never raise a
permission dialog after Part A: no sudo, no shell screen capture, no
System Settings changes, no request_access, no AskUserQuestion. Anything
that would need one goes on the user's list in
research/notes/chapter-5-by-hand.md. This machine may have a printer: never
press Return or Print in a print preview unless NSPrinter.printerNames is
empty or Save as PDF is selected first.

== Read first ==
AGENTS.md; docs/setup.md (§4 Chromium, §5 signing, §5a computer use);
docs/backlog.md rows B-10, B-48, B-93; research/notes/chapter-5-loop.md (its
last section, "Paused 2026-10-21", says where the loop stopped and what 5.4b
must name); docs/chapter-loop-prompt.md (the loop: written for the laptop;
you adapt its machine section here); docs/chapter-5-session-rules.md (the
shared part the laptop appended to every implementer prompt: copy it to
build/chapter-5-prompts/common.md and adapt its machine section).

== Part A: with the user at the Mac (do this first, quickly) ==
1. `git pull --ff-only`. Record what this machine has: `diskutil list` and
   `df -h` (the internal drive's free space, the external SSD's format and
   volumes), `~/chromium` (where it points: the APFS sparse bundle on the
   exFAT SSD per B-10), `cat ~/chromium/src/chrome/VERSION`, the room
   branch's patch count, whether out/dev and out/release exist and their
   age, and `du -sh build` in the repository.
2. Keep the Mac awake: mcp__ccd_host__request_keep_awake (session_idle) and
   `caffeinate -dimsu` in the background for the session's lifetime. Ask the
   user to leave the Mac unlocked overnight.
3. Computer use: request access once for `app.room.desktop.dev` (launch a
   Debug Room on a throwaway state first so the app is found:
   `open -n <Debug Room.app> --args -RoomStateDirectory /tmp/room-mini/grant
   -RoomEngineDirectory /tmp/room-mini/grant/engine`), Finder, clipboard
   read and write. Never `app.room.desktop` (the user's Room).
4. Check Screen Recording and Accessibility for the Claude app
   (`swift -e 'import CoreGraphics; print(CGPreflightScreenCaptureAccess())'`
   and AXIsProcessTrusted); if either is off, open the pane
   (`open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"`
   or `…?Privacy_Accessibility`) and ask the user to switch Claude on.
5. Signing without prompts: run `security find-identity -v -p codesigning`
   and a test `codesign` of a scratch binary with the Developer ID identity;
   if macOS asks for keychain access, the user answers "Always Allow". Check
   `xcrun notarytool history --keychain-profile room` answers. Check that
   local.env has ROOM_SPARKLE_ED_KEY (the user copies it from the laptop's
   local.env or the mini's keychain item "ed25519"; scripts/sparkle-package.sh
   otherwise reads the keychain, which prompts). Check `wrangler whoami`
   (the user logs in if needed; wrangler's "personal" profile, account
   "Lekevicius" fd39de57de7236def4aed06df4ef7bac, holds the room-updates
   bucket: run wrangler from the repository directory or export
   CLOUDFLARE_ACCOUNT_ID).
6. macOS's questions for the Debug apps: run the permissions spike once on
   the Debug app over the release framework (scripts/run-spike.sh
   chromesurfaces2 -RoomSpikeOnly permissions, throwaway state) and the B-62
   choosers (pageservices -RoomSpikeOnly bluetooth / serial) so the user
   answers camera, microphone, location, Bluetooth for app.room.desktop.dev.
   Ad-hoc Debug builds can lose these after a rebuild; if one re-asks later,
   it is a user-list item, never something to wait on (a stable Apple
   Development signature for Debug builds would keep them: propose it as a
   backlog row, do not do it in Part A).
7. Command allow-list: run the `fewer-permission-prompts` skill over this
   project's transcripts if any exist here, and add to the project's
   .claude/settings.local.json (gitignored, the user approves the edit)
   allow rules for what the loop runs all night: Bash for scripts/*,
   xcodegen, xcodebuild, swift, git (not push --force), autoninja/ninja,
   gclient, python3, sqlite3, codesign, xcrun notarytool, hdiutil,
   wrangler r2 object put on the room-updates bucket, lsof, pgrep, kill of
   the session's own pids, du/df/diskutil list/info (not erase), rsync,
   caffeinate. Show the user the list before writing it.
8. The disk decision (Part B), asked now in one question: may the external
   SSD be erased and reformatted APFS? (B-10 says yes since 2026-10-18 and it
   holds only the Chromium sparse bundle; confirm what `diskutil list` shows
   and whether the bundle should be copied off first or the checkout
   fetched again.) Do not erase anything without this answer.
9. Tell the user in five lines what is granted, what is not, and what runs
   overnight. Then continue without waiting.

== Part B: the disk (B-10, B-48) ==
- If the user said yes: get the Chromium checkout onto the APFS volume
  natively (copy the sparse bundle's contents to the new volume if there is
  room to stage them, else a fresh `fetch chromium` at the tag in local.env
  and `scripts/roomcore-apply.sh`; record which and how long). Then move the
  repository's build/ there (its own directory on the SSD, a symlink from
  the repository: `build -> /Volumes/<ssd>/room-build`), and point
  CHROMIUM_ROOT in local.env at the new checkout. Verify: `ls -la
  ~/chromium`, `df -h`, a //room-only incremental of out/dev (or the first
  build if out/dev is gone), then scripts/roomcore-package.sh and the
  baseline. Record timings in research/notes/build-log.md and close B-10 and
  B-48 in docs/backlog.md with the numbers.
- If the user said no or did not answer: leave the disk alone, record the
  free space, follow B-48's rule (keep 10 GB free by deleting regenerable
  build/ output only), continue.
- Never delete evidence directories, build/roomcore-release-signed, or
  anything outside build/ and the Chromium checkout's out/ directories.

== Part C: the Chapter 5 loop, resumed ==
- Adapt docs/chapter-loop-prompt.md's "The machine" to the mini (24 GB:
  ROOM_BUILD_JOBS=6 for official builds; the main display and its refresh
  rate from `system_profiler SPDisplaysDataType`; out/dev and out/release
  on the new volume) and commit that adaptation.
- Resume at the rebase night: `scripts/roomcore-rebase.sh <current Stable
  for Mac>` (read the tag from chromiumdash's Stable channel), `--verify`,
  then the official build (about 3 h 15 min here at 6 jobs: start it with
  nohup from bash and keep working on nothing that edits //room meanwhile).
  A rebase that needs more than one bounded fix stops, is recorded, and 5.4b
  runs on 155.0.8059.36 (which then also needs this machine's out/release
  rebuilt from the current //room: check RoomCoreCommit against main).
- Then 5.4b, 5.5a, 5.5b, 5.6a, 5.6b, 5.7a, 5.7b, 5.8a, 5.8b, 5.9 exactly as
  the loop prompt says (implementer subagents, one at a time; the review
  checklist; the fold-in; research/notes/chapter-5-loop.md entries). 5.4b's
  prompt names B-56 (with 5.4a's data), the renderer count, memory
  pressure, B-87, B-99, B-127, B-139, B-140, B-141 and the numbers table v3.
- DMGs after each phase as the loop says, now with the real feed
  (xcodegen/base.yml's ROOM_UPDATE_FEED_URL is
  https://updates.room.app/appcast.xml since build 20; builds 20 and 21
  were made on the laptop, so the mini's first is 22). Package into
  build/release/ (ROOM_RELEASE_DIR for the laptop's chain; with
  scripts/sparkle-package.sh directly, pass build/release as the output):
  generate_appcast writes one appcast over every DMG in it. An appcast with
  only the newest build is enough for Sparkle; the older ones need not be
  copied here.
- Publishing to users (an outward action), the user's standing instruction
  of 2026-10-21: publish the newest DMG whose phase the planner accepted
  (not "accepted with an engine regression", and only after its local CI
  spec passed), once, before 07:00 local time, with
  `scripts/release-publish.sh build/release <build>` (it refuses a DMG
  whose app is not notarized or not on the real feed). Then load
  https://updates.room.app/appcast.xml and check it lists that build, and
  record the publish in docs/progress.md and chapter-5-loop.md. Nothing
  else is published; after 07:00, build only.
```
