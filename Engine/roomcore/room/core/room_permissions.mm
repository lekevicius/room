// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Permission prompts of Room pages (patch 0017) and the site panel's
// settings: Chrome's PermissionRequestManager keeps deciding when to ask,
// what is remembered (HostContentSettingsMap) and what a navigation
// withdraws; the host draws the prompt and answers it.

#import "room/core/room_page_ui_internal.h"

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "base/barrier_closure.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/permissions/system/system_permission_settings.h"
#include "chrome/browser/profiles/profile.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_pattern.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/content_settings/core/common/content_settings_utils.h"
#include "components/permissions/permission_prompt.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_constants.h"
#include "components/permissions/request_type.h"
#include "content/public/browser/browsing_data_filter_builder.h"
#include "content/public/browser/browsing_data_remover.h"
#include "content/public/browser/ssl_host_state_delegate.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "services/network/public/mojom/clear_data_filter.mojom.h"
#include "services/network/public/mojom/network_context.mojom.h"
#include "url/gurl.h"
#include "url/origin.h"
#import "room/core/room_web_contents_internal.h"

namespace room {
// Defined in chrome/browser/ui/views/permissions/permission_prompt_factory.cc
// (patches/0017-permission-prompt-factory-hook.patch).
extern std::unique_ptr<permissions::PermissionPrompt> (
    *g_create_permission_prompt_hook)(content::WebContents*,
                                      permissions::PermissionPrompt::Delegate*);
}  // namespace room

@interface RoomPermissionRequest ()
- (instancetype)initWithKind:(RoomPermissionKind)kind
                      origin:(NSURL*)origin
   embeddedPermissionElement:(BOOL)embedded
         systemAuthorization:(RoomSystemAuthorization)systemAuthorization;
@end

@implementation RoomPermissionRequest

@synthesize kind = _kind;
@synthesize origin = _origin;
@synthesize embeddedPermissionElement = _embeddedPermissionElement;
@synthesize systemAuthorization = _systemAuthorization;

- (instancetype)initWithKind:(RoomPermissionKind)kind
                      origin:(NSURL*)origin
   embeddedPermissionElement:(BOOL)embedded
         systemAuthorization:(RoomSystemAuthorization)systemAuthorization {
  if ((self = [super init])) {
    _kind = kind;
    _origin = [origin copy];
    _embeddedPermissionElement = embedded;
    _systemAuthorization = systemAuthorization;
  }
  return self;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomPermissionRequest kind=%ld %@ "
                                    @"element=%d system=%ld>",
                                    (long)_kind, _origin,
                                    _embeddedPermissionElement,
                                    (long)_systemAuthorization];
}

@end

namespace room {

RoomWebContents* WrapperAnswering(content::WebContents* contents,
                                  SEL selector) {
  RoomWebContents* wrapper =
      contents ? [RoomWebContents room_existingWrapperFor:contents] : nil;
  id delegate = wrapper.delegate;
  return [delegate respondsToSelector:selector] ? wrapper : nil;
}

}  // namespace room

