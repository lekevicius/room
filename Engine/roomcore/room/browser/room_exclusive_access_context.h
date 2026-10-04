// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_BROWSER_ROOM_EXCLUSIVE_ACCESS_CONTEXT_H_
#define ROOM_BROWSER_ROOM_EXCLUSIVE_ACCESS_CONTEXT_H_

#include <optional>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_type.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"

class BrowserWindowInterface;

namespace content {
class WebContents;
}

namespace room {

class RoomBrowserWindowClient;

// Chrome's ExclusiveAccessContext (tab fullscreen, pointer and keyboard lock)
// for a RoomBrowserWindow, tied to the host's element fullscreen (the app's
// PageFullscreen): Chrome's FullscreenController decides, this context tells
// the host through the client (posted) and reports Chrome's own state back,
// so the page's requestFullscreen() promise resolves and Esc, the page's
// exitFullscreen() and the host's WebContents::ExitFullscreen() all leave.
//
// IsFullscreen() is tab fullscreen only: window fullscreen (the green
// button) is the host's, and Chrome's "browser fullscreen" (IDC_FULLSCREEN)
// is not reachable from Room's menu, so a page fullscreen always starts from
// the normal state as far as Chrome is concerned.
//
// Pointer lock and keyboard lock are Chrome's controllers unchanged; the
// exclusive access bubble (Chrome's "Press Esc to exit" Views bubble) is not
// shown: the bubble state is recorded and reported, the host draws no
// instruction yet (backlog, Phase 3.4b).
class RoomExclusiveAccessContext : public ExclusiveAccessContext {
 public:
  RoomExclusiveAccessContext(BrowserWindowInterface* browser,
                             RoomBrowserWindowClient* client);
  RoomExclusiveAccessContext(const RoomExclusiveAccessContext&) = delete;
  RoomExclusiveAccessContext& operator=(const RoomExclusiveAccessContext&) =
      delete;
  ~RoomExclusiveAccessContext() override;

  // The bubble Chrome last asked for (none while nothing is exclusive).
  ExclusiveAccessBubbleType bubble_type() const { return bubble_type_; }

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
  void DidEnter(base::WeakPtr<content::WebContents> contents,
                url::Origin origin);
  void DidExit(base::WeakPtr<content::WebContents> contents);
  void NotifyWindowFullscreenStateChanged();

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<RoomBrowserWindowClient> client_;
  bool fullscreen_ = false;
  base::WeakPtr<content::WebContents> fullscreen_contents_;
  ExclusiveAccessBubbleType bubble_type_ = EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE;
  base::WeakPtrFactory<RoomExclusiveAccessContext> weak_factory_{this};
};

}  // namespace room

#endif  // ROOM_BROWSER_ROOM_EXCLUSIVE_ACCESS_CONTEXT_H_
