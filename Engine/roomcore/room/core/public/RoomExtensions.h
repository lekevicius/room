// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Chrome extensions for the host (Phase 3.6a): a profile's installed
// extensions (ExtensionRegistry), their actions (ExtensionAction), the
// pinned order (ToolbarActionsModel), management through the host's consent,
// installs from the Chrome Web Store with the host's permission sheet, and
// update checks only when the host asks. Every class is main-thread only;
// every completion and delegate call arrives on the main thread.

#import <AppKit/AppKit.h>

#import "RoomExport.h"

NS_ASSUME_NONNULL_BEGIN

@class RoomProfileExtensions;
@class RoomWebContents;

// An extension's action for one page, or its defaults
// (extensions::ExtensionAction for a tab id).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomExtensionAction : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSString* title;
// GetDisplayBadgeText: the explicit text, else the declarative net
// request count when the extension shows it, else the default; "" for none.
@property(nonatomic, readonly, copy) NSString* badgeText;
// nil when the extension set none (Chrome then uses its own colour).
@property(nonatomic, readonly, copy, nullable) NSColor* badgeBackgroundColor;
@property(nonatomic, readonly, copy, nullable) NSColor* badgeTextColor;
// The icon set for the page (action.setIcon), the declarative one, or the
// action's default icon at 16 pt; nil while it loads.
@property(nonatomic, readonly, nullable) NSImage* icon;
// action.enable/disable (GetIsVisible).
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly) BOOL hasPopup;
@end

// A snapshot of one installed extension; a new array arrives with every
// change (-profileExtensionsDidChange:).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomExtension : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* version;
@property(nonatomic, readonly, copy) NSString* summary;
// The manifest's icon at 16 and 32 pt (every scale factor); nil while
// loading or when the extension has none.
@property(nonatomic, readonly, nullable) NSImage* icon16;
@property(nonatomic, readonly, nullable) NSImage* icon32;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
// Loaded from a folder (Manifest::IsUnpackedLocation): can be reloaded.
@property(nonatomic, readonly, getter=isUnpacked) BOOL unpacked;
// Installed from the Chrome Web Store (updates come from it).
@property(nonatomic, readonly) BOOL fromWebStore;
// The action's defaults (no page); nil for an extension without one.
@property(nonatomic, readonly, nullable) RoomExtensionAction* action;
// Pinned in ToolbarActionsModel (the host's header shows pinned actions).
@property(nonatomic, readonly, getter=isPinned) BOOL pinned;
// OptionsPageInfo::GetOptionsPage; nil when it has none.
@property(nonatomic, readonly, copy, nullable) NSURL* optionsPageURL;
// What the extension may do, as Chrome words it (PermissionMessages).
@property(nonatomic, readonly, copy) NSArray<NSString*>* permissionMessages;
// The hosts it can read and change (effective host permissions), as match
// patterns; "<all_urls>" for every site.
@property(nonatomic, readonly, copy) NSArray<NSString*>* hostPermissions;
@end

// What an install asks the user to allow (extensions::InstallPromptData).
typedef NS_ENUM(NSInteger, RoomExtensionInstallKind) {
  RoomExtensionInstallKindInstall = 0,
  // An installed extension wants more permissions (an update or a
  // permissions request) or is being re-enabled.
  RoomExtensionInstallKindPermissions,
  RoomExtensionInstallKindOther,
};

ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomExtensionInstallRequest : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly) RoomExtensionInstallKind kind;
// Chrome's title for the question, e.g. "Add “Dark Reader”?".
@property(nonatomic, readonly, copy) NSString* title;
// "It can:" or empty when it asks for nothing.
@property(nonatomic, readonly, copy) NSString* permissionsHeading;
// One line per permission (InstallPromptData::GetPermission).
@property(nonatomic, readonly, copy) NSArray<NSString*>* permissions;
// Its detail lines, if any (the same index as `permissions`).
@property(nonatomic, readonly, copy) NSArray<NSArray<NSString*>*>* permissionDetails;
@property(nonatomic, readonly, nullable) NSImage* icon;
// The page that asked (the Web Store's tab), when there is one.
@property(nonatomic, readonly, weak, nullable) RoomWebContents* webContents;
@end

// The result of -checkForUpdatesWithCompletion:.
typedef struct {
  // Whether a check ran (no extension installed, or the extension system
  // not ready yet: none).
  BOOL checked;
  // Extensions asked about.
  NSInteger extensions;
  // Updates found (each then downloads its CRX and installs when idle).
  NSInteger updatesFound;
} RoomExtensionUpdateCheckResult;

// Receives a profile's extension changes and asks the host's consent.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@protocol RoomProfileExtensionsDelegate <NSObject>
@optional
// The installed list changed (install, uninstall, enable, disable, reload,
// pin, an icon that finished loading).
- (void)profileExtensionsDidChange:(RoomProfileExtensions*)extensions
    NS_SWIFT_NAME(profileExtensionsDidChange(_:));
// An action changed (title, badge, icon, enabled) for one page
// (`webContents`) or for every page (nil).
- (void)profileExtensions:(RoomProfileExtensions*)extensions
    didUpdateActionOfExtension:(NSString*)identifier
                   webContents:(nullable RoomWebContents*)webContents
    NS_SWIFT_NAME(profileExtensions(_:didUpdateActionOfExtension:webContents:));
// Before -uninstallExtension:completion: removes it: the host shows its
// consent; NO keeps the extension. Without this member nothing is removed.
- (void)profileExtensions:(RoomProfileExtensions*)extensions
    willUninstallExtension:(RoomExtension*)extension
                completion:(void (^)(BOOL consent))completion
    NS_SWIFT_NAME(profileExtensions(_:willUninstall:completion:));
