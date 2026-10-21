// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/browser/room_browser_window.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <map>
#include <utility>

#include "base/no_destructor.h"

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/observer_list.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_manager_service.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/sad_tab.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/views/interaction/browser_elements_views_impl.h"
#include "chrome/browser/ui/views/autofill/autofill_bubble_handler_impl.h"
#include "components/autofill/content/browser/content_autofill_client.h"
#include "components/autofill/core/browser/suggestions/suggestion_hiding_reason.h"
#include "chrome/browser/ui/views/frame/toolbar_button_provider.h"
#include "chrome/browser/translate/chrome_translate_client.h"
#include "chrome/browser/ui/views/translate/translate_bubble_controller.h"
#include "chrome/browser/ui/views/translate/translate_bubble_view.h"
#include "components/translate/core/browser/language_state.h"
#include "components/translate/core/browser/translate_manager.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/input/native_web_keyboard_event.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "room/browser/room_exclusive_access_context.h"
#include "room/browser/room_find_bar.h"
#include "room/browser/room_location_bar.h"
#include "third_party/blink/public/mojom/picture_in_picture_window_options/picture_in_picture_window_options.mojom.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/views/widget/widget.h"

namespace room {
// Defined in chrome/browser/ui/views/frame/browser_window_factory.cc
// (patches/0003-browser-window-factory-hook.patch).
extern BrowserWindow* (*g_create_browser_window_hook)(BrowserWindowInterface*);
extern views::View* (*g_fedcm_anchor_hook)(BrowserWindowInterface*);
extern BrowserWindow* (*g_find_browser_window_hook)(content::WebContents*);
extern std::unique_ptr<SadTab> (*g_create_sad_tab_hook)(content::WebContents*, SadTabKind);
// Defined in chrome/browser/ui/navigator/browser_navigator.cc
// (patches/0014-navigator-browser-for-disposition-hook.patch).
extern bool (*g_browser_for_disposition_hook)(const NavigateParams&,
                                              BrowserWindowInterface**);
}  // namespace room

namespace {

// Chrome's toolbar for its Views bubbles (3.7a). Chrome asks the Browser's
// ToolbarButtonProvider (user data ToolbarView registers) where a password,
// address or card bubble points: PasswordBubbleViewBase::ShowBubble returns
// without a bubble when there is none, the autofill bubble handler and the
// send-tab/QR/sharing bubbles call GetBubbleAnchor. Room has no Chrome
// toolbar: every anchor is the window's bubble anchor (at the host's site
// button, RoomBrowserWindow::GetBubbleAnchor), every control null. Members
// Chrome reaches for beyond the anchor log their first hit; the extensions
// container stays null (Room's is ExtensionsContainer user data, 3.6b, not
// a Views container: B-71).
class RoomToolbarButtonProvider : public ToolbarButtonProvider {
 public:
  RoomToolbarButtonProvider(RoomBrowserWindow* window,
                            BrowserWindowInterface* browser)
      : window_(window) {
    if (browser) {
      registration_.emplace(browser->GetUnownedUserDataHost(),
                            static_cast<ToolbarButtonProvider&>(*this));
    }
  }
  ~RoomToolbarButtonProvider() override = default;

  ExtensionsContainerViews* GetExtensionsContainerViews() override {
    RoomStubHit("ToolbarButtonProvider::GetExtensionsContainerViews");
    return nullptr;
  }
  PinnedToolbarActions* GetPinnedToolbarActions() override {
    RoomStubHit("ToolbarButtonProvider::GetPinnedToolbarActions");
    return nullptr;
  }
  gfx::Size GetToolbarButtonSize() const override {
    RoomStubHit("ToolbarButtonProvider::GetToolbarButtonSize");
    return {};
  }
  views::BubbleAnchor GetDefaultExtensionDialogAnchor() override {
    RoomStubHit("ToolbarButtonProvider::GetDefaultExtensionDialogAnchor");
    return Anchor();
  }
  page_actions::PageActionViewInterface* GetPageActionViewInterface(
      actions::ActionId) override {
    RoomStubHit("ToolbarButtonProvider::GetPageActionViewInterface");
    return nullptr;
  }
  AppMenuControl* GetAppMenuControl() override {
    RoomStubHit("ToolbarButtonProvider::GetAppMenuControl");
    return nullptr;
  }
  gfx::Rect GetFindBarBoundingBox(int) override {
    RoomStubHit("ToolbarButtonProvider::GetFindBarBoundingBox");
    return {};
  }
  void FocusToolbar() override {
    RoomStubHit("ToolbarButtonProvider::FocusToolbar");
  }
  views::AccessiblePaneView* GetAsAccessiblePaneView() override {
    RoomStubHit("ToolbarButtonProvider::GetAsAccessiblePaneView");
    return nullptr;
  }
  views::BubbleAnchor GetBubbleAnchor(
      std::optional<actions::ActionId>) override {
    return Anchor();
  }
  views::BubbleAnchor GetPageActionBubbleAnchor(actions::ActionId) override {
    return Anchor();
  }
  void ZoomChangedForActiveTab(bool) override {}
  AvatarToolbarButtonInterface* GetAvatarToolbarButtonInterface() override {
    RoomStubHit("ToolbarButtonProvider::GetAvatarToolbarButtonInterface");
    return nullptr;
  }
  ToolbarButton* GetBackButton() override {
    RoomStubHit("ToolbarButtonProvider::GetBackButton");
    return nullptr;
  }
  ReloadControl* GetReloadButton() override {
    RoomStubHit("ToolbarButtonProvider::GetReloadButton");
    return nullptr;
  }
  ToolbarButton* GetDownloadButton() override {
    RoomStubHit("ToolbarButtonProvider::GetDownloadButton");
    return nullptr;
  }
  WebUIToolbarWebView* GetWebUIToolbarViewForTesting() override {
    return nullptr;
  }

