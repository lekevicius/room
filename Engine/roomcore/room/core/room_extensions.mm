// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Chrome extensions behind RoomExtensions.h (Phase 3.6a): the installed list
// from ExtensionRegistry, management through ExtensionRegistrar with the
// host's consent, actions from ExtensionActionManager, the pinned order from
// ToolbarActionsModel, unpacked loads (UnpackedInstaller), the install prompt
// handed to the host (patch 0024) and update checks only inside the host's
// call (patch 0025).

#import "room/core/room_extensions_internal.h"

#include <memory>
#include <string>
#include <vector>

#include "base/auto_reset.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/one_shot_event.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/apps/platform_apps/shortcut_manager.h"
#include "chrome/browser/extensions/api/side_panel/side_panel_service.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/updater/chrome_update_client_config.h"
#include "chrome/browser/extensions/updater/extension_updater.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/browser/ui/extensions/extension_install_ui.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "chrome/common/extensions/api/side_panel.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/image_loader.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/blocked_action_type.h"
#include "extensions/browser/install_prompt_permissions.h"
#include "extensions/browser/permissions/active_tab_permission_granter.h"
#include "extensions/browser/permissions/scripting_permissions_modifier.h"
#include "extensions/browser/permissions/site_permissions_helper.h"
#include "extensions/browser/permissions_manager.h"
#include "extensions/browser/ui_util.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/browser/unpacked_installer.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_set.h"
#include "extensions/common/icons/extension_icon_set.h"
#include "extensions/common/manifest.h"
#include "extensions/common/manifest_handlers/icons_handler.h"
#include "extensions/common/manifest_handlers/options_page_info.h"
#include "extensions/common/permissions/permission_message.h"
#include "extensions/common/permissions/permissions_data.h"
#include "extensions/common/url_pattern.h"
#include "extensions/common/user_script.h"
#include "ui/base/accelerators/command.h"
#include "net/base/apple/url_conversions.h"
#include "skia/ext/skia_utils_mac.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#import "room/core/room_browser_internal.h"
#import "room/core/room_extension_popups.h"
#include "chrome/browser/extensions/extension_util.h"
#include "extensions/browser/extension_util.h"
#import "room/core/room_profile_internal.h"
#import "room/core/room_web_contents_internal.h"

namespace room {
// patches/0024-extension-install-dialog-hook.patch
extern bool (*g_show_extension_install_dialog_hook)(
    std::unique_ptr<ExtensionInstallPromptShowParams>&,
    ExtensionInstallPrompt::DoneCallback&,
    std::unique_ptr<extensions::InstallPromptData>&);
// patches/0025-extension-update-allowed-hook.patch
extern bool (*g_extension_update_allowed_hook)();
}  // namespace room

namespace {

// True only inside -checkForUpdatesWithCompletion:'s CheckNow call: the
// update checks start synchronously there (UpdateService::StartUpdateCheck,
// ExtensionDownloader::StartAllPending with the null cache on macOS).
bool g_host_update_check = false;
// Checks Chrome started on its own (its schedule, runtime.requestUpdateCheck)
// and the gate refused; logged.
int g_refused_update_checks = 0;

NSString* ToNS(const std::string& s) {
  return base::SysUTF8ToNSString(s);
}

NSString* ToNS(const std::u16string& s) {
  return base::SysUTF16ToNSString(s);
}

NSImage* ToNSImage(const gfx::Image& image) {
  return image.IsEmpty() ? nil : image.ToNSImage();
}

NSColor* ToNSColor(SkColor color) {
  return skia::SkColorToSRGBNSColor(color);
}

bool IsListed(const extensions::Extension& extension) {
  return extensions::ui_util::ShouldDisplayInExtensionSettings(extension);
}

using UserSiteAccess = extensions::PermissionsManager::UserSiteAccess;

RoomExtensionSiteAccessLevel ToLevel(UserSiteAccess access) {
  switch (access) {
    case UserSiteAccess::kOnClick:
      return RoomExtensionSiteAccessLevelOnClick;
    case UserSiteAccess::kOnSite:
      return RoomExtensionSiteAccessLevelOnSite;
    case UserSiteAccess::kOnAllSites:
      return RoomExtensionSiteAccessLevelOnAllSites;
  }
}

UserSiteAccess FromLevel(RoomExtensionSiteAccessLevel level) {
  switch (level) {
    case RoomExtensionSiteAccessLevelOnSite:
      return UserSiteAccess::kOnSite;
    case RoomExtensionSiteAccessLevelOnAllSites:
      return UserSiteAccess::kOnAllSites;
    default:
      return UserSiteAccess::kOnClick;
  }
}

// Every open page of `profile` (the Room Browsers' tabs) whose host is `host`.
std::vector<content::WebContents*> PagesOfHost(Profile* profile,
                                               const std::string& host) {
  std::vector<content::WebContents*> pages;
  ProfileBrowserCollection* collection =
      ProfileBrowserCollection::GetForProfile(profile);
  if (!collection) {
    return pages;
  }
  collection->ForEach([&](BrowserWindowInterface* browser) {
    if (TabStripModel* model = browser->GetTabStripModel()) {
      for (int i = 0; i < model->count(); ++i) {
        content::WebContents* contents = model->GetWebContentsAt(i);
        if (contents && contents->GetLastCommittedURL().host() == host) {
          pages.push_back(contents);
        }
      }
    }
    return true;
  });
  return pages;
}

}  // namespace

// MARK: - Value types

@implementation RoomExtensionAction {
  NSString* _title;
  NSString* _badgeText;
  NSColor* _badgeBackgroundColor;
  NSColor* _badgeTextColor;
  NSImage* _icon;
  BOOL _enabled;
  BOOL _hasPopup;
}

- (instancetype)initWithAction:(const extensions::ExtensionAction&)action
                         tabID:(int)tabID
                   defaultIcon:(NSImage*)defaultIcon {
  if ((self = [super init])) {
    _title = ToNS(action.GetTitle(tabID));
    _badgeText = ToNS(action.GetDisplayBadgeText(tabID));
    if (action.HasBadgeBackgroundColor(tabID) ||
        action.HasBadgeBackgroundColor(
            extensions::ExtensionAction::kDefaultTabId)) {
      _badgeBackgroundColor = ToNSColor(action.GetBadgeBackgroundColor(tabID));
    }
    if (action.HasBadgeTextColor(tabID) ||
        action.HasBadgeTextColor(extensions::ExtensionAction::kDefaultTabId)) {
      _badgeTextColor = ToNSColor(action.GetBadgeTextColor(tabID));
    }
    _icon = ToNSImage(action.GetExplicitlySetIcon(tabID));
    if (!_icon) {
      _icon = ToNSImage(action.GetDeclarativeIcon(tabID));
    }
    if (!_icon) {
      _icon = defaultIcon;
    }
    _enabled = action.GetIsVisible(tabID);
    _hasPopup = action.HasPopup(tabID);
  }
  return self;
}

