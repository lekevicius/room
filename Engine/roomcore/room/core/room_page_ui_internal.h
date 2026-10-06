// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_PAGE_UI_INTERNAL_H_
#define ROOM_CORE_ROOM_PAGE_UI_INTERNAL_H_

// What Chrome would draw for a Room page, handed to the host (Phase 3.4a):
// permission prompts (patch 0017), context menus (0018), downloads (0019),
// HTTP auth (0020), certificate errors (0021), file choosers (0022); and
// (3.4b) JavaScript dialogs and beforeunload, the hung-page question,
// external protocols (0023), infobars and the translate offer, the capture
// state and the media session.

#import "room/core/public/RoomBrowser.h"
#import "room/core/public/RoomProfile.h"
#import "room/core/public/RoomWebContents.h"

#include <memory>

class Profile;

namespace content {
class WebContents;
}

namespace room {

// Each installs its hook (called once from RoomApplication at startup).
void InstallPermissionPromptHook();
void InstallContextMenuHook();
void InstallDownloadTargetHook();
void InstallPagePromptHooks();
// The external protocol hook (patch 0023).
void InstallPageDialogHooks();
// Replaces Chrome's Cocoa app-modal alert (beforeunload) for Room pages;
// called once Chrome installed its own (after PreProfileInit).
void InstallAppModalDialogFactory();

// Once a page has Chrome's tab helpers: its TabModalDialogManager gets
// //room's delegate, its TabDialogs //room's wrapper (AdoptPageDialogs), and
// its notices, capture state and media session are observed. Idempotent per
// WebContents.
void AttachPageServices(content::WebContents* contents);
void AdoptPageDialogs(content::WebContents* contents);
// At the quit (the will-terminate notification), before Chrome's singletons
// go: the capture observer and the translate factory are removed.
void DetachPageServiceObservers();
// MediaStreamCaptureIndicator::StopMediaCapturing for `kinds`.
void StopCapturing(content::WebContents* contents, RoomCaptureKinds kinds);

// The wrapper of a Room page whose delegate implements `selector`; nil for
// every other page (Chrome keeps its own UI there).
RoomWebContents* WrapperAnswering(content::WebContents* contents, SEL selector);

// A profile's downloads: the DownloadManager observer and the host's
// delegate, owned by the RoomProfile.
class ProfileDownloads {
 public:
  static std::unique_ptr<ProfileDownloads> Create(Profile* profile,
                                                  RoomProfile* wrapper);
  virtual ~ProfileDownloads() = default;
  // The host's delegate (set: every known download is replayed to it).
  virtual void SetDelegate(id<RoomProfileDownloadsDelegate> delegate) = 0;
  virtual id<RoomProfileDownloadsDelegate> delegate() const = 0;
  virtual NSArray<RoomDownloadItem*>* AllDownloads() = 0;
  virtual void Pause(NSString* identifier) = 0;
  virtual void Resume(NSString* identifier) = 0;
  virtual void Cancel(NSString* identifier) = 0;
  virtual void Remove(NSString* identifier) = 0;
};

// The site panel's settings (HostContentSettingsMap) and site data removal.
RoomContentSetting GetContentSetting(Profile* profile,
                                     RoomContentSettingType type,
                                     NSURL* origin);
void SetContentSetting(Profile* profile,
                       RoomContentSetting setting,
                       RoomContentSettingType type,
                       NSURL* origin);
void ClearSiteData(Profile* profile,
                   RoomSiteDataTypes types,
                   NSURL* origin,
                   void (^completion)(void));
// Settings ▸ Privacy (4.4b): the sites with their own setting for `type`
// (-[RoomProfile contentSettingsForType:]) and Clear browsing data.
NSArray<NSDictionary<NSString*, id>*>* ContentSettingsForType(
    Profile* profile,
    RoomContentSettingType type);
void ClearBrowsingData(Profile* profile,
                       RoomBrowsingDataTypes types,
                       RoomBrowsingDataPeriod period,
                       void (^completion)(void));

}  // namespace room

#endif  // ROOM_CORE_ROOM_PAGE_UI_INTERNAL_H_
