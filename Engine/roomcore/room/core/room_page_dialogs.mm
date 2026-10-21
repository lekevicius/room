// Copyright 2026 Jonas Lekevicius. All rights reserved.

// JavaScript dialogs, beforeunload, the hung-page question and external
// protocols of Room pages (Phase 3.4b). Chrome keeps the policy around each
// (TabModalDialogManager: deferral for pages not shown, withdrawal on
// navigation, automation's Page.handleJavaScriptDialog; the app-modal queue
// for beforeunload, the quit's cancel; the hang monitor; the external
// protocol checks); the host draws the sheet and answers.
//
// Seams, no patch except the external protocol (0023):
// - alert/confirm/prompt: each Room page's TabModalDialogManager is
//   recreated with a //room TabModalDialogManagerDelegate whose views are the
//   host's sheets (Chrome's desktop delegate answers everything else, and
//   draws for pages whose delegate shows no dialogs).
// - beforeunload (a close, a reload, the quit) is app-modal in Chrome: //room
//   installs the AppModalDialogManager's native dialog factory and keeps
//   Chrome's Cocoa factory for every other page.
// - the hung-page dialog: each Room page's TabDialogs is wrapped by a //room
//   TabDialogs that asks the host and forwards the rest to Chrome's.
// - the password save, update and saved bubbles (5.8a): the same TabDialogs'
//   ShowManagePasswordsBubble/HideManagePasswordsBubble, the seam
//   ManagePasswordsUIController shows and hides its bubble through.

#import "room/core/room_page_ui_internal.h"
#import "room/core/room_web_contents_internal.h"

#include <memory>
#include <optional>
#include <string>
#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/chrome_browser_application_mac.h"
#include "chrome/browser/external_protocol/external_protocol_handler.h"
#include "chrome/browser/ui/javascript_dialogs/javascript_tab_modal_dialog_manager_delegate_desktop.h"
#include "chrome/browser/ui/passwords/bubble_controllers/password_bubble_controller_base.h"
#include "chrome/browser/ui/passwords/bubble_controllers/save_update_bubble_controller.h"
#include "chrome/browser/ui/passwords/passwords_model_delegate.h"
#include "chrome/browser/ui/tab_dialogs.h"
#include "components/javascript_dialogs/app_modal_dialog_controller.h"
#include "components/javascript_dialogs/app_modal_dialog_manager.h"
#include "components/javascript_dialogs/app_modal_dialog_view.h"
#include "components/javascript_dialogs/tab_modal_dialog_manager.h"
#include "components/javascript_dialogs/tab_modal_dialog_manager_delegate.h"
#include "components/javascript_dialogs/tab_modal_dialog_view.h"
#include "components/password_manager/core/browser/password_form.h"
#include "components/password_manager/core/common/password_manager_ui.h"
#include "content/public/browser/javascript_dialog_manager.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/result_codes.h"
#include "net/base/apple/url_conversions.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace room {
// Defined in chrome/browser/ui/views/external_protocol_dialog.cc
// (patches/0023-external-protocol-dialog-hook.patch).
extern bool (*g_run_external_protocol_dialog_hook)(
    const GURL&,
    content::WebContents*,
    bool has_user_gesture,
    const std::optional<url::Origin>&,
    content::WeakDocumentPtr&,
    const std::u16string& program_name);
}  // namespace room

