// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_profile_internal.h"

#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include <memory>

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/supports_user_data.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/sessions/exit_type_service.h"
#include "components/prefs/pref_service.h"
#include "chrome/common/pref_names.h"
#include "base/strings/sys_string_conversions.h"
#include "base/logging.h"
#include "base/task/cancelable_task_tracker.h"
#include "chrome/browser/favicon/favicon_service_factory.h"
#include "components/favicon/core/favicon_service.h"
#include "components/favicon_base/favicon_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "ui/gfx/image/image.h"
#import "room/core/room_extensions_internal.h"
#import "room/core/room_omnibox_internal.h"
#import "room/core/room_page_ui_internal.h"
#import "room/core/room_passwords.h"
#import "room/core/room_web_contents_internal.h"

namespace {

const char kRoomProfileKey[] = "RoomProfile";

// Keeps the wrapper alive as long as the Profile and clears the wrapper's
// pointer when the Profile goes away.
class ProfileWrapper : public base::SupportsUserData::Data,
                       public ProfileObserver {
 public:
  ProfileWrapper(Profile* profile, RoomProfile* wrapper)
      : wrapper_(wrapper) {
    observation_.Observe(profile);
  }

  RoomProfile* wrapper() const { return wrapper_; }

  void OnProfileWillBeDestroyed(Profile* profile) override;

 private:
  RoomProfile* __strong wrapper_;
  base::ScopedObservation<Profile, ProfileObserver> observation_{this};
};

}  // namespace

@interface RoomProfile ()
- (instancetype)initWithProfile:(Profile*)profile;
- (void)room_profileWillBeDestroyed;
@end

namespace {

void ProfileWrapper::OnProfileWillBeDestroyed(Profile* profile) {
  observation_.Reset();
  [wrapper_ room_profileWillBeDestroyed];
}

}  // namespace

@implementation RoomProfile {
  raw_ptr<Profile> _profile;
  NSString* _name;
  NSURL* _directory;
  BOOL _offTheRecord;
  BOOL _lastExitWasClean;
  // Pending FaviconService requests; destroying it cancels them.
  std::unique_ptr<base::CancelableTaskTracker> _faviconTasks;
  // The DownloadManager observer and the host's downloads delegate.
  std::unique_ptr<room::ProfileDownloads> _downloads;
  // The host keeps its profiles for the whole session (its windows show
  // their pages); without this Chrome destroys a profile when its last
  // Browser closes (the last page of a window), and the next page the host
  // makes for it would find it gone (found by 3.4b's closeunload).
  std::unique_ptr<ScopedProfileKeepAlive> _keepAlive;
  // Chrome's history and the omnibox controllers handed out (3.5); both
  // let go of the profile's services when it goes away.
  RoomProfileHistory* _history;
  NSHashTable<RoomAutocompleteController*>* _autocompleteControllers;
  // Chrome's extension system (3.6a), made when the host first asks.
  RoomProfileExtensions* _extensions;
  // The password importer (4.3b), made with the first import.
  std::unique_ptr<room::PasswordImport> _passwordImport;
}

+ (RoomProfile*)room_profileFor:(Profile*)profile {
  if (!profile) {
    return nil;
  }
  auto* data =
      static_cast<ProfileWrapper*>(profile->GetUserData(kRoomProfileKey));
  if (!data) {
    RoomProfile* wrapper = [[RoomProfile alloc] initWithProfile:profile];
    auto owned = std::make_unique<ProfileWrapper>(profile, wrapper);
    data = owned.get();
    profile->SetUserData(kRoomProfileKey, std::move(owned));
  }
  return data->wrapper();
}

+ (RoomProfile*)room_existingProfileFor:(Profile*)profile {
  auto* data = profile ? static_cast<ProfileWrapper*>(
                             profile->GetUserData(kRoomProfileKey))
                       : nullptr;
  return data ? data->wrapper() : nil;
}

