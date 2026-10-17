// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include "room/core/content_blocking/network_blocking.h"

#include <memory>
#include <string>
#include <utility>

#include "base/byte_size.h"
#include "base/containers/span.h"
#include "base/no_destructor.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/content_browser_client.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/system/data_pipe.h"
#include "net/base/data_url.h"
#include "net/base/isolation_info.h"
#include "net/base/net_errors.h"
#include "net/http/http_response_headers.h"
#include "room/core/content_blocking/content_blocker.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/url_loader_completion_status.h"
#include "services/network/public/cpp/url_loader_factory_builder.h"
#include "services/network/public/mojom/url_loader.mojom.h"
#include "services/network/public/mojom/url_loader_factory.mojom.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/origin.h"

namespace room {
// Patch 0026 (chrome_content_browser_client.cc).
extern void (*g_url_loader_factory_hook)(
    content::BrowserContext* browser_context,
    content::RenderFrameHost* frame,
    int render_process_id,
    content::ContentBrowserClient::URLLoaderFactoryType type,
    const url::Origin& request_initiator,
    const net::IsolationInfo& isolation_info,
    network::URLLoaderFactoryBuilder& factory_builder);

namespace {

using FactoryType = content::ContentBrowserClient::URLLoaderFactoryType;

BlockedRequestCounter::ChangedCallback& ChangedCallbackStorage() {
  static base::NoDestructor<BlockedRequestCounter::ChangedCallback> callback;
  return *callback;
}

// Serves a $redirect resource (a data: URL from adblock-rust) to the client
// instead of the request. False if the URL does not parse (then: blocked).
bool ServeRedirect(const std::string& data_url,
                   mojo::Remote<network::mojom::URLLoaderClient>& client) {
  std::string mime_type, charset, data;
  scoped_refptr<net::HttpResponseHeaders> headers;
  if (net::DataURL::BuildResponse(GURL(data_url), "GET", &mime_type, &charset,
                                  &data, &headers) != net::OK) {
    return false;
  }
  headers->SetHeader("Access-Control-Allow-Origin", "*");
  mojo::ScopedDataPipeProducerHandle producer;
  mojo::ScopedDataPipeConsumerHandle consumer;
  if (mojo::CreateDataPipe(std::max<size_t>(data.size(), 1), producer,
                           consumer) != MOJO_RESULT_OK) {
    return false;
  }
  if (!data.empty() &&
      producer->WriteAllData(base::as_byte_span(data)) != MOJO_RESULT_OK) {
    return false;
  }
  auto head = network::mojom::URLResponseHead::New();
  head->mime_type = mime_type;
  head->charset = charset;
  head->headers = headers;
  head->content_length = data.size();
  client->OnReceiveResponse(std::move(head), std::move(consumer), std::nullopt);
  network::URLLoaderCompletionStatus status(net::OK);
  status.encoded_data_length = base::ByteSize(data.size());
  status.encoded_body_length = base::ByteSize(data.size());
  status.decoded_body_length = base::ByteSize(data.size());
  client->OnComplete(status);
  return true;
}

// Sits between a frame's (or worker's) URLLoaderFactory and the network:
// each request is matched once against the engine; a blocked one completes
// with ERR_BLOCKED_BY_CLIENT here, an allowed one goes to the real factory
// with its own client (no further hop). Lives on the UI thread until its
// last receiver or the target disconnects.
class ContentBlockingURLLoaderFactory : public network::mojom::URLLoaderFactory {
 public:
  ContentBlockingURLLoaderFactory(
      mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
      mojo::PendingRemote<network::mojom::URLLoaderFactory> target,
      content::GlobalRenderFrameHostId frame_id,
      GURL top_frame_url)
      : frame_id_(frame_id), top_frame_url_(std::move(top_frame_url)) {
    receivers_.Add(this, std::move(receiver));
    receivers_.set_disconnect_handler(
        base::BindRepeating(&ContentBlockingURLLoaderFactory::OnDisconnect,
                            base::Unretained(this)));
    target_.Bind(std::move(target));
    target_.set_disconnect_handler(
        base::BindOnce(&ContentBlockingURLLoaderFactory::Destroy,
                       base::Unretained(this)));
  }

  ContentBlockingURLLoaderFactory(const ContentBlockingURLLoaderFactory&) =
      delete;
  ContentBlockingURLLoaderFactory& operator=(
      const ContentBlockingURLLoaderFactory&) = delete;