namespace {

NSURL* OriginURL(const url::Origin& origin) {
  return origin.opaque() ? nil : net::NSURLWithGURL(origin.GetURL());
}

NSURL* MainFrameOrigin(content::WebContents* contents) {
  return contents
             ? OriginURL(contents->GetPrimaryMainFrame()->GetLastCommittedOrigin())
             : nil;
}

RoomJavaScriptDialogType ToRoomDialogType(content::JavaScriptDialogType type) {
  switch (type) {
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      return RoomJavaScriptDialogTypeConfirm;
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      return RoomJavaScriptDialogTypePrompt;
    case content::JAVASCRIPT_DIALOG_TYPE_ALERT:
    default:
      return RoomJavaScriptDialogTypeAlert;
  }
}

const char* DialogName(content::JavaScriptDialogType type) {
  switch (type) {
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      return "confirm";
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      return "prompt";
    default:
      return "alert";
  }
}

#define kRunDialog \
  @selector(webContents:runJavaScriptDialog:message:defaultText:origin:completion:)
#define kRunBeforeUnload \
  @selector(webContents:runBeforeUnloadDialogForReload:completion:)

void NotifyDialogsDismissed(RoomWebContents* wrapper) {
  id<RoomWebContentsDelegate> delegate = wrapper.delegate;
  if ([delegate
          respondsToSelector:@selector(webContentsDidDismissJavaScriptDialogs:)]) {
    [delegate webContentsDidDismissJavaScriptDialogs:wrapper];
  }
}

// MARK: - alert, confirm, prompt

// The host's sheet in place of Chrome's TabModalDialogViews. It owns itself
// until the host answers (the manager's button callback) or the manager
// withdraws it (CloseDialogWithoutCallback: a navigation, the page hidden or
// closing, a later dialog, automation).
class RoomTabModalDialogView : public javascript_dialogs::TabModalDialogView {
 public:
  static base::WeakPtr<javascript_dialogs::TabModalDialogView> Show(
      RoomWebContents* wrapper,
      content::WebContents* alerting_contents,
      content::JavaScriptDialogType type,
      const std::u16string& message,
      const std::u16string& default_prompt,
      content::JavaScriptDialogManager::DialogClosedCallback button_callback) {
    auto* view = new RoomTabModalDialogView(wrapper, default_prompt,
                                            std::move(button_callback));
    base::WeakPtr<javascript_dialogs::TabModalDialogView> result =
        view->weak_factory_.GetWeakPtr();
    view->Ask(alerting_contents, type, message);
    return result;
  }

  // javascript_dialogs::TabModalDialogView:
  void CloseDialogWithoutCallback() override {
    RoomWebContents* wrapper = wrapper_;
    LOG(INFO) << "RoomCore: JavaScript dialog withdrawn";
    delete this;
    NotifyDialogsDismissed(wrapper);
  }
  std::u16string GetUserInput() override { return default_prompt_; }

 private:
  RoomTabModalDialogView(
      RoomWebContents* wrapper,
      const std::u16string& default_prompt,
      content::JavaScriptDialogManager::DialogClosedCallback button_callback)
      : wrapper_(wrapper),
        default_prompt_(default_prompt),
        button_callback_(std::move(button_callback)) {}
  ~RoomTabModalDialogView() override = default;

  void Ask(content::WebContents* alerting_contents,
           content::JavaScriptDialogType type,
           const std::u16string& message) {
    LOG(INFO) << "RoomCore: JavaScript " << DialogName(type)
              << " to the host";
    base::WeakPtr<RoomTabModalDialogView> weak = weak_factory_.GetWeakPtr();
    RoomWebContents* wrapper = wrapper_;
    [wrapper.delegate webContents:wrapper
              runJavaScriptDialog:ToRoomDialogType(type)
                          message:base::SysUTF16ToNSString(message)
                      defaultText:base::SysUTF16ToNSString(default_prompt_)
                           origin:MainFrameOrigin(alerting_contents)
                       completion:^(BOOL accepted, NSString* text) {
                         if (weak) {
                           weak->Answer(accepted, text);
                         }
                       }];
  }

  void Answer(bool accepted, NSString* text) {
    const std::u16string input =
        text ? base::SysNSStringToUTF16(text) : std::u16string();
    // TabModalDialogManager::CloseDialog(kDialogButtonClicked, ...): the
    // page's callback, then the manager forgets this view. It returns early
    // when the view is already gone, so the view goes after it.
    base::WeakPtr<RoomTabModalDialogView> weak = weak_factory_.GetWeakPtr();
    std::move(button_callback_).Run(accepted, input);
    if (weak) {
      delete this;
    }
  }

