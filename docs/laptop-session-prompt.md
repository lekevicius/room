# Laptop session prompt — the Chapter 3 checks that need this machine

Paste the block below into a Claude Code session on the laptop, in the laptop's clone of the repository. It runs the measurements and device checks the Mac mini could not (its 120 Hz panel, camera, microphone, Bluetooth, the user's accounts are by hand) and records them in the repository. The Mac mini is reachable over ssh as `eve@eve.local` (192.168.1.64); nothing is built on the laptop unless you choose `docs/laptop-build.md` §B.

```
You are running the laptop half of Chapter 3's checks for the Room browser, in
this clone of the repository (the laptop: M1 Max, 64 GB, a 120 Hz panel, a
camera and microphone, Bluetooth). The Mac mini that ran Chapter 3 is
reachable as eve@eve.local (192.168.1.64); its repository is
/Users/eve/Code/room; it holds the built apps you copy. Do not build Chromium
here. Commit messages are prefixed `laptop:`. Work on main; push once at the
end; never add a Co-Authored-By or any attribution trailer.

Read first: AGENTS.md; docs/laptop-build.md (how the apps get here);
research/notes/chapter-3-by-hand.md (the list; you do the steps a session can
do and leave the rest marked for the user); docs/backlog.md rows B-16, B-18,
B-20, B-21 (the 120 Hz measurements: each names its script and what it
expects), B-26 (location, camera, microphone), B-62 (Web Serial and
Bluetooth), B-53 (switching p95, to measure here at 120 Hz too);
research/notes/spike-results.md "Phase 2.2b", "Phase 2.3", "Phase 2.4b",
"Phase 2.5" (how each number was taken at 60 Hz and the bound it has), "Phase
3.9 — grand tour on RoomCore 155.0.8059.36" (the exit tour's numbers to put
yours beside) and "Phase 3.4b" (the capture and chooser drives).

Setup:
1. git pull --ff-only; xcodegen.
2. Copy the Debug app over the release framework (the spike runner over the
   product engine, ~400 MB) from the Mac mini:
   mkdir -p build/roomcore-release/DerivedData/Build/Products/Debug && rsync -a --delete eve@eve.local:/Users/eve/Code/room/build/roomcore-release/DerivedData/Build/Products/Debug/Room.app build/roomcore-release/DerivedData/Build/Products/Debug/
   and export ROOM_APP=$PWD/build/roomcore-release/DerivedData/Build/Products/Debug/Room.app
   for every wrapper (run-spike.sh, tabs-measure.sh, sidebar-snapshots.sh,
   grand-tour.sh). The app is ad-hoc signed and runs with the mock keychain.
3. Start the test servers in a second shell: scripts/test-servers.sh.
4. Conditions for every number: the laptop's panel at 120 Hz (check System
   Settings ▸ Displays; state the refresh rate and the resolution), no
   screen sharing, the app's window key and frontmost, nothing else heavy
   running; record the load average. Spikes take -RoomStateDirectory and
   -RoomEngineDirectory under /tmp; never the real state directory.

The checks, in order (each a heading in research/notes/spike-results.md,
"Laptop (M1 Max, 120 Hz), 2026-10-xx: …", numbers beside the 60 Hz ones):
1. B-20, the palette at 120 Hz: scripts/run-spike.sh palettemeasure
   -RoomSidebarFixture 500 -RoomHistoryRows 50000 (three runs): open-to-frame,
   the first keystroke, later keys' p95; the 16 ms bound.
2. B-21, the space switch: scripts/run-spike.sh spaces -RoomSidebarFixture
   spaces500 -ApplePersistenceIgnoreState YES, the window frontmost (three
   runs): ⌃digit to the slide's first frame, median and p95.
3. B-18 and B-53, tab switching: scripts/tabs-measure.sh (three runs): click
   to committed, the page visible and first frame; the 16 ms p95 bound.
4. B-16, the 500-entry scroll: scripts/sidebar-snapshots.sh 500, then the
   trackpad fling is the user's (leave it marked); record the programmatic
   scroll's late frames at 120 Hz.
5. The exit tour's layout, sidebar and tabs sections once at 120 Hz for the
   comparison: scripts/grand-tour.sh --groups layout,sidebar,tabs light;
   counts and the timing checks beside the Mac mini's.
6. Devices: with the test servers up, scripts/run-spike.sh chromesurfaces
   -RoomSpikeOnly permissions and the capture fixture
   (research/spikes/phase-2.6/capture.html through the pageservices spike):
   camera and microphone prompts with real devices (Allow This Time, then
   Allow: the page's state, the row's capture indicator, stopCapturing); the
   macOS prompts for camera, microphone and location are the user's to
   answer: if one appears, stop that check, mark it for the user with the
   exact step, and continue with the next. Web Serial and Bluetooth (B-62):
   launch the app with `open -a <app> --args …` (TCC blames the launching
   app) and run the chooser fixture (research/spikes/phase-2.6/chooser.html):
   the choosers open and cancel; a Bluetooth permission prompt is the user's.
7. The signed DMG (scp eve@eve.local:/Users/eve/Code/room/build/sparkle-3.9/Room-0.1.0-1.dmg
   ~/Downloads/): mount it, copy Room.app to /Applications, launch it once
   on a scratch state is not possible (the Release app has no state flags):
   leave the launch to the user (the keychain prompt once) and only verify
   codesign --verify --deep --strict and spctl --assess on the copied app.

Rules: AGENTS.md's testing tiers (no driving the UI through accessibility or
computer-use; never answer a system dialog); numbers with conditions, not
adjectives; a number that misses its bound is recorded with the miss, not
chased (one profile at most if it misses by more than a quarter); nothing in
the product changes in this session; a spike that fails on the laptop for a
laptop reason is fixed in the spike and the fix said. Update the backlog
rows you measured (close B-18, B-20, B-21 if their numbers exist now; B-16's
fling stays the user's; B-26 and B-62 with what you saw), add a dated log
entry to docs/progress.md ("Laptop checks, Chapter 3"), append the steps
you could not do to research/notes/chapter-3-by-hand.md under a "Laptop"
heading with the exact command for each, commit, push once, watch CI.

Report: the numbers table (laptop 120 Hz beside the Mac mini 60 Hz, with
the bound per row), the device checks' outcomes, what is left for the user
and why, and anything that differed from the Mac mini that is not the panel.
```
