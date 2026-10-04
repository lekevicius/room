// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include <algorithm>
#include <memory>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/single_thread_task_runner.h"
#include "base/timer/timer.h"
#include "chrome/browser/browser_process.h"
#include "components/component_updater/component_updater_service.h"
#include "content/public/common/cdm_info.h"
#include "content/public/browser/document_service.h"
#include "mojo/public/cpp/bindings/binder_map.h"
#include "room/core/room_cdm.mojom.h"
#include "services/network/public/cpp/is_potentially_trustworthy.h"
#include "services/network/public/mojom/permissions_policy/permissions_policy_feature.mojom.h"

namespace chrome::internal {
extern void (*g_room_populate_frame_binders_hook)(
    mojo::BinderMapWithContext<content::RenderFrameHost*>*);
}

namespace room {
extern CONTENT_EXPORT void (*g_cdm_registered_hook)(const content::CdmInfo&);
namespace {
bool widevine_available = false;
constexpr char kWidevineId[] = "oimompecagnajdejgnnjijobebaeigek";

bool WidevineAvailable() {
  return widevine_available;
}

// Coalesce requests across documents. No startup task or timer is scheduled.
// A failed download can be retried only by a later page request after cooldown.
class Provisioning {
 public:
  using Reply = base::OnceCallback<void(bool)>;
  static Provisioning& Get() {
    static base::NoDestructor<Provisioning> instance;
    return *instance;
  }
  void Ensure(Reply reply) {
    if (!g_browser_process || g_browser_process->IsShuttingDown()) {
      std::move(reply).Run(false);
      return;
    }
    if (WidevineAvailable()) {
      std::move(reply).Run(true);
      return;
    }
    if (callbacks_.empty() && base::TimeTicks::Now() < retry_after_) {
      std::move(reply).Run(false);
      return;
    }
    callbacks_.push_back(std::move(reply));
    if (callbacks_.size() > 1) {
      return;
    }
    deadline_ = base::TimeTicks::Now() + base::Seconds(60);
    requested_ = false;
    Poll();
  }

 private:
  void Poll() {
    if (!g_browser_process || g_browser_process->IsShuttingDown()) {
      Finish(false);
      return;
    }
    if (WidevineAvailable()) {
      Finish(true);
      return;
    }
    if (base::TimeTicks::Now() >= deadline_) {
      Finish(false);
      return;
    }
    auto* updater = g_browser_process->component_updater();
    if (!updater) {
      Finish(false);
      return;
    }
    // Component registration reads disk asynchronously at startup. Wait for
    // that registration before requesting an update; it can also find an
    // already-installed CDM and avoid a network request altogether.
    if (!requested_ && std::ranges::contains(updater->GetComponentIDs(), kWidevineId)) {
      requested_ = true;
      updater->MaybeThrottle(kWidevineId, base::BindOnce([] {}));
    }
    // ComponentReady registers the library asynchronously after installation.
    // Observe actual registration, not just a successful update response.
    timer_.Start(FROM_HERE, base::Milliseconds(100),
                 base::BindOnce(&Provisioning::Poll, base::Unretained(this)));
  }
  void Finish(bool available) {
    timer_.Stop();
    if (!available) {
      retry_after_ = base::TimeTicks::Now() + base::Minutes(1);
    }
    auto callbacks = std::move(callbacks_);
    callbacks_.clear();
    for (auto& callback : callbacks) {
      std::move(callback).Run(available);
    }
  }
  std::vector<Reply> callbacks_;
  base::OneShotTimer timer_;
  base::TimeTicks deadline_;
  base::TimeTicks retry_after_;
  bool requested_ = false;
};

class CdmProvisioner : public content::DocumentService<mojom::CdmProvisioner> {
 public:
  CdmProvisioner(content::RenderFrameHost& frame,
                 mojo::PendingReceiver<mojom::CdmProvisioner> receiver)
      : DocumentService(frame, std::move(receiver)) {}
  void EnsureWidevine(EnsureWidevineCallback callback) override {
    auto& frame = render_frame_host();
    if (!frame.IsActive() ||
        !network::IsOriginPotentiallyTrustworthy(frame.GetLastCommittedOrigin()) ||
        !frame.IsFeatureEnabled(network::mojom::PermissionsPolicyFeature::kEncryptedMedia)) {
      std::move(callback).Run(false);
      return;
    }
    Provisioning::Get().Ensure(std::move(callback));
  }
};

[[maybe_unused]] const bool installed = [] {
  g_cdm_registered_hook = +[](const content::CdmInfo& info) {
    if (info.key_system == "com.widevine.alpha" &&
        info.robustness == content::CdmInfo::Robustness::kSoftwareSecure &&
        info.status == content::CdmInfo::Status::kEnabled &&
        info.capability.has_value() && !info.path.empty()) {
      widevine_available = true;
    }
  };
  chrome::internal::g_room_populate_frame_binders_hook = +[](
      mojo::BinderMapWithContext<content::RenderFrameHost*>* map) {
    map->Add<mojom::CdmProvisioner>(
        [](content::RenderFrameHost* frame,
           mojo::PendingReceiver<mojom::CdmProvisioner> receiver) {
          new CdmProvisioner(*frame, std::move(receiver));
        });
  };
  return true;
}();
}  // namespace
}  // namespace room
