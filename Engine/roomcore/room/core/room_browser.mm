// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_browser_internal.h"

#include <memory>
#include <set>
#include <string>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "base/logging.h"
#include "base/strings/sys_string_conversions.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "content/public/browser/permission_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/service_worker_context.h"
#include "content/public/browser/service_worker_running_info.h"
#include "content/public/browser/storage_partition.h"
#include "services/network/public/cpp/features.h"
#include "third_party/blink/public/common/permissions/permission_utils.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/ui/views/extensions/extension_popup.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "components/permissions/permission_request.h"
#include "base/memory/ref_counted_memory.h"
#include "base/functional/bind.h"
#include "base/memory/memory_pressure_listener.h"
#include "chrome/browser/performance_manager/policies/discard_eligibility_policy.h"
#include "chrome/browser/performance_manager/policies/page_discarding_helper.h"
#include "chrome/browser/resource_coordinator/tab_lifecycle_unit_external.h"
#include "components/performance_manager/public/performance_manager.h"
#include "chrome/browser/ui/webid/identity_dialog_controller.h"
#include "third_party/blink/public/mojom/webid/federated_request.mojom.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/printing/print_preview_dialog_controller.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "components/omnibox/browser/location_bar_model.h"
#include "chrome/browser/ui/webui/print_preview/print_preview_ui.h"
#include "content/public/browser/web_ui.h"
#include "printing/print_job_constants.h"
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/download_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "base/task/single_thread_task_runner.h"
#include "components/tabs/public/tab_interface.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/window_open_disposition.h"
#include "chrome/browser/ui/autofill/address_bubbles_controller.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/ui/autofill/chrome_autofill_client.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/tab_dialogs.h"
#include "chrome/browser/ui/views/passwords/password_bubble_view_base.h"
#include "chrome/browser/ui/passwords/passwords_model_delegate.h"
#include "components/password_manager/core/common/password_manager_ui.h"
#include "chrome/browser/ui/views/frame/toolbar_button_provider.h"
#include "components/autofill/core/browser/data_manager/personal_data_manager.h"
#include "components/autofill/content/browser/content_autofill_driver.h"
#include "components/autofill/core/browser/foundations/autofill_manager.h"
#include "components/autofill/core/browser/form_structure.h"
#include "content/public/browser/render_widget_host_view.h"
#include "components/autofill/core/browser/data_model/payments/credit_card.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/permissions/permission_request_manager.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/views/widget/widget.h"
#include "ui/views/window/dialog_delegate.h"
#include "room/build/buildflags.h"
#import "room/browser/room_browser_window.h"
#import "room/core/room_extension_popups.h"
#import "room/core/room_profile_internal.h"
#import "room/core/room_web_contents_internal.h"

@interface RoomBrowser ()
- (void)room_activeContentsChanged:(content::WebContents*)contents;
- (void)room_windowWillClose;
- (void)room_windowDestroyed;
- (void)room_tabFullscreenEntered:(content::WebContents*)contents
                           origin:(const url::Origin&)origin;
- (void)room_tabFullscreenExited:(content::WebContents*)contents;
- (void)room_tabStripChanged:(const TabStripModelChange&)change
                   selection:(const TabStripSelectionChange&)selection;
- (RoomWebContents*)room_wrapperFor:(content::WebContents*)contents;
- (void)room_focusLocationBarRequested;
- (void)room_toastRequested:(NSString*)kind;
- (NSRect)room_bubbleAnchorRect;
- (RoomWebContents*)room_keyTargetFor:(NSEvent*)event;
- (BOOL)room_handleExtensionKeyEvent:(const input::NativeWebKeyboardEvent&)event;
- (BrowserWindowInterface*)room_browserForOffTheRecord;
- (void)room_forgetPage:(RoomWebContents*)page;
- (void)room_insertDetachedTab:(std::unique_ptr<tabs::TabModel>)tab
                          page:(RoomWebContents*)page;
@end

namespace {

class Client : public room::RoomBrowserWindowClient {
 public:
  explicit Client(RoomBrowser* browser) : browser_(browser) {}

