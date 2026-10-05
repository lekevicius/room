// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <Foundation/Foundation.h>

#import "RoomExport.h"

@class RoomWebContents;

NS_ASSUME_NONNULL_BEGIN

// A Chromium Profile: cookie jar, history, settings, extensions.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomProfile : NSObject

- (instancetype)init NS_UNAVAILABLE;

// Directory basename under the user data directory, e.g. "Default".
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSURL* directory;
@property(nonatomic, readonly, getter=isOffTheRecord) BOOL offTheRecord;

// Whether this profile's previous session ended cleanly: Chrome's
// ExitTypeService (the profile's exit_type pref, "Normal" after a clean quit,
// "Crashed" after a crash or a kill). Read when RoomCore first hands out the
// profile; it does not change during the session. RoomCore then acknowledges
// the crash on the host's behalf (the host restores its own state), so a
// clean quit of this session records "Normal" again.
@property(nonatomic, readonly) BOOL lastExitWasClean;

// A new page with nothing loaded. Owned by the returned object until it is
// added to a RoomBrowser.
- (RoomWebContents*)createWebContents;
// The same, hidden until its view is in a visible window
// (WebContents::CreateParams::initially_hidden): no frames, timers
// throttled.
- (RoomWebContents*)createWebContentsInitiallyHidden:(BOOL)initiallyHidden
    NS_SWIFT_NAME(createWebContents(initiallyHidden:));

// The favicon Chrome stored for a page this profile visited
// (FaviconService); nil when none. Called back on the main thread.
- (void)faviconForPageURL:(NSURL*)pageURL
               completion:(void (^)(NSImage* _Nullable favicon))completion
    NS_SWIFT_NAME(favicon(forPageURL:completion:));

@end

NS_ASSUME_NONNULL_END
