// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_BROWSER_ROOM_FIND_BAR_H_
#define ROOM_BROWSER_ROOM_FIND_BAR_H_

#include <string>
#include <string_view>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "ui/gfx/range/range.h"

namespace room {

// Chrome's FindBar for a Room window: inert. Find in page is the host's
// (its find bar drives FindTabHelper, Phase 3.3b), so Chrome's find commands
// keep a text and a visibility flag and draw nothing.
class RoomFindBar : public FindBar {
 public:
  RoomFindBar();
  RoomFindBar(const RoomFindBar&) = delete;
  RoomFindBar& operator=(const RoomFindBar&) = delete;
  ~RoomFindBar() override;

  // FindBar:
  FindBarController* GetFindBarController() const override;
  void SetFindBarController(FindBarController* find_bar_controller) override;
  void Show(bool animate, bool focus) override;
  void Hide(bool animate) override;
  void SetFocusAndSelection() override;
  void ClearResults(
      const find_in_page::FindNotificationDetails& results) override;
  void StopAnimation() override;
  void MoveWindowIfNecessary() override;
  void SetFindTextAndSelectedRange(const std::u16string& find_text,
                                   const gfx::Range& selected_range) override;
  std::u16string_view GetFindText() const override;
  gfx::Range GetSelectedRange() const override;
  void UpdateUIForFindResult(const find_in_page::FindNotificationDetails& result,
                             const std::u16string& find_text) override;
  void AudibleAlert() override;
  bool IsFindBarVisible() const override;
  void RestoreSavedFocus() override;
  bool HasGlobalFindPasteboard() const override;
  void UpdateFindBarForChangedWebContents() override;
  bool CanPopulateFromSelectedText() override;
  const FindBarTesting* GetFindBarTesting() const override;
  bool HasFocus() const override;
  void CloseOverlappingBubbles() override;
  views::Widget* GetHostWidget() override;

 private:
  raw_ptr<FindBarController> controller_ = nullptr;
  std::u16string text_;
  gfx::Range selection_;
  bool visible_ = false;
};

}  // namespace room

#endif  // ROOM_BROWSER_ROOM_FIND_BAR_H_
