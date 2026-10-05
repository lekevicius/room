#import <AppKit/AppKit.h>

// The ObjC face of one CEF browser. Only Foundation/AppKit types and C scalars
// cross this header (never CEF or std:: types); EngineCEF maps these to the
// Engine protocol in Swift. All calls and callbacks happen on the main thread.

NS_ASSUME_NONNULL_BEGIN

@class RoomCEFBrowser;
@class RoomCEFRequestContext;

/// Posted (object: the `RoomCEFBrowser`) after any browser's `OnBeforeClose`.
extern NSNotificationName const RoomCEFBrowserDidCloseNotification
    NS_SWIFT_NAME(RoomCEFBrowser.didCloseNotification);

/// `cef_window_open_disposition_t`, reduced to what the Engine distinguishes.
typedef NS_ENUM(NSInteger, RoomCEFDisposition) {
  RoomCEFDispositionCurrentTab,
  RoomCEFDispositionNewForegroundTab,
  RoomCEFDispositionNewBackgroundTab,
  RoomCEFDispositionNewPopup,
  RoomCEFDispositionNewWindow,
  RoomCEFDispositionSaveToDisk,
  RoomCEFDispositionOffTheRecord,
  RoomCEFDispositionIgnore,
  RoomCEFDispositionNewPictureInPicture,
};

/// Source part of `cef_transition_type_t` plus the back/forward qualifier.
typedef NS_ENUM(NSInteger, RoomCEFTransition) {
  RoomCEFTransitionLink,
  RoomCEFTransitionTyped,
  RoomCEFTransitionBookmark,
  RoomCEFTransitionGenerated,
  RoomCEFTransitionKeyword,
  RoomCEFTransitionFormSubmit,
  RoomCEFTransitionReload,
  RoomCEFTransitionBackForward,
  RoomCEFTransitionOther,
};

typedef NS_ENUM(NSInteger, RoomCEFJSDialogType) {
  RoomCEFJSDialogTypeAlert,
  RoomCEFJSDialogTypeConfirm,
  RoomCEFJSDialogTypePrompt,
};

typedef NS_ENUM(NSInteger, RoomCEFFileDialogMode) {
  RoomCEFFileDialogModeOpen,
  RoomCEFFileDialogModeOpenMultiple,
  RoomCEFFileDialogModeOpenFolder,
  RoomCEFFileDialogModeSave,
};

typedef NS_ENUM(NSInteger, RoomCEFTerminationStatus) {
  RoomCEFTerminationStatusAbnormal,
  RoomCEFTerminationStatusKilled,
  RoomCEFTerminationStatusCrashed,
  RoomCEFTerminationStatusOutOfMemory,
  RoomCEFTerminationStatusLaunchFailed,
  RoomCEFTerminationStatusIntegrityFailure,
  RoomCEFTerminationStatusNormal,
};

typedef NS_ENUM(NSInteger, RoomCEFPermissionResult) {
  RoomCEFPermissionResultAccept,
  RoomCEFPermissionResultDeny,
  RoomCEFPermissionResultDismiss,
  RoomCEFPermissionResultIgnore,
};

