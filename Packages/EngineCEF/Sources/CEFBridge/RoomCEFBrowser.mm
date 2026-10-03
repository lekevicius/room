#import "RoomCEFBrowser.h"

#include <map>
#include <string>
#include <vector>

#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_cookie.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_image.h"
#include "include/cef_parser.h"
#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_ssl_info.h"
#include "include/cef_ssl_status.h"
#include "include/cef_x509_certificate.h"

NSNotificationName const RoomCEFBrowserDidCloseNotification = @"RoomCEFBrowserDidClose";

namespace {

NSString* ToNS(const CefString& value) {
  std::string utf8 = value.ToString();
  return [[NSString alloc] initWithBytes:utf8.data() length:utf8.size() encoding:NSUTF8StringEncoding] ?: @"";
}

NSString* ToNSOrNil(const CefString& value) {
  return value.empty() ? nil : ToNS(value);
}

CefString ToCef(NSString* value) {
  return CefString(std::string(value.UTF8String ?: ""));
}

RoomCEFDisposition ToDisposition(cef_window_open_disposition_t disposition) {
  switch (disposition) {
    case CEF_WOD_NEW_FOREGROUND_TAB:
    case CEF_WOD_SINGLETON_TAB:
    case CEF_WOD_SWITCH_TO_TAB:
      return RoomCEFDispositionNewForegroundTab;
    case CEF_WOD_NEW_BACKGROUND_TAB:
      return RoomCEFDispositionNewBackgroundTab;
    case CEF_WOD_NEW_POPUP:
      return RoomCEFDispositionNewPopup;
    case CEF_WOD_NEW_WINDOW:
      return RoomCEFDispositionNewWindow;
    case CEF_WOD_SAVE_TO_DISK:
      return RoomCEFDispositionSaveToDisk;
    case CEF_WOD_OFF_THE_RECORD:
      return RoomCEFDispositionOffTheRecord;
    case CEF_WOD_IGNORE_ACTION:
      return RoomCEFDispositionIgnore;
    case CEF_WOD_NEW_PICTURE_IN_PICTURE:
      return RoomCEFDispositionNewPictureInPicture;
    case CEF_WOD_CURRENT_TAB:
    case CEF_WOD_UNKNOWN:
      return RoomCEFDispositionCurrentTab;
    default:
      // CEF_WOD_NEW_SPLIT_VIEW and future values.
      return RoomCEFDispositionNewForegroundTab;
  }
}

RoomCEFTransition ToTransition(cef_transition_type_t transition) {
  const int value = static_cast<int>(transition);
  if (value & TT_FORWARD_BACK_FLAG) {
    return RoomCEFTransitionBackForward;
  }
  switch (value & TT_SOURCE_MASK) {
    case TT_LINK:
      return RoomCEFTransitionLink;
    case TT_EXPLICIT:
      return RoomCEFTransitionTyped;
    case TT_AUTO_BOOKMARK:
      return RoomCEFTransitionBookmark;
    case TT_GENERATED:
      return RoomCEFTransitionGenerated;
    case TT_KEYWORD:
    case TT_KEYWORD_GENERATED:
      return RoomCEFTransitionKeyword;
    case TT_FORM_SUBMIT:
      return RoomCEFTransitionFormSubmit;
    case TT_RELOAD:
      return RoomCEFTransitionReload;
    default:
      return RoomCEFTransitionOther;
  }
}

RoomCEFTerminationStatus ToTerminationStatus(cef_termination_status_t status) {
  switch (status) {
    case TS_ABNORMAL_TERMINATION:
      return RoomCEFTerminationStatusAbnormal;
    case TS_PROCESS_WAS_KILLED:
      return RoomCEFTerminationStatusKilled;
    case TS_PROCESS_CRASHED:
      return RoomCEFTerminationStatusCrashed;
    case TS_PROCESS_OOM:
      return RoomCEFTerminationStatusOutOfMemory;
    case TS_LAUNCH_FAILED:
      return RoomCEFTerminationStatusLaunchFailed;
    case TS_INTEGRITY_FAILURE:
      return RoomCEFTerminationStatusIntegrityFailure;
    default:
      return RoomCEFTerminationStatusNormal;
  }
}

RoomCEFMediaType ToMediaType(cef_context_menu_media_type_t type) {
  switch (type) {
    case CM_MEDIATYPE_IMAGE:
      return RoomCEFMediaTypeImage;
    case CM_MEDIATYPE_VIDEO:
      return RoomCEFMediaTypeVideo;
    case CM_MEDIATYPE_AUDIO:
      return RoomCEFMediaTypeAudio;
    case CM_MEDIATYPE_CANVAS:
      return RoomCEFMediaTypeCanvas;
    case CM_MEDIATYPE_FILE:
      return RoomCEFMediaTypeFile;
    case CM_MEDIATYPE_PLUGIN:
      return RoomCEFMediaTypePlugin;
    default:
      return RoomCEFMediaTypeNone;
  }
}

// The window every browser is created in: never ordered on screen, so new
// browsers start occluded until the host moves their container to its window.
NSWindow* ParkingWindow() {
  static NSWindow* window;
  if (!window) {
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 1280, 800)
                                         styleMask:NSWindowStyleMaskBorderless
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView.wantsLayer = YES;
  }
  return window;
}

}  // namespace

// MARK: - Value objects

@interface RoomCEFNavigationRequest ()
@property(nonatomic, copy) NSString* url;
@property(nonatomic, copy, nullable) NSString* referrer;
@property(nonatomic) RoomCEFTransition transition;
@property(nonatomic) BOOL userGesture;
@property(nonatomic) BOOL redirect;
@end
@implementation RoomCEFNavigationRequest
@end

@interface RoomCEFMenuItem ()
@property(nonatomic) NSInteger commandID;
@property(nonatomic) RoomCEFMenuItemType type;
@property(nonatomic, copy) NSString* title;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL checked;
@property(nonatomic) NSInteger groupID;
@property(nonatomic, copy) NSArray<RoomCEFMenuItem*>* submenu;
@property(nonatomic, copy) NSString* keyEquivalent;
@property(nonatomic) NSEventModifierFlags keyEquivalentModifiers;
@end
@implementation RoomCEFMenuItem
@end

@interface RoomCEFContextMenuParams ()
@property(nonatomic) NSPoint location;
@property(nonatomic, copy, nullable) NSString* pageURL;
@property(nonatomic, copy, nullable) NSString* frameURL;
@property(nonatomic, copy, nullable) NSString* linkURL;
@property(nonatomic, copy, nullable) NSString* sourceURL;
@property(nonatomic) RoomCEFMediaType mediaType;
@property(nonatomic, copy, nullable) NSString* selectionText;
@property(nonatomic) BOOL editable;
@property(nonatomic, copy, nullable) NSString* misspelledWord;
@property(nonatomic, copy) NSArray<NSString*>* dictionarySuggestions;
@end
@implementation RoomCEFContextMenuParams
@end

