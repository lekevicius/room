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
#include "chrome/browser/ui/views/frame/toolbar_button_provider.h"
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

// Private adapter for retained Chromium autofill bubbles. Do not register this
// as the browser's ToolbarButtonProvider: Room has no Chrome toolbar controls.
class RoomAutofillAnchors : public ToolbarButtonProvider {
 public:
  explicit RoomAutofillAnchors(RoomBrowserWindow* window) : window_(window) {}
  ExtensionsContainerViews* GetExtensionsContainerViews() override {
    return nullptr;
  }
  PinnedToolbarActions* GetPinnedToolbarActions() override { return nullptr; }
  gfx::Size GetToolbarButtonSize() const override { return {}; }
  views::BubbleAnchor GetDefaultExtensionDialogAnchor() override {
    return Anchor();
  }
  page_actions::PageActionViewInterface* GetPageActionViewInterface(
      actions::ActionId) override {
    return nullptr;
  }
  AppMenuControl* GetAppMenuControl() override { return nullptr; }
  gfx::Rect GetFindBarBoundingBox(int) override { return {}; }
  void FocusToolbar() override {}
  views::AccessiblePaneView* GetAsAccessiblePaneView() override {
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
    return nullptr;
  }
  ToolbarButton* GetBackButton() override { return nullptr; }
  ReloadControl* GetReloadButton() override { return nullptr; }
  ToolbarButton* GetDownloadButton() override { return nullptr; }
  WebUIToolbarWebView* GetWebUIToolbarViewForTesting() override {
    return nullptr;
  }

 private:
  views::BubbleAnchor Anchor() {
    return views::BubbleAnchor(window_->GetBubbleAnchor());
  }
  raw_ptr<RoomBrowserWindow> window_;
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
  explicit RoomModalDialogHost(NSWindow* window) : window_(window) {
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
        usingBlock:^(NSNotification*) { NotifyPositionRequiresUpdate(); }];
    move_observer_ = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowDidMoveNotification object:window queue:nil
        usingBlock:^(NSNotification*) { NotifyPositionRequiresUpdate(); }];
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
  views::View* GetBubbleAnchor() { return bubble_anchor_; }
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
  void UpdateBounds() {
    NSRect content = [window_.contentView convertRect:window_.contentView.bounds
                                               toView:nil];
    widget_->SetBounds(gfx::ScreenRectFromNSRect([window_ convertRectToScreen:content]));
  }
  NSWindow* __weak window_;
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
  PendingHostWindow* pending = g_pending_host_window;
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
    case WindowOpenDisposition::OFF_THE_RECORD:
      // Room has no private window yet (Chapter 4.8); an incognito Browser
      // would be headless and its page invisible. Cancel the navigation.
      LOG(WARNING) << "RoomCore: refused an off-the-record open from a Room "
                      "window (no private windows before Chapter 4.8)";
      *browser = nullptr;
      return true;
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
  std::unique_ptr<RoomAutofillAnchors> autofill_anchors;
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
  // Payment bubbles resolve AutofillBubbleHandler through window user data,
  // without calling the legacy BrowserWindow getter first.
  GetAutofillBubbleHandler();
}

autofill::AutofillBubbleHandler* RoomBrowserWindow::GetAutofillBubbleHandler() {
  if (!objc_->autofill_handler) {
    objc_->autofill_anchors = std::make_unique<RoomAutofillAnchors>(this);
    objc_->autofill_handler = std::make_unique<autofill::AutofillBubbleHandlerImpl>(
        browser_, objc_->autofill_anchors.get());
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
    UnloadController::DownloadCloseType dialog_type,
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
  // The host's reserved shortcuts (⌘T, ⌘L, ⌘W …) never reach the page; the
  // host runs them itself (its menu, once). Everything else goes to the page
  // first.
  if (client_ && IsHostKeyDown(event) && client_->IsReservedKeyEvent(event)) {
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
    objc_->modal_host = std::make_unique<RoomModalDialogHost>(objc_->window);
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

views::View* RoomBrowserWindow::GetBubbleAnchor() {
  GetWebContentsModalDialogHost();
  return objc_->modal_host->GetBubbleAnchor();
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
