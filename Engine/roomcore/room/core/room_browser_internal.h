// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_BROWSER_INTERNAL_H_
#define ROOM_CORE_ROOM_BROWSER_INTERNAL_H_

#import "room/core/public/RoomBrowser.h"

namespace room {
class RoomBrowserExtensions;
}

@interface RoomBrowser (Internal)
// Makes `webContents` the strip's active tab (it became visible or took
// focus in the host's window). Posted; a page not in this strip is ignored.
- (void)room_activateWebContents:(RoomWebContents*)webContents;
// The window's extension popups and shortcuts (3.6b); nullptr once closed.
@property(nonatomic, readonly) room::RoomBrowserExtensions* room_extensions;
@end

#endif  // ROOM_CORE_ROOM_BROWSER_INTERNAL_H_