- (NSString*)title {
  return _title;
}
- (NSString*)badgeText {
  return _badgeText;
}
- (NSColor*)badgeBackgroundColor {
  return _badgeBackgroundColor;
}
- (NSColor*)badgeTextColor {
  return _badgeTextColor;
}
- (NSImage*)icon {
  return _icon;
}
- (BOOL)isEnabled {
  return _enabled;
}
- (BOOL)hasPopup {
  return _hasPopup;
}

@end

@interface RoomExtension ()
@property(nonatomic, readwrite, copy) NSString* identifier;
@property(nonatomic, readwrite, copy) NSString* name;
@property(nonatomic, readwrite, copy) NSString* version;
@property(nonatomic, readwrite, copy) NSString* summary;
@property(nonatomic, readwrite, nullable) NSImage* icon16;
@property(nonatomic, readwrite, nullable) NSImage* icon32;
@property(nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, readwrite, getter=isUnpacked) BOOL unpacked;
@property(nonatomic, readwrite) BOOL fromWebStore;
@property(nonatomic, readwrite, nullable) RoomExtensionAction* action;
@property(nonatomic, readwrite, getter=isPinned) BOOL pinned;
@property(nonatomic, readwrite, copy, nullable) NSURL* optionsPageURL;
@property(nonatomic, readwrite, copy) NSArray<NSString*>* permissionMessages;
@property(nonatomic, readwrite, copy) NSArray<NSString*>* hostPermissions;
@property(nonatomic, readwrite, copy, nullable) NSURL* directory;
- (instancetype)initPrivate;
@end

@implementation RoomExtension
@synthesize identifier = _identifier;
@synthesize name = _name;
@synthesize version = _version;
@synthesize summary = _summary;
@synthesize icon16 = _icon16;
@synthesize icon32 = _icon32;
@synthesize enabled = _enabled;
@synthesize unpacked = _unpacked;
@synthesize fromWebStore = _fromWebStore;
@synthesize action = _action;
@synthesize pinned = _pinned;
@synthesize optionsPageURL = _optionsPageURL;
@synthesize permissionMessages = _permissionMessages;
@synthesize hostPermissions = _hostPermissions;
@synthesize directory = _directory;
- (instancetype)initPrivate {
  return [super init];
}
- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomExtension %@ %@ %@%@>", _identifier,
                                    _name, _enabled ? @"enabled" : @"disabled",
                                    _pinned ? @" pinned" : @""];
}
@end

@interface RoomExtensionInstallRequest ()
@property(nonatomic, readwrite, copy) NSString* identifier;
@property(nonatomic, readwrite, copy) NSString* name;
@property(nonatomic, readwrite) RoomExtensionInstallKind kind;
@property(nonatomic, readwrite, copy) NSString* title;
@property(nonatomic, readwrite, copy) NSString* permissionsHeading;
@property(nonatomic, readwrite, copy) NSArray<NSString*>* permissions;
@property(nonatomic, readwrite, copy)
    NSArray<NSArray<NSString*>*>* permissionDetails;
@property(nonatomic, readwrite, nullable) NSImage* icon;
@property(nonatomic, readwrite, weak, nullable) RoomWebContents* webContents;
- (instancetype)initPrivate;
@end

@implementation RoomExtensionInstallRequest
@synthesize identifier = _identifier;
@synthesize name = _name;
@synthesize kind = _kind;
@synthesize title = _title;
@synthesize permissionsHeading = _permissionsHeading;
@synthesize permissions = _permissions;
@synthesize permissionDetails = _permissionDetails;
@synthesize icon = _icon;
@synthesize webContents = _webContents;
- (instancetype)initPrivate {
  return [super init];
}
@end

// MARK: - Observers

@interface RoomProfileExtensions ()
- (void)room_extensionsChanged;
- (void)room_actionUpdated:(extensions::ExtensionAction*)action
               webContents:(content::WebContents*)webContents;
@end

namespace {

class ExtensionsObserver : public extensions::ExtensionRegistryObserver,
                           public extensions::ExtensionActionDispatcher::Observer,
                           public ToolbarActionsModel::Observer {
 public:
  ExtensionsObserver(Profile* profile, RoomProfileExtensions* owner)
      : owner_(owner) {
    registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile));
    if (auto* dispatcher = extensions::ExtensionActionDispatcher::Get(profile)) {
      dispatcher_ = dispatcher;
      dispatcher->AddObserver(this);
    }
    if (auto* model = ToolbarActionsModel::Get(profile)) {
      model_observation_.Observe(model);
    }
  }

  ~ExtensionsObserver() override {
    if (dispatcher_) {
      dispatcher_->RemoveObserver(this);
    }
  }

  // ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext*,
                         const extensions::Extension*) override {
    [owner_ room_extensionsChanged];
  }
  void OnExtensionUnloaded(content::BrowserContext*,
                           const extensions::Extension*,
                           extensions::UnloadedExtensionReason) override {
    [owner_ room_extensionsChanged];
  }
  void OnExtensionInstalled(content::BrowserContext*,
                            const extensions::Extension* extension,
                            bool is_update) override {
    LOG(INFO) << "RoomCore: extension " << extension->id() << " ("
              << extension->name() << " " << extension->VersionString()
              << ") " << (is_update ? "updated" : "installed");
    [owner_ room_extensionsChanged];
  }
  void OnExtensionUninstalled(content::BrowserContext*,
                              const extensions::Extension* extension,
                              extensions::UninstallReason) override {
    LOG(INFO) << "RoomCore: extension " << extension->id() << " uninstalled";
    [owner_ room_extensionsChanged];
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_observation_.Reset();
  }

  // ExtensionActionDispatcher::Observer:
  void OnExtensionActionUpdated(extensions::ExtensionAction* action,
                                content::WebContents* web_contents,
                                content::BrowserContext*) override {
    [owner_ room_actionUpdated:action webContents:web_contents];
  }
  void OnShuttingDown() override {
    if (dispatcher_) {
      dispatcher_->RemoveObserver(this);
      dispatcher_ = nullptr;
    }
  }

  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId&) override {}
  void OnToolbarActionRemoved(const ToolbarActionsModel::ActionId&) override {}
  void OnToolbarActionUpdated(const ToolbarActionsModel::ActionId&) override {}
  void OnToolbarModelInitialized() override { [owner_ room_extensionsChanged]; }
  void OnToolbarPinnedActionsChanged() override {
    [owner_ room_extensionsChanged];
  }
  void OnToolbarActionsModelShutdown() override { model_observation_.Reset(); }

 private:
  __weak RoomProfileExtensions* owner_;
  raw_ptr<extensions::ExtensionActionDispatcher> dispatcher_ = nullptr;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  base::ScopedObservation<ToolbarActionsModel, ToolbarActionsModel::Observer>
      model_observation_{this};
};

