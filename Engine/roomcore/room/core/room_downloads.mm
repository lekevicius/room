// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Downloads of Room profiles: the host picks each new download's file
// (patch 0019: DetermineDownloadTarget answered with the host's path, no
// Save panel, no danger verdict) and hears every update from Chrome's
// DownloadManager, including the downloads Chrome's DownloadHistory restores
// at launch (the popover's list survives a relaunch, B-28).

#import "room/core/room_page_ui_internal.h"

#include <algorithm>
#include <memory>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/files/file_path.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_core_service_factory.h"
#include "chrome/browser/download/download_target_determiner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/download/public/common/download_item.h"
#include "components/download/public/common/download_target_info.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/download_manager.h"
#include "net/base/apple/url_conversions.h"
#include "net/base/filename_util.h"
#import "room/core/room_profile_internal.h"

namespace room {
// Defined in chrome/browser/download/chrome_download_manager_delegate.cc
// (patches/0019-download-target-hook.patch).
extern bool (*g_determine_download_target_hook)(
    download::DownloadItem*,
    download::DownloadTargetCallback*);
}  // namespace room

@interface RoomDownloadItem ()
- (instancetype)initWithItem:(const download::DownloadItem&)item
           suggestedFilename:(NSString*)suggestedFilename;
@end

namespace {

// The name Chrome's DownloadTargetDeterminer would start from
// (Content-Disposition, the download attribute, the URL, the MIME type).
NSString* SuggestedFilename(const download::DownloadItem& item) {
  content::BrowserContext* context =
      content::DownloadItemUtils::GetBrowserContext(&item);
  Profile* profile = context ? Profile::FromBrowserContext(context) : nullptr;
  const std::string charset =
      profile ? profile->GetPrefs()->GetString(prefs::kDefaultCharset) : "";
  const base::FilePath name = net::GenerateFileName(
      item.GetURL(), item.GetContentDisposition(), charset,
      item.GetSuggestedFilename(), item.GetMimeType(), "download");
  return base::SysUTF8ToNSString(name.value());
}

RoomDownloadItem* Snapshot(const download::DownloadItem& item) {
  return [[RoomDownloadItem alloc] initWithItem:item
                              suggestedFilename:SuggestedFilename(item)];
}

// Worth telling the host about: a download whose file is decided, or one
// that ended (a new one is announced by -willBeginDownload: first).
bool IsReportable(const download::DownloadItem& item) {
  // The Web Store's CRX (WebstoreInstaller, a forced path under the user
  // data directory) is an install, not a download the user keeps (3.6a).
  if (item.IsTransient() || item.GetDownloadSource() ==
                                download::DownloadSource::EXTENSION_INSTALLER) {
    return false;
  }
  return !item.GetTargetFilePath().empty() ||
         item.GetState() != download::DownloadItem::IN_PROGRESS;
}

}  // namespace

@implementation RoomDownloadItem

@synthesize identifier = _identifier;
@synthesize URL = _URL;
@synthesize suggestedFilename = _suggestedFilename;
@synthesize destination = _destination;
@synthesize mimeType = _mimeType;
@synthesize receivedBytes = _receivedBytes;
@synthesize totalBytes = _totalBytes;
@synthesize currentSpeed = _currentSpeed;
@synthesize state = _state;
@synthesize paused = _paused;
@synthesize canResume = _canResume;
@synthesize startTime = _startTime;

