// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_PROFILE_INTERNAL_H_
#define ROOM_CORE_ROOM_PROFILE_INTERNAL_H_

#import "room/core/public/RoomProfile.h"

class Profile;

@interface RoomProfile (Internal)
// The wrapper for `profile`, created on first use and kept for the profile's
// lifetime.
+ (RoomProfile*)room_profileFor:(Profile*)profile;
// The wrapper if one was created; nil otherwise (never creates one).
+ (RoomProfile*)room_existingProfileFor:(Profile*)profile;
// nullptr once the profile is destroyed.
@property(nonatomic, readonly) Profile* room_profile;
// The extensions object if the host asked for it (never creates one).
@property(nonatomic, readonly) RoomProfileExtensions* room_existingExtensions;
@end

#endif  // ROOM_CORE_ROOM_PROFILE_INTERNAL_H_