// Side panels are not supported in v1 (ROADMAP Chapter 3; 3.6b task 5):
// a Room Browser has no SidePanelUI, and Chrome's sidePanel.open() reaches
// SidePanelUI::Show through OpenGlobalExtensionSidePanel without a null
// check (3.6b: the browser process crashed on the fixture's open()). Without
// a patch: every extension's panel options stay disabled in SidePanelService
// (its own seam, the source of truth the API and the action consult), so
// sidePanel.open() rejects ("No active side panel for tabId: N"),
// setOptions({enabled: true}) is undone at once, getOptions() reports
// enabled false, and an openPanelOnActionClick action shows its popup or
// sends onClicked instead.
class SidePanelGuard : public extensions::SidePanelService::Observer,
                       public extensions::ExtensionRegistryObserver {
 public:
  explicit SidePanelGuard(Profile* profile) : profile_(profile) {
    service_ = extensions::SidePanelService::Get(profile);
    if (service_) {
      service_->AddObserver(this);
    }
    registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile));
    for (const auto& extension :
         extensions::ExtensionRegistry::Get(profile)->enabled_extensions()) {
      Disable(*extension, std::nullopt);
    }
  }

  ~SidePanelGuard() override {
    if (service_) {
      service_->RemoveObserver(this);
    }
  }

  // ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext*,
                         const extensions::Extension* extension) override {
    Disable(*extension, std::nullopt);
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_observation_.Reset();
  }

  // SidePanelService::Observer: an extension enabled a panel (setOptions):
  // disabled again before the call returns (an update of the same entry).
  void OnPanelOptionsChanged(
      const extensions::ExtensionId& extension_id,
      const extensions::api::side_panel::PanelOptions& options) override {
    if (!options.enabled.value_or(true)) {
      return;
    }
    const extensions::Extension* extension =
        extensions::ExtensionRegistry::Get(profile_)
            ->enabled_extensions()
            .GetByID(extension_id);
    if (extension) {
      LOG(INFO) << "RoomCore: side panel options of " << extension_id
                << " enabled by the extension; side panels are not "
                   "supported, disabled again";
      Disable(*extension, options.tab_id);
    }
  }
  void OnSidePanelServiceShutdown() override {
    if (service_) {
      service_->RemoveObserver(this);
      service_ = nullptr;
    }
  }

 private:
  void Disable(const extensions::Extension& extension,
               std::optional<int> tab_id) {
    if (!service_) {
      return;
    }
    extensions::api::side_panel::PanelOptions options;
    options.enabled = false;
    options.tab_id = tab_id;
    service_->SetOptions(extension, std::move(options));
  }

  raw_ptr<Profile> profile_;
  raw_ptr<extensions::SidePanelService> service_ = nullptr;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
};

}  // namespace

// MARK: - RoomProfileExtensions

@implementation RoomProfileExtensions {
  raw_ptr<Profile> _profile;
  std::unique_ptr<ExtensionsObserver> _observer;
  std::unique_ptr<SidePanelGuard> _sidePanelGuard;
  __weak id<RoomProfileExtensionsDelegate> _delegate;
  // Icons loaded through ImageLoader, by extension id; an entry (NSNull)
  // marks a load in flight or an extension without that icon.
  NSMutableDictionary<NSString*, id>* _icons16;
  NSMutableDictionary<NSString*, id>* _icons32;
  NSMutableDictionary<NSString*, id>* _actionIcons;
  BOOL _changePosted;
  BOOL _readyObserved;
}

+ (NSURL*)managementPageURL {
  return [NSURL URLWithString:@"chrome://extensions/"];
}

- (instancetype)initWithChromeProfile:(Profile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    _icons16 = [NSMutableDictionary dictionary];
    _icons32 = [NSMutableDictionary dictionary];
    _actionIcons = [NSMutableDictionary dictionary];
    _observer = std::make_unique<ExtensionsObserver>(profile, self);
    _sidePanelGuard = std::make_unique<SidePanelGuard>(profile);
    __weak RoomProfileExtensions* weakSelf = self;
    extensions::ExtensionSystem::Get(profile)->ready().Post(
        FROM_HERE, base::BindOnce(^{
          RoomProfileExtensions* strongSelf = weakSelf;
          if (strongSelf) {
            strongSelf->_readyObserved = YES;
            [strongSelf room_extensionsChanged];
          }
        }));
  }
  return self;
}

- (void)room_profileWillBeDestroyed {
  _sidePanelGuard.reset();
  _observer.reset();
  _profile = nullptr;
}

- (id<RoomProfileExtensionsDelegate>)delegate {
  return _delegate;
}

- (void)setDelegate:(id<RoomProfileExtensionsDelegate>)delegate {
  _delegate = delegate;
}

- (BOOL)isReady {
  return _profile && extensions::ExtensionSystem::Get(_profile)->is_ready();
}

- (const extensions::Extension*)room_extension:(NSString*)identifier {
  if (!_profile || !identifier) {
    return nullptr;
  }
  return extensions::ExtensionRegistry::Get(_profile)->GetExtensionById(
      base::SysNSStringToUTF8(identifier),
      extensions::ExtensionRegistry::EVERYTHING);
}

// Coalesces a burst of registry and model events into one delegate call.
- (void)room_extensionsChanged {
  if (_changePosted) {
    return;
  }
  _changePosted = YES;
  __weak RoomProfileExtensions* weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    RoomProfileExtensions* strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf->_changePosted = NO;
    id<RoomProfileExtensionsDelegate> delegate = strongSelf->_delegate;
    if ([delegate respondsToSelector:@selector(profileExtensionsDidChange:)]) {
      [delegate profileExtensionsDidChange:strongSelf];
    }
  });
}

- (void)room_actionUpdated:(extensions::ExtensionAction*)action
               webContents:(content::WebContents*)webContents {
  if (!action) {
    return;
  }
  id<RoomProfileExtensionsDelegate> delegate = _delegate;
  if ([delegate respondsToSelector:@selector
                (profileExtensions:didUpdateActionOfExtension:webContents:)]) {
    RoomWebContents* page =
        webContents ? [RoomWebContents room_existingWrapperFor:webContents]
                    : nil;
    [delegate profileExtensions:self
        didUpdateActionOfExtension:ToNS(action->extension_id())
                       webContents:page];
  }
  // The defaults changed: the list's action snapshot too.
  if (!webContents) {
    [self room_extensionsChanged];
  }
}

// MARK: Icons

