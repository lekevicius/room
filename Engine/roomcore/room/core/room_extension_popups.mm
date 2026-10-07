// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Extension action popups and commands for Room windows (Phase 3.6b).
//
// Chrome reaches a window's extension UI through ExtensionsContainer, user
// data on the BrowserWindowInterface (ExtensionsContainer::From): Views'
// ExtensionsToolbarDesktop and WebUIBrowserWindow register one. Room
// registers its own on every Browser it binds to a host window. Its popup is
// what Chrome's ExtensionPopup shows in a Views bubble: an ExtensionViewHost
// (ExtensionViewHostFactory::CreatePopupHost) whose page here is handed to
// the host, which shows it in an NSPopover on the header's action button and
// sizes it from the page's auto-resize (25×25 to 800×600, ExtensionPopup's
// bounds). The window's extension shortcuts are an ExtensionKeybindingRegistry
// like Android's (no Views focus manager): RoomBrowserWindow asks it before a
// key reaches the page.

#import "room/core/room_extension_popups.h"

#import <AppKit/AppKit.h>

#include <map>
#include <set>
#include <utility>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/extensions/commands/command_service.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_keybinding_registry.h"
#include "chrome/browser/extensions/extension_tab_util.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_list_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/common/command.h"
#include "extensions/common/extension.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "ui/base/accelerators/accelerator.h"
#include "ui/base/accelerators/command.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"
#include "ui/content_accelerators/accelerator_util.h"
#include "ui/gfx/geometry/size.h"
#include "chrome/browser/extensions/extension_util.h"
#include "extensions/browser/extension_util.h"
#import "room/browser/room_browser_window.h"
#import "room/core/room_extensions_internal.h"
#import "room/core/room_profile_internal.h"
#import "room/core/room_web_contents_internal.h"

namespace room {
namespace {

// Chrome's ExtensionPopup::kMinSize / kMaxSize.
constexpr gfx::Size kMinPopupSize(25, 25);
constexpr gfx::Size kMaxPopupSize(800, 600);

class Container;

std::set<Container*>& Containers() {
  static base::NoDestructor<std::set<Container*>> containers;
  return *containers;
}

RoomProfileExtensions* ExtensionsWrapper(BrowserWindowInterface* browser) {
  Profile* profile = browser ? browser->GetProfile() : nullptr;
  RoomProfile* wrapper =
      profile ? [RoomProfile room_existingProfileFor:profile->GetOriginalProfile()]
              : nil;
  return wrapper.room_existingExtensions;
}

NSSize ToNSSize(const gfx::Size& size) {
  return NSMakeSize(size.width(), size.height());
}

// One action popup: the ExtensionViewHost (its page is the host's popover
// content) and the ExtensionView Chrome's host talks to.
class Popup : public extensions::ExtensionView,
              public content::WebContentsObserver {
 public:
  Popup(BrowserWindowInterface* browser,
        std::unique_ptr<extensions::ExtensionViewHost> host,
        content::WebContents* page,
        bool by_user,
        ShowPopupCallback callback,
        base::OnceClosure close_request)
      : browser_(browser),
        host_(std::move(host)),
        page_(page ? page->GetWeakPtr() : nullptr),
        by_user_(by_user),
        callback_(std::move(callback)),
        close_request_(std::move(close_request)),
        started_(base::TimeTicks::Now()) {}

  ~Popup() override {
    Observe(nullptr);
    if (shown_) {
      [ExtensionsWrapper(browser_) room_popupDidClose:wrapper_];
    }
    if (callback_) {
      std::move(callback_).Run(nullptr);  // never shown
    }
    LOG(INFO) << "RoomCore: extension popup of " << extension_id_
              << " closed (" << (shown_ ? "shown" : "never shown") << ")";
    host_.reset();
  }

  void Start() {
    extension_id_ = host_->extension_id();
    content::WebContents* contents = host_->host_contents();
    wrapper_ = [[RoomWebContents alloc]
        initWithHostedChromeWebContents:contents
                                profile:[RoomProfile room_profileFor:
                                                         browser_->GetProfile()
                                                             ->GetOriginalProfile()]];
    host_->set_view(this);
    // window.close() in the popup, Esc (ExtensionViewHost), a crashed page:
    // the host closes, after the call that asked for it returns.
    host_->SetCloseHandler(base::BindOnce(
        [](base::WeakPtr<Popup> popup, extensions::ExtensionHost*) {
          if (popup && popup->close_request_) {
            std::move(popup->close_request_).Run();
          }
        },
        weak_factory_.GetWeakPtr()));
    Observe(contents);
    LOG(INFO) << "RoomCore: extension popup of " << extension_id_ << " for "
              << host_->initial_url().spec() << " ("
              << (by_user_ ? "the host's button" : "action.openPopup") << ")";
    host_->CreateRendererSoon();
    if (host_->has_loaded_once()) {
      Shown();
    }
  }

  content::WebContents* contents() const {
    return host_ ? host_->host_contents() : nullptr;
  }
  const std::string& extension_id() const { return extension_id_; }

  // extensions::ExtensionView:
  gfx::NativeView GetNativeView() override {
    return host_->host_contents()->GetNativeView();
  }

  void ResizeDueToAutoResize(content::WebContents*,
                             const gfx::Size& new_size) override {
    gfx::Size size = new_size;
    size.SetToMax(kMinPopupSize);
    size.SetToMin(kMaxPopupSize);
    if (size == size_) {
      return;
    }
    size_ = size;
    if (shown_) {
      [ExtensionsWrapper(browser_) room_popup:wrapper_
                                     didResize:ToNSSize(size_)];
    }
  }

  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    // What views::WebView::EnableSizingFromWebContents does for Chrome's
    // popup: the page's own layout sets the popup's size.
    // views::WebView::RenderFrameCreated: the initial main frame only, not
    // speculative ones (a frame swap arrives in RenderFrameHostChanged).
    if (host_ && frame == host_->host_contents()->GetPrimaryMainFrame()) {
      EnableAutoResize(frame);
    }
  }