@interface RoomCEFDownloadItem ()
@property(nonatomic) uint32_t identifier;
@property(nonatomic, copy) NSString* url;
@property(nonatomic, copy) NSString* suggestedFileName;
@property(nonatomic, copy, nullable) NSString* fullPath;
@property(nonatomic, copy, nullable) NSString* mimeType;
@property(nonatomic) int64_t receivedBytes;
@property(nonatomic) int64_t totalBytes;
@property(nonatomic) int64_t currentSpeed;
@property(nonatomic) BOOL inProgress;
@property(nonatomic) BOOL complete;
@property(nonatomic) BOOL canceled;
@property(nonatomic) BOOL interrupted;
@property(nonatomic) BOOL paused;
@property(nonatomic, copy, nullable) NSDate* startTime;
@end
@implementation RoomCEFDownloadItem
@end

@implementation RoomCEFDownloadControl {
  CefRefPtr<CefDownloadItemCallback> _callback;
}
- (instancetype)initWithCallback:(CefRefPtr<CefDownloadItemCallback>)callback {
  if ((self = [super init])) {
    _callback = callback;
  }
  return self;
}
- (void)pause {
  if (_callback) _callback->Pause();
}
- (void)resume {
  if (_callback) _callback->Resume();
}
- (void)cancel {
  if (_callback) _callback->Cancel();
}
@end

@interface RoomCEFSecurityStatus ()
@property(nonatomic) BOOL secureConnection;
@property(nonatomic) BOOL certificateError;
@property(nonatomic) BOOL mixedContent;
@end
@implementation RoomCEFSecurityStatus
@end

namespace {

RoomCEFDownloadItem* ToDownloadItem(CefRefPtr<CefDownloadItem> item) {
  RoomCEFDownloadItem* result = [[RoomCEFDownloadItem alloc] init];
  result.identifier = item->GetId();
  result.url = ToNS(item->GetURL());
  result.suggestedFileName = ToNS(item->GetSuggestedFileName());
  result.fullPath = ToNSOrNil(item->GetFullPath());
  result.mimeType = ToNSOrNil(item->GetMimeType());
  result.receivedBytes = item->GetReceivedBytes();
  result.totalBytes = item->GetTotalBytes() > 0 ? item->GetTotalBytes() : -1;
  result.currentSpeed = item->GetCurrentSpeed();
  result.inProgress = item->IsInProgress();
  result.complete = item->IsComplete();
  result.canceled = item->IsCanceled();
  result.interrupted = item->IsInterrupted();
  result.paused = item->IsPaused();
  CefBaseTime start = item->GetStartTime();
  if (start.val != 0) {
    // CefBaseTime counts microseconds since 1601-01-01 (Windows epoch).
    const double unix = (static_cast<double>(start.val) - 11644473600000000.0) / 1e6;
    result.startTime = [NSDate dateWithTimeIntervalSince1970:unix];
  }
  return result;
}

// Windows virtual-key codes for letters and digits equal their ASCII values.
NSString* KeyEquivalentForWindowsKeyCode(int code) {
  if ((code >= 'A' && code <= 'Z') || (code >= '0' && code <= '9')) {
    return [[NSString stringWithFormat:@"%c", static_cast<char>(code)] lowercaseString];
  }
  return @"";
}

NSArray<RoomCEFMenuItem*>* ToMenuItems(CefRefPtr<CefMenuModel> model) {
  NSMutableArray<RoomCEFMenuItem*>* items = [NSMutableArray array];
  for (size_t i = 0; i < model->GetCount(); ++i) {
    if (!model->IsVisibleAt(i)) {
      continue;
    }
    RoomCEFMenuItem* item = [[RoomCEFMenuItem alloc] init];
    item.commandID = model->GetCommandIdAt(i);
    item.title = ToNS(model->GetLabelAt(i));
    item.enabled = model->IsEnabledAt(i);
    item.checked = model->IsCheckedAt(i);
    item.groupID = model->GetGroupIdAt(i);
    item.submenu = @[];
    item.keyEquivalent = @"";
    switch (model->GetTypeAt(i)) {
      case MENUITEMTYPE_CHECK:
        item.type = RoomCEFMenuItemTypeCheck;
        break;
      case MENUITEMTYPE_RADIO:
        item.type = RoomCEFMenuItemTypeRadio;
        break;
      case MENUITEMTYPE_SEPARATOR:
        item.type = RoomCEFMenuItemTypeSeparator;
        break;
      case MENUITEMTYPE_SUBMENU:
        item.type = RoomCEFMenuItemTypeSubmenu;
        if (auto submenu = model->GetSubMenuAt(i)) {
          item.submenu = ToMenuItems(submenu);
        }
        break;
      default:
        item.type = RoomCEFMenuItemTypeCommand;
        break;
    }
    int key = 0;
    bool shift = false, ctrl = false, alt = false;
    if (model->GetAcceleratorAt(i, key, shift, ctrl, alt)) {
      item.keyEquivalent = KeyEquivalentForWindowsKeyCode(key);
      // On macOS CEF reports the command key as "ctrl".
      NSEventModifierFlags flags = 0;
      if (ctrl) flags |= NSEventModifierFlagCommand;
      if (shift) flags |= NSEventModifierFlagShift;
      if (alt) flags |= NSEventModifierFlagOption;
      item.keyEquivalentModifiers = flags;
    }
    [items addObject:item];
  }
  return items;
}

}  // namespace

// MARK: - Browser

@class RoomCEFContainerView;

@interface RoomCEFRequestContext ()
- (CefRefPtr<CefRequestContext>)cefContext;
@end

@interface RoomCEFBrowser ()
- (instancetype)initPopupOf:(RoomCEFBrowser*)opener
                  targetURL:(nullable NSString*)url
                disposition:(RoomCEFDisposition)disposition
                userGesture:(BOOL)userGesture;
- (void)attachBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)hostWillClose;
- (void)detachBrowser;
- (void)registerPendingPopup:(RoomCEFBrowser*)popup id:(int)popupID;
- (void)abortPendingPopup:(int)popupID;
- (CefRefPtr<CefClient>)client;
- (void)devToolsResult:(int)messageID success:(BOOL)success data:(NSData*)data;
@end

/// The parent view passed to `SetAsChild`; it is what the host places.
@interface RoomCEFContainerView : NSView
@end

@implementation RoomCEFContainerView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
  }
  return self;
}
- (BOOL)mouseDownCanMoveWindow {
  return NO;
}
// Leaving the parking window means the host is showing the page.
- (void)viewDidMoveToSuperview {
  [super viewDidMoveToSuperview];
  if (self.superview && self.superview != ParkingWindow().contentView) {
    self.hidden = NO;
  }
}
@end

