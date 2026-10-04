// Copyright 2026 Jonas Lekevicius. All rights reserved.

#import "room/core/public/RoomBrowser.h"

#include <memory>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "content/public/browser/permission_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "services/network/public/cpp/features.h"
#include "third_party/blink/public/common/permissions/permission_utils.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/ui/views/extensions/extension_popup.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/common/extension.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "components/permissions/permission_request.h"
#include "base/memory/ref_counted_memory.h"
#include "base/functional/bind.h"
#include "chrome/browser/ui/webid/identity_dialog_controller.h"
#include "third_party/blink/public/mojom/webid/federated_request.mojom.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/printing/print_preview_dialog_controller.h"
#include "chrome/browser/ui/webui/print_preview/print_preview_ui.h"
#include "content/public/browser/web_ui.h"
#include "printing/print_job_constants.h"
#include "chrome/browser/devtools/devtools_ui_controller.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/download_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/autofill/address_bubbles_controller.h"
#include "chrome/browser/autofill/personal_data_manager_factory.h"
#include "chrome/browser/ui/autofill/chrome_autofill_client.h"
#include "chrome/browser/ui/autofill/payments/save_card_bubble_controller_impl.h"
#include "chrome/browser/ui/tab_dialogs.h"
#include "chrome/browser/ui/views/passwords/password_bubble_view_base.h"
#include "chrome/browser/ui/views/frame/toolbar_button_provider.h"
#include "components/autofill/core/browser/data_manager/personal_data_manager.h"
#include "components/autofill/content/browser/content_autofill_driver.h"
#include "components/autofill/core/browser/foundations/autofill_manager.h"
#include "components/autofill/core/browser/form_structure.h"
#include "content/public/browser/render_widget_host_view.h"
#include "components/autofill/core/browser/data_model/payments/credit_card.h"
#include "chrome/browser/ui/autofill/autofill_bubble_base.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/permissions/permission_request_manager.h"
#include "content/public/browser/web_contents.h"
#include "ui/views/widget/widget.h"
#include "ui/views/window/dialog_delegate.h"
#import "room/browser/room_browser_window.h"
#import "room/core/room_profile_internal.h"
#import "room/core/room_web_contents_internal.h"

@interface RoomBrowser ()
- (void)room_activeContentsChanged:(content::WebContents*)contents;
- (void)room_windowWillClose;
- (void)room_windowDestroyed;
@end

namespace {

class Client : public room::RoomBrowserWindowClient {
 public:
  explicit Client(RoomBrowser* browser) : browser_(browser) {}

  void OnActiveContentsChanged(content::WebContents* contents) override {
    [browser_ room_activeContentsChanged:contents];
  }
  void OnBrowserWindowWillClose() override { [browser_ room_windowWillClose]; }
  void OnBrowserWindowDestroyed() override { [browser_ room_windowDestroyed]; }

 private:
  RoomBrowser* __weak browser_;
};

}  // namespace

@implementation RoomBrowser {
  RoomProfile* _profile;
  NSWindow* __weak _window;
  raw_ptr<BrowserWindowInterface> _browser;
  std::unique_ptr<Client> _client;
  std::unique_ptr<IdentityDialogController> _spike_identity_controller;
  std::shared_ptr<int> _spike_address_decisions;
  std::shared_ptr<int> _spike_card_decisions;
  // Wrappers of the pages in the tab strip, so KVO observers the host set up
  // survive as long as the page does.
  NSMutableArray<RoomWebContents*>* _pages;
  RoomWebContents* __weak _activeWebContents;
}

@synthesize delegate = _delegate;

- (instancetype)initWithProfile:(RoomProfile*)profile window:(NSWindow*)window {
  if ((self = [super init])) {
    Profile* chromeProfile = profile.room_profile;
    CHECK(chromeProfile) << "RoomBrowser on a destroyed profile";
    _profile = profile;
    _window = window;
    _pages = [NSMutableArray array];
    _client = std::make_unique<Client>(self);

    room::ScopedPendingHostWindow pending(window, _client.get());
    BrowserWindowCreateParams params(BrowserWindowInterface::TYPE_NORMAL,
                                     *chromeProfile,
                                     /*from_user_gesture=*/true);
    _browser = CreateBrowserWindow(std::move(params));
  }
  return self;
}

- (void)dealloc {
  // The Browser outlives its wrapper only if the host drops it without
  // closing; the window must not call back into a dead object.
  _client.reset();
}