- (instancetype)initWithItem:(const download::DownloadItem&)item
           suggestedFilename:(NSString*)suggestedFilename {
  if ((self = [super init])) {
    _identifier = base::SysUTF8ToNSString(item.GetGuid());
    _URL = item.GetURL().is_valid() ? net::NSURLWithGURL(item.GetURL())
                                    : [NSURL URLWithString:@"about:blank"];
    _suggestedFilename = [suggestedFilename copy];
    const base::FilePath target = item.GetTargetFilePath();
    _destination =
        target.empty()
            ? nil
            : [NSURL fileURLWithPath:base::SysUTF8ToNSString(target.value())
                         isDirectory:NO];
    _mimeType = item.GetMimeType().empty()
                    ? nil
                    : base::SysUTF8ToNSString(item.GetMimeType());
    _receivedBytes = item.GetReceivedBytes();
    const int64_t total = item.GetTotalBytes();
    _totalBytes = total > 0 ? total
                  : item.GetState() == download::DownloadItem::COMPLETE
                      ? item.GetReceivedBytes()
                      : -1;
    _currentSpeed =
        item.GetState() == download::DownloadItem::IN_PROGRESS && !item.IsPaused()
            ? item.CurrentSpeed()
            : 0;
    switch (item.GetState()) {
      case download::DownloadItem::COMPLETE:
        _state = RoomDownloadStateComplete;
        break;
      case download::DownloadItem::CANCELLED:
        _state = RoomDownloadStateCancelled;
        break;
      case download::DownloadItem::INTERRUPTED:
        _state = RoomDownloadStateInterrupted;
        break;
      default:
        _state = RoomDownloadStateInProgress;
        break;
    }
    _paused = item.IsPaused();
    _canResume = item.CanResume();
    _startTime = item.GetStartTime().ToNSDate();
  }
  return self;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomDownloadItem %@ %@ state=%ld "
                                    @"paused=%d canResume=%d %lld/%lld>",
                                    _identifier, _suggestedFilename,
                                    (long)_state, _paused, _canResume,
                                    _receivedBytes, _totalBytes];
}

@end

namespace {

class ProfileDownloadsImpl : public room::ProfileDownloads,
                             public content::DownloadManager::Observer,
                             public download::DownloadItem::Observer {
 public:
  ProfileDownloadsImpl(Profile* profile, RoomProfile* wrapper)
      : wrapper_(wrapper) {
    // Creating the manager creates Chrome's delegate and DownloadHistory,
    // which loads the earlier sessions' downloads (OnDownloadCreated each).
    DownloadCoreServiceFactory::GetForBrowserContext(profile);
    manager_ = profile->GetDownloadManager();
    if (!manager_) {
      return;
    }
    manager_->AddObserver(this);
    content::DownloadManager::DownloadVector items;
    manager_->GetAllDownloads(&items);
    for (download::DownloadItem* item : items) {
      Observe(item);
    }
  }

  ~ProfileDownloadsImpl() override { Stop(); }

  // room::ProfileDownloads:
  void SetDelegate(id<RoomProfileDownloadsDelegate> delegate) override {
    delegate_ = delegate;
    if (!delegate || !manager_) {
      return;
    }
    // Everything Chrome knows, oldest first (the host lists newest first).
    content::DownloadManager::DownloadVector items;
    manager_->GetAllDownloads(&items);
    std::stable_sort(items.begin(), items.end(),
                     [](download::DownloadItem* a, download::DownloadItem* b) {
                       return a->GetStartTime() < b->GetStartTime();
                     });
    for (download::DownloadItem* item : items) {
      if (IsReportable(*item)) {
        Notify(*item);
      }
    }
  }

  id<RoomProfileDownloadsDelegate> delegate() const override {
    return delegate_;
  }

  NSArray<RoomDownloadItem*>* AllDownloads() override {
    NSMutableArray<RoomDownloadItem*>* result = [NSMutableArray array];
    if (!manager_) {
      return result;
    }
    content::DownloadManager::DownloadVector items;
    manager_->GetAllDownloads(&items);
    for (download::DownloadItem* item : items) {
      if (!item->IsTransient() &&
          item->GetDownloadSource() !=
              download::DownloadSource::EXTENSION_INSTALLER) {
        [result addObject:Snapshot(*item)];
      }
    }
    return result;
  }

  void Pause(NSString* identifier) override {
    if (download::DownloadItem* item = Find(identifier)) {
      item->Pause();
    }
  }

  void Resume(NSString* identifier) override {
    if (download::DownloadItem* item = Find(identifier)) {
      item->Resume(/*user_resume=*/true);
    }
  }

  void Cancel(NSString* identifier) override {
    if (download::DownloadItem* item = Find(identifier)) {
      item->Cancel(/*user_cancel=*/true);
    }
  }

  // content::DownloadManager::Observer:
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    Observe(item);
    if (IsReportable(*item)) {
      Notify(*item);  // restored from history, or created with a target
    }
  }

  void ManagerGoingDown(content::DownloadManager* manager) override { Stop(); }

  // download::DownloadItem::Observer:
  void OnDownloadUpdated(download::DownloadItem* item) override {
    if (IsReportable(*item)) {
      Notify(*item);
    }
  }

