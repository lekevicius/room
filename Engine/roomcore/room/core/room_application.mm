// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_application_internal.h"

#include <Security/Security.h>
#include <crt_externs.h>
#include <stdlib.h>

#include <memory>
#include <string>
#include <vector>

#include "base/apple/bundle_locations.h"
#include "base/check.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/logging.h"
#include "base/memory/memory_pressure_level.h"
#include "base/memory/memory_pressure_listener.h"
#include "base/path_service.h"
#include "base/functional/bind.h"
#include "base/callback_list.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/common/chrome_switches.h"
#include "chrome/common/chrome_paths.h"
#include "chrome/common/chrome_paths_internal.h"
#include "components/crash/core/common/crash_key.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "url/gurl.h"
#import "room/browser/room_browser_window.h"
#import "room/core/public/RoomCore.h"
#import "room/core/public/RoomCrApplication.h"
#import "room/core/room_app_controller.h"
#import "room/core/room_extensions_internal.h"
#import "room/core/room_profile_internal.h"
#import "room/core/room_page_ui_internal.h"
#import "room/core/room_web_contents_internal.h"
#include "room/core/room_network_policy.h"

// chrome/app/chrome_main.cc, linked into the same library.
extern "C" int ChromeMain(int argc, const char** argv);

namespace {

// Switches every RoomCore process starts with: the host creates all windows
// itself, and Chromium's first-run and default-browser UI does not exist in
// Room.
constexpr const char* kDefaultSwitches[] = {
    "--no-startup-window",
    "--no-first-run",
    "--no-default-browser-check",
};

// Whether `arguments` (after argv[0]) carry `name`, alone or as `name=…`.
bool HasSwitch(const std::vector<std::string>& arguments, const char* name) {
  const std::string bare = std::string("--") + name;
  for (size_t i = 1; i < arguments.size(); ++i) {
    const std::string& argument = arguments[i];
    if (argument == bare || argument.starts_with(bare + "=")) {
      return true;
    }
  }
  return false;
}

// Room's engine data root when the host names none:
// ~/Library/Application Support/Room/RoomCore (never Chromium's own
// ~/Library/Application Support/Chromium).
NSURL* DefaultUserDataDirectory() {
  NSURL* support =
      [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                           inDomains:NSUserDomainMask]
          .firstObject;
  return [[support URLByAppendingPathComponent:@"Room" isDirectory:YES]
      URLByAppendingPathComponent:@"RoomCore"
                      isDirectory:YES];
}

// Team ID of the running process's signature; empty for ad-hoc or unsigned
// builds. Ad-hoc builds get a new code identity per build, so macOS asks for
// the login password before every read of "Room Safe Storage" (PLAN §4
// Keychain); those run with the mock keychain.
bool IsTeamSigned() {
  SecCodeRef code = nullptr;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess || !code) {
    return false;
  }
  SecStaticCodeRef static_code = nullptr;
  OSStatus status =
      SecCodeCopyStaticCode(code, kSecCSDefaultFlags, &static_code);
  CFRelease(code);
  if (status != errSecSuccess || !static_code) {
    return false;
  }
  CFDictionaryRef info = nullptr;
  status = SecCodeCopySigningInformation(
      static_code, kSecCSSigningInformation, &info);
  CFRelease(static_code);
  if (status != errSecSuccess || !info) {
    return false;
  }
  const bool team_signed =
      CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier) != nullptr;
  CFRelease(info);
  return team_signed;
}

NSString* InfoString(NSBundle* bundle, NSString* key) {
  id value = [bundle objectForInfoDictionaryKey:key];
  return [value isKindOfClass:NSString.class] ? value : nil;
}

// Crash keys every browser-process report carries: the host's version, the
// Chromium tag and the //room commit (written into the framework's
// Info.plist as RoomCoreCommit by scripts/roomcore-package.sh).
void SetCrashKeys() {
  static crash_reporter::CrashKeyString<32> app_version("room-app-version");
  static crash_reporter::CrashKeyString<32> chromium("room-chromium");
  static crash_reporter::CrashKeyString<48> commit("room-commit");
  NSBundle* outer = base::apple::OuterBundle();
  NSString* short_version =
      InfoString(outer, @"CFBundleShortVersionString") ?: @"?";
  NSString* build = InfoString(outer, @"CFBundleVersion") ?: @"?";
  const std::string version = base::SysNSStringToUTF8(
      [NSString stringWithFormat:@"%@ (%@)", short_version, build]);
  const std::string room_commit = base::SysNSStringToUTF8(
      InfoString(base::apple::FrameworkBundle(), @"RoomCoreCommit")
          ?: @"unknown");
  app_version.Set(version);
  chromium.Set(RoomCoreChromiumVersion());
  commit.Set(room_commit);
  LOG(INFO) << "Room crash keys: room-app-version=" << version
            << " room-chromium=" << RoomCoreChromiumVersion()
            << " room-commit=" << room_commit;
}

}  // namespace

