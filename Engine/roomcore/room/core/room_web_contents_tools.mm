// Copyright 2026 Jonas Lekevicius. All rights reserved.

// RoomWebContents (Tools): find in page, viewport capture, print preview and
// DevTools, each through Chrome's own object for it (the tab helpers a Room
// page gets in its RoomBrowser's strip, DevToolsWindow).

#import "room/core/room_web_contents_internal.h"

#import <objc/runtime.h>

#include <algorithm>
#include <string>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/bind_post_task.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/printing/print_view_manager_common.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/common/pref_names.h"
#include "components/find_in_page/find_notification_details.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/prefs/pref_service.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_user_data.h"
#include "room/build/buildflags.h"
#include "skia/ext/skia_utils_mac.h"
#include "ui/base/base_window.h"
#include "ui/gfx/geometry/rect.h"

namespace {

NSError* ToolError(NSInteger code, NSString* description) {
  return [NSError errorWithDomain:@"RoomCore"
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : description}];
}

// Hands FindTabHelper's results for one WebContents to the page's wrapper.
// User data, so it dies with the WebContents (a discard's replacement gets
// its own at its first find).
class FindObserver : public content::WebContentsUserData<FindObserver>,
                     public find_in_page::FindResultObserver {
 public:
  ~FindObserver() override = default;

  void set_wrapper(RoomWebContents* wrapper) { wrapper_ = wrapper; }

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* contents) override {
    auto* helper = find_in_page::FindTabHelper::FromWebContents(contents);
    RoomWebContents* wrapper = wrapper_;
    id<RoomWebContentsDelegate> delegate = wrapper.delegate;
    if (!helper || ![delegate respondsToSelector:@selector
                              (webContents:didUpdateFindResultWithMatchCount:
                                   activeMatch:selectionRect:finalUpdate:)]) {
      return;
    }
    const find_in_page::FindNotificationDetails& result =
        helper->find_result();
    const gfx::Rect rect = result.selection_rect();
    [delegate webContents:wrapper
        didUpdateFindResultWithMatchCount:std::max(result.number_of_matches(), 0)
                              activeMatch:std::max(
                                              result.active_match_ordinal(), 0)
                            selectionRect:NSMakeRect(rect.x(), rect.y(),
                                                     rect.width(),
                                                     rect.height())
                              finalUpdate:result.final_update()];
  }
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper*) override {
    observation_.Reset();
  }

 private:
  friend class content::WebContentsUserData<FindObserver>;
  FindObserver(content::WebContents* contents,
               find_in_page::FindTabHelper* helper)
      : content::WebContentsUserData<FindObserver>(*contents) {
    observation_.Observe(helper);
  }

  RoomWebContents* __weak wrapper_;
  base::ScopedObservation<find_in_page::FindTabHelper,
                          find_in_page::FindResultObserver>
      observation_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(FindObserver);

// The front-end wrapper is kept by the inspected page's wrapper while
// DevTools is open (nothing else holds a wrapper Chrome's DevTools Browser
// made).
char kDevToolsWrapperKey;

DevToolsWindow* DevToolsFor(content::WebContents* contents) {
  return contents ? DevToolsWindow::GetInstanceForInspectedWebContents(contents)
                  : nullptr;
}

}  // namespace

@implementation RoomWebContents (Tools)

#pragma mark Find

- (void)findText:(NSString*)text forward:(BOOL)forward matchCase:(BOOL)matchCase {
  content::WebContents* contents = self.room_webContents;
  auto* helper = contents ? find_in_page::FindTabHelper::FromWebContents(contents)
                          : nullptr;
  if (!helper) {
    return;  // A page in no RoomBrowser has no tab helpers.
  }
  if (!FindObserver::FromWebContents(contents)) {
    FindObserver::CreateForWebContents(contents, helper);
  }
  FindObserver::FromWebContents(contents)->set_wrapper(self);
  const std::u16string search = base::SysNSStringToUTF16(text);
#if BUILDFLAG(ROOM_ENABLE_SPIKES)
  LOG(WARNING) << "RoomCore: find request ("
               << (search == helper->find_text() ? "same text, step"
                                                 : "new text")
               << ", " << search.size() << " characters)";
#endif
  // find_match: the same text steps to the next match, a new text selects
  // its first (Chrome's find bar while typing; no separate counting request).
  helper->StartFinding(search, forward, matchCase, /*find_match=*/true);
}

- (void)stopFindingClearSelection:(BOOL)clearSelection {
  content::WebContents* contents = self.room_webContents;
  auto* helper = contents ? find_in_page::FindTabHelper::FromWebContents(contents)
                          : nullptr;
  if (helper) {
    helper->StopFinding(clearSelection
                            ? find_in_page::SelectionAction::kClear
                            : find_in_page::SelectionAction::kKeep);
  }
}

#pragma mark Capture

