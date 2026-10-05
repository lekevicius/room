// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_EXTENSIONS_INTERNAL_H_
#define ROOM_CORE_ROOM_EXTENSIONS_INTERNAL_H_

#import "room/core/public/RoomExtensions.h"

class Profile;

@interface RoomProfileExtensions (Internal)
- (instancetype)initWithChromeProfile:(Profile*)profile;
// The profile is going away: observers detach, later calls do nothing.
- (void)room_profileWillBeDestroyed;
// From the window's popup (room_extension_popups.mm): the delegate hears it.
- (void)room_popupDidOpen:(RoomWebContents*)popup
                extension:(NSString*)identifier
              webContents:(RoomWebContents*)webContents
                     size:(NSSize)size;
- (void)room_popup:(RoomWebContents*)popup didResize:(NSSize)size;
- (void)room_popupDidClose:(RoomWebContents*)popup;
@end

namespace room {
// Installs the install-prompt hook (patch 0024), the update-check gate
// (patch 0025) and turns off Chrome's post-install dialog, which needs a
// BrowserView's toolbar (3.6a).
void InstallExtensionHooks();
}  // namespace room

#endif  // ROOM_CORE_ROOM_EXTENSIONS_INTERNAL_H_