  // network::mojom::URLLoaderFactory:
  void CreateLoaderAndStart(
      mojo::PendingReceiver<network::mojom::URLLoader> loader,
      int32_t request_id,
      uint32_t options,
      const network::ResourceRequest& request,
      mojo::PendingRemote<network::mojom::URLLoaderClient> client,
      const net::MutableNetworkTrafficAnnotationTag& traffic_annotation)
      override {
    DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
    ContentBlocker* blocker = ContentBlocker::Get();
    // Main documents always load; the page is the user's to open.
    if (blocker->active() &&
        request.destination != network::mojom::RequestDestination::kDocument) {
      const GURL top = TopFrameURL();
      if (!blocker->IsAllowed(top)) {
        const GURL source = request.request_initiator
                                ? request.request_initiator->GetURL()
                                : top;
        const ContentBlockerMatch match = blocker->Check(
            request.url, source,
            RequestTypeFor(request.destination, request.keepalive),
            request.method);
        if (match.block) {
          mojo::Remote<network::mojom::URLLoaderClient> remote(
              std::move(client));
          if (match.redirect.empty() || !ServeRedirect(match.redirect, remote)) {
            remote->OnComplete(network::URLLoaderCompletionStatus(
                net::ERR_BLOCKED_BY_CLIENT));
          }
          CountBlocked();
          return;
        }
      }
    }
    target_->CreateLoaderAndStart(std::move(loader), request_id, options,
                                  request, std::move(client),
                                  traffic_annotation);
  }

  void Clone(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver)
      override {
    receivers_.Add(this, std::move(receiver));
  }

 private:
  ~ContentBlockingURLLoaderFactory() override = default;

  // The page's current top-level URL when the factory belongs to a frame
  // (its document changes under a navigation factory), else the factory's.
  GURL TopFrameURL() const {
    if (content::RenderFrameHost* frame =
            content::RenderFrameHost::FromID(frame_id_)) {
      return frame->GetOutermostMainFrame()->GetLastCommittedURL();
    }
    return top_frame_url_;
  }

  void CountBlocked() {
    content::RenderFrameHost* frame =
        content::RenderFrameHost::FromID(frame_id_);
    content::WebContents* contents =
        frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
    if (!contents) {
      return;
    }
    BlockedRequestCounter::CreateForWebContents(contents);
    BlockedRequestCounter::FromWebContents(contents)->Increment();
  }

  void OnDisconnect() {
    if (receivers_.empty()) {
      Destroy();
    }
  }

  void Destroy() { delete this; }

  mojo::ReceiverSet<network::mojom::URLLoaderFactory> receivers_;
  mojo::Remote<network::mojom::URLLoaderFactory> target_;
  const content::GlobalRenderFrameHostId frame_id_;
  const GURL top_frame_url_;
};

void MaybeProxy(content::BrowserContext* browser_context,
                content::RenderFrameHost* frame,
                int render_process_id,
                FactoryType type,
                const url::Origin& request_initiator,
                const net::IsolationInfo& isolation_info,
                network::URLLoaderFactoryBuilder& factory_builder) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  // Downloads are the user's; the rest is decided per request. A factory
  // made while blocking is off stays unproxied until the frame's next
  // document (each commit makes new factories).
  if (type == FactoryType::kDownload || !ContentBlocker::Get()->active()) {
    return;
  }
  content::GlobalRenderFrameHostId frame_id;
  if (frame) {
    frame_id = frame->GetGlobalId();
  }
  GURL top_frame_url;
  if (isolation_info.top_frame_origin()) {
    top_frame_url = isolation_info.top_frame_origin()->GetURL();
  }
  auto [receiver, target] = factory_builder.Append();
  // Owns itself (deleted on disconnect).
  new ContentBlockingURLLoaderFactory(std::move(receiver), std::move(target),
                                      frame_id, std::move(top_frame_url));
}

}  // namespace

void InstallNetworkBlockingHook() {
  g_url_loader_factory_hook = &MaybeProxy;
}

// static
void BlockedRequestCounter::SetChangedCallback(ChangedCallback callback) {
  ChangedCallbackStorage() = std::move(callback);
}

// static
int BlockedRequestCounter::CountFor(content::WebContents* contents) {
  BlockedRequestCounter* counter = FromWebContents(contents);
  return counter ? counter->count() : 0;
}

BlockedRequestCounter::BlockedRequestCounter(content::WebContents* contents)
    : content::WebContentsObserver(contents),
      content::WebContentsUserData<BlockedRequestCounter>(*contents) {}

BlockedRequestCounter::~BlockedRequestCounter() = default;

void BlockedRequestCounter::Increment() {
  ++count_;
  Notify();
}

void BlockedRequestCounter::PrimaryPageChanged(content::Page& page) {
  if (count_ != 0) {
    count_ = 0;
    Notify();
  }
}

void BlockedRequestCounter::Notify() {
  if (ChangedCallbackStorage()) {
    ChangedCallbackStorage().Run(web_contents(), count_);
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BlockedRequestCounter);

}  // namespace room
