// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_APPLICATION_INTERNAL_H_
#define ROOM_CORE_ROOM_APPLICATION_INTERNAL_H_

#import "room/core/public/RoomApplication.h"

@interface RoomApplication (Internal)
// Called by RoomCrApplication once NSApp has finished launching.
- (void)room_didFinishLaunching;
@end

#endif  // ROOM_CORE_ROOM_APPLICATION_INTERNAL_H_
