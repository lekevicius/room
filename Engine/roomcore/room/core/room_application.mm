// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/room_application_internal.h"

#include <crt_externs.h>

#include <string>
#include <vector>

#include "base/check.h"
#include "base/command_line.h"
#include "base/files/file_path.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/common/chrome_switches.h"
#import "room/browser/room_browser_window.h"
#import "room/core/public/RoomCrApplication.h"
#import "room/core/room_profile_internal.h"

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

}  // namespace

@implementation RoomApplication {
  std::vector<std::string> _arguments;
  Class _applicationClass;
  BOOL _initialized;
  BOOL _running;
  id _willTerminateObserver;
}

@synthesize delegate = _delegate;

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
  if (userDataDirectory) {
    _arguments.insert(_arguments.begin() + 1,
                      std::string("--") + switches::kUserDataDir + "=" +
                          userDataDirectory.fileSystemRepresentation);
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
  room::InstallBrowserWindowFactory();

  __weak RoomApplication* weakSelf = self;
  _willTerminateObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:NSApplicationWillTerminateNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification*) {
                RoomApplication* strongSelf = weakSelf;
                id<RoomApplicationDelegate> delegate = strongSelf.delegate;
                if ([delegate respondsToSelector:@selector
                              (roomApplicationWillTerminate:)]) {
                  [delegate roomApplicationWillTerminate:strongSelf];
                }
              }];

  const int result = ChromeMain(argc, argv.data());

  [NSNotificationCenter.defaultCenter removeObserver:_willTerminateObserver];
  _willTerminateObserver = nil;
  return result;
}

- (void)tryToTerminate {
  [NSApp terminate:nil];
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

- (void)room_didFinishLaunching {
  id<RoomApplicationDelegate> delegate = self.delegate;
  [delegate roomApplicationDidFinishLaunching:self];
}

@end
