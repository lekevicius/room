#import "CEFBridge.h"

#include <crt_externs.h>

#include <memory>

#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

// Must outlive CefShutdown(); unloads the framework when destroyed.
std::unique_ptr<CefScopedLibraryLoader>& LibraryLoader() {
  static std::unique_ptr<CefScopedLibraryLoader> loader;
  return loader;
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
                                  error:(NSError**)error {
  // The process's own argv, which lives for the whole process.
  CefMainArgs main_args(*_NSGetArgc(), *_NSGetArgv());

  CefSettings settings;
  settings.no_sandbox = false;
  SetPath(&settings.root_cache_path, userDataDirectory);
  SetPath(&settings.log_file, logFile);
  if (locale.length) {
    CefString(&settings.locale).FromString(locale.UTF8String);
  }

  if (!CefInitialize(main_args, settings, nullptr, nullptr)) {
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
