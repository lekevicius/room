// Copyright 2026 Jonas Lekevicius. All rights reserved.

#include "chrome/common/chrome_version.h"

// The Chromium version RoomCore was built from, for the host's About box and
// logs. Exported for the Swift host.
extern "C" __attribute__((visibility("default"))) const char*
RoomCoreChromiumVersion() {
  return CHROME_VERSION_STRING;
}