/// `cef_permission_request_types_t` bits (same values).
typedef NS_OPTIONS(uint32_t, RoomCEFPermissionTypes) {
  RoomCEFPermissionARSession = 1u << 0,
  RoomCEFPermissionCameraPanTiltZoom = 1u << 1,
  RoomCEFPermissionCameraStream = 1u << 2,
  RoomCEFPermissionCapturedSurfaceControl = 1u << 3,
  RoomCEFPermissionClipboard = 1u << 4,
  RoomCEFPermissionTopLevelStorageAccess = 1u << 5,
  RoomCEFPermissionDiskQuota = 1u << 6,
  RoomCEFPermissionLocalFonts = 1u << 7,
  RoomCEFPermissionGeolocation = 1u << 8,
  RoomCEFPermissionHandTracking = 1u << 9,
  RoomCEFPermissionIdentityProvider = 1u << 10,
  RoomCEFPermissionIdleDetection = 1u << 11,
  RoomCEFPermissionMicStream = 1u << 12,
  RoomCEFPermissionMidiSysex = 1u << 13,
  RoomCEFPermissionMultipleDownloads = 1u << 14,
  RoomCEFPermissionNotifications = 1u << 15,
  RoomCEFPermissionKeyboardLock = 1u << 16,
  RoomCEFPermissionPointerLock = 1u << 17,
  RoomCEFPermissionProtectedMediaIdentifier = 1u << 18,
  RoomCEFPermissionRegisterProtocolHandler = 1u << 19,
  RoomCEFPermissionStorageAccess = 1u << 20,
  RoomCEFPermissionVRSession = 1u << 21,
  RoomCEFPermissionWebAppInstallation = 1u << 22,
  RoomCEFPermissionWindowManagement = 1u << 23,
  RoomCEFPermissionFileSystemAccess = 1u << 24,
  RoomCEFPermissionLocalNetworkAccess = 1u << 25,
  RoomCEFPermissionLocalNetwork = 1u << 26,
  RoomCEFPermissionLoopbackNetwork = 1u << 27,
  RoomCEFPermissionSensors = 1u << 28,
};

/// `cef_media_access_permission_types_t` bits (same values).
typedef NS_OPTIONS(uint32_t, RoomCEFMediaAccess) {
  RoomCEFMediaAccessDeviceAudio = 1u << 0,
  RoomCEFMediaAccessDeviceVideo = 1u << 1,
  RoomCEFMediaAccessDesktopAudio = 1u << 2,
  RoomCEFMediaAccessDesktopVideo = 1u << 3,
};

typedef NS_ENUM(NSInteger, RoomCEFMenuItemType) {
  RoomCEFMenuItemTypeCommand,
  RoomCEFMenuItemTypeCheck,
  RoomCEFMenuItemTypeRadio,
  RoomCEFMenuItemTypeSeparator,
  RoomCEFMenuItemTypeSubmenu,
};

typedef NS_ENUM(NSInteger, RoomCEFMediaType) {
  RoomCEFMediaTypeNone,
  RoomCEFMediaTypeImage,
  RoomCEFMediaTypeVideo,
  RoomCEFMediaTypeAudio,
  RoomCEFMediaTypeCanvas,
  RoomCEFMediaTypeFile,
  RoomCEFMediaTypePlugin,
};

/// A main-frame navigation about to start (`OnBeforeBrowse`).
@interface RoomCEFNavigationRequest : NSObject
@property(nonatomic, readonly, copy) NSString* url;
@property(nonatomic, readonly, copy, nullable) NSString* referrer;
@property(nonatomic, readonly) RoomCEFTransition transition;
@property(nonatomic, readonly) BOOL userGesture;
@property(nonatomic, readonly) BOOL redirect;
/// `TT_CLIENT_REDIRECT_FLAG`: `location.replace()`, a meta refresh, a script navigation during load.
@property(nonatomic, readonly) BOOL clientRedirect;
@end

/// One row of a CEF context menu.
@interface RoomCEFMenuItem : NSObject
@property(nonatomic, readonly) NSInteger commandID;
@property(nonatomic, readonly) RoomCEFMenuItemType type;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) BOOL checked;
@property(nonatomic, readonly) NSInteger groupID;
@property(nonatomic, readonly, copy) NSArray<RoomCEFMenuItem*>* submenu;
/// Lower-case letter or digit; empty when the accelerator has no character.
@property(nonatomic, readonly, copy) NSString* keyEquivalent;
@property(nonatomic, readonly) NSEventModifierFlags keyEquivalentModifiers;
@end

