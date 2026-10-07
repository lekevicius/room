// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

@class RoomBrowser;
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

// Why the host should not discard a page now: Chrome's own reasons
// (performance_manager's DiscardEligibilityPolicy::CanDiscard with
// CannotDiscardReason, asked as an urgent discard without Chrome's recent-
// visibility window: the host keeps its own idle clock). Empty when nothing
// blocks.
typedef NS_OPTIONS(NSUInteger, RoomDiscardBlockers) {
  // kFormInteractions: the user typed into a form on the page.
  RoomDiscardBlockersFormInteractions = 1 << 0,
  // kUserEdits: other user edits (contenteditable, a text area).
  RoomDiscardBlockersUserEdits = 1 << 1,
  // kPictureInPicture: video or document Picture-in-Picture.
  RoomDiscardBlockersPictureInPicture = 1 << 2,
  // kAudible: playing sound now.
  RoomDiscardBlockersAudible = 1 << 3,
  // kRecentlyAudible: played sound in the last minute.
  RoomDiscardBlockersRecentlyAudible = 1 << 4,
  // kCapturingVideo/Audio/Window/Display, kBeingMirrored.
  RoomDiscardBlockersCapturing = 1 << 5,
  // kNotificationsEnabled (the page may notify).
  RoomDiscardBlockersNotifications = 1 << 6,
  // kDevToolsOpen.
  RoomDiscardBlockersDevTools = 1 << 7,
  // kConnectedToUSB / kConnectedToBluetooth.
  RoomDiscardBlockersConnectedDevice = 1 << 8,
  // Anything else Chrome protects (a PDF, a non-web page, an earlier failed
  // attempt, no main frame yet).
  RoomDiscardBlockersOther = 1 << 9,
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

// Why a page's renderer process went away (base::TerminationStatus).
typedef NS_ENUM(NSInteger, RoomTerminationStatus) {
  RoomTerminationStatusNormal = 0,
  RoomTerminationStatusAbnormal,
  RoomTerminationStatusKilled,
  RoomTerminationStatusCrashed,
  RoomTerminationStatusOutOfMemory,
  RoomTerminationStatusLaunchFailed,
  RoomTerminationStatusIntegrityFailure,
};

// Which part of a keystroke the page consumed.
typedef NS_ENUM(NSInteger, RoomKeyEventPhase) {
  RoomKeyEventPhaseKeyDown = 0,
  RoomKeyEventPhaseKeyUp,
  RoomKeyEventPhaseCharacter,
};

// What a page's permission request asks for (Chrome's desktop
// permissions::RequestType, one case each).
typedef NS_ENUM(NSInteger, RoomPermissionKind) {
  RoomPermissionKindCamera = 0,
  RoomPermissionKindMicrophone,
  RoomPermissionKindCameraPanTiltZoom,
  RoomPermissionKindGeolocation,
  RoomPermissionKindNotifications,
  RoomPermissionKindClipboard,
  RoomPermissionKindMidiSysex,
  RoomPermissionKindStorageAccess,
  RoomPermissionKindTopLevelStorageAccess,
  RoomPermissionKindWindowManagement,
  RoomPermissionKindLocalFonts,
  RoomPermissionKindIdleDetection,
  RoomPermissionKindKeyboardLock,
  RoomPermissionKindPointerLock,
  RoomPermissionKindMultipleDownloads,
  RoomPermissionKindRegisterProtocolHandler,
  RoomPermissionKindFileSystemAccess,
  RoomPermissionKindLocalNetwork,
  RoomPermissionKindLoopbackNetwork,
  RoomPermissionKindSensors,
  RoomPermissionKindArSession,
  RoomPermissionKindVrSession,
  RoomPermissionKindHandTracking,
  RoomPermissionKindIdentityProvider,
  RoomPermissionKindWebAppInstallation,
  RoomPermissionKindCapturedSurfaceControl,
  // navigator.storage.persist() (kDiskQuota).
  RoomPermissionKindPersistentStorage,
};

// How the host answered a permission prompt (Chrome's
// PermissionPrompt::Delegate: Accept, AcceptThisTime, Deny, Dismiss).
typedef NS_ENUM(NSInteger, RoomPermissionResponse) {
  RoomPermissionResponseGranted = 0,
  RoomPermissionResponseGrantedOnce,
  RoomPermissionResponseDenied,
  RoomPermissionResponseDismissed,
};

// Why Chrome would show the quiet prompt (PermissionUiSelector's
// QuietUiReason); None when it would show the normal one.
typedef NS_ENUM(NSInteger, RoomPermissionQuietReason) {
  RoomPermissionQuietReasonNone = 0,
  RoomPermissionQuietReasonEnabledInSettings,
  RoomPermissionQuietReasonCrowdDeny,
  RoomPermissionQuietReasonAbusiveRequests,
  RoomPermissionQuietReasonAbusiveContent,
  RoomPermissionQuietReasonServicePredictedUnlikelyGrant,
  RoomPermissionQuietReasonOnDevicePredictedUnlikelyGrant,
  RoomPermissionQuietReasonDisruptiveBehavior,
  RoomPermissionQuietReasonLackOfGesture,
};

// macOS's own authorization for what the request needs (camera,
// microphone, location, notifications: Chrome's system_permission_settings),
// so the host can say when macOS, not the site's setting, blocks it.
typedef NS_ENUM(NSInteger, RoomSystemAuthorization) {
  // The request needs no system permission.
  RoomSystemAuthorizationNotApplicable = 0,
  // macOS has not asked yet (it will when the page gets access).
  RoomSystemAuthorizationNotDetermined,
  RoomSystemAuthorizationDenied,
  RoomSystemAuthorizationAuthorized,
};

// One permission in a prompt (permissions::PermissionRequest).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomPermissionRequest : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) RoomPermissionKind kind;
// The requesting origin.
@property(nonatomic, readonly, copy) NSURL* origin;
// The page's <permission> element asked (not a script call).
@property(nonatomic, readonly, getter=isEmbeddedPermissionElement)
    BOOL embeddedPermissionElement;
@property(nonatomic, readonly) RoomSystemAuthorization systemAuthorization;
@end

// One row of a context menu (ui::MenuModel's item).
typedef NS_ENUM(NSInteger, RoomMenuItemType) {
  RoomMenuItemTypeCommand = 0,
  RoomMenuItemTypeCheck,
  RoomMenuItemTypeRadio,
  RoomMenuItemTypeSeparator,
  RoomMenuItemTypeSubmenu,
};

ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomMenuItem : NSObject
- (instancetype)init NS_UNAVAILABLE;
// Chrome's command id (IDC_CONTENT_CONTEXT_*, spelling suggestions,
// extension items); -1 for a separator.
@property(nonatomic, readonly) NSInteger commandId;
@property(nonatomic, readonly) RoomMenuItemType type;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly, getter=isChecked) BOOL checked;
// The radio group (RoomMenuItemTypeRadio).
@property(nonatomic, readonly) NSInteger groupId;
// The key equivalent shown beside the title, as NSMenuItem takes it.
@property(nonatomic, readonly, copy) NSString* keyEquivalent;
@property(nonatomic, readonly) NSEventModifierFlags keyEquivalentModifierMask;
@property(nonatomic, readonly, copy, nullable) NSArray<RoomMenuItem*>* submenu;
@end