namespace {

// Every desktop request type, one case each.
RoomPermissionKind ToRoomKind(permissions::RequestType type) {
  using permissions::RequestType;
  switch (type) {
    case RequestType::kArSession:
      return RoomPermissionKindArSession;
    case RequestType::kCameraPanTiltZoom:
      return RoomPermissionKindCameraPanTiltZoom;
    case RequestType::kCameraStream:
      return RoomPermissionKindCamera;
    case RequestType::kCapturedSurfaceControl:
      return RoomPermissionKindCapturedSurfaceControl;
    case RequestType::kClipboard:
      return RoomPermissionKindClipboard;
    case RequestType::kTopLevelStorageAccess:
      return RoomPermissionKindTopLevelStorageAccess;
    case RequestType::kDiskQuota:
      return RoomPermissionKindPersistentStorage;
    case RequestType::kFileSystemAccess:
      return RoomPermissionKindFileSystemAccess;
    case RequestType::kGeolocation:
      return RoomPermissionKindGeolocation;
    case RequestType::kHandTracking:
      return RoomPermissionKindHandTracking;
    case RequestType::kIdentityProvider:
      return RoomPermissionKindIdentityProvider;
    case RequestType::kIdleDetection:
      return RoomPermissionKindIdleDetection;
    case RequestType::kLocalFonts:
      return RoomPermissionKindLocalFonts;
    case RequestType::kLocalNetwork:
      return RoomPermissionKindLocalNetwork;
    case RequestType::kLoopbackNetwork:
      return RoomPermissionKindLoopbackNetwork;
    case RequestType::kMicStream:
      return RoomPermissionKindMicrophone;
    case RequestType::kMidiSysex:
      return RoomPermissionKindMidiSysex;
    case RequestType::kMultipleDownloads:
      return RoomPermissionKindMultipleDownloads;
    case RequestType::kNotifications:
      return RoomPermissionKindNotifications;
    case RequestType::kKeyboardLock:
      return RoomPermissionKindKeyboardLock;
    case RequestType::kPointerLock:
      return RoomPermissionKindPointerLock;
    case RequestType::kRegisterProtocolHandler:
      return RoomPermissionKindRegisterProtocolHandler;
    case RequestType::kSensors:
      return RoomPermissionKindSensors;
    case RequestType::kStorageAccess:
      return RoomPermissionKindStorageAccess;
    case RequestType::kVrSession:
      return RoomPermissionKindVrSession;
    case RequestType::kWebAppInstallation:
      return RoomPermissionKindWebAppInstallation;
    case RequestType::kWindowManagement:
      return RoomPermissionKindWindowManagement;
  }
  NOTREACHED();
}

RoomPermissionQuietReason ToRoomQuietReason(
    std::optional<permissions::PermissionUiSelector::QuietUiReason> reason) {
  using Reason = permissions::PermissionUiSelector::QuietUiReason;
  if (!reason) {
    return RoomPermissionQuietReasonNone;
  }
  switch (*reason) {
    case Reason::kEnabledInPrefs:
      return RoomPermissionQuietReasonEnabledInSettings;
    case Reason::kTriggeredByCrowdDeny:
      return RoomPermissionQuietReasonCrowdDeny;
    case Reason::kTriggeredDueToAbusiveRequests:
      return RoomPermissionQuietReasonAbusiveRequests;
    case Reason::kTriggeredDueToAbusiveContent:
      return RoomPermissionQuietReasonAbusiveContent;
    case Reason::kServicePredictedVeryUnlikelyGrant:
      return RoomPermissionQuietReasonServicePredictedUnlikelyGrant;
    case Reason::kOnDevicePredictedVeryUnlikelyGrant:
      return RoomPermissionQuietReasonOnDevicePredictedUnlikelyGrant;
    case Reason::kTriggeredDueToDisruptiveBehavior:
      return RoomPermissionQuietReasonDisruptiveBehavior;
    case Reason::kTriggeredDueToLackOfGesture:
      return RoomPermissionQuietReasonLackOfGesture;
  }
  return RoomPermissionQuietReasonNone;
}

// macOS's authorization for what the request needs (Chrome's cached
// system_permission_settings; camera, microphone, location and
// notifications have one).
RoomSystemAuthorization SystemAuthorizationFor(ContentSettingsType type) {
  switch (type) {
    case ContentSettingsType::MEDIASTREAM_CAMERA:
    case ContentSettingsType::MEDIASTREAM_MIC:
    case ContentSettingsType::CAMERA_PAN_TILT_ZOOM:
    case ContentSettingsType::GEOLOCATION:
    case ContentSettingsType::NOTIFICATIONS:
      break;
    default:
      return RoomSystemAuthorizationNotApplicable;
  }
  if (system_permission_settings::IsAllowed(type)) {
    return RoomSystemAuthorizationAuthorized;
  }
  if (system_permission_settings::IsDenied(type)) {
    return RoomSystemAuthorizationDenied;
  }
  return RoomSystemAuthorizationNotDetermined;
}

NSURL* ToNSURL(const GURL& url) {
  return url.is_valid() ? net::NSURLWithGURL(url) : nil;
}

// The host's prompt for one PermissionRequestManager prompt. The manager
// owns it and destroys it when the prompt ends: an answer (Accept/Deny/...
// finalizes the requests and deletes the prompt synchronously), a
// navigation, the page closing. Destroyed without the host's answer, it
// tells the host the prompt is withdrawn.
class RoomPermissionPrompt : public permissions::PermissionPrompt {
 public:
  RoomPermissionPrompt(Delegate* delegate, RoomWebContents* wrapper)
      : delegate_(delegate), wrapper_(wrapper) {}

  RoomPermissionPrompt(const RoomPermissionPrompt&) = delete;
  RoomPermissionPrompt& operator=(const RoomPermissionPrompt&) = delete;