// Loads `resources` (1x, 2x) into `cache[identifier]`, then reports a change.
- (void)room_loadIcon:(const extensions::Extension*)extension
            iconSet:(const ExtensionIconSet&)iconSet
             points:(int)points
              cache:(NSMutableDictionary<NSString*, id>*)cache {
  NSString* identifier = ToNS(extension->id());
  if (cache[identifier]) {
    return;
  }
  cache[identifier] = [NSNull null];
  std::vector<extensions::ImageLoader::ImageRepresentation> reps;
  for (int scale = 1; scale <= 2; ++scale) {
    const int pixels = points * scale;
    const std::string& path =
        iconSet.Get(pixels, ExtensionIconSet::Match::kBigger);
    const std::string& fallback =
        path.empty() ? iconSet.Get(pixels, ExtensionIconSet::Match::kSmaller)
                     : path;
    if (fallback.empty()) {
      continue;
    }
    reps.emplace_back(
        extension->GetResource(fallback),
        extensions::ImageLoader::ImageRepresentation::ALWAYS_RESIZE,
        gfx::Size(pixels, pixels), static_cast<float>(scale));
  }
  if (reps.empty() || !_profile) {
    return;
  }
  __weak RoomProfileExtensions* weakSelf = self;
  extensions::ImageLoader::Get(_profile)->LoadImagesAsync(
      extension, reps, base::BindOnce(^(const gfx::Image& image) {
        RoomProfileExtensions* strongSelf = weakSelf;
        if (!strongSelf || image.IsEmpty()) {
          return;
        }
        NSImage* nsImage = image.ToNSImage();
        nsImage.size = NSMakeSize(points, points);
        cache[identifier] = nsImage;
        [strongSelf room_extensionsChanged];
      }));
}

- (NSImage*)room_cachedIcon:(NSMutableDictionary<NSString*, id>*)cache
                 identifier:(NSString*)identifier {
  id value = cache[identifier];
  return [value isKindOfClass:[NSImage class]] ? value : nil;
}

- (NSImage*)room_defaultActionIcon:(const extensions::Extension*)extension
                            action:(const extensions::ExtensionAction&)action {
  const ExtensionIconSet* actionIcons = action.default_icon();
  if (actionIcons && !actionIcons->empty()) {
    [self room_loadIcon:extension
                iconSet:*actionIcons
                 points:16
                  cache:_actionIcons];
    return [self room_cachedIcon:_actionIcons identifier:ToNS(extension->id())];
  }
  // Chrome shows the extension's own icon for an action without one.
  return [self room_cachedIcon:_icons16 identifier:ToNS(extension->id())];
}

// MARK: The list

- (RoomExtension*)room_snapshot:(const extensions::Extension*)extension
                        enabled:(BOOL)enabled
                          model:(ToolbarActionsModel*)model {
  RoomExtension* item = [[RoomExtension alloc] initPrivate];
  NSString* identifier = ToNS(extension->id());
  item.identifier = identifier;
  item.name = ToNS(extension->name());
  item.version = ToNS(extension->VersionString());
  const std::string* description =
      extension->manifest()->FindStringPath("description");
  item.summary = description ? ToNS(*description) : @"";
  const ExtensionIconSet& icons = extensions::IconsInfo::GetIcons(extension);
  [self room_loadIcon:extension iconSet:icons points:16 cache:_icons16];
  [self room_loadIcon:extension iconSet:icons points:32 cache:_icons32];
  item.icon16 = [self room_cachedIcon:_icons16 identifier:identifier];
  item.icon32 = [self room_cachedIcon:_icons32 identifier:identifier];
  item.enabled = enabled;
  item.unpacked =
      extensions::Manifest::IsUnpackedLocation(extension->location());
  item.fromWebStore = extension->from_webstore();
  if (_profile) {
    if (const extensions::ExtensionAction* action =
            extensions::ExtensionActionManager::Get(_profile)
                ->GetExtensionAction(*extension)) {
      item.action = [[RoomExtensionAction alloc]
          initWithAction:*action
                   tabID:extensions::ExtensionAction::kDefaultTabId
             defaultIcon:[self room_defaultActionIcon:extension
                                               action:*action]];
    }
  }
  item.pinned = model && model->actions_initialized() &&
                model->IsActionPinned(extension->id());
  if (extensions::OptionsPageInfo::HasOptionsPage(extension)) {
    item.optionsPageURL = net::NSURLWithGURL(
        extensions::OptionsPageInfo::GetOptionsPage(extension));
  }
  NSMutableArray<NSString*>* messages = [NSMutableArray array];
  for (const extensions::PermissionMessage& message :
       extension->permissions_data()->GetPermissionMessages()) {
    [messages addObject:ToNS(message.message())];
  }
  item.permissionMessages = messages;
  NSMutableArray<NSString*>* hosts = [NSMutableArray array];
  if (extension->permissions_data()
          ->active_permissions()
          .HasEffectiveAccessToAllHosts()) {
    [hosts addObject:@"<all_urls>"];
  } else {
    for (const URLPattern& pattern :
         extension->permissions_data()->GetEffectiveHostPermissions()) {
      [hosts addObject:ToNS(pattern.GetAsString())];
    }
  }
  item.hostPermissions = hosts;
  if (!extension->path().empty()) {
    item.directory = [NSURL
        fileURLWithPath:base::SysUTF8ToNSString(extension->path().value())
            isDirectory:YES];
  }
  return item;
}

- (NSArray<RoomExtension*>*)extensions {
  if (!_profile) {
    return @[];
  }
  auto* registry = extensions::ExtensionRegistry::Get(_profile);
  ToolbarActionsModel* model = ToolbarActionsModel::Get(_profile);
  NSMutableArray<RoomExtension*>* pinned = [NSMutableArray array];
  NSMutableArray<RoomExtension*>* others = [NSMutableArray array];
  auto add = [&](const extensions::ExtensionSet& set, BOOL enabled) {
    for (const auto& extension : set) {
      if (!IsListed(*extension)) {
        continue;
      }
      RoomExtension* item = [self room_snapshot:extension.get()
                                        enabled:enabled
                                          model:model];
      [(item.pinned ? pinned : others) addObject:item];
    }
  };
  add(registry->enabled_extensions(), YES);
  add(registry->disabled_extensions(), NO);
  add(registry->terminated_extensions(), YES);
  add(registry->blocklisted_extensions(), NO);
  if (model && model->actions_initialized()) {
    const std::vector<ToolbarActionsModel::ActionId>& order =
        model->pinned_action_ids();
    [pinned sortUsingComparator:^NSComparisonResult(RoomExtension* a,
                                                    RoomExtension* b) {
      auto index = [&](RoomExtension* e) {
        auto it = std::find(order.begin(), order.end(),
                            base::SysNSStringToUTF8(e.identifier));
        return it - order.begin();
      };
      auto ia = index(a), ib = index(b);
      return ia < ib ? NSOrderedAscending
                     : (ia > ib ? NSOrderedDescending : NSOrderedSame);
    }];
  }
  [others sortUsingComparator:^NSComparisonResult(RoomExtension* a,
                                                  RoomExtension* b) {
    return [a.name localizedCaseInsensitiveCompare:b.name];
  }];
  return [pinned arrayByAddingObjectsFromArray:others];
}

