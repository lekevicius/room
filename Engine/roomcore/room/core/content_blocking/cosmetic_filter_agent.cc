// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include "room/core/content_blocking/cosmetic_filter_agent.h"

#include <set>
#include <utility>

#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/task/sequenced_task_runner.h"
#include "base/values.h"
#include "content/public/renderer/render_frame.h"
#include "extensions/renderer/extension_frame_helper.h"
#include "gin/converter.h"
#include "gin/function_template.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "third_party/blink/public/platform/web_isolated_world_info.h"
#include "third_party/blink/public/platform/web_security_origin.h"
#include "third_party/blink/public/mojom/script/script_evaluation_params.mojom.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_css_origin.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"
#include "url/origin.h"
#include "v8/include/v8-context.h"
#include "v8/include/v8-function.h"
#include "v8/include/v8-isolate.h"
#include "v8/include/v8-object.h"
#include "v8/include/v8-primitive.h"

namespace room {
// Patch 0027 (chrome_content_renderer_client.cc).
extern void (*g_render_frame_created_hook)(content::RenderFrame*);

namespace {

// Reports every class and id the document shows (once each) to the native
// roomHiddenSelectors, which answers with the generic hide selectors they
// trigger. Runs in kContentBlockingWorldId from DidCreateDocumentElement.
constexpr char kClassIdCollector[] = R"JS((() => {
  const send = globalThis.roomHiddenSelectors;
  const root = document.documentElement;
  if (!send || !root || globalThis.__roomCollector) return;
  globalThis.__roomCollector = true;
  const seenClasses = new Set(), seenIds = new Set();
  let classes = [], ids = [], timer = 0;
  const note = (el) => {
    const list = el.classList;
    if (list) for (let i = 0; i < list.length; i++) {
      const c = list[i];
      if (!seenClasses.has(c)) { seenClasses.add(c); classes.push(c); }
    }
    const id = el.id;
    if (id && !seenIds.has(id)) { seenIds.add(id); ids.push(id); }
  };
  const scan = (node) => {
    if (node.nodeType !== 1) return;
    note(node);
    for (const el of node.querySelectorAll('[class],[id]')) note(el);
  };
  const flush = () => {
    timer = 0;
    if (!classes.length && !ids.length) return;
    const c = classes, i = ids;
    classes = []; ids = [];
    send(c, i);
  };
  scan(root);
  flush();
  new MutationObserver((records) => {
    for (const r of records) {
      if (r.type === 'attributes') note(r.target);
      else for (const n of r.addedNodes) scan(n);
    }
    if (!timer) timer = setTimeout(flush, 25);
  }).observe(root, {childList: true, subtree: true, attributes: true,
                    attributeFilter: ['class', 'id']});
})();)JS";

// autoconsent's eval request: an expression from its bundled rule snippets
// ("(()=>!!window.Cookiebot)()"); run in the main world (where the consent
// platform's globals are) and answered with a boolean.
std::string MainWorldEvalWrapper(const std::string& code) {
  return "(() => { try { return !!(" + code + "); } catch (e) { "
         "return false; } })()";
}

}  // namespace

CosmeticFilterAgent::CosmeticFilterAgent(content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame) {
  render_frame->GetAssociatedInterfaceRegistry()
      ->AddInterface<mojom::CosmeticFilterAgent>(base::BindRepeating(
          &CosmeticFilterAgent::Bind, base::Unretained(this)));
}

CosmeticFilterAgent::~CosmeticFilterAgent() = default;

void CosmeticFilterAgent::Bind(
    mojo::PendingAssociatedReceiver<mojom::CosmeticFilterAgent> receiver) {
  receiver_.reset();
  receiver_.Bind(std::move(receiver));
}

void CosmeticFilterAgent::ActivateForNextCommittedLoad(
    mojom::CosmeticResourcesPtr resources,
    mojo::PendingRemote<mojom::CosmeticFilterHost> host) {
  pending_ = std::move(resources);
  pending_host_ = std::move(host);
}

