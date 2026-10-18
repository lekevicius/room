// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include "room/core/content_blocking/content_blocker.h"

#include <utility>

#include "base/containers/span.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/files/important_file_writer.h"
#include "base/hash/sha1.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/task/thread_pool.h"
#include "base/timer/elapsed_timer.h"
#include "content/public/browser/browser_thread.h"
#include "crypto/hash.h"
#include "components/web_cache/browser/web_cache_manager.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "room/core/content_blocking/adblock_ffi.rs.h"

namespace room {

namespace adblock {
struct AdblockEngineHolder {
  explicit AdblockEngineHolder(rust::Box<AdblockEngine> engine)
      : engine(std::move(engine)) {}
  rust::Box<AdblockEngine> engine;
};
}  // namespace adblock

// Bumped when the cache's meaning changes (adblock-rust's own format has a
// version too; a mismatch there rebuilds from text).
constexpr char kEngineCacheVersion[] = "adblock-0.13.3/room-1";

struct BuildInput {
  std::vector<ContentBlockerList> lists;
  std::string custom_rules;
  base::FilePath resources;
  base::FilePath cache_directory;
  base::FilePath cookie_script;
  std::string current_key;
};

struct BuildResult {
  std::string key;
  std::unique_ptr<adblock::AdblockEngineHolder> engine;  // null: unchanged
  ContentBlockerReport report;
  std::string cookie_script;
};

namespace {

std::unique_ptr<BuildResult> Build(BuildInput input) {
  base::ElapsedTimer timer;
  auto result = std::make_unique<BuildResult>();
  result->report.ok = true;
  if (!input.cookie_script.empty() &&
      !base::ReadFileToString(input.cookie_script, &result->cookie_script)) {
    LOG(WARNING) << "RoomCore: content blocking: unreadable "
                 << input.cookie_script;
  }

  std::vector<adblock::ListInput> lists;
  crypto::hash::Hasher hasher(crypto::hash::kSha256);
  hasher.Update(base::as_byte_span(std::string_view(kEngineCacheVersion)));
  for (const ContentBlockerList& list : input.lists) {
    std::string text;
    if (!base::ReadFileToString(list.path, &text)) {
      result->report.error += "unreadable list " + list.path.value() + "\n";
      continue;
    }
    const std::string flags = std::string(list.hosts_format ? "h" : "s") +
                              (list.trusted ? "t" : "u") +
                              base::NumberToString(text.size());
    hasher.Update(base::as_byte_span(flags));
    hasher.Update(base::as_byte_span(text));
    lists.push_back(adblock::ListInput{rust::String(text), list.hosts_format,
                                       list.trusted});
  }
  if (!input.custom_rules.empty()) {
    hasher.Update(base::as_byte_span(std::string_view("custom")));
    hasher.Update(base::as_byte_span(input.custom_rules));
    lists.push_back(
        adblock::ListInput{rust::String(input.custom_rules), false, false});
  }
  std::string resources;
  if (!input.resources.empty() &&
      !base::ReadFileToString(input.resources, &resources)) {
    result->report.error += "unreadable resources " +
                            input.resources.value() + "\n";
  }
  hasher.Update(base::as_byte_span(std::string_view("resources")));
  hasher.Update(base::as_byte_span(resources));
  std::array<uint8_t, crypto::hash::kSha256Size> digest;
  hasher.Finish(digest);
  result->key = base::ToLowerASCII(base::HexEncode(digest));
  if (result->key == input.current_key) {
    result->report.from_cache = true;
    return result;  // Same lists, rules and resources: keep the engine.
  }

  const rust::Str resources_str(resources.data(), resources.size());
  const base::FilePath cache_file =
      input.cache_directory.empty()
          ? base::FilePath()
          : input.cache_directory.AppendASCII(result->key + ".dat");
  std::string cached;
  if (!cache_file.empty() && base::ReadFileToString(cache_file, &cached)) {
    bool ok = false;
    rust::Box<adblock::AdblockEngine> engine = adblock::deserialize_engine(
        rust::Slice<const uint8_t>(
            reinterpret_cast<const uint8_t*>(cached.data()), cached.size()),
        resources_str, ok);
    if (ok) {
      result->engine =
          std::make_unique<adblock::AdblockEngineHolder>(std::move(engine));
      result->report.from_cache = true;
      result->report.engine_bytes = cached.size();
    }
  }
  if (!result->engine) {
    rust::Box<adblock::AdblockEngine> engine = adblock::new_engine(
        rust::Slice<const adblock::ListInput>(lists.data(), lists.size()),
        resources_str);
    rust::Vec<uint8_t> bytes = engine->serialize();
    result->report.engine_bytes = bytes.size();
    if (!cache_file.empty() && base::CreateDirectory(input.cache_directory)) {
      // One cached engine: the previous ones are stale.
      base::FileEnumerator old(input.cache_directory, false,
                               base::FileEnumerator::FILES,
                               FILE_PATH_LITERAL("*.dat"));
      for (base::FilePath path = old.Next(); !path.empty();
           path = old.Next()) {
        base::DeleteFile(path);
      }
      base::ImportantFileWriter::WriteFileAtomically(
          cache_file, std::string_view(reinterpret_cast<const char*>(
                                           bytes.data()),
                                       bytes.size()));
    }
    result->engine =
        std::make_unique<adblock::AdblockEngineHolder>(std::move(engine));
  }
  result->report.build_milliseconds = timer.Elapsed().InMillisecondsF();
  return result;
}

std::vector<std::string> ToStrings(const rust::Vec<rust::String>& values) {
  std::vector<std::string> out;
  out.reserve(values.size());
  for (const rust::String& value : values) {
    out.emplace_back(value);
  }
  return out;
}

std::vector<rust::String> ToRust(const std::vector<std::string>& values) {
  std::vector<rust::String> out;
  out.reserve(values.size());
  for (const std::string& value : values) {
    out.emplace_back(value);
  }
  return out;
}

}  // namespace

ContentBlockerConfig::ContentBlockerConfig() = default;
ContentBlockerConfig::ContentBlockerConfig(ContentBlockerConfig&&) = default;
ContentBlockerConfig& ContentBlockerConfig::operator=(ContentBlockerConfig&&) =
    default;
ContentBlockerConfig::~ContentBlockerConfig() = default;

CosmeticPayload::CosmeticPayload() = default;
CosmeticPayload::CosmeticPayload(CosmeticPayload&&) = default;
CosmeticPayload& CosmeticPayload::operator=(CosmeticPayload&&) = default;
CosmeticPayload::~CosmeticPayload() = default;

// static
ContentBlocker* ContentBlocker::Get() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  static base::NoDestructor<ContentBlocker> instance;
  return instance.get();
}

