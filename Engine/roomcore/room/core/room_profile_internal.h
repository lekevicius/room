// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_PROFILE_INTERNAL_H_
#define ROOM_CORE_ROOM_PROFILE_INTERNAL_H_

#import "room/core/public/RoomProfile.h"

class BrowserWindowInterface;
class Profile;
@class NSWindow;

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
// patches/0014's off-the-record open from a page of `window` (4.8b): the
// twin's Room Browser in a host window (the host's incognito window), else
// one made for the twin in `window` and held until it closes (the host then
// moves the page into its incognito window). The twin is created if needed.
// nullptr for an off-the-record or destroyed profile.
- (BrowserWindowInterface*)room_offTheRecordBrowserForOpenFromWindow:
    (NSWindow*)window;
@end

#endif  // ROOM_CORE_ROOM_PROFILE_INTERNAL_H_