  bool HandleKeyboardEvent(content::WebContents*,
                           const input::NativeWebKeyboardEvent& event) override {
    // A key the popup's page did not use: the host's main menu, as the
    // DevTools front-end's (RoomBrowserWindow::HandleKeyboardEvent).
    NSEvent* ns_event = event.os_event.Get();
    return event.GetType() == blink::WebInputEvent::Type::kRawKeyDown &&
           ns_event && ns_event.type == NSEventTypeKeyDown &&
           [NSApp.mainMenu performKeyEquivalent:ns_event];
  }

  void OnLoaded() override {}

  // content::WebContentsObserver:
  void RenderFrameHostChanged(content::RenderFrameHost* old_host,
                              content::RenderFrameHost* new_host) override {
    if (old_host && new_host && host_ &&
        new_host == host_->host_contents()->GetPrimaryMainFrame()) {
      EnableAutoResize(new_host);
    }
  }

  void DocumentOnLoadCompletedInPrimaryMainFrame() override {
    // ExtensionPopup shows its bubble here: the page's width is computed.
    Shown();
  }

 private:
  void EnableAutoResize(content::RenderFrameHost* frame) {
    if (frame->IsRenderFrameLive() && frame->GetView()) {
      frame->GetView()->EnableAutoResize(kMinPopupSize, kMaxPopupSize);
    }
  }

  void Shown() {
    if (shown_ || !host_) {
      return;
    }
    shown_ = true;
    if (size_.IsEmpty()) {
      size_ = kMinPopupSize;
    }
    const base::TimeDelta elapsed = base::TimeTicks::Now() - started_;
    LOG(INFO) << "RoomCore: extension popup of " << extension_id_
              << " loaded in " << elapsed.InMillisecondsF() << " ms, "
              << size_.ToString();
    RoomWebContents* page =
        page_ ? [RoomWebContents room_existingWrapperFor:page_.get()] : nil;
    [ExtensionsWrapper(browser_)
        room_popupDidOpen:wrapper_
                extension:base::SysUTF8ToNSString(extension_id_)
              webContents:page
                     size:ToNSSize(size_)];
    // The host put the page in its popover (synchronously, above): it takes
    // the keyboard, as ExtensionPopup::ShowBubble focuses the host contents.
    if (host_ && host_->host_contents()) {
      host_->host_contents()->Focus();
    }
    if (callback_) {
      std::move(callback_).Run(host_.get());
    }
  }

