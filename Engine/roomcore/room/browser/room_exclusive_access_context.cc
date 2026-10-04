// Copyright 2026 Jonas Lekevicius. All rights reserved.

#include "room/browser/room_exclusive_access_context.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "room/browser/room_browser_window.h"

namespace room {

namespace {

FullscreenController* GetFullscreenController(BrowserWindowInterface* browser) {
  ExclusiveAccessManager* manager =
      browser->GetFeatures().exclusive_access_manager();
  return manager ? manager->fullscreen_controller() : nullptr;
}

}  // namespace

RoomExclusiveAccessContext::RoomExclusiveAccessContext(
    BrowserWindowInterface* browser,
    RoomBrowserWindowClient* client)
    : browser_(browser), client_(client) {}

RoomExclusiveAccessContext::~RoomExclusiveAccessContext() = default;

Profile* RoomExclusiveAccessContext::GetProfile() {
  return browser_->GetProfile();
}

bool RoomExclusiveAccessContext::IsFullscreen() const {
  return fullscreen_;
}

void RoomExclusiveAccessContext::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {
  if (fullscreen_) {
    return;
  }
  FullscreenController* controller = GetFullscreenController(browser_);
  content::WebContents* contents =
      controller && controller->exclusive_access_tab()
          ? controller->exclusive_access_tab()
          : GetWebContentsForExclusiveAccess();
  if (!contents) {
    return;
  }
  fullscreen_ = true;
  bubble_type_ = bubble_type;
  fullscreen_contents_ = contents->GetWeakPtr();
  // Chrome expects the window's transition to finish later
  // (FullscreenController::WindowFullscreenStateChanged); the host animates
  // on its own, so the state is reported on the next task, and the host is
  // told after it, never inside FullscreenController's call.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&RoomExclusiveAccessContext::DidEnter,
                                weak_factory_.GetWeakPtr(),
                                contents->GetWeakPtr(), origin));
}

void RoomExclusiveAccessContext::DidEnter(
    base::WeakPtr<content::WebContents> contents,
    url::Origin origin) {
  NotifyWindowFullscreenStateChanged();
  if (fullscreen_ && contents && client_) {
    client_->OnTabFullscreenEntered(contents.get(), origin);
  }
}

void RoomExclusiveAccessContext::ExitFullscreen() {
  if (!fullscreen_) {
    return;
  }
  fullscreen_ = false;
  bubble_type_ = EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE;
  base::WeakPtr<content::WebContents> contents =
      std::move(fullscreen_contents_);
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&RoomExclusiveAccessContext::DidExit,
                                weak_factory_.GetWeakPtr(), contents));
}

void RoomExclusiveAccessContext::DidExit(
    base::WeakPtr<content::WebContents> contents) {
  NotifyWindowFullscreenStateChanged();
  if (!contents) {
    return;
  }
  // Chrome tells the renderer through the resize its window makes when it
  // leaves fullscreen (WebContents::ExitFullscreen(will_cause_resize=true)).
  // The host may not resize at all (it refused the request, or the page was
  // not edge to edge yet): send the visual properties now, or the document
  // keeps its fullscreen element.
  if (content::RenderWidgetHostView* view =
          contents->GetRenderWidgetHostView()) {
    view->GetRenderWidgetHost()->SynchronizeVisualProperties();
  }
  if (client_) {
    client_->OnTabFullscreenExited(contents.get());
  }
}

void RoomExclusiveAccessContext::NotifyWindowFullscreenStateChanged() {
  if (FullscreenController* controller = GetFullscreenController(browser_)) {
    controller->WindowFullscreenStateChanged();
  }
}

void RoomExclusiveAccessContext::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
  // Chrome's bubble is a Views widget anchored on BrowserView; the host has
  // no exit instruction yet. Record what Chrome would show.
  if (params.type != EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE || !params.has_download) {
    bubble_type_ = params.type;
  }
  if (first_hide_callback) {
    std::move(first_hide_callback)
        .Run(ExclusiveAccessBubbleHideReason::kNotShown);
  }
}

bool RoomExclusiveAccessContext::IsExclusiveAccessBubbleDisplayed() const {
  return false;
}

void RoomExclusiveAccessContext::OnExclusiveAccessUserInput() {}

content::WebContents*
RoomExclusiveAccessContext::GetWebContentsForExclusiveAccess() {
  return browser_->GetTabStripModel()->GetActiveWebContents();
}

bool RoomExclusiveAccessContext::CanUserEnterFullscreen() const {
  return true;
}

bool RoomExclusiveAccessContext::CanUserExitFullscreen() const {
  return true;
}

}  // namespace room