 private:
  views::BubbleAnchor Anchor() {
    return views::BubbleAnchor(window_->GetBubbleAnchor());
  }
  raw_ptr<RoomBrowserWindow> window_;
  std::optional<ui::ScopedUnownedUserData<ToolbarButtonProvider>>
      registration_;
};

auto& RoomWindows() {
  static base::NoDestructor<std::map<BrowserWindowInterface*, RoomBrowserWindow*>> windows;
  return *windows;
}

// SadTabHelper owns this until a new renderer is ready. Keep the fallback in
// the page's Cocoa view; a Room tab has no Chrome ContentsWebView to decorate.
class RoomSadTab : public SadTab {
 public:
  RoomSadTab(content::WebContents* contents, SadTabKind kind)
      : SadTab(contents, kind) {
    RoomStubHit("CreateSadTab");
    overlay_ = [[NSBox alloc] initWithFrame:NSZeroRect];
    overlay_.identifier = @"RoomSadTab";
    overlay_.boxType = NSBoxCustom;
    overlay_.borderWidth = 0;
    overlay_.titlePosition = NSNoTitle;
    overlay_.fillColor = NSColor.windowBackgroundColor;
    overlay_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTextField* label = [NSTextField labelWithString:@"Page crashed. Reload to try again."];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay_.contentView addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
      [label.centerXAnchor constraintEqualToAnchor:overlay_.contentView.centerXAnchor],
      [label.centerYAnchor constraintEqualToAnchor:overlay_.contentView.centerYAnchor],
    ]];
    ReinstallInWebView();
  }
  ~RoomSadTab() override { [overlay_ removeFromSuperview]; }
  void ReinstallInWebView() override {
    NSView* view = web_contents()->GetNativeView().GetNativeNSView();
    if (!view) {
      return;
    }
    overlay_.frame = view.bounds;
    if (overlay_.superview != view) {
      [overlay_ removeFromSuperview];
      [view addSubview:overlay_];
    }
  }
 private:
  NSBox* __strong overlay_;
};