namespace {

class DevToolsObserver : public CefDevToolsMessageObserver {
 public:
  explicit DevToolsObserver(RoomCEFBrowser* owner) : owner_(owner) {}

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                              int message_id,
                              bool success,
                              const void* result,
                              size_t result_size) override {
    NSData* data = [NSData dataWithBytes:result length:result_size];
    [owner_ devToolsResult:message_id success:success data:data];
  }

 private:
  __weak RoomCEFBrowser* owner_;
  IMPLEMENT_REFCOUNTING(DevToolsObserver);
};

class FaviconCallback : public CefDownloadImageCallback {
 public:
  explicit FaviconCallback(void (^completion)(NSImage* _Nullable)) : completion_(completion) {}

  void OnDownloadImageFinished(const CefString& image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    NSImage* result = nil;
    if (image && !image->IsEmpty()) {
      result = [[NSImage alloc] initWithSize:NSMakeSize(image->GetWidth(), image->GetHeight())];
      for (float scale : {1.0f, 2.0f}) {
        int width = 0, height = 0;
        if (auto png = image->GetAsPNG(scale, true, width, height)) {
          NSData* data = [NSData dataWithBytes:png->GetRawData() length:png->GetSize()];
          if (NSBitmapImageRep* rep = [NSBitmapImageRep imageRepWithData:data]) {
            rep.size = result.size;
            [result addRepresentation:rep];
          }
        }
      }
      if (result.representations.count == 0) result = nil;
    }
    completion_(result);
  }

 private:
  void (^completion_)(NSImage* _Nullable);
  IMPLEMENT_REFCOUNTING(FaviconCallback);
};

// The client for CEF's own DevTools window; no handlers needed.
class DevToolsClient : public CefClient {
 private:
  IMPLEMENT_REFCOUNTING(DevToolsClient);
};

