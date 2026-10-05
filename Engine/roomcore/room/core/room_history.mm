// Copyright 2026 Jonas Lekevicius. All rights reserved.

// RoomProfileHistory (Phase 3.5): a profile's HistoryService behind
// Foundation types. Every query answers on a CancelableTaskTracker callback
// on the UI (main) thread; the tracker goes with the profile.

#import "room/core/room_omnibox_internal.h"

#include <algorithm>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/cancelable_task_tracker.h"
#include "base/time/time.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/history/core/browser/history_backend.h"
#include "components/history/core/browser/history_database.h"
#include "components/history/core/browser/history_db_task.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_types.h"
#include "components/history/core/browser/url_row.h"
#include "components/keyed_service/core/service_access_type.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace {

NSDate* NSDateFromTime(base::Time time) {
  return time.is_null() ? nil : time.ToNSDate();
}

RoomHistoryTransition TransitionFrom(ui::PageTransition transition) {
  switch (ui::PageTransitionStripQualifier(transition)) {
    case ui::PAGE_TRANSITION_LINK:
      return RoomHistoryTransitionLink;
    case ui::PAGE_TRANSITION_TYPED:
      return RoomHistoryTransitionTyped;
    case ui::PAGE_TRANSITION_AUTO_BOOKMARK:
      return RoomHistoryTransitionBookmark;
    case ui::PAGE_TRANSITION_GENERATED:
      return RoomHistoryTransitionGenerated;
    case ui::PAGE_TRANSITION_KEYWORD:
    case ui::PAGE_TRANSITION_KEYWORD_GENERATED:
      return RoomHistoryTransitionKeyword;
    case ui::PAGE_TRANSITION_FORM_SUBMIT:
      return RoomHistoryTransitionFormSubmit;
    case ui::PAGE_TRANSITION_RELOAD:
      return RoomHistoryTransitionReload;
    default:
      return RoomHistoryTransitionOther;
  }
}

ui::PageTransition TransitionTo(RoomHistoryTransition transition) {
  ui::PageTransition core = ui::PAGE_TRANSITION_LINK;
  switch (transition) {
    case RoomHistoryTransitionLink:
      core = ui::PAGE_TRANSITION_LINK;
      break;
    case RoomHistoryTransitionTyped:
      core = ui::PAGE_TRANSITION_TYPED;
      break;
    case RoomHistoryTransitionBookmark:
      core = ui::PAGE_TRANSITION_AUTO_BOOKMARK;
      break;
    case RoomHistoryTransitionGenerated:
      core = ui::PAGE_TRANSITION_GENERATED;
      break;
    case RoomHistoryTransitionKeyword:
      core = ui::PAGE_TRANSITION_KEYWORD;
      break;
    case RoomHistoryTransitionFormSubmit:
      core = ui::PAGE_TRANSITION_FORM_SUBMIT;
      break;
    case RoomHistoryTransitionReload:
      core = ui::PAGE_TRANSITION_RELOAD;
      break;
    case RoomHistoryTransitionOther:
      core = ui::PAGE_TRANSITION_LINK;
      break;
  }
  // A visit of its own (no redirect chain), as Chrome records a top-level
  // navigation without redirects.
  return ui::PageTransitionFromInt(core | ui::PAGE_TRANSITION_CHAIN_START |
                                   ui::PAGE_TRANSITION_CHAIN_END);
}

// "www." and the case do not count when the host deletes a site.
std::string BareHost(std::string_view host) {
  std::string lower = base::ToLowerASCII(host);
  return base::StartsWith(lower, "www.") ? lower.substr(4) : lower;
}

// The visits AddPagesWithDetails cannot carry: every visit but the last of
// each imported URL, with its time and transition, written on the history
// database thread after the rows exist (the backend runs tasks in order).
// The last visit, which AddPagesWithDetails adds as a link, gets its own
// transition. URL rows keep the counts the import gave them.
class ImportVisitsTask : public history::HistoryDBTask {
 public:
  struct Visits {
    GURL url;
    std::vector<std::pair<base::Time, ui::PageTransition>> visits;
  };

  ImportVisitsTask(std::vector<Visits> visits,
                   base::OnceCallback<void(int)> done)
      : visits_(std::move(visits)), done_(std::move(done)) {}