  void OnDownloadDestroyed(download::DownloadItem* item) override {
    item->RemoveObserver(this);
    observed_.erase(item);
  }

 private:
  void Observe(download::DownloadItem* item) {
    if (observed_.insert(item).second) {
      item->AddObserver(this);
    }
  }

  void Stop() {
    for (download::DownloadItem* item : observed_) {
      item->RemoveObserver(this);
    }
    observed_.clear();
    if (manager_) {
      manager_->RemoveObserver(this);
      manager_ = nullptr;
    }
  }

  download::DownloadItem* Find(NSString* identifier) {
    return manager_ && identifier
               ? manager_->GetDownloadByGuid(base::SysNSStringToUTF8(identifier))
               : nullptr;
  }

  void Notify(const download::DownloadItem& item) {
    id<RoomProfileDownloadsDelegate> delegate = delegate_;
    RoomProfile* wrapper = wrapper_;
    if (delegate && wrapper) {
      [delegate profile:wrapper didUpdateDownload:Snapshot(item)];
    }
  }

  RoomProfile* __weak wrapper_;
  id<RoomProfileDownloadsDelegate> __weak delegate_;
  raw_ptr<content::DownloadManager> manager_ = nullptr;
  std::set<raw_ptr<download::DownloadItem, SetExperimental>> observed_;
};

}  // namespace

namespace room {

std::unique_ptr<ProfileDownloads> ProfileDownloads::Create(
    Profile* profile,
    RoomProfile* wrapper) {
  return std::make_unique<ProfileDownloadsImpl>(profile, wrapper);
}

void InstallDownloadTargetHook() {
  g_determine_download_target_hook = +[](download::DownloadItem* item,
                                         download::DownloadTargetCallback*
                                             callback) -> bool {
    // Resumed downloads keep their file; transient ones (the PDF viewer's)
    // are Chrome's.
    if (!item->GetTargetFilePath().empty() || item->IsTransient()) {
      return false;
    }
    // A forced path (the Web Store's CRX, WebstoreInstaller; 3.6a) is
    // Chrome's to honour.
    if (!item->GetForcedFilePath().empty() ||
        item->GetDownloadSource() ==
            download::DownloadSource::EXTENSION_INSTALLER) {
      return false;
    }
    content::BrowserContext* context =
        content::DownloadItemUtils::GetBrowserContext(item);
    Profile* profile = context ? Profile::FromBrowserContext(context) : nullptr;
    RoomProfile* wrapper =
        profile ? [RoomProfile room_existingProfileFor:profile] : nil;
    id<RoomProfileDownloadsDelegate> delegate = wrapper.downloadsDelegate;
    if (!delegate) {
      return false;
    }
    auto pending =
        std::make_shared<download::DownloadTargetCallback>(std::move(*callback));
    const std::string mime_type = item->GetMimeType();
    RoomDownloadItem* snapshot = Snapshot(*item);
    LOG(INFO) << "RoomCore: download " << item->GetGuid() << " asks the host ("
              << base::SysNSStringToUTF8(snapshot.suggestedFilename) << ")";
    [delegate profile:wrapper
        willBeginDownload:snapshot
               completion:^(NSURL* destination) {
                 if (!*pending) {
                   return;  // answered already
                 }
                 download::DownloadTargetInfo target;
                 // Room gives no danger verdicts (Safe Browsing is off).
                 target.danger_type =
                     download::DOWNLOAD_DANGER_TYPE_NOT_DANGEROUS;
                 target.insecure_download_status =
                     download::DownloadItem::InsecureDownloadStatus::SAFE;
                 target.target_disposition =
                     download::DownloadItem::TARGET_DISPOSITION_OVERWRITE;
                 target.mime_type = mime_type;
                 if (destination.isFileURL) {
                   target.target_path = base::FilePath(
                       base::SysNSStringToUTF8(destination.path));
                   target.intermediate_path =
                       DownloadTargetDeterminer::GetCrDownloadPath(
                           target.target_path);
                   target.display_name = target.target_path.BaseName();
                 } else {
                   target.interrupt_reason =
                       download::DOWNLOAD_INTERRUPT_REASON_USER_CANCELED;
                 }
                 std::move(*pending).Run(std::move(target));
               }];
    return true;
  };
}

}  // namespace room