  RoomWebContents* __weak wrapper_;
  const std::u16string default_prompt_;
  content::JavaScriptDialogManager::DialogClosedCallback button_callback_;
  base::WeakPtrFactory<RoomTabModalDialogView> weak_factory_{this};
};

// Chrome's desktop delegate with the host's sheets for pages whose delegate
// shows dialogs. "Foremost" for such a page is "the host shows it" (its view
// is in a visible window): the host, not a Chrome window, decides which page
// is in front.
class RoomTabModalDialogDelegate
    : public javascript_dialogs::TabModalDialogManagerDelegate {
 public:
  explicit RoomTabModalDialogDelegate(content::WebContents* contents)
      : contents_(contents),
        chrome_(std::make_unique<JavaScriptTabModalDialogManagerDelegateDesktop>(
            contents)) {}
  ~RoomTabModalDialogDelegate() override = default;

  base::WeakPtr<javascript_dialogs::TabModalDialogView> CreateNewDialog(
      content::WebContents* alerting_web_contents,
      const std::u16string& title,
      content::JavaScriptDialogType dialog_type,
      const std::u16string& message_text,
      const std::u16string& default_prompt_text,
      content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
      base::OnceClosure dialog_closed_callback) override {
    RoomWebContents* wrapper = room::WrapperAnswering(contents_, kRunDialog);
    if (!wrapper) {
      return chrome_->CreateNewDialog(
          alerting_web_contents, title, dialog_type, message_text,
          default_prompt_text, std::move(dialog_callback),
          std::move(dialog_closed_callback));
    }
    return RoomTabModalDialogView::Show(wrapper, alerting_web_contents,
                                        dialog_type, message_text,
                                        default_prompt_text,
                                        std::move(dialog_callback));
  }
  void WillRunDialog() override { chrome_->WillRunDialog(); }
  void DidCloseDialog() override { chrome_->DidCloseDialog(); }
  void SetTabNeedsAttention(bool attention) override {
    chrome_->SetTabNeedsAttention(attention);
  }
  bool IsWebContentsForemost() override {
    if (room::WrapperAnswering(contents_, kRunDialog)) {
      return contents_->GetVisibility() == content::Visibility::VISIBLE;
    }
    return chrome_->IsWebContentsForemost();
  }
  bool IsApp() override { return chrome_->IsApp(); }
  bool CanShowModalUI() override { return chrome_->CanShowModalUI(); }

 private:
  raw_ptr<content::WebContents> contents_;
  std::unique_ptr<JavaScriptTabModalDialogManagerDelegateDesktop> chrome_;
};

// MARK: - beforeunload (app-modal)

// The host's Leave/Stay sheet in place of Chrome's Cocoa alert
// (JavaScriptAppModalDialogCocoa), for a close, a reload or the quit. Owns
// the controller and itself, as Chrome's view does.
class RoomAppModalDialogView : public javascript_dialogs::AppModalDialogView {
 public:
  RoomAppModalDialogView(
      std::unique_ptr<javascript_dialogs::AppModalDialogController> controller,
      RoomWebContents* wrapper)
      : controller_(std::move(controller)), wrapper_(wrapper) {}
  ~RoomAppModalDialogView() override = default;

