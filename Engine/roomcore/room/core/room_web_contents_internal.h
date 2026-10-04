// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_
#define ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_

#import "room/core/public/RoomWebContents.h"

#include <memory>

class GURL;

namespace content {
class WebContents;
}

namespace url {
class Origin;
}

@class RoomBrowser;

namespace room {
// Installs the WebContents-level hooks (patches/0015: the hovered link).
void InstallWebContentsHooks();
}  // namespace room

@interface RoomWebContents (Internal)
// A page the wrapper owns until -room_releaseWebContents.
- (instancetype)initWithChromeWebContents:
                    (std::unique_ptr<content::WebContents>)webContents
                                 profile:(RoomProfile*)profile;
// A page a tab strip already owns (one Chrome opened for a Room page).
- (instancetype)initWithUnownedChromeWebContents:
                    (content::WebContents*)webContents
                                         profile:(RoomProfile*)profile;
// The wrapper of `webContents`, if one was created.
+ (RoomWebContents*)room_existingWrapperFor:(content::WebContents*)webContents;
// Hands ownership to a tab strip; nullptr if the wrapper does not own it.
- (std::unique_ptr<content::WebContents>)room_releaseWebContents;
@property(nonatomic, readonly) content::WebContents* room_webContents;
// The RoomBrowser whose tab strip holds the page.
@property(nonatomic, weak) RoomBrowser* room_browser;

// Delegate calls from //room (main thread, never re-entrant from Chrome).
- (void)room_targetURLChanged:(const GURL&)url;
- (void)room_didEnterFullscreen:(const url::Origin&)origin;
- (void)room_didExitFullscreen;
- (void)room_didCreateWebContents:(RoomWebContents*)newContents
                        targetURL:(NSURL*)targetURL
                      disposition:(RoomWindowOpenDisposition)disposition
                  requestedBounds:(NSRect)requestedBounds
                      userGesture:(BOOL)userGesture;
@end

#endif  // ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_