  bool RunOnDBThread(history::HistoryBackend* backend,
                     history::HistoryDatabase* db) override {
    if (!db) {
      return true;
    }
    for (const Visits& entry : visits_) {
      history::URLRow row;
      const history::URLID url_id = db->GetRowForURL(entry.url, &row);
      if (!url_id || entry.visits.empty()) {
        continue;
      }
      // The visit AddPagesWithDetails made: the last one, as a link.
      history::VisitRow last;
      if (db->GetMostRecentVisitForURL(
              url_id, &last, history::VisitQuery404sPolicy::kInclude404s)) {
        last.transition = entry.visits.back().second;
        db->UpdateVisitRow(last);
      }
      for (size_t index = 0; index + 1 < entry.visits.size(); ++index) {
        history::VisitRow visit(url_id, entry.visits[index].first,
                                /*arg_referring_visit=*/0,
                                entry.visits[index].second,
                                /*arg_segment_id=*/0,
                                /*arg_incremented_omnibox_typed_score=*/false,
                                /*arg_opener_visit=*/0);
        visit.source = history::SOURCE_BROWSED;
        if (db->AddVisit(&visit)) {
          ++added_;
        }
      }
    }
    return true;
  }

  void DoneRunOnMainThread() override {
    if (done_) {
      std::move(done_).Run(added_);
    }
  }

 private:
  std::vector<Visits> visits_;
  base::OnceCallback<void(int)> done_;
  int added_ = 0;
};

}  // namespace

// MARK: Values

@interface RoomHistoryEntry ()
- (instancetype)initWithURL:(NSURL*)URL
                      title:(NSString*)title
                 visitCount:(NSInteger)visitCount
                 typedCount:(NSInteger)typedCount
                  lastVisit:(NSDate*)lastVisit;
+ (instancetype)room_entryWithRow:(const history::URLRow&)row
                        lastVisit:(base::Time)lastVisit;
@end

@implementation RoomHistoryEntry {
  NSURL* _URL;
  NSString* _title;
  NSInteger _visitCount;
  NSInteger _typedCount;
  NSDate* _lastVisit;
}

- (instancetype)initWithURL:(NSURL*)URL
                           title:(NSString*)title
                      visitCount:(NSInteger)visitCount
                      typedCount:(NSInteger)typedCount
                       lastVisit:(NSDate*)lastVisit {
  if ((self = [super init])) {
    _URL = [URL copy];
    _title = [title copy] ?: @"";
    _visitCount = visitCount;
    _typedCount = typedCount;
    _lastVisit = [lastVisit copy];
  }
  return self;
}

+ (instancetype)room_entryWithRow:(const history::URLRow&)row
                        lastVisit:(base::Time)lastVisit {
  NSURL* url = net::NSURLWithGURL(row.url());
  if (!url) {
    return nil;
  }
  return [[RoomHistoryEntry alloc]
      initWithURL:url
                 title:base::SysUTF16ToNSString(row.title())
            visitCount:row.visit_count()
            typedCount:row.typed_count()
             lastVisit:NSDateFromTime(lastVisit)];
}

- (NSURL*)URL {
  return _URL;
}
- (NSString*)title {
  return _title;
}
- (NSInteger)visitCount {
  return _visitCount;
}
- (NSInteger)typedCount {
  return _typedCount;
}
- (NSDate*)lastVisit {
  return _lastVisit;
}
- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomHistoryEntry %@ visits=%ld typed=%ld>",
                                    _URL.absoluteString, (long)_visitCount,
                                    (long)_typedCount];
}
@end

@implementation RoomHistoryVisit {
  NSDate* _time;
  RoomHistoryTransition _transition;
}

- (instancetype)initWithTime:(NSDate*)time
                  transition:(RoomHistoryTransition)transition {
  if ((self = [super init])) {
    _time = [time copy];
    _transition = transition;
  }
  return self;
}

- (NSDate*)time {
  return _time;
}
- (RoomHistoryTransition)transition {
  return _transition;
}
@end

@implementation RoomHistoryImportEntry {
  NSURL* _URL;
  NSString* _title;
  NSArray<RoomHistoryVisit*>* _visits;
}

- (instancetype)initWithURL:(NSURL*)URL
                      title:(NSString*)title
                     visits:(NSArray<RoomHistoryVisit*>*)visits {
  if ((self = [super init])) {
    _URL = [URL copy];
    _title = [title copy];
    _visits = [visits copy];
  }
  return self;
}

- (NSURL*)URL {
  return _URL;
}
- (NSString*)title {
  return _title;
}
- (NSArray<RoomHistoryVisit*>*)visits {
  return _visits;
}
@end

// MARK: The service

@implementation RoomProfileHistory {
  raw_ptr<Profile> _profile;
  std::unique_ptr<base::CancelableTaskTracker> _tasks;
}

- (instancetype)initWithChromeProfile:(Profile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    _tasks = std::make_unique<base::CancelableTaskTracker>();
  }
  return self;
}