// What was under the pointer (content::ContextMenuParams).
typedef NS_ENUM(NSInteger, RoomContextMenuMediaType) {
  RoomContextMenuMediaTypeNone = 0,
  RoomContextMenuMediaTypeImage,
  RoomContextMenuMediaTypeVideo,
  RoomContextMenuMediaTypeAudio,
  RoomContextMenuMediaTypeCanvas,
  RoomContextMenuMediaTypeFile,
  RoomContextMenuMediaTypePlugin,
};

// A page's context menu as Chrome built it (RenderViewContextMenu): the
// host shows `items` and answers once, -selectCommand: or -cancel. Answers
// after the first, or after the page is gone, are ignored.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomContextMenu : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSArray<RoomMenuItem*>* items;
// In the page view's coordinates (top-left origin, points).
@property(nonatomic, readonly) NSPoint location;
@property(nonatomic, readonly, copy, nullable) NSURL* pageURL;
@property(nonatomic, readonly, copy, nullable) NSURL* frameURL;
@property(nonatomic, readonly, copy, nullable) NSURL* linkURL;
@property(nonatomic, readonly, copy, nullable) NSString* linkText;
@property(nonatomic, readonly, copy, nullable) NSURL* sourceURL;
@property(nonatomic, readonly) RoomContextMenuMediaType mediaType;
@property(nonatomic, readonly, copy, nullable) NSString* selectionText;
@property(nonatomic, readonly, getter=isEditable) BOOL editable;
@property(nonatomic, readonly, copy, nullable) NSString* misspelledWord;
@property(nonatomic, readonly, copy) NSArray<NSString*>* dictionarySuggestions;
// Runs Chrome's command (RenderViewContextMenu::ExecuteCommand) and closes
// the menu.
- (void)selectCommand:(NSInteger)commandId;
// Closes the menu without a command.
- (void)cancel;
@end

