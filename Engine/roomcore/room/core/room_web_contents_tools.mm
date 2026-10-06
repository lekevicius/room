// Copyright 2026 Jonas Lekevicius. All rights reserved.

// RoomWebContents (Tools): find in page, viewport capture, print preview and
// DevTools, each through Chrome's own object for it (the tab helpers a Room
// page gets in its RoomBrowser's strip, DevToolsWindow). RoomWebContents
// (Documents, 4.7a): Save Page (SavePackage, GenerateMHTML) and one DevTools
// protocol command through a DevToolsAgentHost client.

#import "room/core/room_web_contents_internal.h"

#import <objc/runtime.h>

#include <algorithm>
#include <string>

#include "base/apple/foundation_util.h"
#include "base/containers/span.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
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
#include "components/download/public/common/download_item.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "content/public/browser/download_manager.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/save_page_type.h"
#include "content/public/browser/web_contents_user_data.h"
#include "content/public/common/mhtml_generation_params.h"
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

// Waits for the download item Chrome's SavePackage makes for one
// WebContents::SavePage (DownloadManager::CreateSavePackageDownloadItem, so
// the save also reaches the downloads delegate as an item) and answers once
// it completes, is cancelled or interrupted, or after 120 s. Deletes itself
// after answering.
class SavePageWaiter : public content::DownloadManager::Observer,
                       public download::DownloadItem::Observer {
 public:
  SavePageWaiter(content::DownloadManager* manager,
                 const base::FilePath& path,
                 void (^completion)(NSError*))
      : path_(path), completion_([completion copy]) {
    manager_observation_.Observe(manager);
    timer_.Start(FROM_HERE, base::Seconds(120),
                 base::BindOnce(&SavePageWaiter::Finish, base::Unretained(this),
                                ToolError(9, @"no answer from the save in 120 s")));
  }
  SavePageWaiter(const SavePageWaiter&) = delete;
  SavePageWaiter& operator=(const SavePageWaiter&) = delete;
  ~SavePageWaiter() override = default;

  void Finish(NSError* error) {
    if (!completion_) {
      return;
    }
    void (^completion)(NSError*) = completion_;
    completion_ = nil;
    timer_.Stop();
    item_observation_.Reset();
    manager_observation_.Reset();
    completion(error);
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }

  // content::DownloadManager::Observer:
  void OnDownloadCreated(content::DownloadManager*,
                         download::DownloadItem* item) override {
    if (item_observation_.IsObserving() || !item->IsSavePackageDownload() ||
        (item->GetTargetFilePath() != path_ && item->GetFullPath() != path_)) {
      return;
    }
    item_observation_.Observe(item);
    OnDownloadUpdated(item);
  }
  void ManagerGoingDown(content::DownloadManager*) override {
    manager_observation_.Reset();
    Finish(ToolError(8, @"the profile closed during the save"));
  }

  // download::DownloadItem::Observer:
  void OnDownloadUpdated(download::DownloadItem* item) override {
    switch (item->GetState()) {
      case download::DownloadItem::COMPLETE:
        Finish(nil);
        break;
      case download::DownloadItem::CANCELLED:
        Finish(ToolError(7, @"the save was cancelled"));
        break;
      case download::DownloadItem::INTERRUPTED:
        Finish(ToolError(
            7, [NSString stringWithFormat:@"the save was interrupted (%d)",
                                          static_cast<int>(
                                              item->GetLastReason())]));
        break;
      default:
        break;
    }
  }
  void OnDownloadDestroyed(download::DownloadItem*) override {
    item_observation_.Reset();
    Finish(ToolError(7, @"the save's download item went away"));
  }

 private:
  const base::FilePath path_;
  void (^completion_)(NSError*);
  base::OneShotTimer timer_;
  base::ScopedObservation<content::DownloadManager,
                          content::DownloadManager::Observer>
      manager_observation_{this};
  base::ScopedObservation<download::DownloadItem,
                          download::DownloadItem::Observer>
      item_observation_{this};
};

// One DevTools protocol command from the host: attaches to the page's agent
// host as a client (beside DevTools' own front-end when it is open), sends
// the command, answers with its result and detaches. Deletes itself after
// answering (posted: an answer can arrive inside DispatchProtocolMessage).
class DevToolsCommandClient : public content::DevToolsAgentHostClient {
 public:
  static constexpr int kCommandId = 1;

  DevToolsCommandClient(scoped_refptr<content::DevToolsAgentHost> host,
                        void (^completion)(NSDictionary*, NSError*))
      : host_(std::move(host)), completion_([completion copy]) {}
  DevToolsCommandClient(const DevToolsCommandClient&) = delete;
  DevToolsCommandClient& operator=(const DevToolsCommandClient&) = delete;
  ~DevToolsCommandClient() override {
    if (attached_) {
      host_->DetachClient(this);
    }
  }

  // Attaches and sends; false (nothing sent, nothing answered) when the
  // agent host refuses the client.
  bool Send(const std::string& message) {
    if (!host_->AttachClient(this)) {
      return false;
    }
    attached_ = true;
    timer_.Start(FROM_HERE, base::Seconds(30),
                 base::BindOnce(&DevToolsCommandClient::Finish,
                                base::Unretained(this), static_cast<NSDictionary*>(nil),
                                ToolError(12, @"no DevTools answer in 30 s")));
    host_->DispatchProtocolMessage(this, base::as_byte_span(message));
    return true;
  }