void CosmeticFilterAgent::DidCommitProvisionalLoad(
    ui::PageTransition transition) {
  // Each document gets only what was pushed for it; a document committed
  // without a push (blocking off, an allowed site, not http) gets nothing.
  current_ = std::move(pending_);
  host_.reset();
  if (pending_host_) {
    host_.Bind(std::move(pending_host_));
  }
  cookie_banner_reported_ = false;
}

void CosmeticFilterAgent::DidCreateDocumentElement() {
  if (!current_) {
    return;
  }
  if (!current_->hide_selectors.empty()) {
    InsertHideStyleSheet(current_->hide_selectors);
  }
  // Script is forbidden inside this notification (Blink's
  // ScriptForbiddenScope); extensions' document-start scripts run from the
  // frame helper's next step, before the page's own scripts, and so do ours.
  if (auto* helper = extensions::ExtensionFrameHelper::Get(render_frame())) {
    helper->ScheduleAtDocumentStart(base::BindOnce(
        &CosmeticFilterAgent::RunAtDocumentStart, weak_factory_.GetWeakPtr()));
  }
}

void CosmeticFilterAgent::RunAtDocumentStart() {
  if (!current_) {
    return;
  }
  if (!current_->scriptlets.empty()) {
    render_frame()->GetWebFrame()->ExecuteScript(blink::WebScriptSource(
        blink::WebString::FromUtf8(current_->scriptlets)));
  }
  if (current_->collect_class_ids && host_) {
    RunInWorld(kClassIdCollector);
  }
  if (!current_->cookie_script.empty()) {
    RunInWorld(current_->cookie_script);
  }
}

void CosmeticFilterAgent::DidCreateScriptContext(
    v8::Local<v8::Context> context,
    int32_t world_id) {
  if (world_id != kContentBlockingWorldId) {
    return;
  }
  v8::Isolate* isolate = v8::Isolate::GetCurrent();
  v8::HandleScope handle_scope(isolate);
  v8::Context::Scope context_scope(context);
  v8::Local<v8::Object> global = context->Global();
  global
      ->Set(context, gin::StringToV8(isolate, "roomHiddenSelectors"),
            gin::CreateFunctionTemplate(
                isolate,
                base::BindRepeating(&CosmeticFilterAgent::RequestHiddenSelectors,
                                    weak_factory_.GetWeakPtr()))
                ->GetFunction(context)
                .ToLocalChecked())
      .Check();
  global
      ->Set(context, gin::StringToV8(isolate, "roomCookieSend"),
            gin::CreateFunctionTemplate(
                isolate,
                base::BindRepeating(&CosmeticFilterAgent::HandleCookieMessage,
                                    weak_factory_.GetWeakPtr()))
                ->GetFunction(context)
                .ToLocalChecked())
      .Check();
}

void CosmeticFilterAgent::OnDestruct() {
  delete this;
}

void CosmeticFilterAgent::InsertHideStyleSheet(
    const std::vector<std::string>& selectors) {
  // One rule per selector: one invalid selector would void a grouped rule.
  std::string css;
  for (const std::string& selector : selectors) {
    css += selector;
    css += "{display:none !important}\n";
  }
  render_frame()->GetWebFrame()->GetDocument().InsertStyleSheet(
      blink::WebString::FromUtf8(css), nullptr, blink::WebCssOrigin::kUser);
}

