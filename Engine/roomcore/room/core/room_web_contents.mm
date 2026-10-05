// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_web_contents_internal.h"

#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "base/values.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/resource_coordinator/lifecycle_unit_state.mojom.h"
#include "chrome/browser/resource_coordinator/tab_lifecycle_unit_external.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/security_state/core/security_state.h"
#include "components/zoom/zoom_controller.h"
#include "components/zoom/zoom_observer.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/reload_type.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/blink/public/mojom/loader/referrer.mojom.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "ui/gfx/image/image.h"
#include "chrome/browser/printing/print_view_manager.h"
#include "chrome/browser/resource_coordinator/tab_helper.h"
#include "chrome/browser/translate/chrome_translate_client.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/permissions/permission_request_manager.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/page.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/common/input/web_keyboard_event.h"
#include "third_party/blink/public/mojom/input/input_event_result.mojom-shared.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "content/public/browser/visibility.h"
#include "content/public/common/url_constants.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#include "url/origin.h"
#import "room/core/room_browser_internal.h"
#import "room/core/room_profile_internal.h"

namespace room {
// Defined in chrome/browser/ui/browser_web_contents_delegate/
// browser_web_contents_delegate.cc (patches/0015-target-url-hook.patch).
extern bool (*g_update_target_url_hook)(content::WebContents*, const GURL&);
// Defined in chrome/browser/chrome_content_browser_client_navigation_
// throttles.cc (patches/0016-navigation-throttle-hook.patch).
extern void (*g_navigation_throttles_hook)(content::NavigationThrottleRegistry&);
}  // namespace room

@interface RoomNavigationAction ()
- (instancetype)initWithURL:(NSURL*)URL
                   referrer:(NSURL*)referrer
                       kind:(RoomNavigationKind)kind
                 transition:(RoomPageTransition)transition
                disposition:(RoomWindowOpenDisposition)disposition
                userGesture:(BOOL)userGesture
                   redirect:(BOOL)redirect
             clientRedirect:(BOOL)clientRedirect
          rendererInitiated:(BOOL)rendererInitiated;
@end

@implementation RoomNavigationAction

@synthesize URL = _URL;
@synthesize referrer = _referrer;
@synthesize kind = _kind;
@synthesize transition = _transition;
@synthesize disposition = _disposition;
@synthesize userGesture = _userGesture;
@synthesize redirect = _redirect;
@synthesize clientRedirect = _clientRedirect;
@synthesize rendererInitiated = _rendererInitiated;

- (instancetype)initWithURL:(NSURL*)URL
                   referrer:(NSURL*)referrer
                       kind:(RoomNavigationKind)kind
                 transition:(RoomPageTransition)transition
                disposition:(RoomWindowOpenDisposition)disposition
                userGesture:(BOOL)userGesture
                   redirect:(BOOL)redirect
             clientRedirect:(BOOL)clientRedirect
          rendererInitiated:(BOOL)rendererInitiated {
  if ((self = [super init])) {
    _URL = [URL copy];
    _referrer = [referrer copy];
    _kind = kind;
    _transition = transition;
    _disposition = disposition;
    _userGesture = userGesture;
    _redirect = redirect;
    _clientRedirect = clientRedirect;
    _rendererInitiated = rendererInitiated;
  }
  return self;
}

- (NSString*)description {
  return [NSString
      stringWithFormat:@"<RoomNavigationAction %@ kind=%ld transition=%ld "
                       @"disposition=%ld gesture=%d redirect=%d client=%d "
                       @"renderer=%d>",
                       _URL, (long)_kind, (long)_transition, (long)_disposition,
                       _userGesture, _redirect, _clientRedirect,
                       _rendererInitiated];
}

@end

@interface RoomWebContents ()
@property(nonatomic, readwrite, copy, nullable) NSURL* URL;
@property(nonatomic, readwrite, copy) NSString* title;
@property(nonatomic, readwrite, getter=isLoading) BOOL loading;
@property(nonatomic, readwrite) BOOL canGoBack;
@property(nonatomic, readwrite) BOOL canGoForward;
@property(nonatomic, readwrite, getter=isClosed) BOOL closed;
@property(nonatomic, readwrite, nullable) NSImage* favicon;
@property(nonatomic, readwrite) double loadProgress;
@property(nonatomic, readwrite, nullable) NSColor* themeColor;
@property(nonatomic, readwrite, nullable) NSColor* backgroundColor;
@property(nonatomic, readwrite) RoomSecurityLevel securityLevel;
@property(nonatomic, readwrite) BOOL hasMixedContent;
@property(nonatomic, readwrite, getter=isAudible) BOOL audible;
@property(nonatomic, readwrite) RoomLifecycleState lifecycleState;
- (void)room_refresh;
- (void)room_refreshColors;
- (void)room_refreshSecurity;
- (void)room_refreshFavicon;
- (void)room_setLoadProgress:(double)progress;
- (void)room_setAudible:(BOOL)audible;
- (void)room_mutingChanged;
- (void)room_zoomChanged;
- (void)room_didFinishNavigation:(content::NavigationHandle*)handle;
- (void)room_webContentsDestroyed;
- (void)room_shownOrFocused;
- (void)room_didConsumeKeyCode:(unsigned short)keyCode
                 modifierFlags:(NSEventModifierFlags)flags
                         phase:(RoomKeyEventPhase)phase;
@end

namespace {

// Maps a WebContents to its (weakly held) wrapper.
class WrapperLink : public content::WebContentsUserData<WrapperLink> {
 public:
  RoomWebContents* wrapper() const { return wrapper_; }

 private:
  friend class content::WebContentsUserData<WrapperLink>;
  WrapperLink(content::WebContents* contents, RoomWebContents* wrapper)
      : content::WebContentsUserData<WrapperLink>(*contents),
        wrapper_(wrapper) {}