  void OnActiveContentsChanged(content::WebContents* contents) override {
    [browser_ room_activeContentsChanged:contents];
  }
  void OnActivationRequested(content::WebContents* contents) override {
    [[browser_ room_wrapperFor:contents] room_requestActivation];
  }
  void OnBrowserWindowWillClose() override { [browser_ room_windowWillClose]; }
  void OnBrowserWindowDestroyed() override { [browser_ room_windowDestroyed]; }
  void OnTabFullscreenEntered(content::WebContents* contents,
                              const url::Origin& origin) override {
    [browser_ room_tabFullscreenEntered:contents origin:origin];
  }
  void OnTabFullscreenExited(content::WebContents* contents) override {
    [browser_ room_tabFullscreenExited:contents];
  }
  bool IsReservedKeyEvent(const input::NativeWebKeyboardEvent& event) override {
    NSEvent* ns_event = event.os_event.Get();
    return [[browser_ room_keyTargetFor:ns_event] room_isReservedKeyEvent:ns_event];
  }
  bool HandleUnhandledKeyEvent(
      const input::NativeWebKeyboardEvent& event) override {
    NSEvent* ns_event = event.os_event.Get();
    return [[browser_ room_keyTargetFor:ns_event]
        room_handleUnhandledKeyEvent:ns_event];
  }
  bool HandleExtensionKeyEvent(
      const input::NativeWebKeyboardEvent& event) override {
    return [browser_ room_handleExtensionKeyEvent:event];
  }
  void OnFocusLocationBarRequested(bool is_user_initiated) override {
    [browser_ room_focusLocationBarRequested];
  }
  void OnToastRequested(std::string_view kind) override {
    [browser_ room_toastRequested:base::SysUTF8ToNSString(kind)];
  }
  std::optional<gfx::Rect> GetBubbleAnchorRect() override {
    const NSRect rect = [browser_ room_bubbleAnchorRect];
    if (NSIsEmptyRect(rect)) {
      return std::nullopt;
    }
    return gfx::ToEnclosingRect(gfx::RectF(NSRectToCGRect(rect)));
  }
  bool AllowOpenFromTab(const NavigateParams& params) override {
    return room::AllowOpenFromRoomPage(params);
  }
  BrowserWindowInterface* BrowserForOffTheRecord() override {
    return [browser_ room_browserForOffTheRecord];
  }
  void ConfirmCloseWithPendingDownloads(
      int download_count,
      base::OnceCallback<void(bool)> callback) override {
    RoomBrowser* browser = browser_;
    id<RoomBrowserDelegate> delegate = browser.delegate;
    if (![delegate respondsToSelector:@selector
                   (browser:shouldCloseWithPendingDownloads:completion:)]) {
      std::move(callback).Run(true);
      return;
    }
    auto pending =
        std::make_shared<base::OnceCallback<void(bool)>>(std::move(callback));
    [delegate browser:browser
        shouldCloseWithPendingDownloads:download_count
                             completion:^(BOOL proceed) {
                               if (*pending) {
                                 std::move(*pending).Run(proceed);
                               }
                             }];
  }

 private:
  RoomBrowser* __weak browser_;
};

// Sees Chrome insert the pages a Room page opened (Navigate() keeps every
// disposition in this Browser, patches/0014), so the host can place them.
class StripObserver : public TabStripModelObserver {
 public:
  explicit StripObserver(RoomBrowser* browser) : browser_(browser) {}

  void OnTabStripModelChanged(TabStripModel* tab_strip_model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override {
    [browser_ room_tabStripChanged:change selection:selection];
  }

 private:
  RoomBrowser* __weak browser_;
};

RoomWindowOpenDisposition ToRoomDisposition(WindowOpenDisposition disposition,
                                            bool active) {
  switch (disposition) {
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
    default:
      // Inserted outside Navigate() (an extension, a restore): by selection.
      return active ? RoomWindowOpenDispositionNewForegroundTab
                    : RoomWindowOpenDispositionNewBackgroundTab;
  }
}

}  // namespace

@implementation RoomBrowser {
  RoomProfile* _profile;
  NSWindow* __weak _window;
  raw_ptr<BrowserWindowInterface> _browser;
  std::unique_ptr<Client> _client;
  std::unique_ptr<StripObserver> _stripObserver;
  // The window's ExtensionsContainer, popup and extension shortcuts (3.6b).
  std::unique_ptr<room::RoomBrowserExtensions> _extensions;
  // Set while the host's own page goes into the strip (not a new page).
  BOOL _addingFromHost;
#if BUILDFLAG(ROOM_ENABLE_SPIKES)
  std::unique_ptr<IdentityDialogController> _spike_identity_controller;
  std::shared_ptr<int> _spike_address_decisions;
  std::shared_ptr<int> _spike_card_decisions;
#endif
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
    // Room's store restores the host's entries (Phase 2.1). Tracked by
    // Chrome's SessionService, the first Browser of a launch also restored
    // the previous launch's tabs into its strip (seen in the 3.2a tour:
    // duplicate Today tabs); 3.7b decides what SessionService records.
    params.omit_from_session_restore = true;
    _browser = CreateBrowserWindow(std::move(params));
    // Chrome's tab-modal dialogs (TabDialogManager) need the window's
    // primary Views widget at once, not only after a first web-modal dialog
    // made the modal host: an HTTP site whose HTTPS upgrade failed opens
    // Chrome's "ask before HTTP" dialog from a tab helper and CHECKed
    // without it (found in 3.3a).
    if (RoomBrowserWindow* chromeWindow = room::RoomBrowserWindowFor(_browser)) {
      chromeWindow->GetBubbleAnchor();
    }
    _stripObserver = std::make_unique<StripObserver>(self);
    _browser->GetTabStripModel()->AddObserver(_stripObserver.get());
    _extensions = room::RoomBrowserExtensions::Create(_browser);
  }
  return self;
}

- (room::RoomBrowserExtensions*)room_extensions {
  return _extensions.get();
}

- (BrowserWindowInterface*)room_browserInterface {
  RoomBrowserWindow* window =
      _browser ? room::RoomBrowserWindowFor(_browser) : nullptr;
  return window && !window->is_closing() ? _browser.get() : nullptr;
}

// patches/0014's off-the-record open from a page of this window (4.8b): the
// twin's Browser that receives it (RoomProfile finds or makes it).
- (BrowserWindowInterface*)room_browserForOffTheRecord {
  NSWindow* window = _window;
  return window ? [_profile room_offTheRecordBrowserForOpenFromWindow:window]
                : nullptr;
}

- (void)room_forgetPage:(RoomWebContents*)page {
  [_pages removeObject:page];
}

