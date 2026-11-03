#ifndef ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_
#define ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_

namespace room {

// Replaces Chrome's video picture-in-picture controls through patch 0029's
// hook (5.13): AppKit's Liquid Glass controls over the video, the window's
// corners rounded; Chrome's controls, scrims and title hidden.
void InstallVideoOverlayHook();

// Spikes (`roomSpikeAction:` "pip-show-controls"): shows every open window's
// controls as a pointer over it would; returns how many it showed.
int DebugShowVideoOverlayControls();

}  // namespace room

#endif  // ROOM_BROWSER_ROOM_VIDEO_OVERLAY_H_
