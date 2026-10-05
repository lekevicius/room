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

@implementation RoomCrApplication {
  // The delegate answered NSTerminateLater and has not replied yet.
  BOOL _awaitingTerminateReply;
}

// Chrome's -terminate: goes straight to the AppController
// (tryToTerminateApplication: close every Browser, beforeunload may cancel),
// because Chrome's controller was NSApp.delegate and AppKit's
// applicationShouldTerminate: was never asked. Room's delegate is the host's
// (patches/0013), so honour AppKit's contract first: Cancel stops here, Now
// continues into Chrome's close path, Later waits for the delegate, which
// replies with -replyToApplicationShouldTerminate: (typically after
// -[RoomApplication tryToTerminateWithCompletion:]).
- (void)terminate:(id)sender {
  id<NSApplicationDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(applicationShouldTerminate:)]) {
    switch ([delegate applicationShouldTerminate:self]) {
      case NSTerminateCancel:
        return;
      case NSTerminateLater:
        _awaitingTerminateReply = YES;
        return;
      case NSTerminateNow:
        break;
    }
  }
  [super terminate:sender];
}

// Two callers wait for this reply. After -terminate: above, nothing in
// AppKit does (AppKit's own reply would exit() at once, before Chromium shut
// down): YES continues into Chrome's close path (a no-op when the delegate
// already started it), NO leaves the application running. A quit Apple event
// (the quit-timing scripts, the Dock, logout) instead goes through AppKit's
// -_handleAEQuit, which asks the delegate itself and runs a modal loop until
// the reply; AppKit's reply ends that loop, and with YES AppKit then sends
// -terminate: (as for Chrome's own delegate, which never says Later), which
// finds the quit already past its point of no return.
- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate {
  if (!_awaitingTerminateReply) {
    [super replyToApplicationShouldTerminate:shouldTerminate];
    return;
  }
  _awaitingTerminateReply = NO;
  if (shouldTerminate) {
    [super terminate:nil];
  }
}

- (void)finishLaunching {
  // The browser process is up before AppKit tells NSApp.delegate (the
  // host's) that the application finished launching.
  [RoomApplication.sharedApplication room_didFinishLaunching];
  [super finishLaunching];
}

@end