- (instancetype)initWithProfile:(Profile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    const base::FilePath path = profile->GetPath();
    _name = base::SysUTF8ToNSString(path.BaseName().value());
    _directory = [NSURL fileURLWithPath:base::SysUTF8ToNSString(path.value())
                            isDirectory:YES];
    _offTheRecord = profile->IsOffTheRecord();
    if (!_offTheRecord) {
      _keepAlive = std::make_unique<ScopedProfileKeepAlive>(
          profile, ProfileKeepAliveOrigin::kBrowserWindow);
    }
    _lastExitWasClean = YES;
    if (ExitTypeService* exits =
            ExitTypeService::GetInstanceForProfile(profile)) {
      _lastExitWasClean =
          exits->last_session_exit_type() == ExitType::kClean;
      // Chrome waits for the user to acknowledge a crash (its restore bubble,
      // or a tab in a Browser that session restore tracks: Room Browsers are
      // omitted) before a clean quit may record "Normal" again. The host
      // owns crash recovery, so a lock released at once is the
      // acknowledgement.
      if (exits->waiting_for_user_to_ack_crash()) {
        exits->CreateCrashedLock().reset();
      }
      // The service marked this session "Crashed" in the profile's prefs;
      // write it now, not with the pref writer's next batch (~10 s), so a
      // crash in the first seconds is seen at the next launch too.
      profile->GetPrefs()->CommitPendingWrite();
      LOG(INFO) << "RoomCore: profile " << path.BaseName().value()
                << " last exit " << (_lastExitWasClean ? "clean" : "unclean")
                << (exits->waiting_for_user_to_ack_crash()
                        ? " (crash not acknowledged)"
                        : "");
    }
  }
  return self;
}

- (NSString*)name {
  return _name;
}

- (NSURL*)directory {
  return _directory;
}

- (BOOL)isOffTheRecord {
  return _offTheRecord;
}

- (BOOL)lastExitWasClean {
  return _lastExitWasClean;
}

- (Profile*)room_profile {
  return _profile;
}

- (void)room_profileWillBeDestroyed {
  [_extensions room_profileWillBeDestroyed];
  [_history room_profileWillBeDestroyed];
  for (RoomAutocompleteController* controller in _autocompleteControllers) {
    [controller room_profileWillBeDestroyed];
  }
  _autocompleteControllers = nil;
  _passwordImport.reset();
  _keepAlive.reset();
  _downloads.reset();
  _faviconTasks.reset();
  _profile = nullptr;
}

- (RoomWebContents*)createWebContents {
  return [self createWebContentsInitiallyHidden:NO];
}

- (RoomWebContents*)createWebContentsInitiallyHidden:(BOOL)initiallyHidden {
  CHECK(_profile) << "createWebContents on a destroyed profile";
  content::WebContents::CreateParams params(_profile);
  // Hidden until its view is in a visible window: WebContentsViewCocoa
  // reports VISIBLE then (and HIDDEN when the host takes the view out).
  params.initially_hidden = initiallyHidden;
  return [[RoomWebContents alloc]
      initWithChromeWebContents:content::WebContents::Create(params)
                       profile:self];
}

- (void)faviconForPageURL:(NSURL*)pageURL
               completion:(void (^)(NSImage*))completion {
  favicon::FaviconService* service =
      _profile ? FaviconServiceFactory::GetForProfile(
                     _profile, ServiceAccessType::EXPLICIT_ACCESS)
               : nullptr;
  const GURL url = net::GURLWithNSURL(pageURL);
  if (!service || !url.is_valid()) {
    completion(nil);
    return;
  }
  if (!_faviconTasks) {
    _faviconTasks = std::make_unique<base::CancelableTaskTracker>();
  }
  void (^callback)(NSImage*) = [completion copy];
  service->GetFaviconImageForPageURL(
      url,
      base::BindOnce(^(const favicon_base::FaviconImageResult& result) {
        callback(result.image.IsEmpty() ? nil : result.image.ToNSImage());
      }),
      _faviconTasks.get());
}

// MARK: Downloads (Phase 3.4a)

- (room::ProfileDownloads*)room_downloads {
  if (!_downloads && _profile) {
    _downloads = room::ProfileDownloads::Create(_profile, self);
  }
  return _downloads.get();
}

- (id<RoomProfileDownloadsDelegate>)downloadsDelegate {
  return _downloads ? _downloads->delegate() : nil;
}

- (void)setDownloadsDelegate:(id<RoomProfileDownloadsDelegate>)delegate {
  if (room::ProfileDownloads* downloads = [self room_downloads]) {
    downloads->SetDelegate(delegate);
  }
}