  RoomWebContents* __weak wrapper_;
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(WrapperLink);

// RoomCore's isolated world for the host's scripts. Chrome reserves this id
// for AppleScript's "execute javascript", the same job (an embedding app
// scripting a page); Room ships no Chrome AppleScript tab commands, and the
// ids above it are handed out to extensions at run time.
constexpr int32_t kRoomIsolatedWorldId = ISOLATED_WORLD_ID_APPLESCRIPT;

NSEventModifierFlags ToModifierFlags(int modifiers) {
  NSEventModifierFlags flags = 0;
  if (modifiers & blink::WebInputEvent::kShiftKey) {
    flags |= NSEventModifierFlagShift;
  }
  if (modifiers & blink::WebInputEvent::kControlKey) {
    flags |= NSEventModifierFlagControl;
  }
  if (modifiers & blink::WebInputEvent::kAltKey) {
    flags |= NSEventModifierFlagOption;
  }
  if (modifiers & blink::WebInputEvent::kMetaKey) {
    flags |= NSEventModifierFlagCommand;
  }
  if (modifiers & blink::WebInputEvent::kCapsLockOn) {
    flags |= NSEventModifierFlagCapsLock;
  }
  return flags;
}

// The renderer's acknowledgements of key events on the page's main-frame
// widget (the widget changes with the primary page): consumed ones go to the
// wrapper's delegate (didConsumeKey).
class KeyAckObserver : public content::RenderWidgetHost::InputEventObserver,
                       public content::RenderWidgetHostObserver {
 public:
  explicit KeyAckObserver(RoomWebContents* wrapper) : wrapper_(wrapper) {}
  ~KeyAckObserver() override { Detach(); }

  void Attach(content::RenderWidgetHost* widget) {
    if (widget == widget_) {
      return;
    }
    Detach();
    widget_ = widget;
    if (widget_) {
      widget_->AddInputEventObserver(this);
      widget_->AddObserver(this);
    }
  }

  void Detach() {
    if (!widget_) {
      return;
    }
    widget_->RemoveInputEventObserver(this);
    widget_->RemoveObserver(this);
    widget_ = nullptr;
  }

  // content::RenderWidgetHost::InputEventObserver:
  void OnInputEventAck(const content::RenderWidgetHost&,
                       blink::mojom::InputEventResultSource,
                       blink::mojom::InputEventResultState state,
                       const blink::WebInputEvent& event) override {
    if (state != blink::mojom::InputEventResultState::kConsumed ||
        !blink::WebInputEvent::IsKeyboardEventType(event.GetType())) {
      return;
    }
    const auto& key = static_cast<const blink::WebKeyboardEvent&>(event);
    RoomKeyEventPhase phase = RoomKeyEventPhaseKeyDown;
    if (event.GetType() == blink::WebInputEvent::Type::kKeyUp) {
      phase = RoomKeyEventPhaseKeyUp;
    } else if (event.GetType() == blink::WebInputEvent::Type::kChar) {
      phase = RoomKeyEventPhaseCharacter;
    }
    [wrapper_ room_didConsumeKeyCode:static_cast<unsigned short>(
                                         key.native_key_code)
                       modifierFlags:ToModifierFlags(key.GetModifiers())
                               phase:phase];
  }

  // content::RenderWidgetHostObserver:
  void RenderWidgetHostDestroyed(content::RenderWidgetHost* widget) override {
    if (widget == widget_) {
      Detach();
    }
  }

 private:
  RoomWebContents* __weak wrapper_;
  raw_ptr<content::RenderWidgetHost> widget_ = nullptr;
};

// Turns WebContentsObserver events (and, once Chrome attached its tab
// helpers, favicon and zoom events) into KVO changes on the wrapper.
class Observer : public content::WebContentsObserver,
                 public favicon::FaviconDriverObserver,
                 public zoom::ZoomObserver {
 public:
  Observer(content::WebContents* contents, RoomWebContents* wrapper)
      : content::WebContentsObserver(contents),
        wrapper_(wrapper),
        key_acks_(wrapper) {
    key_acks_.Attach(
        contents->GetPrimaryMainFrame()->GetRenderWidgetHost());
  }

  // Favicons and zoom come from tab helpers, which Chrome attaches when the
  // page joins a tab strip (tabs::TabModel). Idempotent.
  void ObserveTabHelpers() {
    content::WebContents* contents = web_contents();
    if (!contents) {
      return;
    }
    if (!favicons_.IsObserving()) {
      if (auto* driver =
              favicon::ContentFaviconDriver::FromWebContents(contents)) {
        favicons_.Observe(driver);
      }
    }
    if (!zoom_.IsObserving()) {
      if (auto* zoom = zoom::ZoomController::FromWebContents(contents)) {
        zoom_.Observe(zoom);
      }
    }
  }

  // The wrapper moved to another WebContents (a discard): this observer
  // stays until the old contents is destroyed but reports nothing.
  void Retire() {
    retired_ = true;
    wrapper_ = nil;
    key_acks_.Detach();
    favicons_.Reset();
    zoom_.Reset();
  }

  void PrimaryPageChanged(content::Page& page) override {
    key_acks_.Attach(page.GetMainDocument().GetRenderWidgetHost());
  }
  void RenderFrameHostChanged(content::RenderFrameHost* old_host,
                              content::RenderFrameHost* new_host) override {
    if (wrapper_ && new_host && new_host->IsInPrimaryMainFrame()) {
      key_acks_.Attach(new_host->GetRenderWidgetHost());
    }
  }

  void DidStartLoading() override { [wrapper_ room_refresh]; }
  void DidStopLoading() override { [wrapper_ room_refresh]; }
  void DidStartNavigation(content::NavigationHandle*) override {
    [wrapper_ room_refresh];
  }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    [wrapper_ room_refresh];
    [wrapper_ room_didFinishNavigation:handle];
  }
  void TitleWasSet(content::NavigationEntry*) override {
    [wrapper_ room_refresh];
  }
  void NavigationEntryCommitted(const content::LoadCommittedDetails&) override {
    [wrapper_ room_refresh];
  }
  void NavigationListPruned(const content::PrunedDetails&) override {
    [wrapper_ room_refresh];
  }
  void LoadProgressChanged(double progress) override {
    [wrapper_ room_setLoadProgress:progress];
  }
  void DidChangeThemeColor() override { [wrapper_ room_refreshColors]; }
  void OnBackgroundColorChanged() override { [wrapper_ room_refreshColors]; }
  void DidChangeVisibleSecurityState() override {
    [wrapper_ room_refreshSecurity];
  }
  void OnAudioStateChanged(bool audible) override {
    [wrapper_ room_setAudible:audible];
  }
  void DidUpdateAudioMutingState(bool) override {
    [wrapper_ room_mutingChanged];
  }
  // The host showed the page (its view is in a visible window) or the user
  // focused it (a click into a split pane): it is the active tab now.
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::VISIBLE) {
      [wrapper_ room_shownOrFocused];
    }
    [wrapper_ room_refresh];
  }
  void OnWebContentsFocused(content::RenderWidgetHost*) override {
    [wrapper_ room_shownOrFocused];
  }
  void WebContentsDestroyed() override {
    key_acks_.Detach();
    favicons_.Reset();
    zoom_.Reset();
    if (retired_) {
      content::RenderProcessHost* process =
          web_contents()->GetPrimaryMainFrame()->GetProcess();
      LOG(WARNING) << "RoomCore: a discarded page's old WebContents is "
                      "destroyed (renderer pid "
                   << (process && process->IsReady()
                           ? process->GetProcess().Pid()
                           : 0)
                   << ", hosting " << (process ? process->GetActiveViewCount() : 0)
                   << " views)";
    }
    [wrapper_ room_webContentsDestroyed];
  }

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver*,
                        NotificationIconType type,
                        const GURL&,
                        bool,
                        const gfx::Image&) override {
    if (type == NON_TOUCH_16_DIP) {
      [wrapper_ room_refreshFavicon];
    }
  }

  // zoom::ZoomObserver:
  void OnZoomControllerDestroyed(zoom::ZoomController*) override {
    zoom_.Reset();
  }
  void OnZoomChanged(
      const zoom::ZoomController::ZoomChangedEventData& data) override {
    if (data.web_contents == web_contents()) {
      [wrapper_ room_zoomChanged];
    }
  }

 private:
  RoomWebContents* __weak wrapper_;
  bool retired_ = false;
  KeyAckObserver key_acks_;
  base::ScopedObservation<favicon::FaviconDriver,
                          favicon::FaviconDriverObserver>
      favicons_{this};
  base::ScopedObservation<zoom::ZoomController, zoom::ZoomObserver> zoom_{
      this};
};

