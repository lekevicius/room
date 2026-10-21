// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_APPLICATION_INTERNAL_H_
#define ROOM_CORE_ROOM_APPLICATION_INTERNAL_H_

#import "room/core/public/RoomApplication.h"

namespace content {
class WebContents;
}

namespace room {
// A Room page stopped loading (RoomWebContents' observer). The first visible
// one starts B-87's check: Chrome's own startup-complete signal gets 5 s.
void NoteRoomPageStoppedLoading(content::WebContents* contents);
}  // namespace room

@interface RoomApplication (Internal)
// Called by RoomCrApplication once NSApp has finished launching.
- (void)room_didFinishLaunching;
@end

#endif  // ROOM_CORE_ROOM_APPLICATION_INTERNAL_H_