// Views-backed web dialogs still need a native parent and an explicit host
// lifetime even though Room does not own a BrowserView.
class RoomModalDialogHost : public web_modal::WebContentsModalDialogHost {
 public:
  // `anchor_rect` answers where bubbles point, in `window`'s coordinates
  // (the host's site button), or nullopt for the corner default.
  // `window_changed` runs when the host window moves or resizes.
  RoomModalDialogHost(NSWindow* window,
                      base::RepeatingCallback<std::optional<gfx::Rect>()>
                          anchor_rect,
                      base::RepeatingClosure window_changed)
      : window_(window),
        anchor_rect_(std::move(anchor_rect)),
        window_changed_(std::move(window_changed)) {
    // NativeWidgetMac's child-modal path needs a Views NSWindow host, not
    // merely an arbitrary NSView. A transparent, noninteractive child widget
    // supplies that bridge without replacing the Swift-owned browser window.
    widget_ = std::make_unique<views::Widget>();
    views::Widget::InitParams params(
        views::Widget::InitParams::CLIENT_OWNS_WIDGET,
        views::Widget::InitParams::TYPE_WINDOW_FRAMELESS);
    params.name = "RoomModalAnchor";
    params.opacity = views::Widget::InitParams::WindowOpacity::kTranslucent;
    params.accept_events = false;
    params.activatable = views::Widget::InitParams::Activatable::kNo;
    widget_->Init(std::move(params));
    auto* contents = widget_->SetContentsView(std::make_unique<views::View>());
    bubble_anchor_ = contents->AddChildView(std::make_unique<views::View>());
    bubble_anchor_->SetBounds(16, 16, 1, 1);
    widget_->SetVisibilityChangedAnimationsEnabled(false);
    widget_->SetOpacity(0);
    UpdateBounds();
    // Above the host's window: the dialogs and bubbles parented here are
    // its child windows, which AppKit orders just above it; below the host's
    // window they were hidden behind it (3.3b: print preview). The anchor
    // itself is transparent and ignores the mouse.
    [window addChildWindow:widget_->GetNativeWindow().GetNativeNSWindow()
                  ordered:NSWindowAbove];
    widget_->ShowInactive();
    resize_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowDidResizeNotification object:window queue:nil
        usingBlock:^(NSNotification*) { WindowChanged(); }];
    move_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowDidMoveNotification object:window queue:nil
        usingBlock:^(NSNotification*) { WindowChanged(); }];
  }
  ~RoomModalDialogHost() override {
    [NSNotificationCenter.defaultCenter removeObserver:resize_observer_];
    [NSNotificationCenter.defaultCenter removeObserver:move_observer_];
    for (auto& observer : observers_) {
      observer.OnHostDestroying();
    }
    [window_ removeChildWindow:widget_->GetNativeWindow().GetNativeNSWindow()];
    widget_->CloseNow();
  }
  gfx::NativeView GetHostView() const override {
    return widget_->GetNativeView();
  }
  views::View* GetBubbleAnchor() {
    PositionAnchor();
    return bubble_anchor_;
  }
  gfx::Point GetDialogPosition(const gfx::Size& size) override {
    const gfx::Size bounds = GetMaximumDialogSize();
    return gfx::Point(std::max(0, (bounds.width() - size.width()) / 2),
                      std::max(0, (bounds.height() - size.height()) / 2));
  }
  gfx::Size GetMaximumDialogSize() override {
    const NSSize size = window_.contentView.bounds.size;
    return gfx::Size(size.width, size.height);
  }
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.AddObserver(observer);
  }
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.RemoveObserver(observer);
  }
  void NotifyPositionRequiresUpdate() override {
    UpdateBounds();
    for (auto& observer : observers_) {
      observer.OnPositionRequiresUpdate();
    }
  }
 private:
  void WindowChanged() {
    NotifyPositionRequiresUpdate();
    if (window_changed_) {
      window_changed_.Run();
    }
  }
  void UpdateBounds() {
    NSRect content = [window_.contentView convertRect:window_.contentView.bounds
                                               toView:nil];
    widget_->SetBounds(gfx::ScreenRectFromNSRect([window_ convertRectToScreen:content]));
    PositionAnchor();
  }
  // The anchor view at the host's rect, in the widget's (top-left) coordinates;
  // the widget covers the window's content view. Bubbles anchored on it follow
  // its bounds (BubbleDialogDelegate observes the anchor view and widget).
  void PositionAnchor() {
    NSWindow* window = window_;
    if (!window || !bubble_anchor_) {
      return;
    }
    gfx::Rect bounds(16, 16, 1, 1);
    if (std::optional<gfx::Rect> rect =
            anchor_rect_ ? anchor_rect_.Run() : std::nullopt;
        rect && !rect->IsEmpty()) {
      NSRect content = [window.contentView convertRect:window.contentView.bounds
                                                toView:nil];
      bounds = gfx::Rect(rect->x() - NSMinX(content),
                         NSMaxY(content) - rect->bottom(), rect->width(),
                         rect->height());
    }
    if (bubble_anchor_->bounds() != bounds) {
      bubble_anchor_->SetBoundsRect(bounds);
    }
  }
  NSWindow* __weak window_;
  base::RepeatingCallback<std::optional<gfx::Rect>()> anchor_rect_;
  base::RepeatingClosure window_changed_;
  id resize_observer_;
  id move_observer_;
  std::unique_ptr<views::Widget> widget_;
  raw_ptr<views::View> bubble_anchor_ = nullptr;
  base::ObserverList<web_modal::ModalDialogHostObserver> observers_;
};

struct PendingHostWindow {
  NSWindow* __weak window = nil;
  raw_ptr<room::RoomBrowserWindowClient> client = nullptr;
};

// Set while a RoomBrowser creates its Browser; Browser's constructor calls the
// factory hook synchronously.
PendingHostWindow* g_pending_host_window = nullptr;

const char* BrowserTypeName(BrowserWindowInterface::Type type) {
  switch (type) {
    case BrowserWindowInterface::TYPE_NORMAL:
      return "normal";
    case BrowserWindowInterface::TYPE_POPUP:
      return "popup";
    case BrowserWindowInterface::TYPE_APP:
      return "app";
    case BrowserWindowInterface::TYPE_DEVTOOLS:
      return "devtools";
    case BrowserWindowInterface::TYPE_APP_POPUP:
      return "app-popup";
    case BrowserWindowInterface::TYPE_PICTURE_IN_PICTURE:
      return "picture-in-picture";
    default:
      return "other";
  }
}

BrowserWindow* CreateRoomBrowserWindow(BrowserWindowInterface* browser) {
  if (!g_pending_host_window || !g_pending_host_window->window) {
    // Chrome made this Browser (an extension's windows.create, undocked
    // DevTools, a Chrome command): Chrome's BrowserView would be a Chrome
    // window beside the host's. Refuse it; the Browser lives headless.
    LOG(WARNING) << "RoomCore: refused a Chrome BrowserView for a "
                 << BrowserTypeName(browser->GetType())
                 << " Browser //room did not create; it stays headless";
    return new RoomBrowserWindow(browser, nil, nullptr);
  }
  // Taken here, so deleted here (B-139: it leaked one per RoomBrowser).
  std::unique_ptr<PendingHostWindow> pending(g_pending_host_window);
  // One Browser per pending window: anything Browser's constructor creates in
  // turn (it does not today) is headless.
  g_pending_host_window = nullptr;
  return new RoomBrowserWindow(browser, pending->window, pending->client);
}