- (RoomProfile*)profile {
  return _profile;
}

- (NSWindow*)window {
  return _window;
}

- (BOOL)isClosed {
  return _browser == nullptr;
}

- (NSArray<RoomWebContents*>*)webContents {
  NSMutableArray<RoomWebContents*>* result = [NSMutableArray array];
  if (!_browser) {
    return result;
  }
  TabStripModel* strip = _browser->GetTabStripModel();
  for (int i = 0; i < strip->count(); ++i) {
    if (RoomWebContents* wrapper = [RoomWebContents
            room_existingWrapperFor:strip->GetWebContentsAt(i)]) {
      [result addObject:wrapper];
    }
  }
  return result;
}

- (RoomWebContents*)activeWebContents {
  return _activeWebContents;
}

- (void)addWebContents:(RoomWebContents*)webContents activate:(BOOL)activate {
  CHECK(_browser) << "addWebContents on a closed browser";
  std::unique_ptr<content::WebContents> owned =
      [webContents room_releaseWebContents];
  CHECK(owned) << "the page already belongs to a browser";
  [_pages addObject:webContents];
  _browser->GetTabStripModel()->AppendWebContents(std::move(owned), activate);
}

- (void)close {
  if (_browser) {
    chrome::CloseWindow(_browser);
  }
}

- (void)room_activeContentsChanged:(content::WebContents*)contents {
  RoomWebContents* wrapper = [RoomWebContents room_existingWrapperFor:contents];
  [self willChangeValueForKey:@"activeWebContents"];
  _activeWebContents = wrapper;
  [self didChangeValueForKey:@"activeWebContents"];
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browser:didActivateWebContents:)]) {
    [delegate browser:self didActivateWebContents:wrapper];
  }
}

- (void)room_windowWillClose {
  _spike_identity_controller.reset();
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserWillClose:)]) {
    [delegate browserWillClose:self];
  }
}

- (void)room_windowDestroyed {
  [self willChangeValueForKey:@"closed"];
  _browser = nullptr;
  [self didChangeValueForKey:@"closed"];
  [_pages removeAllObjects];
  id<RoomBrowserDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(browserDidClose:)]) {
    [delegate browserDidClose:self];
  }
}

// Spike-only entry point; intentionally absent from the public API.
- (NSNumber*)roomSpikeCommand:(NSNumber*)command {
  if (!_browser ||
      ![[NSProcessInfo processInfo].arguments containsObject:@"-RoomSpike"]) {
    return @NO;
  }
  const int command_id = command.intValue;
  switch (command_id) {
    case IDC_FIND:
    case IDC_FIND_NEXT:
    case IDC_CLOSE_FIND_OR_STOP:
    case IDC_ZOOM_PLUS:
    case IDC_ZOOM_MINUS:
    case IDC_ZOOM_NORMAL:
    case IDC_PRINT:
    case IDC_DEV_TOOLS:
      if (!chrome::IsCommandEnabled(_browser, command_id)) {
        return @NO;
      }
      return @(chrome::ExecuteCommand(_browser, command_id));
    default:
      return @NO;
  }
}

