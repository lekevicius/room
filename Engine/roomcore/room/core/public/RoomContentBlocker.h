// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_PUBLIC_ROOMCONTENTBLOCKER_H_
#define ROOM_CORE_PUBLIC_ROOMCONTENTBLOCKER_H_

#import <Foundation/Foundation.h>

#import "RoomExport.h"

NS_ASSUME_NONNULL_BEGIN

// Room's built-in ad and tracker blocker (B-30): adblock-rust in the browser
// process, one engine for every profile. The host owns the lists (files it
// bundled or downloaded when the user asked) and every setting; RoomCore
// never fetches anything for it.

typedef NS_ENUM(NSInteger, RoomCookieBannerMode) {
  RoomCookieBannerModeOff = 0,
  // Only the cookie list's hiding rules (they are among the host's lists).
  RoomCookieBannerModeHide = 1,
  // DuckDuckGo's autoconsent opts out of the banner's purposes, then hides it.
  RoomCookieBannerModeReject = 2,
};

NS_SWIFT_UI_ACTOR
ROOM_EXPORT
@interface RoomContentBlockerList : NSObject
- (instancetype)initWithFileURL:(NSURL*)fileURL
                    hostsFormat:(BOOL)hostsFormat
                        trusted:(BOOL)trusted NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSURL* fileURL;
// One hostname per line (HOSTS files) instead of filter syntax.
@property(nonatomic, readonly) BOOL hostsFormat;
// The list may use privileged scriptlets.
@property(nonatomic, readonly) BOOL trusted;
@end

NS_SWIFT_UI_ACTOR
ROOM_EXPORT
@interface RoomContentBlockerConfiguration : NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic, copy) NSArray<RoomContentBlockerList*>* lists;
// Filter syntax, one rule per line (Settings ▸ Privacy ▸ Custom Rules).
@property(nonatomic, copy) NSString* customRules;
// adblock-rust's resources JSON (scriptlets and redirect bodies).
@property(nonatomic, copy, nullable) NSURL* resourcesURL;
// Where the built engine is cached between launches.
@property(nonatomic, copy, nullable) NSURL* cacheDirectoryURL;
// Registrable domains ("example.co.uk") where nothing is blocked.
@property(nonatomic, copy) NSArray<NSString*>* allowedSites;
@property(nonatomic) RoomCookieBannerMode cookieBanners;
// Room's autoconsent bundle, its rules inside (Reject only).
@property(nonatomic, copy, nullable) NSURL* cookieScriptURL;
@end

NS_SWIFT_UI_ACTOR
ROOM_EXPORT
@interface RoomContentBlockerReport : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) BOOL ok;
// Unreadable files, one per line; empty when every file was read.
@property(nonatomic, readonly, copy) NSString* problems;
// The engine came from the cache (or was unchanged) rather than the text.
@property(nonatomic, readonly) BOOL fromCache;
@property(nonatomic, readonly) double buildMilliseconds;
@property(nonatomic, readonly) NSInteger engineBytes;
@end

NS_SWIFT_UI_ACTOR
ROOM_EXPORT
@interface RoomContentBlocker : NSObject
@property(class, nonatomic, readonly) RoomContentBlocker* sharedBlocker;
- (instancetype)init NS_UNAVAILABLE;
// Replaces the configuration; the completion runs once the new engine is in
// use (building from text takes a few hundred milliseconds for EasyList and
// EasyPrivacy; a cached engine loads in a few). Allowed sites and the
// cookie-banner mode apply to documents committed after the call.
- (void)applyConfiguration:(RoomContentBlockerConfiguration*)configuration
                completion:(void (^)(RoomContentBlockerReport* report))completion;
// What the network proxy would decide for one request (diagnostics):
// `requestType` is "script", "image", "stylesheet", "sub_frame",
// "xmlhttprequest", "ping", "media", "font", "object" or "other".
- (BOOL)wouldBlockURL:(NSURL*)URL
            sourceURL:(NSURL*)sourceURL
          requestType:(NSString*)requestType;
@end

NS_ASSUME_NONNULL_END

#endif  // ROOM_CORE_PUBLIC_ROOMCONTENTBLOCKER_H_
