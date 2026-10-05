// Copyright 2026 Jonas Lekevicius. All rights reserved.

// HTTP auth (patch 0020), certificate errors (0021) and file choosers
// (0022) of Room pages: Chrome keeps the flow around each (LoginTabHelper
// and the password manager's auth observer; the navigation's SSL throttle
// and its HSTS verdict; the page's FileSelectListener), the host draws the
// sheet and answers.

#import "room/core/room_page_ui_internal.h"

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "base/files/file_enumerator.h"
#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/thread_pool.h"
#include "chrome/browser/ui/login/login_handler.h"
#include "components/security_interstitials/core/ssl_error_options_mask.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/file_select_listener.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/ssl_host_state_delegate.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "net/base/auth.h"
#include "net/base/net_errors.h"
#include "net/cert/x509_certificate.h"
#include "net/cert/x509_util.h"
#include "net/ssl/ssl_info.h"
#include "third_party/blink/public/mojom/choosers/file_chooser.mojom.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace room {
// Defined in chrome/browser/ui/views/login_handler_views.cc
// (patches/0020-login-handler-hook.patch).
extern std::unique_ptr<LoginHandler> (*g_create_login_handler_hook)(
    const net::AuthChallengeInfo&,
    content::WebContents*,
    content::LoginDelegate::LoginAuthRequiredCallback&);
// Defined in chrome/browser/chrome_content_browser_client_navigation_
// throttles.cc (patches/0021-ssl-error-hook.patch).
extern bool (*g_ssl_error_hook)(content::WebContents*,
                                net::Error,
                                const net::SSLInfo&,
                                const GURL&,
                                bool user_can_proceed);
// Defined in chrome/browser/ui/browser_web_contents_delegate/
// browser_web_contents_delegate.cc (patches/0022-file-chooser-hook.patch).
extern bool (*g_run_file_chooser_hook)(
    content::RenderFrameHost*,
    scoped_refptr<content::FileSelectListener>&,
    const blink::mojom::FileChooserParams&);
}  // namespace room

// MARK: - Value objects

@interface RoomAuthChallenge ()
- (instancetype)initWithInfo:(const net::AuthChallengeInfo&)info;
@end

@implementation RoomAuthChallenge

@synthesize origin = _origin;
@synthesize realm = _realm;
@synthesize scheme = _scheme;
@synthesize proxyChallenge = _proxyChallenge;

- (instancetype)initWithInfo:(const net::AuthChallengeInfo&)info {
  if ((self = [super init])) {
    const GURL url = info.challenger.GetURL();
    _origin = url.is_valid() ? net::NSURLWithGURL(url)
                             : [NSURL URLWithString:@"about:blank"];
    _realm = info.realm.empty() ? nil : base::SysUTF8ToNSString(info.realm);
    _scheme = base::SysUTF8ToNSString(info.scheme);
    _proxyChallenge = info.is_proxy;
  }
  return self;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomAuthChallenge %@ realm=%@ %@%@>",
                                    _origin, _realm, _scheme,
                                    _proxyChallenge ? @" proxy" : @""];
}

@end

@interface RoomCertificateError ()
- (instancetype)initWithURL:(NSURL*)URL
                  errorCode:(NSInteger)errorCode
                  errorName:(NSString*)errorName
           certificateChain:(NSArray<NSData*>*)chain
          strictEnforcement:(BOOL)strict
                overridable:(BOOL)overridable;
@end

@implementation RoomCertificateError

@synthesize URL = _URL;
@synthesize errorCode = _errorCode;
@synthesize errorName = _errorName;
@synthesize certificateChain = _certificateChain;
@synthesize strictEnforcement = _strictEnforcement;
@synthesize overridable = _overridable;

- (instancetype)initWithURL:(NSURL*)URL
                  errorCode:(NSInteger)errorCode
                  errorName:(NSString*)errorName
           certificateChain:(NSArray<NSData*>*)chain
          strictEnforcement:(BOOL)strict
                overridable:(BOOL)overridable {
  if ((self = [super init])) {
    _URL = [URL copy];
    _errorCode = errorCode;
    _errorName = [errorName copy];
    _certificateChain = [chain copy];
    _strictEnforcement = strict;
    _overridable = overridable;
  }
  return self;
}

