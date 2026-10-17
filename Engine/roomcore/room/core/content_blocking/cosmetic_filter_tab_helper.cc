// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include "room/core/content_blocking/cosmetic_filter_tab_helper.h"

#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "base/no_destructor.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "mojo/public/cpp/bindings/self_owned_receiver.h"
#include "room/core/content_blocking/content_blocker.h"
#include "room/core/content_blocking/cosmetic_filters.mojom.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"

namespace room {
namespace {

CosmeticFilterTabHelper::CookieBannerCallback& CookieBannerCallbackStorage() {
  static base::NoDestructor<CosmeticFilterTabHelper::CookieBannerCallback>
      callback;
  return *callback;
}

// One document's answers: its generic-selector exceptions and the page to
// report a handled cookie banner to. Owned by its receiver (the renderer's
// remote lives as long as the document).
class CosmeticFilterHostImpl : public mojom::CosmeticFilterHost {
 public:
  CosmeticFilterHostImpl(content::GlobalRenderFrameHostId frame_id,
                         std::vector<std::string> exceptions)
      : frame_id_(frame_id), exceptions_(std::move(exceptions)) {}

  void HiddenClassIdSelectors(
      const std::vector<std::string>& classes,
      const std::vector<std::string>& ids,
      HiddenClassIdSelectorsCallback callback) override {
    std::move(callback).Run(ContentBlocker::Get()->HiddenClassIdSelectors(
        classes, ids, exceptions_));
  }

  void CookieBannerHandled(const std::string& cmp, bool opted_out) override {
    content::RenderFrameHost* frame =
        content::RenderFrameHost::FromID(frame_id_);
    content::WebContents* contents =
        frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
    if (contents && CookieBannerCallbackStorage()) {
      CookieBannerCallbackStorage().Run(contents, cmp, opted_out);
    }
  }

 private:
  const content::GlobalRenderFrameHostId frame_id_;
  const std::vector<std::string> exceptions_;
};

}  // namespace

// static
void CosmeticFilterTabHelper::SetCookieBannerCallback(
    CookieBannerCallback callback) {
  CookieBannerCallbackStorage() = std::move(callback);
}

CosmeticFilterTabHelper::CosmeticFilterTabHelper(content::WebContents* contents)
    : content::WebContentsObserver(contents),
      content::WebContentsUserData<CosmeticFilterTabHelper>(*contents) {}

CosmeticFilterTabHelper::~CosmeticFilterTabHelper() = default;

void CosmeticFilterTabHelper::ReadyToCommitNavigation(
    content::NavigationHandle* handle) {
  if (handle->IsSameDocument() || handle->IsErrorPage()) {
    return;
  }
  content::RenderFrameHost* frame = handle->GetRenderFrameHost();
  if (!frame) {
    return;
  }
  // The page's top-level URL: the navigation's own for a main frame,
  // the committed outermost page's for a subframe.
  const GURL top_level_url =
      handle->IsInOutermostMainFrame()
          ? handle->GetURL()
          : frame->GetOutermostMainFrame()->GetLastCommittedURL();
  std::optional<CosmeticPayload> payload =
      ContentBlocker::Get()->CosmeticFor(handle->GetURL(), top_level_url);
  if (!payload) {
    return;
  }
  auto resources = mojom::CosmeticResources::New();
  resources->hide_selectors = std::move(payload->hide_selectors);
  resources->exceptions = payload->exceptions;
  resources->scriptlets = std::move(payload->scriptlets);
  resources->generichide = payload->generichide;
  resources->collect_class_ids = !payload->generichide;
  resources->cookie_script = std::move(payload->cookie_script);

  mojo::PendingRemote<mojom::CosmeticFilterHost> host;
  mojo::MakeSelfOwnedReceiver(
      std::make_unique<CosmeticFilterHostImpl>(frame->GetGlobalId(),
                                               std::move(payload->exceptions)),
      host.InitWithNewPipeAndPassReceiver());
  mojo::AssociatedRemote<mojom::CosmeticFilterAgent> agent;
  frame->GetRemoteAssociatedInterfaces()->GetInterface(&agent);
  agent->ActivateForNextCommittedLoad(std::move(resources), std::move(host));
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(CosmeticFilterTabHelper);

}  // namespace room
