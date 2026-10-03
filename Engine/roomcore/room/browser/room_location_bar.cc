// Copyright 2026 Jonas Lekevicius. All rights reserved.

#include "room/browser/room_location_bar.h"

#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "room/browser/room_browser_window.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace room {

RoomLocationBar::RoomLocationBar(BrowserWindowInterface* browser)
    : LocationBar(chrome::BrowserCommandController::From(browser)),
      browser_(browser) {}

RoomLocationBar::~RoomLocationBar() = default;

void RoomLocationBar::FocusLocation(bool is_user_initiated,
                                    bool clear_focus_if_failed) {}
void RoomLocationBar::FocusSearch() {}
void RoomLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}
void RoomLocationBar::UpdateContentSettingsIcons() {}
void RoomLocationBar::SaveStateToContents(content::WebContents* contents) {}
void RoomLocationBar::Revert() {}

OmniboxView* RoomLocationBar::GetOmniboxView() {
  return nullptr;
}

OmniboxPopupView* RoomLocationBar::GetOmniboxPopupView() {
  return nullptr;
}

OmniboxController* RoomLocationBar::GetOmniboxController() {
  return nullptr;
}

bool RoomLocationBar::ShouldCloseOmniboxPopup(ui::MouseEvent* event) {
  return false;
}

content::WebContents* RoomLocationBar::GetWebContents() {
  return browser_->GetTabStripModel()->GetActiveWebContents();
}

LocationBarModel* RoomLocationBar::GetLocationBarModel() {
  return nullptr;
}

std::optional<bubble_anchor_util::AnchorConfiguration>
RoomLocationBar::GetChipAnchor() {
  // This existing LocationBar hook precedes Chrome's BrowserView-only
  // fallback. Supply a real Views anchor, without impersonating BrowserView.
  auto* window = static_cast<RoomBrowserWindow*>(
      BrowserWindow::FromBrowser(browser_));
  return bubble_anchor_util::AnchorConfiguration{
      views::BubbleAnchor(window->GetBubbleAnchor()), std::nullopt,
      views::BubbleBorder::TOP_LEFT};
}

ChipController* RoomLocationBar::GetChipController() {
  return nullptr;
}

void RoomLocationBar::AnnounceAlert(const std::u16string& announcement) {}
void RoomLocationBar::OnChanged() {}
void RoomLocationBar::UpdateWithoutTabRestore() {}

ui::TrackedElement* RoomLocationBar::GetAnchorOrNull() {
  return nullptr;
}

BrowserWindowInterface* RoomLocationBar::GetBrowser() {
  return browser_;
}

Profile* RoomLocationBar::GetProfile() {
  return browser_->GetProfile();
}

bool RoomLocationBar::IsInitialized() const {
  return true;
}

bool RoomLocationBar::IsVisible() const {
  return false;
}

bool RoomLocationBar::IsDrawn() const {
  return false;
}

bool RoomLocationBar::IsFullscreen() const {
  return false;
}

bool RoomLocationBar::IsEditingOrEmpty() const {
  return false;
}

bool RoomLocationBar::IsMouseHovered() const {
  return false;
}

bool RoomLocationBar::IsFocusWithin() const {
  return false;
}

void RoomLocationBar::InvalidateLayout() {}

gfx::Rect RoomLocationBar::Bounds() const {
  return gfx::Rect();
}

gfx::Rect RoomLocationBar::BoundsInScreen() const {
  return gfx::Rect();
}

gfx::Size RoomLocationBar::MinimumSize() const {
  return gfx::Size();
}

gfx::Size RoomLocationBar::PreferredSize() const {
  return gfx::Size();
}

void RoomLocationBar::Update(content::WebContents* contents) {}
void RoomLocationBar::ResetTabState(content::WebContents* contents) {}

bool RoomLocationBar::HasSecurityStateChanged() {
  return false;
}

LocationBarTesting* RoomLocationBar::GetLocationBarForTesting() {
  return nullptr;
}

}  // namespace room