// Bounded fixture actions use Chrome's real completion paths, not synthetic
// web permission overrides. Kept private and disabled outside spike runs.
- (NSNumber*)roomSpikeAction:(NSString*)action {
  if (!_browser ||
      ![[NSProcessInfo processInfo].arguments containsObject:@"-RoomSpike"]) {
    return @(-1);
  }
  auto* contents = _browser->GetTabStripModel()->GetActiveWebContents();
  if (!contents || contents->GetVisibleURL().host() != "127.0.0.1") {
    return @(-1);
  }
  if ([action hasPrefix:@"network-"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("ip-address-space-overrides")) {
      return @(-1);
    }
    if ([action isEqualToString:@"network-flags"]) {
      const int flags = (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecks) ? 1 : 0) |
                        (network::features::kLocalNetworkAccessChecksWarn.Get() ? 2 : 0) |
                        (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecksWebSockets) ? 4 : 0) |
                        (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecksWebTransport) ? 8 : 0) |
                        (base::FeatureList::IsEnabled(network::features::kLocalNetworkAccessChecksWebRTC) ? 16 : 0);
      return @(flags);
    }
    if ([action isEqualToString:@"network-reset"]) {
      auto* controller = _profile.room_profile->GetPermissionController();
      const auto origin = contents->GetPrimaryMainFrame()->GetLastCommittedOrigin();
      controller->ResetPermission(blink::PermissionType::LOCAL_NETWORK, origin);
      controller->ResetPermission(blink::PermissionType::LOOPBACK_NETWORK, origin);
      return @1;
    }
    auto* manager = permissions::PermissionRequestManager::FromWebContents(contents);
    if (!manager || !manager->IsRequestInProgress() || manager->Requests().empty()) { return @0; }
    for (const auto& request : manager->Requests()) {
      if (request->request_type() != permissions::RequestType::kLocalNetwork &&
          request->request_type() != permissions::RequestType::kLoopbackNetwork) { return @(-1); }
    }
    if ([action isEqualToString:@"network-accept"]) { manager->Accept(std::monostate{}); }
    return @1;
  }
  if ([action isEqualToString:@"download-prompt-enable"]) {
    _profile.room_profile->GetPrefs()->SetBoolean(prefs::kPromptForDownload, true);
    return @1;
  }
  if ([action isEqualToString:@"download-close-decision"]) {
    int count = _profile.room_profile->GetDownloadManager()->InProgressCount();
    if (count < 1) { return @(-1); }
    auto state = std::make_shared<int>(0);
    BrowserWindow::FromBrowser(_browser)->ConfirmBrowserCloseWithPendingDownloads(
        count, UnloadController::DownloadCloseType::kBrowserShutdown,
        base::BindOnce([](std::shared_ptr<int> result, bool cancel_downloads) {
          *result = 1 | (cancel_downloads ? 2 : 0);
          LOG(WARNING) << "Room UI probe download close callback cancel_downloads=" << cancel_downloads;
        }, state));
    LOG(WARNING) << "Room UI probe download close active=" << count << " immediate_state=" << *state;
    return @(*state);
  }
  if ([action hasPrefix:@"extension-popup-"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("load-extension")) {
      return @(-1);
    }
    if ([action isEqualToString:@"extension-popup-open"]) {
      auto* registry = extensions::ExtensionRegistry::Get(_profile.room_profile);
      for (const auto& extension : registry->enabled_extensions()) {
        if (extension->name() != "Room spike extension") {
          continue;
        }
        auto host = extensions::ExtensionViewHostFactory::CreatePopupHost(
            *extension, extension->GetResourceURL("popup.html"), _browser);
        if (!host) {
          return @(-1);
        }
        auto* window = static_cast<RoomBrowserWindow*>(BrowserWindow::FromBrowser(_browser));
        ExtensionPopup::ShowPopup(
            _browser, std::move(host), views::BubbleAnchor(window->GetBubbleAnchor()),
            views::BubbleBorder::TOP_LEFT, PopupShowAction::kShow,
            base::BindOnce([](extensions::ExtensionHost* shown) {
              LOG(WARNING) << "Room UI probe extension popup callback shown=" << (shown != nullptr);
            }));
        return @1;
      }
      return @0;
    }
    auto* popup = ExtensionPopup::last_popup_for_testing();
    if (!popup || !popup->host() || popup->host()->extension()->name() != "Room spike extension") {
      return @0;
    }
    auto* widget = popup->GetWidget();
    if ([action isEqualToString:@"extension-popup-close"]) {
      popup->CloseDeferredIfNecessary();
      return @1;
    }
    if ([action isEqualToString:@"extension-popup-size"]) {
      auto size = widget->GetClientAreaBoundsInScreen().size();
      return @(size.width() * 10000 + size.height());
    }
    NSWindow* native = widget->GetNativeWindow().GetNativeNSWindow();
    const bool owned = native.parentWindow == _window || native.parentWindow.parentWindow == _window;
    LOG(WARNING) << "Room UI probe extension popup visible=" << widget->IsVisible()
                 << " room_owned=" << owned << " active=" << widget->IsActive();
    return @(1 | (widget->IsVisible() ? 2 : 0) | (owned ? 4 : 0) |
             (widget->IsActive() ? 8 : 0));
  }
  if ([action isEqualToString:@"print-preview-pdf"]) {
    auto* dialogs = printing::PrintPreviewDialogController::GetInstance();
    auto* preview = dialogs ? dialogs->GetPrintPreviewForContents(contents) : nullptr;
    auto* ui = preview && preview->GetWebUI()
                   ? preview->GetWebUI()->GetController()->GetAs<printing::PrintPreviewUI>()
                   : nullptr;
    auto bytes = ui ? ui->GetPrintPreviewDataForIndex(
                          printing::COMPLETE_PREVIEW_DOCUMENT_INDEX)
                    : nullptr;
    if (!bytes || bytes->size() == 0) {
      return @0;
    }
    NSString* output = [NSUserDefaults.standardUserDefaults stringForKey:@"RoomSpikeOutput"];
    if (!output) {
      return @(-1);
    }
    NSString* path = [[output stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"generated-preview.pdf"];
    NSData* data = [NSData dataWithBytes:bytes->data() length:bytes->size()];
    NSError* error = nil;
    if (![data writeToFile:path options:NSDataWritingWithoutOverwriting error:&error]) {
      LOG(WARNING) << "Room UI probe preview write failed=" << error.localizedDescription.UTF8String;
      return @(-1);
    }
    NSWindow* window = preview->GetNativeView().GetNativeNSView().window;
    LOG(WARNING) << "Room UI probe preview bytes=" << bytes->size()
                 << " native_window=" << (window != nil)
                 << " parent_window=" << (window.parentWindow != nil);
    return @(bytes->size());
  }
  if ([action isEqualToString:@"devtools-state"]) {
    auto* devtools = DevToolsWindow::GetInstanceForInspectedWebContents(contents);
    auto* controller = DevtoolsUIController::From(_browser);
    int state = controller ? 1 : 0;
    if (devtools) {
      state |= 2;
      if (devtools->IsDocked()) {
        state |= 4;
      }
      auto* frontend = devtools->GetDevToolsWebContents().get();
      if (frontend && frontend->GetNativeView().GetNativeNSView().window) {
        state |= 8;
      }
      LOG(WARNING) << "Room UI probe DevTools state=" << state
                   << " can_dock=" << (controller && controller->CanDockDevtools())
                   << " frontend=" << (frontend ? frontend->GetVisibleURL().spec() : "none");
    }
    return @(state);
  }
  if ([action hasPrefix:@"ui-dialog-"]) {
    auto* window =
        static_cast<RoomBrowserWindow*>(BrowserWindow::FromBrowser(_browser));
    auto widgets = views::Widget::GetAllOwnedWidgets(
        window->GetBubbleAnchor()->GetWidget()->GetNativeView());
    int count = 0;
    for (const auto& widget : widgets) {
      auto* dialog = widget->widget_delegate()->AsDialogDelegate();
      if (!dialog || !widget->IsVisible()) {
        continue;
      }
      ++count;
      LOG(WARNING) << "Room UI probe dialog=" << widget->GetName();
      if ([action isEqualToString:@"ui-dialog-cancel"]) {
        dialog->CancelDialog();
        break;
      }
      if ([action isEqualToString:@"ui-dialog-accept"]) {
        dialog->AcceptDialog();
        break;
      }
    }
    return @(count);
  }
  if ([action isEqualToString:@"password-presentation"]) {
    auto* dialogs = TabDialogs::FromWebContents(contents);
    if (!dialogs) { return @(-1); }
    dialogs->ShowManagePasswordsBubble(true);
    bool provider = ToolbarButtonProvider::From(_browser) != nullptr;
    bool bubble = PasswordBubbleViewBase::manage_password_bubble() != nullptr;
    LOG(WARNING) << "Room UI probe password provider=" << provider << " bubble=" << bubble;
    return @(1 | (provider ? 2 : 0) | (bubble ? 4 : 0));
  }
  if ([action isEqualToString:@"card-save"]) {
    autofill::CreditCard card;
    card.SetRawInfo(autofill::CREDIT_CARD_NAME_FULL, u"Room Fixture");
    card.SetNumber(u"4111111111111111");
    card.SetExpirationMonth(12);
    card.SetExpirationYear(2030);
    autofill::SaveCardBubbleControllerImpl::CreateForWebContents(contents);
    _spike_card_decisions = std::make_shared<int>(0);
    autofill::SaveCardBubbleControllerImpl::FromWebContents(contents)->OfferLocalSave(
        card, autofill::payments::PaymentsAutofillClient::SaveCreditCardOptions().with_show_prompt(),
        base::BindOnce([](std::shared_ptr<int> count,
                         autofill::payments::PaymentsAutofillClient::SaveCardOfferUserDecision decision) {
          LOG(WARNING) << "Room UI probe local card decision=" << static_cast<int>(decision) << " count=" << ++*count;
        }, _spike_card_decisions));
    return @1;
  }
  if ([action isEqualToString:@"card-decisions"]) {
    return @(_spike_card_decisions ? *_spike_card_decisions : -1);
  }
  if ([action isEqualToString:@"address-profiles"]) {
    auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(_profile.room_profile);
    return @(data->address_data_manager().GetProfiles().size());
  }
  if ([action isEqualToString:@"address-diagnostics"]) {
    auto* client = autofill::ChromeAutofillClient::FromWebContentsForTesting(contents);
    auto* driver = autofill::ContentAutofillDriver::GetForRenderFrameHost(contents->GetPrimaryMainFrame());
    auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(_profile.room_profile);
    int forms = 0, fields = 0;
    if (driver) {
      driver->GetAutofillManager().ForEachCachedForm([&](const autofill::FormStructure& form) {
        ++forms; fields += form.fields().size();
      });
    }
    auto* view = contents->GetRenderWidgetHostView();
    LOG(WARNING) << "Room UI probe address enabled=" << (client && client->IsAutofillProfileEnabled())
                 << " eligible=" << data->address_data_manager().GetProfilesToSuggest().size()
                 << " view_focus=" << (view && view->HasFocus())
                 << " driver=" << (driver != nullptr) << " forms=" << forms << " fields=" << fields
                 << " can_show=" << (driver && driver->GetAutofillManager().CanShowAutofillUi());
    return @(forms);
  }
  if ([action isEqualToString:@"address-suggestions"]) {
    auto* client = autofill::ChromeAutofillClient::FromWebContentsForTesting(contents);
    if (!client) { return @(-1); }
    LOG(WARNING) << "Room UI probe autofill suggestions=" << client->GetAutofillSuggestions().size()
                 << " ui_session=" << client->GetSessionIdForCurrentAutofillSuggestions().has_value();
    return @(client->GetAutofillSuggestions().size());
  }
  if ([action isEqualToString:@"address-seed"] ||
      [action isEqualToString:@"address-save"] ||
      [action isEqualToString:@"address-update"]) {
    autofill::AutofillProfile address(autofill::AddressCountryCode("US"));
    address.SetRawInfo(autofill::NAME_FULL, u"Room Fixture");
    address.SetRawInfo(autofill::ADDRESS_HOME_STREET_ADDRESS, u"1 Test Street");
    address.SetRawInfo(autofill::ADDRESS_HOME_CITY, u"Mountain View");
    address.SetRawInfo(autofill::ADDRESS_HOME_STATE, u"CA");
    address.SetRawInfo(autofill::ADDRESS_HOME_ZIP, u"94043");
    if ([action isEqualToString:@"address-seed"]) {
      address.SetRawInfo(autofill::EMAIL_ADDRESS, u"room-fixture@example.test");
      address.FinalizeAfterImport();
      auto* data = autofill::PersonalDataManagerFactory::GetForBrowserContext(_profile.room_profile);
      data->address_data_manager().AddProfile(address);
      return @1;
    }
    autofill::AutofillProfile original(address);
    const bool update = [action isEqualToString:@"address-update"];
    if (update) {
      address.SetRawInfo(autofill::ADDRESS_HOME_STREET_ADDRESS,
                         u"2 Test Street");
    }
    _spike_address_decisions = std::make_shared<int>(0);
    autofill::AddressBubblesController::SetUpAndShowSaveOrUpdateAddressBubble(
        contents, address, update ? &original : nullptr,
        autofill::AutofillClient::SaveAddressBubbleType::kSave, update,
        base::BindOnce(
            [](std::shared_ptr<int> count,
               autofill::AutofillClient::AddressPromptUserDecision decision,
               base::optional_ref<const autofill::AutofillProfile>) {
              LOG(WARNING) << "Room UI probe address decision="
                           << static_cast<int>(decision)
                           << " count=" << ++*count;
            },
            _spike_address_decisions));
    return @1;
  }
  if ([action isEqualToString:@"address-visible"]) {
    auto* controller =
        autofill::AddressBubblesController::FromWebContents(contents);
    return @(controller && controller->GetBubbleView());
  }
  if ([action isEqualToString:@"address-decisions"]) {
    return @(_spike_address_decisions ? *_spike_address_decisions : -1);
  }
  if ([action isEqualToString:@"renderer-status"]) {
    int status = contents->IsCrashed() ? 1 : 0;
    for (NSView* view in contents->GetNativeView().GetNativeNSView().subviews) {
      if ([view.identifier isEqualToString:@"RoomSadTab"]) {
        status |= 2;
      }
    }
    return @(status);
  }
  if ([action isEqualToString:@"fedcm-close"]) {
    _spike_identity_controller.reset();
    return @1;
  }
  if ([action isEqualToString:@"fedcm-passive"] ||
      [action isEqualToString:@"fedcm-active"]) {
    _spike_identity_controller = std::make_unique<IdentityDialogController>(contents);
    content::IdentityProviderMetadata metadata;
    metadata.idp_login_url = contents->GetVisibleURL();
    if ([action isEqualToString:@"fedcm-active"]) {
      return @(_spike_identity_controller->ShowLoadingDialog(
          content::RelyingPartyData(u"RoomCore fixture", u""), "Local IdP",
          blink::mojom::RpContext::kSignIn, blink::mojom::RpMode::kActive,
          base::BindOnce([](content::IdentityRequestDialogController::DismissReason) {})));
    }
    return @(_spike_identity_controller->ShowFailureDialog(
        content::RelyingPartyData(u"RoomCore fixture", u""), "Local IdP",
        blink::mojom::RpContext::kSignIn,
        blink::mojom::RpMode::kPassive,
        metadata, {},
        base::BindOnce([](content::IdentityRequestDialogController::DismissReason) {}),
        base::BindRepeating([](const GURL&, GURL) {})));
  }
  if ([action isEqualToString:@"capture-state"]) {
    auto indicator = MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator();
    return @((indicator->IsCapturingAudio(contents) ? 1 : 0) |
             (indicator->IsCapturingVideo(contents) ? 2 : 0) |
             (indicator->IsCapturingDisplay(contents) ? 4 : 0));
  }
  if ([action isEqualToString:@"stop-fake-capture"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("use-fake-device-for-media-stream")) {
      return @(-1);
    }
    MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator()
        ->StopMediaCapturing(contents, MediaStreamCaptureIndicator::kUserMedia);
    return @1;
  }
  if ([action isEqualToString:@"accept-fake-capture"]) {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("use-fake-device-for-media-stream")) {
      return @(-1);
    }
    auto* manager = permissions::PermissionRequestManager::FromWebContents(contents);
    if (!manager || !manager->IsRequestInProgress() || manager->Requests().empty()) {
      return @0;
    }
    for (const auto& request : manager->Requests()) {
      if (request->request_type() != permissions::RequestType::kCameraStream &&
          request->request_type() != permissions::RequestType::kMicStream) {
        return @(-1);
      }
    }
    manager->Accept(std::monostate{});
    return @1;
  }
  if ([action isEqualToString:@"media-mute"]) {
    contents->SetAudioMuted(true);
    return @(contents->IsAudioMuted());
  }
  if ([action isEqualToString:@"media-state"]) {
    return @((contents->IsAudioMuted() ? 1 : 0) |
             (contents->IsCurrentlyAudible() ? 2 : 0));
  }
  if ([action isEqualToString:@"deny-permission"]) {
    auto* manager = permissions::PermissionRequestManager::FromWebContents(contents);
    if (!manager || !manager->IsRequestInProgress()) {
      return @0;
    }
    manager->Deny(std::monostate{});
    return @1;
  }
  if ([action isEqualToString:@"auth-cancel"] ||
      [action isEqualToString:@"auth-supply"]) {
    for (auto* handler : LoginHandler::GetAllLoginHandlersForTest()) {
      if (handler->web_contents() == contents) {
        if ([action isEqualToString:@"auth-cancel"]) {
          handler->CancelAuth(false);
        } else {
          handler->SetAuth(u"room", u"spike");
        }
        return @1;
      }
    }
    return @0;
  }
  auto* find = find_in_page::FindTabHelper::FromWebContents(contents);
  if (find && [action isEqualToString:@"find-row"]) {
    find->StartFinding(u"Row", true, false, true);
    return @1;
  }
  if (find && [action isEqualToString:@"find-count"]) {
    return @(find->find_result().final_update() &&
                     find->find_result().request_id() == find->current_find_request_id()
                 ? find->find_result().number_of_matches() : -1);
  }
  return @(-1);
}

@end