  // javascript_dialogs::AppModalDialogView:
  void ShowAppModalDialog() override {
    showing_ = true;
    base::WeakPtr<RoomAppModalDialogView> weak = weak_factory_.GetWeakPtr();
    RoomWebContents* wrapper = wrapper_;
    if (controller_->is_before_unload_dialog()) {
      LOG(INFO) << "RoomCore: beforeunload to the host (reload="
                << controller_->is_reload() << ")";
      [wrapper.delegate webContents:wrapper
          runBeforeUnloadDialogForReload:controller_->is_reload()
                              completion:^(BOOL leave) {
                                if (weak) {
                                  weak->Finish(leave, nil);
                                }
                              }];
      return;
    }
    // An app-modal alert, confirm or prompt (extensions, pages without a
    // tab-modal manager).
    [wrapper.delegate
        webContents:wrapper
        runJavaScriptDialog:ToRoomDialogType(controller_->javascript_dialog_type())
                    message:base::SysUTF16ToNSString(controller_->message_text())
                defaultText:base::SysUTF16ToNSString(
                                controller_->default_prompt_text())
                     origin:MainFrameOrigin(controller_->web_contents())
                 completion:^(BOOL accepted, NSString* text) {
                   if (weak) {
                     weak->Finish(accepted, text);
                   }
                 }];
  }
  void ActivateAppModalDialog() override {}
  // Invalidated (a navigation, the page closing) or the queue closes it.
  void CloseAppModalDialog() override {
    RoomWebContents* wrapper = wrapper_;
    LOG(INFO) << "RoomCore: app-modal dialog withdrawn";
    controller_->OnClose();
    delete this;
    NotifyDialogsDismissed(wrapper);
  }
  // Automation (Page.handleJavaScriptDialog through the manager).
  void AcceptAppModalDialog() override {
    RoomWebContents* wrapper = wrapper_;
    Finish(true, nil);
    NotifyDialogsDismissed(wrapper);
  }
  void CancelAppModalDialog() override {
    RoomWebContents* wrapper = wrapper_;
    Finish(false, nil);
    NotifyDialogsDismissed(wrapper);
  }
  bool IsShowing() const override { return showing_; }

 private:
  // What JavaScriptAppModalDialogCocoa::OnAlertFinished does.
  void Finish(bool accepted, NSString* text) {
    if (accepted) {
      controller_->OnAccept(text ? base::SysNSStringToUTF16(text)
                                 : controller_->default_prompt_text(),
                            /*suppress_js_messages=*/false);
    } else {
      // Staying on the page stops a quit in progress.
      if (controller_->is_before_unload_dialog()) {
        chrome_browser_application_mac::CancelTerminate();
      }
      controller_->OnCancel(/*suppress_js_messages=*/false);
    }
    delete this;
  }

  std::unique_ptr<javascript_dialogs::AppModalDialogController> controller_;
  RoomWebContents* __weak wrapper_;
  bool showing_ = false;
  base::WeakPtrFactory<RoomAppModalDialogView> weak_factory_{this};
};

// MARK: - Password offers (5.8a)

// The password manager's automatic bubbles of one page offered to the host:
// ManagePasswordsUIController shows its bubble through the page's TabDialogs
// (ShowManagePasswordsBubble), which the Views bubble would read its state
// from. For the save and update states the host is asked first; when it takes
// the offer, Chrome's own SaveUpdateBubbleController (no view) stands in for
// the bubble, so the answer goes through the same controller calls, metrics
// and dismissal counts as the Views buttons, and its destruction reports the
// bubble hidden. The saved confirmations are confirmed by the host or drawn by
// Chrome. Everything else (the manage bubble from a user action, generation's
// add-username, biometrics, move to account, leak and post-save bubbles) is
// Chrome's.
class PasswordOffers {
 public:
  explicit PasswordOffers(content::WebContents* contents)
      : contents_(contents) {}
  PasswordOffers(const PasswordOffers&) = delete;
  PasswordOffers& operator=(const PasswordOffers&) = delete;
  ~PasswordOffers() = default;

