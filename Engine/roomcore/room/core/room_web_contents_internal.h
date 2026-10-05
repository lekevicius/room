// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_
#define ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_

#import "room/core/public/RoomWebContents.h"

#include <memory>

class GURL;
@class NSEvent;

namespace content {
class WebContents;
}

namespace url {
class Origin;
}

@class RoomBrowser;

struct NavigateParams;

namespace room {
// Installs the WebContents-level hooks (patches/0015: the hovered link;
// patches/0016: the navigation throttle of Room pages).
void InstallWebContentsHooks();
// The policy answer for a page Navigate() is about to open from a Room page
// (a modifier click, target=_blank, window.open): false cancels it.
bool AllowOpenFromRoomPage(const NavigateParams& params);
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
// A page Chrome owns outside any tab strip (an extension's action popup,
// 3.6b): no tab helpers, no page services; its owner's delegate is Chrome's.
- (instancetype)initWithHostedChromeWebContents:
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
// Chrome wants the address field focused (RoomLocationBar::FocusLocation).
- (void)room_requestFocusOnLocationBar;
// The delegate's bubble anchor (window coordinates), NSZeroRect when none.
- (NSRect)room_bubbleAnchorRect;
- (void)room_didEnterFullscreen:(const url::Origin&)origin;
- (void)room_didExitFullscreen;
// Key routing from the page's RoomBrowserWindow (the delegate's answer).
- (BOOL)room_isReservedKeyEvent:(NSEvent*)event;
- (BOOL)room_handleUnhandledKeyEvent:(NSEvent*)event;
// Chrome attached its tab helpers (the page joined a tab strip): favicons
// and zoom are observed from now on.
- (void)room_tabHelpersAttached;
// Chrome replaced the page's WebContents in its strip (a discard,
// TabStripModelChange::kReplaced): the wrapper moves to `newContents`.
- (void)room_replaceWebContents:(content::WebContents*)newContents;
// The delegate's navigation policy (CurrentTab when it has none).
- (RoomWindowOpenDisposition)room_decidePolicy:(RoomNavigationAction*)action;
// The page's capture state and media session (room_page_state.mm), KVO.
- (void)room_setCaptureState:(RoomCaptureState)state;
- (void)room_setMediaSession:(RoomMediaSessionInfo*)info;
- (void)room_didCreateWebContents:(RoomWebContents*)newContents
                        targetURL:(NSURL*)targetURL
                      disposition:(RoomWindowOpenDisposition)disposition
                  requestedBounds:(NSRect)requestedBounds
                      userGesture:(BOOL)userGesture;
@end

#endif  // ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_
