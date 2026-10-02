// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/browser/room_browser_window.h"

#import <AppKit/AppKit.h>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_manager_service.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "room/browser/room_exclusive_access_context.h"
#include "room/browser/room_location_bar.h"
#include "ui/gfx/mac/coordinate_conversion.h"

namespace room {
// Defined in chrome/browser/ui/views/frame/browser_window_factory.cc
// (patches/0003-browser-window-factory-hook.patch).
extern BrowserWindow* (*g_create_browser_window_hook)(BrowserWindowInterface*);
}  // namespace room

namespace {

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
};

RoomBrowserWindow::RoomBrowserWindow(BrowserWindowInterface* browser,
                                     NSWindow* window,
                                     room::RoomBrowserWindowClient* client)
    : browser_(browser),
      client_(client),
      objc_(std::make_unique<ObjCMembers>(ObjCMembers{window})),
      exclusive_access_context_(
          std::make_unique<room::RoomExclusiveAccessContext>(browser)) {}

RoomBrowserWindow::~RoomBrowserWindow() {
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