// An HTTP or proxy authentication challenge (net::AuthChallengeInfo).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomAuthChallenge : NSObject
- (instancetype)init NS_UNAVAILABLE;
// Scheme, host and port asking (the proxy's for a proxy).
@property(nonatomic, readonly, copy) NSURL* origin;
@property(nonatomic, readonly, copy, nullable) NSString* realm;
// "basic", "digest", "ntlm", "negotiate".
@property(nonatomic, readonly, copy) NSString* scheme;
// A proxy asks (named so as not to shadow NSObject's -isProxy).
@property(nonatomic, readonly, getter=isProxyChallenge) BOOL proxyChallenge;
@end

// A certificate error on a main-frame navigation (net::SSLInfo).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomCertificateError : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSURL* URL;
// The net::Error code, e.g. -202 ERR_CERT_AUTHORITY_INVALID.
@property(nonatomic, readonly) NSInteger errorCode;
// Chromium's name for it ("ERR_CERT_AUTHORITY_INVALID").
@property(nonatomic, readonly, copy) NSString* errorName;
// DER, leaf first.
@property(nonatomic, readonly, copy) NSArray<NSData*>* certificateChain;
// The host has HSTS or pinning (SSLInfo::is_fatal_cert_error): no bypass.
@property(nonatomic, readonly, getter=isStrictEnforcement) BOOL strictEnforcement;
// Chrome's verdict (CalculateSSLErrorOptionsMask): the person may proceed.
@property(nonatomic, readonly, getter=isOverridable) BOOL overridable;
@end

// What a file chooser asks for (blink::mojom::FileChooserParams).
typedef NS_ENUM(NSInteger, RoomFileChooserMode) {
  RoomFileChooserModeOpen = 0,
  RoomFileChooserModeOpenMultiple,
  // <input webkitdirectory>: the page gets the folder's files.
  RoomFileChooserModeUploadFolder,
  RoomFileChooserModeOpenDirectory,
  RoomFileChooserModeSave,
};

ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomFileChooserRequest : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) RoomFileChooserMode mode;
@property(nonatomic, readonly, copy, nullable) NSString* title;
@property(nonatomic, readonly, copy, nullable) NSURL* defaultPath;
// MIME types ("image/*") and extensions (".pdf") from the accept attribute.
@property(nonatomic, readonly, copy) NSArray<NSString*>* acceptTypes;
@end

