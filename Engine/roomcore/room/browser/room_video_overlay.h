#ifndef ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_
#define ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_

namespace room {

// Restyles Chrome's video picture-in-picture controls through patch 0029's
// hook (5.12, 5.13): every button on a frosted disc and the progress row on a
// frosted capsule, the origin centred, the playback buttons growing under the
// pointer.
void InstallVideoOverlayHook();

// Spikes (`roomSpikeAction:` "pip-show-controls"): shows every open window's
// controls as a pointer over it would; returns how many it showed.
int DebugShowVideoOverlayControls();

}  // namespace room

#endif  // ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_
