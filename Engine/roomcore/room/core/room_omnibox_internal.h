// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_OMNIBOX_INTERNAL_H_
#define ROOM_CORE_ROOM_OMNIBOX_INTERNAL_H_

#import "room/core/public/RoomOmnibox.h"

#include <string>

class Profile;

@interface RoomProfileHistory (Internal)
- (instancetype)initWithChromeProfile:(Profile*)profile;
// The profile is going away: pending queries are cancelled, later calls
// answer empty.
- (void)room_profileWillBeDestroyed;
@end

@interface RoomAutocompleteController (Internal)
- (instancetype)initWithChromeProfile:(Profile*)profile;
// Destroys Chrome's controllers (they hold the profile's services).
- (void)room_profileWillBeDestroyed;
@end

namespace room {
// Makes Room's engine the profile's default search engine
// (TemplateURLService), once the service has loaded. Templates use
// Chrome's {searchTerms}.
void SetDefaultSearchEngine(Profile* profile,
                            const std::u16string& name,
                            const std::u16string& keyword,
                            const std::string& search_url,
                            const std::string& suggest_url);
}  // namespace room

#endif  // ROOM_CORE_ROOM_OMNIBOX_INTERNAL_H_
