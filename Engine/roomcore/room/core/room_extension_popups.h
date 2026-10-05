// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_EXTENSION_POPUPS_H_
#define ROOM_CORE_ROOM_EXTENSION_POPUPS_H_

#include <memory>
#include <string>

class BrowserWindowInterface;

namespace content {
class WebContents;
}
namespace input {
struct NativeWebKeyboardEvent;
}

@class RoomWebContents;

namespace room {

// The extensions side of one Room Browser (Phase 3.6b): Chrome's
// ExtensionsContainer registered as the Browser's user data (as
// WebUIBrowserWindow and ExtensionsToolbarDesktop do), the one action popup
// the window shows (an ExtensionViewHost whose page the host puts in its
// popover) and the window's extension keyboard shortcuts (an
// ExtensionKeybindingRegistry without Views). Created by RoomBrowser for the
// Browser it binds to a host window; destroyed before the Browser.
class RoomBrowserExtensions {
 public:
  static std::unique_ptr<RoomBrowserExtensions> Create(
      BrowserWindowInterface* browser);
  virtual ~RoomBrowserExtensions() = default;

  // A click on the host's action button for `contents` (the window's active
  // page): ExtensionActionRunner::RunAction with tab permissions (activeTab,
  // action.onClicked for an action without a popup), then the popup when the
  // action has one. True when a popup is opening.
  virtual bool RunActionFromHost(const std::string& extension_id,
                                 content::WebContents* contents) = 0;
  // Closes the popup whose page is `popup` (the host's popover closed).
  virtual void ClosePopup(content::WebContents* popup) = 0;
  // A key-down on its way to a page of this window: true when an extension
  // command took it (a named command's onCommand, `_execute_action`).
  virtual bool HandleKeyEvent(const input::NativeWebKeyboardEvent& event) = 0;
};

// The RoomBrowserExtensions whose popup shows `popup`, if any.
RoomBrowserExtensions* BrowserExtensionsForPopup(content::WebContents* popup);

}  // namespace room

#endif  // ROOM_CORE_ROOM_EXTENSION_POPUPS_H_