// A page another Browser of this profile detached for insertion
// (TabStripModel::DetachTabAtForInsertion: its WebContents, navigation
// controller and tab helpers): inserted at the end, not activated (the strip's
// active tab follows the host's view, as for any page).
- (void)room_insertDetachedTab:(std::unique_ptr<tabs::TabModel>)tab
                          page:(RoomWebContents*)page {
  CHECK(self.room_browserInterface) << "a page moved into a closed browser";
  [_pages addObject:page];
  page.room_browser = self;
  TabStripModel* strip = _browser->GetTabStripModel();
  _addingFromHost = YES;
  strip->InsertDetachedTabAt(strip->count(), std::move(tab),
                             AddTabTypes::ADD_NONE);
  _addingFromHost = NO;
  // Idempotent: the observers and Room's page services are per WebContents.
  [page room_tabHelpersAttached];
}

- (BOOL)room_handleExtensionKeyEvent:(const input::NativeWebKeyboardEvent&)event {
  return _extensions && _extensions->HandleKeyEvent(event);
}

- (void)dealloc {
  _extensions.reset();
  // The Browser outlives its wrapper only if the host drops it without
  // closing; the window must not call back into a dead object.
  _stripObserver.reset();
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
  webContents.room_browser = self;
  _addingFromHost = YES;
  _browser->GetTabStripModel()->AppendWebContents(std::move(owned), activate);
  _addingFromHost = NO;
  // tabs::TabModel attached Chrome's tab helpers on the way in.
  [webContents room_tabHelpersAttached];
}

// The wrapper of a page in the strip, created for pages Chrome inserted.
- (RoomWebContents*)room_wrapperFor:(content::WebContents*)contents {
  if (!contents) {
    return nil;
  }
  RoomWebContents* wrapper = [RoomWebContents room_existingWrapperFor:contents];
  if (!wrapper) {
    wrapper = [[RoomWebContents alloc] initWithUnownedChromeWebContents:contents
                                                                profile:_profile];
    [_pages addObject:wrapper];
  }
  if (!wrapper.room_browser) {
    wrapper.room_browser = self;
  }
  return wrapper;
}

// The page a key event belongs to: the one whose view holds the key
// window's first responder (a split shows several pages of one strip; the
// strip's active tab follows a click only on the next task), else the
// strip's active tab.
- (RoomWebContents*)room_keyTargetFor:(NSEvent*)event {
  if (!_browser) {
    return nil;
  }
  TabStripModel* strip = _browser->GetTabStripModel();
  NSResponder* responder = (event.window ?: NSApp.keyWindow).firstResponder;
  if ([responder isKindOfClass:NSView.class]) {
    for (int i = 0; i < strip->count(); ++i) {
      content::WebContents* contents = strip->GetWebContentsAt(i);
      NSView* view = contents->GetNativeView().GetNativeNSView();
      if (view && [(NSView*)responder isDescendantOf:view]) {
        return [RoomWebContents room_existingWrapperFor:contents];
      }
    }
  }
  return [RoomWebContents
      room_existingWrapperFor:strip->GetActiveWebContents()];
}

- (void)room_activateWebContents:(RoomWebContents*)webContents {
  RoomBrowser* __weak weakSelf = self;
  RoomWebContents* __weak weakPage = webContents;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(^{
        RoomBrowser* strongSelf = weakSelf;
        RoomWebContents* page = weakPage;
        if (!strongSelf || !page || !strongSelf->_browser ||
            !page.room_webContents) {
          return;
        }
        TabStripModel* strip = strongSelf->_browser->GetTabStripModel();
        const int index = strip->GetIndexOfWebContents(page.room_webContents);
        if (index == TabStripModel::kNoTab || index == strip->active_index() ||
            strip->closing_all()) {
          return;
        }
        strip->ActivateTabAt(index);
      }));
}

- (void)room_tabStripChanged:(const TabStripModelChange&)change
                   selection:(const TabStripSelectionChange&)selection {
  if (change.type() == TabStripModelChange::kReplaced) {
    // A discard swaps the page's WebContents for an empty one with the same
    // navigation entries: the wrapper (its observers, the key-ack observer,
    // the native view) moves along, so the old contents' destruction is not
    // the page closing.
    const TabStripModelChange::Replace* replace = change.GetReplace();
    RoomWebContents* page =
        [RoomWebContents room_existingWrapperFor:replace->old_contents];
    if (page) {
      [page room_replaceWebContents:replace->new_contents];
      [page room_tabHelpersAttached];
    }
    return;
  }
  if (change.type() != TabStripModelChange::kInserted || _addingFromHost ||
      !_browser) {
    return;
  }
  RoomBrowserWindow* window = room::RoomBrowserWindowFor(_browser);
  for (const auto& inserted : change.GetInsert()->contents) {
    content::WebContents* contents = inserted.contents;
    RoomWebContents* page = [self room_wrapperFor:contents];
    std::optional<room::PendingOpen> pending =
        window ? window->TakePendingOpen() : std::nullopt;
    const bool active = selection.new_contents == contents;
    RoomWindowOpenDisposition disposition = ToRoomDisposition(
        pending ? pending->disposition : WindowOpenDisposition::UNKNOWN, active);
    // The page that opened it: Navigate()'s source, else the tab's opener,
    // else the page that was active before.
    content::WebContents* opener =
        pending && pending->source ? pending->source.get() : nullptr;
    if (!opener) {
      TabStripModel* strip = _browser->GetTabStripModel();
      const int index = strip->GetIndexOfWebContents(contents);
      tabs::TabInterface* tab =
          index == TabStripModel::kNoTab ? nullptr : strip->GetOpenerOfTabAt(index);
      opener = tab ? tab->GetContents() : selection.old_contents.get();
    }
    RoomWebContents* openerPage =
        opener && opener != contents
            ? [RoomWebContents room_existingWrapperFor:opener]
            : nil;
    GURL url = pending && pending->url.is_valid() ? pending->url
                                                  : contents->GetVisibleURL();
    NSURL* targetURL = url.is_valid() ? net::NSURLWithGURL(url) : nil;
    const gfx::Rect bounds = pending ? pending->requested_bounds : gfx::Rect();
    const NSRect requested =
        NSMakeRect(bounds.x(), bounds.y(), bounds.width(), bounds.height());
    const BOOL gesture = pending ? pending->user_gesture : NO;
    LOG(WARNING) << "RoomCore: new contents in a Room window, disposition "
                 << static_cast<int>(disposition) << ", opener "
                 << (openerPage ? "found" : "none");
    if (!openerPage) {
      continue;  // Stays in the strip; the host sees it in -webContents.
    }
    // After Navigate() returns: the host may close or show it at once.
    RoomWebContents* __weak weakOpener = openerPage;
    RoomWebContents* __weak weakPage = page;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(^{
          RoomWebContents* strongOpener = weakOpener;
          RoomWebContents* strongPage = weakPage;
          if (!strongOpener || !strongPage || strongPage.closed) {
            return;
          }
          [strongOpener room_didCreateWebContents:strongPage
                                        targetURL:targetURL
                                      disposition:disposition
                                  requestedBounds:requested
                                      userGesture:gesture];
        }));
  }
}