- (void)room_profileWillBeDestroyed {
  _tasks.reset();
  _profile = nullptr;
}

- (history::HistoryService*)room_service {
  return _profile ? HistoryServiceFactory::GetForProfile(
                        _profile, ServiceAccessType::EXPLICIT_ACCESS)
                  : nullptr;
}

- (void)room_query:(const std::u16string&)text
           options:(const history::QueryOptions&)options
        completion:(void (^)(NSArray<RoomHistoryEntry*>*))completion {
  history::HistoryService* service = [self room_service];
  if (!service || !_tasks) {
    completion(@[]);
    return;
  }
  void (^callback)(NSArray<RoomHistoryEntry*>*) = [completion copy];
  service->QueryHistory(
      text, options,
      base::BindOnce(^(history::QueryResults results) {
        NSMutableArray<RoomHistoryEntry*>* entries =
            [NSMutableArray arrayWithCapacity:results.size()];
        for (const history::URLResult& result : results) {
          if (RoomHistoryEntry* entry =
                  [RoomHistoryEntry room_entryWithRow:result
                                            lastVisit:result.visit_time()]) {
            [entries addObject:entry];
          }
        }
        callback(entries);
      }),
      _tasks.get());
}

- (void)searchText:(NSString*)text
          maxCount:(NSInteger)maxCount
        completion:(void (^)(NSArray<RoomHistoryEntry*>*))completion {
  history::QueryOptions options;
  options.max_count = static_cast<int>(std::max<NSInteger>(0, maxCount));
  options.duplicate_policy = history::QueryOptions::REMOVE_ALL_DUPLICATES;
  [self room_query:base::SysNSStringToUTF16(text)
           options:options
        completion:completion];
}

- (void)entriesFrom:(NSDate*)begin
                 to:(NSDate*)end
           maxCount:(NSInteger)maxCount
         completion:(void (^)(NSArray<RoomHistoryEntry*>*))completion {
  history::QueryOptions options;
  options.begin_time = begin ? base::Time::FromNSDate(begin) : base::Time();
  options.end_time = end ? base::Time::FromNSDate(end) : base::Time();
  options.max_count = static_cast<int>(std::max<NSInteger>(0, maxCount));
  options.duplicate_policy = history::QueryOptions::REMOVE_ALL_DUPLICATES;
  [self room_query:std::u16string() options:options completion:completion];
}

- (void)visitsForURL:(NSURL*)URL
          completion:(void (^)(RoomHistoryEntry*,
                               NSArray<RoomHistoryVisit*>*))completion {
  history::HistoryService* service = [self room_service];
  const GURL url = net::GURLWithNSURL(URL);
  if (!service || !_tasks || !url.is_valid()) {
    completion(nil, @[]);
    return;
  }
  void (^callback)(RoomHistoryEntry*, NSArray<RoomHistoryVisit*>*) =
      [completion copy];
  service->QueryURLAndVisits(
      url, history::VisitQuery404sPolicy::kInclude404s,
      base::BindOnce(^(history::QueryURLAndVisitsResult result) {
        if (!result.success) {
          callback(nil, @[]);
          return;
        }
        NSMutableArray<RoomHistoryVisit*>* visits =
            [NSMutableArray arrayWithCapacity:result.visits.size()];
        for (const history::VisitRow& visit : result.visits) {
          [visits addObject:[[RoomHistoryVisit alloc]
                                initWithTime:visit.visit_time.ToNSDate()
                                  transition:TransitionFrom(visit.transition)]];
        }
        callback([RoomHistoryEntry room_entryWithRow:result.row
                                           lastVisit:result.row.last_visit()],
                 visits);
      }),
      _tasks.get());
}

- (void)mostVisitedWithMaxCount:(NSInteger)maxCount
                     completion:
                         (void (^)(NSArray<RoomHistoryEntry*>*))completion {
  history::HistoryService* service = [self room_service];
  if (!service || !_tasks || maxCount <= 0) {
    completion(@[]);
    return;
  }
  void (^callback)(NSArray<RoomHistoryEntry*>*) = [completion copy];
  service->QueryMostVisitedURLs(
      static_cast<int>(maxCount),
      base::BindOnce(^(history::MostVisitedURLList list) {
        NSMutableArray<RoomHistoryEntry*>* entries =
            [NSMutableArray arrayWithCapacity:list.size()];
        for (const history::MostVisitedURL& visited : list) {
          NSURL* url = net::NSURLWithGURL(visited.url);
          if (!url) {
            continue;
          }
          [entries addObject:[[RoomHistoryEntry alloc]
                                 initWithURL:url
                                            title:base::SysUTF16ToNSString(
                                                      visited.title)
                                       visitCount:0
                                       typedCount:0
                                        lastVisit:nil]];
        }
        callback(entries);
      }),
      _tasks.get());
}

