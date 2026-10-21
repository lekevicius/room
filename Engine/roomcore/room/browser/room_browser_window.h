// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_BROWSER_ROOM_BROWSER_WINDOW_H_
#define ROOM_BROWSER_ROOM_BROWSER_WINDOW_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/browser_window.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/geometry/rect.h"
#include "url/gurl.h"
#include "url/origin.h"

#ifdef __OBJC__
@class NSWindow;
#else
class NSWindow;
#endif

struct NavigateParams;

namespace content {
class WebContents;
}
namespace input {
struct NativeWebKeyboardEvent;
}
namespace views {
class View;
}

class RoomBrowserWindow;

namespace room {

class RoomExclusiveAccessContext;
class RoomLocationBar;

// How Chrome's Navigate() is opening the next contents a Room Browser
// receives (recorded by the navigator hook, patches/0014, consumed when the
// contents is inserted into the Browser's tab strip).
struct PendingOpen {
  PendingOpen();
  PendingOpen(const PendingOpen&);
  PendingOpen& operator=(const PendingOpen&);
  ~PendingOpen();

  WindowOpenDisposition disposition = WindowOpenDisposition::UNKNOWN;
  // The page's requested window rect (window.open features) or the
  // picture-in-picture size (origin 0,0); empty when the page asked nothing.
  gfx::Rect requested_bounds;
  GURL url;
  bool user_gesture = false;
  base::WeakPtr<content::WebContents> source;
};

// What a RoomBrowserWindow reports back to its RoomBrowser (//room/core).
class RoomBrowserWindowClient {
 public:
  virtual ~RoomBrowserWindowClient() = default;
  virtual void OnActiveContentsChanged(content::WebContents* contents) = 0;
  // Chrome asked to show `contents` (WebContentsDelegate::ActivateContents:
  // picture-in-picture's back to tab, a page's opener.focus(), a
  // notification's click): Chrome made it the strip's active tab and
  // activates the window; the host selects the page (B-107).
  virtual void OnActivationRequested(content::WebContents* contents) = 0;
  // Tab fullscreen (the ExclusiveAccessContext): the page asked for element
  // fullscreen and Chrome granted it; the host makes the page fill the
  // window. Posted, never re-entrant.
  virtual void OnTabFullscreenEntered(content::WebContents* contents,
                                      const url::Origin& origin) = 0;
  // Tab fullscreen ended (the page, Esc, or the host's exitFullscreen).
  virtual void OnTabFullscreenExited(content::WebContents* contents) = 0;
  // Chromium is closing the window: the tabs are gone, the Browser is about
  // to be destroyed.
  virtual void OnBrowserWindowWillClose() = 0;
  // The Browser and its window are destroyed.
  virtual void OnBrowserWindowDestroyed() = 0;
  // A key-down on its way to the focused page, before the renderer sees it:
  // true when the host reserves it (the page never gets it).
  virtual bool IsReservedKeyEvent(const input::NativeWebKeyboardEvent& event) = 0;
  // A key-down the page did not consume: the host's turn (its main menu).
  virtual bool HandleUnhandledKeyEvent(
      const input::NativeWebKeyboardEvent& event) = 0;
  // Navigate() is about to open a page from a page of this window with a
  // tab, popup or window disposition (a modifier click, target=_blank,
  // window.open): false cancels it (the host's navigation policy).
  virtual bool AllowOpenFromTab(const NavigateParams& params) = 0;
  // Navigate() is about to open a page from a page of this window in an
  // off-the-record window (OFF_THE_RECORD: Chrome's "Open link in incognito
  // window"): the Browser of the profile's off-the-record twin that receives
  // it (4.8b), or nullptr to cancel the open.
  virtual BrowserWindowInterface* BrowserForOffTheRecord() = 0;
  // Chrome is closing the window (the quit) with downloads in progress,
  // which closing cancels: the host decides (true continues).
  virtual void ConfirmCloseWithPendingDownloads(
      int download_count,
      base::OnceCallback<void(bool)> callback) = 0;
  // A key-down on its way to a page of this window (or its extension
  // popup), before the host's reserved keys: true when an extension command
  // took it (3.6b).
  virtual bool HandleExtensionKeyEvent(
      const input::NativeWebKeyboardEvent& event) = 0;
  // Chrome wants the address field focused (IDC_FOCUS_LOCATION,
  // chrome::FocusLocationBar, LocationBar::FocusLocation): the host's field.
  virtual void OnFocusLocationBarRequested(bool is_user_initiated) = 0;
  // Where Chrome's Views bubbles point (passwords, address and card saves,
  // choosers, FedCM, permission chips): the host's site button, in the
  // NSWindow's coordinates (AppKit, bottom-left origin), asked through the
  // active page's delegate (3.7a); nullopt: RoomCore's default corner.
  virtual std::optional<gfx::Rect> GetBubbleAnchorRect() = 0;
};

// Installs the BrowserWindow factory hook (patches/0003): a Browser created
// inside a ScopedPendingHostWindow gets a RoomBrowserWindow bound to that
// window. Chrome's BrowserView is refused for every other Browser: it gets a
// headless RoomBrowserWindow (no NSWindow, nothing drawn) and a log line, so
// a Chrome window never appears. Also installs the navigator hook
// (patches/0014): new contents of every disposition opened from a Room
// Browser stay in that Browser, where its host places them.
void InstallBrowserWindowFactory();

// The RoomBrowserWindow of a Browser //room created; nullptr otherwise.
RoomBrowserWindow* RoomBrowserWindowFor(BrowserWindowInterface* browser);

class ScopedPendingHostWindow {
 public:
  ScopedPendingHostWindow(NSWindow* window, RoomBrowserWindowClient* client);
  ScopedPendingHostWindow(const ScopedPendingHostWindow&) = delete;
  ScopedPendingHostWindow& operator=(const ScopedPendingHostWindow&) = delete;
  ~ScopedPendingHostWindow();
};

}  // namespace room

