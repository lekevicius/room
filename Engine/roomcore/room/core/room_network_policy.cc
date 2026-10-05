// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include "room/core/room_network_policy.h"

#include <memory>
#include <string>

#include "base/check.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "chrome/browser/invalidation/profile_invalidation_provider_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/signin/chrome_signin_client.h"
#include "chrome/browser/signin/chrome_signin_client_factory.h"
#include "chrome/common/chrome_switches.h"
#include "chrome/common/chrome_paths_internal.h"
#include "components/component_updater/update_scheduler.h"
#include "components/keyed_service/content/browser_context_dependency_manager.h"
#include "components/keyed_service/core/keyed_service.h"

namespace room {
// Tiny factory hook (patch 0006); update service and on-demand path stay intact.
extern std::unique_ptr<component_updater::UpdateScheduler>
    (*g_create_component_update_scheduler_hook)();

namespace {
class OnDemandOnlyScheduler : public component_updater::UpdateScheduler {
 public:
  void Schedule(base::TimeDelta, base::TimeDelta, const UserTask&,
                const OnStopTaskCallback&) override {}
  void Stop() override {}
};

// Room has no Chrome account/sync UI. Web-page Google sign-in uses the normal
// page network stack, independently of this browser-account client.
class RoomSigninClient : public ChromeSigninClient {
 public:
  explicit RoomSigninClient(Profile* profile) : ChromeSigninClient(profile) {}
  bool AreSigninCookiesAllowed() override { return false; }
  bool AreNetworkCallsDelayed() override { return true; }
  void DelayNetworkCall(base::OnceClosure) override {}
};
}  // namespace

base::CallbackListSubscription InstallNetworkPolicy() {
  auto* command_line = base::CommandLine::ForCurrentProcess();
  command_line->AppendSwitch(switches::kDisableBackgroundNetworking);
  command_line->AppendSwitch(switches::kDisableComponentExtensionsWithBackgroundPages);
  command_line->AppendSwitch("disable-sync");
  std::string disabled = command_line->GetSwitchValueASCII("disable-features");
  if (!disabled.empty()) {
    disabled += ",";
  }
  disabled += "NetworkTimeServiceQuerying,AimEnabled,PreconnectToSearch,"
              "PreconnectFromKeyedService,OptimizationHints,"
              "OptimizationTargetPrediction,OptimizationGuideModelExecution,"
              "OnDeviceModelBackgroundDownload,PreemptiveSodaDownload";
  // Translate's ranker fetches its model from www.gstatic.com (traffic
  // annotation ranker_url_fetcher) when the first WebContents creates
  // TranslateRankerImpl; either feature on is enough. 3.1b net-log on Room.app:
  // the one engine request over launch + 600 s idle + quit, 0 with both off.
  // The translate offer itself does not need the ranker.
  disabled += ",TranslateRankerQuery,TranslateRankerEnforcement";
  // Autofill's crowdsourced field-type query (autofill_query to
  // content-autofill.googleapis.com) on every page with a form. 3.1b
  // browsing ten real sites: 13 requests. Local autofill keeps working.
  disabled += ",AutofillServerCommunication";
  // Not network: Chrome clones the app bundle at launch so a running copy
  // survives an in-place update, and a code-sign-clone-cleanup helper deletes
  // it after quit (1-2 s past the browser; B-45). Sparkle replaces the whole
  // bundle and relaunches, so the clone buys Room nothing.
  disabled += ",MacAppCodeSignClone";
  // Not network: Chromium builds take WebContentsDiscard from the field-trial
  // testing config, an in-place discard that blanks the document but keeps
  // its renderer process (3.3a, seven discards: renderers 11 -> 12 after
  // 10 s, memory up 140 MB). Chrome's default on desktop (feature off)
  // replaces the WebContents and its process goes; RoomCore moves the page's
  // wrapper to the replacement (TabStripModelChange::kReplaced).
  disabled += ",WebContentsDiscard";
  // Not network: Chrome's confirmation toasts (ToastController) anchor on a
  // BrowserView's toolbar and CHECK in a Room window, which has none: the
  // context menu's Copy Link Address crashed in 3.4a. Room shows its own
  // toasts (spec §F).
  disabled += ",LinkCopiedToast,ImageCopiedToast,VideoFrameCopiedToast,"
              "LinkToHighlightCopiedToast,ReadingListToast,TranslateToast";
  command_line->AppendSwitchASCII("disable-features", disabled);

  // M154's global manifest broker registers/downloads its manifest even with
  // model execution disabled. Its supported local manifest override provides
  // an empty component catalog without modifying Chromium or faking a URL.
  base::FilePath root = command_line->GetSwitchValuePath(switches::kUserDataDir);
  if (root.empty()) {
    CHECK(chrome::GetDefaultUserDataDirectory(&root));
  }
  const base::FilePath config = root.AppendASCII("RoomNetworkPolicy")
      .AppendASCII("model-manifest.json");
  CHECK(base::CreateDirectory(config.DirName()));
  CHECK(base::WriteFile(config, "{}\n"));
  command_line->AppendSwitchPath("optimization-guide-manifest-override", config);

  g_create_component_update_scheduler_hook = +[]()
      -> std::unique_ptr<component_updater::UpdateScheduler> {
    return std::make_unique<OnDemandOnlyScheduler>();
  };

  // These existing factory seams are named for tests upstream but have no
  // test-only behavior or CHECK_IS_TEST. Use them for Room's real policy,
  // avoiding new patches and never constructing test/fake browser contexts.
  invalidation::ProfileInvalidationProviderFactory::GetInstance()
      ->RegisterTestingFactory(base::BindRepeating(
          [](content::BrowserContext*) -> std::unique_ptr<KeyedService> {
            return nullptr;  // No Chrome cloud-policy invalidation channels.
          }));
  return BrowserContextDependencyManager::GetInstance()
      ->RegisterCreateServicesCallbackForTesting(base::BindRepeating(
          [](content::BrowserContext* context) {
            Profile* profile = Profile::FromBrowserContext(context);
            if (profile->IsOffTheRecord()) {
              return;
            }
            ChromeSigninClientFactory::GetInstance()->SetTestingFactory(
                context, base::BindRepeating(
                    [](content::BrowserContext* context) -> std::unique_ptr<KeyedService> {
                      return std::make_unique<RoomSigninClient>(
                          Profile::FromBrowserContext(context));
                    }));
          }));
}
}  // namespace room
