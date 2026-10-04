// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

@class RoomProfile;
@class RoomWebContents;

NS_ASSUME_NONNULL_BEGIN

// How a page asked for a new page to open (Chromium's WindowOpenDisposition,
// the ones that create contents).
typedef NS_ENUM(NSInteger, RoomWindowOpenDisposition) {
  RoomWindowOpenDispositionNewForegroundTab = 0,
  RoomWindowOpenDispositionNewBackgroundTab,
  RoomWindowOpenDispositionNewPopup,
  RoomWindowOpenDispositionNewWindow,
  RoomWindowOpenDispositionNewPictureInPicture,
  RoomWindowOpenDispositionSingletonTab,
  RoomWindowOpenDispositionSwitchToTab,
  RoomWindowOpenDispositionOffTheRecord,
  RoomWindowOpenDispositionNewSplitView,
};

// What a page asks of the UI around it. Called on the main thread.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@protocol RoomWebContentsDelegate <NSObject>
@optional
// The page opened `newContents` (a link with a new-tab disposition,
// window.open, a document picture-in-picture window). It is already in the
// tab strip of this page's RoomBrowser, never in a window of its own; the
// host places it (or closes it). `requestedBounds` is the window.open
// features' rect or the picture-in-picture size (top-left screen
// coordinates; zero where the page asked nothing).
- (void)webContents:(RoomWebContents*)webContents
    didCreateWebContents:(RoomWebContents*)newContents
               targetURL:(nullable NSURL*)targetURL
             disposition:(RoomWindowOpenDisposition)disposition
         requestedBounds:(NSRect)requestedBounds
             userGesture:(BOOL)userGesture
    NS_SWIFT_NAME(webContents(_:didCreate:targetURL:disposition:requestedBounds:userGesture:));
// The link under the pointer or keyboard focus changed; nil when none.
- (void)webContents:(RoomWebContents*)webContents
    didChangeStatusText:(nullable NSString*)text;
// The page entered element fullscreen (Chrome granted it); the host makes
// the page fill the window, or calls -exitFullscreen to refuse.
- (void)webContentsDidRequestEnterFullscreen:(RoomWebContents*)webContents
                                      origin:(nullable NSURL*)origin;
// Element fullscreen ended (the page, Esc, or -exitFullscreen).
- (void)webContentsDidRequestExitFullscreen:(RoomWebContents*)webContents;
@end

// One page (content::WebContents). Properties are KVO-observable and change on
// the main thread.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomWebContents : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, readonly) RoomProfile* profile;
@property(nonatomic, weak, nullable) id<RoomWebContentsDelegate> delegate;

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

// Leaves element fullscreen (the page's exitFullscreen()).
- (void)exitFullscreen;

// Closes the page (runs no beforeunload handlers).
- (void)close;

@end

NS_ASSUME_NONNULL_END
