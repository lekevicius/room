// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_web_contents_internal.h"

#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/pickle.h"
#include "base/process/kill.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "base/values.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/performance_manager/policies/cannot_discard_reason.h"
#include "chrome/browser/performance_manager/policies/discard_eligibility_policy.h"
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
#include "components/performance_manager/public/performance_manager.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "components/sessions/core/session_constants.h"
#include "chrome/common/chrome_version.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_details.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/restore_type.h"
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
#include "room/core/content_blocking/cosmetic_filter_tab_helper.h"
#include "room/core/content_blocking/network_blocking.h"
#import "room/core/room_browser_internal.h"
#import "room/core/room_page_ui_internal.h"
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
@property(nonatomic, readwrite) NSInteger blockedRequestCount;
@property(nonatomic, readwrite) RoomLifecycleState lifecycleState;
@property(nonatomic, readwrite) RoomCaptureState captureState;
@property(nonatomic, readwrite, nullable) RoomMediaSessionInfo* mediaSession;
- (void)room_refresh;
- (void)room_refreshColors;
- (void)room_refreshSecurity;
- (void)room_refreshFavicon;
- (void)room_setLoadProgress:(double)progress;
- (void)room_setAudible:(BOOL)audible;
- (void)room_blockedRequestCountChanged:(int)count;
- (void)room_cookieBannerHandled:(const std::string&)platform optedOut:(bool)optedOut;
- (void)room_mutingChanged;
- (void)room_zoomChanged;
- (void)room_didFinishNavigation:(content::NavigationHandle*)handle;
- (void)room_navigationStateChanged;
- (void)room_webContentsDestroyed;
- (void)room_shownOrFocused;
- (void)room_renderProcessGone:(base::TerminationStatus)status;
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

