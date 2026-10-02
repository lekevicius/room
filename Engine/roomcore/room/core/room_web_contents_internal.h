// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_
#define ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_

#import "room/core/public/RoomWebContents.h"

#include <memory>

namespace content {
class WebContents;
}

@interface RoomWebContents (Internal)
// A page the wrapper owns until -room_releaseWebContents.
- (instancetype)initWithChromeWebContents:
                    (std::unique_ptr<content::WebContents>)webContents
                                 profile:(RoomProfile*)profile;
// The wrapper of `webContents`, if one was created.
+ (RoomWebContents*)room_existingWrapperFor:(content::WebContents*)webContents;
// Hands ownership to a tab strip; nullptr if the wrapper does not own it.
- (std::unique_ptr<content::WebContents>)room_releaseWebContents;
@property(nonatomic, readonly) content::WebContents* room_webContents;
@end

#endif  // ROOM_CORE_ROOM_WEB_CONTENTS_INTERNAL_H_
