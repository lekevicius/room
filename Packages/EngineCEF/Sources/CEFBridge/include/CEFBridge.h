#import <AppKit/AppKit.h>

#import "RoomCEFBrowser.h"

NS_ASSUME_NONNULL_BEGIN

/// The app's NSApplication subclass. CEF requires the shared application to
/// implement Chromium's CrAppProtocol; it must be instantiated (via
/// `+sharedApplication`) before anything else touches `NSApp`.
NS_SWIFT_UI_ACTOR
@interface RoomCEFApplication : NSApplication

/// Called instead of AppKit's terminate. CEF must leave its message loop on its
/// own (closing browsers first); `-terminate:` never exits the process directly.
@property(nonatomic, copy, nullable) void (^terminationHandler)(void);

@end

/// Process-wide CEF lifecycle. Each call is valid once, in this order:
/// load → initialize → runMessageLoop (returns after quitMessageLoop) → shutdown.
NS_SWIFT_UI_ACTOR
@interface RoomCEFRuntime : NSObject

/// dlopen()s Chromium Embedded Framework from Contents/Frameworks.
+ (BOOL)loadLibrary;

+ (BOOL)initializeWithUserDataDirectory:(NSURL*)userDataDirectory
                                logFile:(nullable NSURL*)logFile
                                 locale:(nullable NSString*)locale
                        useMockKeychain:(BOOL)useMockKeychain
                        enabledFeatures:(NSArray<NSString*>*)enabledFeatures
                       disabledFeatures:(NSArray<NSString*>*)disabledFeatures
                    remoteDebuggingPort:(NSInteger)remoteDebuggingPort
                                  error:(NSError**)error;

/// Runs the CEF (Chromium) message loop on top of `-[NSApplication run]`.
+ (void)runMessageLoop;

+ (void)quitMessageLoop;

+ (void)shutdown;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
