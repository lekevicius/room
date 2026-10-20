# Chapter 5 — by hand

Since 2026-10-21 sessions verify their own work (AGENTS.md "Testing"). This file has two parts: what the sessions ran themselves, one result line per check, and the short list of steps that need the user (accounts, the real state and other browsers, hardware this Mac lacks, macOS prompts, the 120 Hz runs, taste). The current DMG goes at the top.

## The current DMG

- Build 14: `build/sparkle-14/Room-0.1.0-14.dmg` (2026-10-19).

## For the user

(At most ten steps per phase; the 120 Hz runs, B-16, B-20 and B-21, need the built-in panel as the main display.)

## Run by the sessions

(One line per check: the step, how it was run, the result or the backlog row.)

- **Loop step 0, permissions (2026-10-21, laptop, the user present):** Debug app over the release engine (build/roomcore-release, built 2026-10-19), throwaway state /tmp/room-step0, `chromesurfaces2 -RoomSpikeOnly permissions`: notifications popover answered (denied, remembered after reload); camera+microphone popover answered, macOS's question answered by the user, page result `camera: granted`; geolocation `popover=false`, state stays `prompt` (macOS Location Services for this build not granted; B-26's location stays a user step).
- **Loop step 0, B-62 (same app and night):** `pageservices -RoomSpikeOnly bluetooth`: chooser opened (448×444 over Room), cancel gives `NotFoundError`, quit clean, **no main-thread hang**; `pageservices -RoomSpikeOnly serial`: chooser opened (448×468), cancel `NotFoundError`, clean. The hang of 2026-10-06 does not reproduce with the machine's Bluetooth authorization answered: 5.4b needs no B-62 engine attempt; a real Bluetooth/serial device stays the user's hardware step.
