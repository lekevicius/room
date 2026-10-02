// Copyright 2026 Jonas Lekevicius. All rights reserved.

// public/RoomCrApplication.h declares RoomCrApplication as an NSApplication
// subclass so the host compiles without Chromium's headers. Its real
// superclass is Chromium's BrowserCrApplication, which is why that header is
// not imported here.

#import "chrome/browser/chrome_browser_application_mac.h"
#include "chrome/app/chrome_command_ids.h"
#import "room/core/public/RoomExport.h"
#import "room/core/room_application_internal.h"

ROOM_EXPORT
@interface RoomCrApplication : BrowserCrApplication
@end

@implementation RoomCrApplication

- (void)setMainMenu:(NSMenu*)mainMenu {
  // Chrome's AppController builds a BookmarkMenuBridge from the main menu's
  // IDC_BOOKMARKS_MENU submenu whenever a browser window becomes main, and
  // CHECKs that it exists. The host's menu has no Bookmarks menu (yet), so
  // give it a hidden, empty one.
  if (mainMenu && ![mainMenu itemWithTag:IDC_BOOKMARKS_MENU]) {
    NSMenuItem* bookmarks = [[NSMenuItem alloc] initWithTitle:@"Bookmarks"
                                                       action:nil
                                                keyEquivalent:@""];
    bookmarks.tag = IDC_BOOKMARKS_MENU;
    bookmarks.submenu = [[NSMenu alloc] initWithTitle:@"Bookmarks"];
    bookmarks.hidden = YES;
    [mainMenu addItem:bookmarks];
  }
  [super setMainMenu:mainMenu];
}

- (void)finishLaunching {
  // Chrome's AppController (NSApp.delegate) finishes its own launch inside
  // super; the host starts after it.
  [super finishLaunching];
  [RoomApplication.sharedApplication room_didFinishLaunching];
}

@end