RoomPageTransition ToRoomTransition(ui::PageTransition transition) {
  if (transition & ui::PAGE_TRANSITION_FORWARD_BACK) {
    return RoomPageTransitionOther;
  }
  switch (ui::PageTransitionStripQualifier(transition)) {
    case ui::PAGE_TRANSITION_LINK:
      return RoomPageTransitionLink;
    case ui::PAGE_TRANSITION_TYPED:
      return RoomPageTransitionTyped;
    case ui::PAGE_TRANSITION_AUTO_BOOKMARK:
      return RoomPageTransitionAutoBookmark;
    case ui::PAGE_TRANSITION_GENERATED:
      return RoomPageTransitionGenerated;
    case ui::PAGE_TRANSITION_KEYWORD:
    case ui::PAGE_TRANSITION_KEYWORD_GENERATED:
      return RoomPageTransitionKeyword;
    case ui::PAGE_TRANSITION_FORM_SUBMIT:
      return RoomPageTransitionFormSubmit;
    case ui::PAGE_TRANSITION_RELOAD:
      return RoomPageTransitionReload;
    default:
      return RoomPageTransitionOther;
  }
}

ui::PageTransition FromRoomTransition(RoomPageTransition transition) {
  switch (transition) {
    case RoomPageTransitionLink:
      return ui::PAGE_TRANSITION_LINK;
    case RoomPageTransitionTyped:
      return ui::PAGE_TRANSITION_TYPED;
    case RoomPageTransitionAutoBookmark:
      return ui::PAGE_TRANSITION_AUTO_BOOKMARK;
    case RoomPageTransitionGenerated:
      return ui::PAGE_TRANSITION_GENERATED;
    case RoomPageTransitionKeyword:
      return ui::PAGE_TRANSITION_KEYWORD;
    case RoomPageTransitionFormSubmit:
      return ui::PAGE_TRANSITION_FORM_SUBMIT;
    case RoomPageTransitionReload:
      return ui::PAGE_TRANSITION_RELOAD;
    case RoomPageTransitionOther:
      return ui::PAGE_TRANSITION_AUTO_TOPLEVEL;
  }
  return ui::PAGE_TRANSITION_LINK;
}

WindowOpenDisposition FromRoomDisposition(RoomWindowOpenDisposition d) {
  switch (d) {
    case RoomWindowOpenDispositionNewForegroundTab:
      return WindowOpenDisposition::NEW_FOREGROUND_TAB;
    case RoomWindowOpenDispositionNewBackgroundTab:
      return WindowOpenDisposition::NEW_BACKGROUND_TAB;
    case RoomWindowOpenDispositionNewPopup:
      return WindowOpenDisposition::NEW_POPUP;
    case RoomWindowOpenDispositionNewWindow:
      return WindowOpenDisposition::NEW_WINDOW;
    case RoomWindowOpenDispositionNewPictureInPicture:
      return WindowOpenDisposition::NEW_PICTURE_IN_PICTURE;
    case RoomWindowOpenDispositionSingletonTab:
      return WindowOpenDisposition::SINGLETON_TAB;
    case RoomWindowOpenDispositionSwitchToTab:
      return WindowOpenDisposition::SWITCH_TO_TAB;
    case RoomWindowOpenDispositionOffTheRecord:
      return WindowOpenDisposition::OFF_THE_RECORD;
    case RoomWindowOpenDispositionNewSplitView:
      return WindowOpenDisposition::NEW_SPLIT_VIEW;
    case RoomWindowOpenDispositionCurrentTab:
      return WindowOpenDisposition::CURRENT_TAB;
    case RoomWindowOpenDispositionIgnoreAction:
      return WindowOpenDisposition::IGNORE_ACTION;
    case RoomWindowOpenDispositionSaveToDisk:
      return WindowOpenDisposition::SAVE_TO_DISK;
  }
  return WindowOpenDisposition::CURRENT_TAB;
}

