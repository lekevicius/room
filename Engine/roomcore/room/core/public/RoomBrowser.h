// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

@class RoomBrowser;
@class RoomProfile;
@class RoomWebContents;

NS_ASSUME_NONNULL_BEGIN

ROOM_EXPORT NS_SWIFT_UI_ACTOR
@protocol RoomBrowserDelegate <NSObject>
@optional
- (void)browser:(RoomBrowser*)browser
    didActivateWebContents:(nullable RoomWebContents*)webContents
    NS_SWIFT_NAME(browser(_:didActivate:));
// Chromium decided to close this browser's window (quit, last tab closed,
// window.close()). The host should close its NSWindow; the RoomBrowser is
// gone once -browserDidClose: arrives.
- (void)browserWillClose:(RoomBrowser*)browser;
- (void)browserDidClose:(RoomBrowser*)browser;
@end

// Chrome's Browser (tab strip, commands, session) bound to a window the host
// owns. The host keeps drawing everything: RoomCore never adds views to
// `window`. The tab strip mirrors the host's loaded pages: pages the host
// adds, plus the pages they open (delivered to the opener's
// RoomWebContentsDelegate). A page becomes the active tab when it becomes
// visible or takes focus; RoomCore never reorders the strip for the host.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomBrowser : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProfile:(RoomProfile*)profile window:(NSWindow*)window;

@property(nonatomic, weak, nullable) id<RoomBrowserDelegate> delegate;
@property(nonatomic, readonly) RoomProfile* profile;
@property(nonatomic, readonly, weak, nullable) NSWindow* window;
@property(nonatomic, readonly) NSArray<RoomWebContents*>* webContents;
@property(nonatomic, readonly, nullable) RoomWebContents* activeWebContents;
@property(nonatomic, readonly, getter=isClosed) BOOL closed;

// Moves `webContents` into this browser's tab strip; the browser owns the page
// from now on.
- (void)addWebContents:(RoomWebContents*)webContents
                 activate:(BOOL)activate NS_SWIFT_NAME(add(_:activate:));

// Starts closing the browser: runs beforeunload handlers, closes the pages,
// then calls -browserWillClose: and -browserDidClose:.
- (void)close;

@end

NS_ASSUME_NONNULL_END
