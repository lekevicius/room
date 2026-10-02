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
#include "net/base/apple/url_conversions.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#import "room/core/room_profile_internal.h"

@interface RoomWebContents ()
@property(nonatomic, readwrite, copy, nullable) NSURL* URL;
@property(nonatomic, readwrite, copy) NSString* title;
@property(nonatomic, readwrite, getter=isLoading) BOOL loading;
@property(nonatomic, readwrite) BOOL canGoBack;
@property(nonatomic, readwrite) BOOL canGoForward;
@property(nonatomic, readwrite, getter=isClosed) BOOL closed;
- (void)room_refresh;
- (void)room_webContentsDestroyed;
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
  void WebContentsDestroyed() override {
    [wrapper_ room_webContentsDestroyed];
  }

 private:
  RoomWebContents* __weak wrapper_;
};

}  // namespace

@implementation RoomWebContents {
  RoomProfile* _profile;
  // Set while the wrapper owns the page (before it joins a tab strip).
  std::unique_ptr<content::WebContents> _owned;
  raw_ptr<content::WebContents> _contents;
  std::unique_ptr<Observer> _observer;
}

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
