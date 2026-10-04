# Chapter 3 — by hand

What the Chapter 3 sessions could not check without a click, a device or an account, in phase order, with the launch command for each step. Sessions append to it; the user works through it at the end of the chapter (3.9 also has the Chapter 2 list once more on RoomCore). Friction goes into `docs/backlog.md` with the phase as the source.

## Setup

1. Build the fork and both RoomCore apps: `bash -c 'ROOM_BUILD_JOBS=6 nohup scripts/roomcore-build.sh > build/roomcore-build.log 2>&1 &'`, then `scripts/roomcore-package.sh` (Room.app on RoomCore in `build/roomcore/DerivedData`, the embryo host in `build/roomcore-host/DerivedData`).
2. The CEF app for comparison: `xcodegen && xcodebuild -scheme Room -configuration Debug -derivedDataPath build/DerivedData build`.

## Phase 3.1a

1. **The laptop's checkout drops patch 0010.** Its `room` branch carries PR #1's twelve patch commits, 0010 included; `scripts/roomcore-apply.sh` only adds missing patches, so it reports "0 applied, 11 already" while 0010 stays compiled in. In `$CHROMIUM_SRC` on the laptop: `git checkout room`, find the 0010 commit with `git log --oneline tags/154.0.8037.58..room` (subject `room: 0010-shutdown-worker-start-priority`), drop it with `git rebase --onto <0010>^ <0010> room`, then `scripts/roomcore-apply.sh` (expect "patches: 0 applied, 11 already on the room branch") and `scripts/roomcore-build.sh`. Needed before 3.1b's release build on the laptop.
2. **Room.app on RoomCore, by hand** (light, then dark):
   `build/roomcore/DerivedData/Build/Products/Debug/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-3.1a -RoomEngineDirectory /tmp/room-3.1a/engine -RoomSidebarFixture demo`
   Click through the sidebar entries (each page loads in the card), type a URL in the header field and with ⌘T, scroll and click links in a page, go back and forward with the menu, ⌘W a Today tab, ⌘Q. Expected gaps until their phases: no favicons, padlock or theme colour (3.3a), no find, zoom, print, DevTools (3.3b), no popups or `target=_blank` (3.2a), keys typed into the page do not fall through to Room's menu (⌘T/⌘L from inside a page: 3.2b), no dialogs, permission prompts or downloads (3.4), history is not recorded (3.3a/3.5). Anything else that breaks is a backlog row.
3. **macOS notification prompt for the new identity.** The first RoomCore launch under `app.room.desktop` showed two "“Room” Notifications" banners (Chromium's alert service registering). Choose in System Settings ▸ Notifications ▸ Room (Room uses none of its own yet; "Off" is the conservative answer).
4. **A stray directory from a spike run.** A wrapper's `activate` relaunched Room.app on RoomCore without arguments once (B-47); it opened the real state at `~/Library/Application Support/Room` (a running-flag write, nothing else changed) and created `~/Library/Application Support/Room/RoomCore`. Delete that `RoomCore` directory if you do not want it; the next launch of the CEF app runs the full integrity check once (unclean flag) and goes on.
5. **The defaults domain moved** from `com.lekevicius.room` to `app.room.desktop`: Room's own settings live in its database, but anything stored in user defaults by hand (Sparkle's keys, `NSInitialToolTipDelay`, window frames) starts fresh. `defaults delete com.lekevicius.room` clears the old domain when you no longer need it.