ContentBlocker::ContentBlocker()
    : build_runner_(base::ThreadPool::CreateSequencedTaskRunner(
          {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
           base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN})) {}

ContentBlocker::~ContentBlocker() = default;

void ContentBlocker::Apply(
    ContentBlockerConfig config,
    base::OnceCallback<void(ContentBlockerReport)> done) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  BuildInput input;
  input.lists = config.lists;
  input.custom_rules = config.custom_rules;
  input.resources = config.resources;
  input.cache_directory = config.cache_directory;
  input.cookie_script = config.cookie_script;
  input.current_key = engine_ ? engine_key_ : std::string();
  config_ = std::move(config);
  const uint64_t generation = ++generation_;
  build_runner_->PostTaskAndReplyWithResult(
      FROM_HERE, base::BindOnce(&Build, std::move(input)),
      base::BindOnce(&ContentBlocker::OnBuilt, weak_factory_.GetWeakPtr(),
                     generation, std::move(done)));
  for (Observer& observer : observers_) {
    observer.OnContentBlockerChanged();  // the allowed sites and mode now
  }
}

void ContentBlocker::OnBuilt(
    uint64_t generation,
    base::OnceCallback<void(ContentBlockerReport)> done,
    std::unique_ptr<BuildResult> result) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (generation == generation_) {
    if (result->engine) {
      engine_ = std::move(result->engine);
      engine_key_ = result->key;
      engine_bytes_ = result->report.engine_bytes;
    } else {
      result->report.engine_bytes = engine_bytes_;  // unchanged lists
    }
    cookie_script_ = std::move(result->cookie_script);
    LOG(WARNING) << "RoomCore: content blocking: engine "
                 << (result->report.from_cache ? "cached" : "built") << " in "
                 << result->report.build_milliseconds << " ms, "
                 << result->report.engine_bytes << " bytes";
    // Renderers keep fetched subresources in their memory caches and reuse
    // them without a request: a script loaded while its site was allowed
    // would load again unchecked after the switch is turned back on.
    web_cache::WebCacheManager::GetInstance()->ClearCache();
    for (Observer& observer : observers_) {
      observer.OnContentBlockerChanged();
    }
  }
  if (done) {
    std::move(done).Run(std::move(result->report));
  }
}

bool ContentBlocker::active() const {
  return config_.enabled && engine_;
}