  // TabDialogs::ShowManagePasswordsBubble without a user action: true when
  // the host took it (Chrome then draws nothing).
  bool Show() {
    base::WeakPtr<PasswordsModelDelegate> model =
        PasswordsModelDelegateFromWebContents(contents_);
    if (!model) {
      return false;
    }
    const password_manager::ui::State state = model->GetState();
    const bool pending =
        state == password_manager::ui::PENDING_PASSWORD_STATE ||
        state == password_manager::ui::PENDING_PASSWORD_UPDATE_STATE;
    // The saved confirmation (UPDATE_CONFIRMATION_STATE has no pending
    // password to read and stays Chrome's; both follow a generated password,
    // which Room's builds do not offer without Sync, B-72).
    const bool confirmation =
        state == password_manager::ui::SAVE_CONFIRMATION_STATE;
    if (!pending && !confirmation) {
      return false;
    }
    NSURL* origin = OriginURL(model->GetOrigin());
    if (!origin) {
      return false;
    }
    const password_manager::PasswordForm& form = model->GetPendingPassword();
    NSString* username = base::SysUTF16ToNSString(form.username_value);
    const NSInteger length = static_cast<NSInteger>(form.password_value.size());
    if (confirmation) {
      RoomWebContents* wrapper = room::WrapperAnswering(
          contents_, @selector(webContents:didSavePasswordForOrigin:username:
                                                         passwordLength:));
      if (!wrapper || ![wrapper.delegate webContents:wrapper
                             didSavePasswordForOrigin:origin
                                             username:username
                                       passwordLength:length]) {
        return false;
      }
      LOG(INFO) << "RoomCore: password saved, the host confirms it";
      // What the confirmation bubble's controller tells the model: shown,
      // then hidden (the state moves on to MANAGE_STATE).
      model->OnBubbleShown();
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(
                         [](base::WeakPtr<PasswordsModelDelegate> model) {
                           if (model) {
                             model->OnBubbleHidden();
                           }
                         },
                         model));
      return true;
    }
    RoomWebContents* wrapper = room::WrapperAnswering(
        contents_,
        @selector(webContents:willOfferPasswordForOrigin:username:passwordLength:
                                                   update:completion:));
    if (!wrapper) {
      return false;
    }
    Withdraw();  // An earlier offer still open (not expected: Chrome hides first).
    const bool update =
        state == password_manager::ui::PENDING_PASSWORD_UPDATE_STATE;
    const int offer = ++offer_;
    base::WeakPtr<PasswordOffers> weak = weak_factory_.GetWeakPtr();
    BOOL taken = [wrapper.delegate webContents:wrapper
                    willOfferPasswordForOrigin:origin
                                      username:username
                                passwordLength:length
                                        update:update
                                    completion:^(NSString* response) {
                                      // Never inside the host's call or a
                                      // controller callback: the next turn.
                                      std::string answer =
                                          base::SysNSStringToUTF8(response ?: @"");
                                      base::SequencedTaskRunner::GetCurrentDefault()
                                          ->PostTask(
                                              FROM_HERE,
                                              base::BindOnce(&PasswordOffers::Answer,
                                                             weak, offer,
                                                             std::move(answer)));
                                    }];
    if (!taken) {
      ++offer_;  // A late answer to the refused offer is ignored.
      return false;
    }
    LOG(INFO) << "RoomCore: password " << (update ? "update" : "save")
              << " offer taken by the host";
    // Shown: OnBubbleShown and the shown metrics, as the Views bubble's.
    controller_ = std::make_unique<SaveUpdateBubbleController>(
        model, PasswordBubbleControllerBase::DisplayReason::kAutomatic);
    update_ = update;
    return true;
  }

  // TabDialogs::HideManagePasswordsBubble: true when the host's offer was
  // the bubble (it is withdrawn; Chrome's own has nothing to close).
  bool Hide() { return Withdraw(); }

 private:
  bool Withdraw() {
    if (!controller_) {
      return false;
    }
    ++offer_;
    LOG(INFO) << "RoomCore: password offer withdrawn";
    // As a closing Views bubble: its controller goes on the next turn
    // (reporting no interaction to a model that still listens, and hidden).
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(
        FROM_HERE, std::move(controller_));
    RoomWebContents* wrapper = room::WrapperAnswering(
        contents_, @selector(webContentsDidWithdrawPasswordOffer:));
    [wrapper.delegate webContentsDidWithdrawPasswordOffer:wrapper];
    return true;
  }

