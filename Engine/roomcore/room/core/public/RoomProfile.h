// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import <Foundation/Foundation.h>

#import "RoomExport.h"

@class RoomWebContents;
@class RoomProfileHistory;
@class RoomAutocompleteController;
@class RoomProfileExtensions;

NS_ASSUME_NONNULL_BEGIN
@class RoomProfile;

// A download's state (download::DownloadItem::DownloadState).
typedef NS_ENUM(NSInteger, RoomDownloadState) {
  RoomDownloadStateInProgress = 0,
  RoomDownloadStateComplete,
  RoomDownloadStateCancelled,
  RoomDownloadStateInterrupted,
};

// A snapshot of one download (download::DownloadItem); a new one arrives
// with every update.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomDownloadItem : NSObject
- (instancetype)init NS_UNAVAILABLE;
// Chrome's GUID: stable across relaunches (the downloads history).
@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSURL* URL;
// The name Chrome would give the file (Content-Disposition, the page's
// download attribute, the URL), before the host picks a path.
@property(nonatomic, readonly, copy) NSString* suggestedFilename;
// The file being written; nil until the target is decided.
@property(nonatomic, readonly, copy, nullable) NSURL* destination;
@property(nonatomic, readonly, copy, nullable) NSString* mimeType;
@property(nonatomic, readonly) int64_t receivedBytes;
// -1 when the server sent no length.
@property(nonatomic, readonly) int64_t totalBytes;
// Bytes per second.
@property(nonatomic, readonly) int64_t currentSpeed;
@property(nonatomic, readonly) RoomDownloadState state;
@property(nonatomic, readonly, getter=isPaused) BOOL paused;
// DownloadItem::CanResume: an interrupted or paused download may continue.
@property(nonatomic, readonly) BOOL canResume;
@property(nonatomic, readonly, copy) NSDate* startTime;
@end

// Receives a profile's downloads. Called on the main thread.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@protocol RoomProfileDownloadsDelegate <NSObject>
// A new download (DownloadManagerDelegate::DetermineDownloadTarget): the
// host picks the file; `completion(nil)` cancels it. Chrome shows no Save
// panel and gives no danger verdict.
- (void)profile:(RoomProfile*)profile
    willBeginDownload:(RoomDownloadItem*)item
           completion:(void (^)(NSURL* _Nullable destination))completion
    NS_SWIFT_NAME(profile(_:willBeginDownload:completion:));
// Progress, pause and resume, completion, cancellation, interruption; also
// every download Chrome's history restored (once, when the delegate is set
// or the history has loaded).
- (void)profile:(RoomProfile*)profile
    didUpdateDownload:(RoomDownloadItem*)item
    NS_SWIFT_NAME(profile(_:didUpdateDownload:));
@end

// The site permissions the host's site panel shows (Chrome's
// ContentSettingsType).
typedef NS_ENUM(NSInteger, RoomContentSettingType) {
  RoomContentSettingTypeGeolocation = 0,
  RoomContentSettingTypeCamera,
  RoomContentSettingTypeMicrophone,
  RoomContentSettingTypeNotifications,
  RoomContentSettingTypeClipboard,
  RoomContentSettingTypeSensors,
  RoomContentSettingTypeMidiSysex,
  RoomContentSettingTypePopups,
  RoomContentSettingTypeSound,
  RoomContentSettingTypeAutomaticDownloads,
  RoomContentSettingTypeJavaScript,
  RoomContentSettingTypeImages,
};

// A site's stored setting; Default when it has none (ContentSetting).
typedef NS_ENUM(NSInteger, RoomContentSetting) {
  RoomContentSettingDefault = 0,
  RoomContentSettingAllow,
  RoomContentSettingBlock,
  RoomContentSettingAsk,
};

// What -clearSiteData:forOrigin:completion: removes.
typedef NS_OPTIONS(NSUInteger, RoomSiteDataTypes) {
  RoomSiteDataTypeCookies = 1 << 0,
  RoomSiteDataTypeCache = 1 << 1,
  // Local and session storage, IndexedDB, Cache Storage, service workers.
  RoomSiteDataTypeStorage = 1 << 2,
  RoomSiteDataTypeHTTPAuthCredentials = 1 << 3,
  // Site permissions and certificate decisions ("Visit anyway").
  RoomSiteDataTypePermissions = 1 << 4,
};