  raw_ptr<BrowserWindowInterface> browser_;
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  base::WeakPtr<content::WebContents> page_;
  const bool by_user_;
  ShowPopupCallback callback_;
  base::OnceClosure close_request_;
  const base::TimeTicks started_;
  std::string extension_id_;
  RoomWebContents* __strong wrapper_ = nil;
  gfx::Size size_;
  bool shown_ = false;
  base::WeakPtrFactory<Popup> weak_factory_{this};
};

// The window's extension shortcuts: ExtensionKeybindingRegistryAndroid's
// shape (no focus manager to register with): the registry keeps the
// accelerators, RoomBrowserWindow asks it for each key-down.
class KeybindingRegistry : public extensions::ExtensionKeybindingRegistry {
 public:
  KeybindingRegistry(Profile* profile,
                     TabListInterface* tabs,
                     base::RepeatingCallback<void(const std::string&)> action)
      : ExtensionKeybindingRegistry(profile, tabs, ALL_EXTENSIONS),
        action_(std::move(action)) {
    Init();
  }

  bool HandleAccelerator(const ui::Accelerator& accelerator) {
    if (suspended_ || !accelerators_.contains(accelerator)) {
      return false;
    }
    const auto action = action_accelerators_.find(accelerator);
    if (action != action_accelerators_.end()) {
      LOG(INFO) << "RoomCore: _execute_action of " << action->second
                << " from the keyboard";
      action_.Run(action->second);
      return true;
    }
    const bool executed = NotifyEventTargets(accelerator);
    LOG(INFO) << "RoomCore: extension command for "
              << base::UTF16ToUTF8(accelerator.GetShortcutText())
              << (executed ? " sent" : " has no listener");
    return executed;
  }

  // A named command without its key (4.5, B-70): commands.onCommand with the
  // window's active tab, as NotifyEventTargets sends it for the key.
  void RunNamedCommand(const extensions::ExtensionId& extension_id,
                       const std::string& command_name) {
    LOG(INFO) << "RoomCore: extension command " << command_name << " of "
              << extension_id << " from the host";
    CommandExecuted(extension_id, command_name);
  }

 private:
  // extensions::ExtensionKeybindingRegistry:
  bool PopulateCommands(const extensions::Extension* extension,
                        ui::CommandMap* commands) override {
    auto* service = extensions::CommandService::Get(browser_context());
    const bool named = service->GetNamedCommands(
        extension->id(), extensions::CommandService::ACTIVE,
        extensions::CommandService::REGULAR, commands);
    extensions::Command command;
    const bool action = service->GetExtensionActionCommand(
        extension->id(), extensions::ActionInfo::Type::kAction,
        extensions::CommandService::ACTIVE, &command, /*active=*/nullptr);
    if (action) {
      (*commands)[command.command_name()] = command;
    }
    return named || action;
  }

  bool RegisterAccelerator(const ui::Accelerator& accelerator,
                           const extensions::ExtensionId& extension_id,
                           const std::string& command_name) override {
    accelerators_.insert(accelerator);
    if (extensions::Command::IsActionRelatedCommand(command_name)) {
      action_accelerators_[accelerator] = extension_id;
    }
    return true;
  }

  void UnregisterAccelerator(const ui::Accelerator& accelerator) override {
    accelerators_.erase(accelerator);
    action_accelerators_.erase(accelerator);
  }

  void OnShortcutHandlingSuspended(bool suspended) override {
    suspended_ = suspended;
  }

  // This registry runs the action commands itself (Views leaves them to
  // each toolbar button).
  bool ShouldIgnoreCommand(const std::string&) const override { return false; }