- (void)room_tabFullscreenEntered:(content::WebContents*)contents
                           origin:(const url::Origin&)origin {
  [[self room_wrapperFor:contents] room_didEnterFullscreen:origin];
}

- (void)room_tabFullscreenExited:(content::WebContents*)contents {
  [[RoomWebContents room_existingWrapperFor:contents] room_didExitFullscreen];
}

- (void)close {
  if (_browser) {
    chrome::CloseWindow(_browser);
  }
}

// Chrome asked for the address field (IDC_FOCUS_LOCATION and friends): the
// active page's delegate hears it, as the host's field belongs to the page
// the window shows.
- (void)room_focusLocationBarRequested {
  RoomWebContents* page = self.activeWebContents;
  LOG(INFO) << "RoomBrowser: focus the location bar asked; active page "
            << (page ? "yes" : "none");
  [page room_requestFocusOnLocationBar];
}

// Chrome's bubbles point at the host's site button: the active page's
// delegate knows where it is (3.7a).
- (void)room_toastRequested:(NSString*)kind {
  RoomWebContents* page = self.activeWebContents;
  LOG(INFO) << "RoomCore: Chrome's toast " << base::SysNSStringToUTF8(kind)
            << (page ? " to the active page's host" : " with no active page");
  [page room_requestToast:kind];
}

- (NSRect)room_bubbleAnchorRect {
  return [self.activeWebContents room_bubbleAnchorRect];
}

- (void)room_activeContentsChanged:(content::WebContents*)contents {
  RoomWebContents* wrapper = [self room_wrapperFor:contents];
  [self willChangeValueForKey:@"activeWebContents"];
  _activeWebContents = wrapper;
  [self didChangeValueForKey:@"activeWebContents"];
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browser:didActivateWebContents:)]) {
    [delegate browser:self didActivateWebContents:wrapper];
  }
}

- (void)room_windowWillClose {
  _extensions.reset();
  _stripObserver.reset();
#if BUILDFLAG(ROOM_ENABLE_SPIKES)
  _spike_identity_controller.reset();
#endif
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserWillClose:)]) {
    [delegate browserWillClose:self];
  }
}

- (void)room_windowDestroyed {
  _extensions.reset();
  [self willChangeValueForKey:@"closed"];
  _browser = nullptr;
  [self didChangeValueForKey:@"closed"];
  [_pages removeAllObjects];
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserDidClose:)]) {
    [delegate browserDidClose:self];
  }
}