class RoomCEFClient : public CefClient,
                      public CefAudioHandler,
                      public CefContextMenuHandler,
                      public CefDialogHandler,
                      public CefDisplayHandler,
                      public CefDownloadHandler,
                      public CefFindHandler,
                      public CefFocusHandler,
                      public CefJSDialogHandler,
                      public CefKeyboardHandler,
                      public CefLifeSpanHandler,
                      public CefLoadHandler,
                      public CefPermissionHandler,
                      public CefRequestHandler {
 public:
  explicit RoomCEFClient(RoomCEFBrowser* owner) : owner_(owner) {}

  CefRefPtr<CefAudioHandler> GetAudioHandler() override { return this; }
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
  CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
  CefRefPtr<CefFocusHandler> GetFocusHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

  // MARK: CefLifeSpanHandler

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override {
    RoomCEFBrowser* owner = owner_;
    id<RoomCEFBrowserDelegate> delegate = owner.delegate;
    NSString* url = ToNSOrNil(target_url);
    const RoomCEFDisposition disposition = ToDisposition(target_disposition);
    if (!owner ||
        ![delegate respondsToSelector:@selector(browser:shouldOpenPopupWithURL:disposition:userGesture:)] ||
        ![delegate browser:owner shouldOpenPopupWithURL:url disposition:disposition userGesture:user_gesture]) {
      return true;  // blocked
    }
    RoomCEFBrowser* popup = [[RoomCEFBrowser alloc] initPopupOf:owner
                                                      targetURL:url
                                                    disposition:disposition
                                                    userGesture:user_gesture];
    [owner registerPendingPopup:popup id:popup_id];
    const NSRect bounds = popup.containerView.bounds;
    windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(popup.containerView),
                          CefRect(0, 0, static_cast<int>(bounds.size.width), static_cast<int>(bounds.size.height)));
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    client = [popup client];
    return false;
  }

  void OnBeforePopupAborted(CefRefPtr<CefBrowser> browser, int popup_id) override {
    [owner_ abortPendingPopup:popup_id];
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    [owner_ attachBrowser:browser];
  }

  // Returning false would make CEF send performClose: to the NSWindow that
  // hosts the view (browser_platform_delegate_native_mac.mm, CloseHostWindow),
  // closing the whole Room window. Remove our view instead; its dealloc
  // destroys the browser and OnBeforeClose follows.
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    [owner_ hostWillClose];
    return true;
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    [owner_ detachBrowser];
  }

  // MARK: CefDisplayHandler

  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (!frame->IsMain()) return;
    if ([delegate() respondsToSelector:@selector(browser:didChangeAddress:)]) {
      [delegate() browser:owner_ didChangeAddress:ToNS(url)];
    }
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override {
    if ([delegate() respondsToSelector:@selector(browser:didChangeTitle:)]) {
      [delegate() browser:owner_ didChangeTitle:ToNSOrNil(title)];
    }
  }

  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& icon_urls) override {
    if (![delegate() respondsToSelector:@selector(browser:didChangeFaviconURLs:)]) return;
    NSMutableArray<NSString*>* urls = [NSMutableArray array];
    for (const auto& url : icon_urls) [urls addObject:ToNS(url)];
    [delegate() browser:owner_ didChangeFaviconURLs:urls];
  }

  void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override {
    if ([delegate() respondsToSelector:@selector(browser:didChangeFullscreen:)]) {
      [delegate() browser:owner_ didChangeFullscreen:fullscreen];
    }
  }

  void OnStatusMessage(CefRefPtr<CefBrowser> browser, const CefString& value) override {
    if ([delegate() respondsToSelector:@selector(browser:didChangeStatusMessage:)]) {
      [delegate() browser:owner_ didChangeStatusMessage:ToNSOrNil(value)];
    }
  }

  void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override {
    if ([delegate() respondsToSelector:@selector(browser:didChangeLoadingProgress:)]) {
      [delegate() browser:owner_ didChangeLoadingProgress:progress];
    }
  }

  bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                        cef_log_severity_t level,
                        const CefString& message,
                        const CefString& source,
                        int line) override {
    if ([delegate() respondsToSelector:@selector(browser:didChangeConsoleMessage:source:line:)]) {
      [delegate() browser:owner_ didChangeConsoleMessage:ToNS(message) source:ToNS(source) line:line];
    }
    return false;
  }

  // MARK: CefLoadHandler

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack, bool canGoForward) override {
    if ([delegate() respondsToSelector:@selector(browser:loadingStateChanged:canGoBack:canGoForward:)]) {
      [delegate() browser:owner_ loadingStateChanged:isLoading canGoBack:canGoBack canGoForward:canGoForward];
    }
  }

  void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) override {
    if (frame->IsMain() && [delegate() respondsToSelector:@selector(browser:didCommitMainFrameNavigation:transition:)]) {
      [delegate() browser:owner_ didCommitMainFrameNavigation:ToNS(frame->GetURL()) transition:ToTransition(transition_type)];
    }
  }

  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) override {
    if (frame->IsMain() && [delegate() respondsToSelector:@selector(browser:didFinishMainFrameLoad:)]) {
      [delegate() browser:owner_ didFinishMainFrameLoad:httpStatusCode];
    }
  }

  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override {
    if (frame->IsMain() && [delegate() respondsToSelector:@selector(browser:didFailMainFrameLoad:errorText:url:)]) {
      [delegate() browser:owner_ didFailMainFrameLoad:errorCode errorText:ToNS(errorText) url:ToNS(failedUrl)];
    }
  }

  // MARK: CefKeyboardHandler

  bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                     const CefKeyEvent& event,
                     CefEventHandle os_event,
                     bool* is_keyboard_shortcut) override {
    NSEvent* ns_event = CAST_CEF_EVENT_HANDLE_TO_NSEVENT(os_event);
    if (event.type != KEYEVENT_RAWKEYDOWN || ns_event.type != NSEventTypeKeyDown) return false;
    if ([delegate() respondsToSelector:@selector(browser:isReservedKeyEvent:)]) {
      return [delegate() browser:owner_ isReservedKeyEvent:ns_event];
    }
    return false;
  }

  bool OnKeyEvent(CefRefPtr<CefBrowser> browser, const CefKeyEvent& event, CefEventHandle os_event) override {
    NSEvent* ns_event = CAST_CEF_EVENT_HANDLE_TO_NSEVENT(os_event);
    if (event.type != KEYEVENT_RAWKEYDOWN || ns_event.type != NSEventTypeKeyDown) return false;
    if ([delegate() respondsToSelector:@selector(browser:handleUnhandledKeyEvent:)]) {
      // Handled or not, the delegate already offered it to the main menu;
      // returning true keeps CEF from offering it a second time.
      [delegate() browser:owner_ handleUnhandledKeyEvent:ns_event];
      return true;
    }
    return false;
  }

  // MARK: CefRequestHandler

  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                      CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request,
                      bool user_gesture,
                      bool is_redirect) override {
    if (!frame->IsMain() || ![delegate() respondsToSelector:@selector(browser:shouldCancelNavigation:)]) return false;
    RoomCEFNavigationRequest* navigation = [[RoomCEFNavigationRequest alloc] init];
    navigation.url = ToNS(request->GetURL());
    navigation.referrer = ToNSOrNil(request->GetReferrerURL());
    navigation.transition = ToTransition(request->GetTransitionType());
    navigation.userGesture = user_gesture;
    navigation.redirect = is_redirect;
    return [delegate() browser:owner_ shouldCancelNavigation:navigation];
  }

  bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        const CefString& target_url,
                        WindowOpenDisposition target_disposition,
                        bool user_gesture) override {
    if (![delegate() respondsToSelector:@selector(browser:shouldCancelOpenURL:disposition:userGesture:)]) return false;
    return [delegate() browser:owner_
           shouldCancelOpenURL:ToNS(target_url)
                   disposition:ToDisposition(target_disposition)
                   userGesture:user_gesture];
  }

  // Runs on the IO thread: hop to main; CefAuthCallback is thread-safe.
  bool GetAuthCredentials(CefRefPtr<CefBrowser> browser,
                          const CefString& origin_url,
                          bool isProxy,
                          const CefString& host,
                          int port,
                          const CefString& realm,
                          const CefString& scheme,
                          CefRefPtr<CefAuthCallback> callback) override {
    NSString* origin = ToNS(origin_url);
    NSString* realm_ns = ToNSOrNil(realm);
    NSString* scheme_ns = ToNS(scheme);
    CefRefPtr<RoomCEFClient> self_ref(this);
    dispatch_async(dispatch_get_main_queue(), ^{
      id<RoomCEFBrowserDelegate> delegate = self_ref->delegate();
      if (![delegate respondsToSelector:@selector(browser:authChallengeForOrigin:isProxy:realm:scheme:completion:)]) {
        callback->Cancel();
        return;
      }
      [delegate browser:self_ref->owner_
          authChallengeForOrigin:origin
                         isProxy:isProxy
                           realm:realm_ns
                          scheme:scheme_ns
                      completion:^(NSString* user, NSString* password) {
                        if (user) {
                          callback->Continue(ToCef(user), ToCef(password ?: @""));
                        } else {
                          callback->Cancel();
                        }
                      }];
    });
    return true;
  }

  bool OnCertificateError(CefRefPtr<CefBrowser> browser,
                          cef_errorcode_t cert_error,
                          const CefString& request_url,
                          CefRefPtr<CefSSLInfo> ssl_info,
                          CefRefPtr<CefCallback> callback) override {
    if (![delegate() respondsToSelector:@selector(browser:certificateError:url:certificates:completion:)]) return false;
    NSMutableArray<NSData*>* chain = [NSMutableArray array];
    if (ssl_info) {
      if (auto certificate = ssl_info->GetX509Certificate()) {
        CefX509Certificate::IssuerChainBinaryList issuers;
        if (auto der = certificate->GetDEREncoded()) {
          [chain addObject:[NSData dataWithBytes:der->GetRawData() length:der->GetSize()]];
        }
        certificate->GetDEREncodedIssuerChain(issuers);
        for (const auto& issuer : issuers) {
          [chain addObject:[NSData dataWithBytes:issuer->GetRawData() length:issuer->GetSize()]];
        }
      }
    }
    [delegate() browser:owner_
        certificateError:cert_error
                     url:ToNS(request_url)
             certificates:chain
              completion:^(BOOL proceed) {
                if (proceed) {
                  callback->Continue();
                } else {
                  callback->Cancel();
                }
              }];
    return true;
  }

  void OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                 TerminationStatus status,
                                 int error_code,
                                 const CefString& error_string) override {
    if ([delegate() respondsToSelector:@selector(browser:renderProcessTerminated:)]) {
      [delegate() browser:owner_ renderProcessTerminated:ToTerminationStatus(status)];
    }
  }

  // MARK: CefPermissionHandler

  bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser,
                                      CefRefPtr<CefFrame> frame,
                                      const CefString& requesting_origin,
                                      uint32_t requested_permissions,
                                      CefRefPtr<CefMediaAccessCallback> callback) override {
    if (![delegate() respondsToSelector:@selector(browser:mediaAccessForOrigin:permissions:completion:)]) return false;
    [delegate() browser:owner_
        mediaAccessForOrigin:ToNS(requesting_origin)
                 permissions:requested_permissions
                  completion:^(RoomCEFMediaAccess allowed) {
                    if (allowed) {
                      callback->Continue(allowed);
                    } else {
                      callback->Cancel();
                    }
                  }];
    return true;
  }

  bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser,
                              uint64_t prompt_id,
                              const CefString& requesting_origin,
                              uint32_t requested_permissions,
                              CefRefPtr<CefPermissionPromptCallback> callback) override {
    if (![delegate() respondsToSelector:@selector(browser:permissionPrompt:origin:permissions:completion:)]) return false;
    [delegate() browser:owner_
        permissionPrompt:prompt_id
                  origin:ToNS(requesting_origin)
             permissions:requested_permissions
              completion:^(RoomCEFPermissionResult result) {
                switch (result) {
                  case RoomCEFPermissionResultAccept:
                    callback->Continue(CEF_PERMISSION_RESULT_ACCEPT);
                    break;
                  case RoomCEFPermissionResultDeny:
                    callback->Continue(CEF_PERMISSION_RESULT_DENY);
                    break;
                  case RoomCEFPermissionResultDismiss:
                    callback->Continue(CEF_PERMISSION_RESULT_DISMISS);
                    break;
                  case RoomCEFPermissionResultIgnore:
                    callback->Continue(CEF_PERMISSION_RESULT_IGNORE);
                    break;
                }
              }];
    return true;
  }

  void OnDismissPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                 uint64_t prompt_id,
                                 cef_permission_request_result_t result) override {
    if ([delegate() respondsToSelector:@selector(browser:dismissPermissionPrompt:)]) {
      [delegate() browser:owner_ dismissPermissionPrompt:prompt_id];
    }
  }

  // MARK: CefJSDialogHandler

  bool OnJSDialog(CefRefPtr<CefBrowser> browser,
                  const CefString& origin_url,
                  JSDialogType dialog_type,
                  const CefString& message_text,
                  const CefString& default_prompt_text,
                  CefRefPtr<CefJSDialogCallback> callback,
                  bool& suppress_message) override {
    if (![delegate() respondsToSelector:@selector(browser:runJSDialog:message:defaultText:origin:completion:)]) {
      return false;
    }
    RoomCEFJSDialogType type = RoomCEFJSDialogTypeAlert;
    if (dialog_type == JSDIALOGTYPE_CONFIRM) type = RoomCEFJSDialogTypeConfirm;
    if (dialog_type == JSDIALOGTYPE_PROMPT) type = RoomCEFJSDialogTypePrompt;
    [delegate() browser:owner_
            runJSDialog:type
                message:ToNS(message_text)
            defaultText:ToNS(default_prompt_text)
                 origin:ToNSOrNil(origin_url)
             completion:^(BOOL success, NSString* input) {
               callback->Continue(success, ToCef(input ?: @""));
             }];
    return true;
  }

  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser,
                            const CefString& message_text,
                            bool is_reload,
                            CefRefPtr<CefJSDialogCallback> callback) override {
    if (![delegate() respondsToSelector:@selector(browser:runBeforeUnloadDialogIsReload:completion:)]) return false;
    [delegate() browser:owner_
        runBeforeUnloadDialogIsReload:is_reload
                           completion:^(BOOL leave) {
                             callback->Continue(leave, CefString());
                           }];
    return true;
  }

  void OnResetDialogState(CefRefPtr<CefBrowser> browser) override {
    if ([delegate() respondsToSelector:@selector(browserDidResetDialogState:)]) {
      [delegate() browserDidResetDialogState:owner_];
    }
  }

  // MARK: CefContextMenuHandler

  bool RunContextMenu(CefRefPtr<CefBrowser> browser,
                      CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefContextMenuParams> params,
                      CefRefPtr<CefMenuModel> model,
                      CefRefPtr<CefRunContextMenuCallback> callback) override {
    if (![delegate() respondsToSelector:@selector(browser:runContextMenu:params:completion:)]) return false;
    RoomCEFContextMenuParams* info = [[RoomCEFContextMenuParams alloc] init];
    info.location = NSMakePoint(params->GetXCoord(), params->GetYCoord());
    info.pageURL = ToNSOrNil(params->GetPageUrl());
    info.frameURL = ToNSOrNil(params->GetFrameUrl());
    info.linkURL = ToNSOrNil(params->GetLinkUrl());
    info.sourceURL = ToNSOrNil(params->GetSourceUrl());
    info.mediaType = ToMediaType(params->GetMediaType());
    info.selectionText = ToNSOrNil(params->GetSelectionText());
    info.editable = params->IsEditable();
    info.misspelledWord = ToNSOrNil(params->GetMisspelledWord());
    std::vector<CefString> suggestions;
    params->GetDictionarySuggestions(suggestions);
    NSMutableArray<NSString*>* words = [NSMutableArray array];
    for (const auto& word : suggestions) [words addObject:ToNS(word)];
    info.dictionarySuggestions = words;
    return [delegate() browser:owner_
                runContextMenu:ToMenuItems(model)
                        params:info
                    completion:^(NSInteger commandID) {
                      if (commandID >= 0) {
                        callback->Continue(static_cast<int>(commandID), EVENTFLAG_NONE);
                      } else {
                        callback->Cancel();
                      }
                    }];
  }

  // MARK: CefDialogHandler

  bool OnFileDialog(CefRefPtr<CefBrowser> browser,
                    FileDialogMode mode,
                    const CefString& title,
                    const CefString& default_file_path,
                    const std::vector<CefString>& accept_filters,
                    const std::vector<CefString>& accept_extensions,
                    const std::vector<CefString>& accept_descriptions,
                    CefRefPtr<CefFileDialogCallback> callback) override {
    if (![delegate() respondsToSelector:@selector(browser:runFileDialog:title:defaultPath:acceptTypes:completion:)]) {
      return false;
    }
    RoomCEFFileDialogMode dialog_mode = RoomCEFFileDialogModeOpen;
    if (mode == FILE_DIALOG_OPEN_MULTIPLE) dialog_mode = RoomCEFFileDialogModeOpenMultiple;
    if (mode == FILE_DIALOG_OPEN_FOLDER) dialog_mode = RoomCEFFileDialogModeOpenFolder;
    if (mode == FILE_DIALOG_SAVE) dialog_mode = RoomCEFFileDialogModeSave;
    NSMutableArray<NSString*>* types = [NSMutableArray array];
    for (const auto& filter : accept_filters) [types addObject:ToNS(filter)];
    return [delegate() browser:owner_
                 runFileDialog:dialog_mode
                         title:ToNSOrNil(title)
                   defaultPath:ToNSOrNil(default_file_path)
                   acceptTypes:types
                    completion:^(NSArray<NSString*>* paths) {
                      if (paths) {
                        std::vector<CefString> files;
                        for (NSString* path in paths) files.push_back(ToCef(path));
                        callback->Continue(files);
                      } else {
                        callback->Cancel();
                      }
                    }];
  }

  // MARK: CefFindHandler

  void OnFindResult(CefRefPtr<CefBrowser> browser,
                    int identifier,
                    int count,
                    const CefRect& selectionRect,
                    int activeMatchOrdinal,
                    bool finalUpdate) override {
    if ([delegate() respondsToSelector:@selector(browser:findResultCount:activeMatch:finalUpdate:)]) {
      [delegate() browser:owner_ findResultCount:count activeMatch:activeMatchOrdinal finalUpdate:finalUpdate];
    }
  }

  // MARK: CefFocusHandler

  void OnGotFocus(CefRefPtr<CefBrowser> browser) override {
    if ([delegate() respondsToSelector:@selector(browserDidGainFocus:)]) {
      [delegate() browserDidGainFocus:owner_];
    }
  }

  // MARK: CefDownloadHandler

  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString& suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override {
    if (![delegate() respondsToSelector:@selector(browser:willBeginDownload:suggestedName:completion:)]) return false;
    [delegate() browser:owner_
        willBeginDownload:ToDownloadItem(download_item)
            suggestedName:ToNS(suggested_name)
               completion:^(NSString* path) {
                 // Not continuing cancels the download (Alloy).
                 if (path) callback->Continue(ToCef(path), false);
               }];
    return true;
  }

  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> callback) override {
    if ([delegate() respondsToSelector:@selector(browser:didUpdateDownload:control:)]) {
      [delegate() browser:owner_
          didUpdateDownload:ToDownloadItem(download_item)
                    control:[[RoomCEFDownloadControl alloc] initWithCallback:callback]];
    }
  }

  // MARK: CefAudioHandler

  // Returning false skips audio capture (sound keeps playing) but still tells
  // us the page became audible; CEF calls this per new audio stream.
  bool GetAudioParameters(CefRefPtr<CefBrowser> browser, CefAudioParameters& params) override {
    if ([delegate() respondsToSelector:@selector(browserDidBecomeAudible:)]) {
      [delegate() browserDidBecomeAudible:owner_];
    }
    return false;
  }
  void OnAudioStreamStarted(CefRefPtr<CefBrowser>, const CefAudioParameters&, int) override {}
  void OnAudioStreamPacket(CefRefPtr<CefBrowser>, const float**, int, int64_t) override {}
  void OnAudioStreamStopped(CefRefPtr<CefBrowser>) override {}
  void OnAudioStreamError(CefRefPtr<CefBrowser>, const CefString&) override {}

 private:
  id<RoomCEFBrowserDelegate> delegate() const { return owner_.delegate; }

  __weak RoomCEFBrowser* owner_;
  IMPLEMENT_REFCOUNTING(RoomCEFClient);
};