RoomWindowOpenDisposition ToRoomDisposition(WindowOpenDisposition d) {
  switch (d) {
    case WindowOpenDisposition::NEW_FOREGROUND_TAB:
      return RoomWindowOpenDispositionNewForegroundTab;
    case WindowOpenDisposition::NEW_BACKGROUND_TAB:
      return RoomWindowOpenDispositionNewBackgroundTab;
    case WindowOpenDisposition::NEW_POPUP:
      return RoomWindowOpenDispositionNewPopup;
    case WindowOpenDisposition::NEW_WINDOW:
      return RoomWindowOpenDispositionNewWindow;
    case WindowOpenDisposition::NEW_PICTURE_IN_PICTURE:
      return RoomWindowOpenDispositionNewPictureInPicture;
    case WindowOpenDisposition::SINGLETON_TAB:
      return RoomWindowOpenDispositionSingletonTab;
    case WindowOpenDisposition::SWITCH_TO_TAB:
      return RoomWindowOpenDispositionSwitchToTab;
    case WindowOpenDisposition::OFF_THE_RECORD:
      return RoomWindowOpenDispositionOffTheRecord;
    case WindowOpenDisposition::NEW_SPLIT_VIEW:
      return RoomWindowOpenDispositionNewSplitView;
    case WindowOpenDisposition::IGNORE_ACTION:
      return RoomWindowOpenDispositionIgnoreAction;
    case WindowOpenDisposition::SAVE_TO_DISK:
      return RoomWindowOpenDispositionSaveToDisk;
    default:
      return RoomWindowOpenDispositionCurrentTab;
  }
}

NSURL* ToNSURL(const GURL& url) {
  return url.is_valid() ? net::NSURLWithGURL(url) : nil;
}

// A WebContents created hidden (initially_hidden, a background tab Chrome
// opened, a discard's replacement) gets a hidden WebContentsViewCocoa
// (WebContentsViewMac::CreateView): Chrome's Views WebView unhides it when it
// shows the tab (ViewsHostableSetVisible). The host has no Views, so the
// view is unhidden here; it then follows its window: VISIBLE once the host
// puts it in a visible window (WasShown on the first time), HIDDEN when the
// host takes it out (WebContentsViewCocoa -viewDidMoveToWindow).
void UnhideNativeView(content::WebContents* contents) {
  NSView* view = contents ? contents->GetNativeView().GetNativeNSView() : nil;
  if (view.hidden) {
    view.hidden = NO;
  }
}

// The policy question for a navigation of a Room page's primary main frame,
// asked of the host synchronously on the UI thread (the main thread) before
// the request starts and at each server redirect.
class RoomNavigationThrottle : public content::NavigationThrottle {
 public:
  explicit RoomNavigationThrottle(content::NavigationThrottleRegistry& registry)
      : content::NavigationThrottle(registry) {}

  ThrottleCheckResult WillStartRequest() override { return Decide(false); }
  ThrottleCheckResult WillRedirectRequest() override { return Decide(true); }
  const char* GetNameForLogging() override { return "RoomNavigationThrottle"; }

 private:
  ThrottleCheckResult Decide(bool redirect) {
    content::NavigationHandle* handle = navigation_handle();
    content::WebContents* contents = handle->GetWebContents();
    RoomWebContents* wrapper = [RoomWebContents room_existingWrapperFor:contents];
    if (!wrapper) {
      return PROCEED;
    }
    const ui::PageTransition transition = handle->GetPageTransition();
    RoomNavigationKind kind = RoomNavigationKindOther;
    if (handle->IsFormSubmission() ||
        ui::PageTransitionCoreTypeIs(transition,
                                     ui::PAGE_TRANSITION_FORM_SUBMIT)) {
      kind = RoomNavigationKindFormSubmitted;
    } else if (transition & ui::PAGE_TRANSITION_FORWARD_BACK) {
      kind = RoomNavigationKindBackForward;
    } else if (handle->GetReloadType() != content::ReloadType::NONE ||
               ui::PageTransitionCoreTypeIs(transition,
                                            ui::PAGE_TRANSITION_RELOAD)) {
      kind = RoomNavigationKindReload;
    } else if (handle->IsRendererInitiated() &&
               handle->WasInitiatedByLinkClick()) {
      // Blink's navigation type kLinkClicked: the navigation came from an
      // event on a link (HTMLAnchorElement), never from window.location.
      kind = RoomNavigationKindLinkClicked;
    }
    RoomNavigationAction* action = [[RoomNavigationAction alloc]
          initWithURL:ToNSURL(handle->GetURL())
             referrer:ToNSURL(handle->GetReferrer().url)
                 kind:kind
           transition:ToRoomTransition(transition)
          disposition:RoomWindowOpenDispositionCurrentTab
          userGesture:handle->HasUserGesture()
             redirect:redirect || handle->WasServerRedirect()
       clientRedirect:(transition & ui::PAGE_TRANSITION_CLIENT_REDIRECT) != 0
    rendererInitiated:handle->IsRendererInitiated()];
    if (!action.URL) {
      return PROCEED;
    }
    const RoomWindowOpenDisposition decision = [wrapper room_decidePolicy:action];
    switch (decision) {
      case RoomWindowOpenDispositionCurrentTab:
        return PROCEED;
      case RoomWindowOpenDispositionIgnoreAction:
        return CANCEL_AND_IGNORE;
      default: {
        // Cancelled here and opened the way the host asked, once this
        // navigation has unwound (Navigate() keeps it in this Browser).
        content::OpenURLParams params(
            handle->GetURL(), content::Referrer(handle->GetReferrer()),
            FromRoomDisposition(decision), transition,
            handle->IsRendererInitiated());
        params.user_gesture = handle->HasUserGesture();
        base::WeakPtr<content::WebContents> weak = contents->GetWeakPtr();
        base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
            FROM_HERE, base::BindOnce(
                           [](base::WeakPtr<content::WebContents> contents,
                              content::OpenURLParams params) {
                             if (contents) {
                               contents->OpenURL(params, {});
                             }
                           },
                           weak, std::move(params)));
        return CANCEL_AND_IGNORE;
      }
    }
  }
};

