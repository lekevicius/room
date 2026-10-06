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
// Pages of this profile still open: the host's own (created here, closed or
// not yet in a strip) and every tab of the profile's browsers (4.4b).
@property(nonatomic, readonly) NSInteger room_openPageCount;
// -[RoomApplication deleteProfile:completion:]'s second half (4.4b): lets go
// of the profile (its keep-alive, its emptied browsers); `completion` runs
// once the profile is destroyed and its directory deletion has run (`gone`:
// the directory no longer exists), or after the wait with `destroyed` NO.
- (void)room_deleteWithCompletion:(void (^)(BOOL destroyed,
                                            BOOL gone))completion;
// A deletion is under way (no second one, no new pages).
@property(nonatomic, readonly) BOOL room_deleting;
@end

#endif  // ROOM_CORE_ROOM_PROFILE_INTERNAL_H_