NSMutableArray<RoomCEFBrowser*>* LiveBrowsers() {
  static NSMutableArray<RoomCEFBrowser*>* browsers = [NSMutableArray array];
  return browsers;
}

}  // namespace

@implementation RoomCEFBrowser {
  CefRefPtr<CefBrowser> _browser;
  CefRefPtr<RoomCEFClient> _client;
  CefRefPtr<CefRegistration> _devToolsRegistration;
  std::map<int, void (^)(BOOL, NSData*)> _devToolsCompletions;
  int _nextDevToolsMessageID;
  NSMutableDictionary<NSNumber*, RoomCEFBrowser*>* _pendingPopups;
  // Popups only, until OnAfterCreated.
  __weak RoomCEFBrowser* _opener;
  NSString* _popupURL;
  RoomCEFDisposition _popupDisposition;
  BOOL _popupUserGesture;
}

+ (NSArray<RoomCEFBrowser*>*)liveBrowsers {
  return [LiveBrowsers() copy];
}

- (instancetype)initContainerHidden:(BOOL)hidden {
  if ((self = [super init])) {
    NSView* parking = ParkingWindow().contentView;
    _containerView = [[RoomCEFContainerView alloc] initWithFrame:parking.bounds];
    _containerView.hidden = hidden;
    [parking addSubview:_containerView];
    _client = new RoomCEFClient(self);
    _pendingPopups = [NSMutableDictionary dictionary];
  }
  return self;
}

