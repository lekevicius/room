// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <Foundation/Foundation.h>

#import "RoomExport.h"

@class RoomWebContents;

NS_ASSUME_NONNULL_BEGIN

// A Chromium Profile: cookie jar, history, settings, extensions.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomProfile : NSObject

- (instancetype)init NS_UNAVAILABLE;

// Directory basename under the user data directory, e.g. "Default".
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSURL* directory;
@property(nonatomic, readonly, getter=isOffTheRecord) BOOL offTheRecord;

// A new page with nothing loaded. Owned by the returned object until it is
// added to a RoomBrowser.
- (RoomWebContents*)createWebContents;

@end

NS_ASSUME_NONNULL_END