// The kinds of JavaScript dialog (content::JavaScriptDialogType).
typedef NS_ENUM(NSInteger, RoomJavaScriptDialogType) {
  RoomJavaScriptDialogTypeAlert = 0,
  RoomJavaScriptDialogTypeConfirm,
  RoomJavaScriptDialogTypePrompt,
};

// The host's answer to an unresponsive renderer (Chrome's hung-page dialog:
// Wait restarts the hang monitor, Exit ends the renderer with RESULT_CODE_HUNG).
typedef NS_ENUM(NSInteger, RoomUnresponsiveAction) {
  RoomUnresponsiveActionWait = 0,
  RoomUnresponsiveActionTerminate,
};

// A page asks to open a URL in another application (mailto:, a custom
// scheme): Chrome's external protocol dialog (ExternalProtocolHandler) after
// its own checks (the scheme is not blocked, the application exists and is
// not Room).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomExternalProtocolRequest : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSURL* URL;
@property(nonatomic, readonly, copy) NSString* scheme;
// The site that asked (the precursor origin for a sandboxed frame).
@property(nonatomic, readonly, copy, nullable) NSURL* initiatingOrigin;
@property(nonatomic, readonly, getter=isUserGesture) BOOL userGesture;
// The application macOS would open it with ("Mail").
@property(nonatomic, readonly, copy) NSString* applicationName;
@end

typedef NS_ENUM(NSInteger, RoomInfoBarKind) {
  // One of Chrome's confirm infobars (infobars::ContentInfoBarManager).
  RoomInfoBarKindChrome = 0,
  // Chrome's translate offer (on the desktop a bubble through
  // BrowserWindow::ShowTranslateBubble, handed over the same way).
  RoomInfoBarKindTranslateOffer,
};

// A notice Chrome would show above the page: an infobar
// (ConfirmInfoBarDelegate) or the translate offer. The host shows it (a
// toast) until -webContents:didRemoveInfoBar:, and answers at most once.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomInfoBar : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) RoomInfoBarKind kind;
// Chrome's infobars::InfoBarDelegate::InfoBarIdentifier (the translate
// offer: TRANSLATE_INFOBAR_DELEGATE_NON_AURA).
@property(nonatomic, readonly) NSInteger identifier;
@property(nonatomic, readonly, copy) NSString* message;
// The button labels, the primary (OK, Translate) first; empty for a notice
// without buttons.
@property(nonatomic, readonly, copy) NSArray<NSString*>* buttons;
// The translate offer's languages (BCP 47 codes and display names).
@property(nonatomic, readonly, copy, nullable) NSString* sourceLanguage;
@property(nonatomic, readonly, copy, nullable) NSString* targetLanguage;
// Presses a button (0 = the primary): ConfirmInfoBarDelegate::Accept or
// Cancel; the translate offer's Translate (TranslateManager::TranslatePage).
- (void)pressButtonAtIndex:(NSInteger)index;
// Closes it without a choice (InfoBarDismissed).
- (void)dismiss;
@end

// What a page captures now (Chrome's MediaStreamCaptureIndicator): its
// camera, microphone, a screen, a tab or a window, and whether the page
// itself is being captured (mirrored) by another.
typedef NS_OPTIONS(NSUInteger, RoomCaptureState) {
  RoomCaptureStateCamera = 1 << 0,
  RoomCaptureStateMicrophone = 1 << 1,
  RoomCaptureStateDisplay = 1 << 2,
  RoomCaptureStateTab = 1 << 3,
  RoomCaptureStateWindow = 1 << 4,
  RoomCaptureStateMirrored = 1 << 5,
};

// What -stopCapturing: ends (MediaStreamCaptureIndicator::MediaType).
typedef NS_OPTIONS(NSUInteger, RoomCaptureKinds) {
  // getUserMedia: camera and microphone.
  RoomCaptureKindsUserMedia = 1 << 0,
  // getDisplayMedia: screens, windows, tabs.
  RoomCaptureKindsDisplayMedia = 1 << 1,
};