@interface RoomApplication ()
- (void)room_memoryPressureChanged:(base::MemoryPressureLevel)level;
@end

namespace {

// Chromium's memory-pressure notifications for the host (3.7b). The
// registration needs a MemoryPressureListenerTag, a closed //base enum used
// only to suppress listeners by field trial; Room takes the tab-loading
// policy's tag (BackgroundTabLoadingPolicy is the other listener that acts
// on tabs under pressure; Room runs without field trials). A tag of its own
// would be a //base patch, which the patch policy rules out.
class RoomMemoryPressureListener : public base::MemoryPressureListener {
 public:
  explicit RoomMemoryPressureListener(RoomApplication* application)
      : application_(application),
        registration_(FROM_HERE,
                      base::MemoryPressureListenerTag::kBackgroundTabLoadingPolicy,
                      this) {}

 protected:
  void OnMemoryPressure(base::MemoryPressureLevel level) override {
    [application_ room_memoryPressureChanged:level];
  }

 private:
  RoomApplication* __weak application_;
  base::MemoryPressureListenerRegistration registration_;
};

}  // namespace

@implementation RoomApplication {
  std::vector<std::string> _arguments;
  Class _applicationClass;
  BOOL _initialized;
  BOOL _running;
  BOOL _exiting;
  id _willTerminateObserver;
  // Waiting for the quit's outcome (-tryToTerminateWithCompletion:).
  NSMutableArray<void (^)(BOOL)>* _terminationCompletions;
  base::CallbackListSubscription _closingAllBrowsersSubscription;
  std::unique_ptr<RoomMemoryPressureListener> _memoryPressureListener;
  RoomMemoryPressureLevel _memoryPressureLevel;
}

@synthesize delegate = _delegate;
@synthesize applicationDelegate = _applicationDelegate;

+ (void)initialize {
  if (self != RoomApplication.class) {
    return;
  }
  // BrowserCrApplication's +initialize reads the command line, and a Swift
  // host triggers it as soon as it names its RoomCrApplication subclass
  // (`RoomHostApplication.self`), before -initializeWithArguments: or -run.
  // -run replaces this with the full argument list.
  base::CommandLine::Init(*_NSGetArgc(), *_NSGetArgv());
}

+ (NSString*)siteForHost:(NSString*)host {
  // GURL canonicalises the host (lower case, IDN to punycode, a trailing
  // dot kept as Chromium keeps it).
  const GURL url("http://" + base::SysNSStringToUTF8(host) + "/");
  if (!url.is_valid() || url.host().empty()) {
    return host.lowercaseString;
  }
  const std::string domain =
      net::registry_controlled_domains::GetDomainAndRegistry(
          url, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  return base::SysUTF8ToNSString(domain.empty() ? std::string(url.host())
                                                : domain);
}

+ (RoomApplication*)sharedApplication {
  static RoomApplication* shared = [[RoomApplication alloc] init];
  return shared;
}

- (BOOL)initializeWithArguments:(NSArray<NSString*>*)arguments
               applicationClass:(Class)applicationClass
              userDataDirectory:(NSURL*)userDataDirectory
                          error:(NSError**)error {
  if (_initialized || ![applicationClass isSubclassOfClass:RoomCrApplication.class]) {
    if (error) {
      NSString* reason =
          _initialized ? @"RoomApplication is already initialized"
                       : @"applicationClass must inherit from RoomCrApplication";
      *error = [NSError errorWithDomain:@"RoomCore"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey : reason}];
    }
    return NO;
  }
  _applicationClass = applicationClass;
  for (NSString* argument in arguments) {
    _arguments.push_back(base::SysNSStringToUTF8(argument));
  }
  if (_arguments.empty()) {
    _arguments.push_back("Room");
  }
  for (const char* item : kDefaultSwitches) {
    _arguments.insert(_arguments.begin() + 1, item);
  }
  NSURL* dataRoot = userDataDirectory ?: DefaultUserDataDirectory();
  [NSFileManager.defaultManager createDirectoryAtURL:dataRoot
                         withIntermediateDirectories:YES
                                          attributes:nil
                                               error:nil];
  // The real path: the helpers' sandbox profiles allow the log file by its
  // literal path, and /tmp is a symlink to /private/tmp.
  if (char* real = realpath(dataRoot.fileSystemRepresentation, nullptr)) {
    dataRoot = [NSURL fileURLWithFileSystemRepresentation:real
                                              isDirectory:YES
                                            relativeToURL:nil];
    free(real);
  }
  _arguments.insert(_arguments.begin() + 1,
                    std::string("--") + switches::kUserDataDir + "=" +
                        dataRoot.fileSystemRepresentation);
  // A log file under the data root unless the host chose where logs go.
  if (!HasSwitch(_arguments, "enable-logging") &&
      !HasSwitch(_arguments, "log-file")) {
    _arguments.push_back("--enable-logging");
    _arguments.push_back(
        std::string("--log-file=") +
        [dataRoot URLByAppendingPathComponent:@"RoomCore.log"]
            .fileSystemRepresentation);
  }
  if (!HasSwitch(_arguments, "use-mock-keychain") && !IsTeamSigned()) {
    _arguments.push_back("--use-mock-keychain");
  }
  _initialized = YES;
  return YES;
}