bool ContentBlocker::IsAllowed(const GURL& top_level_url) const {
  if (config_.allowed_sites.empty() || !top_level_url.has_host()) {
    return false;
  }
  std::string site = net::registry_controlled_domains::GetDomainAndRegistry(
      top_level_url,
      net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  if (site.empty()) {
    site = top_level_url.host();
  }
  return config_.allowed_sites.contains(base::ToLowerASCII(site));
}

ContentBlockerMatch ContentBlocker::Check(const GURL& url,
                                          const GURL& source_url,
                                          std::string_view request_type,
                                          std::string_view method) const {
  ContentBlockerMatch match;
  if (!active() || !url.SchemeIsHTTPOrHTTPS()) {
    return match;
  }
  const adblock::NetworkMatch result = engine_->engine->check_request(
      url.spec(), source_url.is_valid() ? source_url.spec() : std::string(),
      rust::Str(request_type.data(), request_type.size()),
      rust::Str(method.data(), method.size()));
  match.block = result.block;
  if (result.block && !result.redirect.empty()) {
    match.redirect = std::string(result.redirect);
  }
  return match;
}

std::optional<CosmeticPayload> ContentBlocker::CosmeticFor(
    const GURL& document_url,
    const GURL& top_level_url) const {
  if (!active() || !document_url.SchemeIsHTTPOrHTTPS() ||
      IsAllowed(top_level_url)) {
    return std::nullopt;
  }
  const adblock::CosmeticResources resources =
      engine_->engine->cosmetic_resources(document_url.spec());
  CosmeticPayload payload;
  payload.hide_selectors = ToStrings(resources.hide_selectors);
  payload.procedural_actions = ToStrings(resources.procedural_actions);
  payload.exceptions = ToStrings(resources.exceptions);
  if (!resources.injected_script.empty()) {
    // uBlock Origin's scriptlets read `scriptletGlobals`, which uBO's own
    // injector declares (as Brave's does); the function also keeps their
    // helpers (`safeSelf`…) out of the page's global scope.
    payload.scriptlets =
        base::StrCat({"(function() {\nconst scriptletGlobals = {};\n",
                      std::string_view(resources.injected_script.data(),
                                       resources.injected_script.size()),
                      "\n})();\n"});
  }
  payload.generichide = resources.generichide;
  if (config_.cookie_banners == CookieBannerMode::kReject) {
    payload.cookie_script = cookie_script_;
  }
  return payload;
}

std::vector<std::string> ContentBlocker::HiddenClassIdSelectors(
    const std::vector<std::string>& classes,
    const std::vector<std::string>& ids,
    const std::vector<std::string>& exceptions) const {
  if (!active()) {
    return {};
  }
  const std::vector<rust::String> rust_classes = ToRust(classes);
  const std::vector<rust::String> rust_ids = ToRust(ids);
  const std::vector<rust::String> rust_exceptions = ToRust(exceptions);
  return ToStrings(engine_->engine->hidden_class_id_selectors(
      rust::Slice<const rust::String>(rust_classes.data(), rust_classes.size()),
      rust::Slice<const rust::String>(rust_ids.data(), rust_ids.size()),
      rust::Slice<const rust::String>(rust_exceptions.data(),
                                      rust_exceptions.size())));
}

void ContentBlocker::AddObserver(Observer* observer) {
  observers_.AddObserver(observer);
}

void ContentBlocker::RemoveObserver(Observer* observer) {
  observers_.RemoveObserver(observer);
}

std::string_view RequestTypeFor(network::mojom::RequestDestination destination,
                                bool keepalive) {
  using network::mojom::RequestDestination;
  switch (destination) {
    case RequestDestination::kDocument:
      return "document";
    case RequestDestination::kFrame:
    case RequestDestination::kIframe:
    case RequestDestination::kFencedframe:
      return "sub_frame";
    case RequestDestination::kScript:
    case RequestDestination::kWorker:
    case RequestDestination::kSharedWorker:
    case RequestDestination::kServiceWorker:
    case RequestDestination::kAudioWorklet:
    case RequestDestination::kPaintWorklet:
    case RequestDestination::kXslt:
      return "script";
    case RequestDestination::kStyle:
      return "stylesheet";
    case RequestDestination::kImage:
      return "image";
    case RequestDestination::kFont:
      return "font";
    case RequestDestination::kAudio:
    case RequestDestination::kVideo:
    case RequestDestination::kTrack:
      return "media";
    case RequestDestination::kObject:
    case RequestDestination::kEmbed:
      return "object";
    case RequestDestination::kReport:
      return "csp_report";
    case RequestDestination::kEmpty:
      return keepalive ? "ping" : "xmlhttprequest";
    default:
      return "other";
  }
}

}  // namespace room
