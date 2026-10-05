// Copyright 2026 Jonas Lekevicius. All rights reserved.

#include "room/browser/room_location_bar.h"

#include "base/logging.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "components/omnibox/browser/location_bar_model.h"
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
                                    bool clear_focus_if_failed) {
  auto* window =
      static_cast<RoomBrowserWindow*>(BrowserWindow::FromBrowser(browser_));
  LOG(INFO) << "RoomLocationBar: FocusLocation (user initiated "
            << is_user_initiated << ") to the host";
  if (window && window->client()) {
    window->client()->OnFocusLocationBarRequested(is_user_initiated);
  }
}
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
  // The Browser's own model (BrowserWindowFeatures, over
  // BrowserLocationBarModelDelegate): the active page's URL and its
  // chrome_security_state level, the same source the host's site button
  // reads through RoomWebContents.securityLevel.
  LocationBarModel* model =
      browser_->GetFeatures().location_bar_model();
  if (!logged_model_request_ && model) {
    logged_model_request_ = true;
    LOG(INFO) << "RoomLocationBar: GetLocationBarModel asked; security level "
              << static_cast<int>(model->GetSecurityLevel());
  }
  return model;
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
