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
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/updater/chrome_update_client_config.h"
#include "chrome/browser/extensions/updater/extension_updater.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/extensions/extension_install_ui.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
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
#include "extensions/browser/install_prompt_permissions.h"
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
#include "net/base/apple/url_conversions.h"
#include "skia/ext/skia_utils_mac.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
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

}  // namespace

// MARK: - RoomProfileExtensions

@implementation RoomProfileExtensions {
  raw_ptr<Profile> _profile;
  std::unique_ptr<ExtensionsObserver> _observer;
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
}

}  // namespace room