- (NSString*)description {
  return [NSString
      stringWithFormat:@"<RoomCertificateError %@ %ld %@ chain=%lu strict=%d "
                       @"overridable=%d>",
                       _URL, (long)_errorCode, _errorName,
                       (unsigned long)_certificateChain.count,
                       _strictEnforcement, _overridable];
}

@end

@interface RoomFileChooserRequest ()
- (instancetype)initWithParams:(const blink::mojom::FileChooserParams&)params;
@end

@implementation RoomFileChooserRequest

@synthesize mode = _mode;
@synthesize title = _title;
@synthesize defaultPath = _defaultPath;
@synthesize acceptTypes = _acceptTypes;

- (instancetype)initWithParams:(const blink::mojom::FileChooserParams&)params {
  if ((self = [super init])) {
    using Mode = blink::mojom::FileChooserParams::Mode;
    switch (params.mode) {
      case Mode::kOpenMultiple:
        _mode = RoomFileChooserModeOpenMultiple;
        break;
      case Mode::kUploadFolder:
        _mode = RoomFileChooserModeUploadFolder;
        break;
      case Mode::kOpenDirectory:
        _mode = RoomFileChooserModeOpenDirectory;
        break;
      case Mode::kSave:
        _mode = RoomFileChooserModeSave;
        break;
      default:
        _mode = RoomFileChooserModeOpen;
        break;
    }
    _title = params.title.empty() ? nil : base::SysUTF16ToNSString(params.title);
    _defaultPath =
        params.default_file_name.empty()
            ? nil
            : [NSURL fileURLWithPath:base::SysUTF8ToNSString(
                                         params.default_file_name.value())];
    NSMutableArray<NSString*>* types = [NSMutableArray array];
    for (const std::u16string& type : params.accept_types) {
      [types addObject:base::SysUTF16ToNSString(type)];
    }
    _acceptTypes = [types copy];
  }
  return self;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomFileChooserRequest mode=%ld %@>",
                                    (long)_mode,
                                    [_acceptTypes componentsJoinedByString:@","]];
}

@end

// MARK: - HTTP auth

namespace {

// Chrome's LoginHandler with the host's sheet for a view: Chrome keeps the
// handler's lifetime (LoginTabHelper, HttpAuthCoordinator) and its
// bookkeeping (the password manager's HTTP auth observer, other handlers
// waiting for the same credentials).
class RoomLoginHandler : public LoginHandler {
 public:
  RoomLoginHandler(const net::AuthChallengeInfo& auth_info,
                   content::WebContents* web_contents,
                   content::LoginDelegate::LoginAuthRequiredCallback callback)
      : LoginHandler(auth_info, web_contents, std::move(callback)) {}

  ~RoomLoginHandler() override = default;

 protected:
  bool BuildViewImpl(const std::u16string& authority,
                     const std::u16string& explanation,
                     LoginModelData* login_model_data) override {
    RoomWebContents* wrapper = room::WrapperAnswering(
        web_contents(),
        @selector(webContents:didReceiveAuthChallenge:completion:));
    if (!wrapper) {
      return false;
    }
    RoomAuthChallenge* challenge =
        [[RoomAuthChallenge alloc] initWithInfo:auth_info()];
    LOG(INFO) << "RoomCore: auth challenge "
              << base::SysNSStringToUTF8(challenge.description);
    base::WeakPtr<RoomLoginHandler> weak = weak_factory_.GetWeakPtr();
    [wrapper.delegate webContents:wrapper
          didReceiveAuthChallenge:challenge
                       completion:^(NSString* user, NSString* password) {
                         if (!weak || weak->answered_) {
                           return;
                         }
                         weak->answered_ = true;
                         // Either call can destroy the handler.
                         if (user) {
                           weak->SetAuth(base::SysNSStringToUTF16(user),
                                         base::SysNSStringToUTF16(password ?: @""));
                         } else {
                           weak->CancelAuth(/*notify_others=*/true);
                         }
                       }];
    return true;
  }

