// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/public/RoomBrowser.h"

#include <memory>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "base/functional/bind.h"
#include "chrome/browser/ui/webid/identity_dialog_controller.h"
#include "third_party/blink/public/mojom/webid/federated_request.mojom.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/permissions/permission_request_manager.h"
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
  raw_ptr<BrowserWindowInterface> _browser;
  std::unique_ptr<Client> _client;
  std::unique_ptr<IdentityDialogController> _spike_identity_controller;
  // Wrappers of the pages in the tab strip, so KVO observers the host set up
  // survive as long as the page does.
  NSMutableArray<RoomWebContents*>* _pages;
  RoomWebContents* __weak _activeWebContents;
}

@synthesize delegate = _delegate;

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
    _browser = CreateBrowserWindow(std::move(params));
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
  TabStripModel* strip = _browser->GetTabStripModel();
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
  _browser->GetTabStripModel()->AppendWebContents(std::move(owned), activate);
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
  _spike_identity_controller.reset();
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

// Spike-only entry point; intentionally absent from the public API.
- (NSNumber*)roomSpikeCommand:(NSNumber*)command {
  if (!_browser ||
      ![[NSProcessInfo processInfo].arguments containsObject:@"-RoomSpike"]) {
    return @NO;
  }
  const int command_id = command.intValue;
  switch (command_id) {
    case IDC_FIND:
    case IDC_FIND_NEXT:
    case IDC_CLOSE_FIND_OR_STOP:
    case IDC_ZOOM_PLUS:
    case IDC_ZOOM_MINUS:
    case IDC_ZOOM_NORMAL:
    case IDC_PRINT:
      if (!chrome::IsCommandEnabled(_browser, command_id)) {
        return @NO;
      }
      return @(chrome::ExecuteCommand(_browser, command_id));
    default:
      return @NO;
  }
}

// Bounded fixture actions use Chrome's real completion paths, not synthetic
// web permission overrides. Kept private and disabled outside spike runs.
- (NSNumber*)roomSpikeAction:(NSString*)action {
  if (!_browser ||
      ![[NSProcessInfo processInfo].arguments containsObject:@"-RoomSpike"]) {
    return @(-1);
  }
  auto* contents = _browser->GetTabStripModel()->GetActiveWebContents();
  if (!contents || contents->GetVisibleURL().host() != "127.0.0.1") {
    return @(-1);
  }
  if ([action isEqualToString:@"renderer-status"]) {
    int status = contents->IsCrashed() ? 1 : 0;
    for (NSView* view in contents->GetNativeView().GetNativeNSView().subviews) {
      if ([view.identifier isEqualToString:@"RoomSadTab"]) {
        status |= 2;
      }
    }
    return @(status);
  }
  if ([action isEqualToString:@"fedcm-close"]) {
    _spike_identity_controller.reset();
    return @1;
  }
  if ([action isEqualToString:@"fedcm-passive"] ||
      [action isEqualToString:@"fedcm-active"]) {
    _spike_identity_controller = std::make_unique<IdentityDialogController>(contents);
    content::IdentityProviderMetadata metadata;
    metadata.idp_login_url = contents->GetVisibleURL();
    if ([action isEqualToString:@"fedcm-active"]) {
      return @(_spike_identity_controller->ShowLoadingDialog(
          content::RelyingPartyData(u"RoomCore fixture", u""), "Local IdP",
          blink::mojom::RpContext::kSignIn, blink::mojom::RpMode::kActive,
          base::BindOnce([](content::IdentityRequestDialogController::DismissReason) {})));
    }
    return @(_spike_identity_controller->ShowFailureDialog(
        content::RelyingPartyData(u"RoomCore fixture", u""), "Local IdP",
        blink::mojom::RpContext::kSignIn,
        blink::mojom::RpMode::kPassive,
        metadata, {},
        base::BindOnce([](content::IdentityRequestDialogController::DismissReason) {}),
        base::BindRepeating([](const GURL&, GURL) {})));
  }
  if ([action isEqualToString:@"deny-permission"]) {
    auto* manager = permissions::PermissionRequestManager::FromWebContents(contents);
    if (!manager || !manager->IsRequestInProgress()) {
      return @0;
    }
    manager->Deny(std::monostate{});
    return @1;
  }
  if ([action isEqualToString:@"auth-cancel"] ||
      [action isEqualToString:@"auth-supply"]) {
    for (auto* handler : LoginHandler::GetAllLoginHandlersForTest()) {
      if (handler->web_contents() == contents) {
        if ([action isEqualToString:@"auth-cancel"]) {
          handler->CancelAuth(false);
        } else {
          handler->SetAuth(u"room", u"spike");
        }
        return @1;
      }
    }
    return @0;
  }
  auto* find = find_in_page::FindTabHelper::FromWebContents(contents);
  if (find && [action isEqualToString:@"find-row"]) {
    find->StartFinding(u"Row", true, false, true);
    return @1;
  }
  if (find && [action isEqualToString:@"find-count"]) {
    return @(find->find_result().final_update() &&
                     find->find_result().request_id() == find->current_find_request_id()
                 ? find->find_result().number_of_matches() : -1);
  }
  return @(-1);
}

@end
