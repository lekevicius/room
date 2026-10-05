// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_profile_internal.h"

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
#include "base/logging.h"
#include "base/task/cancelable_task_tracker.h"
#include "chrome/browser/favicon/favicon_service_factory.h"
#include "components/favicon/core/favicon_service.h"
#include "components/favicon_base/favicon_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "ui/gfx/image/image.h"
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

- (instancetype)initWithProfile:(Profile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    const base::FilePath path = profile->GetPath();
    _name = base::SysUTF8ToNSString(path.BaseName().value());
    _directory = [NSURL fileURLWithPath:base::SysUTF8ToNSString(path.value())
                            isDirectory:YES];
    _offTheRecord = profile->IsOffTheRecord();
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

@end