- (instancetype)initWithRequestContext:(RoomCEFRequestContext*)requestContext
                                hidden:(BOOL)hidden
                              delegate:(id<RoomCEFBrowserDelegate>)delegate {
  if ((self = [self initContainerHidden:hidden])) {
    _delegate = delegate;
    CefWindowInfo windowInfo;
    const NSRect bounds = _containerView.bounds;
    windowInfo.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(_containerView),
                          CefRect(0, 0, static_cast<int>(bounds.size.width), static_cast<int>(bounds.size.height)));
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
    CefBrowserSettings settings;
    CefRefPtr<CefRequestContext> context = requestContext ? [requestContext cefContext] : nullptr;
    CefRefPtr<CefBrowser> browser =
        CefBrowserHost::CreateBrowserSync(windowInfo, _client.get(), CefString(), settings, nullptr, context);
    if (!browser) {
      [_containerView removeFromSuperview];
      return nil;
    }
    // OnAfterCreated normally ran inside CreateBrowserSync already.
    if (!_browser) [self attachBrowser:browser];
  }
  return self;
}

- (instancetype)initPopupOf:(RoomCEFBrowser*)opener
                  targetURL:(NSString*)url
                disposition:(RoomCEFDisposition)disposition
                userGesture:(BOOL)userGesture {
  if ((self = [self initContainerHidden:YES])) {
    _opener = opener;
    _popupURL = [url copy];
    _popupDisposition = disposition;
    _popupUserGesture = userGesture;
  }
  return self;
}

- (CefRefPtr<CefClient>)client {
  return _client.get();
}

- (void)registerPendingPopup:(RoomCEFBrowser*)popup id:(int)popupID {
  _pendingPopups[@(popupID)] = popup;
}

- (void)abortPendingPopup:(int)popupID {
  RoomCEFBrowser* popup = _pendingPopups[@(popupID)];
  [popup.containerView removeFromSuperview];
  [_pendingPopups removeObjectForKey:@(popupID)];
}

- (void)attachBrowser:(CefRefPtr<CefBrowser>)browser {
  if (_browser) return;
  _browser = browser;
  [LiveBrowsers() addObject:self];
  RoomCEFBrowser* opener = _opener;
  if (opener) {
    _opener = nil;
    // The opener's pending entry is the only strong reference so far; the
    // delegate below takes over (or closes the popup).
    for (NSNumber* key in [opener->_pendingPopups allKeysForObject:self]) {
      [opener->_pendingPopups removeObjectForKey:key];
    }
    id<RoomCEFBrowserDelegate> delegate = opener.delegate;
    if ([delegate respondsToSelector:@selector(browser:didCreatePopup:targetURL:disposition:userGesture:)]) {
      [delegate browser:opener
          didCreatePopup:self
               targetURL:_popupURL
             disposition:_popupDisposition
             userGesture:_popupUserGesture];
    } else {
      [self close:YES];
    }
  }
  if ([_delegate respondsToSelector:@selector(browserDidCreate:)]) {
    [_delegate browserDidCreate:self];
  }
}

- (void)hostWillClose {
  if ([_delegate respondsToSelector:@selector(browserWillClose:)]) {
    [_delegate browserWillClose:self];
  }
  NSView* view = self.browserView;
  dispatch_async(dispatch_get_main_queue(), ^{
    [view removeFromSuperview];
  });
}