  // content::DevToolsAgentHostClient:
  void DispatchProtocolMessage(content::DevToolsAgentHost*,
                               base::span<const uint8_t> message) override {
    NSData* data = [NSData dataWithBytes:message.data() length:message.size()];
    id object = [NSJSONSerialization JSONObjectWithData:data
                                                options:0
                                                  error:nil];
    if (![object isKindOfClass:[NSDictionary class]] ||
        ![object[@"id"] isEqual:@(kCommandId)]) {
      return;  // An event, or not ours.
    }
    NSDictionary* answer = object;
    if ([answer[@"error"] isKindOfClass:[NSDictionary class]]) {
      NSDictionary* error = answer[@"error"];
      Finish(nil, ToolError([error[@"code"] integerValue] ?: 11,
                            [NSString stringWithFormat:@"DevTools: %@",
                                                       error[@"message"]]));
      return;
    }
    NSDictionary* result = answer[@"result"];
    Finish([result isKindOfClass:[NSDictionary class]] ? result : @{}, nil);
  }
  void AgentHostClosed(content::DevToolsAgentHost*) override {
    attached_ = false;
    Finish(nil, ToolError(13, @"the page's DevTools agent closed"));
  }

 private:
  void Finish(NSDictionary* result, NSError* error) {
    if (!completion_) {
      return;
    }
    void (^completion)(NSDictionary*, NSError*) = completion_;
    completion_ = nil;
    timer_.Stop();
    completion(result, error);
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }

  scoped_refptr<content::DevToolsAgentHost> host_;
  void (^completion_)(NSDictionary*, NSError*);
  bool attached_ = false;
  base::OneShotTimer timer_;
};

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

@implementation RoomWebContents (Documents)

#pragma mark Save Page

- (void)savePageAs:(RoomSavePageFormat)format
            toPath:(NSString*)path
        completion:(void (^)(NSError*))completion {
  content::WebContents* contents = self.room_webContents;
  if (!contents) {
    completion(ToolError(3, @"the page is closed"));
    return;
  }
  if (!path.absolutePath) {
    completion(ToolError(5, @"the path is not absolute"));
    return;
  }
  if (!contents->IsSavable()) {
    completion(ToolError(
        6, [NSString stringWithFormat:@"a %s page cannot be saved",
                                      contents->GetContentsMimeType().c_str()]));
    return;
  }
  const base::FilePath main_file = base::apple::NSStringToFilePath(path);
  if (format == RoomSavePageFormatMHTML) {
    void (^callback)(NSError*) = [completion copy];
    contents->GenerateMHTML(
        content::MHTMLGenerationParams(main_file),
        base::BindPostTask(
            base::SingleThreadTaskRunner::GetCurrentDefault(),
            base::BindOnce(^(int64_t size) {
              LOG(INFO) << "RoomCore: saved MHTML, " << size << " bytes";
              callback(size < 0 ? ToolError(7, @"GenerateMHTML failed") : nil);
            })));
    return;
  }
  // Chrome's convention: "Page.html" keeps its resources in "Page_files".
  const base::FilePath directory =
      format == RoomSavePageFormatCompleteHTML
          ? base::FilePath(main_file.RemoveFinalExtension().value() + "_files")
          : main_file.DirName();
  content::DownloadManager* manager =
      contents->GetBrowserContext()->GetDownloadManager();
  auto* waiter = new SavePageWaiter(manager, main_file, completion);
  if (!contents->SavePage(main_file, directory,
                          format == RoomSavePageFormatCompleteHTML
                              ? content::SAVE_PAGE_TYPE_AS_COMPLETE_HTML
                              : content::SAVE_PAGE_TYPE_AS_ONLY_HTML)) {
    waiter->Finish(ToolError(6, @"Chrome refused to start the save"));
  }
}

#pragma mark DevTools protocol

- (void)sendDevToolsCommand:(NSString*)method
                     params:(NSDictionary<NSString*, id>*)params
                 completion:(void (^)(NSDictionary<NSString*, id>*,
                                      NSError*))completion {
  content::WebContents* contents = self.room_webContents;
  if (!contents) {
    completion(nil, ToolError(3, @"the page is closed"));
    return;
  }
  NSDictionary* command =
      @{@"id" : @(DevToolsCommandClient::kCommandId),
        @"method" : method,
        @"params" : params ?: @{}};
  if (![NSJSONSerialization isValidJSONObject:command]) {
    completion(nil, ToolError(10, @"the parameters are not JSON"));
    return;
  }
  NSData* json = [NSJSONSerialization dataWithJSONObject:command
                                                 options:0
                                                   error:nil];
  auto* client = new DevToolsCommandClient(
      content::DevToolsAgentHost::GetOrCreateFor(contents), completion);
  if (!client->Send(std::string(static_cast<const char*>(json.bytes),
                                json.length))) {
    delete client;
    completion(nil, ToolError(14, @"the page's DevTools agent refused a client"));
  }
}

@end
