// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

NS_ASSUME_NONNULL_BEGIN

// The NSApplication class Chromium's browser process runs on. The host's
// NSApplication subclass must inherit from it and be passed to
// -[RoomApplication initializeWithArguments:applicationClass:...]; RoomCore
// creates NSApp from it at the right moment of startup, so the host must not
// touch NSApplication.sharedApplication before -[RoomApplication run].
//
// It brings everything Chromium expects of NSApp: CrAppProtocol and
// CrAppControlProtocol (nested event loops), event observers for input
// latency, accessibility hooks, and an orderly -terminate: that first asks
// NSApp's delegate (the host's: -applicationShouldTerminate:, with
// NSTerminateLater answered by -replyToApplicationShouldTerminate:), then
// closes all browsers before the run loop exits (-[RoomApplication run] then
// returns). Chrome's own AppController is never NSApp's delegate.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomCrApplication : NSApplication
@end

NS_ASSUME_NONNULL_END