typedef NS_ENUM(NSInteger, RoomMediaPlaybackState) {
  RoomMediaPlaybackStateNone = 0,
  RoomMediaPlaybackStatePaused,
  RoomMediaPlaybackStatePlaying,
};

// The actions a media session supports (media_session::mojom::
// MediaSessionAction: the page's action handlers, and play, pause and stop
// for any playing media).
typedef NS_OPTIONS(NSUInteger, RoomMediaSessionActions) {
  RoomMediaSessionActionPlay = 1 << 0,
  RoomMediaSessionActionPause = 1 << 1,
  RoomMediaSessionActionPreviousTrack = 1 << 2,
  RoomMediaSessionActionNextTrack = 1 << 3,
  RoomMediaSessionActionSeekBackward = 1 << 4,
  RoomMediaSessionActionSeekForward = 1 << 5,
  RoomMediaSessionActionSeekTo = 1 << 6,
  RoomMediaSessionActionStop = 1 << 7,
  RoomMediaSessionActionSkipAd = 1 << 8,
};

// The page's media session (content::MediaSession: navigator.mediaSession
// metadata, or what Chrome infers from the playing media).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomMediaSessionInfo : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* artist;
@property(nonatomic, readonly, copy) NSString* album;
// The first artwork image's URL.
@property(nonatomic, readonly, copy, nullable) NSURL* artworkURL;
// That image as Chrome fetched it for the page (MediaSession::
// GetMediaImageBitmap, in the page's network context); nil until it arrives
// or when it cannot be decoded.
@property(nonatomic, readonly, nullable) NSImage* artwork;
@property(nonatomic, readonly) RoomMediaPlaybackState playbackState;
// MediaSessionActionsChanged.
@property(nonatomic, readonly) RoomMediaSessionActions actions;
// MediaSessionPositionChanged: whether the page (or its player) reported a
// position; then the duration, the position when this info was made and
// the playback rate (0 while paused).
@property(nonatomic, readonly) BOOL hasPosition;
@property(nonatomic, readonly) NSTimeInterval duration;
@property(nonatomic, readonly) NSTimeInterval position;
@property(nonatomic, readonly) double playbackRate;
@end

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
// Chrome wants the address field focused (IDC_FOCUS_LOCATION through the
// command dispatch, chrome::FocusLocationBar, LocationBar::FocusLocation):
// the host focuses its own field for this page.
- (void)webContentsDidRequestFocusOnLocationBar:(RoomWebContents*)webContents
    NS_SWIFT_NAME(webContentsDidRequestFocusOnLocationBar(_:));
// Where Chrome's own bubbles point while this page is its window's active
// page (the password save and update bubbles, address and card saves,
// device choosers, FedCM): the host's site button, in the window's
// coordinates. NSZeroRect (or not implemented): the window's top-left corner.
// Asked when a bubble is about to show and when the window moves or resizes.
- (NSRect)webContentsBubbleAnchorRect:(RoomWebContents*)webContents
    NS_SWIFT_NAME(webContentsBubbleAnchorRect(_:));
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
// The renderer process of the page's main frame went away (it crashed, was
// killed, ran out of memory); the page shows nothing until it is reloaded.
- (void)webContents:(RoomWebContents*)webContents
    renderProcessGone:(RoomTerminationStatus)status
    NS_SWIFT_NAME(webContents(_:renderProcessGone:));
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
// A permission prompt for the page (Chrome's PermissionRequestManager): one
// origin, one or more permissions (camera with microphone). Call
// `completion` once; a navigation or the page closing withdraws the prompt
// first (-webContentsDidDismissPermissionPrompt:), after which it is
// ignored. Not implemented: Chrome's own bubble.
- (void)webContents:(RoomWebContents*)webContents
    willAskForPermissions:(NSArray<RoomPermissionRequest*>*)requests
              quietReason:(RoomPermissionQuietReason)quietReason
               completion:(void (^)(RoomPermissionResponse response))completion
    NS_SWIFT_NAME(webContents(_:willAskForPermissions:quietReason:completion:));
