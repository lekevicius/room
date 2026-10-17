# Capturing Room for the website

Every image and clip on the site comes from the real app, staged the same way each time, so a new build or a design change means re-running a script rather than re-shooting by hand.

## The parts

| Part | What it does |
|---|---|
| `-RoomSidebarFixture showcase` | Seeds four themed spaces (Studio, Reading, Work in its own profile, Travel), six Essentials, folders and real, good-looking pages (`App/Sources/Debug/ShowcaseSpikes.swift`). |
| `-RoomSpike showcase` | Warms every page once (favicons, caches), then stages each scene light and dark and asks for a capture. Every page gets `tidy`: consent banners hidden (captures are made from the EU), the scroll set. |
| `capture.sh` | Runs the spike and answers each request with `screencapture -o -l <window>`: Room's window alone, no shadow, transparent corners. Encodes to `Website/assets/shots/<scene>-<light|dark>.webp` at 2400 px. |
| `RoomRecorder/` (`room-record`) | Records Room's window alone with ScreenCaptureKit at 60 fps **without the system cursor**, and logs the pointer's path and clicks to `<clip>.cursor.json`. Plays a choreography (`scenes/<clip>.json`) with real events, so a clip can be redone. `--probe` prints the pointer's position in window points while you point at things. |
| `record.sh <clip> [light|dark]` | Stages the clip's first state (`-RoomShowcaseStage`), plays the scene with `room-record`, quits Room, then runs `clip.sh`. `ROOM_RECORD_MANUAL=1` records your own hands instead (Return stops). |
| `clip.sh <name> [trim]` | `.mov` → H.264 MP4 at 1920 px (faststart), a WebP poster, the trimmed pointer track, and `clips.json`, the list the site reads. |

The site draws the shadow, the corners and the **cursor** itself: the pointer is an SVG moved along the logged track in step with the video's frames, with a soft ring on each click. It stays sharp at any size and in both appearances, and it can be restyled without re-recording.

## Running

```bash
scripts/roomcore-package.sh --app-only        # a Debug app with the showcase spike
Website/capture/capture.sh                    # every still, light and dark (≈ 3 min)
Website/capture/capture.sh hero,palette       # some of them
Website/capture/record.sh palette             # one clip
Website/capture/record.sh spaces dark
```

Before a run: the screen awake and unlocked, Screen & System Audio Recording for the terminal (System Settings ▸ Privacy & Security), Accessibility as well for `record.sh` (it posts events). Leave the Mac alone while it runs; the spike keeps Room in front.

The state lives in `build/showcase/state` and survives runs, so the second run has every favicon. `ROOM_SHOWCASE_FRESH=1` starts it over. `ROOM_SHOWCASE_SIZE=1600x1000` changes the window.

## Scenes

Stills (`capture.sh`): `hero`, `sidebar`, `spaces` (a slide between two spaces slowed 30× and caught midway: both lists, two tints), `palette`, `peek`, `split`, `reader`, `hidden`.

Clips (`scenes/*.json`): one step per line.

```json
{ "start": [930, 560],
  "steps": [
    { "wait": 0.8 },
    { "move": [880, 430], "duration": 0.7, "arc": 0.08 },
    { "click": true, "modifiers": "shift" },
    { "drag": [150, 300], "duration": 0.9 },
    { "key": "cmd+t" },
    { "type": "palette", "interval": 0.11 },
    { "scroll": [0, 420], "duration": 1.0 }
  ] }
```

Points are Room's window points from its top-left corner at the staged size (1440×900, sidebar 300). Moves follow a gentle arc with smootherstep easing at 120 Hz; typing has a little human unevenness. Find coordinates with `room-record --probe` while Room is staged (`record.sh` leaves it staged if the scene fails). `palette.json` and `spaces.json` are keyboard-led and work as they are; `peek.json` and `sidebar.json` hold first guesses for the link and row positions, to be probed.

## Seeds

Pages were chosen for how they look in a window: galleries, a painting, well-set essays, Apple's documentation. A page that changes (a new banner, a redesign) is replaced in `ShowcaseSpikes.swift` by editing its URL; the scenes find pages by a fragment of their URL.
