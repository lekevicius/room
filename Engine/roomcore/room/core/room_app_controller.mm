// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_app_controller.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <set>
#include <string>

#import "chrome/browser/app_controller_mac.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/devtools/chrome_devtools_manager_delegate.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/sessions/tab_restore_service_factory.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/browser_window/public/profile_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "content/public/browser/web_contents.h"
#include "room/browser/room_browser_window.h"
#include "ui/color/color_provider.h"

namespace room {
// Defined in chrome/browser/app_controller_mac.mm
// (patches/0013-app-controller-hook.patch).
extern id (*g_app_controller_hook)();
}  // namespace room

// Stands in for Chrome's AppController (PLAN §4 "Main menu"). The host owns
// NSApp.delegate and the menu bar; this object answers the messages Chrome
// code sends to AppController.sharedController directly: termination
// (BrowserCrApplication -terminate:/-cancelTerminate:), the end of the main
// loop, the keep-alive, the last profile, command dispatch, the main window's
// Browser. It has no menu bridges, opens no windows and never becomes
// NSApp.delegate. Every other AppController message is logged on its first
// hit and answered with zero (-forwardInvocation:), like the BrowserWindow
// stubs.
@interface RoomAppController : NSObject
+ (instancetype)sharedController;
@end

namespace {

// First hit of each message, by selector: implemented ones at INFO, the
// forwarded (stubbed) ones as "stub hit" warnings the baseline collects.
void LogFirstHit(SEL selector, bool implemented) {
  static base::NoDestructor<std::set<std::string>> seen;
  const std::string name =
      base::SysNSStringToUTF8(NSStringFromSelector(selector));
  if (!seen->insert(name).second) {
    return;
  }
  if (implemented) {
    LOG(INFO) << "RoomAppController: " << name;
  } else {
    LOG(WARNING) << "RoomAppController stub hit: " << name;
  }
}

// The Room Browser (one //room created for a host window) the user works in:
// the most recently activated one.
BrowserWindowInterface* LastActiveRoomBrowser() {
  BrowserWindowInterface* found = nullptr;
  GlobalBrowserCollection::GetInstance()->ForEach(
      [&found](BrowserWindowInterface* browser) {
        if (room::RoomBrowserWindowFor(browser)) {
          found = browser;
          return false;
        }
        return true;
      },
      BrowserCollection::Order::kActivation);
  return found;
}

// The Room Browser of `window` whose active page is on screen (a host window
// holds one Browser per profile); the first one of that window otherwise.
BrowserWindowInterface* RoomBrowserShownIn(NSWindow* window) {
  BrowserWindowInterface* found = nullptr;
  GlobalBrowserCollection::GetInstance()->ForEach(
      [&found, window](BrowserWindowInterface* browser) {
        RoomBrowserWindow* room_window = room::RoomBrowserWindowFor(browser);
        if (!room_window ||
            room_window->GetNativeWindow().GetNativeNSWindow() != window) {
          return true;
        }
        if (!found) {
          found = browser;
        }
        content::WebContents* active =
            browser->GetTabStripModel()->GetActiveWebContents();
        NSView* view =
            active ? active->GetNativeView().GetNativeNSView() : nil;
        if (view.window == window && !view.hiddenOrHasHiddenAncestor) {
          found = browser;
          return false;
        }
        return true;
      });
  return found;
}

}  // namespace

@implementation RoomAppController {
  // What AppController's keep-alive does: the browser process outlives its
  // last Browser (Room closes a window's Browser when its last page leaves).
  std::unique_ptr<ScopedKeepAlive> _keepAlive;
}

+ (instancetype)sharedController {
  static RoomAppController* shared = [[RoomAppController alloc] init];
  return shared;
}

- (instancetype)init {
  if ((self = [super init])) {
    _keepAlive = std::make_unique<ScopedKeepAlive>(
        KeepAliveOrigin::APP_CONTROLLER, KeepAliveRestartOption::DISABLED);
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(windowDidBecomeMain:)
                   name:NSWindowDidBecomeMainNotification
                 object:nil];
    // Posted by chrome::OnAppExiting() (HandleAppExitingForPlatform), the
    // quit's point of no return.
    [center addObserver:self
               selector:@selector(room_appWillTerminate:)
                   name:NSApplicationWillTerminateNotification
                 object:nil];
    LOG(INFO) << "RoomCore: RoomAppController stands in for AppController "
                 "(no Chrome main menu; NSApp.delegate is the host's)";
  }
  return self;
}

// MARK: Termination

// BrowserCrApplication -terminate: (after the host's delegate agreed) and
// -[RoomApplication tryToTerminateWithCompletion:]: Chrome's close path.
// beforeunload handlers run on every Browser's tabs (BrowserCloseManager);
// a "stay" cancels the quit. No downloads prompt (the host's, 3.4a), no
// confirm-to-quit panel, no apps-keep-running check.
- (void)tryToTerminateApplication {
  LogFirstHit(_cmd, true);
  if (browser_shutdown::IsTryingToQuit()) {
    return;
  }
  chrome::OnClosingAllBrowsers(true);
  chrome::CloseAllBrowsersAndQuit();
}

