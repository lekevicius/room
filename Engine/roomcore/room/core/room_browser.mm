// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/public/RoomBrowser.h"

#include <memory>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/web_contents.h"
#import "room/browser/room_browser_window.h"
#import "room/core/room_profile_internal.h"
#import "room/core/room_web_contents_internal.h"

@interface RoomBrowser ()
- (void)room_activeContentsChanged:(content::WebContents*)contents;
- (void)room_windowWillClose;
- (void)room_windowDestroyed;
@end

namespace {

class Client : public room::RoomBrowserWindowClient {
 public:
  explicit Client(RoomBrowser* browser) : browser_(browser) {}

  void OnActiveContentsChanged(content::WebContents* contents) override {
    [browser_ room_activeContentsChanged:contents];
  }
  void OnBrowserWindowWillClose() override { [browser_ room_windowWillClose]; }
  void OnBrowserWindowDestroyed() override { [browser_ room_windowDestroyed]; }

 private:
  RoomBrowser* __weak browser_;
};

}  // namespace

@implementation RoomBrowser {
  RoomProfile* _profile;
  NSWindow* __weak _window;
  raw_ptr<Browser> _browser;
  std::unique_ptr<Client> _client;
  // Wrappers of the pages in the tab strip, so KVO observers the host set up
  // survive as long as the page does.
  NSMutableArray<RoomWebContents*>* _pages;
  RoomWebContents* __weak _activeWebContents;
}

- (instancetype)initWithProfile:(RoomProfile*)profile window:(NSWindow*)window {
  if ((self = [super init])) {
    Profile* chromeProfile = profile.room_profile;
    CHECK(chromeProfile) << "RoomBrowser on a destroyed profile";
    _profile = profile;
    _window = window;
    _pages = [NSMutableArray array];
    _client = std::make_unique<Client>(self);

    room::ScopedPendingHostWindow pending(window, _client.get());
    BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                     *chromeProfile,
                                     /*from_user_gesture=*/true);
    _browser = Browser::Create(std::move(params));
  }
  return self;
}

- (void)dealloc {
  // The Browser outlives its wrapper only if the host drops it without
  // closing; the window must not call back into a dead object.
  _client.reset();
}

- (RoomProfile*)profile {
  return _profile;
}

- (NSWindow*)window {
  return _window;
}

- (BOOL)isClosed {
  return _browser == nullptr;
}

- (NSArray<RoomWebContents*>*)webContents {
  NSMutableArray<RoomWebContents*>* result = [NSMutableArray array];
  if (!_browser) {
    return result;
  }
  TabStripModel* strip = _browser->tab_strip_model();
  for (int i = 0; i < strip->count(); ++i) {
    if (RoomWebContents* wrapper = [RoomWebContents
            room_existingWrapperFor:strip->GetWebContentsAt(i)]) {
      [result addObject:wrapper];
    }
  }
  return result;
}

- (RoomWebContents*)activeWebContents {
  return _activeWebContents;
}

- (void)addWebContents:(RoomWebContents*)webContents activate:(BOOL)activate {
  CHECK(_browser) << "addWebContents on a closed browser";
  std::unique_ptr<content::WebContents> owned =
      [webContents room_releaseWebContents];
  CHECK(owned) << "the page already belongs to a browser";
  [_pages addObject:webContents];
  _browser->tab_strip_model()->AppendWebContents(std::move(owned), activate);
}

- (void)close {
  if (_browser) {
    chrome::CloseWindow(_browser);
  }
}

- (void)room_activeContentsChanged:(content::WebContents*)contents {
  RoomWebContents* wrapper = [RoomWebContents room_existingWrapperFor:contents];
  [self willChangeValueForKey:@"activeWebContents"];
  _activeWebContents = wrapper;
  [self didChangeValueForKey:@"activeWebContents"];
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browser:didActivateWebContents:)]) {
    [delegate browser:self didActivateWebContents:wrapper];
  }
}

- (void)room_windowWillClose {
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserWillClose:)]) {
    [delegate browserWillClose:self];
  }
}

- (void)room_windowDestroyed {
  [self willChangeValueForKey:@"closed"];
  _browser = nullptr;
  [self didChangeValueForKey:@"closed"];
  [_pages removeAllObjects];
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserDidClose:)]) {
    [delegate browserDidClose:self];
  }
}

@end
