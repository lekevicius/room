// Copyright 2026 Jonas Lekevicius. All rights reserved.

// Chrome's history and omnibox for the host's palette (Phase 3.5): a
// profile's HistoryService and AutocompleteController behind Foundation
// types. Every class is main-thread only; every completion and delegate call
// arrives on the main thread.

#import <Foundation/Foundation.h>

#import "RoomExport.h"

NS_ASSUME_NONNULL_BEGIN

@class RoomAutocompleteController;

// How a visit started, as history keeps it (ui::PageTransition's core type).
typedef NS_ENUM(NSInteger, RoomHistoryTransition) {
  RoomHistoryTransitionLink = 0,
  RoomHistoryTransitionTyped,
  RoomHistoryTransitionBookmark,
  RoomHistoryTransitionGenerated,
  RoomHistoryTransitionKeyword,
  RoomHistoryTransitionFormSubmit,
  RoomHistoryTransitionReload,
  RoomHistoryTransitionOther,
};

// One URL in history (history::URLRow / URLResult).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomHistoryEntry : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSURL* URL;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly) NSInteger visitCount;
@property(nonatomic, readonly) NSInteger typedCount;
// The last visit (for a query by time: the visit inside the range).
@property(nonatomic, readonly, copy, nullable) NSDate* lastVisit;
@end

// One visit of a URL (history::VisitRow).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomHistoryVisit : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTime:(NSDate*)time
                  transition:(RoomHistoryTransition)transition
    NS_DESIGNATED_INITIALIZER;
@property(nonatomic, readonly, copy) NSDate* time;
@property(nonatomic, readonly) RoomHistoryTransition transition;
@end

// A URL to import with its visits (the host's Chapter 2 history); its
// visit and typed counts are its visits' (reloads are not visits).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomHistoryImportEntry : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithURL:(NSURL*)URL
                      title:(nullable NSString*)title
                     visits:(NSArray<RoomHistoryVisit*>*)visits
    NS_DESIGNATED_INITIALIZER;
@property(nonatomic, readonly, copy) NSURL* URL;
@property(nonatomic, readonly, copy, nullable) NSString* title;
@property(nonatomic, readonly, copy) NSArray<RoomHistoryVisit*>* visits;
@end

// What an import added.
typedef struct {
  NSInteger urls;
  NSInteger visits;
  // Visits older than Chrome keeps (90 days): not imported.
  NSInteger expiredVisits;
  // URLs whose every visit was older than that.
  NSInteger expiredURLs;
} RoomHistoryImportResult;

// A profile's HistoryService (HistoryServiceFactory, EXPLICIT_ACCESS).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomProfileHistory : NSObject
- (instancetype)init NS_UNAVAILABLE;

// URLs whose title or URL contain every word of `text` (QueryHistory with
// the text, duplicates removed), most recent first.
- (void)searchText:(NSString*)text
          maxCount:(NSInteger)maxCount
        completion:(void (^)(NSArray<RoomHistoryEntry*>* entries))completion
    NS_SWIFT_NAME(search(_:maxCount:completion:));
// URLs visited in [begin, end) (nil: unbounded), most recent first.
- (void)entriesFrom:(nullable NSDate*)begin
                 to:(nullable NSDate*)end
           maxCount:(NSInteger)maxCount
         completion:(void (^)(NSArray<RoomHistoryEntry*>* entries))completion
    NS_SWIFT_NAME(entries(from:to:maxCount:completion:));
// The URL's row and its visits (QueryURLAndVisits); nil when not in history.
- (void)visitsForURL:(NSURL*)URL
          completion:(void (^)(RoomHistoryEntry* _Nullable entry,
                               NSArray<RoomHistoryVisit*>* visits))completion
    NS_SWIFT_NAME(visits(for:completion:));
// The most visited URLs, recent visits counting more (QueryMostVisitedURLs,
// TopSites' scoring).
- (void)mostVisitedWithMaxCount:(NSInteger)maxCount
                     completion:
                         (void (^)(NSArray<RoomHistoryEntry*>* entries))
                             completion
    NS_SWIFT_NAME(mostVisited(maxCount:completion:));
// Deletes the URLs and their visits (DeleteURLs).
- (void)deleteURLs:(NSArray<NSURL*>*)URLs;
// Deletes every URL of `host` ("www." and the scheme ignored; QueryHistory
// with host_only, then DeleteURLs); completion with how many.
- (void)deleteHost:(NSString*)host
        completion:(void (^)(NSInteger deleted))completion;
