#include "CEFHelper.h"

#include "include/cef_app.h"
#include "include/cef_sandbox_mac.h"
#include "include/wrapper/cef_library_loader.h"

int RoomCEFHelperMain(int argc, char* argv[]) {
  // Enters the Seatbelt sandbox via ../../../Chromium Embedded
  // Framework.framework/Libraries/libcef_sandbox.dylib; must come first.
  CefScopedSandboxContext sandbox_context;
  if (!sandbox_context.Initialize(argc, argv)) {
    return 1;
  }

  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }

  CefMainArgs main_args(argc, argv);
  return CefExecuteProcess(main_args, nullptr, nullptr);
}
