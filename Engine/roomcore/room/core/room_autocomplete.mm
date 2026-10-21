// Copyright 2026 Jonas Lekevicius. All rights reserved.

// RoomAutocompleteController (Phase 3.5): Chrome's omnibox
// AutocompleteController with ChromeAutocompleteProviderClient for the
// host's palette, and Room's search engine as the profile's default
// (TemplateURLService), so SearchProvider asks Room's engine.

#import "room/core/room_omnibox_internal.h"

#include <map>
#include <memory>
#include <string>
#include <utility>

#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_ostream_operators.h"
#include "base/uuid.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_provider_client.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/search_engines/template_url_service_factory.h"
#include "components/omnibox/browser/autocomplete_controller.h"
#include "components/omnibox/browser/autocomplete_controller_config.h"
#include "components/omnibox/browser/autocomplete_enums.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_match_type.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/autocomplete_result.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_data.h"
#include "components/search_engines/template_url_service.h"
#include "net/base/apple/url_conversions.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"

namespace {

int ChromeProviderTypes(RoomAutocompleteProviders providers) {
  int types = 0;
  if (providers & RoomAutocompleteProviderHistoryQuick) {
    types |= static_cast<int>(AutocompleteProvider::Type::kHistoryQuick);
  }
  if (providers & RoomAutocompleteProviderHistoryURL) {
    types |= static_cast<int>(AutocompleteProvider::Type::kHistoryUrl);
  }
  if (providers & RoomAutocompleteProviderBookmark) {
    types |= static_cast<int>(AutocompleteProvider::Type::kBookmark);
  }
  if (providers & RoomAutocompleteProviderShortcuts) {
    types |= static_cast<int>(AutocompleteProvider::Type::kShortcuts);
  }
  if (providers & RoomAutocompleteProviderOpenTab) {
    types |= static_cast<int>(AutocompleteProvider::Type::kOpenTab);
  }
  if (providers & RoomAutocompleteProviderSearch) {
    types |= static_cast<int>(AutocompleteProvider::Type::kSearch);
  }
  return types;
}

RoomAutocompleteProviders RoomProvider(const AutocompleteProvider* provider) {
  if (!provider) {
    return 0;
  }
  switch (provider->type()) {
    case AutocompleteProvider::Type::kHistoryQuick:
      return RoomAutocompleteProviderHistoryQuick;
    case AutocompleteProvider::Type::kHistoryUrl:
      return RoomAutocompleteProviderHistoryURL;
    case AutocompleteProvider::Type::kBookmark:
      return RoomAutocompleteProviderBookmark;
    case AutocompleteProvider::Type::kShortcuts:
      return RoomAutocompleteProviderShortcuts;
    case AutocompleteProvider::Type::kOpenTab:
      return RoomAutocompleteProviderOpenTab;
    case AutocompleteProvider::Type::kSearch:
      return RoomAutocompleteProviderSearch;
    default:
      return 0;
  }
}

RoomAutocompleteMatchType RoomMatchType(omnibox::AutocompleteMatchType type) {
  switch (type) {
    case omnibox::AutocompleteMatchType::kUrlWhatYouTyped:
      return RoomAutocompleteMatchTypeURLWhatYouTyped;
    case omnibox::AutocompleteMatchType::kHistoryUrl:
      return RoomAutocompleteMatchTypeHistoryURL;
    case omnibox::AutocompleteMatchType::kHistoryTitle:
      return RoomAutocompleteMatchTypeHistoryTitle;
    case omnibox::AutocompleteMatchType::kHistoryBody:
      return RoomAutocompleteMatchTypeHistoryBody;
    case omnibox::AutocompleteMatchType::kHistoryKeyword:
      return RoomAutocompleteMatchTypeHistoryKeyword;
    case omnibox::AutocompleteMatchType::kNavsuggest:
    case omnibox::AutocompleteMatchType::kNavsuggestPersonalized:
      return RoomAutocompleteMatchTypeNavSuggest;
    case omnibox::AutocompleteMatchType::kSearchWhatYouTyped:
      return RoomAutocompleteMatchTypeSearchWhatYouTyped;
    case omnibox::AutocompleteMatchType::kSearchHistory:
      return RoomAutocompleteMatchTypeSearchHistory;
    case omnibox::AutocompleteMatchType::kSearchSuggest:
    case omnibox::AutocompleteMatchType::kSearchSuggestEntity:
    case omnibox::AutocompleteMatchType::kSearchSuggestTail:
    case omnibox::AutocompleteMatchType::kSearchSuggestPersonalized:
    case omnibox::AutocompleteMatchType::kSearchSuggestProfile:
      return RoomAutocompleteMatchTypeSearchSuggest;
    case omnibox::AutocompleteMatchType::kSearchOtherEngine:
      return RoomAutocompleteMatchTypeSearchOtherEngine;
    case omnibox::AutocompleteMatchType::kBookmarkTitle:
      return RoomAutocompleteMatchTypeBookmarkTitle;
    case omnibox::AutocompleteMatchType::kOpenTab:
      return RoomAutocompleteMatchTypeOpenTab;
    default:
      return RoomAutocompleteMatchTypeOther;
  }
}

}  // namespace