// MARK: Management

- (void)setEnabled:(BOOL)enabled forExtension:(NSString*)identifier {
  if (![self room_extension:identifier]) {
    return;
  }
  auto* registrar = extensions::ExtensionRegistrar::Get(_profile);
  const std::string id = base::SysNSStringToUTF8(identifier);
  if (enabled) {
    registrar->EnableExtension(id);
  } else {
    registrar->DisableExtension(
        id, {extensions::disable_reason::DISABLE_USER_ACTION});
  }
}

- (void)reloadExtension:(NSString*)identifier {
  if (![self room_extension:identifier]) {
    return;
  }
  extensions::ExtensionRegistrar::Get(_profile)->ReloadExtension(
      base::SysNSStringToUTF8(identifier));
}

- (void)uninstallExtension:(NSString*)identifier
                completion:(void (^)(BOOL))completion {
  void (^done)(BOOL) = completion;
  if (!done) {
    done = ^(BOOL) {
    };
  }
  const extensions::Extension* extension = [self room_extension:identifier];
  id<RoomProfileExtensionsDelegate> delegate = _delegate;
  if (!extension ||
      ![delegate respondsToSelector:@selector(profileExtensions:
                                         willUninstallExtension:completion:)]) {
    // No consent can be asked: nothing is removed.
    done(NO);
    return;
  }
  RoomExtension* snapshot =
      [self room_snapshot:extension
                  enabled:extensions::ExtensionRegistry::Get(_profile)
                              ->enabled_extensions()
                              .Contains(extension->id())
                    model:ToolbarActionsModel::Get(_profile)];
  __weak RoomProfileExtensions* weakSelf = self;
  __block BOOL answered = NO;
  [delegate profileExtensions:self
       willUninstallExtension:snapshot
                   completion:^(BOOL consent) {
                     if (answered) {
                       return;
                     }
                     answered = YES;
                     RoomProfileExtensions* strongSelf = weakSelf;
                     if (!consent || !strongSelf ||
                         ![strongSelf room_extension:identifier]) {
                       done(NO);
                       return;
                     }
                     std::u16string error;
                     const bool started =
                         extensions::ExtensionRegistrar::Get(
                             strongSelf->_profile)
                             ->UninstallExtension(
                                 base::SysNSStringToUTF8(identifier),
                                 extensions::UNINSTALL_REASON_USER_INITIATED,
                                 &error, base::BindOnce(^{
                                   done(YES);
                                 }));
                     if (!started) {
                       LOG(WARNING) << "RoomCore: uninstall refused: " << error;
                       done(NO);
                     }
                   }];
}

- (void)loadUnpackedAtURL:(NSURL*)directory
               completion:(void (^)(NSString*, NSString*))completion {
  void (^done)(NSString*, NSString*) = [completion copy];
  if (!_profile || !directory.isFileURL) {
    done(nil, @"Not a folder");
    return;
  }
  // Loading a folder is developer mode (chrome://extensions shows it on, and
  // Chrome keeps unpacked extensions enabled only with it on).
  _profile->GetPrefs()->SetBoolean(prefs::kExtensionsUIDeveloperMode, true);
  scoped_refptr<extensions::UnpackedInstaller> installer =
      extensions::UnpackedInstaller::Create(_profile);
  installer->set_be_noisy_on_failure(false);
  installer->set_completion_callback(base::BindOnce(
      ^(const extensions::Extension* extension, const base::FilePath&,
        const std::u16string& error) {
        if (extension) {
          done(ToNS(extension->id()), nil);
        } else {
          done(nil, ToNS(error));
        }
      }));
  installer->Load(base::FilePath(base::SysNSStringToUTF8(directory.path)));
}

- (NSURL*)optionsPageURLForExtension:(NSString*)identifier {
  const extensions::Extension* extension = [self room_extension:identifier];
  if (!extension || !extensions::OptionsPageInfo::HasOptionsPage(extension)) {
    return nil;
  }
  return net::NSURLWithGURL(
      extensions::OptionsPageInfo::GetOptionsPage(extension));
}

- (void)setPinned:(BOOL)pinned forExtension:(NSString*)identifier {
  if (![self room_extension:identifier]) {
    return;
  }
  ToolbarActionsModel* model = ToolbarActionsModel::Get(_profile);
  const std::string id = base::SysNSStringToUTF8(identifier);
  // SetActionVisibility DCHECKs a change; asking for the current state is a
  // no-op here.
  if (model && model->actions_initialized() && model->HasAction(id) &&
      model->IsActionPinned(id) != static_cast<bool>(pinned)) {
    model->SetActionVisibility(id, pinned);
  }
}

- (void)setAllowedInIncognito:(BOOL)allowed
                 forExtension:(NSString*)identifier {
  if (![self room_extension:identifier] ||
      static_cast<bool>(allowed) == [self isAllowedInIncognito:identifier]) {
    return;
  }
  // Reloads the extension when it is enabled: Chrome applies the bit at load.
  extensions::util::SetIsIncognitoEnabled(base::SysNSStringToUTF8(identifier),
                                          _profile, allowed);
}

- (BOOL)isAllowedInIncognito:(NSString*)identifier {
  return [self room_extension:identifier] &&
         extensions::util::IsIncognitoEnabled(
             base::SysNSStringToUTF8(identifier), _profile);
}

- (RoomExtensionAction*)actionForExtension:(NSString*)identifier
                               webContents:(RoomWebContents*)webContents {
  const extensions::Extension* extension = [self room_extension:identifier];
  if (!extension) {
    return nil;
  }
  const extensions::ExtensionAction* action =
      extensions::ExtensionActionManager::Get(_profile)->GetExtensionAction(
          *extension);
  if (!action) {
    return nil;
  }
  content::WebContents* contents =
      webContents ? webContents.room_webContents : nullptr;
  const int tabID = contents ? extensions::ExtensionTabUtil::GetTabId(contents)
                             : extensions::ExtensionAction::kDefaultTabId;
  return [[RoomExtensionAction alloc]
      initWithAction:*action
               tabID:tabID
         defaultIcon:[self room_defaultActionIcon:extension action:*action]];
}

// MARK: Popups (3.6b)

