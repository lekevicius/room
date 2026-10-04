// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/browser/room_browser_window.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <map>

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
#include "chrome/browser/ui/views/find_bar_host.h"
#include "chrome/browser/ui/views/interaction/browser_elements_views_impl.h"
#include "chrome/browser/ui/views/find_bar_owner.h"
#include "chrome/browser/ui/views/autofill/autofill_bubble_handler_impl.h"
#include "chrome/browser/ui/views/frame/toolbar_button_provider.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "room/browser/room_exclusive_access_context.h"
#include "room/browser/room_location_bar.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/views/widget/widget.h"

namespace room {
// Defined in chrome/browser/ui/views/frame/browser_window_factory.cc
// (patches/0003-browser-window-factory-hook.patch).
extern BrowserWindow* (*g_create_browser_window_hook)(BrowserWindowInterface*);
extern views::View* (*g_fedcm_anchor_hook)(BrowserWindowInterface*);
extern BrowserWindow* (*g_find_browser_window_hook)(content::WebContents*);
extern std::unique_ptr<SadTab> (*g_create_sad_tab_hook)(content::WebContents*, SadTabKind);
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
    [window addChildWindow:widget_->GetNativeWindow().GetNativeNSWindow()
                  ordered:NSWindowBelow];
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

// Chrome's find implementation is decoupled from BrowserView by this owner.
class RoomFindBarOwner : public FindBarOwner {
 public:
  explicit RoomFindBarOwner(RoomBrowserWindow* window)
      : FindBarOwner(window->browser()->GetUnownedUserDataHost()),
        window_(window) {}
  views::Widget* GetOwnerWidget() override {
    return window_->GetBubbleAnchor()->GetWidget();
  }
  gfx::Rect GetFindBarBoundingBox() override {
    return GetOwnerWidget()->GetContentsView()->GetLocalBounds();
  }
  gfx::Rect GetFindBarClippingBox() override {
    return GetFindBarBoundingBox();
  }
  bool IsOffTheRecord() const override {
    return window_->browser()->GetProfile()->IsOffTheRecord();
  }
  views::Widget* GetWidgetForAnchoring() override { return GetOwnerWidget(); }
  std::u16string GetFindBarAccessibleWindowTitle() override {
    return u"Find in page";
  }
  void OnFindBarVisibilityChanged(gfx::Rect) override {
    window_->browser()->GetFeatures().GetFindBarController()
        ->OnFindBarVisibilityChanged();
  }
  void CloseOverlappingBubbles() override {}
 private:
  raw_ptr<RoomBrowserWindow> window_;
};

struct PendingHostWindow {
  NSWindow* __weak window = nil;
  raw_ptr<room::RoomBrowserWindowClient> client = nullptr;
};

// Set while a RoomBrowser creates its Browser; Browser's constructor calls the
// factory hook synchronously.
PendingHostWindow* g_pending_host_window = nullptr;

BrowserWindow* CreateRoomBrowserWindow(BrowserWindowInterface* browser) {
  if (!g_pending_host_window || !g_pending_host_window->window) {
    return nullptr;
  }
  PendingHostWindow* pending = g_pending_host_window;
  // One Browser per pending window: anything Browser's constructor creates in
  // turn (it does not today) gets a normal BrowserView.
  g_pending_host_window = nullptr;
  return new RoomBrowserWindow(browser, pending->window, pending->client);
}

}  // namespace

