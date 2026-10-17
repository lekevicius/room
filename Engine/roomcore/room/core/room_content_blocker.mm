// Copyright 2026 Jonas Lekevicius. All rights reserved.
#import "room/core/public/RoomContentBlocker.h"

#include <set>
#include <string>
#include <utility>

#include "base/apple/foundation_util.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "net/base/apple/url_conversions.h"
#include "room/core/content_blocking/content_blocker.h"

namespace {

base::FilePath PathFrom(NSURL* url) {
  return url.isFileURL ? base::apple::NSStringToFilePath(url.path)
                       : base::FilePath();
}

room::CookieBannerMode ModeFrom(RoomCookieBannerMode mode) {
  switch (mode) {
    case RoomCookieBannerModeHide:
      return room::CookieBannerMode::kHide;
    case RoomCookieBannerModeReject:
      return room::CookieBannerMode::kReject;
    case RoomCookieBannerModeOff:
      return room::CookieBannerMode::kOff;
  }
  return room::CookieBannerMode::kOff;
}

}  // namespace

@implementation RoomContentBlockerList
@synthesize fileURL = _fileURL;
@synthesize hostsFormat = _hostsFormat;
@synthesize trusted = _trusted;
- (instancetype)initWithFileURL:(NSURL*)fileURL
                    hostsFormat:(BOOL)hostsFormat
                        trusted:(BOOL)trusted {
  if ((self = [super init])) {
    _fileURL = [fileURL copy];
    _hostsFormat = hostsFormat;
    _trusted = trusted;
  }
  return self;
}
@end

@implementation RoomContentBlockerConfiguration
@synthesize enabled = _enabled;
@synthesize lists = _lists;
@synthesize customRules = _customRules;
@synthesize resourcesURL = _resourcesURL;
@synthesize cacheDirectoryURL = _cacheDirectoryURL;
@synthesize allowedSites = _allowedSites;
@synthesize cookieBanners = _cookieBanners;
@synthesize cookieScriptURL = _cookieScriptURL;
- (instancetype)init {
  if ((self = [super init])) {
    _lists = @[];
    _customRules = @"";
    _allowedSites = @[];
  }
  return self;
}
@end

@implementation RoomContentBlockerReport {
  room::ContentBlockerReport _report;
}
- (instancetype)initWithReport:(room::ContentBlockerReport)report {
  if ((self = [super init])) {
    _report = std::move(report);
  }
  return self;
}
- (BOOL)ok {
  return _report.ok;
}
- (NSString*)problems {
  return base::SysUTF8ToNSString(_report.error);
}
- (BOOL)fromCache {
  return _report.from_cache;
}
- (double)buildMilliseconds {
  return _report.build_milliseconds;
}
- (NSInteger)engineBytes {
  return static_cast<NSInteger>(_report.engine_bytes);
}
@end

@implementation RoomContentBlocker

+ (RoomContentBlocker*)sharedBlocker {
  static RoomContentBlocker* shared = [[RoomContentBlocker alloc] initShared];
  return shared;
}

- (instancetype)initShared {
  return [super init];
}

- (void)applyConfiguration:(RoomContentBlockerConfiguration*)configuration
                completion:(void (^)(RoomContentBlockerReport*))completion {
  room::ContentBlockerConfig config;
  config.enabled = configuration.enabled;
  for (RoomContentBlockerList* list in configuration.lists) {
    config.lists.push_back(room::ContentBlockerList{
        PathFrom(list.fileURL), static_cast<bool>(list.hostsFormat),
        static_cast<bool>(list.trusted)});
  }
  config.custom_rules = base::SysNSStringToUTF8(configuration.customRules);
  config.resources = PathFrom(configuration.resourcesURL);
  config.cache_directory = PathFrom(configuration.cacheDirectoryURL);
  for (NSString* site in configuration.allowedSites) {
    config.allowed_sites.insert(
        base::ToLowerASCII(base::SysNSStringToUTF8(site)));
  }
  config.cookie_banners = ModeFrom(configuration.cookieBanners);
  config.cookie_script = PathFrom(configuration.cookieScriptURL);
  void (^done)(RoomContentBlockerReport*) = [completion copy];
  room::ContentBlocker::Get()->Apply(
      std::move(config),
      base::BindOnce(
          [](void (^done)(RoomContentBlockerReport*),
             room::ContentBlockerReport report) {
            if (done) {
              done([[RoomContentBlockerReport alloc]
                  initWithReport:std::move(report)]);
            }
          },
          done));
}

- (BOOL)wouldBlockURL:(NSURL*)URL
            sourceURL:(NSURL*)sourceURL
          requestType:(NSString*)requestType {
  const std::string type = base::SysNSStringToUTF8(requestType);
  return room::ContentBlocker::Get()
      ->Check(net::GURLWithNSURL(URL), net::GURLWithNSURL(sourceURL), type,
              "GET")
      .block;
}

@end