- (void)deleteURLs:(NSArray<NSURL*>*)URLs {
  history::HistoryService* service = [self room_service];
  if (!service) {
    return;
  }
  std::vector<GURL> urls;
  for (NSURL* URL in URLs) {
    const GURL url = net::GURLWithNSURL(URL);
    if (url.is_valid()) {
      urls.push_back(url);
    }
  }
  if (!urls.empty()) {
    service->DeleteURLs(urls);
  }
}

- (void)deleteHost:(NSString*)host
        completion:(void (^)(NSInteger))completion {
  history::HistoryService* service = [self room_service];
  const std::string bare = BareHost(base::SysNSStringToUTF8(host));
  if (!service || !_tasks || bare.empty()) {
    completion(0);
    return;
  }
  // The host's URLs (a hostname query), then the exact host's among them:
  // a query for "example.com" also finds "notexample.com".
  history::QueryOptions options;
  options.host_only = true;
  options.duplicate_policy = history::QueryOptions::REMOVE_ALL_DUPLICATES;
  void (^callback)(NSInteger) = [completion copy];
  base::WeakPtr<history::HistoryService> weak_service = service->AsWeakPtr();
  service->QueryHistory(
      base::UTF8ToUTF16(bare), options,
      base::BindOnce(^(history::QueryResults results) {
        std::vector<GURL> urls;
        for (const history::URLResult& result : results) {
          if (BareHost(result.url().host()) == bare) {
            urls.push_back(result.url());
          }
        }
        if (!urls.empty() && weak_service) {
          weak_service->DeleteURLs(urls);
        }
        callback(static_cast<NSInteger>(urls.size()));
      }),
      _tasks.get());
}

- (void)importEntries:(NSArray<RoomHistoryImportEntry*>*)entries
           completion:(void (^)(RoomHistoryImportResult))completion {
  RoomHistoryImportResult result = {0, 0, 0, 0};
  history::HistoryService* service = [self room_service];
  if (!service || !_tasks) {
    completion(result);
    return;
  }
  // Chrome expires visits older than 90 days (HistoryBackend's expirer;
  // AddPagesWithDetails drops such rows): a day's margin keeps the boundary
  // out of the import.
  const base::Time cutoff =
      base::Time::Now() -
      base::Days(history::HistoryBackend::kExpireDaysThreshold - 1);
  history::URLRows rows;
  std::vector<ImportVisitsTask::Visits> visits;
  rows.reserve(entries.count);
  visits.reserve(entries.count);
  for (RoomHistoryImportEntry* entry in entries) {
    const GURL url = net::GURLWithNSURL(entry.URL);
    if (!url.is_valid()) {
      continue;
    }
    ImportVisitsTask::Visits kept{url, {}};
    int typed = 0;
    for (RoomHistoryVisit* visit in entry.visits) {
      const base::Time time = base::Time::FromNSDate(visit.time);
      if (time < cutoff) {
        ++result.expiredVisits;
        continue;
      }
      if (visit.transition == RoomHistoryTransitionReload) {
        continue;  // Not a visit (Chrome's history skips reloads).
      }
      if (visit.transition == RoomHistoryTransitionTyped) {
        ++typed;
      }
      kept.visits.emplace_back(time, TransitionTo(visit.transition));
    }
    if (kept.visits.empty()) {
      ++result.expiredURLs;
      continue;
    }
    std::sort(kept.visits.begin(), kept.visits.end(),
              [](const auto& a, const auto& b) { return a.first < b.first; });
    history::URLRow row(url);
    row.set_title(entry.title ? base::SysNSStringToUTF16(entry.title)
                              : std::u16string());
    row.set_visit_count(static_cast<int>(kept.visits.size()));
    row.set_typed_count(typed);
    row.set_last_visit(kept.visits.back().first);
    rows.push_back(std::move(row));
    result.urls += 1;
    result.visits += static_cast<NSInteger>(kept.visits.size());
    visits.push_back(std::move(kept));
  }
  if (rows.empty()) {
    completion(result);
    return;
  }
  service->AddPagesWithDetails(rows, history::SOURCE_BROWSED);
  void (^callback)(RoomHistoryImportResult) = [completion copy];
  service->ScheduleDBTask(
      FROM_HERE,
      std::make_unique<ImportVisitsTask>(
          std::move(visits), base::BindOnce(^(int added) {
            VLOG(1) << "RoomCore: history import added " << added
                    << " earlier visits";
            callback(result);
          })),
      _tasks.get());
}

@end