// base::Value (the renderer's V8 conversion) as Foundation objects.
id ToFoundation(const base::Value& value) {
  switch (value.type()) {
    case base::Value::Type::NONE:
    case base::Value::Type::BINARY:
      return NSNull.null;
    case base::Value::Type::BOOLEAN:
      return @(value.GetBool());
    case base::Value::Type::INTEGER:
      return @(value.GetInt());
    case base::Value::Type::DOUBLE:
      return @(value.GetDouble());
    case base::Value::Type::STRING:
      return base::SysUTF8ToNSString(value.GetString());
    case base::Value::Type::DICT: {
      NSMutableDictionary* result = [NSMutableDictionary dictionary];
      for (const auto [key, item] : value.GetDict()) {
        result[base::SysUTF8ToNSString(key)] = ToFoundation(item);
      }
      return result;
    }
    case base::Value::Type::LIST: {
      NSMutableArray* result = [NSMutableArray array];
      for (const base::Value& item : value.GetList()) {
        [result addObject:ToFoundation(item)];
      }
      return result;
    }
  }
  return NSNull.null;
}

}  // namespace

namespace room {

void InstallWebContentsHooks() {
  g_update_target_url_hook = +[](content::WebContents* source,
                                 const GURL& url) -> bool {
    // Only Room pages have a wrapper; Chrome's own (headless) Browsers keep
    // Chrome's behaviour (no status bubble: nothing happens).
    RoomWebContents* wrapper = [RoomWebContents room_existingWrapperFor:source];
    if (!wrapper) {
      return false;
    }
    [wrapper room_targetURLChanged:url];
    return true;
  };
  g_navigation_throttles_hook =
      +[](content::NavigationThrottleRegistry& registry) {
        content::NavigationHandle& handle = registry.GetNavigationHandle();
        // Room pages only (they have a wrapper), their primary main frame
        // only: subframes, prerenders and Chrome's own pages keep Chrome's
        // throttles alone.
        if (!handle.IsInPrimaryMainFrame() ||
            ![RoomWebContents
                room_existingWrapperFor:handle.GetWebContents()]) {
          return;
        }
        registry.AddThrottle(std::make_unique<RoomNavigationThrottle>(registry));
      };
}

bool AllowOpenFromRoomPage(const NavigateParams& params) {
  content::WebContents* source = params.source_contents.get();
  RoomWebContents* wrapper =
      source ? [RoomWebContents room_existingWrapperFor:source] : nil;
  if (!wrapper || params.disposition == WindowOpenDisposition::CURRENT_TAB) {
    return true;  // A navigation of the page itself: the throttle asks.
  }
  RoomNavigationKind kind = RoomNavigationKindOther;
  if (ui::PageTransitionCoreTypeIs(params.transition,
                                   ui::PAGE_TRANSITION_FORM_SUBMIT)) {
    kind = RoomNavigationKindFormSubmitted;
  } else if (params.is_renderer_initiated && params.user_gesture &&
             !params.contents_to_insert) {
    // OpenURLFromTab from the page with a gesture: a modifier or middle
    // click on a link (a script cannot ask for a tab disposition; a
    // window.open, target=_blank included, arrives with its contents).
    kind = RoomNavigationKindLinkClicked;
  }
  RoomNavigationAction* action = [[RoomNavigationAction alloc]
        initWithURL:ToNSURL(params.url)
           referrer:ToNSURL(params.referrer.url)
               kind:kind
         transition:ToRoomTransition(params.transition)
        disposition:ToRoomDisposition(params.disposition)
        userGesture:params.user_gesture
           redirect:NO
     clientRedirect:(params.transition & ui::PAGE_TRANSITION_CLIENT_REDIRECT) != 0
  rendererInitiated:params.is_renderer_initiated];
  if (!action.URL) {
    return true;
  }
  return [wrapper room_decidePolicy:action] !=
         RoomWindowOpenDispositionIgnoreAction;
}

}  // namespace room

@implementation RoomWebContents {
  RoomProfile* _profile;
  // Set while the wrapper owns the page (before it joins a tab strip).
  std::unique_ptr<content::WebContents> _owned;
  raw_ptr<content::WebContents> _contents;
  std::unique_ptr<Observer> _observer;
  RoomBrowser* __weak _browser;
  NSString* _statusText;
  // Observers of contents the wrapper left (a discard), deleted once their
  // contents is gone.
  std::vector<std::unique_ptr<Observer>> _retiredObservers;
}

@synthesize delegate = _delegate;

@synthesize URL = _URL;
@synthesize title = _title;
@synthesize loading = _loading;
@synthesize canGoBack = _canGoBack;
@synthesize canGoForward = _canGoForward;
@synthesize closed = _closed;
@synthesize favicon = _favicon;
@synthesize loadProgress = _loadProgress;
@synthesize themeColor = _themeColor;
@synthesize backgroundColor = _backgroundColor;
@synthesize securityLevel = _securityLevel;
@synthesize hasMixedContent = _hasMixedContent;
@synthesize audible = _audible;
@synthesize lifecycleState = _lifecycleState;

