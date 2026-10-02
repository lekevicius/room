// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

@class RoomApplication;
@class RoomProfile;

NS_ASSUME_NONNULL_BEGIN

ROOM_EXPORT NS_SWIFT_UI_ACTOR
@protocol RoomApplicationDelegate <NSObject>
// The browser process is up: profiles are loaded and RoomBrowser/RoomProfile
// can be used. Called from -[NSApplication finishLaunching], i.e. as the
// first thing on the main run loop.
- (void)roomApplicationDidFinishLaunching:(RoomApplication*)application;

@optional
// Chromium is past the point of no return of a quit: all browsers are closed
// and the run loop is about to stop.
- (void)roomApplicationWillTerminate:(RoomApplication*)application;
@end

// The browser process. One per process; the host creates it in main(),
// initializes it, then hands the main thread to -run. The host's first
// RoomCore call must be +sharedApplication, before it touches its
// RoomCrApplication subclass: Chromium's NSApplication +initialize reads the
// command line, which +sharedApplication sets up.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomApplication : NSObject

@property(class, nonatomic, readonly) RoomApplication* sharedApplication NS_SWIFT_NAME(shared);

@property(nonatomic, weak, nullable) id<RoomApplicationDelegate> delegate;

// Records the process arguments and startup options; does not start anything.
// `applicationClass` must be RoomCrApplication or a subclass. With a nil
// `userDataDirectory` Chromium's default (~/Library/Application Support/
// Chromium) is used, so hosts should always pass one.
- (BOOL)initializeWithArguments:(NSArray<NSString*>*)arguments
               applicationClass:(Class)applicationClass
              userDataDirectory:(nullable NSURL*)userDataDirectory
                          error:(NSError**)error
    NS_SWIFT_NAME(initialize(arguments:applicationClass:userDataDirectory:));

// Runs Chromium's browser main on this thread (creates NSApp, starts the
// browser process, runs the main run loop). Returns the process exit code
// once Chromium has shut down, after which no RoomCore object may be used.
- (int)run;

// Starts an orderly quit: closes every browser (beforeunload handlers may
// cancel it), then leaves the run loop so -run returns. Same as
// -[NSApp terminate:].
- (void)tryToTerminate;

// Loaded profiles. Chromium loads the last used profile ("Default" on first
// launch) during startup.
@property(nonatomic, readonly) NSArray<RoomProfile*>* profiles;
@property(nonatomic, readonly, nullable) RoomProfile* defaultProfile;

// Loads the profile in directory `name` under the user data directory,
// creating it if needed. The completion receives nil on failure.
- (void)createProfile:(NSString*)name
           completion:(void (^)(RoomProfile* _Nullable profile))completion;

@end

NS_ASSUME_NONNULL_END