// What -clearBrowsingData:since:completion: removes (Chrome's Clear browsing
// data kinds).
typedef NS_OPTIONS(NSUInteger, RoomBrowsingDataTypes) {
  RoomBrowsingDataTypeHistory = 1 << 0,
  // Cookies and site storage (Chrome's DATA_TYPE_SITE_DATA).
  RoomBrowsingDataTypeCookiesAndSiteData = 1 << 1,
  RoomBrowsingDataTypeCache = 1 << 2,
  // The downloads list (the files stay on disk).
  RoomBrowsingDataTypeDownloads = 1 << 3,
  // Autofill's form entries and addresses (DATA_TYPE_FORM_DATA).
  RoomBrowsingDataTypeAutofill = 1 << 4,
  RoomBrowsingDataTypePasswords = 1 << 5,
};

// How far back -clearBrowsingData:since:completion: goes
// (browsing_data::TimePeriod).
typedef NS_ENUM(NSInteger, RoomBrowsingDataPeriod) {
  RoomBrowsingDataPeriodLastHour = 0,
  RoomBrowsingDataPeriodLastDay,
  RoomBrowsingDataPeriodLastWeek,
  RoomBrowsingDataPeriodFourWeeks,
  RoomBrowsingDataPeriodAllTime,
};

// A Chromium Profile: cookie jar, history, settings, extensions.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomProfile : NSObject

- (instancetype)init NS_UNAVAILABLE;

// Directory basename under the user data directory, e.g. "Default".
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSURL* directory;
@property(nonatomic, readonly, getter=isOffTheRecord) BOOL offTheRecord;

// Whether this profile's previous session ended cleanly: Chrome's
// ExitTypeService (the profile's exit_type pref, "Normal" after a clean quit,
// "Crashed" after a crash or a kill). Read when RoomCore first hands out the
// profile; it does not change during the session. RoomCore then acknowledges
// the crash on the host's behalf (the host restores its own state), so a
// clean quit of this session records "Normal" again.
@property(nonatomic, readonly) BOOL lastExitWasClean;

// A new page with nothing loaded. Owned by the returned object until it is
// added to a RoomBrowser.
- (RoomWebContents*)createWebContents;
// The same, hidden until its view is in a visible window
// (WebContents::CreateParams::initially_hidden): no frames, timers
// throttled.
- (RoomWebContents*)createWebContentsInitiallyHidden:(BOOL)initiallyHidden
    NS_SWIFT_NAME(createWebContents(initiallyHidden:));

// The favicon Chrome stored for a page this profile visited
// (FaviconService); nil when none. Called back on the main thread.
- (void)faviconForPageURL:(NSURL*)pageURL
               completion:(void (^)(NSImage* _Nullable favicon))completion
    NS_SWIFT_NAME(favicon(forPageURL:completion:));

// Receives this profile's downloads (Chrome's DownloadManager; the history
// of earlier sessions is replayed through -profile:didUpdateDownload:).
// Without one, Chrome decides the downloads' files itself.
@property(nonatomic, weak, nullable) id<RoomProfileDownloadsDelegate>
    downloadsDelegate;
// Every download Chrome knows in this profile, its history included.
@property(nonatomic, readonly) NSArray<RoomDownloadItem*>* downloads;
// download::DownloadItem::Pause / Resume / Cancel by identifier.
- (void)pauseDownload:(NSString*)identifier;
- (void)resumeDownload:(NSString*)identifier;
- (void)cancelDownload:(NSString*)identifier;
// download::DownloadItem::Remove by identifier (4.1b): the download leaves
// Chrome's list and its history database (DownloadHistory), so the next
// launch does not list it; a finished file stays on disk, a partial one is
// deleted. No further update is reported for it.
- (void)removeDownload:(NSString*)identifier;

// The setting stored for `origin` (HostContentSettingsMap), Default when the
// site has none.
- (RoomContentSetting)contentSettingForType:(RoomContentSettingType)type
                                     origin:(NSURL*)origin
    NS_SWIFT_NAME(contentSetting(for:origin:));
// Stores `setting` for `origin`; Default removes the site's setting.
- (void)setContentSetting:(RoomContentSetting)setting
                  forType:(RoomContentSettingType)type
                   origin:(NSURL*)origin
    NS_SWIFT_NAME(setContentSetting(_:for:origin:));