// Chrome withdrew the pending prompt before the host answered.
- (void)webContentsDidDismissPermissionPrompt:(RoomWebContents*)webContents;
// The page's context menu. Return YES to show it (and later answer
// `menu`); NO lets Chrome show its own.
- (BOOL)webContents:(RoomWebContents*)webContents
    willShowContextMenu:(RoomContextMenu*)menu
    NS_SWIFT_NAME(webContents(_:willShowContextMenu:));
// HTTP or proxy authentication; `completion(nil, nil)` cancels. Not
// implemented: Chrome's own dialog.
- (void)webContents:(RoomWebContents*)webContents
    didReceiveAuthChallenge:(RoomAuthChallenge*)challenge
                 completion:(void (^)(NSString* _Nullable user,
                                      NSString* _Nullable password))completion
    NS_SWIFT_NAME(webContents(_:didReceiveAuthChallenge:completion:));
// A certificate error on the page's navigation, which waits for the answer:
// YES visits the site (Chrome remembers the decision for the host), NO stops
// the navigation (the page stays on what it showed). Not implemented:
// Chrome's own interstitial.
- (void)webContents:(RoomWebContents*)webContents
    didFailCertificateCheck:(RoomCertificateError*)error
                 completion:(void (^)(BOOL proceed))completion
    NS_SWIFT_NAME(webContents(_:didFailCertificateCheck:completion:));
// <input type=file>: `completion(nil)` cancels. Not implemented: Chrome's
// own panel.
- (void)webContents:(RoomWebContents*)webContents
     runFileChooser:(RoomFileChooserRequest*)request
         completion:(void (^)(NSArray<NSURL*>* _Nullable files))completion
    NS_SWIFT_NAME(webContents(_:runFileChooser:completion:));
// alert(), confirm(), prompt() of the page (Chrome's TabModalDialogManager,
// whose policy stays: dialogs of a page that is not shown are deferred or
// refused, a navigation withdraws them). Call `completion` once: OK with the
// prompt's text, or Cancel; after -webContentsDidDismissJavaScriptDialogs:
// it is ignored. Not implemented: Chrome's own dialog.
- (void)webContents:(RoomWebContents*)webContents
    runJavaScriptDialog:(RoomJavaScriptDialogType)type
                message:(NSString*)message
            defaultText:(NSString*)defaultText
                 origin:(nullable NSURL*)origin
             completion:(void (^)(BOOL accepted,
                                  NSString* _Nullable text))completion
    NS_SWIFT_NAME(webContents(_:runJavaScriptDialog:message:defaultText:origin:completion:));
// The page's beforeunload asks whether to leave (a close, a reload, the
// quit): YES leaves. A "stay" during a quit cancels the quit. Not
// implemented: Chrome's own alert.
- (void)webContents:(RoomWebContents*)webContents
    runBeforeUnloadDialogForReload:(BOOL)isReload
                        completion:(void (^)(BOOL leave))completion
    NS_SWIFT_NAME(webContents(_:runBeforeUnloadDialogForReload:completion:));
// Chrome withdrew the page's pending dialog (a navigation, the page closing
// or hidden, automation answered it): the host closes its sheet unanswered.
- (void)webContentsDidDismissJavaScriptDialogs:(RoomWebContents*)webContents;
// The page's renderer stopped answering input (Chrome's hang monitor):
// RoomUnresponsiveActionWait keeps waiting (asked again if it stays hung),
// Terminate ends the renderer (the page then reports its process gone). Not
// implemented: Chrome's own dialog.
- (void)webContentsRendererDidBecomeUnresponsive:(RoomWebContents*)webContents
                                      completion:
                                          (void (^)(RoomUnresponsiveAction action))
                                              completion
    NS_SWIFT_NAME(webContentsRendererDidBecomeUnresponsive(_:completion:));