- (int)run {
  CHECK(_initialized) << "-[RoomApplication run] before initialize";
  CHECK(!_running);
  _running = YES;

  std::vector<const char*> argv;
  for (const std::string& argument : _arguments) {
    argv.push_back(argument.c_str());
  }
  const int argc = static_cast<int>(argv.size());
  argv.push_back(nullptr);

  // The command line exists since +initialize (BrowserCrApplication's
  // +initialize reads it); give it the full argument list now. ChromeMain's
  // own Init() is a no-op.
  base::CommandLine::ForCurrentProcess()->InitFromArgv(argc, argv.data());
  // NSApp is the host's class. Chromium's RegisterBrowserCrApp() finds it
  // already created and of the right kind.
  [_applicationClass sharedApplication];
  // The host's delegate from the start (PLAN §4 Main menu): Chrome's
  // AppController is replaced by //room's (patches/0013) and never becomes
  // NSApp.delegate.
  NSApp.delegate = _applicationDelegate;
  room::InstallAppController();
  room::InstallBrowserWindowFactory();
  room::InstallWebContentsHooks();
  // What Chrome would draw for a Room page goes to the host (3.4a).
  room::InstallPermissionPromptHook();
  room::InstallContextMenuHook();
  room::InstallDownloadTargetHook();
  room::InstallPagePromptHooks();
  room::InstallPageDialogHooks();
  room::InstallExtensionHooks();

  __weak RoomApplication* weakSelf = self;
  _willTerminateObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:NSApplicationWillTerminateNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification*) {
                RoomApplication* strongSelf = weakSelf;
                if (strongSelf) {
                  strongSelf->_memoryPressureListener.reset();
                }
                room::DetachPageServiceObservers();
                [strongSelf room_finishTermination:YES];
                id<RoomApplicationDelegate> delegate = strongSelf.delegate;
                if ([delegate respondsToSelector:@selector
                              (roomApplicationWillTerminate:)]) {
                  [delegate roomApplicationWillTerminate:strongSelf];
                }
              }];

  // Chrome's default crash path ignores --user-data-dir. Keep each host's
  // crash database inside the same selected profile root. Overrides survive
  // ChromeMain's later path-provider registration.
  // -initialize always passes --user-data-dir (the host's or Room's default).
  base::FilePath user_data = base::CommandLine::ForCurrentProcess()
                                 ->GetSwitchValuePath(switches::kUserDataDir);
  CHECK(!user_data.empty());
  CHECK(base::PathService::Override(chrome::DIR_CRASH_DUMPS,
                                    user_data.AppendASCII("Crashpad")));

  auto network_policy = room::InstallNetworkPolicy();
  const int result = ChromeMain(argc, argv.data());

  [NSNotificationCenter.defaultCenter removeObserver:_willTerminateObserver];
  _willTerminateObserver = nil;
  return result;
}

- (void)tryToTerminate {
  [NSApp terminate:nil];
}