void CosmeticFilterAgent::RunInWorld(const std::string& script) {
  static bool named = [] {
    // A world of its own: an opaque origin (no site's privileges) and a name
    // for DevTools' context menu.
    blink::WebIsolatedWorldInfo info;
    info.security_origin = blink::WebSecurityOrigin(url::Origin());
    info.human_readable_name = blink::WebString::FromUtf8("Room Blocker");
    blink::SetIsolatedWorldInfo(kContentBlockingWorldId, info);
    return true;
  }();
  (void)named;
  const blink::WebScriptSource source(blink::WebString::FromUtf8(script));
  render_frame()->GetWebFrame()->RequestExecuteScript(
      kContentBlockingWorldId, base::span_from_ref(source),
      blink::mojom::UserActivationOption::kDoNotActivate,
      blink::mojom::EvaluationTiming::kSynchronous,
      blink::mojom::LoadEventBlockingOption::kDoNotBlock,
      blink::WebScriptExecutionCallback(), blink::BackForwardCacheAware::kAllow,
      blink::mojom::WantResultOption::kNoResult,
      blink::mojom::PromiseResultOption::kDoNotWait, blink::WebString());
}

void CosmeticFilterAgent::RequestHiddenSelectors(
    std::vector<std::string> classes,
    std::vector<std::string> ids) {
  if (!host_ || !current_ || current_->generichide) {
    return;
  }
  host_->HiddenClassIdSelectors(
      std::move(classes), std::move(ids),
      base::BindOnce(&CosmeticFilterAgent::OnHiddenSelectors,
                     weak_factory_.GetWeakPtr()));
}

void CosmeticFilterAgent::OnHiddenSelectors(
    const std::vector<std::string>& selectors) {
  if (!selectors.empty()) {
    InsertHideStyleSheet(selectors);
  }
}

void CosmeticFilterAgent::HandleCookieMessage(const std::string& json) {
  std::optional<base::DictValue> parsed =
      base::JSONReader::ReadDict(json, base::JSON_PARSE_RFC);
  if (!parsed) {
    return;
  }
  const base::DictValue& message = *parsed;
  const std::string* type = message.FindString("type");
  if (!type) {
    return;
  }
  if (*type == "eval") {
    const std::string* id = message.FindString("id");
    const std::string* code = message.FindString("code");
    if (!id || !code) {
      return;
    }
    blink::WebLocalFrame* frame = render_frame()->GetWebFrame();
    v8::Isolate* isolate = v8::Isolate::GetCurrent();
    v8::HandleScope handle_scope(isolate);
    v8::Local<v8::Value> value = frame->ExecuteScriptAndReturnValue(
        blink::WebScriptSource(
            blink::WebString::FromUtf8(MainWorldEvalWrapper(*code))));
    const bool result = !value.IsEmpty() && value->IsTrue();
    base::DictValue reply;
    reply.Set("type", "evalResp");
    reply.Set("id", *id);
    reply.Set("result", result);
    // Later, not now: autoconsent files the request as pending only after
    // its send returns, so a reply inside the send would be dropped.
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&CosmeticFilterAgent::RunInWorld, weak_factory_.GetWeakPtr(),
                       "globalThis.roomCookieReceive && globalThis.roomCookieReceive(" +
                           base::WriteJson(reply).value_or("{}") + ");"));
    return;
  }
  if ((*type == "optOutResult" || *type == "autoconsentDone") && host_ &&
      !cookie_banner_reported_) {
    const std::string* cmp = message.FindString("cmp");
    const bool opted_out =
        *type == "optOutResult" ? message.FindBool("result").value_or(false)
                                : !message.FindBool("isCosmetic").value_or(true);
    if (*type == "autoconsentDone" || opted_out) {
      cookie_banner_reported_ = true;
      host_->CookieBannerHandled(cmp ? *cmp : std::string(), opted_out);
    }
  }
}

namespace {
// Helpers enter ChromeMain directly (no RoomApplication); install the hook
// when the framework loads, as room_cdm_renderer.cc does.
[[maybe_unused]] const bool installed = [] {
  g_render_frame_created_hook = +[](content::RenderFrame* render_frame) {
    new CosmeticFilterAgent(render_frame);  // deletes itself (OnDestruct)
  };
  return true;
}();
}  // namespace

}  // namespace room