/// `CefContextMenuParams`.
@interface RoomCEFContextMenuParams : NSObject
/// Browser view coordinates, top-left origin.
@property(nonatomic, readonly) NSPoint location;
@property(nonatomic, readonly, copy, nullable) NSString* pageURL;
@property(nonatomic, readonly, copy, nullable) NSString* frameURL;
@property(nonatomic, readonly, copy, nullable) NSString* linkURL;
@property(nonatomic, readonly, copy, nullable) NSString* sourceURL;
@property(nonatomic, readonly) RoomCEFMediaType mediaType;
@property(nonatomic, readonly, copy, nullable) NSString* selectionText;
@property(nonatomic, readonly) BOOL editable;
@property(nonatomic, readonly, copy, nullable) NSString* misspelledWord;
@property(nonatomic, readonly, copy) NSArray<NSString*>* dictionarySuggestions;
@end

/// Snapshot of a `CefDownloadItem`.
@interface RoomCEFDownloadItem : NSObject
@property(nonatomic, readonly) uint32_t identifier;
@property(nonatomic, readonly, copy) NSString* url;
@property(nonatomic, readonly, copy) NSString* suggestedFileName;
@property(nonatomic, readonly, copy, nullable) NSString* fullPath;
@property(nonatomic, readonly, copy, nullable) NSString* mimeType;
@property(nonatomic, readonly) int64_t receivedBytes;
/// -1 when unknown.
@property(nonatomic, readonly) int64_t totalBytes;
@property(nonatomic, readonly) int64_t currentSpeed;
@property(nonatomic, readonly) BOOL inProgress;
@property(nonatomic, readonly) BOOL complete;
@property(nonatomic, readonly) BOOL canceled;
@property(nonatomic, readonly) BOOL interrupted;
@property(nonatomic, readonly) BOOL paused;
@property(nonatomic, readonly, copy, nullable) NSDate* startTime;
@end

/// Pause/resume/cancel for one download; valid until it completes.
@interface RoomCEFDownloadControl : NSObject
- (void)pause;
- (void)resume;
- (void)cancel;
@end

/// SSL state of the visible navigation entry.
@interface RoomCEFSecurityStatus : NSObject
@property(nonatomic, readonly) BOOL secureConnection;
/// A certificate error other than revocation-check problems.
@property(nonatomic, readonly) BOOL certificateError;
/// Passive or active mixed content.
@property(nonatomic, readonly) BOOL mixedContent;
@end

/// Receives a browser's CEF handler callbacks. Every method has a "no UI"
/// fallback in the bridge, so all are optional.
NS_SWIFT_UI_ACTOR
@protocol RoomCEFBrowserDelegate <NSObject>
@optional
// Life span.
- (void)browserDidCreate:(RoomCEFBrowser*)browser;
/// `window.open` / `target=_blank`: return NO to block the popup.
- (BOOL)browser:(RoomCEFBrowser*)browser
    shouldOpenPopupWithURL:(nullable NSString*)url
               disposition:(RoomCEFDisposition)disposition
               userGesture:(BOOL)userGesture;
/// The popup allowed above exists; it is parked hidden until re-parented.
- (void)browser:(RoomCEFBrowser*)browser
    didCreatePopup:(RoomCEFBrowser*)popup
         targetURL:(nullable NSString*)url
       disposition:(RoomCEFDisposition)disposition
       userGesture:(BOOL)userGesture;
- (void)browserWillClose:(RoomCEFBrowser*)browser;
- (void)browserDidClose:(RoomCEFBrowser*)browser;

// Display.
- (void)browser:(RoomCEFBrowser*)browser didChangeAddress:(NSString*)url;
- (void)browser:(RoomCEFBrowser*)browser didChangeTitle:(nullable NSString*)title;
- (void)browser:(RoomCEFBrowser*)browser didChangeFaviconURLs:(NSArray<NSString*>*)urls;
- (void)browser:(RoomCEFBrowser*)browser didChangeFullscreen:(BOOL)fullscreen;
- (void)browser:(RoomCEFBrowser*)browser didChangeStatusMessage:(nullable NSString*)message;
- (void)browser:(RoomCEFBrowser*)browser didChangeLoadingProgress:(double)progress;
- (void)browser:(RoomCEFBrowser*)browser
    didChangeConsoleMessage:(NSString*)message
                     source:(NSString*)source
                       line:(NSInteger)line;