- (NSArray<RoomDownloadItem*>*)downloads {
  room::ProfileDownloads* downloads = [self room_downloads];
  return downloads ? downloads->AllDownloads() : @[];
}

- (void)pauseDownload:(NSString*)identifier {
  if (room::ProfileDownloads* downloads = [self room_downloads]) {
    downloads->Pause(identifier);
  }
}

- (void)resumeDownload:(NSString*)identifier {
  if (room::ProfileDownloads* downloads = [self room_downloads]) {
    downloads->Resume(identifier);
  }
}

- (void)cancelDownload:(NSString*)identifier {
  if (room::ProfileDownloads* downloads = [self room_downloads]) {
    downloads->Cancel(identifier);
  }
}

- (void)removeDownload:(NSString*)identifier {
  if (room::ProfileDownloads* downloads = [self room_downloads]) {
    downloads->Remove(identifier);
  }
}

// MARK: Site settings (Phase 3.4a)

- (RoomContentSetting)contentSettingForType:(RoomContentSettingType)type
                                     origin:(NSURL*)origin {
  return room::GetContentSetting(_profile, type, origin);
}

- (void)setContentSetting:(RoomContentSetting)setting
                  forType:(RoomContentSettingType)type
                   origin:(NSURL*)origin {
  room::SetContentSetting(_profile, setting, type, origin);
}

- (void)clearSiteData:(RoomSiteDataTypes)types
            forOrigin:(NSURL*)origin
           completion:(void (^)(void))completion {
  room::ClearSiteData(_profile, types, origin, completion);
}

// MARK: History and the omnibox (Phase 3.5)

- (RoomProfileHistory*)history {
  if (!_history && _profile && !_offTheRecord) {
    _history = [[RoomProfileHistory alloc] initWithChromeProfile:_profile];
  }
  return _history;
}

- (RoomAutocompleteController*)makeAutocompleteController {
  if (!_profile || _offTheRecord) {
    return nil;
  }
  RoomAutocompleteController* controller =
      [[RoomAutocompleteController alloc] initWithChromeProfile:_profile];
  if (!_autocompleteControllers) {
    _autocompleteControllers = [NSHashTable weakObjectsHashTable];
  }
  [_autocompleteControllers addObject:controller];
  return controller;
}

- (void)setDefaultSearchEngineWithName:(NSString*)name
                               keyword:(NSString*)keyword
                             searchURL:(NSString*)searchURL
                            suggestURL:(NSString*)suggestURL {
  if (!_profile) {
    return;
  }
  room::SetDefaultSearchEngine(
      _profile, base::SysNSStringToUTF16(name),
      base::SysNSStringToUTF16(keyword), base::SysNSStringToUTF8(searchURL),
      suggestURL ? base::SysNSStringToUTF8(suggestURL) : std::string());
}

// MARK: Extensions (Phase 3.6a)

- (RoomProfileExtensions*)extensions {
  if (!_extensions && _profile && !_offTheRecord) {
    _extensions = [[RoomProfileExtensions alloc] initWithChromeProfile:_profile];
  }
  return _extensions;
}

- (RoomProfileExtensions*)room_existingExtensions {
  return _extensions;
}

// MARK: Passwords (Phase 4.3b)

- (void)importPasswordsFromCSV:(NSString*)csv
              replaceConflicts:(BOOL)replaceConflicts
                    completion:(void (^)(NSDictionary<NSString*, id>*))completion {
  if (!_profile || _offTheRecord) {
    completion(@{@"status" : @"unavailable"});
    return;
  }
  if (!_passwordImport) {
    _passwordImport = std::make_unique<room::PasswordImport>(_profile);
  }
  _passwordImport->Start(base::SysNSStringToUTF8(csv), replaceConflicts,
                         completion);
}

- (BOOL)searchSuggestEnabled {
  return _profile &&
         _profile->GetPrefs()->GetBoolean(prefs::kSearchSuggestEnabled);
}

- (void)setSearchSuggestEnabled:(BOOL)enabled {
  if (_profile) {
    _profile->GetPrefs()->SetBoolean(prefs::kSearchSuggestEnabled, enabled);
  }
}

@end
