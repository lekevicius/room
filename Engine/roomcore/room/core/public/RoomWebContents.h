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
  // Navigation policy answers (-webContents:decidePolicyForNavigationAction:)
  // and the disposition of a navigation in the page itself.
  RoomWindowOpenDispositionCurrentTab,
  RoomWindowOpenDispositionIgnoreAction,
  RoomWindowOpenDispositionSaveToDisk,
};

// How a navigation began: Chromium's ui::PageTransition core types (history
// and the omnibox rank by it).
typedef NS_ENUM(NSInteger, RoomPageTransition) {
  RoomPageTransitionLink = 0,
  RoomPageTransitionTyped,
  RoomPageTransitionAutoBookmark,
  RoomPageTransitionGenerated,
  RoomPageTransitionKeyword,
  RoomPageTransitionFormSubmit,
  RoomPageTransitionReload,
  // Back/forward, a subframe's, or nothing the host asked for.
  RoomPageTransitionOther,
};

// What started a navigation, exactly: a click on a link (an anchor, also
// one clicked by script while the user's gesture lasts) is never confused
// with the page's script setting window.location (Other).
typedef NS_ENUM(NSInteger, RoomNavigationKind) {
  RoomNavigationKindLinkClicked = 0,
  RoomNavigationKindFormSubmitted,
  RoomNavigationKindBackForward,
  RoomNavigationKindReload,
  // The host, the page's script, anything else.
  RoomNavigationKindOther,
};

// The page's connection security (Chrome's security_state::SecurityLevel,
// what its padlock shows).
typedef NS_ENUM(NSInteger, RoomSecurityLevel) {
  // No indicator: about:, file:, chrome:, a new page, a local host.
  RoomSecurityLevelNone = 0,
  RoomSecurityLevelSecure,
  // Not secure: plain HTTP, or HTTPS with mixed forms.
  RoomSecurityLevelWarning,
  // A certificate error the user clicked through, a Safe Browsing hit.
  RoomSecurityLevelDangerous,
};

// The renderer's lifecycle (Chrome's TabLifecycleUnit state).
typedef NS_ENUM(NSInteger, RoomLifecycleState) {
  RoomLifecycleStateActive = 0,
  // The renderer is gone; the navigation entries stay, the next load or
  // reload brings the page back with its history.
  RoomLifecycleStateDiscarded,
  // Chrome froze the page (it runs no tasks until it is shown).
  RoomLifecycleStateFrozen,
};

// A navigation about to start in a page's main frame (Chromium's
// NavigationHandle at WillStartRequest/WillRedirectRequest), or a link the
// page asked to open elsewhere (a modifier click, target=_blank,
// window.open).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomNavigationAction : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSURL* URL;
@property(nonatomic, readonly, copy, nullable) NSURL* referrer;
@property(nonatomic, readonly) RoomNavigationKind kind;
@property(nonatomic, readonly) RoomPageTransition transition;
// RoomWindowOpenDispositionCurrentTab for a navigation of the page itself.
@property(nonatomic, readonly) RoomWindowOpenDisposition disposition;
@property(nonatomic, readonly, getter=isUserGesture) BOOL userGesture;
// A server redirect (3xx) in the navigation's chain.
@property(nonatomic, readonly, getter=isRedirect) BOOL redirect;
// location.replace(), a meta refresh, a script navigation while the page
// loads (PAGE_TRANSITION_CLIENT_REDIRECT).
@property(nonatomic, readonly, getter=isClientRedirect) BOOL clientRedirect;
// The page started it (not the host).
@property(nonatomic, readonly, getter=isRendererInitiated) BOOL rendererInitiated;
@end

