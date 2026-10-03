// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include <memory>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "content/public/renderer/render_frame.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "room/core/room_cdm.mojom.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/media/web_encrypted_media_client_impl.h"
#include "third_party/blink/public/platform/web_encrypted_media_request.h"

namespace room {
extern CONTENT_EXPORT std::unique_ptr<blink::WebEncryptedMediaClientImpl>
    (*g_create_encrypted_media_client_hook)(
        content::RenderFrame*, media::KeySystems*, media::CdmFactory*,
        media::MediaPermission*,
        std::unique_ptr<blink::KeySystemConfigSelector::WebLocalFrameDelegate>);

namespace {
class RoomEncryptedMediaClient : public blink::WebEncryptedMediaClientImpl {
 public:
  RoomEncryptedMediaClient(
      content::RenderFrame* frame, media::KeySystems* keys,
      media::CdmFactory* factory, media::MediaPermission* permission,
      std::unique_ptr<blink::KeySystemConfigSelector::WebLocalFrameDelegate> delegate)
      : WebEncryptedMediaClientImpl(keys, factory, permission, std::move(delegate)) {
    frame->GetBrowserInterfaceBroker().GetInterface(
        provisioner_.BindNewPipeAndPassReceiver());
    provisioner_.set_disconnect_handler(base::BindOnce(
        &RoomEncryptedMediaClient::OnReady, weak_factory_.GetWeakPtr(), false));
  }

  void RequestMediaKeySystemAccess(blink::WebEncryptedMediaRequest request) override {
    if (request.KeySystem().Utf8() != "com.widevine.alpha" ||
        !provisioner_.is_connected()) {
      WebEncryptedMediaClientImpl::RequestMediaKeySystemAccess(std::move(request));
      return;
    }
    pending_.push_back(std::move(request));
    if (pending_.size() == 1) {
      provisioner_->EnsureWidevine(base::BindOnce(
          &RoomEncryptedMediaClient::OnReady, weak_factory_.GetWeakPtr()));
    }
  }

 private:
  void OnReady(bool available) {
    // On failure preserve Blink's ordinary unsupported-key-system result.
    // No injected capabilities, fake CDM, or weakened configuration checks.
    auto pending = std::move(pending_);
    for (auto& request : pending) {
      WebEncryptedMediaClientImpl::RequestMediaKeySystemAccess(std::move(request));
    }
  }
  mojo::Remote<mojom::CdmProvisioner> provisioner_;
  std::vector<blink::WebEncryptedMediaRequest> pending_;
  base::WeakPtrFactory<RoomEncryptedMediaClient> weak_factory_{this};
};

// Helpers enter ChromeMain directly rather than RoomApplication.run. Install
// this process-local factory when the framework loads, including renderers.
[[maybe_unused]] const bool installed = [] {
  g_create_encrypted_media_client_hook = +[](
      content::RenderFrame* frame, media::KeySystems* keys,
      media::CdmFactory* factory, media::MediaPermission* permission,
      std::unique_ptr<blink::KeySystemConfigSelector::WebLocalFrameDelegate> delegate)
      -> std::unique_ptr<blink::WebEncryptedMediaClientImpl> {
    return std::make_unique<RoomEncryptedMediaClient>(
        frame, keys, factory, permission, std::move(delegate));
  };
  return true;
}();
}  // namespace
}  // namespace room
