#ifndef ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_
#define ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_

namespace room {

// Restyles Chrome's video picture-in-picture controls through patch 0029's
// hook (5.12): Back to Tab and Close as labelled pills, the origin centred,
// the playback buttons growing under the pointer.
void InstallVideoOverlayHook();

// Spikes (`roomSpikeAction:` "pip-show-controls"): shows every open window's
// controls as a pointer over it would; returns how many it showed.
int DebugShowVideoOverlayControls();

}  // namespace room

#endif  // ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_
