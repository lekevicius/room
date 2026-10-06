// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

@class RoomApplication;
@class RoomProfile;

NS_ASSUME_NONNULL_BEGIN

// The system's memory pressure as Chromium's monitor reports it
// (base::MemoryPressureLevel; on macOS from the kernel's memory-pressure
// events).
typedef NS_ENUM(NSInteger, RoomMemoryPressureLevel) {
  RoomMemoryPressureLevelNone = 0,
  RoomMemoryPressureLevelModerate,
  RoomMemoryPressureLevelCritical,
};

// -deleteProfile:completion:'s error codes, in the error domain
// @"RoomProfileDeletion" (a literal: an exported constant would join
// room_core.exports, which lists classes only, B-77).
typedef NS_ENUM(NSInteger, RoomProfileDeletionError) {
  // Not a loaded profile (destroyed, off the record, or being deleted).
  RoomProfileDeletionErrorNotLoaded = 1,
  // A page of the profile is open; the description says how many.
  RoomProfileDeletionErrorPagesOpen = 2,
  // Chrome still holds the profile after the wait.
  RoomProfileDeletionErrorStillLoaded = 3,
  // The profile is gone but its directory could not be deleted.
  RoomProfileDeletionErrorDirectoryLeft = 4,
};

ROOM_EXPORT NS_SWIFT_UI_ACTOR
@protocol RoomApplicationDelegate <NSObject>
// The browser process is up: profiles are loaded and RoomBrowser/RoomProfile
// can be used. Called from -[NSApplication finishLaunching], i.e. as the
// first thing on the main run loop, before NSApp.delegate receives
// applicationWillFinishLaunching: and applicationDidFinishLaunching:.
- (void)roomApplicationDidFinishLaunching:(RoomApplication*)application;

@optional
// Chromium is past the point of no return of a quit: all browsers are closed
// and the run loop is about to stop.
- (void)roomApplicationWillTerminate:(RoomApplication*)application;
// Chromium's memory-pressure notification (base::MemoryPressureListener):
// at each change of level and again while the pressure lasts (Chromium
// repeats a moderate or critical level). RoomCore never discards a Room page
// for it: the host's policy decides.
- (void)roomApplication:(RoomApplication*)application
    didChangeMemoryPressure:(RoomMemoryPressureLevel)level;
@end

// The browser process. One per process; the host creates it in main(),
// initializes it, then hands the main thread to -run. The host's first
// RoomCore call must be +sharedApplication, before it touches its
// RoomCrApplication subclass: Chromium's NSApplication +initialize reads the
// command line, which +sharedApplication sets up.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomApplication : NSObject

@property(class, nonatomic, readonly) RoomApplication* sharedApplication NS_SWIFT_NAME(shared);

// The site of `host` as Chromium counts it for same-site: the registrable
// domain (eTLD+1, net::registry_controlled_domains with private
// registries); the host itself for an IP address, localhost or any host
// without one. Lower-case, punycode.
+ (NSString*)siteForHost:(NSString*)host NS_SWIFT_NAME(site(forHost:));

@property(nonatomic, weak, nullable) id<RoomApplicationDelegate> delegate;

// Installed as NSApp.delegate as soon as -run creates NSApp, before Chromium
// starts: links from other apps, Dock reopen and applicationShouldTerminate:
// are the host's (Chrome's AppController is never installed; //room answers
// the messages Chrome sends it). NSApp holds it weakly: the host keeps it.
// Set before -run.
@property(nonatomic, weak, nullable) id<NSApplicationDelegate> applicationDelegate;

// Records the process arguments and startup options; does not start anything.
// `applicationClass` must be RoomCrApplication or a subclass. With a nil
// `userDataDirectory` the data root is ~/Library/Application Support/Room/
// RoomCore. Unless `arguments` say otherwise, the engine logs to
// RoomCore.log in the data root (--enable-logging/--log-file override it) and
// a build without a team signature runs with --use-mock-keychain.
- (BOOL)initializeWithArguments:(NSArray<NSString*>*)arguments
               applicationClass:(Class)applicationClass
              userDataDirectory:(nullable NSURL*)userDataDirectory
                          error:(NSError**)error
    NS_SWIFT_NAME(initialize(arguments:applicationClass:userDataDirectory:));

// Runs Chromium's browser main on this thread (creates NSApp, starts the
// browser process, runs the main run loop). Returns the process exit code
// once Chromium has shut down, after which no RoomCore object may be used.
- (int)run;

// Same as -[NSApp terminate:]: asks NSApp.delegate's
// applicationShouldTerminate: (RoomCrApplication honours it), then Chrome's
// close path.
- (void)tryToTerminate;

// Chrome's close path, for a delegate that answered NSTerminateLater:
// beforeunload handlers run on every browser's tabs (Chrome's
// BrowserCloseManager). A page answering "stay" cancels the quit and
// `completion(NO)` follows, every page still open. Otherwise every browser
// closes and `completion(YES)` arrives at the point of no return
// (chrome::OnAppExiting), before the run loop stops; -run returns once
// Chromium shut down. May call back before returning when no browser is
// open. Calls while a quit is under way only add their completion.
- (void)tryToTerminateWithCompletion:(nullable void (^)(BOOL terminating))completion
    NS_SWIFT_NAME(tryToTerminate(completion:));

// A quit is under way (browser_shutdown::IsTryingToQuit()): pages closing
// now are closed by the quit. NO again after a "stay".
@property(nonatomic, readonly, getter=isTerminating) BOOL terminating;

// The last memory-pressure level Chromium reported (None before the first).
@property(nonatomic, readonly) RoomMemoryPressureLevel memoryPressureLevel;

// Loaded profiles. Chromium loads the last used profile ("Default" on first
// launch) during startup.
@property(nonatomic, readonly) NSArray<RoomProfile*>* profiles;
@property(nonatomic, readonly, nullable) RoomProfile* defaultProfile;

// Loads the profile in directory `name` under the user data directory,
// creating it if needed. The completion receives nil on failure.
- (void)createProfile:(NSString*)name
           completion:(void (^)(RoomProfile* _Nullable profile))completion;

// Deletes `profile` and its directory (4.4b). Every page of the profile must
// be closed first: with one open the completion gets an error at once
// (code RoomProfileDeletionErrorPagesOpen) and nothing changes. Otherwise
// the profile is marked for deletion (Chrome's ProfilesDeleted list, so a
// crash before the end still deletes the directory at the next launch),
// stops being Chrome's last used profile, RoomCore lets go of it and closes
// its emptied browsers; Chrome unloads it, and once it is destroyed its
// directory and cache are deleted (NukeProfileFromDisk). The completion runs
// on the main thread: nil when the directory is gone; an error when it is
// still there (RoomProfileDeletionErrorDirectoryLeft) or when Chrome did not
// let go of the profile within 20 s (RoomProfileDeletionErrorStillLoaded:
// the directory goes at the next launch). The profile is not usable after
// the call.
- (void)deleteProfile:(RoomProfile*)profile
           completion:(void (^)(NSError* _Nullable error))completion
    NS_SWIFT_NAME(deleteProfile(_:completion:));

@end

NS_ASSUME_NONNULL_END