// Room's blocker on every Room page (B-30): the per-document cosmetic push
// and the blocked-request count (the proxy decides on its own).
void AttachContentBlocking(content::WebContents* contents) {
  room::CosmeticFilterTabHelper::CreateForWebContents(contents);
  room::BlockedRequestCounter::CreateForWebContents(contents);
}

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
    [wrapper_ room_navigationStateChanged];
  }
  void NavigationListPruned(const content::PrunedDetails&) override {
    [wrapper_ room_refresh];
    [wrapper_ room_navigationStateChanged];
  }
  // A title, a favicon or the renderer's page state (scroll position, form
  // contents) of an entry: what -navigationState saves changed.
  void NavigationEntryChanged(const content::EntryChangedDetails&) override {
    [wrapper_ room_navigationStateChanged];
  }
  void NavigationEntriesDeleted() override {
    [wrapper_ room_refresh];
    [wrapper_ room_navigationStateChanged];
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
  void PrimaryMainFrameRenderProcessGone(
      base::TerminationStatus status) override {
    [wrapper_ room_renderProcessGone:status];
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


// -navigationState's format: a header, then Chromium's own serialisation of
// each entry (SerializedNavigationEntry::WriteToPickle, what Chrome's session
// and tab-restore files hold).
constexpr char kNavigationStateMagic[] = "RoomNavigationState";
constexpr int kNavigationStateFormat = 1;
// Per entry, as Chrome's session commands (base_session_service_commands.cc:
// "navigations up to 63k"): a larger page state is left out, the entry kept.
constexpr int kMaxSerializedEntryBytes = 63 * 1024;
// More than a session ever writes (sessions::gMaxPersistNavigationCount each
// side of the current entry): anything above is damage.
constexpr int kMaxRestoredEntries = 64;

// Room pages are discarded by the host alone (its idle and memory-pressure
// policy, which asks -discardBlockers first): performance_manager's own
// urgent and proactive discarding skip a page that is not auto-discardable
// (CanDiscard: kExtensionProtected, protected; DiscardAPage passes
// discard_protected_tabs = false). The unit exists once the page is in a tab
// strip (tabs::TabModel's helpers), and a discard's replacement gets a new one.
void MarkNotAutoDiscardable(content::WebContents* contents) {
  auto* unit = contents ? resource_coordinator::TabLifecycleUnitExternal::
                              FromWebContents(contents)
                        : nullptr;
  if (unit && unit->IsAutoDiscardable()) {
    unit->SetAutoDiscardable(false);
  }
}

// Chrome's reasons not to discard a page, as the host's blockers. Reasons
// the host decides itself are left out: visibility and the active tab (the
// host never discards what it shows), the recent-visibility window (its own
// idle clock), Chrome's pinned tabs (Room has none), background title or
// favicon updates (Chrome's proactive heuristic), and the extension
// protection RoomCore sets on every Room page (not auto-discardable, so
// performance_manager never discards one behind the host).
RoomDiscardBlockers ToRoomBlockers(
    const std::vector<performance_manager::policies::CannotDiscardReason>&
        reasons) {
  using Reason = performance_manager::policies::CannotDiscardReason;
  RoomDiscardBlockers blockers = 0;
  for (Reason reason : reasons) {
    switch (reason) {
      case Reason::kFormInteractions:
        blockers |= RoomDiscardBlockersFormInteractions;
        break;
      case Reason::kUserEdits:
        blockers |= RoomDiscardBlockersUserEdits;
        break;
      case Reason::kPictureInPicture:
        blockers |= RoomDiscardBlockersPictureInPicture;
        break;
      case Reason::kAudible:
        blockers |= RoomDiscardBlockersAudible;
        break;
      case Reason::kRecentlyAudible:
        blockers |= RoomDiscardBlockersRecentlyAudible;
        break;
      case Reason::kCapturingVideo:
      case Reason::kCapturingAudio:
      case Reason::kCapturingWindow:
      case Reason::kCapturingDisplay:
      case Reason::kBeingMirrored:
        blockers |= RoomDiscardBlockersCapturing;
        break;
      case Reason::kNotificationsEnabled:
        blockers |= RoomDiscardBlockersNotifications;
        break;
      case Reason::kDevToolsOpen:
        blockers |= RoomDiscardBlockersDevTools;
        break;
      case Reason::kConnectedToUSB:
      case Reason::kConnectedToBluetooth:
        blockers |= RoomDiscardBlockersConnectedDevice;
        break;
      case Reason::kVisible:
      case Reason::kRecentlyVisible:
      case Reason::kActiveTab:
      case Reason::kPinnedTab:
      case Reason::kBackgroundActivity:
      case Reason::kExtensionProtected:
      case Reason::kGlicShared:
        break;
      case Reason::kNotATab:
      case Reason::kAlreadyDiscarded:
      case Reason::kDiscardAttempted:
      case Reason::kNoMainFrame:
      case Reason::kPdf:
      case Reason::kNotWebOrInternal:
      case Reason::kInvalidURL:
      case Reason::kOptedOut:
      case Reason::kWebApp:
        blockers |= RoomDiscardBlockersOther;
        break;
    }
  }
  return blockers;
}

}  // namespace

namespace room {

void InstallWebContentsHooks() {
  BlockedRequestCounter::SetChangedCallback(
      base::BindRepeating([](content::WebContents* contents, int count) {
        [[RoomWebContents room_existingWrapperFor:contents]
            room_blockedRequestCountChanged:count];
      }));
  CosmeticFilterTabHelper::SetCookieBannerCallback(base::BindRepeating(
      [](content::WebContents* contents, const std::string& platform,
         bool opted_out) {
        [[RoomWebContents room_existingWrapperFor:contents]
            room_cookieBannerHandled:platform
                            optedOut:opted_out];
      }));
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
  // A navigation-state change is posted for the end of this turn.
  BOOL _navigationStatePending;
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
@synthesize blockedRequestCount = _blockedRequestCount;
@synthesize lifecycleState = _lifecycleState;
@synthesize captureState = _captureState;
@synthesize mediaSession = _mediaSession;

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
    AttachContentBlocking(_contents);
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
    AttachContentBlocking(_contents);
    _observer = std::make_unique<Observer>(_contents, self);
    // Chrome inserted it into a tab strip: its tab helpers exist.
    _observer->ObserveTabHelpers();
    room::AttachPageServices(_contents);
    MarkNotAutoDiscardable(_contents);
    [self room_refresh];
    [self room_refreshColors];
    [self room_refreshSecurity];
    [self room_refreshFavicon];
  }
  return self;
}

- (instancetype)initWithHostedChromeWebContents:
                    (content::WebContents*)webContents
                                        profile:(RoomProfile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    _contents = webContents;
    _title = @"";
    _loadProgress = 1;
    UnhideNativeView(_contents);
    WrapperLink::CreateForWebContents(_contents, self);
    AttachContentBlocking(_contents);
    _observer = std::make_unique<Observer>(_contents, self);
    [self room_refresh];
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

- (void)room_renderProcessGone:(base::TerminationStatus)status {
  RoomTerminationStatus mapped = RoomTerminationStatusAbnormal;
  switch (status) {
    case base::TERMINATION_STATUS_NORMAL_TERMINATION:
      mapped = RoomTerminationStatusNormal;
      break;
    case base::TERMINATION_STATUS_PROCESS_WAS_KILLED:
      mapped = RoomTerminationStatusKilled;
      break;
    case base::TERMINATION_STATUS_PROCESS_CRASHED:
      mapped = RoomTerminationStatusCrashed;
      break;
    case base::TERMINATION_STATUS_OOM:
      mapped = RoomTerminationStatusOutOfMemory;
      break;
    case base::TERMINATION_STATUS_LAUNCH_FAILED:
      mapped = RoomTerminationStatusLaunchFailed;
      break;
    // INTEGRITY_FAILURE exists on Windows only.
    default:
      break;
  }
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(webContents:renderProcessGone:)]) {
    [delegate webContents:self renderProcessGone:mapped];
  }
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

- (void)room_requestFocusOnLocationBar {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector
                (webContentsDidRequestFocusOnLocationBar:)]) {
    [delegate webContentsDidRequestFocusOnLocationBar:self];
  }
}

