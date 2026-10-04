// Copyright 2026 Jonas Lekevicius. All rights reserved.

#include "room/browser/room_find_bar.h"

namespace room {

RoomFindBar::RoomFindBar() = default;
RoomFindBar::~RoomFindBar() = default;

FindBarController* RoomFindBar::GetFindBarController() const {
  return controller_;
}

void RoomFindBar::SetFindBarController(FindBarController* find_bar_controller) {
  controller_ = find_bar_controller;
}

void RoomFindBar::Show(bool animate, bool focus) {
  visible_ = true;
}

void RoomFindBar::Hide(bool animate) {
  visible_ = false;
}

void RoomFindBar::SetFocusAndSelection() {}

void RoomFindBar::ClearResults(
    const find_in_page::FindNotificationDetails& results) {}

void RoomFindBar::StopAnimation() {}

void RoomFindBar::MoveWindowIfNecessary() {}

void RoomFindBar::SetFindTextAndSelectedRange(const std::u16string& find_text,
                                              const gfx::Range& selected_range) {
  text_ = find_text;
  selection_ = selected_range;
}

std::u16string_view RoomFindBar::GetFindText() const {
  return text_;
}

gfx::Range RoomFindBar::GetSelectedRange() const {
  return selection_;
}

void RoomFindBar::UpdateUIForFindResult(
    const find_in_page::FindNotificationDetails& result,
    const std::u16string& find_text) {}

void RoomFindBar::AudibleAlert() {}

bool RoomFindBar::IsFindBarVisible() const {
  return visible_;
}

void RoomFindBar::RestoreSavedFocus() {}

bool RoomFindBar::HasGlobalFindPasteboard() const {
  // The host's find bar owns the macOS find pasteboard.
  return false;
}

void RoomFindBar::UpdateFindBarForChangedWebContents() {}

bool RoomFindBar::CanPopulateFromSelectedText() {
  return false;
}

const FindBarTesting* RoomFindBar::GetFindBarTesting() const {
  return nullptr;
}

bool RoomFindBar::HasFocus() const {
  return false;
}

void RoomFindBar::CloseOverlappingBubbles() {}

views::Widget* RoomFindBar::GetHostWidget() {
  return nullptr;
}

}  // namespace room
