// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_BRANDING_ROOM_BRANDED_STRINGS_H_
#define ROOM_BRANDING_ROOM_BRANDED_STRINGS_H_

#include <string>

namespace room {

// Overrides every locale string that names Chromium as the product with Room's name
// (B-103). Called once in the browser process after the resource bundle has its locale and
// before any WebUI page or dialog asks for a string (ChromeBrowserMainPartsMac's
// PreCreateThreads, through //room's AppController hook).
void InstallBrandedStrings();

// The rule, for tests and the log: "Chromium" becomes the product name except in the
// open-source attribution ("the Chromium open source project", "The Chromium Authors")
// and Chromium OS's name.
std::u16string RebrandString(const std::u16string& text);

}  // namespace room

#endif  // ROOM_BRANDING_ROOM_BRANDED_STRINGS_H_