// Chrome's BrowserWindow for a window the Swift host owns. It draws nothing:
// the host's NSWindow and views are the UI. The members Chrome reaches for
// are real (window state from the NSWindow, show/close lifecycle, active tab,
// unhandled keys, tab fullscreen through the host, and the toolbar/status
// members as deliberate no-ops: the host observes that state itself); the
// rest are stubs in room_browser_window_stubs.cc, generated by
// Engine/roomcore/tools/gen_browser_window_stubs.py, that log their first
// hit. A RoomBrowserWindow with no NSWindow is headless: Chrome made the
// Browser, not //room (see InstallBrowserWindowFactory).
class RoomBrowserWindow : public BrowserWindow {
 public:
  RoomBrowserWindow(BrowserWindowInterface* browser,
                    NSWindow* window,
                    room::RoomBrowserWindowClient* client);
  RoomBrowserWindow(const RoomBrowserWindow&) = delete;
  RoomBrowserWindow& operator=(const RoomBrowserWindow&) = delete;
  ~RoomBrowserWindow() override;

  BrowserWindowInterface* browser() const { return browser_; }
  // Internal Views bridge for Chrome bubbles; the host owns the address UI.
  // Positioned at the host's anchor rect (the client's GetBubbleAnchorRect)
  // each time it is asked for and when the window moves or resizes.
  views::View* GetBubbleAnchor();

  // A Browser //room did not create: no host window, nothing drawn.
  bool is_headless() const;
  // Its strip emptied and Chrome destroys it after this task: a new page
  // must not join it (B-81).
  bool is_closing() const { return destroy_posted_; }
  room::RoomBrowserWindowClient* client() const { return client_; }

  // Records how the next inserted contents is being opened (navigator hook).
  void SetPendingOpen(const room::PendingOpen& pending);
  std::optional<room::PendingOpen> TakePendingOpen();