namespace room {

void InstallBrowserWindowFactory() {
  g_create_browser_window_hook = &CreateRoomBrowserWindow;
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
  std::unique_ptr<RoomFindBarOwner> find_owner;
  std::unique_ptr<RoomAutofillAnchors> autofill_anchors;
  std::unique_ptr<autofill::AutofillBubbleHandlerImpl> autofill_handler;
};

RoomBrowserWindow::RoomBrowserWindow(BrowserWindowInterface* browser,
                                     NSWindow* window,
                                     room::RoomBrowserWindowClient* client)
    : browser_(browser),
      client_(client),
      objc_(std::make_unique<ObjCMembers>(ObjCMembers{window, nullptr, nullptr,
                                                   nullptr, nullptr})),
      exclusive_access_context_(
          std::make_unique<room::RoomExclusiveAccessContext>(browser)) {
  RoomWindows().emplace(browser, this);
  // Payment bubbles resolve AutofillBubbleHandler through window user data,
  // without calling the legacy BrowserWindow getter first.
  GetAutofillBubbleHandler();
}

autofill::AutofillBubbleHandler* RoomBrowserWindow::GetAutofillBubbleHandler() {
  RoomStubHit("GetAutofillBubbleHandler");
  if (!objc_->autofill_handler) {
    objc_->autofill_anchors = std::make_unique<RoomAutofillAnchors>(this);
    objc_->autofill_handler = std::make_unique<autofill::AutofillBubbleHandlerImpl>(
        browser_, objc_->autofill_anchors.get());
  }
  return objc_->autofill_handler.get();
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

gfx::Rect RoomBrowserWindow::GetBounds() const {
  NSWindow* window = objc_->window;
  return window ? gfx::ScreenRectFromNSRect(window.frame) : gfx::Rect();
}

void RoomBrowserWindow::Show() {
  // Same as BrowserView::Show() on macOS: the Browser must be the last active
  // one as soon as it is shown, before AppKit reports the activation.
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  [objc_->window makeKeyAndOrderFront:nil];
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
  // Match NativeWidgetNSWindowBridge: AppKit must activate the application
  // before making its window key, or an inactive app can retain no key window.
  [NSApp activateIgnoringOtherApps:YES];
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  [objc_->window makeKeyAndOrderFront:nil];
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

gfx::Size RoomBrowserWindow::GetContentsSize() const {
  content::WebContents* contents =
      browser_->GetTabStripModel()->GetActiveWebContents();
  return contents ? contents->GetContainerBounds().size() : gfx::Size();
}

content::KeyboardEventProcessingResult
RoomBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // Every key goes to the page first; the host's reserved shortcuts are
  // matched by its own menu before the event reaches the web view.
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool RoomBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // A key the page did not consume: give it once to the host's main menu
  // (what views::UnhandledKeyboardEventHandler does for BrowserView).
  if (event.skip_if_unhandled) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  if (!ns_event || ns_event.type != NSEventTypeKeyDown) {
    return false;
  }
  return [NSApp.mainMenu performKeyEquivalent:ns_event];
}

BrowserView* RoomBrowserWindow::AsBrowserView() {
  return nullptr;
}

ExclusiveAccessContext* RoomBrowserWindow::GetExclusiveAccessContext() {
  return exclusive_access_context_.get();
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
  RoomStubHit("GetWebContentsModalDialogHost");
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
  RoomStubHit("GetWebContentsModalDialogHostFor");
  return GetWebContentsModalDialogHost();
}

views::View* RoomBrowserWindow::GetBubbleAnchor() {
  GetWebContentsModalDialogHost();
  return objc_->modal_host->GetBubbleAnchor();
}

std::unique_ptr<FindBar> RoomBrowserWindow::CreateFindBar() {
  RoomStubHit("CreateFindBar");
  if (!objc_->find_owner) {
    objc_->find_owner = std::make_unique<RoomFindBarOwner>(this);
  }
  return std::make_unique<FindBarHost>(objc_->find_owner.get());
}

// The Cocoa host does not run Chrome's TabDragController. Its live TabStripModel
// can accept extension edits unless closing or explicitly disabled by a test.
bool RoomBrowserWindow::IsTabStripEditable() const {
  RoomStubHit("IsTabStripEditable");
  return !tab_strip_editing_disabled_ && !browser_->GetTabStripModel()->closing_all();
}

void RoomBrowserWindow::DisableTabStripEditingForTesting() {
  RoomStubHit("DisableTabStripEditingForTesting");
  tab_strip_editing_disabled_ = true;
}