// patches/0014: Navigate() asks which Browser receives a disposition. From a
// Room Browser every new contents stays in that Browser's tab strip, where
// the host places it (a Today tab under the opener, Phase 2.6): the popup and
// window dispositions would otherwise create a Browser of their own.
bool BrowserForDisposition(const NavigateParams& params,
                           BrowserWindowInterface** browser) {
  const auto found = RoomWindows().find(params.browser.get());
  if (found == RoomWindows().end() || found->second->is_headless()) {
    return false;  // Chrome's choice.
  }
  // The host's navigation policy for a page opened from one of its pages
  // (CEF asks in OnBeforePopup/OnOpenURLFromTab): Peek takes a ⇧-click.
  if (params.disposition != WindowOpenDisposition::CURRENT_TAB &&
      found->second->client() &&
      !found->second->client()->AllowOpenFromTab(params)) {
    LOG(WARNING) << "RoomCore: the host's navigation policy cancelled a "
                    "disposition "
                 << static_cast<int>(params.disposition) << " open";
    *browser = nullptr;
    return true;
  }
  room::PendingOpen pending;
  pending.disposition = params.disposition;
  pending.url = params.url;
  pending.user_gesture = params.user_gesture;
  if (params.source_contents) {
    pending.source = params.source_contents->GetWeakPtr();
  }
  switch (params.disposition) {
    case WindowOpenDisposition::NEW_POPUP:
    case WindowOpenDisposition::NEW_WINDOW:
      pending.requested_bounds = params.window_features.bounds;
      found->second->SetPendingOpen(pending);
      *browser = params.browser;
      return true;
    case WindowOpenDisposition::NEW_PICTURE_IN_PICTURE: {
      if (params.contents_to_insert) {
        if (auto options =
                params.contents_to_insert->GetPictureInPictureOptions()) {
          pending.requested_bounds =
              gfx::Rect(0, 0, static_cast<int>(options->width),
                        static_cast<int>(options->height));
        }
      }
      found->second->SetPendingOpen(pending);
      *browser = params.browser;
      return true;
    }
    case WindowOpenDisposition::OFF_THE_RECORD: {
      // From an off-the-record page the page stays in its own Browser
      // (Chrome's NormalizeDisposition makes it a foreground tab there).
      if (params.browser->GetProfile()->IsOffTheRecord()) {
        found->second->SetPendingOpen(pending);
        *browser = params.browser;
        return true;
      }
      // Otherwise the twin's Browser in the host's incognito window, or one
      // //room makes for the twin in this window: the opener's delegate
      // hears didCreate with the off-the-record disposition and the host
      // moves the page into its incognito window (4.8b, B-50). Chrome's own
      // choice would be an incognito Browser with a BrowserView.
      BrowserWindowInterface* target =
          found->second->client()
              ? found->second->client()->BrowserForOffTheRecord()
              : nullptr;
      RoomBrowserWindow* target_window =
          target ? room::RoomBrowserWindowFor(target) : nullptr;
      if (!target_window) {
        LOG(WARNING) << "RoomCore: refused an off-the-record open (no "
                        "off-the-record profile)";
        *browser = nullptr;
        return true;
      }
      target_window->SetPendingOpen(pending);
      *browser = target;
      return true;
    }
    default:
      // Tabs (foreground, background, singleton, switch-to-tab, split):
      // Chrome already keeps them in this Browser.
      found->second->SetPendingOpen(pending);
      return false;
  }
}

}  // namespace

namespace room {

void InstallBrowserWindowFactory() {
  g_create_browser_window_hook = &CreateRoomBrowserWindow;
  g_browser_for_disposition_hook = &BrowserForDisposition;
  g_find_browser_window_hook = +[](content::WebContents* contents) -> BrowserWindow* {
    for (const auto& [browser, window] : RoomWindows()) {
      if (browser->GetTabStripModel()->GetIndexOfWebContents(contents) >= 0) {
        return window;
      }
    }
    return nullptr;
  };
  g_create_sad_tab_hook = +[](content::WebContents* contents, SadTabKind kind)
      -> std::unique_ptr<SadTab> {
    for (const auto& [browser, window] : RoomWindows()) {
      if (browser->GetTabStripModel()->GetIndexOfWebContents(contents) >= 0) {
        return std::make_unique<RoomSadTab>(contents, kind);
      }
    }
    return nullptr;  // Preserve Chrome's UI for fallback Chrome windows.
  };
  g_fedcm_anchor_hook = +[](BrowserWindowInterface* browser) -> views::View* {
    const auto found = RoomWindows().find(browser);
    if (found == RoomWindows().end()) {
      return nullptr;
    }
    RoomStubHit("GetFedCmAnchor");
    return found->second->GetBubbleAnchor();
  };
}

RoomBrowserWindow* RoomBrowserWindowFor(BrowserWindowInterface* browser) {
  const auto found = RoomWindows().find(browser);
  return found == RoomWindows().end() || found->second->is_headless()
             ? nullptr
             : found->second;
}

PendingOpen::PendingOpen() = default;
PendingOpen::PendingOpen(const PendingOpen&) = default;
PendingOpen& PendingOpen::operator=(const PendingOpen&) = default;
PendingOpen::~PendingOpen() = default;

ScopedPendingHostWindow::ScopedPendingHostWindow(
    NSWindow* window,
    RoomBrowserWindowClient* client) {
  CHECK(!g_pending_host_window);
  g_pending_host_window = new PendingHostWindow{window, client};
}

ScopedPendingHostWindow::~ScopedPendingHostWindow() {
  // Normally consumed (and cleared) by CreateRoomBrowserWindow.
  delete g_pending_host_window;
  g_pending_host_window = nullptr;
}

}  // namespace room