- (NSRect)room_bubbleAnchorRect {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if (![delegate respondsToSelector:@selector(webContentsBubbleAnchorRect:)]) {
    return NSZeroRect;
  }
  return [delegate webContentsBubbleAnchorRect:self];
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
  room::AttachPageServices(_contents);
  MarkNotAutoDiscardable(_contents);
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
  AttachContentBlocking(_contents);
  _observer = std::make_unique<Observer>(_contents, self);
  _observer->ObserveTabHelpers();
  MarkNotAutoDiscardable(_contents);
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

- (void)room_blockedRequestCountChanged:(int)count {
  if (count != _blockedRequestCount) {
    self.blockedRequestCount = count;
  }
}

- (void)room_cookieBannerHandled:(const std::string&)platform
                        optedOut:(bool)optedOut {
  id<RoomWebContentsDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector
                (webContents:didHandleCookieBannerOfPlatform:optedOut:)]) {
    [delegate webContents:self
        didHandleCookieBannerOfPlatform:base::SysUTF8ToNSString(platform)
                               optedOut:optedOut];
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

- (RoomDiscardBlockers)discardBlockers {
  using performance_manager::PerformanceManager;
  using performance_manager::policies::DiscardEligibilityPolicy;
  if (!_contents || !PerformanceManager::IsAvailable()) {
    return RoomDiscardBlockersOther;
  }
  base::WeakPtr<performance_manager::PageNode> node =
      PerformanceManager::GetPrimaryPageNodeForWebContents(_contents);
  DiscardEligibilityPolicy* policy =
      DiscardEligibilityPolicy::GetFromGraph(PerformanceManager::GetGraph());
  if (!node || !policy) {
    return RoomDiscardBlockersOther;
  }
  // PROACTIVE: the full list (URGENT leaves notifications out); the
  // recent-visibility window off, since the host's idle clock decides when.
  std::vector<performance_manager::policies::CannotDiscardReason> reasons;
  policy->CanDiscard(node.get(), DiscardEligibilityPolicy::DiscardReason::PROACTIVE,
                     /*ignore_recent_visibility=*/true, &reasons);
  const RoomDiscardBlockers blockers = ToRoomBlockers(reasons);
  if (VLOG_IS_ON(1) || blockers) {
    std::string names;
    for (auto reason : reasons) {
      names += std::string(names.empty() ? "" : ",") +
               performance_manager::policies::CannotDiscardReasonToString(reason);
    }
    LOG(INFO) << "RoomCore: discard blockers of "
              << _contents->GetVisibleURL().possibly_invalid_spec() << ": "
              << (names.empty() ? "none" : names) << " -> " << blockers;
  }
  return blockers;
}

- (void)room_navigationStateChanged {
  if (_navigationStatePending || !_contents) {
    return;
  }
  _navigationStatePending = YES;
  RoomWebContents* __weak weakSelf = self;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(^{
        RoomWebContents* strongSelf = weakSelf;
        if (!strongSelf) {
          return;
        }
        strongSelf->_navigationStatePending = NO;
        if (!strongSelf->_contents) {
          return;
        }
        id<RoomWebContentsDelegate> delegate = strongSelf.delegate;
        if ([delegate respondsToSelector:@selector
                      (webContentsDidChangeNavigationState:)]) {
          [delegate webContentsDidChangeNavigationState:strongSelf];
        }
      }));
}