  void CloseDialog() override {
    // Another handler supplied the credentials, or the request went away;
    // the host's answer is ignored from now on (the protocol has no member
    // to withdraw the sheet: it stays until the host answers).
    answered_ = true;
  }

 private:
  bool answered_ = false;
  base::WeakPtrFactory<RoomLoginHandler> weak_factory_{this};
};

// MARK: - Certificate errors

NSArray<NSData*>* ChainOf(const net::SSLInfo& ssl_info) {
  NSMutableArray<NSData*>* chain = [NSMutableArray array];
  const net::X509Certificate* cert = ssl_info.cert.get();
  if (!cert) {
    return chain;
  }
  base::span<const uint8_t> leaf = cert->cert_span();
  [chain addObject:[NSData dataWithBytes:leaf.data() length:leaf.size()]];
  for (const auto& buffer : cert->intermediate_buffers()) {
    base::span<const uint8_t> bytes =
        net::x509_util::CryptoBufferAsSpan(buffer.get());
    [chain addObject:[NSData dataWithBytes:bytes.data() length:bytes.size()]];
  }
  return chain;
}

bool HandleCertificateError(content::WebContents* contents,
                            net::Error cert_error,
                            const net::SSLInfo& ssl_info,
                            const GURL& request_url,
                            bool user_can_proceed) {
  RoomWebContents* wrapper = room::WrapperAnswering(
      contents, @selector(webContents:didFailCertificateCheck:completion:));
  if (!wrapper || !ssl_info.cert) {
    return false;
  }
  // Chrome's own verdict (what SSLErrorHandler gives SSLBlockingPage): no
  // bypass for an HSTS or pinned host, for a fatal error, or where policy
  // forbids it.
  const int options = security_interstitials::CalculateSSLErrorOptionsMask(
      cert_error, /*hard_override_disabled=*/!user_can_proceed,
      ssl_info.is_fatal_cert_error);
  const bool overridable =
      options & security_interstitials::SSLErrorOptionsMask::SOFT_OVERRIDE_ENABLED;
  RoomCertificateError* error = [[RoomCertificateError alloc]
             initWithURL:net::NSURLWithGURL(request_url)
               errorCode:cert_error
               errorName:base::SysUTF8ToNSString(
                             net::ErrorToShortString(cert_error))
        certificateChain:ChainOf(ssl_info)
       strictEnforcement:ssl_info.is_fatal_cert_error
             overridable:overridable];
  LOG(INFO) << "RoomCore: certificate error "
            << base::SysNSStringToUTF8(error.description);
  base::WeakPtr<content::WebContents> weak = contents->GetWeakPtr();
  scoped_refptr<net::X509Certificate> cert = ssl_info.cert;
  // A copy for the block (it would capture the reference parameter).
  const GURL url = request_url;
  auto answered = std::make_shared<bool>(false);
  [wrapper.delegate
              webContents:wrapper
      didFailCertificateCheck:error
                   completion:^(BOOL proceed) {
                     if (*answered || !weak) {
                       return;
                     }
                     *answered = true;
                     if (!proceed || !overridable) {
                       // The deferred navigation goes; the page keeps what it
                       // showed.
                       weak->Stop();
                       return;
                     }
                     // What SSLBlockingPage's Proceed does: remember the
                     // decision for the host, then load the URL again.
                     if (content::SSLHostStateDelegate* state =
                             weak->GetBrowserContext()->GetSSLHostStateDelegate()) {
                       state->AllowCert(
                           std::string(url.host()), *cert, cert_error,
                           weak->GetPrimaryMainFrame()->GetStoragePartition());
                     }
                     content::NavigationController::LoadURLParams params(url);
                     content::NavigationEntry* pending =
                         weak->GetController().GetPendingEntry();
                     params.transition_type =
                         pending && pending->GetURL() == url
                             ? pending->GetTransitionType()
                             : ui::PAGE_TRANSITION_LINK;
                     weak->GetController().LoadURLWithParams(params);
                   }];
  return true;
}

// MARK: - File choosers

std::vector<blink::mojom::FileChooserFileInfoPtr> NativeFiles(
    const std::vector<base::FilePath>& paths) {
  std::vector<blink::mojom::FileChooserFileInfoPtr> files;
  for (const base::FilePath& path : paths) {
    files.push_back(blink::mojom::FileChooserFileInfo::NewNativeFile(
        blink::mojom::NativeFileInfo::New(path, std::u16string(),
                                          std::vector<std::u16string>())));
  }
  return files;
}

// Every file under `folder` (what <input webkitdirectory> uploads;
// FileSelectHelper enumerates the same way).
std::vector<base::FilePath> FilesUnder(const base::FilePath& folder) {
  std::vector<base::FilePath> paths;
  base::FileEnumerator enumerator(folder, /*recursive=*/true,
                                  base::FileEnumerator::FILES);
  for (base::FilePath path = enumerator.Next(); !path.empty();
       path = enumerator.Next()) {
    paths.push_back(path);
  }
  return paths;
}

bool RunFileChooser(content::RenderFrameHost* frame,
                    scoped_refptr<content::FileSelectListener>& listener,
                    const blink::mojom::FileChooserParams& params) {
  content::WebContents* contents =
      content::WebContents::FromRenderFrameHost(frame);
  RoomWebContents* wrapper = room::WrapperAnswering(
      contents, @selector(webContents:runFileChooser:completion:));
  if (!wrapper) {
    return false;
  }
  RoomFileChooserRequest* request =
      [[RoomFileChooserRequest alloc] initWithParams:params];
  LOG(INFO) << "RoomCore: file chooser "
            << base::SysNSStringToUTF8(request.description);
  scoped_refptr<content::FileSelectListener> page = listener;
  const blink::mojom::FileChooserParams::Mode mode = params.mode;
  auto answered = std::make_shared<bool>(false);
  [wrapper.delegate webContents:wrapper
                 runFileChooser:request
                     completion:^(NSArray<NSURL*>* chosen) {
                       if (*answered) {
                         return;
                       }
                       *answered = true;
                       std::vector<base::FilePath> paths;
                       for (NSURL* url in chosen) {
                         if (url.isFileURL) {
                           paths.emplace_back(
                               base::SysNSStringToUTF8(url.path));
                         }
                       }
                       if (!chosen || paths.empty()) {
                         page->FileSelectionCanceled();
                         return;
                       }
                       if (mode == blink::mojom::FileChooserParams::Mode::
                                       kUploadFolder) {
                         const base::FilePath folder = paths.front();
                         base::ThreadPool::PostTaskAndReplyWithResult(
                             FROM_HERE,
                             {base::MayBlock(),
                              base::TaskPriority::USER_BLOCKING},
                             base::BindOnce(&FilesUnder, folder),
                             base::BindOnce(
                                 [](scoped_refptr<content::FileSelectListener>
                                        page,
                                    base::FilePath folder,
                                    std::vector<base::FilePath> files) {
                                   page->FileSelected(
                                       NativeFiles(files), folder,
                                       blink::mojom::FileChooserParams::Mode::
                                           kUploadFolder);
                                 },
                                 page, folder));
                         return;
                       }
                       page->FileSelected(NativeFiles(paths), base::FilePath(),
                                          mode);
                     }];
  return true;
}

}  // namespace

namespace room {

void InstallPagePromptHooks() {
  g_create_login_handler_hook =
      +[](const net::AuthChallengeInfo& auth_info,
          content::WebContents* contents,
          content::LoginDelegate::LoginAuthRequiredCallback& callback)
      -> std::unique_ptr<LoginHandler> {
    if (!WrapperAnswering(
            contents,
            @selector(webContents:didReceiveAuthChallenge:completion:))) {
      return nullptr;
    }
    return std::make_unique<RoomLoginHandler>(auth_info, contents,
                                              std::move(callback));
  };
  g_ssl_error_hook = &HandleCertificateError;
  g_run_file_chooser_hook = &RunFileChooser;
}

}  // namespace room