- (BOOL)openPopupForExtension:(NSString*)identifier
                  webContents:(RoomWebContents*)webContents {
  content::WebContents* contents = webContents.room_webContents;
  room::RoomBrowserExtensions* window = webContents.room_browser.room_extensions;
  if (!_profile || !identifier || !contents || !window) {
    LOG(WARNING) << "RoomCore: no popup: the page is not in a Room window";
    return NO;
  }
  return window->RunActionFromHost(base::SysNSStringToUTF8(identifier),
                                   contents);
}

- (void)closePopup:(RoomWebContents*)popup {
  content::WebContents* contents = popup.room_webContents;
  if (room::RoomBrowserExtensions* window =
          contents ? room::BrowserExtensionsForPopup(contents) : nullptr) {
    window->ClosePopup(contents);
  }
}

- (void)room_popupDidOpen:(RoomWebContents*)popup
                extension:(NSString*)identifier
              webContents:(RoomWebContents*)webContents
                     size:(NSSize)size {
  id<RoomProfileExtensionsDelegate> delegate = _delegate;
  if ([delegate respondsToSelector:@selector
                (profileExtensions:didOpenPopup:forExtension:webContents:preferredSize:)]) {
    [delegate profileExtensions:self
                   didOpenPopup:popup
                   forExtension:identifier
                    webContents:webContents
                  preferredSize:size];
  }
}

- (void)room_popup:(RoomWebContents*)popup didResize:(NSSize)size {
  id<RoomProfileExtensionsDelegate> delegate = _delegate;
  if ([delegate respondsToSelector:@selector(profileExtensions:popup:didResizeToSize:)]) {
    [delegate profileExtensions:self popup:popup didResizeToSize:size];
  }
}

- (void)room_popupDidClose:(RoomWebContents*)popup {
  id<RoomProfileExtensionsDelegate> delegate = _delegate;
  if ([delegate respondsToSelector:@selector(profileExtensions:popupDidClose:)]) {
    [delegate profileExtensions:self popupDidClose:popup];
  }
}

// MARK: Site access and commands (4.5)

- (const extensions::Extension*)room_enabledExtension:(NSString*)identifier {
  if (!_profile || !identifier) {
    return nullptr;
  }
  return extensions::ExtensionRegistry::Get(_profile)
      ->enabled_extensions()
      .GetByID(base::SysNSStringToUTF8(identifier));
}

- (NSDictionary<NSString*, id>*)siteAccessForExtension:(NSString*)identifier
                                           webContents:
                                               (RoomWebContents*)webContents {
  const extensions::Extension* extension =
      [self room_enabledExtension:identifier];
  content::WebContents* contents = webContents.room_webContents;
  if (!extension || !contents) {
    return nil;
  }
  const GURL url = contents->GetLastCommittedURL();
  if (!url.is_valid() || url.is_empty()) {
    return nil;
  }
  auto* manager = extensions::PermissionsManager::Get(_profile);
  const bool restricted =
      extension->permissions_data()->IsRestrictedUrl(url, /*error=*/nullptr);
  const extensions::PermissionsManager::ExtensionSiteAccess site =
      restricted ? extensions::PermissionsManager::ExtensionSiteAccess()
                 : manager->GetSiteAccess(*extension, url);
  const bool wants_site =
      !restricted && (site.has_site_access || site.withheld_site_access ||
                      manager->HasActiveTabAndCanAccess(*extension, url));
  NSMutableArray<NSNumber*>* selectable = [NSMutableArray array];
  if (!restricted) {
    for (UserSiteAccess access :
         {UserSiteAccess::kOnClick, UserSiteAccess::kOnSite,
          UserSiteAccess::kOnAllSites}) {
      if (manager->CanUserSelectSiteAccess(*extension, url, access)) {
        [selectable addObject:@(ToLevel(access))];
      }
    }
  }
  const UserSiteAccess level = restricted
                                   ? UserSiteAccess::kOnClick
                                   : manager->GetUserSiteAccess(*extension, url);
  extensions::ExtensionActionRunner* runner =
      extensions::ExtensionActionRunner::GetForWebContents(contents);
  return @{
    @"level" : @(ToLevel(level)),
    @"selectable" : selectable,
    @"wantsSite" : @(wants_site),
    @"canAffect" : @(!restricted && manager->CanAffectExtension(*extension)),
    @"wantsToRun" : @(runner && runner->WantsToRun(extension)),
  };
}

- (BOOL)setSiteAccess:(RoomExtensionSiteAccessLevel)level
         forExtension:(NSString*)identifier
                 host:(NSString*)host {
  const extensions::Extension* extension =
      [self room_enabledExtension:identifier];
  const std::string host_name = base::SysNSStringToUTF8(host ?: @"");
  if (!extension || host_name.empty()) {
    return NO;
  }
  auto* manager = extensions::PermissionsManager::Get(_profile);
  const UserSiteAccess access = FromLevel(level);
  // The host's pages may be http or https: the first scheme on which the
  // extension can take `access` answers for the host (the grant below covers
  // both, as "*://host/*").
  GURL url;
  for (const char* scheme : {"https", "http"}) {
    GURL candidate(std::string(scheme) + "://" + host_name + "/");
    if (candidate.is_valid() &&
        manager->CanUserSelectSiteAccess(*extension, candidate, access)) {
      url = candidate;
      break;
    }
  }
  if (url.is_empty()) {
    LOG(INFO) << "RoomCore: site access " << static_cast<int>(access)
              << " not selectable for " << extension->id() << " on "
              << host_name;
    return NO;
  }
  const UserSiteAccess current = manager->GetUserSiteAccess(*extension, url);
  if (current == access) {
    return YES;
  }
  // UpdateSiteAccess CHECKs this ("on click" is selectable for an activeTab
  // extension that runtime host permissions do not affect).
  if (!manager->CanAffectExtension(*extension)) {
    return NO;
  }
  // As SitePermissionsHelper::UpdateSiteAccess (Chrome's site-access menu),
  // with the host's pattern in place of one page's origin.
  if (current == UserSiteAccess::kOnAllSites) {
    manager->AddExtensionToPreviousBroadSiteAccessSet(extension->id());
  } else {
    manager->RemoveExtensionFromPreviousBroadSiteAccessSet(extension->id());
  }
  extensions::ScriptingPermissionsModifier modifier(_profile, extension);
  const GURL urls[] = {GURL("https://" + host_name + "/"),
                       GURL("http://" + host_name + "/")};
  switch (access) {
    case UserSiteAccess::kOnClick:
    case UserSiteAccess::kOnSite: {
      if (manager->HasBroadGrantedHostPermissions(*extension)) {
        modifier.RemoveBroadGrantedHostPermissions();
      }
      modifier.SetWithholdHostPermissions(true);
      if (access == UserSiteAccess::kOnClick) {
        for (const GURL& each : urls) {
          if (manager->HasGrantedHostPermission(*extension, each)) {
            modifier.RemoveGrantedHostPermission(each);
          }
        }
      } else if (!manager->HasGrantedHostPermission(*extension, url)) {
        URLPattern pattern(extensions::UserScript::ValidUserScriptSchemes());
        if (pattern.Parse("*://" + host_name + "/*") !=
            URLPattern::ParseResult::kSuccess) {
          return NO;
        }
        modifier.GrantHostPermission(pattern, base::DoNothing());
      }
      break;
    }
    case UserSiteAccess::kOnAllSites:
      modifier.SetWithholdHostPermissions(false);
      break;
  }
  // The host's open pages: "on click" takes the tab grant back (Chrome then
  // asks for a reload, here the page keeps what already ran); a grant runs
  // what was blocked when it needs no reload (ChromeExtensionsBrowserClient::
  // RunBlockActionsIfNeeded).
  extensions::SitePermissionsHelper helper(_profile);
  for (content::WebContents* contents : PagesOfHost(_profile, host_name)) {
    if (access == UserSiteAccess::kOnClick) {
      if (auto* granter =
              extensions::ActiveTabPermissionGranter::FromWebContents(
                  contents)) {
        granter->ClearActiveExtensionAndNotify(extension->id());
      }
      continue;
    }
    auto* runner = extensions::ExtensionActionRunner::GetForWebContents(contents);
    const int blocked = runner ? runner->GetBlockedActions(extension->id())
                               : extensions::BLOCKED_ACTION_NONE;
    if (blocked != extensions::BLOCKED_ACTION_NONE &&
        !helper.PageNeedsRefreshToRun(blocked)) {
      runner->RunBlockedActions(extension);
    }
  }
  LOG(INFO) << "RoomCore: site access of " << extension->id() << " on "
            << host_name << ": " << static_cast<int>(current) << " -> "
            << static_cast<int>(access);
  return YES;
}