// An install wants the user's consent (the Web Store's "Add to Chrome", a
// CRX, more permissions after an update): the host shows the permissions;
// NO cancels. Implementing this member replaces Chrome's install dialog for
// this profile.
- (void)profileExtensions:(RoomProfileExtensions*)extensions
    willInstallExtension:(RoomExtensionInstallRequest*)request
              completion:(void (^)(BOOL consent))completion
    NS_SWIFT_NAME(profileExtensions(_:willInstall:completion:));
// An action popup opened (Phase 3.6b): `popup` is its page (Chrome's
// ExtensionViewHost), loaded and sized by its own layout (`size`, 25×25 to
// 800×600); `webContents` is the page the action ran for, whose window shows
// the popup in a popover on the action's button. After a click on that
// button (-openPopupForExtension:webContents:), the action's keyboard
// shortcut (`_execute_action`) or the extension's action.openPopup.
- (void)profileExtensions:(RoomProfileExtensions*)extensions
             didOpenPopup:(RoomWebContents*)popup
             forExtension:(NSString*)identifier
              webContents:(nullable RoomWebContents*)webContents
            preferredSize:(NSSize)size
    NS_SWIFT_NAME(profileExtensions(_:didOpenPopup:forExtension:webContents:preferredSize:));
// The popup's page changed its size (auto-resize, clamped as above).
- (void)profileExtensions:(RoomProfileExtensions*)extensions
                    popup:(RoomWebContents*)popup
            didResizeToSize:(NSSize)size
    NS_SWIFT_NAME(profileExtensions(_:popup:didResizeTo:));
// The popup is gone (the host's -closePopup:, window.close() or Esc in the
// popup, the window's active page changed, the extension unloaded): the
// host closes its popover if it still shows it.
- (void)profileExtensions:(RoomProfileExtensions*)extensions
            popupDidClose:(RoomWebContents*)popup
    NS_SWIFT_NAME(profileExtensions(_:popupDidClose:));
@end

// A profile's extension system (ExtensionRegistry, ExtensionRegistrar,
// ExtensionActionManager, ToolbarActionsModel, ExtensionUpdater).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomProfileExtensions : NSObject
- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, weak, nullable) id<RoomProfileExtensionsDelegate> delegate;
// Every installed extension (enabled and disabled; not Chrome's component
// extensions), pinned first in the toolbar's order, then by name.
@property(nonatomic, readonly, copy) NSArray<RoomExtension*>* extensions;
// The extension system has loaded the installed extensions.
@property(nonatomic, readonly, getter=isReady) BOOL ready;

// ExtensionRegistrar::EnableExtension / DisableExtension (user action).
- (void)setEnabled:(BOOL)enabled
      forExtension:(NSString*)identifier
    NS_SWIFT_NAME(setEnabled(_:forExtension:));
// ExtensionRegistrar::ReloadExtension (an unpacked extension re-reads its
// folder; others restart).
- (void)reloadExtension:(NSString*)identifier;
// Asks the delegate's consent, then ExtensionRegistrar::UninstallExtension
// (user initiated). completion(YES) once it is gone, NO when the host said
// no or Chrome refused.
- (void)uninstallExtension:(NSString*)identifier
                completion:(void (^)(BOOL uninstalled))completion
    NS_SWIFT_NAME(uninstallExtension(_:completion:));
// UnpackedInstaller::Load; completion with the new extension's identifier,
// or nil and Chrome's error.
- (void)loadUnpackedAtURL:(NSURL*)directory
               completion:(void (^)(NSString* _Nullable identifier,
                                    NSString* _Nullable error))completion
    NS_SWIFT_NAME(loadUnpacked(at:completion:));
// OptionsPageInfo::GetOptionsPage, for the host to open as a tab.
- (nullable NSURL*)optionsPageURLForExtension:(NSString*)identifier
    NS_SWIFT_NAME(optionsPageURL(forExtension:));
// chrome://extensions (Chrome's management page, opened as a tab).
@property(class, nonatomic, readonly) NSURL* managementPageURL;
// ToolbarActionsModel::SetActionVisibility.
- (void)setPinned:(BOOL)pinned
     forExtension:(NSString*)identifier
    NS_SWIFT_NAME(setPinned(_:forExtension:));
// The action as `webContents` shows it (nil: the defaults).
- (nullable RoomExtensionAction*)actionForExtension:(NSString*)identifier
                                        webContents:
                                            (nullable RoomWebContents*)webContents
    NS_SWIFT_NAME(action(forExtension:webContents:));
// A click on the action's button for `webContents` (a page in a
// RoomBrowser): ExtensionActionRunner::RunAction with tab permissions
// (activeTab; action.onClicked when the action has no popup), then the
// popup when it has one; YES when a popup is opening (the delegate's
// -profileExtensions:didOpenPopup:… follows once it loaded). A click while
// that action's popup shows closes it. Side panels are not supported: an
// action set to open one does nothing.
- (BOOL)openPopupForExtension:(NSString*)identifier
                  webContents:(RoomWebContents*)webContents
    NS_SWIFT_NAME(openPopup(forExtension:webContents:));
// The host's popover closed (focus loss, Esc): the popup's page is
// destroyed; -profileExtensions:popupDidClose: follows.
- (void)closePopup:(RoomWebContents*)popup;
// ExtensionUpdater::CheckNow for every installed extension: the only way an
// extension update check reaches the network (Chrome's own schedule is
// refused). Updates found download and install when the extension is idle.
- (void)checkForUpdatesWithCompletion:
    (void (^)(RoomExtensionUpdateCheckResult result))completion
    NS_SWIFT_NAME(checkForUpdates(completion:));
@end

NS_ASSUME_NONNULL_END