- (void)tryToTerminateWithCompletion:(void (^)(BOOL))completion {
  if (_exiting) {
    if (completion) {
      completion(YES);
    }
    return;
  }
  if (!_terminationCompletions) {
    _terminationCompletions = [NSMutableArray array];
  }
  if (completion) {
    [_terminationCompletions addObject:[completion copy]];
  }
  if (!_closingAllBrowsersSubscription) {
    // UnloadController::CancelWindowClose() reports a "stay" here, after
    // BrowserCloseManager::CancelBrowserClose() reset the quit flag.
    __weak RoomApplication* weakSelf = self;
    _closingAllBrowsersSubscription =
        chrome::AddClosingAllBrowsersCallback(base::BindRepeating(^(bool closing) {
          if (!closing && !browser_shutdown::IsTryingToQuit()) {
            [weakSelf room_finishTermination:NO];
          }
        }));
  }
  room::TryToTerminateApplication();
}

- (BOOL)isTerminating {
  return _exiting || browser_shutdown::IsTryingToQuit();
}

- (void)room_finishTermination:(BOOL)terminating {
  if (terminating) {
    _exiting = YES;
  }
  NSArray<void (^)(BOOL)>* completions = [_terminationCompletions copy];
  [_terminationCompletions removeAllObjects];
  if (completions.count) {
    LOG(INFO) << "RoomCore: quit " << (terminating ? "proceeds" : "cancelled")
              << " (" << completions.count << " waiting)";
  }
  for (void (^completion)(BOOL) in completions) {
    completion(terminating);
  }
}

- (NSArray<RoomProfile*>*)profiles {
  NSMutableArray<RoomProfile*>* result = [NSMutableArray array];
  if (!g_browser_process || !g_browser_process->profile_manager()) {
    return result;
  }
  for (Profile* profile :
       g_browser_process->profile_manager()->GetLoadedProfiles()) {
    if (profile->IsOffTheRecord()) {
      continue;
    }
    [result addObject:[RoomProfile room_profileFor:profile]];
  }
  return result;
}

- (RoomProfile*)defaultProfile {
  if (!g_browser_process || !g_browser_process->profile_manager()) {
    return nil;
  }
  Profile* profile = ProfileManager::GetLastUsedProfileIfLoaded();
  if (!profile) {
    return self.profiles.firstObject;
  }
  return [RoomProfile room_profileFor:profile->GetOriginalProfile()];
}

- (void)createProfile:(NSString*)name
           completion:(void (^)(RoomProfile*))completion {
  ProfileManager* manager =
      g_browser_process ? g_browser_process->profile_manager() : nullptr;
  if (!manager || name.length == 0 || [name containsString:@"/"]) {
    completion(nil);
    return;
  }
  base::FilePath path =
      manager->user_data_dir().Append(base::SysNSStringToUTF8(name));
  manager->CreateProfileAsync(path, base::BindOnce(^(Profile* profile) {
                                completion(profile ? [RoomProfile
                                                         room_profileFor:profile]
                                                   : nil);
                              }));
}

- (RoomMemoryPressureLevel)memoryPressureLevel {
  return _memoryPressureLevel;
}

- (void)room_memoryPressureChanged:(base::MemoryPressureLevel)level {
  RoomMemoryPressureLevel mapped = RoomMemoryPressureLevelNone;
  switch (level) {
    case base::MEMORY_PRESSURE_LEVEL_MODERATE:
      mapped = RoomMemoryPressureLevelModerate;
      break;
    case base::MEMORY_PRESSURE_LEVEL_CRITICAL:
      mapped = RoomMemoryPressureLevelCritical;
      break;
    default:
      mapped = RoomMemoryPressureLevelNone;
      break;
  }
  LOG(INFO) << "RoomCore: memory pressure " << static_cast<int>(mapped);
  _memoryPressureLevel = mapped;
  id<RoomApplicationDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(roomApplication:
                                       didChangeMemoryPressure:)]) {
    [delegate roomApplication:self didChangeMemoryPressure:mapped];
  }
}

- (void)room_didFinishLaunching {
  SetCrashKeys();
  // Chromium's memory-pressure monitor and listener registry exist now.
  _memoryPressureListener = std::make_unique<RoomMemoryPressureListener>(self);
  // Chrome installed its Cocoa alert factory in PreProfileInit.
  room::InstallAppModalDialogFactory();
  LOG(INFO) << "RoomCore: NSApp.delegate is "
            << (NSApp.delegate
                    ? base::SysNSStringToUTF8(
                          NSStringFromClass([(NSObject*)NSApp.delegate class]))
                    : std::string("nil"));
  id<RoomApplicationDelegate> delegate = self.delegate;
  [delegate roomApplicationDidFinishLaunching:self];
}

@end