@interface RoomAutocompleteMatch ()
- (instancetype)initWithChromeMatch:(const AutocompleteMatch&)match;
@end

@implementation RoomAutocompleteMatch {
  NSString* _contents;
  NSString* _matchDescription;
  NSURL* _destinationURL;
  NSString* _fillIntoEdit;
  NSString* _inlineAutocompletion;
  NSInteger _relevance;
  RoomAutocompleteMatchType _type;
  RoomAutocompleteProviders _provider;
  BOOL _deletable;
  BOOL _hasTabMatch;
  BOOL _allowedToBeDefault;
}

- (instancetype)initWithChromeMatch:(const AutocompleteMatch&)match {
  if ((self = [super init])) {
    _contents = base::SysUTF16ToNSString(match.contents);
    _matchDescription = base::SysUTF16ToNSString(match.description);
    _destinationURL = match.destination_url.is_valid()
                          ? net::NSURLWithGURL(match.destination_url)
                          : nil;
    _fillIntoEdit = base::SysUTF16ToNSString(match.fill_into_edit);
    _inlineAutocompletion =
        base::SysUTF16ToNSString(match.inline_autocompletion);
    _relevance = match.relevance;
    _type = RoomMatchType(match.type);
    _provider = RoomProvider(match.provider);
    _deletable = match.SupportsDeletion();
    _hasTabMatch = match.has_tab_match.value_or(false);
    _allowedToBeDefault = match.allowed_to_be_default_match;
  }
  return self;
}

- (NSString*)contents {
  return _contents;
}
- (NSString*)matchDescription {
  return _matchDescription;
}
- (NSURL*)destinationURL {
  return _destinationURL;
}
- (NSString*)fillIntoEdit {
  return _fillIntoEdit;
}
- (NSString*)inlineAutocompletion {
  return _inlineAutocompletion;
}
- (NSInteger)relevance {
  return _relevance;
}
- (RoomAutocompleteMatchType)type {
  return _type;
}
- (RoomAutocompleteProviders)provider {
  return _provider;
}
- (BOOL)isDeletable {
  return _deletable;
}
- (BOOL)hasTabMatch {
  return _hasTabMatch;
}
- (BOOL)allowedToBeDefault {
  return _allowedToBeDefault;
}
- (NSString*)description {
  return [NSString
      stringWithFormat:@"<RoomAutocompleteMatch %@ type=%ld provider=%lu "
                       @"relevance=%ld inline=%@>",
                       _destinationURL.absoluteString ?: _contents, (long)_type,
                       (unsigned long)_provider, (long)_relevance,
                       _inlineAutocompletion];
}
@end

@interface RoomAutocompleteController ()
- (void)room_resultChanged:(AutocompleteController*)controller;
@end

namespace {

class ResultObserver : public AutocompleteController::Observer {
 public:
  explicit ResultObserver(RoomAutocompleteController* owner) : owner_(owner) {}

  void OnResultChanged(AutocompleteController* controller,
                       bool default_match_changed) override {
    [owner_ room_resultChanged:controller];
  }

 private:
  RoomAutocompleteController* __weak owner_;
};

}  // namespace

@implementation RoomAutocompleteController {
  id<RoomAutocompleteControllerDelegate> __weak _delegate;
  raw_ptr<Profile> _profile;
  // One Chrome controller per provider set asked for (a controller's
  // providers are fixed at construction); in practice two: the base set,
  // and the base set with SearchProvider while suggestions are on.
  std::map<int, std::unique_ptr<AutocompleteController>> _controllers;
  raw_ptr<AutocompleteController> _active;
  std::unique_ptr<ResultObserver> _observer;
  std::unique_ptr<ChromeAutocompleteSchemeClassifier> _classifier;
  NSArray<RoomAutocompleteMatch*>* _matches;
}

@synthesize delegate = _delegate;

- (instancetype)initWithChromeProfile:(Profile*)profile {
  if ((self = [super init])) {
    _profile = profile;
    _observer = std::make_unique<ResultObserver>(self);
    _classifier = std::make_unique<ChromeAutocompleteSchemeClassifier>(profile);
    _matches = @[];
  }
  return self;
}

- (void)dealloc {
  [self room_profileWillBeDestroyed];
}

- (void)room_profileWillBeDestroyed {
  _active = nullptr;
  for (auto& [types, controller] : _controllers) {
    controller->RemoveObserver(_observer.get());
    controller->Stop(AutocompleteStopReason::kClobbered);
  }
  _controllers.clear();
  _classifier.reset();
  _profile = nullptr;
}

- (AutocompleteController*)room_controllerFor:(int)types {
  auto found = _controllers.find(types);
  if (found != _controllers.end()) {
    return found->second.get();
  }
  AutocompleteControllerConfig config;
  config.provider_types = types;
  auto controller = std::make_unique<AutocompleteController>(
      std::make_unique<ChromeAutocompleteProviderClient>(_profile), config);
  controller->AddObserver(_observer.get());
  AutocompleteController* raw = controller.get();
  _controllers[types] = std::move(controller);
  LOG(INFO) << "RoomCore: autocomplete controller for provider types 0x"
            << std::hex << types;
  return raw;
}

