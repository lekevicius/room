// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Umbrella header of RoomCore.framework: Room's Chromium fork behind an
// Objective-C API. Only Foundation/AppKit types and C structs cross this
// boundary; every class is main-thread only (NS_SWIFT_UI_ACTOR) and every
// callback arrives on the main thread.

#import <AppKit/AppKit.h>

#import "RoomExport.h"
#import "RoomApplication.h"
#import "RoomBrowser.h"
#import "RoomCrApplication.h"
#import "RoomExtensions.h"
#import "RoomOmnibox.h"
#import "RoomProfile.h"
#import "RoomWebContents.h"

NS_ASSUME_NONNULL_BEGIN

// The Chromium version the framework was built from, e.g. "154.0.8037.58".
FOUNDATION_EXPORT const char* RoomCoreChromiumVersion(void);

NS_ASSUME_NONNULL_END