- (NSData*)navigationState {
  if (!_contents) {
    return nil;
  }
  content::NavigationController& controller = _contents->GetController();
  const int current = controller.GetLastCommittedEntryIndex();
  const int count = controller.GetEntryCount();
  if (current < 0 || current >= count) {
    return nil;
  }
  // Chrome's session window: the current entry and up to
  // gMaxPersistNavigationCount on each side.
  const int first = std::max(0, current - sessions::gMaxPersistNavigationCount);
  const int last =
      std::min(count - 1, current + sessions::gMaxPersistNavigationCount);
  std::vector<sessions::SerializedNavigationEntry> navigations;
  int selected = -1;
  for (int i = first; i <= last; ++i) {
    content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
    if (!entry || entry->IsInitialEntry() || !entry->GetVirtualURL().is_valid()) {
      continue;
    }
    if (i == current) {
      selected = static_cast<int>(navigations.size());
    }
    navigations.push_back(
        sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(
            i, entry));
  }
  if (navigations.empty() || selected < 0) {
    return nil;
  }
  base::Pickle pickle;
  pickle.WriteString(kNavigationStateMagic);
  pickle.WriteInt(kNavigationStateFormat);
  pickle.WriteString(CHROME_VERSION_STRING);
  pickle.WriteInt(selected);
  pickle.WriteInt(static_cast<int>(navigations.size()));
  for (const auto& navigation : navigations) {
    navigation.WriteToPickle(kMaxSerializedEntryBytes, &pickle);
  }
  return [NSData dataWithBytes:pickle.data() length:pickle.size()];
}