// Which part of a keystroke the page consumed.
typedef NS_ENUM(NSInteger, RoomKeyEventPhase) {
  RoomKeyEventPhaseKeyDown = 0,
  RoomKeyEventPhaseKeyUp,
  RoomKeyEventPhaseCharacter,
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
// A key-down on its way to the focused page, before the renderer sees it.
// YES keeps it from the page: the host handles it itself (its main menu).
- (BOOL)webContents:(RoomWebContents*)webContents
    isReservedKeyEvent:(NSEvent*)event;
// A key-down the page did not consume; YES when the host used it.
- (BOOL)webContents:(RoomWebContents*)webContents
    handleUnhandledKeyEvent:(NSEvent*)event;
// The page consumed a key event (the renderer's acknowledgement of the main
// frame's widget): the macOS key code, modifier flags and phase.
- (void)webContents:(RoomWebContents*)webContents
    didConsumeKeyCode:(unsigned short)keyCode
        modifierFlags:(NSEventModifierFlags)modifierFlags
                phase:(RoomKeyEventPhase)phase
    NS_SWIFT_NAME(webContents(_:didConsumeKeyCode:modifierFlags:phase:));
// Where a navigation goes, asked before it starts (and at each server
// redirect): RoomWindowOpenDispositionCurrentTab (or the action's own
// disposition) lets it proceed, IgnoreAction cancels it, another tab
// disposition cancels it here and opens the URL that way. Not implemented:
// every navigation proceeds.
- (RoomWindowOpenDisposition)webContents:(RoomWebContents*)webContents
         decidePolicyForNavigationAction:(RoomNavigationAction*)action
    NS_SWIFT_NAME(webContents(_:decidePolicyFor:));
// A main-frame navigation committed (not an error page): the page shows
// `URL` now. Same-document navigations (fragments, pushState) included.
- (void)webContents:(RoomWebContents*)webContents
    didCommitNavigationToURL:(NSURL*)URL
                  transition:(RoomPageTransition)transition
                sameDocument:(BOOL)sameDocument
    NS_SWIFT_NAME(webContents(_:didCommitNavigation:transition:sameDocument:));
// A find-in-page result (Chrome's FindNotificationDetails, merged by its
// FindTabHelper): the matches counted so far, the 1-based active match (0
// when there is none), the active match's rect in the page view's
// coordinates (top-left origin, points), and whether counting is done.
- (void)webContents:(RoomWebContents*)webContents
    didUpdateFindResultWithMatchCount:(NSInteger)matchCount
                          activeMatch:(NSInteger)activeMatch
                        selectionRect:(NSRect)selectionRect
                          finalUpdate:(BOOL)finalUpdate
    NS_SWIFT_NAME(webContents(_:didUpdateFindResultWithMatchCount:activeMatch:selectionRect:finalUpdate:));
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

// The page's favicon (Chrome's ContentFaviconDriver, 16 pt with the
// screen's representations); nil until the page has one.
@property(nonatomic, readonly, nullable) NSImage* favicon;
// 0...1 while loading, 1 when idle (WebContents::GetLoadProgress).
@property(nonatomic, readonly) double loadProgress;
// <meta name="theme-color">, nil when none (WebContents::GetThemeColor).
@property(nonatomic, readonly, nullable) NSColor* themeColor;
// The page's root background, nil before the first paint
// (WebContents::GetBackgroundColor).
@property(nonatomic, readonly, nullable) NSColor* backgroundColor;
@property(nonatomic, readonly) RoomSecurityLevel securityLevel;
// Passive mixed content shown on an HTTPS page.
@property(nonatomic, readonly) BOOL hasMixedContent;
// Playing sound now (WebContents::IsCurrentlyAudible, both edges).
@property(nonatomic, readonly, getter=isAudible) BOOL audible;
@property(nonatomic, getter=isMuted) BOOL muted;
// Page zoom, 1 is 100% (Chrome's ZoomController: per host, so the host's
// other pages change with it).
@property(nonatomic) double zoomFactor;
@property(nonatomic, readonly) RoomLifecycleState lifecycleState;

// Navigates as if typed into the address bar.
- (void)loadURL:(NSURL*)URL;
// Navigates with `transition` (FROM_ADDRESS_BAR added when `fromAddressBar`).
- (void)loadURL:(NSURL*)URL
        transition:(RoomPageTransition)transition
    fromAddressBar:(BOOL)fromAddressBar;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stop;

// Releases the renderer and keeps the navigation entries (Chrome's
// TabLifecycleUnit discard; the page needs a RoomBrowser). `nativeView`
// changes (Chrome replaces the WebContents). NO when Chrome refused.
- (BOOL)discard;

// Gives the page keyboard focus.
- (void)focus;

// Leaves element fullscreen (the page's exitFullscreen()).
- (void)exitFullscreen;

// Runs `script` in RoomCore's isolated world of the page's main frame (the
// page's DOM is shared; its own JavaScript globals are not visible) and
// delivers the completion value as Foundation objects: NSString, NSNumber,
// NSArray, NSDictionary, NSNull for null and undefined (and for an uncaught
// exception). Promises are not awaited. DevTools' own front-end
// (devtools://, -devToolsWebContents) runs it in its main world instead. `error` is set when the page is
// closed or has no live document. Called back on the main thread.
- (void)evaluateJavaScript:(NSString*)script
                completion:(void (^)(id _Nullable result,
                                     NSError* _Nullable error))completion
    NS_SWIFT_NAME(evaluateJavaScript(_:completion:));

// Closes the page. A page in a RoomBrowser closes through its tab strip,
// which runs its beforeunload handler first (Chrome's dialog until the host
// answers dialogs); the closed change follows once it is gone. A page in no
// RoomBrowser closes at once.
- (void)close;

@end

// What -showDevTools: opens DevTools on.
typedef NS_ENUM(NSInteger, RoomDevToolsTool) {
  // The panel DevTools last showed.
  RoomDevToolsToolDefault = 0,
  RoomDevToolsToolConsole,
  RoomDevToolsToolElements,
  // The element picker (Chrome's Inspect: the next click on the page picks).
  RoomDevToolsToolElementPicker,
};

// The page's tools: find, capture, print, DevTools.
@interface RoomWebContents (Tools)

// Finds `text` in the page (Chrome's FindTabHelper, one request per call):
// the same text again steps to the next match (`forward`) or the previous
// one; a new text starts a new find with its first match selected. Results
// arrive through the delegate.
- (void)findText:(NSString*)text
         forward:(BOOL)forward
       matchCase:(BOOL)matchCase
    NS_SWIFT_NAME(find(_:forward:matchCase:));
// Ends the find; the selection stays on the active match unless cleared.
- (void)stopFindingClearSelection:(BOOL)clearSelection
    NS_SWIFT_NAME(stopFinding(clearSelection:));

// The page's viewport as the compositor drew it, at the screen's scale (the
// image's size is in points; RenderWidgetHostView::CopyFromSurface). An
// error when the page has no surface to copy (closed, never shown).
- (void)captureViewportWithCompletion:
    (void (^)(NSImage* _Nullable image, NSError* _Nullable error))completion
    NS_SWIFT_NAME(captureViewport(completion:));

// Chrome's print preview over the host window (a Views dialog on the page's
// RoomBrowser), or the system print panel where policy disables the
// preview. NO when the page cannot print now.
- (BOOL)printWithPreview;

// DevTools for this page: Chrome's DevToolsWindow with its front-end in a
// RoomWebContents the host shows in its own view (never a Chromium window).
@property(nonatomic, readonly, getter=isDevToolsOpen) BOOL devToolsOpen;
// The front-end page while DevTools is open; the host adds its nativeView to
// its pane and sizes it. Its closed change follows when DevTools goes.
@property(nonatomic, readonly, nullable) RoomWebContents* devToolsWebContents
    NS_SWIFT_NAME(devToolsWebContents);
// Opens DevTools (or keeps it open) on `tool`.
- (void)showDevTools:(RoomDevToolsTool)tool;
// Opens DevTools on the Elements panel with the element at `point` (the
// page view's coordinates: top-left origin, points) selected.
- (void)inspectElementAtPoint:(NSPoint)point;
- (void)closeDevTools;

@end

NS_ASSUME_NONNULL_END