struct RoomBrowserWindow::ObjCMembers {
  NSWindow* __weak window;
  std::unique_ptr<RoomModalDialogHost> modal_host;
  // Registered as the Browser's ToolbarButtonProvider for a window the host
  // owns (3.7a); a headless Browser has none (its bubbles have no window).
  std::unique_ptr<RoomToolbarButtonProvider> toolbar_provider;
  std::unique_ptr<autofill::AutofillBubbleHandlerImpl> autofill_handler;
};

RoomBrowserWindow::RoomBrowserWindow(BrowserWindowInterface* browser,
                                     NSWindow* window,
                                     room::RoomBrowserWindowClient* client)
    : browser_(browser),
      client_(client),
      objc_(std::make_unique<ObjCMembers>(
          ObjCMembers{window, nullptr, nullptr, nullptr})),
      exclusive_access_context_(
          std::make_unique<room::RoomExclusiveAccessContext>(browser, client)) {
  RoomWindows().emplace(browser, this);
  objc_->toolbar_provider = std::make_unique<RoomToolbarButtonProvider>(
      this, is_headless() ? nullptr : browser);
  // Payment bubbles resolve AutofillBubbleHandler through window user data,
  // without calling the legacy BrowserWindow getter first.
  GetAutofillBubbleHandler();
}

autofill::AutofillBubbleHandler* RoomBrowserWindow::GetAutofillBubbleHandler() {
  if (!objc_->autofill_handler) {
    objc_->autofill_handler = std::make_unique<autofill::AutofillBubbleHandlerImpl>(
        browser_, objc_->toolbar_provider.get());
  }
  return objc_->autofill_handler.get();
}

bool RoomBrowserWindow::is_headless() const {
  return !client_;
}

void RoomBrowserWindow::SetPendingOpen(const room::PendingOpen& pending) {
  pending_open_ = pending;
  // Navigate() inserts the contents before it returns; a record left after
  // that (a singleton tab that already existed) must not describe the next,
  // unrelated insertion.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<RoomBrowserWindow> window) {
                       if (window) {
                         window->pending_open_.reset();
                       }
                     },
                     weak_factory_.GetWeakPtr()));
}

std::optional<room::PendingOpen> RoomBrowserWindow::TakePendingOpen() {
  return std::exchange(pending_open_, std::nullopt);
}

RoomBrowserWindow::~RoomBrowserWindow() {
  RoomWindows().erase(browser_);
  // The handler points at the provider; both go before the Browser's user
  // data host does.
  objc_->autofill_handler.reset();
  objc_->toolbar_provider.reset();
  // What BrowserView and WebUIBrowserWindow do in their destructors: features
  // that hold on to window-scoped objects (side panel entries, for example)
  // let go of them before the Browser destroys the features themselves.
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
  if (client_) {
    client_->OnBrowserWindowDestroyed();
  }
}

// ui::BaseWindow: window state is the host window's.

bool RoomBrowserWindow::IsActive() const {
  return objc_->window.keyWindow;
}

bool RoomBrowserWindow::IsMaximized() const {
  return objc_->window.zoomed;
}

bool RoomBrowserWindow::IsMinimized() const {
  return objc_->window.miniaturized;
}

bool RoomBrowserWindow::IsFullscreen() const {
  return (objc_->window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

gfx::NativeWindow RoomBrowserWindow::GetNativeWindow() const {
  return gfx::NativeWindow(objc_->window);
}

gfx::Rect RoomBrowserWindow::GetRestoredBounds() const {
  return GetBounds();
}

ui::mojom::WindowShowState RoomBrowserWindow::GetRestoredState() const {
  // What BrowserView reports: the state a restored window comes back in.
  if (IsMaximized()) {
    return ui::mojom::WindowShowState::kMaximized;
  }
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  return ui::mojom::WindowShowState::kNormal;
}

ui::mojom::WindowShowState RoomBrowserWindow::GetWindowShowState() const {
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMaximized()) {
    return ui::mojom::WindowShowState::kMaximized;
  }
  return ui::mojom::WindowShowState::kNormal;
}

bool RoomBrowserWindow::GetCanResize() {
  return (objc_->window.styleMask & NSWindowStyleMaskResizable) != 0;
}

std::string RoomBrowserWindow::GetWorkspace() const {
  // macOS Spaces have no public identifier (BrowserView on Mac: empty too).
  return std::string();
}

bool RoomBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return (objc_->window.collectionBehavior &
          NSWindowCollectionBehaviorCanJoinAllSpaces) != 0;
}