  // The host's answer: the Views bubble's buttons.
  void Answer(int offer, std::string response) {
    if (offer != offer_ || !controller_) {
      return;  // Withdrawn or replaced meanwhile.
    }
    ++offer_;
    std::unique_ptr<SaveUpdateBubbleController> controller =
        std::move(controller_);
    LOG(INFO) << "RoomCore: the host answers the password "
              << (update_ ? "update" : "save") << " offer: " << response;
    base::WeakPtr<PasswordsModelDelegate> model =
        PasswordsModelDelegateFromWebContents(contents_);
    const password_manager::ui::State offered =
        update_ ? password_manager::ui::PENDING_PASSWORD_UPDATE_STATE
                : password_manager::ui::PENDING_PASSWORD_STATE;
    if (!model || model->GetState() != offered) {
      LOG(INFO) << "RoomCore: the password offer's state is gone";
      return;  // The controller closes as an unanswered bubble.
    }
    if (response == "save") {
      controller->OnSaveClicked();
    } else if (response == "never" && !update_) {
      controller->OnNeverForThisSiteClicked();
    } else if (update_) {
      controller->OnNoThanksClicked();
    } else {
      controller->OnNotNowClicked();
    }
    // The bubble closes: interactions reported, OnBubbleHidden.
    controller.reset();
  }

  raw_ptr<content::WebContents> contents_;
  std::unique_ptr<SaveUpdateBubbleController> controller_;
  bool update_ = false;
  int offer_ = 0;
  base::WeakPtrFactory<PasswordOffers> weak_factory_{this};
};

// MARK: - The hung-page question

// Chrome's TabDialogs for the page with the hung-page question and the
// password offers going to the host. Everything else is Chrome's (forwarded).
class RoomTabDialogs : public TabDialogs {
 public:
  static void Adopt(content::WebContents* contents) {
    if (!TabDialogs::FromWebContents(contents)) {
      return;
    }
    std::unique_ptr<base::SupportsUserData::Data> chrome =
        contents->TakeUserData(UserDataKey());
    contents->SetUserData(
        UserDataKey(),
        std::make_unique<RoomTabDialogs>(
            contents,
            std::unique_ptr<TabDialogs>(static_cast<TabDialogs*>(chrome.release()))));
  }

  RoomTabDialogs(content::WebContents* contents,
                 std::unique_ptr<TabDialogs> chrome)
      : contents_(contents), chrome_(std::move(chrome)), passwords_(contents) {}
  ~RoomTabDialogs() override = default;

  // TabDialogs:
  gfx::NativeView GetDialogParentView() const override {
    return chrome_->GetDialogParentView();
  }
  void ShowCollectedCookies() override { chrome_->ShowCollectedCookies(); }
  void ShowHungRendererDialog(
      content::RenderWidgetHost* render_widget_host,
      base::RepeatingClosure hang_monitor_restarter) override {
    RoomWebContents* wrapper = room::WrapperAnswering(
        contents_, @selector(webContentsRendererDidBecomeUnresponsive:
                                                        completion:));
    if (!wrapper) {
      chrome_->ShowHungRendererDialog(render_widget_host,
                                      std::move(hang_monitor_restarter));
      return;
    }
    process_id_ = render_widget_host->GetProcess()->GetDeprecatedID();
    routing_id_ = render_widget_host->GetRoutingID();
    restarter_ = std::move(hang_monitor_restarter);
    if (asking_) {
      return;  // The host's question is still open.
    }
    asking_ = true;
    const int question = ++question_;
    LOG(INFO) << "RoomCore: renderer unresponsive, asking the host";
    base::WeakPtr<RoomTabDialogs> weak = weak_factory_.GetWeakPtr();
    [wrapper.delegate
        webContentsRendererDidBecomeUnresponsive:wrapper
                                      completion:^(RoomUnresponsiveAction action) {
                                        if (weak && weak->question_ == question) {
                                          weak->Answer(action);
                                        }
                                      }];
  }
  void HideHungRendererDialog(
      content::RenderWidgetHost* render_widget_host) override {
    if (!asking_) {
      chrome_->HideHungRendererDialog(render_widget_host);
      return;
    }
    asking_ = false;
    ++question_;
    restarter_.Reset();
    LOG(INFO) << "RoomCore: renderer responsive again";
    RoomWebContents* wrapper =
        [RoomWebContents room_existingWrapperFor:contents_];
    id<RoomWebContentsDelegate> delegate = wrapper.delegate;
    if ([delegate respondsToSelector:@selector
                  (webContentsRendererDidBecomeResponsive:)]) {
      [delegate webContentsRendererDidBecomeResponsive:wrapper];
    }
  }
  bool IsShowingHungRendererDialog() override {
    return asking_ || chrome_->IsShowingHungRendererDialog();
  }
  void ShowDeprecatedAppsDialog(
      const extensions::ExtensionId& optional_launched_extension_id,
      const std::set<extensions::ExtensionId>& deprecated_app_ids,
      content::WebContents* web_contents) override {
    chrome_->ShowDeprecatedAppsDialog(optional_launched_extension_id,
                                      deprecated_app_ids, web_contents);
  }
  void ShowForceInstalledDeprecatedAppsDialog(
      const extensions::ExtensionId& app_id,
      content::WebContents* web_contents) override {
    chrome_->ShowForceInstalledDeprecatedAppsDialog(app_id, web_contents);
  }
  void ShowForceInstalledPreinstalledDeprecatedAppDialog(
      const extensions::ExtensionId& extension_id,
      content::WebContents* web_contents) override {
    chrome_->ShowForceInstalledPreinstalledDeprecatedAppDialog(extension_id,
                                                               web_contents);
  }
  void ShowManagePasswordsBubble(bool user_action) override {
    if (!user_action && passwords_.Show()) {
      return;
    }
    chrome_->ShowManagePasswordsBubble(user_action);
  }
  void HideManagePasswordsBubble() override {
    if (passwords_.Hide()) {
      return;
    }
    chrome_->HideManagePasswordsBubble();
  }