- (instancetype)initWithChromeWebContents:
                    (std::unique_ptr<content::WebContents>)webContents
                                 profile:(RoomProfile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    _owned = std::move(webContents);
    _contents = _owned.get();
    _title = @"";
    _loadProgress = 1;
    UnhideNativeView(_contents);
    WrapperLink::CreateForWebContents(_contents, self);
    _observer = std::make_unique<Observer>(_contents, self);
    [self room_refresh];
  }
  return self;
}

- (instancetype)initWithUnownedChromeWebContents:
                    (content::WebContents*)webContents
                                         profile:(RoomProfile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    _contents = webContents;
    _title = @"";
    _loadProgress = 1;
    UnhideNativeView(_contents);
    WrapperLink::CreateForWebContents(_contents, self);
    _observer = std::make_unique<Observer>(_contents, self);
    // Chrome inserted it into a tab strip: its tab helpers exist.
    _observer->ObserveTabHelpers();
    [self room_refresh];
    [self room_refreshColors];
    [self room_refreshSecurity];
    [self room_refreshFavicon];
  }
  return self;
}

+ (RoomWebContents*)room_existingWrapperFor:(content::WebContents*)contents {
  WrapperLink* link = contents ? WrapperLink::FromWebContents(contents) : nullptr;
  return link ? link->wrapper() : nil;
}

- (void)dealloc {
  _observer.reset();
  if (_contents) {
    _contents->RemoveUserData(WrapperLink::UserDataKey());
  }
}

- (std::unique_ptr<content::WebContents>)room_releaseWebContents {
  return std::move(_owned);
}

- (content::WebContents*)room_webContents {
  return _contents;
}

- (RoomProfile*)profile {
  return _profile;
}

- (RoomBrowser*)room_browser {
  return _browser;
}

- (void)setRoom_browser:(RoomBrowser*)browser {
  _browser = browser;
}

- (void)room_shownOrFocused {
  [_browser room_activateWebContents:self];
}

- (void)room_targetURLChanged:(const GURL&)url {
  NSString* text = url.is_empty() ? nil : base::SysUTF8ToNSString(url.spec());
  if (text == _statusText || [text isEqualToString:_statusText]) {
    return;
  }
  _statusText = [text copy];
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(webContents:didChangeStatusText:)]) {
    [delegate webContents:self didChangeStatusText:text];
  }
}

- (void)room_didEnterFullscreen:(const url::Origin&)origin {
  NSURL* originURL =
      origin.opaque() ? nil : net::NSURLWithGURL(origin.GetURL());
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector
                (webContentsDidRequestEnterFullscreen:origin:)]) {
    [delegate webContentsDidRequestEnterFullscreen:self origin:originURL];
  }
}

- (void)room_didExitFullscreen {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate
          respondsToSelector:@selector(webContentsDidRequestExitFullscreen:)]) {
    [delegate webContentsDidRequestExitFullscreen:self];
  }
}

- (BOOL)room_isReservedKeyEvent:(NSEvent*)event {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  return [delegate respondsToSelector:@selector(webContents:isReservedKeyEvent:)]
             ? [delegate webContents:self isReservedKeyEvent:event]
             : NO;
}

- (BOOL)room_handleUnhandledKeyEvent:(NSEvent*)event {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  return [delegate
             respondsToSelector:@selector(webContents:handleUnhandledKeyEvent:)]
             ? [delegate webContents:self handleUnhandledKeyEvent:event]
             : NO;
}

- (void)room_didConsumeKeyCode:(unsigned short)keyCode
                 modifierFlags:(NSEventModifierFlags)flags
                         phase:(RoomKeyEventPhase)phase {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector
                (webContents:didConsumeKeyCode:modifierFlags:phase:)]) {
    [delegate webContents:self
        didConsumeKeyCode:keyCode
            modifierFlags:flags
                    phase:phase];
  }
}

- (void)evaluateJavaScript:(NSString*)script
                completion:(void (^)(id, NSError*))completion {
  content::RenderFrameHost* frame =
      _contents ? _contents->GetPrimaryMainFrame() : nullptr;
  if (!frame || !frame->IsRenderFrameLive()) {
    completion(nil, [NSError
                        errorWithDomain:@"RoomCore"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     _contents ? @"the page has no live document"
                                               : @"the page is closed"
                               }]);
    return;
  }
  void (^callback)(id, NSError*) = [completion copy];
  auto deliver = base::BindOnce(^(base::Value result) {
    callback(ToFoundation(result), nil);
  });
  // DevTools' own front-end (devtools://, a page RoomCore hands the host in
  // its pane) runs scripts in its main world: content allows that for
  // devtools: pages, and the front-end's modules are reachable only there.
  if (frame->GetLastCommittedURL().SchemeIs(content::kChromeDevToolsScheme)) {
    frame->ExecuteJavaScript(base::SysNSStringToUTF16(script),
                             std::move(deliver));
    return;
  }
  frame->ExecuteJavaScriptInIsolatedWorld(base::SysNSStringToUTF16(script),
                                          std::move(deliver),
                                          kRoomIsolatedWorldId);
}

- (void)room_didCreateWebContents:(RoomWebContents*)newContents
                        targetURL:(NSURL*)targetURL
                      disposition:(RoomWindowOpenDisposition)disposition
                  requestedBounds:(NSRect)requestedBounds
                      userGesture:(BOOL)userGesture {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector
                (webContents:didCreateWebContents:targetURL:disposition:
                     requestedBounds:userGesture:)]) {
    [delegate webContents:self
        didCreateWebContents:newContents
                   targetURL:targetURL
                 disposition:disposition
             requestedBounds:requestedBounds
                 userGesture:userGesture];
  }
}