bool RoomBrowserWindow::IsOnCurrentWorkspace() const {
  NSWindow* window = objc_->window;
  return window && window.onActiveSpace;
}

bool RoomBrowserWindow::IsVisibleOnScreen() const {
  NSWindow* window = objc_->window;
  return window && window.visible &&
         (window.occlusionState & NSWindowOcclusionStateVisible) != 0;
}

ui::ZOrderLevel RoomBrowserWindow::GetZOrderLevel() const {
  NSWindow* window = objc_->window;
  return window && window.level > NSNormalWindowLevel
             ? ui::ZOrderLevel::kFloatingWindow
             : ui::ZOrderLevel::kNormal;
}

void RoomBrowserWindow::Maximize() {
  // Chrome asks (extension windows.update, session restore); AppKit's zoom.
  NSWindow* window = objc_->window;
  if (window && !window.zoomed) {
    [window zoom:nil];
  }
}

void RoomBrowserWindow::Minimize() {
  [objc_->window miniaturize:nil];
}

void RoomBrowserWindow::Restore() {
  NSWindow* window = objc_->window;
  if (window.miniaturized) {
    [window deminiaturize:nil];
  } else if (window.zoomed) {
    [window zoom:nil];
  }
}

gfx::Rect RoomBrowserWindow::GetBounds() const {
  NSWindow* window = objc_->window;
  return window ? gfx::ScreenRectFromNSRect(window.frame) : gfx::Rect();
}

void RoomBrowserWindow::Show() {
  NSWindow* window = objc_->window;
  if (!window) {
    return;  // Headless: never the last active Browser.
  }
  // Same as BrowserView::Show() on macOS: the Browser must be the last active
  // one as soon as it is shown, before AppKit reports the activation.
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  // Chrome shows a window for every link opened with a gesture; the host's
  // window is already on screen. Never pull it over another application.
  if (NSApp.active) {
    [window makeKeyAndOrderFront:nil];
  } else if (!window.visible) {
    [window orderFront:nil];
  }
}

void RoomBrowserWindow::Hide() {
  [objc_->window orderOut:nil];
}

bool RoomBrowserWindow::IsVisible() const {
  return objc_->window.visible;
}

void RoomBrowserWindow::ShowInactive() {
  [objc_->window orderFront:nil];
}

void RoomBrowserWindow::Close() {
  if (destroy_posted_) {
    return;
  }
  // The sequence of WebUIBrowserWindow::OnWindowCloseRequested() and
  // BrowserWidget: beforeunload handlers, downloads warnings or policy may
  // hold the close; UnloadController calls Close() again when they are done.
  UnloadController* unload = UnloadController::From(browser_);
  if (!unload->HandleBeforeClose()) {
    return;
  }
  // Closes all tabs; when the strip is empty, Browser::TabStripEmpty() calls
  // Close() again and we get past this point with no tabs left.
  unload->OnWindowClosing();
  if (!browser_->GetTabStripModel()->empty()) {
    return;
  }
  destroy_posted_ = true;
  if (client_) {
    client_->OnBrowserWindowWillClose();
  }
  // Views destroys the Browser when its widget is destroyed, after the
  // current task; do the same.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&RoomBrowserWindow::DestroyBrowser,
                                weak_factory_.GetWeakPtr()));
}

void RoomBrowserWindow::DestroyBrowser() {
  UnloadController::From(browser_)->set_force_skip_warning_user_on_close(true);
  UnloadController::From(browser_)->OnWindowClosing();
  // Deletes the Browser, which deletes this window (DeleteBrowserWindow).
  BrowserManagerService::SynchronouslyDestroyBrowser(browser_);
}

void RoomBrowserWindow::Activate() {
  NSWindow* window = objc_->window;
  if (!window) {
    return;
  }
  // BrowserWebContentsDelegate::ActivateContents made the page the strip's
  // active tab first: the host shows it (B-107), whether or not the window
  // may take the keyboard below.
  if (client_) {
    client_->OnActivationRequested(
        browser_->GetTabStripModel()->GetActiveWebContents());
  }
  // NativeWidgetNSWindowBridge activates the application first
  // (activateIgnoringOtherApps), so a page's window.focus() or an extension
  // could take the keyboard from another application. Room does not: while
  // the app is active the window becomes key; while another application is,
  // nothing moves (the window becomes key when the user comes back).
  if (!NSApp.active) {
    LOG(WARNING) << "RoomCore: Activate() while the application is inactive; "
                    "not stealing focus";
    return;
  }
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  [window makeKeyAndOrderFront:nil];
}