// The renderer answers again: the question is withdrawn.
- (void)webContentsRendererDidBecomeResponsive:(RoomWebContents*)webContents;
// The page asks to open `request.URL` in another application; YES opens it
// (ExternalProtocolHandler::LaunchUrlWithoutSecurityCheck), NO blocks it.
// Not implemented: Chrome's own dialog.
- (void)webContents:(RoomWebContents*)webContents
    shouldOpenExternalProtocol:(RoomExternalProtocolRequest*)request
                    completion:(void (^)(BOOL open))completion
    NS_SWIFT_NAME(webContents(_:shouldOpenExternalProtocol:completion:));
// The page's navigation entries changed (a commit, a pruned list, a new
// title or page state of an entry): -navigationState reads something new.
// Coalesced: at most once per run-loop turn.
- (void)webContentsDidChangeNavigationState:(RoomWebContents*)webContents;
// Chrome added a notice for the page (an infobar, the translate offer).
- (void)webContents:(RoomWebContents*)webContents
      didAddInfoBar:(RoomInfoBar*)infoBar;
// The notice went (answered, the page navigated, Chrome removed it).
- (void)webContents:(RoomWebContents*)webContents
    didRemoveInfoBar:(RoomInfoBar*)infoBar;
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
// What the page captures now (camera, microphone, screen, tab, window) and
// whether it is being captured (MediaStreamCaptureIndicator).
@property(nonatomic, readonly) RoomCaptureState captureState;
// The page's media session; nil when it has none.
@property(nonatomic, readonly, nullable) RoomMediaSessionInfo* mediaSession;

// Navigates as if typed into the address bar.
- (void)loadURL:(NSURL*)URL;
// Navigates with `transition` (FROM_ADDRESS_BAR added when `fromAddressBar`).
- (void)loadURL:(NSURL*)URL
        transition:(RoomPageTransition)transition
    fromAddressBar:(BOOL)fromAddressBar;
- (void)goBack;
- (void)goForward;
// Reloads the page; a restored page that has not loaded yet (and a
// discarded one) loads its current entry instead
// (NavigationController::LoadIfNecessary).
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stop;

// Releases the renderer and keeps the navigation entries (Chrome's
// TabLifecycleUnit discard; the page needs a RoomBrowser). `nativeView`
// changes (Chrome replaces the WebContents). NO when Chrome refused.
- (BOOL)discard;
// Why Chrome would not discard the page now (empty: nothing blocks). Read
// on the main thread from performance_manager's graph; RoomCore never
// discards a Room page by itself (every page is not auto-discardable): the
// host decides.
@property(nonatomic, readonly) RoomDiscardBlockers discardBlockers;

// The page's navigation entries and the current one, in Chromium's session
// serialisation (sessions::SerializedNavigationEntry with its PageState, as
// Chrome's session file keeps them: up to six entries each side of the
// current one), opaque to the host; nil when the page has nothing to save.
// Written by this Chromium version: restoring it in another may fail.
@property(nonatomic, readonly, copy, nullable) NSData* navigationState;

// Restores entries -navigationState gave, before the page's first load
// (NavigationController::Restore): URL, title and canGoBack/canGoForward
// read the restored entry at once, and the next -reload loads it (with its
// scroll position and form state). NO when the data cannot be read (another
// version's format, damage) or the page has loaded already; the page is
// then untouched.
- (BOOL)restoreNavigationState:(NSData*)state;


// Gives the page keyboard focus.
- (void)focus;

// Leaves element fullscreen (the page's exitFullscreen()).
- (void)exitFullscreen;