 private:
  // What HungRendererDialogView's buttons do.
  void Answer(RoomUnresponsiveAction action) {
    asking_ = false;
    if (action == RoomUnresponsiveActionTerminate) {
      content::RenderWidgetHost* widget =
          content::RenderWidgetHost::FromID(process_id_, routing_id_);
      LOG(INFO) << "RoomCore: the host ends the unresponsive renderer"
                << (widget ? "" : " (already gone)");
      restarter_.Reset();
      if (widget) {
        widget->GetProcess()->Shutdown(content::RESULT_CODE_HUNG);
      }
      return;
    }
    LOG(INFO) << "RoomCore: the host waits for the renderer";
    if (restarter_) {
      restarter_.Run();
    }
  }

  raw_ptr<content::WebContents> contents_;
  std::unique_ptr<TabDialogs> chrome_;
  PasswordOffers passwords_;
  bool asking_ = false;
  int question_ = 0;
  int process_id_ = 0;
  int routing_id_ = 0;
  base::RepeatingClosure restarter_;
  base::WeakPtrFactory<RoomTabDialogs> weak_factory_{this};
};

// MARK: - External protocols

}  // namespace

@interface RoomExternalProtocolRequest ()
- (instancetype)initWithURL:(NSURL*)URL
                     scheme:(NSString*)scheme
           initiatingOrigin:(NSURL*)origin
                userGesture:(BOOL)userGesture
            applicationName:(NSString*)applicationName;
@end

@implementation RoomExternalProtocolRequest

@synthesize URL = _URL;
@synthesize scheme = _scheme;
@synthesize initiatingOrigin = _initiatingOrigin;
@synthesize userGesture = _userGesture;
@synthesize applicationName = _applicationName;

- (instancetype)initWithURL:(NSURL*)URL
                     scheme:(NSString*)scheme
           initiatingOrigin:(NSURL*)origin
                userGesture:(BOOL)userGesture
            applicationName:(NSString*)applicationName {
  if ((self = [super init])) {
    _URL = [URL copy];
    _scheme = [scheme copy];
    _initiatingOrigin = [origin copy];
    _userGesture = userGesture;
    _applicationName = [applicationName copy];
  }
  return self;
}

- (NSString*)description {
  return [NSString
      stringWithFormat:@"<RoomExternalProtocolRequest %@ app=%@ from=%@ gesture=%d>",
                       _URL, _applicationName, _initiatingOrigin, _userGesture];
}

@end

