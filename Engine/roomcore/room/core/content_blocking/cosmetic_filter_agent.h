// Copyright 2026 Jonas Lekevicius. All rights reserved.
#ifndef ROOM_CORE_CONTENT_BLOCKING_COSMETIC_FILTER_AGENT_H_
#define ROOM_CORE_CONTENT_BLOCKING_COSMETIC_FILTER_AGENT_H_

#include <optional>
#include <string>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "content/public/renderer/render_frame_observer.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "room/core/content_blocking/cosmetic_filters.mojom.h"
#include "v8/include/v8-forward.h"

namespace room {

// The isolated world Room's page scripts run in (the generic class/id
// collector, autoconsent): far above the ids Chrome and extensions allocate
// (extensions count up from ISOLATED_WORLD_ID_EXTENSIONS), below Blink's
// kEmbedderWorldIdLimit (1 << 29).
inline constexpr int32_t kContentBlockingWorldId = (1 << 29) - 2;

// Renderer side of Room's blocker, one per frame (patch 0027 creates it):
// applies what the browser pushed for the committing document at
// DidCreateDocumentElement, before the page's own scripts run. Hide
// selectors go into a user-origin stylesheet the page cannot override;
// scriptlets run in the main world; the class/id collector and autoconsent
// run in kContentBlockingWorldId and reach back through two native functions.
class CosmeticFilterAgent : public content::RenderFrameObserver,
                            public mojom::CosmeticFilterAgent {
 public:
  explicit CosmeticFilterAgent(content::RenderFrame* render_frame);
  CosmeticFilterAgent(const CosmeticFilterAgent&) = delete;
  CosmeticFilterAgent& operator=(const CosmeticFilterAgent&) = delete;
  ~CosmeticFilterAgent() override;

  // mojom::CosmeticFilterAgent:
  void ActivateForNextCommittedLoad(
      mojom::CosmeticResourcesPtr resources,
      mojo::PendingRemote<mojom::CosmeticFilterHost> host) override;

  // Called by the isolated world's native functions.
  void RequestHiddenSelectors(std::vector<std::string> classes,
                              std::vector<std::string> ids);
  void HandleCookieMessage(const std::string& json);

 private:
  // content::RenderFrameObserver:
  void DidCommitProvisionalLoad(ui::PageTransition transition) override;
  void DidCreateDocumentElement() override;
  void DidCreateScriptContext(v8::Local<v8::Context> context,
                              int32_t world_id) override;
  void OnDestruct() override;

  void Bind(
      mojo::PendingAssociatedReceiver<mojom::CosmeticFilterAgent> receiver);
  void InsertHideStyleSheet(const std::vector<std::string>& selectors);
  void RunInWorld(const std::string& script);
  void OnHiddenSelectors(const std::vector<std::string>& selectors);

  mojo::AssociatedReceiver<mojom::CosmeticFilterAgent> receiver_{this};
  // Pushed for the next commit; becomes current at DidCommitProvisionalLoad.
  mojom::CosmeticResourcesPtr pending_;
  mojo::PendingRemote<mojom::CosmeticFilterHost> pending_host_;
  mojom::CosmeticResourcesPtr current_;
  mojo::Remote<mojom::CosmeticFilterHost> host_;
  bool cookie_banner_reported_ = false;
  base::WeakPtrFactory<CosmeticFilterAgent> weak_factory_{this};
};

}  // namespace room

#endif  // ROOM_CORE_CONTENT_BLOCKING_COSMETIC_FILTER_AGENT_H_