- (void)room_tabHelpersAttached {
  if (!_observer || !_contents) {
    return;
  }
  _observer->ObserveTabHelpers();
  static bool logged = false;
  if (!logged) {
    logged = true;
    // Which of Chrome's tab helpers a Room page has (attached by
    // tabs::TabModel when the page joins a Room Browser's strip).
    content::WebContents* c = _contents;
    LOG(WARNING)
        << "RoomCore: tab helpers on a Room page: favicon="
        << !!favicon::ContentFaviconDriver::FromWebContents(c)
        << " zoom=" << !!zoom::ZoomController::FromWebContents(c)
        << " lifecycle="
        << !!resource_coordinator::TabLifecycleUnitExternal::FromWebContents(c)
        << " resource_coordinator="
        << !!resource_coordinator::ResourceCoordinatorTabHelper::FromWebContents(
               c)
        << " find=" << !!find_in_page::FindTabHelper::FromWebContents(c)
        << " session=" << !!sessions::SessionTabHelper::FromWebContents(c)
        << " permissions="
        << !!permissions::PermissionRequestManager::FromWebContents(c)
        << " translate=" << !!ChromeTranslateClient::FromWebContents(c)
        << " print=" << !!printing::PrintViewManager::FromWebContents(c);
  }
  [self room_refreshFavicon];
  [self room_zoomChanged];
  [self room_refresh];
}

- (void)room_replaceWebContents:(content::WebContents*)newContents {
  if (!_contents || !newContents || newContents == _contents) {
    return;
  }
  // The old contents is destroyed after the strip swapped it out; its
  // observer must not report that as this page closing.
  _observer->Retire();
  _retiredObservers.push_back(std::move(_observer));
  _contents->RemoveUserData(WrapperLink::UserDataKey());
  [self willChangeValueForKey:@"nativeView"];
  _contents = newContents;
  UnhideNativeView(_contents);
  [self didChangeValueForKey:@"nativeView"];
  WrapperLink::CreateForWebContents(_contents, self);
  _observer = std::make_unique<Observer>(_contents, self);
  _observer->ObserveTabHelpers();
  [self room_refresh];
  [self room_refreshColors];
  [self room_refreshSecurity];
  [self room_refreshFavicon];
  // Drop the retired observers once the old contents is gone (it is
  // destroyed later in the same discard).
  RoomWebContents* __weak weakSelf = self;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(^{
        RoomWebContents* strongSelf = weakSelf;
        if (strongSelf) {
          strongSelf->_retiredObservers.clear();
        }
      }));
}

- (RoomWindowOpenDisposition)room_decidePolicy:(RoomNavigationAction*)action {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector
                 (webContents:decidePolicyForNavigationAction:)]) {
    return action.disposition;
  }
  return [delegate webContents:self decidePolicyForNavigationAction:action];
}

- (void)room_didFinishNavigation:(content::NavigationHandle*)handle {
  if (!handle->HasCommitted() || !handle->IsInPrimaryMainFrame() ||
      handle->IsErrorPage()) {
    return;
  }
  if (!handle->IsSameDocument()) {
    [self room_refreshFavicon];
    [self room_refreshColors];
  }
  [self room_refreshSecurity];
  NSURL* url = ToNSURL(handle->GetURL());
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if (url && [delegate respondsToSelector:@selector
                       (webContents:didCommitNavigationToURL:transition:
                            sameDocument:)]) {
    [delegate webContents:self
        didCommitNavigationToURL:url
                      transition:ToRoomTransition(handle->GetPageTransition())
                    sameDocument:handle->IsSameDocument()];
  }
}

- (void)room_setLoadProgress:(double)progress {
  if (progress != _loadProgress) {
    self.loadProgress = progress;
  }
}

- (void)room_refreshColors {
  if (!_contents) {
    return;
  }
  std::optional<SkColor> theme = _contents->GetThemeColor();
  NSColor* themeColor = theme ? skia::SkColorToSRGBNSColor(*theme) : nil;
  if (!(themeColor == _themeColor || [themeColor isEqual:_themeColor])) {
    self.themeColor = themeColor;
  }
  std::optional<SkColor> background = _contents->GetBackgroundColor();
  NSColor* backgroundColor =
      background ? skia::SkColorToSRGBNSColor(*background) : nil;
  if (!(backgroundColor == _backgroundColor ||
        [backgroundColor isEqual:_backgroundColor])) {
    self.backgroundColor = backgroundColor;
  }
}

- (void)room_refreshSecurity {
  if (!_contents) {
    return;
  }
  RoomSecurityLevel level = RoomSecurityLevelNone;
  switch (chrome_security_state::GetSecurityLevel(_contents)) {
    case security_state::SECURE:
      level = RoomSecurityLevelSecure;
      break;
    case security_state::WARNING:
      level = RoomSecurityLevelWarning;
      break;
    case security_state::DANGEROUS:
      level = RoomSecurityLevelDangerous;
      break;
    default:
      level = RoomSecurityLevelNone;
      break;
  }
  std::unique_ptr<security_state::VisibleSecurityState> visible =
      chrome_security_state::GetVisibleSecurityState(_contents);
  const BOOL mixed = visible && visible->displayed_mixed_content;
  if (mixed != _hasMixedContent) {
    self.hasMixedContent = mixed;
  }
  if (level != _securityLevel) {
    self.securityLevel = level;
  }
}

- (void)room_refreshFavicon {
  if (!_contents) {
    return;
  }
  auto* driver = favicon::ContentFaviconDriver::FromWebContents(_contents);
  NSImage* favicon = nil;
  if (driver && driver->FaviconIsValid()) {
    gfx::Image image = driver->GetFavicon();
    if (!image.IsEmpty()) {
      favicon = image.ToNSImage();
    }
  }
  if (favicon != _favicon) {
    self.favicon = favicon;
  }
}

- (void)room_setAudible:(BOOL)audible {
  if (audible != _audible) {
    self.audible = audible;
  }
}

- (BOOL)isMuted {
  return _contents && _contents->IsAudioMuted();
}

- (void)setMuted:(BOOL)muted {
  if (_contents && _contents->IsAudioMuted() != static_cast<bool>(muted)) {
    _contents->SetAudioMuted(muted);
  }
}

- (void)room_mutingChanged {
  [self willChangeValueForKey:@"muted"];
  [self didChangeValueForKey:@"muted"];
}

