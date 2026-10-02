// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

@class RoomProfile;

NS_ASSUME_NONNULL_BEGIN

// One page (content::WebContents). Properties are KVO-observable and change on
// the main thread.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomWebContents : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, readonly) RoomProfile* profile;

// The page's view. The host adds it to its own view hierarchy and sizes it;
// nil once the page is closed.
@property(nonatomic, readonly, nullable) NSView* nativeView;

@property(nonatomic, readonly, copy, nullable) NSURL* URL;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, getter=isLoading) BOOL loading;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic, readonly, getter=isClosed) BOOL closed;

// Navigates as if typed into the address bar.
- (void)loadURL:(NSURL*)URL;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;

// Gives the page keyboard focus.
- (void)focus;

// Closes the page (runs no beforeunload handlers).
- (void)close;

@end

NS_ASSUME_NONNULL_END