// Load.
- (void)browser:(RoomCEFBrowser*)browser
    loadingStateChanged:(BOOL)isLoading
              canGoBack:(BOOL)canGoBack
           canGoForward:(BOOL)canGoForward;
/// `CefLoadHandler::OnLoadStart` for the main frame: called after a
/// cross-document navigation committed (not for same-document ones).
- (void)browser:(RoomCEFBrowser*)browser
    didCommitMainFrameNavigation:(NSString*)url
                      transition:(RoomCEFTransition)transition;
- (void)browser:(RoomCEFBrowser*)browser didFinishMainFrameLoad:(NSInteger)httpStatusCode;
- (void)browser:(RoomCEFBrowser*)browser
    didFailMainFrameLoad:(NSInteger)errorCode
               errorText:(NSString*)errorText
                     url:(NSString*)url;

// Keyboard. `event` is the original NSEvent (key-down only).
- (BOOL)browser:(RoomCEFBrowser*)browser isReservedKeyEvent:(NSEvent*)event;
- (BOOL)browser:(RoomCEFBrowser*)browser handleUnhandledKeyEvent:(NSEvent*)event;

// Requests.
/// Return YES to cancel the navigation.
- (BOOL)browser:(RoomCEFBrowser*)browser shouldCancelNavigation:(RoomCEFNavigationRequest*)request;
/// ⌘-click / middle-click. Return YES to cancel (the delegate opens it itself).
- (BOOL)browser:(RoomCEFBrowser*)browser
    shouldCancelOpenURL:(NSString*)url
            disposition:(RoomCEFDisposition)disposition
            userGesture:(BOOL)userGesture;
- (void)browser:(RoomCEFBrowser*)browser
    authChallengeForOrigin:(NSString*)origin
                   isProxy:(BOOL)isProxy
                     realm:(nullable NSString*)realm
                    scheme:(NSString*)scheme
                completion:(void (^)(NSString* _Nullable user, NSString* _Nullable password))completion;
- (void)browser:(RoomCEFBrowser*)browser
    certificateError:(NSInteger)errorCode
                 url:(NSString*)url
         certificates:(NSArray<NSData*>*)derChain
          completion:(void (^)(BOOL proceed))completion;
- (void)browser:(RoomCEFBrowser*)browser renderProcessTerminated:(RoomCEFTerminationStatus)status;
/// `CefRequestHandler::OnRenderProcessUnresponsive`: `completion(YES)`
/// terminates the renderer, `NO` waits (CEF asks again if it stays hung).
- (void)browser:(RoomCEFBrowser*)browser
    renderProcessUnresponsiveWithCompletion:(void (^)(BOOL terminate))completion;
- (void)browserRenderProcessResponsive:(RoomCEFBrowser*)browser;
/// `CefDisplayHandler::OnMediaAccessChange`.
- (void)browser:(RoomCEFBrowser*)browser
    didChangeMediaAccessVideo:(BOOL)video
                        audio:(BOOL)audio;

// Permissions.
- (void)browser:(RoomCEFBrowser*)browser
    permissionPrompt:(uint64_t)promptID
              origin:(NSString*)origin
         permissions:(RoomCEFPermissionTypes)permissions
          completion:(void (^)(RoomCEFPermissionResult result))completion;
- (void)browser:(RoomCEFBrowser*)browser dismissPermissionPrompt:(uint64_t)promptID;
/// `completion` receives the allowed subset; 0 denies.
- (void)browser:(RoomCEFBrowser*)browser
    mediaAccessForOrigin:(NSString*)origin
             permissions:(RoomCEFMediaAccess)permissions
              completion:(void (^)(RoomCEFMediaAccess allowed))completion;

// JavaScript dialogs. `completion(success, input)`.
- (void)browser:(RoomCEFBrowser*)browser
    runJSDialog:(RoomCEFJSDialogType)type
        message:(NSString*)message
    defaultText:(NSString*)defaultText
         origin:(nullable NSString*)origin
     completion:(void (^)(BOOL success, NSString* _Nullable input))completion
    NS_SWIFT_NAME(browser(_:runJSDialog:message:defaultText:origin:completion:));