  base::RepeatingCallback<void(const std::string&)> action_;
  std::set<ui::Accelerator> accelerators_;
  std::map<ui::Accelerator, extensions::ExtensionId> action_accelerators_;
  bool suspended_ = false;
};

class Container : public RoomBrowserExtensions,
                  public ExtensionsContainer,
                  public TabStripModelObserver,
                  public extensions::ExtensionRegistryObserver {
 public:
  explicit Container(BrowserWindowInterface* browser)
      : browser_(browser),
        profile_(browser->GetProfile()),
        registration_(browser->GetUnownedUserDataHost(),
                      static_cast<ExtensionsContainer&>(*this)) {
    Containers().insert(this);
    browser_->GetTabStripModel()->AddObserver(this);
    registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile_));
    keybindings_ = std::make_unique<KeybindingRegistry>(
        profile_, TabListInterface::From(browser_),
        base::BindRepeating(&Container::ExecuteActionCommand,
                            base::Unretained(this)));
  }

  ~Container() override {
    Containers().erase(this);
    popup_.reset();
    keybindings_.reset();
    browser_->GetTabStripModel()->RemoveObserver(this);
  }

  bool Owns(content::WebContents* popup) const {
    return popup_ && popup_->contents() == popup;
  }

  // RoomBrowserExtensions:
  bool RunActionFromHost(const std::string& extension_id,
                         content::WebContents* contents) override {
    const extensions::Extension* extension = EnabledExtension(extension_id);
    if (!extension || !contents) {
      return false;
    }
    if (popup_ && popup_->extension_id() == extension_id) {
      // A second click (or the command) on the action whose popup shows
      // closes it, as Chrome's button does.
      ClosePopupSoon();
      return false;
    }
    auto* runner = extensions::ExtensionActionRunner::GetForWebContents(contents);
    if (!runner) {
      LOG(WARNING) << "RoomCore: no ExtensionActionRunner for the page; "
                      "action of "
                   << extension_id << " not run";
      return false;
    }
    // Chrome's ExtensionActionViewModel::ExecuteUserAction: a user action
    // grants tab permissions (activeTab), dispatches action.onClicked when
    // there is no popup, and says what the UI shows.
    const extensions::ExtensionAction::ShowAction show =
        runner->RunAction(extension, /*grant_tab_permissions=*/true);
    switch (show) {
      case extensions::ExtensionAction::ShowAction::kShowPopup:
        return OpenPopup(*extension, contents, /*by_user=*/true,
                         ShowPopupCallback());
      case extensions::ExtensionAction::ShowAction::kToggleSidePanel:
        LOG(WARNING) << "RoomCore: " << extension_id
                     << " opens a side panel on its action; side panels are "
                        "not supported (3.6b)";
        return false;
      default:
        return false;  // onClicked went to the extension (or nothing to do)
    }
  }

  void ClosePopup(content::WebContents* popup) override {
    if (Owns(popup)) {
      ClosePopupSoon();
    }
  }

  bool HandleKeyEvent(const input::NativeWebKeyboardEvent& event) override {
    if (event.GetType() != blink::WebInputEvent::Type::kRawKeyDown) {
      return false;
    }
    return keybindings_->HandleAccelerator(
        ui::GetAcceleratorFromNativeWebKeyboardEvent(event));
  }

  bool RunCommand(const std::string& extension_id,
                  const std::string& command_name,
                  content::WebContents* contents) override {
    if (!EnabledExtension(extension_id)) {
      return false;
    }
    auto* service = extensions::CommandService::Get(profile_);
    extensions::Command action_command;
    if (extensions::Command::IsActionRelatedCommand(command_name)) {
      // The action's command clicks the action for the page (the window's
      // active one when the host names none), as its key does.
      if (!service->GetExtensionActionCommand(
              extension_id, extensions::ActionInfo::Type::kAction,
              extensions::CommandService::ACTIVE, &action_command,
              /*active=*/nullptr)) {
        return false;
      }
      LOG(INFO) << "RoomCore: _execute_action of " << extension_id
                << " from the host";
      RunActionFromHost(extension_id,
                        contents ? contents
                                 : browser_->GetTabStripModel()
                                       ->GetActiveWebContents());
      return true;
    }
    ui::CommandMap named;
    service->GetNamedCommands(extension_id,
                              extensions::CommandService::ACTIVE,
                              extensions::CommandService::ANY_SCOPE, &named);
    if (!named.contains(command_name)) {
      return false;
    }
    keybindings_->RunNamedCommand(extension_id, command_name);
    return true;
  }

  Profile* profile() const { return profile_; }

  // ExtensionsContainer:
  ToolbarActionViewModel* GetActionForId(const std::string& action_id) override {
    // Chrome's view models are Views-side; Room's buttons are the host's.
    // Callers: the DevTools protocol's Extensions.triggerAction, Views menus.
    RoomStubHit("ExtensionsContainer::GetActionForId");
    return nullptr;
  }

  void HideActivePopup() override { ClosePopupSoon(); }

  void CloseExtensionsMenuIfOpen() override {
    // Room has no extensions menu (the overflow menu is Chapter 4.5).
    RoomStubHit("ExtensionsContainer::CloseExtensionsMenuIfOpen");
  }

  bool ShowToolbarActionPopupForAPICall(const std::string& action_id,
                                        ShowPopupCallback callback) override {
    // action.openPopup (OpenPopupInBrowser checked the toolbar and that the
    // active tab's action has a popup). Not a user action: no tab
    // permissions, as ExtensionActionViewModel::TriggerPopupForAPI.
    const extensions::Extension* extension = EnabledExtension(action_id);
    content::WebContents* contents =
        browser_->GetTabStripModel()->GetActiveWebContents();
    if (!extension || !contents) {
      return false;
    }
    return OpenPopup(*extension, contents, /*by_user=*/false,
                     std::move(callback));
  }

  void ToggleExtensionsMenu() override {
    RoomStubHit("ExtensionsContainer::ToggleExtensionsMenu");
  }

  bool HasAnyExtensions() const override {
    ToolbarActionsModel* model = ToolbarActionsModel::Get(profile_);
    return model && !model->action_ids().empty();
  }

  // TabStripModelObserver: Chrome's popup closes when the active tab
  // changes (ExtensionPopup::OnTabStripModelChanged).
  void OnTabStripModelChanged(TabStripModel* tab_strip_model,
                              const TabStripModelChange&,
                              const TabStripSelectionChange& selection) override {
    if (popup_ && !tab_strip_model->empty() && selection.active_tab_changed()) {
      ClosePopupSoon();
    }
  }

  // ExtensionRegistryObserver:
  void OnExtensionUnloaded(content::BrowserContext*,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    if (popup_ && popup_->extension_id() == extension->id()) {
      ClosePopupSoon();
    }
  }

 private:
  const extensions::Extension* EnabledExtension(const std::string& id) {
    const extensions::Extension* extension =
        extensions::ExtensionRegistry::Get(profile_)
            ->enabled_extensions()
            .GetByID(id);
    // An off-the-record window offers only the extensions allowed in
    // incognito (4.8b; Chrome's toolbar model filters the same way).
    if (extension && profile_->IsOffTheRecord() &&
        !extensions::util::IsIncognitoEnabled(id, profile_)) {
      return nullptr;
    }
    return extension;
  }

  bool OpenPopup(const extensions::Extension& extension,
                 content::WebContents* contents,
                 bool by_user,
                 ShowPopupCallback callback) {
    const extensions::ExtensionAction* action =
        extensions::ExtensionActionManager::Get(profile_)->GetExtensionAction(
            extension);
    const int tab_id = extensions::ExtensionTabUtil::GetTabId(contents);
    if (!action || !action->HasPopup(tab_id)) {
      return false;
    }
    popup_.reset();  // one popup per window
    closing_ = false;
    std::unique_ptr<extensions::ExtensionViewHost> host =
        extensions::ExtensionViewHostFactory::CreatePopupHost(
            extension, action->GetPopupUrl(tab_id), browser_);
    if (!host) {
      return false;
    }
    popup_ = std::make_unique<Popup>(
        browser_, std::move(host), contents, by_user, std::move(callback),
        base::BindOnce(&Container::ClosePopupSoon, weak_factory_.GetWeakPtr()));
    popup_->Start();
    return true;
  }

  void ExecuteActionCommand(const std::string& extension_id) {
    RunActionFromHost(extension_id,
                      browser_->GetTabStripModel()->GetActiveWebContents());
  }

  // After the current task: a close may come from inside the popup host's
  // own call stack (window.close(), Esc).
  void ClosePopupSoon() {
    if (!popup_ || closing_) {
      return;
    }
    closing_ = true;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<Container> container) {
                         if (container && container->closing_) {
                           container->closing_ = false;
                           container->popup_.reset();
                         }
                       },
                       weak_factory_.GetWeakPtr()));
  }

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<Profile> profile_;
  ui::ScopedUnownedUserData<ExtensionsContainer> registration_;
  std::unique_ptr<KeybindingRegistry> keybindings_;
  std::unique_ptr<Popup> popup_;
  bool closing_ = false;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  base::WeakPtrFactory<Container> weak_factory_{this};
};

}  // namespace

RoomBrowserExtensions* BrowserExtensionsForProfile(Profile* profile) {
  for (Container* container : Containers()) {
    if (container->profile() == profile) {
      return container;
    }
  }
  return nullptr;
}

std::unique_ptr<RoomBrowserExtensions> RoomBrowserExtensions::Create(
    BrowserWindowInterface* browser) {
  return std::make_unique<Container>(browser);
}

RoomBrowserExtensions* BrowserExtensionsForPopup(content::WebContents* popup) {
  for (Container* container : Containers()) {
    if (container->Owns(popup)) {
      return container;
    }
  }
  return nullptr;
}

}  // namespace room