- (double)zoomFactor {
  auto* zoom = _contents ? zoom::ZoomController::FromWebContents(_contents)
                         : nullptr;
  return zoom ? blink::ZoomLevelToZoomFactor(zoom->GetZoomLevel()) : 1.0;
}

- (void)setZoomFactor:(double)zoomFactor {
  auto* zoom = _contents ? zoom::ZoomController::FromWebContents(_contents)
                         : nullptr;
  if (zoom && zoomFactor > 0) {
    zoom->SetZoomLevel(blink::ZoomFactorToZoomLevel(zoomFactor));
  }
}

- (void)room_zoomChanged {
  [self willChangeValueForKey:@"zoomFactor"];
  [self didChangeValueForKey:@"zoomFactor"];
}

- (BOOL)discard {
  if (!_contents) {
    return NO;
  }
  auto* unit =
      resource_coordinator::TabLifecycleUnitExternal::FromWebContents(_contents);
  if (!unit) {
    LOG(WARNING) << "RoomCore: discard refused: the page is in no tab strip";
    return NO;
  }
  const bool discarded = unit->DiscardTab(
      ::mojom::LifecycleUnitDiscardReason::EXTERNAL);
  [self room_refresh];
  return discarded;
}

- (NSView*)nativeView {
  return _contents ? _contents->GetNativeView().GetNativeNSView() : nil;
}

// Pushes Chromium's state into the KVO properties, writing only what changed
// so observers see one notification per real change.
- (void)room_refresh {
  if (!_contents) {
    return;
  }
  NSURL* url = net::NSURLWithGURL(_contents->GetVisibleURL());
  if (!(url == self.URL || [url isEqual:self.URL])) {
    self.URL = url;
  }
  NSString* title = base::SysUTF16ToNSString(_contents->GetTitle());
  if (![title isEqualToString:self.title]) {
    self.title = title;
  }
  const BOOL loading = _contents->IsLoading();
  if (loading != self.loading) {
    self.loading = loading;
  }
  content::NavigationController& controller = _contents->GetController();
  if (controller.CanGoBack() != self.canGoBack) {
    self.canGoBack = controller.CanGoBack();
  }
  if (controller.CanGoForward() != self.canGoForward) {
    self.canGoForward = controller.CanGoForward();
  }
  if (!loading && _loadProgress != 1) {
    self.loadProgress = 1;
  }
  RoomLifecycleState state = _contents->WasDiscarded()
                                 ? RoomLifecycleStateDiscarded
                                 : RoomLifecycleStateActive;
  if (auto* unit = resource_coordinator::TabLifecycleUnitExternal::
          FromWebContents(_contents)) {
    switch (unit->GetTabState()) {
      case ::mojom::LifecycleUnitState::DISCARDED:
        state = RoomLifecycleStateDiscarded;
        break;
      case ::mojom::LifecycleUnitState::FROZEN:
        state = RoomLifecycleStateFrozen;
        break;
      default:
        state = RoomLifecycleStateActive;
        break;
    }
  }
  if (state != _lifecycleState) {
    LOG(WARNING) << "RoomCore: page lifecycle " << static_cast<int>(_lifecycleState)
              << " -> " << static_cast<int>(state);
    self.lifecycleState = state;
  }
}

- (void)room_webContentsDestroyed {
  [self willChangeValueForKey:@"nativeView"];
  _observer.reset();
  _contents = nullptr;
  [self didChangeValueForKey:@"nativeView"];
  self.loading = NO;
  self.audible = NO;
  self.canGoBack = NO;
  self.canGoForward = NO;
  self.closed = YES;
}

- (void)loadURL:(NSURL*)URL {
  [self loadURL:URL transition:RoomPageTransitionTyped fromAddressBar:YES];
}

- (void)loadURL:(NSURL*)URL
        transition:(RoomPageTransition)transition
    fromAddressBar:(BOOL)fromAddressBar {
  if (!_contents) {
    return;
  }
  content::NavigationController::LoadURLParams params(net::GURLWithNSURL(URL));
  int type = FromRoomTransition(transition);
  if (fromAddressBar) {
    type |= ui::PAGE_TRANSITION_FROM_ADDRESS_BAR;
  }
  params.transition_type = ui::PageTransitionFromInt(type);
  _contents->GetController().LoadURLWithParams(params);
}

- (void)goBack {
  if (_contents && _contents->GetController().CanGoBack()) {
    _contents->GetController().GoBack();
  }
}

- (void)goForward {
  if (_contents && _contents->GetController().CanGoForward()) {
    _contents->GetController().GoForward();
  }
}

- (void)reload {
  if (_contents) {
    _contents->GetController().Reload(content::ReloadType::NORMAL,
                                      /*check_for_repost=*/true);
  }
}

- (void)reloadIgnoringCache {
  if (_contents) {
    _contents->GetController().Reload(content::ReloadType::BYPASSING_CACHE,
                                      /*check_for_repost=*/true);
  }
}

- (void)stop {
  if (_contents) {
    _contents->Stop();
  }
}

- (void)focus {
  if (_contents) {
    _contents->Focus();
  }
}

- (void)exitFullscreen {
  if (_contents) {
    // The host may not resize the page when it leaves (it never went edge
    // to edge): ask for the renderer update now.
    _contents->ExitFullscreen(/*will_cause_resize=*/false);
  }
}

- (void)close {
  if (!_contents) {
    return;
  }
  if (_owned) {
    // Still ours: destroying it fires WebContentsDestroyed.
    _owned.reset();
    return;
  }
  // In a tab strip: the strip closes it.
  for (BrowserWindowInterface* browser :
       GetAllBrowserWindowInterfaces()) {
    TabStripModel* strip = browser->GetTabStripModel();
    const int index = strip->GetIndexOfWebContents(_contents);
    if (index != TabStripModel::kNoTab) {
      strip->CloseWebContentsAt(index, TabCloseTypes::CLOSE_NONE);
      return;
    }
  }
}

@end