// Ends the page's captures of `kinds` (MediaStreamCaptureIndicator::
// StopMediaCapturing); captureState follows.
- (void)stopCapturing:(RoomCaptureKinds)kinds;

// The media session's controls (content::MediaSession::Get(contents)): what
// a system media key or Chrome's own media controls do. Play and pause are
// Resume/Suspend(kUI), which run the page's "play"/"pause" action handler
// when it has one; next and previous track run the page's handler (nothing
// without one); seek runs "seekto" or seeks the players. mediaSession
// follows.
- (void)mediaPlay;
- (void)mediaPause;
- (void)mediaNextTrack;
- (void)mediaPreviousTrack;
- (void)mediaSeekTo:(NSTimeInterval)seconds;

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
// which runs its beforeunload handler first (the delegate's
// -webContents:runBeforeUnloadDialogForReload:completion:); the closed
// change follows once it is gone. A page in no
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

// What -savePageAs:toPath:completion: writes (content::SavePageType).
typedef NS_ENUM(NSInteger, RoomSavePageFormat) {
  // The page's HTML only (SAVE_PAGE_TYPE_AS_ONLY_HTML).
  RoomSavePageFormatHTML = 0,
  // The HTML with its resources in "<name>_files" beside it
  // (SAVE_PAGE_TYPE_AS_COMPLETE_HTML).
  RoomSavePageFormatCompleteHTML,
  // One MHTML web archive (WebContents::GenerateMHTML).
  RoomSavePageFormatMHTML,
};

// Saving the page and the DevTools protocol (Phase 4.7a).
@interface RoomWebContents (Documents)

// Saves the page to `path` (an absolute file path; complete HTML also
// writes "<path without extension>_files"). HTML and complete HTML go
// through Chrome's SavePackage (WebContents::SavePage), which shows as a
// download item through the downloads delegate; MHTML is
// WebContents::GenerateMHTML. The completion runs on the main thread once
// the file is written, with an error when the page cannot be saved (not
// savable, cancelled, interrupted, closed) or no answer came in 120 s.
- (void)savePageAs:(RoomSavePageFormat)format
            toPath:(NSString*)path
        completion:(void (^)(NSError* _Nullable error))completion
    NS_SWIFT_NAME(savePage(as:toPath:completion:));

// Sends one DevTools protocol command to the page (a DevToolsAgentHost
// client attached for this command and detached after its answer) and
// delivers its "result" object as Foundation values parsed from the JSON.
// `params` must be JSON-serialisable. An error when the protocol answers
// one, when the client cannot attach, or after 30 s. For the host's own
// commands (a full-page capture), never a debugging port.
- (void)sendDevToolsCommand:(NSString*)method
                     params:(NSDictionary<NSString*, id>*)params
                 completion:(void (^)(NSDictionary<NSString*, id>* _Nullable
                                          result,
                                      NSError* _Nullable error))completion
    NS_SWIFT_NAME(sendDevToolsCommand(_:params:completion:));

@end

// Moving a page between windows (Phase 4.8b).
@interface RoomWebContents (Windows)

// Moves the page into `browser`'s tab strip with its back/forward list, its
// tab helpers and its renderer: Chrome's tab drag between windows
// (TabStripModel::DetachTabAtForInsertion on the page's strip, then
// InsertDetachedTabAt on `browser`'s). `browser` must be open and of the
// page's profile. `nativeView` stays the same NSView: the host moves it from
// one window's views to the other's. A page not yet in a strip joins
// `browser` as -[RoomBrowser addWebContents:activate:] would; a page already
// in it stays. The browser it leaves closes when its strip empties (Chrome's
// rule). NO, with `error` set (domain "RoomWebContentsMove"), when the page
// is closed or `browser` is closed or of another profile.
- (BOOL)moveToBrowser:(RoomBrowser*)browser
                error:(NSError* _Nullable*)error NS_SWIFT_NAME(move(to:));

@end

NS_ASSUME_NONNULL_END