- (BOOL)runActionForExtension:(NSString*)identifier
                  webContents:(RoomWebContents*)webContents {
  const extensions::Extension* extension =
      [self room_enabledExtension:identifier];
  content::WebContents* contents = webContents.room_webContents;
  extensions::ExtensionActionRunner* runner =
      contents ? extensions::ExtensionActionRunner::GetForWebContents(contents)
               : nullptr;
  if (!extension || !runner || !runner->WantsToRun(extension)) {
    return NO;
  }
  // With blocked actions RunAction grants the tab and runs them, and shows
  // no popup (ExtensionActionRunner::RunAction's first branch).
  runner->RunAction(extension, /*grant_tab_permissions=*/true);
  LOG(INFO) << "RoomCore: Run for " << extension->id() << " from the host";
  return YES;
}

- (NSArray<NSDictionary<NSString*, id>*>*)commandsForExtension:
    (NSString*)identifier {
  const extensions::Extension* extension = [self room_extension:identifier];
  if (!extension) {
    return @[];
  }
  auto* service = extensions::CommandService::Get(_profile);
  NSMutableArray<NSDictionary<NSString*, id>*>* commands =
      [NSMutableArray array];
  auto add = [&](const ui::Command& command, bool is_action) {
    [commands addObject:@{
      @"name" : ToNS(command.command_name()),
      @"description" : ToNS(command.description()),
      @"shortcut" :
          ToNS(ui::Command::AcceleratorToString(command.accelerator())),
      @"isAction" : @(is_action),
    }];
  };
  extensions::Command action;
  if (service->GetExtensionActionCommand(
          extension->id(), extensions::ActionInfo::Type::kAction,
          extensions::CommandService::ACTIVE, &action, /*active=*/nullptr)) {
    add(action, true);
  }
  ui::CommandMap named;
  service->GetNamedCommands(extension->id(),
                            extensions::CommandService::ACTIVE,
                            extensions::CommandService::ANY_SCOPE, &named);
  for (const auto& [name, command] : named) {
    add(command, false);
  }
  return commands;
}

- (BOOL)performCommand:(NSString*)name
          forExtension:(NSString*)identifier
           webContents:(RoomWebContents*)webContents {
  if (!_profile || !name || !identifier) {
    return NO;
  }
  content::WebContents* contents =
      webContents ? webContents.room_webContents : nullptr;
  room::RoomBrowserExtensions* window =
      webContents ? webContents.room_browser.room_extensions : nullptr;
  if (!window) {
    window = room::BrowserExtensionsForProfile(_profile);
    contents = nullptr;
  }
  if (!window) {
    LOG(WARNING) << "RoomCore: no window for the command "
                 << base::SysNSStringToUTF8(name);
    return NO;
  }
  return window->RunCommand(base::SysNSStringToUTF8(identifier),
                            base::SysNSStringToUTF8(name), contents);
}

// MARK: Updates

- (void)checkForUpdatesWithCompletion:
    (void (^)(RoomExtensionUpdateCheckResult))completion {
  void (^done)(RoomExtensionUpdateCheckResult) = [completion copy];
  RoomExtensionUpdateCheckResult result = {NO, 0, 0};
  extensions::ExtensionUpdater* updater =
      _profile ? extensions::ExtensionUpdater::Get(_profile) : nullptr;
  if (!updater || !updater->enabled() || !self.ready) {
    done(result);
    return;
  }
  for (const auto& extension :
       extensions::ExtensionRegistry::Get(_profile)
           ->GenerateInstalledExtensionsSet()) {
    if (IsListed(*extension) &&
        !extensions::Manifest::IsUnpackedLocation(extension->location())) {
      ++result.extensions;
    }
  }
  if (result.extensions == 0) {
    done(result);
    return;
  }
  result.checked = YES;
  auto found = std::make_shared<NSInteger>(0);
  extensions::ExtensionUpdater::CheckParams params;
  params.fetch_priority = extensions::DownloadFetchPriority::kForeground;
  params.update_found_callback = base::BindRepeating(
      [](std::shared_ptr<NSInteger> found, const std::string& id,
         const base::Version& version) {
        ++*found;
        LOG(INFO) << "RoomCore: extension update found: " << id << " "
                  << version.GetString();
      },
      found);
  params.callback = base::BindOnce(^{
    RoomExtensionUpdateCheckResult finished = result;
    finished.updatesFound = *found;
    LOG(INFO) << "RoomCore: extension update check done: "
              << finished.extensions << " asked, " << finished.updatesFound
              << " found";
    done(finished);
  });
  LOG(INFO) << "RoomCore: extension update check (the host's) for "
            << result.extensions << " extensions";
  base::AutoReset<bool> allow(&g_host_update_check, true);
  updater->CheckNow(std::move(params));
}

@end

// MARK: - Hooks