#if BUILDFLAG(ROOM_ENABLE_SPIKES)
// Spike hooks (room_enable_spikes=true, args/dev.gn only): private selectors
// the Swift host calls with -performSelector:, absent from the public API
// and from release builds.
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
    case IDC_DEV_TOOLS:
    case IDC_FOCUS_LOCATION:
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
  if ([action isEqualToString:@"renderer-census"]) {
    // 5.4b: what each renderer is for (the spare, a site's pages, cross-site
    // subframes under site isolation, an extension, workers), one log line
    // per process; returns the count.
    int count = 0;
    for (auto it = content::RenderProcessHost::AllHostsIterator();
         !it.IsAtEnd(); it.Advance()) {
      content::RenderProcessHost* host = it.GetCurrentValue();
      if (!host->IsInitializedAndNotDead()) {
        continue;
      }
      ++count;
      int main_frames = 0;
      int subframes = 0;
      std::set<std::string> origins;
      host->ForEachRenderFrameHost([&](content::RenderFrameHost* frame) {
        if (frame->GetParent()) {
          ++subframes;
        } else {
          ++main_frames;
        }
        origins.insert(frame->GetLastCommittedOrigin().Serialize());
      });
      std::string sites;
      for (const std::string& origin : origins) {
        sites += (sites.empty() ? "" : ",") + origin;
      }
      size_t service_workers = 0;
      if (auto* partition = host->GetStoragePartition()) {
        if (auto* context = partition->GetServiceWorkerContext()) {
          for (const auto& [version, info] :
               context->GetRunningServiceWorkerInfos()) {
            if (info.render_process_id == host->GetID()) {
              ++service_workers;
            }
          }
        }
      }
      LOG(WARNING) << "RoomCore census: pid=" << host->GetProcess().Pid()
                   << " spare=" << host->IsSpare()
                   << " views=" << host->GetActiveViewCount()
                   << " main_frames=" << main_frames
                   << " subframes=" << subframes
                   << " service_workers=" << service_workers
                   << " unused=" << host->IsUnused()
                   << " origins=" << sites;
    }
    LOG(WARNING) << "RoomCore census: " << count << " renderers";
    return @(count);
  }
  if ([action isEqualToString:@"location-bar-security"]) {
    // What Chrome code reads from the LocationBar for the active page
    // (Phase 3.5: the chip's state beside the host's securityLevel).
    BrowserWindow* window = BrowserWindow::FromBrowser(_browser);
    LocationBar* location_bar = window ? window->GetLocationBar() : nullptr;
    LocationBarModel* model =
        location_bar ? location_bar->GetLocationBarModel() : nullptr;
    return @(model ? static_cast<int>(model->GetSecurityLevel()) : -1);
  }
  if ([action isEqualToString:@"pm-urgent-discard"]) {
    // 3.7b: what performance_manager's urgent discarding does under memory
    // pressure (UrgentPageDiscardingPolicy -> DiscardAPage(URGENT)), asked
    // directly and without the recent-visibility window: Room pages are not
    // auto-discardable (protected), so it must find none.
    using performance_manager::PerformanceManager;
    auto* helper = performance_manager::policies::PageDiscardingHelper::GetFromGraph(
        PerformanceManager::GetGraph());
    if (!helper) {
      return @(-1);
    }
    const auto result = helper->DiscardAPage(
        performance_manager::policies::DiscardEligibilityPolicy::DiscardReason::URGENT,
        /*ignore_recent_visibility=*/true);
    LOG(WARNING) << "RoomCore spike: performance_manager urgent discard: "
                 << (result.first_discard_time ? "discarded a page" : "nothing discarded");
    return @(result.first_discard_time ? 1 : 0);
  }
  if ([action isEqualToString:@"auto-discardable-count"]) {
    TabStripModel* strip = _browser->GetTabStripModel();
    int count = 0;
    for (int i = 0; i < strip->count(); ++i) {
      auto* unit = resource_coordinator::TabLifecycleUnitExternal::FromWebContents(
          strip->GetWebContentsAt(i));
      if (unit && unit->IsAutoDiscardable()) {
        ++count;
      }
    }
    return @(count);
  }
  if ([action hasPrefix:@"memory-pressure-"]) {
    // 3.7b: Chromium's own notification path, as a pressure event from the
    // system monitor would run it (every listener, performance_manager's
    // included, and RoomCore's report to the host).
    base::MemoryPressureLevel level = base::MEMORY_PRESSURE_LEVEL_NONE;
    if ([action isEqualToString:@"memory-pressure-critical"]) {
      level = base::MEMORY_PRESSURE_LEVEL_CRITICAL;
    } else if ([action isEqualToString:@"memory-pressure-moderate"]) {
      level = base::MEMORY_PRESSURE_LEVEL_MODERATE;
    }
    LOG(WARNING) << "RoomCore spike: simulated memory pressure " << level;
    base::MemoryPressureListener::SimulatePressureNotification(level);
    return @(level);
  }
  auto* contents = _browser->GetTabStripModel()->GetActiveWebContents();
  if (!contents || contents->GetVisibleURL().host() != "127.0.0.1") {
    return @(-1);
  }
  if ([action hasPrefix:@"network-"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("ip-address-space-overrides")) {
      return @(-1);
    }
    if ([action isEqualToString:@"network-flags"]) {
      const int flags = (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecks) ? 1 : 0) |
                        (network::features::kLocalNetworkAccessChecksWarn.Get() ? 2 : 0) |
                        (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecksWebSockets) ? 4 : 0) |
                        (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecksWebTransport) ? 8 : 0) |
                        (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecksWebRTC) ? 16 : 0);
      return @(flags);
    }
    if ([action isEqualToString:@"network-reset"]) {
      auto* controller = _profile.room_profile->GetPermissionController();
      const auto origin = contents->GetPrimaryMainFrame()->GetLastCommittedOrigin();
      controller->ResetPermission(blink::PermissionType::LOCAL_NETWORK, origin);
      controller->ResetPermission(blink::PermissionType::LOOPBACK_NETWORK, origin);
      return @1;
    }
    auto* manager = permissions::PermissionRequestManager::FromWebContents(contents);
    if (!manager || !manager->IsRequestInProgress() || manager->Requests().empty()) { return @0; }
    for (const auto& request : manager->Requests()) {
      if (request->request_type() != permissions::RequestType::kLocalNetwork &&
          request->request_type() != permissions::RequestType::kLoopbackNetwork) { return @(-1); }
    }
    if ([action isEqualToString:@"network-accept"]) { manager->Accept(std::monostate{}); }
    return @1;
  }
  if ([action isEqualToString:@"pip-back-to-tab"]) {
    // The overlay's back-to-tab button (VideoOverlayWindowViews; Chrome's
    // document PiP frame has the same): close the window, focus the opener.
    return @(PictureInPictureWindowManager::GetInstance()
                     ->ExitPictureInPictureViaWindowUi(
                         PictureInPictureWindowManager::UiBehavior::
                             kCloseWindowAndFocusOpener)
                 ? 1
                 : 0);
  }
  if ([action isEqualToString:@"download-prompt-enable"]) {
    _profile.room_profile->GetPrefs()->SetBoolean(prefs::kPromptForDownload, true);
    return @1;
  }
  if ([action isEqualToString:@"download-close-decision"]) {
    int count = _profile.room_profile->GetDownloadManager()->InProgressCount();
    if (count < 1) { return @(-1); }
    auto state = std::make_shared<int>(0);
    BrowserWindow::FromBrowser(_browser)->ConfirmBrowserCloseWithPendingDownloads(
        count, DownloadCloseType::kBrowserShutdown,
        base::BindOnce([](std::shared_ptr<int> result, bool cancel_downloads) {
          *result = 1 | (cancel_downloads ? 2 : 0);
          LOG(WARNING) << "Room UI probe download close callback cancel_downloads=" << cancel_downloads;
        }, state));
    LOG(WARNING) << "Room UI probe download close active=" << count << " immediate_state=" << *state;
    return @(*state);
  }
  if ([action hasPrefix:@"extension-popup-"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("load-extension")) {
      return @(-1);
    }
    if ([action isEqualToString:@"extension-popup-open"]) {
      auto* registry = extensions::ExtensionRegistry::Get(_profile.room_profile);
      for (const auto& extension : registry->enabled_extensions()) {
        if (extension->name() != "Room spike extension") {
          continue;
        }
        auto host = extensions::ExtensionViewHostFactory::CreatePopupHost(
            *extension, extension->GetResourceURL("popup.html"), _browser);
        if (!host) {
          return @(-1);
        }
        auto* window = static_cast<RoomBrowserWindow*>(BrowserWindow::FromBrowser(_browser));
        ExtensionPopup::ShowPopup(
            _browser, std::move(host), views::BubbleAnchor(window->GetBubbleAnchor()),
            views::BubbleBorder::TOP_LEFT, PopupShowAction::kShow,
            base::BindOnce([](extensions::ExtensionHost* shown) {
              LOG(WARNING) << "Room UI probe extension popup callback shown=" << (shown != nullptr);
            }));
        return @1;
      }
      return @0;
    }
    auto* popup = ExtensionPopup::last_popup_for_testing();
    if (!popup || !popup->host() || popup->host()->extension()->name() != "Room spike extension") {
      return @0;
    }
    auto* widget = popup->GetWidget();
    if ([action isEqualToString:@"extension-popup-close"]) {
      popup->CloseDeferredIfNecessary();
      return @1;
    }
    if ([action isEqualToString:@"extension-popup-size"]) {
      auto size = widget->GetClientAreaBoundsInScreen().size();
      return @(size.width() * 10000 + size.height());
    }
    NSWindow* native = widget->GetNativeWindow().GetNativeNSWindow();
    const bool owned = native.parentWindow == _window || native.parentWindow.parentWindow == _window;
    LOG(WARNING) << "Room UI probe extension popup visible=" << widget->IsVisible()
                 << " room_owned=" << owned << " active=" << widget->IsActive();
    return @(1 | (widget->IsVisible() ? 2 : 0) | (owned ? 4 : 0) |
             (widget->IsActive() ? 8 : 0));
  }
  if ([action isEqualToString:@"print-preview-pdf"]) {
    auto* dialogs = printing::PrintPreviewDialogController::GetInstance();
    auto* preview = dialogs ? dialogs->GetPrintPreviewForContents(contents) : nullptr;
    auto* ui = preview && preview->GetWebUI()
                   ? preview->GetWebUI()->GetController()->GetAs<printing::PrintPreviewUI>()
                   : nullptr;
    auto bytes = ui ? ui->GetPrintPreviewDataForIndex(
                          printing::COMPLETE_PREVIEW_DOCUMENT_INDEX)
                    : nullptr;
    if (!bytes || bytes->size() == 0) {
      return @0;
    }
    NSString* output = [NSUserDefaults.standardUserDefaults stringForKey:@"RoomSpikeOutput"];
    if (!output) {
      return @(-1);
    }
    NSString* path = [[output stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"generated-preview.pdf"];
    NSData* data = [NSData dataWithBytes:bytes->data() length:bytes->size()];
    NSError* error = nil;
    if (![data writeToFile:path options:NSDataWritingWithoutOverwriting error:&error]) {
      LOG(WARNING) << "Room UI probe preview write failed=" << error.localizedDescription.UTF8String;
      return @(-1);
    }
    NSWindow* window = preview->GetNativeView().GetNativeNSView().window;
    LOG(WARNING) << "Room UI probe preview bytes=" << bytes->size()
                 << " native_window=" << (window != nil)
                 << " parent_window=" << (window.parentWindow != nil);
    return @(bytes->size());
  }
  if ([action isEqualToString:@"devtools-state"]) {
    auto* devtools = DevToolsWindow::GetInstanceForInspectedWebContents(contents);
    auto* controller = DevtoolsUIController::From(_browser);
    int state = controller ? 1 : 0;
    if (devtools) {
      state |= 2;
      if (devtools->IsDocked()) {
        state |= 4;
      }
      auto* frontend = devtools->GetDevToolsWebContents().get();
      if (frontend && frontend->GetNativeView().GetNativeNSView().window) {
        state |= 8;
      }
      LOG(WARNING) << "Room UI probe DevTools state=" << state
                   << " can_dock=" << (controller && controller->CanDockDevtools())
                   << " frontend=" << (frontend ? frontend->GetVisibleURL().spec() : "none");
    }
    return @(state);
  }
  if ([action hasPrefix:@"ui-dialog-"]) {
    auto* window =
        static_cast<RoomBrowserWindow*>(BrowserWindow::FromBrowser(_browser));
    auto widgets = views::Widget::GetAllOwnedWidgets(
        window->GetBubbleAnchor()->GetWidget()->GetNativeView());
    int count = 0;
    for (const auto& widget : widgets) {
      auto* dialog = widget->widget_delegate()->AsDialogDelegate();
      if (!dialog || !widget->IsVisible()) {
        continue;
      }
      ++count;
      LOG(WARNING) << "Room UI probe dialog=" << widget->GetName();
      if ([action isEqualToString:@"ui-dialog-cancel"]) {
        dialog->CancelDialog();
        break;
      }
      if ([action isEqualToString:@"ui-dialog-accept"]) {
        dialog->AcceptDialog();
        break;
      }
    }
    return @(count);
  }
  if ([action isEqualToString:@"password-presentation"]) {
    auto* dialogs = TabDialogs::FromWebContents(contents);
    if (!dialogs) { return @(-1); }
    // 3.7a: with Room's ToolbarButtonProvider the presentation reaches
    // CreateBubble, which has no view for the inactive state (NOTREACHED):
    // Chrome shows the bubble only for a pending or managed password. The
    // real save/update flow is Room.app's `passwords` spike (a submitted form).
    bool provider = ToolbarButtonProvider::From(_browser) != nullptr;
    base::WeakPtr<PasswordsModelDelegate> model =
        PasswordsModelDelegateFromWebContents(contents);
    bool inactive = !model ||
                    model->GetState() == password_manager::ui::INACTIVE_STATE;
    if (!inactive) {
      dialogs->ShowManagePasswordsBubble(true);
    }
    bool bubble = PasswordBubbleViewBase::manage_password_bubble() != nullptr;
    LOG(WARNING) << "Room UI probe password provider=" << provider
                 << " inactive=" << inactive << " bubble=" << bubble;
    return @(1 | (provider ? 2 : 0) | (bubble ? 4 : 0) | (inactive ? 8 : 0));
  }
  if ([action isEqualToString:@"card-save"]) {
    autofill::CreditCard card;
    card.SetRawInfo(autofill::CREDIT_CARD_NAME_FULL, u"Room Fixture");
    card.SetNumber(u"4111111111111111");
    card.SetExpirationMonth(12);
    card.SetExpirationYear(2030);
    autofill::SaveCardBubbleControllerImpl::CreateForWebContents(contents);
    _spike_card_decisions = std::make_shared<int>(0);
    autofill::SaveCardBubbleControllerImpl::FromWebContents(contents)->OfferLocalSave(
        card, autofill::payments::PaymentsAutofillClient::SaveCreditCardOptions().with_show_prompt(),
        base::BindOnce([](std::shared_ptr<int> count,
                         autofill::payments::PaymentsAutofillClient::SaveCardOfferUserDecision decision) {
          LOG(WARNING) << "Room UI probe local card decision=" << static_cast<int>(decision) << " count=" << ++*count;
        }, _spike_card_decisions));
    return @1;
  }
  if ([action isEqualToString:@"card-decisions"]) {
    return @(_spike_card_decisions ? *_spike_card_decisions : -1);
  }
  if ([action isEqualToString:@"address-profiles"]) {
    auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(_profile.room_profile);
    return @(data->address_data_manager().GetProfiles().size());
  }
  if ([action isEqualToString:@"address-diagnostics"]) {
    auto* client = autofill::ChromeAutofillClient::FromWebContentsForTesting(contents);
    auto* driver = autofill::ContentAutofillDriver::GetForRenderFrameHost(contents->GetPrimaryMainFrame());
    auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(_profile.room_profile);
    int forms = 0, fields = 0;
    if (driver) {
      driver->GetAutofillManager().ForEachCachedForm([&](const autofill::FormStructure& form) {
        ++forms; fields += form.fields().size();
      });
    }
    auto* view = contents->GetRenderWidgetHostView();
    LOG(WARNING) << "Room UI probe address enabled=" << (client && client->IsAutofillProfileEnabled())
                 << " eligible=" << data->address_data_manager().GetProfilesToSuggest().size()
                 << " view_focus=" << (view && view->HasFocus())
                 << " driver=" << (driver != nullptr) << " forms=" << forms << " fields=" << fields
                 << " can_show=" << (driver && driver->GetAutofillManager().CanShowAutofillUi());
    return @(forms);
  }
  if ([action isEqualToString:@"address-suggestions"]) {
    auto* client = autofill::ChromeAutofillClient::FromWebContentsForTesting(contents);
    if (!client) { return @(-1); }
    LOG(WARNING) << "Room UI probe autofill suggestions=" << client->GetAutofillSuggestions().size()
                 << " ui_session=" << client->GetSessionIdForCurrentAutofillSuggestions().has_value();
    return @(client->GetAutofillSuggestions().size());
  }
  if ([action isEqualToString:@"address-seed"] ||
      [action isEqualToString:@"address-save"] ||
      [action isEqualToString:@"address-update"]) {
    autofill::AutofillProfile address(autofill::AddressCountryCode("US"));
    address.SetRawInfo(autofill::NAME_FULL, u"Room Fixture");
    address.SetRawInfo(autofill::ADDRESS_HOME_STREET_ADDRESS, u"1 Test Street");
    address.SetRawInfo(autofill::ADDRESS_HOME_CITY, u"Mountain View");
    address.SetRawInfo(autofill::ADDRESS_HOME_STATE, u"CA");
    address.SetRawInfo(autofill::ADDRESS_HOME_ZIP, u"94043");
    if ([action isEqualToString:@"address-seed"]) {
      address.SetRawInfo(autofill::EMAIL_ADDRESS, u"room-fixture@example.test");
      address.FinalizeAfterImport();
      auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(_profile.room_profile);
      data->address_data_manager().AddProfile(address);
      return @1;
    }
    autofill::AutofillProfile original(address);
    const bool update = [action isEqualToString:@"address-update"];
    if (update) {
      address.SetRawInfo(autofill::ADDRESS_HOME_STREET_ADDRESS,
                         u"2 Test Street");
    }
    _spike_address_decisions = std::make_shared<int>(0);
    autofill::AddressBubblesController::SetUpAndShowSaveOrUpdateAddressBubble(
        contents, address, update ? &original : nullptr,
        autofill::AutofillClient::SaveAddressBubbleType::kSave, update,
        base::BindOnce(
            [](std::shared_ptr<int> count,
               autofill::AutofillClient::AddressPromptUserDecision decision,
               base::optional_ref<const autofill::AutofillProfile>) {
              LOG(WARNING) << "Room UI probe address decision="
                           << static_cast<int>(decision)
                           << " count=" << ++*count;
            },
            _spike_address_decisions));
    return @1;
  }
  if ([action isEqualToString:@"address-visible"]) {
    auto* controller =
        autofill::AddressBubblesController::FromWebContents(contents);
    return @(controller && controller->GetBubbleView());
  }
  if ([action isEqualToString:@"address-decisions"]) {
    return @(_spike_address_decisions ? *_spike_address_decisions : -1);
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
  if ([action isEqualToString:@"capture-state"]) {
    auto indicator = MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator();
    return @((indicator->IsCapturingAudio(contents) ? 1 : 0) |
             (indicator->IsCapturingVideo(contents) ? 2 : 0) |
             (indicator->IsCapturingDisplay(contents) ? 4 : 0));
  }
  if ([action isEqualToString:@"stop-fake-capture"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("use-fake-device-for-media-stream")) {
      return @(-1);
    }
    MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator()
        ->StopMediaCapturing(contents, MediaStreamCaptureIndicator::kUserMedia);
    return @1;
  }
  if ([action isEqualToString:@"accept-fake-capture"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("use-fake-device-for-media-stream")) {
      return @(-1);
    }
    auto* manager = permissions::PermissionRequestManager::FromWebContents(contents);
    if (!manager || !manager->IsRequestInProgress() || manager->Requests().empty()) {
      return @0;
    }
    for (const auto& request : manager->Requests()) {
      if (request->request_type() != permissions::RequestType::kCameraStream &&
          request->request_type() != permissions::RequestType::kMicStream) {
        return @(-1);
      }
    }
    manager->Accept(std::monostate{});
    return @1;
  }
  if ([action isEqualToString:@"media-mute"]) {
    contents->SetAudioMuted(true);
    return @(contents->IsAudioMuted());
  }
  if ([action isEqualToString:@"media-state"]) {
    return @((contents->IsAudioMuted() ? 1 : 0) |
             (contents->IsCurrentlyAudible() ? 2 : 0));
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
#endif  // BUILDFLAG(ROOM_ENABLE_SPIKES)

@end

// MARK: Moving a page between windows (Phase 4.8b)

@implementation RoomWebContents (Windows)

- (BOOL)moveToBrowser:(RoomBrowser*)target error:(NSError**)error {
  content::WebContents* contents = self.room_webContents;
  NSString* failure = nil;
  if (!contents || self.closed) {
    failure = @"the page is closed";
  } else if (!target.room_browserInterface) {
    failure = @"the target browser is closed";
  } else if (target.profile != self.profile) {
    failure = @"the target browser belongs to another profile";
  }
  if (failure) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"RoomWebContentsMove"
                     code:1
                 userInfo:@{NSLocalizedDescriptionKey : failure}];
    }
    return NO;
  }
  BrowserWindowInterface* destination = target.room_browserInterface;
  for (BrowserWindowInterface* browser : GetAllBrowserWindowInterfaces()) {
    TabStripModel* strip = browser->GetTabStripModel();
    const int index = strip->GetIndexOfWebContents(contents);
    if (index == TabStripModel::kNoTab) {
      continue;
    }
    if (browser == destination) {
      return YES;
    }
    // Chrome's tab drag between windows: the TabModel (the WebContents with
    // its navigation controller and tab helpers) leaves one strip and joins
    // the other; the source Browser closes if its strip empties.
    std::unique_ptr<tabs::TabModel> tab = strip->DetachTabAtForInsertion(index);
    [self.room_browser room_forgetPage:self];
    [target room_insertDetachedTab:std::move(tab) page:self];
    return YES;
  }
  // Not in a strip yet: the page joins `target` as a new page would.
  [target addWebContents:self activate:NO];
  return YES;
}

@end
