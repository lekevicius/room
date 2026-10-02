// Copyright 2026 Jonas Lekevicius. All rights reserved.

// public/RoomCrApplication.h declares RoomCrApplication as an NSApplication
// subclass so the host compiles without Chromium's headers. Its real
// superclass is Chromium's BrowserCrApplication, which is why that header is
// not imported here.

#import "chrome/browser/chrome_browser_application_mac.h"
#import "room/core/public/RoomExport.h"
#import "room/core/room_application_internal.h"

ROOM_EXPORT
@interface RoomCrApplication : BrowserCrApplication
@end

@implementation RoomCrApplication

- (void)finishLaunching {
  // Chrome's AppController (NSApp.delegate) finishes its own launch inside
  // super; the host starts after it.
  [super finishLaunching];
  [RoomApplication.sharedApplication room_didFinishLaunching];
}

@end