namespace room {
namespace {

RoomExtensionInstallKind KindFor(extensions::InstallPromptData::PromptType type) {
  switch (type) {
    case extensions::InstallPromptData::INSTALL_PROMPT:
    case extensions::InstallPromptData::EXTERNAL_INSTALL_PROMPT:
    case extensions::InstallPromptData::REMOTE_INSTALL_PROMPT:
    case extensions::InstallPromptData::REPAIR_PROMPT:
      return RoomExtensionInstallKindInstall;
    case extensions::InstallPromptData::RE_ENABLE_PROMPT:
    case extensions::InstallPromptData::PERMISSIONS_PROMPT:
      return RoomExtensionInstallKindPermissions;
    default:
      return RoomExtensionInstallKindOther;
  }
}

// The extension update client's configuration without a ping URL:
// update_client then sends no event pings (the uninstall ping Chrome sends
// for every Web Store extension removed, the "update applied" pings after a
// check). Telemetry, not a request the user asked for: 3.6a's install
// net-log showed one update_client POST per uninstall.
class RoomUpdateClientConfig : public extensions::ChromeUpdateClientConfig {
 public:
  explicit RoomUpdateClientConfig(content::BrowserContext* context)
      : ChromeUpdateClientConfig(context, std::nullopt) {}

  std::vector<GURL> PingUrl() const override { return {}; }

  // ChromeUpdateClientConfig::Create asks this factory (a protected setter
  // named for tests upstream, no test behaviour). Room never overrides the
  // Web Store's update URL, so the URL override Create would pass is empty.
  static void Install() {
    SetChromeUpdateClientConfigFactoryForTesting(base::BindRepeating(
        [](content::BrowserContext* context)
            -> scoped_refptr<extensions::ChromeUpdateClientConfig> {
          return base::MakeRefCounted<RoomUpdateClientConfig>(context);
        }));
  }

 protected:
  ~RoomUpdateClientConfig() override = default;
};

bool ShowInstallDialog(
    std::unique_ptr<ExtensionInstallPromptShowParams>& show_params,
    ExtensionInstallPrompt::DoneCallback& done_callback,
    std::unique_ptr<extensions::InstallPromptData>& prompt) {
  if (!show_params || !prompt || !prompt->extension()) {
    return false;
  }
  const RoomExtensionInstallKind kind = KindFor(prompt->type());
  if (kind == RoomExtensionInstallKindOther) {
    return false;  // enterprise requests, parent approval: Chrome's
  }
  Profile* profile = show_params->profile();
  RoomProfile* wrapper =
      profile ? [RoomProfile room_existingProfileFor:profile->GetOriginalProfile()]
              : nil;
  RoomProfileExtensions* extensions = wrapper.room_existingExtensions;
  id<RoomProfileExtensionsDelegate> delegate = extensions.delegate;
  if (![delegate respondsToSelector:@selector(profileExtensions:
                                         willInstallExtension:completion:)]) {
    return false;
  }
  RoomExtensionInstallRequest* request =
      [[RoomExtensionInstallRequest alloc] initPrivate];
  request.identifier = ToNS(prompt->extension()->id());
  request.name = ToNS(prompt->extension()->name());
  request.kind = kind;
  request.title = ToNS(prompt->GetDialogTitle());
  request.permissionsHeading = ToNS(prompt->GetPermissionsHeading());
  const extensions::InstallPromptPermissions permissions =
      prompt->GetPermissions();
  NSMutableArray<NSString*>* lines = [NSMutableArray array];
  NSMutableArray<NSArray<NSString*>*>* details = [NSMutableArray array];
  for (size_t i = 0; i < permissions.permissions.size(); ++i) {
    [lines addObject:ToNS(permissions.permissions[i])];
    NSString* detail =
        i < permissions.details.size() ? ToNS(permissions.details[i]) : @"";
    [details addObject:detail.length
                           ? [detail componentsSeparatedByString:@"\n"]
                           : @[]];
  }
  request.permissions = lines;
  request.permissionDetails = details;
  request.icon = ToNSImage(prompt->icon());
  if (content::WebContents* contents = show_params->GetParentWebContents()) {
    request.webContents = [RoomWebContents room_existingWrapperFor:contents];
  }
  LOG(INFO) << "RoomCore: install prompt for " << prompt->extension()->id()
            << " (" << prompt->extension()->name() << ", type "
            << prompt->type() << ", " << permissions.permissions.size()
            << " permissions) goes to the host";
  // The prompt data and show params live until the host answers (the
  // prompt observers and the parent's lifetime are Chrome's).
  auto pending = std::make_shared<ExtensionInstallPrompt::DoneCallback>(
      std::move(done_callback));
  std::shared_ptr<ExtensionInstallPromptShowParams> params(
      std::move(show_params));
  std::shared_ptr<extensions::InstallPromptData> data(std::move(prompt));
  data->OnDialogOpened();
  [delegate profileExtensions:extensions
         willInstallExtension:request
                   completion:^(BOOL consent) {
                     if (!*pending) {
                       return;  // answered already
                     }
                     using Result = ExtensionInstallPrompt::Result;
                     Result result = consent ? Result::ACCEPTED
                                             : Result::USER_CANCELED;
                     if (consent && params->WasParentDestroyed()) {
                       result = Result::ABORTED;
                     }
                     if (consent) {
                       data->OnDialogAccepted();
                     } else {
                       data->OnDialogCanceled();
                     }
                     LOG(INFO) << "RoomCore: install prompt answered "
                               << (consent ? "accept" : "cancel");
                     std::move(*pending).Run(
                         ExtensionInstallPrompt::DoneCallbackPayload(result));
                   }];
  return true;
}

}  // namespace

void InstallExtensionHooks() {
  g_show_extension_install_dialog_hook = &ShowInstallDialog;
  g_extension_update_allowed_hook = +[]() -> bool {
    if (!g_host_update_check) {
      ++g_refused_update_checks;
      LOG(INFO) << "RoomCore: an extension update check the host did not ask "
                   "for was refused ("
                << g_refused_update_checks << " so far)";
    }
    return g_host_update_check;
  };
  // Chrome's post-install dialog anchors its follow-up on a BrowserView's
  // toolbar (ExtensionInstallUIDesktop::OnInstallSuccess), which a Room window
  // does not have; the host announces installs itself. The setter is named
  // for tests upstream but only turns that UI off (no test behaviour).
  static base::NoDestructor<base::AutoReset<bool>> no_post_install_ui(
      ExtensionInstallUI::disable_ui_for_tests(true));
  RoomUpdateClientConfig::Install();
  // Chrome Apps' OS shortcuts: AppShortcutManager deletes "all shortcuts" of
  // every uninstalled extension, which creates ~/Applications/Chromium
  // Apps.localized with its icon (3.6a: made by the first uninstall). Room
  // has no Chrome Apps; the switch (named for tests upstream, no test
  // behaviour) turns the shortcut manager's file work off.
  AppShortcutManager::SuppressShortcutsForTesting();
}

}  // namespace room