- (void)startWithText:(NSString*)text
               cursorPosition:(NSInteger)cursorPosition
    preventInlineAutocomplete:(BOOL)preventInlineAutocomplete
                  keywordMode:(BOOL)keywordMode
                    providers:(RoomAutocompleteProviders)providers {
  if (!_profile || !_classifier) {
    return;
  }
  const int types = ChromeProviderTypes(providers);
  AutocompleteController* controller = [self room_controllerFor:types];
  if (_active && _active != controller) {
    // The switch flipped (or the set changed): the other controller stops
    // and its result goes; nothing it started keeps running.
    _active->Stop(AutocompleteStopReason::kClobbered);
  }
  _active = controller;
  const std::u16string text16 = base::SysNSStringToUTF16(text);
  const size_t cursor =
      cursorPosition < 0
          ? std::u16string::npos
          : std::min<size_t>(static_cast<size_t>(cursorPosition), text16.size());
  AutocompleteInput input(text16, cursor, metrics::OmniboxEventProto::OTHER,
                          *_classifier);
  input.set_prevent_inline_autocomplete(preventInlineAutocomplete);
  input.set_in_keyword_mode(keywordMode);
  input.set_allow_exact_keyword_match(keywordMode);
  controller->Start(input);
}

- (void)stop {
  if (_active) {
    _active->Stop(AutocompleteStopReason::kInteraction);
  }
}

- (NSArray<RoomAutocompleteMatch*>*)matches {
  return _matches;
}

- (BOOL)isDone {
  return !_active || _active->done();
}

- (void)deleteMatchAtIndex:(NSInteger)index {
  if (!_active || index < 0 ||
      static_cast<size_t>(index) >= _active->result().size()) {
    return;
  }
  const AutocompleteMatch match =
      _active->result().match_at(static_cast<size_t>(index));
  if (!match.SupportsDeletion()) {
    return;
  }
  // Chrome deletes matches only while no query runs.
  _active->Stop(AutocompleteStopReason::kInteraction);
  _active->DeleteMatch(match);
}

- (void)room_resultChanged:(AutocompleteController*)controller {
  if (controller != _active) {
    return;
  }
  const AutocompleteResult& result = controller->result();
  NSMutableArray<RoomAutocompleteMatch*>* matches =
      [NSMutableArray arrayWithCapacity:result.size()];
  for (const AutocompleteMatch& match : result) {
    [matches addObject:[[RoomAutocompleteMatch alloc] initWithChromeMatch:match]];
  }
  _matches = matches;
  [self.delegate autocompleteControllerDidUpdateResult:self];
}

@end

namespace room {

namespace {

void ApplyDefaultSearchEngine(TemplateURLService* service,
                              const TemplateURLData& data) {
  TemplateURL* existing = service->GetTemplateURLForKeyword(data.keyword());
  const TemplateURL* current = service->GetDefaultSearchProvider();
  if (existing && existing->url() == data.url() &&
      existing->suggestions_url() == data.suggestions_url &&
      existing->short_name() == data.short_name()) {
    if (current != existing) {
      service->SetUserSelectedDefaultSearchProvider(existing);
    }
    return;
  }
  if (existing && existing == current) {
    LOG(WARNING) << "RoomCore: the default search engine "
                 << data.keyword() << " changed in place; kept as it was";
    return;
  }
  if (existing) {
    service->Remove(existing);
  }
  TemplateURL* added = service->Add(std::make_unique<TemplateURL>(data));
  if (!added) {
    LOG(WARNING) << "RoomCore: search engine " << data.keyword()
                 << " not added";
    return;
  }
  service->SetUserSelectedDefaultSearchProvider(added);
  LOG(INFO) << "RoomCore: default search engine " << data.keyword()
            << " (suggest " << (data.suggestions_url.empty() ? "none" : "set")
            << ")";
}

}  // namespace

void SetDefaultSearchEngine(Profile* profile,
                            const std::u16string& name,
                            const std::u16string& keyword,
                            const std::string& search_url,
                            const std::string& suggest_url) {
  TemplateURLService* service =
      profile ? TemplateURLServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    return;
  }
  TemplateURLData data;
  data.SetShortName(name);
  data.SetKeyword(keyword);
  data.SetURL(search_url);
  data.suggestions_url = suggest_url;
  data.safe_for_autoreplace = false;
  data.sync_guid = base::Uuid::GenerateRandomV4().AsLowercaseString();
  if (service->loaded()) {
    ApplyDefaultSearchEngine(service, data);
    return;
  }
  // Applied once the keyword table has loaded; the subscription lives until
  // then (it runs once).
  auto subscription = std::make_shared<base::CallbackListSubscription>();
  *subscription = service->RegisterOnLoadedCallback(base::BindOnce(
      // The service runs its own callback: it is alive when this runs.
      [](TemplateURLService* service, TemplateURLData data,
         std::shared_ptr<base::CallbackListSubscription> keep) {
        ApplyDefaultSearchEngine(service, data);
      },
      base::Unretained(service), data, subscription));
  service->Load();
}

}  // namespace room