// Every site with its own setting for `type` (4.4b): the rules
// HostContentSettingsMap::GetSettingsForOneType has from the user's
// preferences whose site pattern is not the wildcard, as dictionaries of
// Foundation values (no class of its own):
//   @"pattern"  NSString: the site pattern (ContentSettingsPattern::ToString);
//   @"origin"   NSURL: a URL the pattern matches (ToRepresentativeUrl;
//               absent when it has none), for -setContentSetting:…;
//   @"setting"  NSNumber: a RoomContentSetting (Allow, Block or Ask);
//   @"embedded" NSNumber (BOOL): the secondary pattern is not the wildcard.
- (NSArray<NSDictionary<NSString*, id>*>*)contentSettingsForType:
    (RoomContentSettingType)type NS_SWIFT_NAME(contentSettings(for:));
// Chrome's Clear browsing data (4.4b): BrowsingDataRemover with Chrome's
// data types for `types`, every site, web origins protected or not, from the
// start of `period` until now; completion on the main thread once Chrome has.
- (void)clearBrowsingData:(RoomBrowsingDataTypes)types
                    since:(RoomBrowsingDataPeriod)period
               completion:(void (^)(void))completion
    NS_SWIFT_NAME(clearBrowsingData(_:since:completion:));
// Removes site data of `types` for `origin` (nil: every site); completion
// on the main thread once Chrome has.
- (void)clearSiteData:(RoomSiteDataTypes)types
            forOrigin:(nullable NSURL*)origin
           completion:(void (^)(void))completion
    NS_SWIFT_NAME(clearSiteData(_:for:completion:));

// Chrome's history for this profile (HistoryService; RoomOmnibox.h); nil
// for an off-the-record profile.
@property(nonatomic, readonly, nullable) RoomProfileHistory* history;
// A new omnibox AutocompleteController for one address field
// (RoomOmnibox.h); nil for an off-the-record profile.
- (nullable RoomAutocompleteController*)makeAutocompleteController;
// Makes Room's engine the profile's default search engine
// (TemplateURLService): SearchProvider's suggestions and its search matches
// use it. Templates take Chrome's {searchTerms}; `suggestURL` nil means no
// suggestions endpoint. The keyword names the engine (a different keyword is
// a different engine; the host's own site-search keywords stay the host's).
- (void)setDefaultSearchEngineWithName:(NSString*)name
                               keyword:(NSString*)keyword
                             searchURL:(NSString*)searchURL
                            suggestURL:(nullable NSString*)suggestURL
    NS_SWIFT_NAME(setDefaultSearchEngine(name:keyword:searchURL:suggestURL:));
// Chrome's search-suggest preference (prefs::kSearchSuggestEnabled); the
// host mirrors its suggestions switch here as well as choosing providers.
@property(nonatomic) BOOL searchSuggestEnabled;

// Chrome's extension system for this profile (RoomExtensions.h); nil for an
// off-the-record profile.
@property(nonatomic, readonly, nullable) RoomProfileExtensions* extensions;

// Imports passwords from `csv` (Chrome's export format: a header naming the
// columns, `name,url,username,password,note`, with Chrome's aliases such as
// `login_uri`, `origin`, `login_username`) into this profile's password
// store through Chrome's PasswordImporter (4.3b). The importer validates and
// parses the text off the main thread. A row whose site and username are
// saved with a different password is a conflict: all of them are replaced
// (`replaceConflicts`) or all kept. `completion` runs once on the main thread
// with a dictionary of Foundation values (no class of its own):
//   @"status"    NSString: "success", "badFormat" (no usable header),
//                "tooLarge" (over 1000 KB), "tooMany" (over Chrome's row
//                limit), "unreadable", "busy" (an import is running),
//                "unavailable" (no password store, off the record), "failed";
//   @"imported"  NSNumber: rows now saved, Chrome's count (a row already
//                saved with the same password counts, a replaced one too);
//   @"conflicts" NSNumber: conflicting rows; @"replaced" NSNumber: of those,
//                replaced;
//   @"rows"      NSArray of NSDictionary {@"url", @"username", @"reason"}:
//                each row not added as given, `reason` "conflictKept",
//                "conflictReplaced", "missingURL", "invalidURL",
//                "missingPassword", "longURL", "longUsername", "longPassword",
//                "longNote" or "malformed". Never a password.
// Absent keys mean 0 or none (a failed import has only @"status").
- (void)importPasswordsFromCSV:(NSString*)csv
              replaceConflicts:(BOOL)replaceConflicts
                    completion:
                        (void (^)(NSDictionary<NSString*, id>* result))completion
    NS_SWIFT_NAME(importPasswords(csv:replaceConflicts:completion:));

@end

NS_ASSUME_NONNULL_END