namespace {

bool RunExternalProtocolDialog(const GURL& url,
                               content::WebContents* contents,
                               bool has_user_gesture,
                               const std::optional<url::Origin>& initiating_origin,
                               content::WeakDocumentPtr& initiator_document,
                               const std::u16string& program_name) {
  RoomWebContents* wrapper = room::WrapperAnswering(
      contents, @selector(webContents:shouldOpenExternalProtocol:completion:));
  NSURL* nsurl = url.is_valid() ? net::NSURLWithGURL(url) : nil;
  if (!wrapper || !nsurl) {
    return false;
  }
  RoomExternalProtocolRequest* request = [[RoomExternalProtocolRequest alloc]
       initWithURL:nsurl
            scheme:base::SysUTF8ToNSString(std::string(url.scheme()))
      initiatingOrigin:initiating_origin ? OriginURL(*initiating_origin) : nil
       userGesture:has_user_gesture
   applicationName:base::SysUTF16ToNSString(program_name)];
  LOG(INFO) << "RoomCore: external protocol "
            << base::SysNSStringToUTF8(request.description);
  base::WeakPtr<content::WebContents> weak = contents->GetWeakPtr();
  content::WeakDocumentPtr document = initiator_document;
  // A copy: a block captures a C++ reference as a reference, and Chrome's
  // URL is gone by the time the host answers (the first run launched an
  // empty URL).
  const GURL launch_url = url;
  auto answered = std::make_shared<bool>(false);
  [wrapper.delegate webContents:wrapper
      shouldOpenExternalProtocol:request
                      completion:^(BOOL open) {
                        if (*answered) {
                          return;
                        }
                        *answered = true;
                        if (!open || !weak) {
                          LOG(INFO) << "RoomCore: external protocol blocked "
                                    << launch_url.possibly_invalid_spec();
                          return;
                        }
                        LOG(INFO) << "RoomCore: external protocol opened "
                                  << launch_url.possibly_invalid_spec();
                        // What ExternalProtocolDialog::OnDialogAccepted does.
                        ExternalProtocolHandler::LaunchUrlWithoutSecurityCheck(
                            launch_url, weak.get(), document);
                      }];
  return true;
}

}  // namespace

namespace room {

void InstallPageDialogHooks() {
  g_run_external_protocol_dialog_hook = &RunExternalProtocolDialog;
}

void InstallAppModalDialogFactory() {
  javascript_dialogs::AppModalDialogManager* manager =
      javascript_dialogs::AppModalDialogManager::GetInstance();
  // Chrome's own (the Cocoa alert, installed in PreProfileInit) for every
  // page that is not a Room page answering dialogs.
  static base::NoDestructor<
      javascript_dialogs::AppModalDialogManager::AppModalViewFactory>
      chrome_factory(*manager->view_factory());
  manager->SetNativeDialogFactory(base::BindRepeating(
      [](std::unique_ptr<javascript_dialogs::AppModalDialogController> controller)
          -> javascript_dialogs::AppModalDialogView* {
        RoomWebContents* wrapper = WrapperAnswering(
            controller->web_contents(),
            controller->is_before_unload_dialog() ? kRunBeforeUnload
                                                  : kRunDialog);
        if (!wrapper) {
          return chrome_factory->Run(std::move(controller));
        }
        return new RoomAppModalDialogView(std::move(controller), wrapper);
      }));
}

void AdoptPageDialogs(content::WebContents* contents) {
  // Once per WebContents (a discard's replacement is a new one).
  static const char kAdopted = 0;
  if (!contents || contents->GetUserData(&kAdopted)) {
    return;
  }
  contents->SetUserData(&kAdopted,
                        std::make_unique<base::SupportsUserData::Data>());
  if (javascript_dialogs::TabModalDialogManager::FromWebContents(contents)) {
    contents->RemoveUserData(
        javascript_dialogs::TabModalDialogManager::UserDataKey());
    javascript_dialogs::TabModalDialogManager::CreateForWebContents(
        contents, std::make_unique<RoomTabModalDialogDelegate>(contents));
  }
  RoomTabDialogs::Adopt(contents);
}

}  // namespace room
