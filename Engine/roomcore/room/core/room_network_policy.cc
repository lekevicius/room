// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include "room/core/room_network_policy.h"

#include <memory>
#include <string>

#include "base/check.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "chrome/browser/invalidation/profile_invalidation_provider_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/signin/chrome_signin_client.h"
#include "chrome/browser/signin/chrome_signin_client_factory.h"
#include "chrome/common/chrome_switches.h"
#include "chrome/common/chrome_paths_internal.h"
#include "chrome/common/pref_names.h"
#include "components/component_updater/update_scheduler.h"
#include "components/password_manager/core/common/password_manager_pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/spellcheck/browser/pref_names.h"
#include "components/keyed_service/content/browser_context_dependency_manager.h"
#include "components/keyed_service/core/keyed_service.h"

namespace room {
// Tiny factory hook (patch 0006); update service and on-demand path stay intact.
extern std::unique_ptr<component_updater::UpdateScheduler>
    (*g_create_component_update_scheduler_hook)();

namespace {
// Settings ▸ Downloads ▸ PDFs: Download (4.7a). The host passes
// --enable-features=RoomPdfsDownload at launch when the setting says so;
// Chrome's own pref then turns a PDF navigation into a download.
BASE_FEATURE(kRoomPdfsDownload, base::FEATURE_DISABLED_BY_DEFAULT);

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
  // Not network: Chrome's confirmation toasts reach the host through
  // RoomToastController (B-58: the copy toasts are on again). Room has no
  // reading list, and the translate offer is the host's infobar (3.4b), so
  // those two stay off.
  disabled += ",ReadingListToast,TranslateToast";
  // Gemini in Chrome (Glic): 156's field-trial testing config enables it
  // (Glic<GlicDogfood), and its menu-bar status icon (GlicChromeStatusIcon,
  // on by default) then put an NSStatusBarWindow in Room's process (5.9's
  // tour, 2026-10-22). Room has no Gemini surface.
  disabled += ",Glic,GlicChromeStatusIcon";
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
            // Chrome checks every password it saves or fills against
            // Google's leak database (lookup_single_password_leak to
            // passwordsleakcheck-pa.googleapis.com; 3.7a net-log: one POST
            // per saved login, no account needed). Room asks nothing the
            // user did not ask for: off by default (the pref stays
            // Chrome's, so a later setting can turn it on).
            profile->GetPrefs()->SetDefaultPrefValue(
                password_manager::prefs::kPasswordLeakDetectionEnabled,
                base::Value(false));
            // Chrome's "Enhanced Spell Check" sends the text being checked
            // to Google's spelling service. Room offers no switch for it
            // and hides the context menu's item (B-74, decided 2026-10-06):
            // off as a default too, so nothing turns it on behind the user.
            // The macOS checker keeps working.
            profile->GetPrefs()->SetDefaultPrefValue(
                spellcheck::prefs::kSpellCheckUseSpellingService,
                base::Value(false));
            // PDFs download instead of opening in Chrome's viewer
            // (plugins.always_open_pdf_externally) when the host asked.
            profile->GetPrefs()->SetDefaultPrefValue(
                prefs::kPluginsAlwaysOpenPdfExternally,
                base::Value(base::FeatureList::IsEnabled(kRoomPdfsDownload)));
            ChromeSigninClientFactory::GetInstance()->SetTestingFactory(
                context, base::BindRepeating(
                    [](content::BrowserContext* context) -> std::unique_ptr<KeyedService> {
                      return std::make_unique<RoomSigninClient>(
                          Profile::FromBrowserContext(context));
                    }));
          }));
}
}  // namespace room