- (void)detachBrowser {
  _devToolsRegistration = nullptr;
  for (auto& [messageID, completion] : _devToolsCompletions) {
    completion(NO, [NSData data]);
  }
  _devToolsCompletions.clear();
  _browser = nullptr;
  // Keep self alive through the delegate call even if this was the last reference.
  RoomCEFBrowser* strongSelf = self;
  [LiveBrowsers() removeObject:strongSelf];
  [_containerView removeFromSuperview];
  if ([_delegate respondsToSelector:@selector(browserDidClose:)]) {
    [_delegate browserDidClose:strongSelf];
  }
  [NSNotificationCenter.defaultCenter postNotificationName:RoomCEFBrowserDidCloseNotification object:strongSelf];
}

- (NSView*)browserView {
  if (!_browser) return nil;
  return CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(_browser->GetHost()->GetWindowHandle());
}

- (NSInteger)identifier {
  return _browser ? _browser->GetIdentifier() : 0;
}

- (BOOL)isPopup {
  return _browser ? _browser->IsPopup() : NO;
}

- (BOOL)isAlive {
  return _browser != nullptr;
}

- (void)loadURL:(NSString*)url {
  if (_browser) _browser->GetMainFrame()->LoadURL(ToCef(url));
}

- (void)goBack {
  if (_browser) _browser->GoBack();
}

- (void)goForward {
  if (_browser) _browser->GoForward();
}

- (void)reload {
  if (_browser) _browser->Reload();
}

- (void)reloadIgnoringCache {
  if (_browser) _browser->ReloadIgnoreCache();
}

- (void)stopLoad {
  if (_browser) _browser->StopLoad();
}

- (BOOL)isAudioMuted {
  return _browser ? _browser->GetHost()->IsAudioMuted() : NO;
}

- (void)setAudioMuted:(BOOL)muted {
  if (_browser) _browser->GetHost()->SetAudioMuted(muted);
}

- (double)zoomLevel {
  return _browser ? _browser->GetHost()->GetZoomLevel() : 0;
}

- (void)setZoomLevel:(double)level {
  if (_browser) _browser->GetHost()->SetZoomLevel(level);
}

- (void)find:(NSString*)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
  if (_browser) _browser->GetHost()->Find(ToCef(text), forward, matchCase, findNext);
}

- (void)stopFinding:(BOOL)clearSelection {
  if (_browser) _browser->GetHost()->StopFinding(clearSelection);
}

- (void)close:(BOOL)force {
  if (_browser) _browser->GetHost()->CloseBrowser(force);
}

- (BOOL)tryClose {
  return _browser ? _browser->GetHost()->TryCloseBrowser() : YES;
}

- (void)setFocus:(BOOL)focus {
  if (_browser) _browser->GetHost()->SetFocus(focus);
}

- (void)printPage {
  if (_browser) _browser->GetHost()->Print();
}

- (void)exitFullscreen {
  if (_browser && _browser->GetHost()->IsFullscreen()) _browser->GetHost()->ExitFullscreen(true);
}

- (RoomCEFSecurityStatus*)visibleSecurityStatus {
  if (!_browser) return nil;
  CefRefPtr<CefNavigationEntry> entry = _browser->GetHost()->GetVisibleNavigationEntry();
  if (!entry) return nil;
  CefRefPtr<CefSSLStatus> ssl = entry->GetSSLStatus();
  if (!ssl) return nil;
  RoomCEFSecurityStatus* status = [[RoomCEFSecurityStatus alloc] init];
  status.secureConnection = ssl->IsSecureConnection();
  // Chromium's CERT_STATUS_ALL_ERRORS minus the two revocation-check "minor" errors.
  const uint32_t errors = 0xFF00FFFF & ~(CERT_STATUS_NO_REVOCATION_MECHANISM | CERT_STATUS_UNABLE_TO_CHECK_REVOCATION);
  status.certificateError = (static_cast<uint32_t>(ssl->GetCertStatus()) & errors) != 0;
  status.mixedContent = ssl->GetContentStatus() != SSL_CONTENT_NORMAL_CONTENT;
  return status;
}

- (void)showDevToolsWindowInspectingElementAt:(NSPoint)point {
  if (!_browser) return;
  CefWindowInfo windowInfo;  // no parent: Chrome style, top-level window
  CefBrowserSettings settings;
  _browser->GetHost()->ShowDevTools(windowInfo, new DevToolsClient(), settings,
                                    CefPoint(static_cast<int>(point.x), static_cast<int>(point.y)));
}

- (void)closeDevTools {
  if (_browser) _browser->GetHost()->CloseDevTools();
}

- (BOOL)hasDevTools {
  return _browser ? _browser->GetHost()->HasDevTools() : NO;
}

- (void)executeDevToolsMethod:(NSString*)method
                   paramsJSON:(NSString*)params
                   completion:(void (^)(BOOL, NSData*))completion {
  if (!_browser) {
    completion(NO, [NSData data]);
    return;
  }
  if (!_devToolsRegistration) {
    _devToolsRegistration = _browser->GetHost()->AddDevToolsMessageObserver(new DevToolsObserver(self));
  }
  CefRefPtr<CefDictionaryValue> dictionary;
  if (params.length) {
    CefRefPtr<CefValue> value = CefParseJSON(ToCef(params), JSON_PARSER_RFC);
    if (!value || value->GetType() != VTYPE_DICTIONARY) {
      completion(NO, [@"{\"message\":\"params is not a JSON object\"}" dataUsingEncoding:NSUTF8StringEncoding]);
      return;
    }
    dictionary = value->GetDictionary();
  }
  // Our own id, registered before sending: CEF may deliver the result
  // synchronously inside ExecuteDevToolsMethod (seen for Target.getTargetInfo).
  const int messageID = ++_nextDevToolsMessageID;
  _devToolsCompletions[messageID] = completion;
  if (_browser->GetHost()->ExecuteDevToolsMethod(messageID, ToCef(method), dictionary) == 0) {
    [self devToolsResult:messageID
                 success:NO
                    data:[@"{\"message\":\"ExecuteDevToolsMethod failed\"}" dataUsingEncoding:NSUTF8StringEncoding]];
  }
}

- (void)devToolsResult:(int)messageID success:(BOOL)success data:(NSData*)data {
  auto it = _devToolsCompletions.find(messageID);
  if (it == _devToolsCompletions.end()) return;
  auto completion = it->second;
  _devToolsCompletions.erase(it);
  completion(success, data);
}

- (void)downloadFavicon:(NSString*)url maxSize:(NSInteger)maxSize completion:(void (^)(NSImage*))completion {
  if (!_browser) {
    completion(nil);
    return;
  }
  _browser->GetHost()->DownloadImage(ToCef(url), true, static_cast<uint32_t>(maxSize), false,
                                     new FaviconCallback(completion));
}

