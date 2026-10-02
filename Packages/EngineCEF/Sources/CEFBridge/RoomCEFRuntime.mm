#import "CEFBridge.h"

#include <crt_externs.h>

#include <memory>
#include <string>

#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

// Must outlive CefShutdown(); unloads the framework when destroyed.
std::unique_ptr<CefScopedLibraryLoader>& LibraryLoader() {
  static std::unique_ptr<CefScopedLibraryLoader> loader;
  return loader;
}

// Browser-process command-line tweaks applied before Chromium parses them.
class RoomCEFApp : public CefApp {
 public:
  RoomCEFApp(bool use_mock_keychain,
             bool allow_devtools_frontend,
             std::string enabled_features,
             std::string disabled_features)
      : use_mock_keychain_(use_mock_keychain),
        allow_devtools_frontend_(allow_devtools_frontend),
        enabled_features_(std::move(enabled_features)),
        disabled_features_(std::move(disabled_features)) {}

  void OnBeforeCommandLineProcessing(
      const CefString& process_type,
      CefRefPtr<CefCommandLine> command_line) override {
    if (!process_type.empty()) {
      return;
    }
    if (use_mock_keychain_) {
      command_line->AppendSwitch("use-mock-keychain");
    }
    if (allow_devtools_frontend_) {
      // The docked DevTools front-end connects over the debugging port.
      command_line->AppendSwitchWithValue("remote-allow-origins", "devtools://devtools");
    }
    MergeFeatureSwitch(command_line, "enable-features", enabled_features_);
    MergeFeatureSwitch(command_line, "disable-features", disabled_features_);
  }

 private:
  // Appends to a comma-separated feature switch instead of replacing it, so
  // features CEF or the command line already set survive.
  static void MergeFeatureSwitch(CefRefPtr<CefCommandLine> command_line,
                                 const std::string& name,
                                 const std::string& features) {
    if (features.empty()) {
      return;
    }
    std::string value = command_line->GetSwitchValue(name).ToString();
    value += value.empty() ? features : "," + features;
    command_line->AppendSwitchWithValue(name, value);
  }

  const bool use_mock_keychain_;
  const bool allow_devtools_frontend_;
  const std::string enabled_features_;
  const std::string disabled_features_;

  IMPLEMENT_REFCOUNTING(RoomCEFApp);
};

std::string JoinFeatures(NSArray<NSString*>* features) {
  return [features componentsJoinedByString:@","].UTF8String;
}

void SetPath(cef_string_t* target, NSURL* url) {
  if (url) {
    CefString(target).FromString(url.path.fileSystemRepresentation);
  }
}

}  // namespace

@implementation RoomCEFRuntime

+ (BOOL)loadLibrary {
  auto& loader = LibraryLoader();
  if (loader) {
    return YES;
  }
  loader = std::make_unique<CefScopedLibraryLoader>();
  if (!loader->LoadInMain()) {
    loader.reset();
    return NO;
  }
  return YES;
}

+ (BOOL)initializeWithUserDataDirectory:(NSURL*)userDataDirectory
                                logFile:(NSURL*)logFile
                                 locale:(NSString*)locale
                        useMockKeychain:(BOOL)useMockKeychain
                        enabledFeatures:(NSArray<NSString*>*)enabledFeatures
                       disabledFeatures:(NSArray<NSString*>*)disabledFeatures
                    remoteDebuggingPort:(NSInteger)remoteDebuggingPort
                                  error:(NSError**)error {
  // The process's own argv, which lives for the whole process.
  CefMainArgs main_args(*_NSGetArgc(), *_NSGetArgv());

  CefSettings settings;
  settings.no_sandbox = false;
  SetPath(&settings.root_cache_path, userDataDirectory);
  SetPath(&settings.log_file, logFile);
  // 0 = off. Chromium binds it to 127.0.0.1 only.
  settings.remote_debugging_port = static_cast<int>(remoteDebuggingPort);
  if (locale.length) {
    CefString(&settings.locale).FromString(locale.UTF8String);
  }

  CefRefPtr<RoomCEFApp> app(new RoomCEFApp(useMockKeychain, remoteDebuggingPort > 0,
                                           JoinFeatures(enabledFeatures),
                                           JoinFeatures(disabledFeatures)));
  if (!CefInitialize(main_args, settings, app.get(), nullptr)) {
    if (error) {
      *error = [NSError errorWithDomain:@"RoomCEF"
                                   code:CefGetExitCode()
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"CefInitialize failed"
                               }];
    }
    return NO;
  }
  return YES;
}

+ (void)runMessageLoop {
  CefRunMessageLoop();
}

+ (void)quitMessageLoop {
  CefQuitMessageLoop();
}

+ (void)shutdown {
  CefShutdown();
}

@end