// Adds URLs with their titles, counts and visits (AddPagesWithDetails for
// the rows, then the earlier visits with their times in a HistoryDBTask);
// the omnibox index learns them as from browsing. Visits older than 90 days
// are left out, as Chrome expires them.
- (void)importEntries:(NSArray<RoomHistoryImportEntry*>*)entries
           completion:(void (^)(RoomHistoryImportResult result))completion;
@end

// Which providers a query asks (AutocompleteProvider::Type).
typedef NS_OPTIONS(NSUInteger, RoomAutocompleteProviders) {
  RoomAutocompleteProviderHistoryQuick = 1 << 0,
  RoomAutocompleteProviderHistoryURL = 1 << 1,
  RoomAutocompleteProviderBookmark = 1 << 2,
  RoomAutocompleteProviderShortcuts = 1 << 3,
  RoomAutocompleteProviderOpenTab = 1 << 4,
  // Search suggestions from the default engine (network: the host asks for
  // it only when its suggestions switch is on).
  RoomAutocompleteProviderSearch = 1 << 5,
};

// AutocompleteMatchType, reduced to what the host tells apart.
typedef NS_ENUM(NSInteger, RoomAutocompleteMatchType) {
  RoomAutocompleteMatchTypeOther = 0,
  RoomAutocompleteMatchTypeURLWhatYouTyped,
  RoomAutocompleteMatchTypeHistoryURL,
  RoomAutocompleteMatchTypeHistoryTitle,
  RoomAutocompleteMatchTypeHistoryBody,
  RoomAutocompleteMatchTypeHistoryKeyword,
  RoomAutocompleteMatchTypeNavSuggest,
  RoomAutocompleteMatchTypeSearchWhatYouTyped,
  RoomAutocompleteMatchTypeSearchHistory,
  RoomAutocompleteMatchTypeSearchSuggest,
  RoomAutocompleteMatchTypeSearchOtherEngine,
  RoomAutocompleteMatchTypeBookmarkTitle,
  RoomAutocompleteMatchTypeOpenTab,
};

// One match of the published result (AutocompleteMatch).
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomAutocompleteMatch : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly, copy) NSString* contents;
@property(nonatomic, readonly, copy) NSString* matchDescription;
@property(nonatomic, readonly, copy, nullable) NSURL* destinationURL;
@property(nonatomic, readonly, copy) NSString* fillIntoEdit;
// What completes the text inline after the cursor; empty when nothing.
@property(nonatomic, readonly, copy) NSString* inlineAutocompletion;
@property(nonatomic, readonly) NSInteger relevance;
@property(nonatomic, readonly) RoomAutocompleteMatchType type;
// The provider that made it (one of RoomAutocompleteProviders; 0 for a
// provider the host does not ask).
@property(nonatomic, readonly) RoomAutocompleteProviders provider;
@property(nonatomic, readonly, getter=isDeletable) BOOL deletable;
// The destination is open in a tab of a Room Browser (TabMatcher).
@property(nonatomic, readonly) BOOL hasTabMatch;
@property(nonatomic, readonly) BOOL allowedToBeDefault;
@end

ROOM_EXPORT NS_SWIFT_UI_ACTOR
@protocol RoomAutocompleteControllerDelegate <NSObject>
// The published result changed (OnResultChanged): once from inside
// -start… with the synchronous pass, then as asynchronous providers answer.
- (void)autocompleteControllerDidUpdateResult:
    (RoomAutocompleteController*)controller;
@end

// One omnibox AutocompleteController with ChromeAutocompleteProviderClient,
// for one address field.
ROOM_EXPORT NS_SWIFT_UI_ACTOR
@interface RoomAutocompleteController : NSObject
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, weak, nullable) id<RoomAutocompleteControllerDelegate>
    delegate;
// Starts a query (AutocompleteController::Start) with only `providers`
// (Chrome fixes a controller's providers at construction: RoomCore keeps one
// per provider set it was asked for and stops the others).
- (void)startWithText:(NSString*)text
               cursorPosition:(NSInteger)cursorPosition
    preventInlineAutocomplete:(BOOL)preventInlineAutocomplete
                  keywordMode:(BOOL)keywordMode
                    providers:(RoomAutocompleteProviders)providers
    NS_SWIFT_NAME(start(text:cursorPosition:preventInlineAutocomplete:keywordMode:providers:));
// Stops the query; the result stays.
- (void)stop;
// The published result, the default match first when there is one.
@property(nonatomic, readonly, copy) NSArray<RoomAutocompleteMatch*>* matches;
// No provider is still working on the last query.
@property(nonatomic, readonly, getter=isDone) BOOL done;
// Asks the match's provider to delete it (history: the URL).
- (void)deleteMatchAtIndex:(NSInteger)index;
@end

NS_ASSUME_NONNULL_END