  ~RoomPermissionPrompt() override {
    if (answered_ || !asked_) {
      return;
    }
    RoomWebContents* wrapper = wrapper_;
    id<RoomWebContentsDelegate> delegate = wrapper.delegate;
    if ([delegate respondsToSelector:@selector
                  (webContentsDidDismissPermissionPrompt:)]) {
      [delegate webContentsDidDismissPermissionPrompt:wrapper];
    }
  }

  // Asks the host (once, right after the manager created the prompt).
  void Ask() {
    RoomWebContents* wrapper = wrapper_;
    id<RoomWebContentsDelegate> delegate = wrapper.delegate;
    if (!wrapper || ![delegate respondsToSelector:@selector
                               (webContents:willAskForPermissions:quietReason:
                                    completion:)]) {
      return;
    }
    NSMutableArray<RoomPermissionRequest*>* requests = [NSMutableArray array];
    for (const auto& request : delegate_->Requests()) {
      [requests addObject:[[RoomPermissionRequest alloc]
                                   initWithKind:ToRoomKind(request->request_type())
                                         origin:ToNSURL(request->requesting_origin())
                      embeddedPermissionElement:request->IsEmbeddedPermissionElementInitiated()
                            systemAuthorization:SystemAuthorizationFor(
                                                    request->GetContentSettingsType())]];
    }
    const RoomPermissionQuietReason quiet =
        ToRoomQuietReason(delegate_->ReasonForUsingQuietUi());
    LOG(INFO) << "RoomCore: permission prompt for "
              << delegate_->GetRequestingOrigin().spec() << ": "
              << base::SysNSStringToUTF8(requests.description)
              << " quiet=" << static_cast<int>(quiet);
    asked_ = true;
    base::WeakPtr<RoomPermissionPrompt> weak = weak_factory_.GetWeakPtr();
    [delegate webContents:wrapper
        willAskForPermissions:requests
                  quietReason:quiet
                   completion:^(RoomPermissionResponse response) {
                     if (weak) {
                       weak->Answer(response);
                     }
                   }];
  }

  // permissions::PermissionPrompt:
  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override {
    // The host keeps a hidden page's prompt queued and shows it again.
    return TabSwitchingBehavior::kKeepPromptAlive;
  }
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override {
    return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE;
  }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override {
    return std::nullopt;
  }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override {
    return {};
  }
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  void Answer(RoomPermissionResponse response) {
    if (answered_) {
      return;
    }
    answered_ = true;
    // Geolocation with options (the approximate-location experiment) takes
    // the accuracy; Room asks for precise.
    PromptOptions options = std::monostate();
    // GetGeolocationPromptType() CHECKs a single request (a camera and
    // microphone prompt has two; found by 3.4b's capture run).
    if (delegate_->Requests().size() == 1 &&
        delegate_->GetGeolocationPromptType().has_value()) {
      options = GeolocationPromptOptions{GeolocationAccuracy::kPrecise};
    }
    // Each call finalizes the requests and destroys `this`.
    Delegate* delegate = delegate_;
    switch (response) {
      case RoomPermissionResponseGranted:
        delegate->Accept(options);
        return;
      case RoomPermissionResponseGrantedOnce:
        delegate->AcceptThisTime(options);
        return;
      case RoomPermissionResponseDenied:
        delegate->Deny(options);
        return;
      case RoomPermissionResponseDismissed:
        delegate->Dismiss(options);
        return;
    }
    delegate->Dismiss(options);
  }

  const raw_ptr<Delegate> delegate_;
  RoomWebContents* __weak wrapper_;
  bool asked_ = false;
  bool answered_ = false;
  base::WeakPtrFactory<RoomPermissionPrompt> weak_factory_{this};
};

}  // namespace

namespace room {

void InstallPermissionPromptHook() {
  g_create_permission_prompt_hook =
      +[](content::WebContents* contents,
          permissions::PermissionPrompt::Delegate* delegate)
      -> std::unique_ptr<permissions::PermissionPrompt> {
    RoomWebContents* wrapper = WrapperAnswering(
        contents,
        @selector(webContents:willAskForPermissions:quietReason:completion:));
    if (!wrapper || delegate->Requests().empty()) {
      return nullptr;
    }
    auto prompt = std::make_unique<RoomPermissionPrompt>(delegate, wrapper);
    prompt->Ask();
    return prompt;
  };
}

}  // namespace room