void RoomBrowserWindow::Deactivate() {
  BrowserActiveStateManager::From(browser_)->DidBecomeInactive();
}

// BrowserWindow.

void RoomBrowserWindow::UpdateTitleBar() {
  // The host draws its own title (the sidebar), from RoomWebContents.title.
}

void RoomBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                           content::WebContents* new_contents,
                                           int index,
                                           int reason) {
  if (client_) {
    client_->OnActiveContentsChanged(new_contents);
  }
}

void RoomBrowserWindow::OnTabDetached(content::WebContents* contents,
                                      bool was_active) {
  // The host owns the strip it draws; Chrome's detach needs nothing here.
}

std::vector<StatusBubble*> RoomBrowserWindow::GetStatusBubbles() {
  // None, deliberately: BrowserWebContentsDelegate::UpdateTargetURL and
  // ContentsMouseEvent static_cast every status bubble to StatusBubbleViews
  // (and its anchor to ContentsWebView), so any other StatusBubble would be
  // undefined behaviour on the first hover. The hovered link reaches the host
  // from UpdateTargetURL through patches/0015 (didChangeStatusText); Chrome's
  // loading text ("Waiting for…") is not shown by Room.
  return {};
}

void RoomBrowserWindow::UpdateLoadingAnimations(bool is_visible) {
  // The host observes RoomWebContents.loading itself.
}

void RoomBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {
  // Ditto: the host's reload/stop follows RoomWebContents.loading.
}

void RoomBrowserWindow::UpdateToolbar(content::WebContents* contents) {
  // The host's address field follows RoomWebContents.URL and title.
}

bool RoomBrowserWindow::UpdateToolbarSecurityState() {
  // The host's site button reads the security state from the page (3.3a).
  return false;
}

void RoomBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {}

void RoomBrowserWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {
  // BrowserView animates its tab strip; the host places the new contents.
}

void RoomBrowserWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

void RoomBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  // The host decides (Phase 3.4a); a window without a client closes.
  if (!client_) {
    std::move(callback).Run(true);
    return;
  }
  LOG(INFO) << "RoomCore: closing with " << download_count
            << " downloads in progress asks the host";
  client_->ConfirmCloseWithPendingDownloads(download_count,
                                            std::move(callback));
}

gfx::Size RoomBrowserWindow::GetContentsSize() const {
  content::WebContents* contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  return contents ? contents->GetContainerBounds().size() : gfx::Size();
}

namespace {

// The events the host's key delegates see: key-downs with their NSEvent
// (CEF's OnPreKeyEvent/OnKeyEvent take KEYEVENT_RAWKEYDOWN only, too).
bool IsHostKeyDown(const input::NativeWebKeyboardEvent& event) {
  NSEvent* ns_event = event.os_event.Get();
  return event.GetType() == blink::WebInputEvent::Type::kRawKeyDown &&
         ns_event && ns_event.type == NSEventTypeKeyDown;
}

}  // namespace

content::KeyboardEventProcessingResult
RoomBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // An extension's command (its keybinding registry, 3.6b: Chrome gives
  // extension accelerators high priority) and the host's reserved shortcuts
  // (⌘T, ⌘L, ⌘W …) never reach the page; the host runs its own itself (its
  // menu, once). Everything else goes to the page first.
  if (client_ && IsHostKeyDown(event) &&
      (client_->HandleExtensionKeyEvent(event) ||
       client_->IsReservedKeyEvent(event))) {
    return content::KeyboardEventProcessingResult::HANDLED;
  }
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool RoomBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // A key the page did not consume: the host's delegate gives it once to its
  // main menu (what views::UnhandledKeyboardEventHandler's redispatch does
  // for BrowserView). Content already drops skip_if_unhandled events and
  // keys of hidden pages; repeats arrive as key-downs with isARepeat.
  if (event.skip_if_unhandled || !IsHostKeyDown(event)) {
    return false;
  }
  if (!client_) {
    // DevTools' front-end lives in a headless DevTools Browser while the host
    // shows it in its pane (3.3b): a key it did not use (⌥⌘I, ⌘W) goes to
    // the host's main menu, as a page's does through the client.
    return browser_->GetType() == BrowserWindowInterface::TYPE_DEVTOOLS &&
           [NSApp.mainMenu performKeyEquivalent:event.os_event.Get()];
  }
  return client_->HandleUnhandledKeyEvent(event);
}

BrowserView* RoomBrowserWindow::AsBrowserView() {
  return nullptr;
}

ExclusiveAccessContext* RoomBrowserWindow::GetExclusiveAccessContext() {
  return exclusive_access_context_.get();
}

void RoomBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {
  // BrowserView focuses its LocationBarView; the address field is the
  // host's, which RoomLocationBar::FocusLocation asks for.
  GetLocationBar()->FocusLocation(is_user_initiated,
                                  /*clear_focus_if_failed=*/false);
}

bool RoomBrowserWindow::IsLocationBarVisible() const {
  // The host's address field is always reachable (⌘L opens the palette even
  // with the sidebar hidden, spec §C); IDC_FOCUS_LOCATION checks this first.
  return true;
}