@end

// MARK: - Request context

namespace {

class ContextInitHandler : public CefRequestContextHandler {
 public:
  explicit ContextInitHandler(void (^completion)(CefRefPtr<CefRequestContext>)) : completion_(completion) {}

  void OnRequestContextInitialized(CefRefPtr<CefRequestContext> request_context) override {
    if (!completion_) return;
    auto completion = completion_;
    completion_ = nil;
    CefRefPtr<CefRequestContext> context = request_context;
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(context);
    });
  }

 private:
  void (^completion_)(CefRefPtr<CefRequestContext>);
  IMPLEMENT_REFCOUNTING(ContextInitHandler);
};

class Completion : public CefCompletionCallback, public CefDeleteCookiesCallback {
 public:
  explicit Completion(void (^block)(void)) : block_(block) {}
  void OnComplete() override { Run(); }
  void OnComplete(int num_deleted) override { Run(); }

 private:
  void Run() {
    auto block = block_;
    block_ = nil;
    if (block) dispatch_async(dispatch_get_main_queue(), block);
  }
  void (^block_)(void);
  IMPLEMENT_REFCOUNTING(Completion);
};

}  // namespace

@implementation RoomCEFRequestContext {
  CefRefPtr<CefRequestContext> _context;
}

- (instancetype)initWithContext:(CefRefPtr<CefRequestContext>)context {
  if ((self = [super init])) {
    _context = context;
  }
  return self;
}

- (CefRefPtr<CefRequestContext>)cefContext {
  return _context;
}

+ (instancetype)globalContext {
  return [[self alloc] initWithContext:CefRequestContext::GetGlobalContext()];
}

+ (void)createWithCachePath:(NSString*)path completion:(void (^)(RoomCEFRequestContext*))completion {
  CefRequestContextSettings settings;
  CefString(&settings.cache_path).FromString(path.fileSystemRepresentation);
  settings.persist_session_cookies = true;
  void (^done)(RoomCEFRequestContext*) = completion;
  CefRefPtr<ContextInitHandler> handler(new ContextInitHandler(^(CefRefPtr<CefRequestContext> context) {
    done([[RoomCEFRequestContext alloc] initWithContext:context]);
  }));
  CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, handler);
  if (!context) {
    dispatch_async(dispatch_get_main_queue(), ^{
      done(nil);
    });
  }
}

- (NSString*)cachePath {
  return ToNS(_context->GetCachePath());
}

- (void)deleteCookiesForURL:(NSString*)url completion:(void (^)(void))completion {
  CefRefPtr<Completion> callback(new Completion(completion));
  CefRefPtr<CefCookieManager> manager = _context->GetCookieManager(nullptr);
  if (!manager || !manager->DeleteCookies(url ? ToCef(url) : CefString(), CefString(), callback.get())) {
    callback->OnComplete(0);
  }
}

- (void)clearHTTPCacheWithCompletion:(void (^)(void))completion {
  _context->ClearHttpCache(new Completion(completion));
}

- (void)clearHTTPAuthCredentialsWithCompletion:(void (^)(void))completion {
  _context->ClearHttpAuthCredentials(new Completion(completion));
}

- (void)clearCertificateExceptionsWithCompletion:(void (^)(void))completion {
  _context->ClearCertificateExceptions(new Completion(completion));
}

static cef_content_setting_types_t ToCefContentType(RoomCEFContentSettingType type) {
  switch (type) {
    case RoomCEFContentSettingTypeGeolocation: return CEF_CONTENT_SETTING_TYPE_GEOLOCATION;
    case RoomCEFContentSettingTypeCamera: return CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_CAMERA;
    case RoomCEFContentSettingTypeMicrophone: return CEF_CONTENT_SETTING_TYPE_MEDIASTREAM_MIC;
    case RoomCEFContentSettingTypeNotifications: return CEF_CONTENT_SETTING_TYPE_NOTIFICATIONS;
    case RoomCEFContentSettingTypeClipboard: return CEF_CONTENT_SETTING_TYPE_CLIPBOARD_READ_WRITE;
    case RoomCEFContentSettingTypeSensors: return CEF_CONTENT_SETTING_TYPE_SENSORS;
    case RoomCEFContentSettingTypeMidiSysex: return CEF_CONTENT_SETTING_TYPE_MIDI_SYSEX;
    case RoomCEFContentSettingTypePopups: return CEF_CONTENT_SETTING_TYPE_POPUPS;
    case RoomCEFContentSettingTypeSound: return CEF_CONTENT_SETTING_TYPE_SOUND;
    case RoomCEFContentSettingTypeAutomaticDownloads: return CEF_CONTENT_SETTING_TYPE_AUTOMATIC_DOWNLOADS;
    case RoomCEFContentSettingTypeJavaScript: return CEF_CONTENT_SETTING_TYPE_JAVASCRIPT;
    case RoomCEFContentSettingTypeImages: return CEF_CONTENT_SETTING_TYPE_IMAGES;
  }
}

- (RoomCEFContentSettingValue)contentSettingForURL:(NSString*)url type:(RoomCEFContentSettingType)type {
  switch (_context->GetContentSetting(ToCef(url), ToCef(url), ToCefContentType(type))) {
    case CEF_CONTENT_SETTING_VALUE_ALLOW: return RoomCEFContentSettingValueAllow;
    case CEF_CONTENT_SETTING_VALUE_BLOCK: return RoomCEFContentSettingValueBlock;
    case CEF_CONTENT_SETTING_VALUE_ASK: return RoomCEFContentSettingValueAsk;
    case CEF_CONTENT_SETTING_VALUE_SESSION_ONLY: return RoomCEFContentSettingValueSessionOnly;
    default: return RoomCEFContentSettingValueDefault;
  }
}

- (void)setContentSetting:(RoomCEFContentSettingValue)value forURL:(NSString*)url type:(RoomCEFContentSettingType)type {
  cef_content_setting_values_t cefValue = CEF_CONTENT_SETTING_VALUE_DEFAULT;
  switch (value) {
    case RoomCEFContentSettingValueDefault: cefValue = CEF_CONTENT_SETTING_VALUE_DEFAULT; break;
    case RoomCEFContentSettingValueAllow: cefValue = CEF_CONTENT_SETTING_VALUE_ALLOW; break;
    case RoomCEFContentSettingValueBlock: cefValue = CEF_CONTENT_SETTING_VALUE_BLOCK; break;
    case RoomCEFContentSettingValueAsk: cefValue = CEF_CONTENT_SETTING_VALUE_ASK; break;
    case RoomCEFContentSettingValueSessionOnly: cefValue = CEF_CONTENT_SETTING_VALUE_SESSION_ONLY; break;
  }
  _context->SetContentSetting(ToCef(url), ToCef(url), ToCefContentType(type), cefValue);
}

@end