// MARK: - The site panel's settings and site data

namespace {

ContentSettingsType ToContentSettingsType(RoomContentSettingType type) {
  switch (type) {
    case RoomContentSettingTypeGeolocation:
      return ContentSettingsType::GEOLOCATION;
    case RoomContentSettingTypeCamera:
      return ContentSettingsType::MEDIASTREAM_CAMERA;
    case RoomContentSettingTypeMicrophone:
      return ContentSettingsType::MEDIASTREAM_MIC;
    case RoomContentSettingTypeNotifications:
      return ContentSettingsType::NOTIFICATIONS;
    case RoomContentSettingTypeClipboard:
      return ContentSettingsType::CLIPBOARD_READ_WRITE;
    case RoomContentSettingTypeSensors:
      return ContentSettingsType::SENSORS;
    case RoomContentSettingTypeMidiSysex:
      return ContentSettingsType::MIDI_SYSEX;
    case RoomContentSettingTypePopups:
      return ContentSettingsType::POPUPS;
    case RoomContentSettingTypeSound:
      return ContentSettingsType::SOUND;
    case RoomContentSettingTypeAutomaticDownloads:
      return ContentSettingsType::AUTOMATIC_DOWNLOADS;
    case RoomContentSettingTypeJavaScript:
      return ContentSettingsType::JAVASCRIPT;
    case RoomContentSettingTypeImages:
      return ContentSettingsType::IMAGES;
  }
  return ContentSettingsType::DEFAULT;
}

constexpr RoomContentSettingType kAllSettingTypes[] = {
    RoomContentSettingTypeGeolocation, RoomContentSettingTypeCamera,
    RoomContentSettingTypeMicrophone,  RoomContentSettingTypeNotifications,
    RoomContentSettingTypeClipboard,   RoomContentSettingTypeSensors,
    RoomContentSettingTypeMidiSysex,   RoomContentSettingTypePopups,
    RoomContentSettingTypeSound,       RoomContentSettingTypeAutomaticDownloads,
    RoomContentSettingTypeJavaScript,  RoomContentSettingTypeImages,
};

// The site's registrable domain (an IP or a local name stands for itself):
// what Chrome's own "delete data for this site" removes.
std::string SiteOf(const GURL& url) {
  std::string domain = net::registry_controlled_domains::GetDomainAndRegistry(
      url, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  return domain.empty() ? std::string(url.host()) : domain;
}

// Observes one removal (registered with the remover first, as it requires)
// and deletes itself when it is done.
class RemovalObserver : public content::BrowsingDataRemover::Observer {
 public:
  RemovalObserver(content::BrowsingDataRemover* remover, base::OnceClosure done)
      : remover_(remover), done_(std::move(done)) {
    remover_->AddObserver(this);
  }
  void OnBrowsingDataRemoverDone(uint64_t failed_data_types) override {
    if (failed_data_types) {
      LOG(WARNING) << "RoomCore: site data removal failed for types "
                   << failed_data_types;
    }
    remover_->RemoveObserver(this);
    std::move(done_).Run();
    delete this;
  }

 private:
  raw_ptr<content::BrowsingDataRemover> remover_;
  base::OnceClosure done_;
};

}  // namespace

namespace room {

RoomContentSetting GetContentSetting(Profile* profile,
                                     RoomContentSettingType type,
                                     NSURL* origin) {
  HostContentSettingsMap* map =
      profile ? HostContentSettingsMapFactory::GetForProfile(profile) : nullptr;
  const GURL url = net::GURLWithNSURL(origin);
  if (!map || !url.is_valid()) {
    return RoomContentSettingDefault;
  }
  content_settings::SettingInfo info;
  const ContentSetting setting =
      map->GetContentSetting(url, url, ToContentSettingsType(type), &info);
  // A value from the wildcard patterns is the default, not the site's.
  if (info.primary_pattern.MatchesAllHosts() &&
      info.secondary_pattern.MatchesAllHosts()) {
    return RoomContentSettingDefault;
  }
  switch (setting) {
    case CONTENT_SETTING_ALLOW:
    case CONTENT_SETTING_SESSION_ONLY:
      return RoomContentSettingAllow;
    case CONTENT_SETTING_BLOCK:
      return RoomContentSettingBlock;
    case CONTENT_SETTING_ASK:
      return RoomContentSettingAsk;
    default:
      return RoomContentSettingDefault;
  }
}

void SetContentSetting(Profile* profile,
                       RoomContentSetting setting,
                       RoomContentSettingType type,
                       NSURL* origin) {
  HostContentSettingsMap* map =
      profile ? HostContentSettingsMapFactory::GetForProfile(profile) : nullptr;
  const GURL url = net::GURLWithNSURL(origin);
  if (!map || !url.is_valid()) {
    return;
  }
  ContentSetting value = CONTENT_SETTING_DEFAULT;
  switch (setting) {
    case RoomContentSettingAllow:
      value = CONTENT_SETTING_ALLOW;
      break;
    case RoomContentSettingBlock:
      value = CONTENT_SETTING_BLOCK;
      break;
    case RoomContentSettingAsk:
      value = CONTENT_SETTING_ASK;
      break;
    case RoomContentSettingDefault:
      break;
  }
  map->SetContentSettingDefaultScope(url, url, ToContentSettingsType(type),
                                     value);
}

void ClearSiteData(Profile* profile,
                   RoomSiteDataTypes types,
                   NSURL* origin,
                   void (^completion)(void)) {
  void (^done)(void) = [completion copy];
  if (!profile) {
    done();
    return;
  }
  const GURL url = origin ? net::GURLWithNSURL(origin) : GURL();
  const bool all_sites = !origin;
  if (!all_sites && !url.is_valid()) {
    done();
    return;
  }
  // Permissions and certificate decisions are synchronous.
  if (types & RoomSiteDataTypePermissions) {
    HostContentSettingsMap* map =
        HostContentSettingsMapFactory::GetForProfile(profile);
    for (RoomContentSettingType type : kAllSettingTypes) {
      if (all_sites) {
        map->ClearSettingsForOneType(ToContentSettingsType(type));
      } else {
        map->SetContentSettingDefaultScope(
            url, url, ToContentSettingsType(type), CONTENT_SETTING_DEFAULT);
      }
    }
    if (content::SSLHostStateDelegate* ssl = profile->GetSSLHostStateDelegate()) {
      const std::string host(url.host());
      ssl->Clear(all_sites ? base::RepeatingCallback<bool(const std::string&)>()
                           : base::BindRepeating(
                                 [](const std::string& host,
                                    const std::string& candidate) {
                                   return candidate == host;
                                 },
                                 host));
    }
  }
  // The rest finish asynchronously; `done` runs once after the last.
  auto barrier = base::BarrierClosure(2, base::BindOnce(^{
                                        done();
                                      }));
  uint64_t remove_mask = 0;
  if (types & RoomSiteDataTypeCookies) {
    remove_mask |= content::BrowsingDataRemover::DATA_TYPE_COOKIES;
  }
  if (types & RoomSiteDataTypeCache) {
    remove_mask |= content::BrowsingDataRemover::DATA_TYPE_CACHE;
  }
  if (types & RoomSiteDataTypeStorage) {
    remove_mask |= content::BrowsingDataRemover::DATA_TYPE_DOM_STORAGE;
  }
  if (remove_mask) {
    std::unique_ptr<content::BrowsingDataFilterBuilder> filter =
        content::BrowsingDataFilterBuilder::Create(
            all_sites ? content::BrowsingDataFilterBuilder::Mode::kPreserve
                      : content::BrowsingDataFilterBuilder::Mode::kDelete);
    if (!all_sites) {
      filter->AddRegisterableDomain(SiteOf(url));
    }
    content::BrowsingDataRemover* remover = profile->GetBrowsingDataRemover();
    remover->RemoveWithFilterAndReply(
        base::Time(), base::Time::Max(), remove_mask,
        content::BrowsingDataRemover::ORIGIN_TYPE_UNPROTECTED_WEB,
        std::move(filter), new RemovalObserver(remover, barrier));
  } else {
    barrier.Run();
  }
  if (types & RoomSiteDataTypeHTTPAuthCredentials) {
    network::mojom::ClearDataFilterPtr filter;
    if (!all_sites) {
      filter = network::mojom::ClearDataFilter::New();
      filter->type = network::mojom::ClearDataFilter::Type::DELETE_MATCHES;
      filter->origins.push_back(url::Origin::Create(url));
    }
    profile->GetDefaultStoragePartition()
        ->GetNetworkContext()
        ->ClearHttpAuthCache(base::Time(), base::Time::Max(), std::move(filter),
                             barrier);
  } else {
    barrier.Run();
  }
}

}  // namespace room
