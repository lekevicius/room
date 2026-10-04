// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_web_contents_internal.h"

#include <memory>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "content/public/browser/visibility.h"
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
}  // namespace room

@interface RoomWebContents ()
@property(nonatomic, readwrite, copy, nullable) NSURL* URL;
@property(nonatomic, readwrite, copy) NSString* title;
@property(nonatomic, readwrite, getter=isLoading) BOOL loading;
@property(nonatomic, readwrite) BOOL canGoBack;
@property(nonatomic, readwrite) BOOL canGoForward;
@property(nonatomic, readwrite, getter=isClosed) BOOL closed;
- (void)room_refresh;
- (void)room_webContentsDestroyed;
- (void)room_shownOrFocused;
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

// Turns WebContentsObserver events into KVO changes on the wrapper.
class Observer : public content::WebContentsObserver {
 public:
  Observer(content::WebContents* contents, RoomWebContents* wrapper)
      : content::WebContentsObserver(contents), wrapper_(wrapper) {}

  void DidStartLoading() override { [wrapper_ room_refresh]; }
  void DidStopLoading() override { [wrapper_ room_refresh]; }
  void DidStartNavigation(content::NavigationHandle*) override {
    [wrapper_ room_refresh];
  }
  void DidFinishNavigation(content::NavigationHandle*) override {
    [wrapper_ room_refresh];
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
  // The host showed the page (its view is in a visible window) or the user
  // focused it (a click into a split pane): it is the active tab now.
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::VISIBLE) {
      [wrapper_ room_shownOrFocused];
    }
  }
  void OnWebContentsFocused(content::RenderWidgetHost*) override {
    [wrapper_ room_shownOrFocused];
  }
  void WebContentsDestroyed() override {
    [wrapper_ room_webContentsDestroyed];
  }

 private:
  RoomWebContents* __weak wrapper_;
};

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
}

@synthesize delegate = _delegate;

@synthesize URL = _URL;
@synthesize title = _title;
@synthesize loading = _loading;
@synthesize canGoBack = _canGoBack;
@synthesize canGoForward = _canGoForward;
@synthesize closed = _closed;

- (instancetype)initWithChromeWebContents:
                    (std::unique_ptr<content::WebContents>)webContents
                                 profile:(RoomProfile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    _owned = std::move(webContents);
    _contents = _owned.get();
    _title = @"";
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
    WrapperLink::CreateForWebContents(_contents, self);
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
}

- (void)room_webContentsDestroyed {
  [self willChangeValueForKey:@"nativeView"];
  _observer.reset();
  _contents = nullptr;
  [self didChangeValueForKey:@"nativeView"];
  self.loading = NO;
  self.canGoBack = NO;
  self.canGoForward = NO;
  self.closed = YES;
}

- (void)loadURL:(NSURL*)URL {
  if (!_contents) {
    return;
  }
  content::NavigationController::LoadURLParams params(net::GURLWithNSURL(URL));
  params.transition_type = ui::PageTransitionFromInt(
      ui::PAGE_TRANSITION_TYPED | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
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
