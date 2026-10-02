// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/public/RoomCore.h"

#include "chrome/common/chrome_version.h"

const char* RoomCoreChromiumVersion(void) {
  return CHROME_VERSION_STRING;
}
