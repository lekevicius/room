// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_BROWSER_ROOM_LOCATION_BAR_H_
#define ROOM_BROWSER_ROOM_LOCATION_BAR_H_

#include <optional>
#include <string>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/location_bar/location_bar.h"

namespace room {

// Chrome's LocationBar for a RoomBrowserWindow. The address field is the
// host's; Chrome only needs an object to call into (Browser saves and restores
// per-tab omnibox state through it, for example). Everything is a no-op that
// reports "nothing to show".
class RoomLocationBar : public LocationBar {
 public:
  explicit RoomLocationBar(BrowserWindowInterface* browser);
  RoomLocationBar(const RoomLocationBar&) = delete;
  RoomLocationBar& operator=(const RoomLocationBar&) = delete;
  ~RoomLocationBar() override;

  // LocationBar:
  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override;
  void FocusSearch() override;
  void UpdateFocusBehavior(bool toolbar_visible) override;
  void UpdateContentSettingsIcons() override;
  void SaveStateToContents(content::WebContents* contents) override;
  void Revert() override;
  OmniboxView* GetOmniboxView() override;
  OmniboxPopupView* GetOmniboxPopupView() override;
  OmniboxController* GetOmniboxController() override;
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override;
  content::WebContents* GetWebContents() override;
  LocationBarModel* GetLocationBarModel() override;
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override;
  ChipController* GetChipController() override;
  void AnnounceAlert(const std::u16string& announcement) override;
  void OnChanged() override;
  void UpdateWithoutTabRestore() override;
  ui::TrackedElement* GetAnchorOrNull() override;
  BrowserWindowInterface* GetBrowser() override;
  Profile* GetProfile() override;
  bool IsInitialized() const override;
  bool IsVisible() const override;
  bool IsDrawn() const override;
  bool IsFullscreen() const override;
  bool IsEditingOrEmpty() const override;
  bool IsMouseHovered() const override;
  bool IsFocusWithin() const override;
  void InvalidateLayout() override;
  gfx::Rect Bounds() const override;
  gfx::Rect BoundsInScreen() const override;
  gfx::Size MinimumSize() const override;
  gfx::Size PreferredSize() const override;
  void Update(content::WebContents* contents) override;
  void ResetTabState(content::WebContents* contents) override;
  bool HasSecurityStateChanged() override;
  LocationBarTesting* GetLocationBarForTesting() override;

 private:
  raw_ptr<BrowserWindowInterface> browser_;
  bool logged_model_request_ = false;
};

}  // namespace room

#endif  // ROOM_BROWSER_ROOM_LOCATION_BAR_H_