- (BOOL)restoreNavigationState:(NSData*)state {
  if (!_contents || state.length == 0) {
    return NO;
  }
  content::NavigationController& controller = _contents->GetController();
  content::NavigationEntry* committed = controller.GetLastCommittedEntry();
  if (controller.GetPendingEntry() || controller.GetEntryCount() > 1 ||
      (committed && !committed->IsInitialEntry())) {
    LOG(WARNING) << "RoomCore: navigation state not restored: the page has "
                    "loaded already";
    return NO;
  }
  const base::Pickle pickle =
      base::Pickle::WithUnownedBuffer(base::apple::NSDataToSpan(state));
  base::PickleIterator iterator(pickle);
  std::string magic;
  std::string version;
  int format = 0;
  int selected = -1;
  int count = 0;
  if (!iterator.ReadString(&magic) || magic != kNavigationStateMagic ||
      !iterator.ReadInt(&format) || format != kNavigationStateFormat ||
      !iterator.ReadString(&version) || !iterator.ReadInt(&selected) ||
      !iterator.ReadInt(&count) || count <= 0 || count > kMaxRestoredEntries ||
      selected < 0 || selected >= count) {
    LOG(WARNING) << "RoomCore: navigation state not restored: unreadable "
                    "header ("
                 << state.length << " bytes)";
    return NO;
  }
  std::vector<sessions::SerializedNavigationEntry> navigations(count);
  for (auto& navigation : navigations) {
    if (!navigation.ReadFromPickle(&iterator)) {
      LOG(WARNING) << "RoomCore: navigation state written by Chromium "
                   << version << " not restored by " << CHROME_VERSION_STRING
                   << ": an entry does not read";
      return NO;
    }
  }
  if (version != CHROME_VERSION_STRING) {
    LOG(WARNING) << "RoomCore: navigation state written by Chromium " << version
                 << ", restored by " << CHROME_VERSION_STRING;
  }
  std::vector<std::unique_ptr<content::NavigationEntry>> entries =
      sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(
          navigations, _contents->GetBrowserContext());
  controller.Restore(selected, content::RestoreType::kRestored, &entries);
  [self room_refresh];
  return YES;
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
  if (!_contents) {
    return;
  }
  content::NavigationController& controller = _contents->GetController();
  if (controller.NeedsReload()) {
    // Restored (-restoreNavigationState:) or discarded: load the current
    // entry with its page state, as Chrome does when it shows the tab.
    controller.LoadIfNecessary();
    return;
  }
  controller.Reload(content::ReloadType::NORMAL, /*check_for_repost=*/true);
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

- (void)room_setCaptureState:(RoomCaptureState)state {
  if (state != _captureState) {
    self.captureState = state;
  }
}

- (void)room_setMediaSession:(RoomMediaSessionInfo*)info {
  if (info == _mediaSession || [info isEqual:_mediaSession]) {
    return;
  }
  LOG(INFO) << "RoomCore: media session "
            << (info ? base::SysNSStringToUTF8(info.description) : "none");
  self.mediaSession = info;
}

- (void)stopCapturing:(RoomCaptureKinds)kinds {
  room::StopCapturing(_contents, kinds);
}

// The media session's controls: what Chrome's global media controls and the
// system's media keys call (content::MediaSession, a UI suspend type).
- (void)mediaPlay {
  if (_contents) {
    LOG(INFO) << "RoomCore: media play";
    content::MediaSession::Get(_contents)->Resume(
        content::MediaSession::SuspendType::kUI);
  }
}

- (void)mediaPause {
  if (_contents) {
    LOG(INFO) << "RoomCore: media pause";
    content::MediaSession::Get(_contents)->Suspend(
        content::MediaSession::SuspendType::kUI);
  }
}

- (void)mediaNextTrack {
  if (_contents) {
    LOG(INFO) << "RoomCore: media next track";
    content::MediaSession::Get(_contents)->NextTrack();
  }
}

- (void)mediaPreviousTrack {
  if (_contents) {
    LOG(INFO) << "RoomCore: media previous track";
    content::MediaSession::Get(_contents)->PreviousTrack();
  }
}

- (void)mediaSeekTo:(NSTimeInterval)seconds {
  if (_contents) {
    LOG(INFO) << "RoomCore: media seek to " << seconds;
    content::MediaSession::Get(_contents)->SeekTo(
        base::Seconds(std::max(0.0, seconds)));
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
