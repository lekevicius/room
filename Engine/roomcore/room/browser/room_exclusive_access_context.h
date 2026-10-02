// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_BROWSER_ROOM_EXCLUSIVE_ACCESS_CONTEXT_H_
#define ROOM_BROWSER_ROOM_EXCLUSIVE_ACCESS_CONTEXT_H_

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"

class BrowserWindowInterface;

namespace room {

// Chrome's ExclusiveAccessContext (tab fullscreen, pointer and keyboard lock)
// for a RoomBrowserWindow. Chrome calls into it on every user input; until
// the host implements page fullscreen (Chapter 3), it refuses fullscreen and
// shows no bubbles.
class RoomExclusiveAccessContext : public ExclusiveAccessContext {
 public:
  explicit RoomExclusiveAccessContext(BrowserWindowInterface* browser);
  RoomExclusiveAccessContext(const RoomExclusiveAccessContext&) = delete;
  RoomExclusiveAccessContext& operator=(const RoomExclusiveAccessContext&) =
      delete;
  ~RoomExclusiveAccessContext() override;

  // ExclusiveAccessContext:
  Profile* GetProfile() override;
  bool IsFullscreen() const override;
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override;
  void ExitFullscreen() override;
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override;
  bool IsExclusiveAccessBubbleDisplayed() const override;
  void OnExclusiveAccessUserInput() override;
  content::WebContents* GetWebContentsForExclusiveAccess() override;
  bool CanUserEnterFullscreen() const override;
  bool CanUserExitFullscreen() const override;

 private:
  raw_ptr<BrowserWindowInterface> browser_;
};

}  // namespace room

#endif  // ROOM_BROWSER_ROOM_EXCLUSIVE_ACCESS_CONTEXT_H_