bool RoomBrowserWindow::IsToolbarVisible() const {
  // The host's header is the window's toolbar: its action buttons show the
  // pinned extensions (3.6b). action.openPopup asks this first
  // (OpenPopupInBrowser: "Browser window has no toolbar."). Headless
  // Browsers have none.
  return !is_headless();
}

LocationBar* RoomBrowserWindow::GetLocationBar() const {
  if (!location_bar_) {
    location_bar_ = std::make_unique<room::RoomLocationBar>(browser_);
  }
  return location_bar_.get();
}

void RoomBrowserWindow::DeleteBrowserWindow() {
  delete this;
}

web_modal::WebContentsModalDialogHost*
RoomBrowserWindow::GetWebContentsModalDialogHost() {
  if (!objc_->modal_host) {
    objc_->modal_host = std::make_unique<RoomModalDialogHost>(
        objc_->window,
        base::BindRepeating(
            [](base::WeakPtr<RoomBrowserWindow> window)
                -> std::optional<gfx::Rect> {
              return window && window->client()
                         ? window->client()->GetBubbleAnchorRect()
                         : std::nullopt;
            },
            weak_factory_.GetWeakPtr()),
        base::BindRepeating(&RoomBrowserWindow::HideAutofillSuggestions,
                            weak_factory_.GetWeakPtr()));
    // TabDialogManager needs a primary Views widget as well as the native
    // modal parent. This context does not claim to own the page's WebView.
    BrowserElements::From(browser_)->AsA<BrowserElementsViewsImpl>()->Init(
        objc_->modal_host->GetBubbleAnchor());
  }
  return objc_->modal_host.get();
}

web_modal::WebContentsModalDialogHost*
RoomBrowserWindow::GetWebContentsModalDialogHostFor(content::WebContents*) {
  return GetWebContentsModalDialogHost();
}

// Chrome's autofill and password suggestion popups (PopupViewViews) close
// when their browser widget moves or resizes (PopupBaseView observes it as
// its parent widget, kWidgetChanged). A Room window is no Views widget, so the
// popup's parent is null and it would stay where it opened (3.7a: it stayed
// put after a 60 pt window move): close it the same way here.
void RoomBrowserWindow::HideAutofillSuggestions() {
  TabStripModel* strip = browser_->GetTabStripModel();
  for (int i = 0; i < strip->count(); ++i) {
    if (auto* client = autofill::ContentAutofillClient::FromWebContents(
            strip->GetWebContentsAt(i))) {
      client->HideSuggestions(autofill::SuggestionHidingReason::kWidgetChanged,
                              std::nullopt);
    }
  }
}

views::View* RoomBrowserWindow::GetBubbleAnchor() {
  GetWebContentsModalDialogHost();
  return objc_->modal_host->GetBubbleAnchor();
}

ShowTranslateBubbleResult RoomBrowserWindow::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  // BrowserView::ShowTranslateBubble without the Views toolbar: the same
  // controller (every Browser has one, BrowserWindowFeatures::Init), the
  // anchor the window's bubble anchor at the host's site button.
  TranslateBubbleController* controller =
      is_headless() ? nullptr : TranslateBubbleController::From(browser_);
  ChromeTranslateClient* client =
      contents ? ChromeTranslateClient::FromWebContents(contents) : nullptr;
  if (!controller || !client) {
    LOG(WARNING) << "RoomCore: no translate bubble (controller "
                 << !!controller << ", client " << !!client << ")";
    return ShowTranslateBubbleResult::kBrowserWindowNotValid;
  }
  client->GetTranslateManager()->GetLanguageState()->SetTranslateEnabled(true);
  if (IsMinimized()) {
    return ShowTranslateBubbleResult::kBrowserWindowMinimized;
  }
  views::Widget* widget = controller->ShowTranslateBubble(
      contents, views::BubbleAnchor(GetBubbleAnchor()), std::nullopt, step,
      source_language, target_language, error_type,
      is_user_gesture ? TranslateBubbleView::USER_GESTURE
                      : TranslateBubbleView::AUTOMATIC);
  LOG(INFO) << "RoomCore: translate bubble step " << static_cast<int>(step)
            << (widget ? " shown" : " updated or not shown");
  return ShowTranslateBubbleResult::kSuccess;
}

std::unique_ptr<FindBar> RoomBrowserWindow::CreateFindBar() {
  // Find in page is the host's (FindTabHelper, 3.3b): Chrome's find bar is
  // inert, never the Views FindBarHost.
  return std::make_unique<room::RoomFindBar>();
}

// The Cocoa host does not run Chrome's TabDragController. Its live TabStripModel
// can accept extension edits unless closing or explicitly disabled by a test.
bool RoomBrowserWindow::IsTabStripEditable() const {
  return !tab_strip_editing_disabled_ && !browser_->GetTabStripModel()->closing_all();
}

void RoomBrowserWindow::DisableTabStripEditingForTesting() {
  tab_strip_editing_disabled_ = true;
}
