// Copyright 2026 Jonas Lekevicius. All rights reserved.
#ifndef ROOM_CORE_CONTENT_BLOCKING_CONTENT_BLOCKER_H_
#define ROOM_CORE_CONTENT_BLOCKING_CONTENT_BLOCKER_H_

#include <memory>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/observer_list.h"
#include "base/task/sequenced_task_runner.h"
#include "services/network/public/mojom/fetch_api.mojom-shared.h"
#include "url/gurl.h"

namespace room {

namespace adblock {
struct AdblockEngineHolder;
}
struct BuildResult;

// What the host's cookie-banner setting asks for (Settings ▸ Privacy).
enum class CookieBannerMode { kOff, kHide, kReject };

struct ContentBlockerList {
  base::FilePath path;
  bool hosts_format = false;  // one hostname per line
  bool trusted = false;       // may use privileged scriptlets
};

struct ContentBlockerConfig {
  ContentBlockerConfig();
  ContentBlockerConfig(ContentBlockerConfig&&);
  ContentBlockerConfig& operator=(ContentBlockerConfig&&);
  ~ContentBlockerConfig();

  bool enabled = false;
  std::vector<ContentBlockerList> lists;
  std::string custom_rules;
  base::FilePath resources;  // adblock-rust resources JSON; empty for none
  base::FilePath cache_directory;
  std::set<std::string> allowed_sites;  // registrable domains, lowercase
  CookieBannerMode cookie_banners = CookieBannerMode::kOff;
  base::FilePath cookie_script;  // Room's autoconsent bundle (rules inside)
};

struct ContentBlockerReport {
  bool ok = false;
  std::string error;
  bool from_cache = false;
  double build_milliseconds = 0;
  size_t engine_bytes = 0;
};

// The network decision for one request.
struct ContentBlockerMatch {
  bool block = false;
  std::string redirect;  // data: URL to serve instead (blocks too)
};

// What a document gets at commit (pushed to the renderer).
struct CosmeticPayload {
  CosmeticPayload();
  CosmeticPayload(CosmeticPayload&&);
  CosmeticPayload& operator=(CosmeticPayload&&);
  ~CosmeticPayload();

  std::vector<std::string> hide_selectors;
  std::vector<std::string> procedural_actions;  // JSON, for the page script
  std::vector<std::string> exceptions;
  std::string scriptlets;  // main-world script
  bool generichide = false;
  std::string cookie_script;  // empty unless kReject
};

// The browser's single ad and tracker blocker (B-30): one adblock-rust
// engine for every profile, built off the UI thread from the host's lists,
// matched on the UI thread. Every member is UI-thread only.
class ContentBlocker {
 public:
  class Observer : public base::CheckedObserver {
   public:
    virtual void OnContentBlockerChanged() = 0;
  };

  static ContentBlocker* Get();

  ContentBlocker(const ContentBlocker&) = delete;
  ContentBlocker& operator=(const ContentBlocker&) = delete;

  // Replaces the configuration. The engine is rebuilt (or read from the
  // cache) when the lists, rules or resources changed; the callback runs on
  // the UI thread once the new engine is in use.
  void Apply(ContentBlockerConfig config,
             base::OnceCallback<void(ContentBlockerReport)> done);

  // Blocking is on and an engine is loaded.
  bool active() const;
  // `top_level_url`'s site is on the host's allowed list.
  bool IsAllowed(const GURL& top_level_url) const;

  // `request_type` is adblock-rust's name ("script", "image", "sub_frame"…).
  ContentBlockerMatch Check(const GURL& url,
                            const GURL& source_url,
                            std::string_view request_type,
                            std::string_view method) const;
  // Nullopt when nothing applies to the document (inactive or allowed).
  std::optional<CosmeticPayload> CosmeticFor(const GURL& document_url,
                                             const GURL& top_level_url) const;
  std::vector<std::string> HiddenClassIdSelectors(
      const std::vector<std::string>& classes,
      const std::vector<std::string>& ids,
      const std::vector<std::string>& exceptions) const;

  void AddObserver(Observer* observer);
  void RemoveObserver(Observer* observer);

 private:
  friend class base::NoDestructor<ContentBlocker>;
  ContentBlocker();
  ~ContentBlocker();

  void OnBuilt(uint64_t generation,
               base::OnceCallback<void(ContentBlockerReport)> done,
               std::unique_ptr<BuildResult> result);

  ContentBlockerConfig config_;
  std::string engine_key_;
  std::unique_ptr<adblock::AdblockEngineHolder> engine_;
  std::string cookie_script_;
  uint64_t generation_ = 0;
  scoped_refptr<base::SequencedTaskRunner> build_runner_;
  base::ObserverList<Observer> observers_;
  base::WeakPtrFactory<ContentBlocker> weak_factory_{this};
};

// adblock-rust's request type for a request's destination; `keepalive`
// tells a beacon from a fetch.
std::string_view RequestTypeFor(network::mojom::RequestDestination destination,
                                bool keepalive);

}  // namespace room

#endif  // ROOM_CORE_CONTENT_BLOCKING_CONTENT_BLOCKER_H_