- (void)captureViewportWithCompletion:(void (^)(NSImage*, NSError*))completion {
  content::WebContents* contents = self.room_webContents;
  content::RenderFrameHost* frame =
      contents ? contents->GetPrimaryMainFrame() : nullptr;
  content::RenderWidgetHostView* view = frame ? frame->GetView() : nullptr;
  if (!view || !view->IsSurfaceAvailableForCopy()) {
    completion(nil, ToolError(3, contents ? @"the page has no surface to copy"
                                          : @"the page is closed"));
    return;
  }
  const float scale = view->GetDeviceScaleFactor();
  void (^callback)(NSImage*, NSError*) = [completion copy];
  view->CopyFromSurface(
      /*src_rect=*/gfx::Rect(), /*output_size=*/gfx::Size(), base::TimeDelta(),
      base::BindPostTask(
          base::SingleThreadTaskRunner::GetCurrentDefault(),
          base::BindOnce(^(const content::CopyFromSurfaceResult& result) {
            if (!result.has_value() || result->bitmap.drawsNothing()) {
              callback(nil, ToolError(4, [NSString
                                             stringWithFormat:
                                                 @"CopyFromSurface failed (%d)",
                                                 result.has_value()
                                                     ? -1
                                                     : static_cast<int>(
                                                           result.error())]));
              return;
            }
            const SkBitmap& bitmap = result->bitmap;
            NSImage* image = skia::SkBitmapToNSImage(bitmap);
            if (scale > 0) {
              image.size = NSMakeSize(bitmap.width() / scale,
                                      bitmap.height() / scale);
            }
            callback(image, nil);
          })));
}

#pragma mark Print

- (BOOL)printWithPreview {
  content::WebContents* contents = self.room_webContents;
  if (!contents) {
    return NO;
  }
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  // chrome::Print(): the preview unless policy disables it, the whole page.
  return printing::StartPrint(
      contents,
      profile->GetPrefs()->GetBoolean(prefs::kPrintPreviewDisabled),
      /*has_selection=*/false);
}

#pragma mark DevTools

- (BOOL)isDevToolsOpen {
  DevToolsWindow* window = DevToolsFor(self.room_webContents);
  return window && window->GetDevToolsWebContents();
}

- (RoomWebContents*)devToolsWebContents {
  DevToolsWindow* window = DevToolsFor(self.room_webContents);
  content::WebContents* frontend =
      window ? window->GetDevToolsWebContents().get() : nullptr;
  RoomWebContents* wrapper = nil;
  if (frontend) {
    wrapper = [RoomWebContents room_existingWrapperFor:frontend];
    if (!wrapper) {
      // Chrome's DevTools Browser (headless, 3.2a) owns the front-end in its
      // strip; the host shows the wrapper's view in its pane.
      wrapper = [[RoomWebContents alloc] initWithUnownedChromeWebContents:frontend
                                                                  profile:self.profile];
    }
  }
  objc_setAssociatedObject(self, &kDevToolsWrapperKey, wrapper,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return wrapper;
}

- (void)showDevTools:(RoomDevToolsTool)tool {
  content::WebContents* contents = self.room_webContents;
  if (!contents) {
    return;
  }
  // Without a DevtoolsUIController on the inspected Browser, DevToolsWindow
  // cannot dock and makes its own (headless) DevTools Browser synchronously:
  // the front-end exists when this returns.
  auto action = [tool] {
    switch (tool) {
      case RoomDevToolsToolConsole:
        return DevToolsToggleAction::ShowConsolePanel();
      case RoomDevToolsToolElements:
        return DevToolsToggleAction::ShowElementsPanel();
      case RoomDevToolsToolElementPicker:
        return DevToolsToggleAction::Inspect();
      case RoomDevToolsToolDefault:
        break;
    }
    return DevToolsToggleAction::Show();
  }();
  DevToolsWindow::OpenDevToolsWindow(
      contents, action, DevToolsOpenedByAction::kMainMenuOrMainShortcut);
}

- (void)inspectElementAtPoint:(NSPoint)point {
  content::WebContents* contents = self.room_webContents;
  content::RenderFrameHost* frame =
      contents ? contents->GetPrimaryMainFrame() : nullptr;
  if (!frame || !frame->IsRenderFrameLive()) {
    return;
  }
  DevToolsWindow::InspectElement(frame, static_cast<int>(point.x),
                                 static_cast<int>(point.y));
}

- (void)closeDevTools {
  DevToolsWindow* window = DevToolsFor(self.room_webContents);
  content::WebContents* frontend =
      window ? window->GetDevToolsWebContents().get() : nullptr;
  BrowserWindowInterface* browser =
      frontend
          ? GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(frontend)
          : nullptr;
  // What DevToolsWindow::CloseWindow() does for an undocked window: close
  // its Browser (the front-end's beforeunload is DevToolsWindow's to run).
  if (browser) {
    browser->GetWindow()->Close();
  }
  objc_setAssociatedObject(self, &kDevToolsWrapperKey, nil,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
