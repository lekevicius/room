// Copyright 2026 Jonas Lekevicius. All rights reserved.

#include "room/browser/room_exclusive_access_context.h"

#include <utility>

#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"

namespace room {

RoomExclusiveAccessContext::RoomExclusiveAccessContext(
    BrowserWindowInterface* browser)
    : browser_(browser) {}

RoomExclusiveAccessContext::~RoomExclusiveAccessContext() = default;

Profile* RoomExclusiveAccessContext::GetProfile() {
  return browser_->GetProfile();
}

bool RoomExclusiveAccessContext::IsFullscreen() const {
  return false;
}

void RoomExclusiveAccessContext::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {}

void RoomExclusiveAccessContext::ExitFullscreen() {}

void RoomExclusiveAccessContext::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
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
  return false;
}

bool RoomExclusiveAccessContext::CanUserExitFullscreen() const {
  return true;
}

}  // namespace room