- (void)browser:(RoomCEFBrowser*)browser
    runBeforeUnloadDialogIsReload:(BOOL)isReload
                       completion:(void (^)(BOOL leave))completion;
- (void)browserDidResetDialogState:(RoomCEFBrowser*)browser;

// Context menu and file chooser: return NO to let CEF show its own UI.
- (BOOL)browser:(RoomCEFBrowser*)browser
    runContextMenu:(NSArray<RoomCEFMenuItem*>*)items
            params:(RoomCEFContextMenuParams*)params
        completion:(void (^)(NSInteger commandID))completion;  // < 0 cancels
- (BOOL)browser:(RoomCEFBrowser*)browser
    runFileDialog:(RoomCEFFileDialogMode)mode
            title:(nullable NSString*)title
      defaultPath:(nullable NSString*)defaultPath
     acceptTypes:(NSArray<NSString*>*)acceptTypes
       completion:(void (^)(NSArray<NSString*>* _Nullable paths))completion;

// Find.
- (void)browser:(RoomCEFBrowser*)browser
    findResultCount:(NSInteger)count
        activeMatch:(NSInteger)activeMatch
        finalUpdate:(BOOL)finalUpdate;

// Downloads. `completion(nil)` cancels.
- (void)browser:(RoomCEFBrowser*)browser
    willBeginDownload:(RoomCEFDownloadItem*)item
        suggestedName:(NSString*)suggestedName
           completion:(void (^)(NSString* _Nullable path))completion;
- (void)browser:(RoomCEFBrowser*)browser
    didUpdateDownload:(RoomCEFDownloadItem*)item
              control:(RoomCEFDownloadControl*)control;

// Audio: `GetAudioParameters`, called when the page starts producing sound.
- (void)browserDidBecomeAudible:(RoomCEFBrowser*)browser;

// Focus.
- (void)browserDidGainFocus:(RoomCEFBrowser*)browser;
@end

/// One CEF browser hosted as a child view (Alloy style). The browser lives in
/// `containerView`, which starts parked in an off-screen window and is moved
/// into the card by the host.
NS_SWIFT_UI_ACTOR
@interface RoomCEFBrowser : NSObject

/// Creates the browser synchronously under a new container view. `hidden`
/// keeps the container hidden until it is moved out of the parking window.
- (nullable instancetype)initWithRequestContext:(nullable RoomCEFRequestContext*)requestContext
                                         hidden:(BOOL)hidden
                                       delegate:(nullable id<RoomCEFBrowserDelegate>)delegate;
- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, weak, nullable) id<RoomCEFBrowserDelegate> delegate;
/// The view the host places; CEF's own view fills it and autoresizes.
@property(nonatomic, readonly) NSView* containerView;
/// CEF's `CefBrowserHostView` inside `containerView`; nil once closed.
@property(nonatomic, readonly, nullable) NSView* browserView;
@property(nonatomic, readonly) NSInteger identifier;
@property(nonatomic, readonly) BOOL isPopup;
/// YES between creation and `browserDidClose:`.
@property(nonatomic, readonly) BOOL isAlive;

/// Live browsers in creation order, popups included (DevTools front-ends are
/// not wrapped).
+ (NSArray<RoomCEFBrowser*>*)liveBrowsers;