  // ui::BaseWindow and BrowserWindow members with real implementations
  // (room_browser_window.mm; listed in tools/browser_window_real_members.txt).
  bool IsActive() const override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  bool IsFullscreen() const override;
  gfx::NativeWindow GetNativeWindow() const override;
  gfx::Rect GetRestoredBounds() const override;
  ui::mojom::WindowShowState GetRestoredState() const override;
  gfx::Rect GetBounds() const override;
  void Show() override;
  void Hide() override;
  bool IsVisible() const override;
  void ShowInactive() override;
  void Close() override;
  void Activate() override;
  void Deactivate() override;
  void Maximize() override;
  void Minimize() override;
  void Restore() override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  bool IsOnCurrentWorkspace() const override;
  bool IsVisibleOnScreen() const override;
  std::string GetWorkspace() const override;
  bool IsVisibleOnAllWorkspaces() const override;
  bool GetCanResize() override;
  ui::mojom::WindowShowState GetWindowShowState() const override;
  void UpdateTitleBar() override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          int index,
                          int reason) override;
  void OnTabDetached(content::WebContents* contents, bool was_active) override;
  gfx::Size GetContentsSize() const override;
  std::vector<StatusBubble*> GetStatusBubbles() override;
  void UpdateLoadingAnimations(bool is_visible) override;
  void UpdateReloadStopState(bool is_loading, bool force) override;
  void UpdateToolbar(content::WebContents* contents) override;
  bool UpdateToolbarSecurityState() override;
  void ResetToolbarTabState(content::WebContents* contents) override;
  void LinkOpeningFromGesture(WindowOpenDisposition disposition) override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override;
  BrowserView* AsBrowserView() override;
  LocationBar* GetLocationBar() const override;
  void SetFocusToLocationBar(bool is_user_initiated) override;
  bool IsLocationBarVisible() const override;
  bool IsToolbarVisible() const override;
  ExclusiveAccessContext* GetExclusiveAccessContext() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(
      content::WebContents* web_contents) override;
  std::unique_ptr<FindBar> CreateFindBar() override;
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override;
  bool IsTabStripEditable() const override;
  void DisableTabStripEditingForTesting() override;
  void ConfirmBrowserCloseWithPendingDownloads(
      int download_count,
      DownloadCloseType dialog_type,
      base::OnceCallback<void(bool)> callback) override;
  void ShowEmojiPanel() override;
  // Chrome's translate bubble (Views) on the host's site button (3.7b): the
  // offer itself is the host's notice (room_page_state.mm's factory), the
  // later steps (translating, translated, an error) are Chrome's bubble.
  ShowTranslateBubbleResult ShowTranslateBubble(
      content::WebContents* contents,
      translate::TranslateStep step,
      const std::string& source_language,
      const std::string& target_language,
      translate::TranslateErrors error_type,
      bool is_user_gesture) override;

  // Stubs (room_browser_window_stubs.cc).
  void SetBounds(const gfx::Rect& bounds) override;
  void FlashFrame(bool flash) override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;
  void SetTopControlsShownRatio(content::WebContents* web_contents, float ratio) override;
  bool DoBrowserControlsShrinkRendererSize( const content::WebContents* contents) const override;
  ui::NativeTheme* GetNativeTheme() override;
  const ui::ThemeProvider* GetThemeProvider() const override;
  const ui::ColorProvider* GetColorProvider() const override;
  int GetTopControlsHeight() const override;
  void SetTopControlsGestureScrollInProgress(bool in_progress) override;
  void SetContentsSize(const gfx::Size& size) override;
  ui::AcceleratorProvider* GetAcceleratorProvider() override;
  PinnedToolbarActions* GetPinnedToolbarActions() override;
  void UpdateCustomTabBarVisibility(bool visible, bool animate) override;
  void FocusToolbar() override;
  void ToolbarSizeChanged(bool is_animating) override;
  void TabDraggingStatusChanged(bool is_dragging) override;
  void FocusAppMenu() override;
  bool IsToolbarShowing() const override;
  void ShowUpdateChromeDialog() override;
  void ShowIntentPickerBubble( std::vector<apps::IntentPickerAppInfo> app_info, bool show_stay_in_chrome, bool show_remember_selection, apps::IntentPickerBubbleType bubble_type, const std::optional<url::Origin>& initiating_origin, IntentPickerResponse callback) override;
  void ShowBookmarkBubble(const GURL& url, bool already_bookmarked) override;
  DownloadBubbleUIController* GetDownloadBubbleUIController() override;
  void ShowAppMenu() override;
  void PreHandleDragUpdate(const content::DropData& drop_data, const gfx::PointF& point) override;
  void PreHandleDragExit() override;
  void HandleDragEnded() override;
  void ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) override;
  void MaybeShowProfileSwitchIPH() override;
  void MaybeShowSupervisedUserProfileSignInIPH() override;
  void ShowHatsDialog( const std::string& site_id, const std::optional<std::string>& hats_histogram_name, const std::optional<uint64_t> hats_survey_ukm_id, base::OnceClosure success_callback, base::OnceClosure failure_callback, const SurveyBitsData& product_specific_bits_data, const SurveyStringData& product_specific_string_data) override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper( content::RenderFrameHost* frame, content::EyeDropperListener* listener) override;
  void ShowCaretBrowsingDialog() override;
  void CreateTabSearchBubble() override;
  void CloseTabSearchBubble() override;
  void ShowIncognitoClearBrowsingDataDialog() override;
  void ShowIncognitoHistoryDisclaimerDialog() override;
  bool IsUnframedModeEnabled() const override;
  void ShowChromeLabs() override;

 protected:
  void DeleteBrowserWindow() override;

 private:
  void DestroyBrowser();
  // Closes the pages' autofill suggestion popups (the window moved or resized).
  void HideAutofillSuggestions();

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<room::RoomBrowserWindowClient> client_;
  // The host NSWindow, held weakly (room_browser_window.mm).
  struct ObjCMembers;
  std::unique_ptr<ObjCMembers> objc_;
  // Created on first use: the Browser's command controller, which it needs,
  // may not exist yet while the Browser constructs its window.
  mutable std::unique_ptr<room::RoomLocationBar> location_bar_;
  std::unique_ptr<room::RoomExclusiveAccessContext> exclusive_access_context_;
  std::optional<room::PendingOpen> pending_open_;
  bool destroy_posted_ = false;
  bool tab_strip_editing_disabled_ = false;
  base::WeakPtrFactory<RoomBrowserWindow> weak_factory_{this};
};

// Logs the first call of each stub, so a run's log lists the BrowserWindow
// members Chrome actually needed.
void RoomStubHit(const char* name);

#endif  // ROOM_BROWSER_ROOM_BROWSER_WINDOW_H_