- (void)stopTryingToTerminateApplication {
  LogFirstHit(_cmd, true);
  if (browser_shutdown::IsTryingToQuit()) {
    browser_shutdown::SetTryingToQuit(false);
  }
}

- (void)allowApplicationToTerminate {
  LogFirstHit(_cmd, true);
  _keepAlive.reset();
}

- (ConfirmQuitResult)confirmQuitIfNeeded {
  LogFirstHit(_cmd, true);
  return ConfirmQuitResultNotPrompted;
}

- (void)room_appWillTerminate:(NSNotification*)notification {
  _keepAlive.reset();
  // The host accepted this quit: with --remote-debugging-port (Debug spikes)
  // Chrome would otherwise wait for the protocol's Browser.close.
  ChromeDevToolsManagerDelegate::AllowBrowserToClose();
}

- (void)didEndMainMessageLoop {
  LogFirstHit(_cmd, true);
  // AppController resets its last profile's TabRestoreService here so the
  // NavigationControllers shut down before the threads go; Room's pages live
  // in several profiles, so every loaded one without Browsers.
  ProfileManager* manager =
      g_browser_process ? g_browser_process->profile_manager() : nullptr;
  if (!manager) {
    return;
  }
  for (Profile* profile : manager->GetLoadedProfiles()) {
    ProfileBrowserCollection* browsers =
        ProfileBrowserCollection::GetForProfile(profile);
    if (!browsers || !browsers->GetSize()) {
      TabRestoreServiceFactory::ResetForProfile(profile);
    }
  }
}

// MARK: Profiles

- (Profile*)lastProfileIfLoaded {
  LogFirstHit(_cmd, true);
  if (BrowserWindowInterface* browser = LastActiveRoomBrowser()) {
    return browser->GetProfile()->GetOriginalProfile();
  }
  return ProfileManager::GetLastUsedProfileIfLoaded();
}

- (Profile*)lastProfile {
  LogFirstHit(_cmd, true);
  return self.lastProfileIfLoaded;
}

- (Profile*)safeProfileForNewWindows:(Profile*)profile {
  LogFirstHit(_cmd, true);
  return profile;
}

- (BOOL)startupComplete {
  LogFirstHit(_cmd, true);
  return YES;
}

- (BOOL)keyWindowIsModal {
  LogFirstHit(_cmd, true);
  NSWindow* key = NSApp.keyWindow;
  return NSApp.modalWindow != nil || key.attachedSheet != nil;
}

- (const ui::ColorProvider&)lastActiveColorProvider {
  // Only Chrome's menu bridges ask; Room has none.
  LogFirstHit(_cmd, false);
  static base::NoDestructor<ui::ColorProvider> provider;
  return *provider;
}

// MARK: Windows

// What AppController's -windowDidBecomeMain: does for Browsers, without the
// menu bridges: the window's Browser becomes the last active one (Chrome's
// BrowserView reports this from its widget; RoomBrowserWindow only on
// Show/Activate).
- (void)windowDidBecomeMain:(NSNotification*)notification {
  if (BrowserWindowInterface* browser =
          RoomBrowserShownIn(notification.object)) {
    BrowserActiveStateManager::From(browser)->DidBecomeActive();
  }
}

// MARK: Commands

// Chrome-internal callers dispatch IDC_* commands here (menu items tagged
// with a command id, extension commands); they run on the active Room
// Browser's command controller.
- (void)commandDispatch:(id)sender {
  LogFirstHit(_cmd, true);
  if (g_browser_process->IsShuttingDown() ||
      browser_shutdown::IsTryingToQuit()) {
    return;
  }
  if ([sender tag] == IDC_EXIT) {
    [NSApp terminate:sender];  // The host's delegate decides.
    return;
  }
  [self executeCommand:sender withProfile:self.lastProfileIfLoaded];
}

- (void)commandDispatchUsingKeyModifiers:(id)sender {
  LogFirstHit(_cmd, true);
  [self commandDispatch:sender];
}

- (void)executeCommand:(id)sender withProfile:(Profile*)profile {
  LogFirstHit(_cmd, true);
  const int command = static_cast<int>([sender tag]);
  BrowserWindowInterface* browser = LastActiveRoomBrowser();
  if (!browser) {
    LOG(WARNING) << "RoomAppController: no Room Browser for command "
                 << command;
    return;
  }
  if (!chrome::IsCommandEnabled(browser, command)) {
    LOG(WARNING) << "RoomAppController: command " << command
                 << " is disabled";
    return;
  }
  chrome::ExecuteCommand(browser, command);
}

// MARK: Everything else AppController answers

- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector {
  NSMethodSignature* signature = [super methodSignatureForSelector:selector];
  return signature ?: [AppController instanceMethodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation*)invocation {
  LogFirstHit(invocation.selector, false);
  const NSUInteger length = invocation.methodSignature.methodReturnLength;
  if (length > 0) {
    std::string zero(length, '\0');
    [invocation setReturnValue:zero.data()];
  }
}

@end

namespace room {

void InstallAppController() {
  g_app_controller_hook = +[]() -> id {
    return [RoomAppController sharedController];
  };
}

void TryToTerminateApplication() {
  [[RoomAppController sharedController] tryToTerminateApplication];
}

}  // namespace room