- (void)loadURL:(NSString*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stopLoad;

@property(nonatomic, getter=isAudioMuted) BOOL audioMuted;
@property(nonatomic) double zoomLevel;

- (void)find:(NSString*)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext;
- (void)stopFinding:(BOOL)clearSelection;

/// `CloseBrowser(force)`; beforeunload runs unless `force`.
- (void)close:(BOOL)force;
/// `TryCloseBrowser`: YES when the browser can be (or was) closed now.
- (BOOL)tryClose;

- (void)setFocus:(BOOL)focus;
- (void)printPage;
/// `ExitFullscreen(true)`: leaves element fullscreen.
- (void)exitFullscreen;
- (nullable RoomCEFSecurityStatus*)visibleSecurityStatus;

/// CEF's own DevTools window: a separate Chrome-style top-level window. CEF
/// 154 cannot parent DevTools to a view on macOS (Chrome style refuses a
/// native parent, issue #3294, and DevTools is always Chrome style), so a
/// docked pane is hosted by EngineCEF itself. `point` (view coordinates,
/// top-left origin) selects that element; `NSZeroPoint` just opens.
- (void)showDevToolsWindowInspectingElementAt:(NSPoint)point;
- (void)closeDevTools;
@property(nonatomic, readonly) BOOL hasDevTools;

/// DevTools protocol over CEF's in-process channel. `params` is a JSON object
/// string (or nil); `completion` gets the raw JSON result or error object.
- (void)executeDevToolsMethod:(NSString*)method
                   paramsJSON:(nullable NSString*)params
                   completion:(void (^)(BOOL success, NSData* result))completion;

/// `DownloadImage` as a favicon of at most `maxSize` pixels.
- (void)downloadFavicon:(NSString*)url
                maxSize:(NSInteger)maxSize
             completion:(void (^)(NSImage* _Nullable image))completion;

@end

/// The content-setting types the site panel reads and writes
/// (`cef_content_setting_types_t`).
typedef NS_ENUM(NSInteger, RoomCEFContentSettingType) {
  RoomCEFContentSettingTypeGeolocation,
  RoomCEFContentSettingTypeCamera,
  RoomCEFContentSettingTypeMicrophone,
  RoomCEFContentSettingTypeNotifications,
  RoomCEFContentSettingTypeClipboard,
  RoomCEFContentSettingTypeSensors,
  RoomCEFContentSettingTypeMidiSysex,
  RoomCEFContentSettingTypePopups,
  RoomCEFContentSettingTypeSound,
  RoomCEFContentSettingTypeAutomaticDownloads,
  RoomCEFContentSettingTypeJavaScript,
  RoomCEFContentSettingTypeImages,
};

/// `cef_content_setting_values_t` (Default = nothing stored for the site).
typedef NS_ENUM(NSInteger, RoomCEFContentSettingValue) {
  RoomCEFContentSettingValueDefault,
  RoomCEFContentSettingValueAllow,
  RoomCEFContentSettingValueBlock,
  RoomCEFContentSettingValueAsk,
  RoomCEFContentSettingValueSessionOnly,
};

/// One profile: a `CefRequestContext` with its own cache path.
NS_SWIFT_UI_ACTOR
@interface RoomCEFRequestContext : NSObject

/// The global context (`root_cache_path`).
+ (instancetype)globalContext;

/// Creates a context whose `cache_path` is `path` (a child of the root cache
/// path); `completion` runs on `OnRequestContextInitialized`.
+ (void)createWithCachePath:(NSString*)path
                 completion:(void (^)(RoomCEFRequestContext* _Nullable context))completion;

- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, readonly, copy) NSString* cachePath;

/// All cookies, or those for `url`.
- (void)deleteCookiesForURL:(nullable NSString*)url completion:(void (^)(void))completion;
- (void)clearHTTPCacheWithCompletion:(void (^)(void))completion;
- (void)clearHTTPAuthCredentialsWithCompletion:(void (^)(void))completion;
- (void)clearCertificateExceptionsWithCompletion:(void (^)(void))completion;

/// `GetContentSetting(url, url, type)`: the value stored for the site, or Default.
- (RoomCEFContentSettingValue)contentSettingForURL:(NSString*)url type:(RoomCEFContentSettingType)type;
/// `SetContentSetting(url, url, type, value)`; Default removes the site's value.
- (void)setContentSetting:(RoomCEFContentSettingValue)value forURL:(NSString*)url type:(RoomCEFContentSettingType)type;

@end

NS_ASSUME_NONNULL_END
