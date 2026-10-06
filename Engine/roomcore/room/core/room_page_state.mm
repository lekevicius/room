// Copyright 2026 Jonas Lekevicius. All rights reserved.

// What Chrome would show around a Room page that is not a dialog (Phase
// 3.4b): infobars and the translate offer as host notices, the page's
// capture state, its media session. No patch:
// - infobars: an infobars::InfoBarManager::Observer on the page's
//   ContentInfoBarManager (Chrome's container is a Views view of BrowserView,
//   so on a Room page infobars are added and never drawn);
// - the translate offer: a TranslateBubbleFactory (the desktop offer is a
//   bubble, BrowserWindow::ShowTranslateBubble, never an infobar);
// - capture: a MediaStreamCaptureIndicator::Observer;
// - the media session: a media_session::mojom::MediaSessionObserver on
//   content::MediaSession.

#import "room/core/room_page_ui_internal.h"
#import "room/core/room_web_contents_internal.h"

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/at_exit.h"
#include "base/containers/flat_map.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/translate/chrome_translate_client.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/translate/translate_bubble_factory.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_delegate.h"
#include "components/infobars/core/infobar_manager.h"
#include "components/translate/core/browser/translate_manager.h"
#include "components/translate/core/browser/translate_metrics_logger.h"
#include "components/translate/core/browser/translate_step.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "net/base/apple/url_conversions.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "services/media_session/public/cpp/media_image.h"
#include "services/media_session/public/cpp/media_metadata.h"
#include "services/media_session/public/cpp/media_position.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "ui/base/l10n/l10n_util.h"

// MARK: - Value objects

@interface RoomInfoBar ()
- (instancetype)initWithKind:(RoomInfoBarKind)kind
                  identifier:(NSInteger)identifier
                     message:(NSString*)message
                     buttons:(NSArray<NSString*>*)buttons
              sourceLanguage:(NSString*)sourceLanguage
              targetLanguage:(NSString*)targetLanguage
                       press:(void (^)(NSInteger index))press
                     dismiss:(void (^)(void))dismiss;
// Gone from Chrome: answers are ignored from now on.
- (void)room_invalidate;
@end

@implementation RoomInfoBar {
  void (^_press)(NSInteger);
  void (^_dismiss)(void);
  BOOL _done;
}

@synthesize kind = _kind;
@synthesize identifier = _identifier;
@synthesize message = _message;
@synthesize buttons = _buttons;
@synthesize sourceLanguage = _sourceLanguage;
@synthesize targetLanguage = _targetLanguage;

- (instancetype)initWithKind:(RoomInfoBarKind)kind
                  identifier:(NSInteger)identifier
                     message:(NSString*)message
                     buttons:(NSArray<NSString*>*)buttons
              sourceLanguage:(NSString*)sourceLanguage
              targetLanguage:(NSString*)targetLanguage
                       press:(void (^)(NSInteger))press
                     dismiss:(void (^)(void))dismiss {
  if ((self = [super init])) {
    _kind = kind;
    _identifier = identifier;
    _message = [message copy];
    _buttons = [buttons copy];
    _sourceLanguage = [sourceLanguage copy];
    _targetLanguage = [targetLanguage copy];
    _press = [press copy];
    _dismiss = [dismiss copy];
  }
  return self;
}

- (void)room_invalidate {
  _done = YES;
  _press = nil;
  _dismiss = nil;
}

- (void)pressButtonAtIndex:(NSInteger)index {
  if (_done || index < 0 || index >= (NSInteger)_buttons.count) {
    return;
  }
  _done = YES;
  void (^press)(NSInteger) = _press;
  _press = nil;
  _dismiss = nil;
  press(index);
}

- (void)dismiss {
  if (_done) {
    return;
  }
  _done = YES;
  void (^dismiss)(void) = _dismiss;
  _press = nil;
  _dismiss = nil;
  dismiss();
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<RoomInfoBar kind=%ld id=%ld \"%@\" [%@]%@>",
                                    (long)_kind, (long)_identifier, _message,
                                    [_buttons componentsJoinedByString:@", "],
                                    _sourceLanguage
                                        ? [NSString stringWithFormat:@" %@→%@",
                                                                     _sourceLanguage,
                                                                     _targetLanguage]
                                        : @""];
}

@end

@interface RoomMediaSessionInfo ()
- (instancetype)initWithTitle:(NSString*)title
                       artist:(NSString*)artist
                        album:(NSString*)album
                   artworkURL:(NSURL*)artworkURL
                      artwork:(NSImage*)artwork
                playbackState:(RoomMediaPlaybackState)playbackState
                      actions:(RoomMediaSessionActions)actions
                  hasPosition:(BOOL)hasPosition
                     duration:(NSTimeInterval)duration
                     position:(NSTimeInterval)position
                 playbackRate:(double)playbackRate;
@end

@implementation RoomMediaSessionInfo

@synthesize title = _title;
@synthesize artist = _artist;
@synthesize album = _album;
@synthesize artworkURL = _artworkURL;
@synthesize artwork = _artwork;
@synthesize playbackState = _playbackState;
@synthesize actions = _actions;
@synthesize hasPosition = _hasPosition;
@synthesize duration = _duration;
@synthesize position = _position;
@synthesize playbackRate = _playbackRate;

- (instancetype)initWithTitle:(NSString*)title
                       artist:(NSString*)artist
                        album:(NSString*)album
                   artworkURL:(NSURL*)artworkURL
                      artwork:(NSImage*)artwork
                playbackState:(RoomMediaPlaybackState)playbackState
                      actions:(RoomMediaSessionActions)actions
                  hasPosition:(BOOL)hasPosition
                     duration:(NSTimeInterval)duration
                     position:(NSTimeInterval)position
                 playbackRate:(double)playbackRate {
  if ((self = [super init])) {
    _title = [title copy];
    _artist = [artist copy];
    _album = [album copy];
    _artworkURL = [artworkURL copy];
    _artwork = artwork;
    _playbackState = playbackState;
    _actions = actions;
    _hasPosition = hasPosition;
    _duration = duration;
    _position = position;
    _playbackRate = playbackRate;
  }
  return self;
}

- (BOOL)isEqual:(id)object {
  if (![object isKindOfClass:RoomMediaSessionInfo.class]) {
    return NO;
  }
  RoomMediaSessionInfo* other = object;
  return [_title isEqualToString:other.title] &&
         [_artist isEqualToString:other.artist] &&
         [_album isEqualToString:other.album] &&
         (_artworkURL == other.artworkURL ||
          [_artworkURL isEqual:other.artworkURL]) &&
         _artwork == other.artwork && _playbackState == other.playbackState &&
         _actions == other.actions && _hasPosition == other.hasPosition &&
         _duration == other.duration && _position == other.position &&
         _playbackRate == other.playbackRate;
}

- (NSUInteger)hash {
  return _title.hash ^ _artist.hash ^ (NSUInteger)_playbackState;
}

- (NSString*)description {
  return [NSString
      stringWithFormat:@"<RoomMediaSessionInfo \"%@\" by \"%@\" on \"%@\" "
                       @"art=%@%@ state=%ld actions=0x%lx position=%@>",
                       _title, _artist, _album,
                       // B-90: a data: URL as its scheme and length, not kilobytes per line.
                       [_artworkURL.scheme isEqualToString:@"data"]
                           ? [NSString stringWithFormat:@"data:(%lu chars)",
                                                        (unsigned long)_artworkURL.absoluteString.length]
                           : _artworkURL.absoluteString,
                       _artwork ? @" (image)" : @"", (long)_playbackState,
                       (unsigned long)_actions,
                       _hasPosition
                           ? [NSString stringWithFormat:@"%.1f/%.1f@%.1f",
                                                        _position, _duration,
                                                        _playbackRate]
                           : @"none"];
}

@end

namespace {

NSString* LanguageName(const std::string& code) {
  const std::u16string name = l10n_util::GetDisplayNameForLocale(
      code, g_browser_process->GetApplicationLocale(), /*is_for_ui=*/true);
  return name.empty() ? base::SysUTF8ToNSString(code)
                      : base::SysUTF16ToNSString(name);
}

// MARK: - Per page: infobars, the translate offer, the media session

class PageServices : public content::WebContentsUserData<PageServices>,
                     public content::WebContentsObserver,
                     public infobars::InfoBarManager::Observer,
                     public media_session::mojom::MediaSessionObserver {
 public:
  ~PageServices() override { [translate_offer_ room_invalidate]; }

  // Room pages whose delegate shows notices get them; the others keep
  // Chrome's behaviour (infobars kept undrawn, the bubble refused).
  RoomWebContents* NoticeTarget() {
    return room::WrapperAnswering(web_contents(),
                                  @selector(webContents:didAddInfoBar:));
  }

  ShowTranslateBubbleResult OnTranslateStep(BrowserWindow* window,
                                            translate::TranslateStep step,
                                            const std::string& source,
                                            const std::string& target,
                                            translate::TranslateErrors error) {
    LOG(INFO) << "RoomCore: translate step " << static_cast<int>(step) << " "
              << source << " -> " << target << " error "
              << static_cast<int>(error);
    if (step != translate::TRANSLATE_STEP_BEFORE_TRANSLATE) {
      // Translating, translated, an error: the offer is answered; Chrome's
      // bubble (Views, on the host's site button: RoomBrowserWindow) takes
      // the later steps, as after its own offer. The host's Translate is the
      // user's gesture that opens it; Chrome's automatic steps only update it.
      WithdrawTranslateOffer();
      const bool gesture = host_requested_translation_;
      host_requested_translation_ = false;
      if (!window) {
        return ShowTranslateBubbleResult::kBrowserWindowNotValid;
      }
      return window->ShowTranslateBubble(web_contents(), step, source, target,
                                         error, gesture);
    }
    RoomWebContents* wrapper = NoticeTarget();
    if (!wrapper) {
      return ShowTranslateBubbleResult::kBrowserWindowNotValid;
    }
    WithdrawTranslateOffer();
    base::WeakPtr<content::WebContents> weak = web_contents()->GetWeakPtr();
    NSString* message = [NSString
        stringWithFormat:@"Translate this page from %@ to %@?",
                         LanguageName(source), LanguageName(target)];
    const std::string from = source, to = target;
    RoomInfoBar* offer = [[RoomInfoBar alloc]
          initWithKind:RoomInfoBarKindTranslateOffer
            identifier:infobars::InfoBarDelegate::
                           TRANSLATE_INFOBAR_DELEGATE_NON_AURA
               message:message
               buttons:@[ @"Translate" ]
        sourceLanguage:base::SysUTF8ToNSString(source)
        targetLanguage:base::SysUTF8ToNSString(target)
                 press:^(NSInteger) {
                   if (!weak) {
                     return;
                   }
                   ChromeTranslateClient* client =
                       ChromeTranslateClient::FromWebContents(weak.get());
                   translate::TranslateManager* manager =
                       client ? client->GetTranslateManager() : nullptr;
                   LOG(INFO) << "RoomCore: translate " << from << " -> " << to
                             << (manager ? "" : " (no manager)");
                   if (auto* services = PageServices::FromWebContents(weak.get())) {
                     services->host_requested_translation_ = true;
                   }
                   if (manager) {
                     manager->TranslatePage(
                         from, to, /*triggered_from_menu=*/false,
                         translate::TranslationType::kManualUiInitialTranslation);
                   }
                   if (auto* services = PageServices::FromWebContents(weak.get())) {
                     services->WithdrawTranslateOffer();
                   }
                 }
               dismiss:^{
                 if (!weak) {
                   return;
                 }
                 LOG(INFO) << "RoomCore: translate offer dismissed";
                 if (auto* services = PageServices::FromWebContents(weak.get())) {
                   services->WithdrawTranslateOffer();
                 }
               }];
    translate_offer_ = offer;
    LOG(INFO) << "RoomCore: notice to the host "
              << base::SysNSStringToUTF8(offer.description);
    [wrapper.delegate webContents:wrapper didAddInfoBar:offer];
    return ShowTranslateBubbleResult::kSuccess;
  }

  void WithdrawTranslateOffer() {
    RoomInfoBar* offer = translate_offer_;
    if (!offer) {
      return;
    }
    translate_offer_ = nil;
    [offer room_invalidate];
    Removed(offer);
  }

 private:
  friend class content::WebContentsUserData<PageServices>;

  explicit PageServices(content::WebContents* contents)
      : content::WebContentsUserData<PageServices>(*contents),
        content::WebContentsObserver(contents) {
    if (auto* manager =
            infobars::ContentInfoBarManager::FromWebContents(contents)) {
      infobar_observation_.Observe(manager);
    }
    if (content::MediaSession* session = content::MediaSession::Get(contents)) {
      session->AddObserver(media_receiver_.BindNewPipeAndPassRemote());
    }
  }

  void Removed(RoomInfoBar* infobar) {
    RoomWebContents* wrapper =
        [RoomWebContents room_existingWrapperFor:web_contents()];
    id<RoomWebContentsDelegate> delegate = wrapper.delegate;
    LOG(INFO) << "RoomCore: notice removed "
              << base::SysNSStringToUTF8(infobar.description);
    if ([delegate respondsToSelector:@selector(webContents:didRemoveInfoBar:)]) {
      [delegate webContents:wrapper didRemoveInfoBar:infobar];
    }
  }

  // content::WebContentsObserver:
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) {
      WithdrawTranslateOffer();
    }
  }
  void WebContentsDestroyed() override {
    infobar_observation_.Reset();
    media_receiver_.reset();
  }

  // infobars::InfoBarManager::Observer:
  void OnInfoBarAdded(infobars::InfoBar* infobar) override {
    RoomWebContents* wrapper = NoticeTarget();
    infobars::InfoBarDelegate* delegate = infobar->delegate();
    LOG(INFO) << "RoomCore: infobar added, identifier "
              << static_cast<int>(delegate->GetIdentifier())
              << (wrapper ? " (to the host)" : " (not drawn)");
    if (!wrapper) {
      return;
    }
    ConfirmInfoBarDelegate* confirm = delegate->AsConfirmInfoBarDelegate();
    NSMutableArray<NSString*>* buttons = [NSMutableArray array];
    bool has_ok = false;
    if (confirm) {
      const int mask = confirm->GetButtons();
      if (mask & ConfirmInfoBarDelegate::BUTTON_OK) {
        has_ok = true;
        [buttons addObject:base::SysUTF16ToNSString(confirm->GetButtonLabel(
                               ConfirmInfoBarDelegate::BUTTON_OK))];
      }
      if (mask & ConfirmInfoBarDelegate::BUTTON_CANCEL) {
        [buttons addObject:base::SysUTF16ToNSString(confirm->GetButtonLabel(
                               ConfirmInfoBarDelegate::BUTTON_CANCEL))];
      }
    }
    base::WeakPtr<infobars::InfoBar> weak = infobar->AsWeakPtr();
    RoomInfoBar* notice = [[RoomInfoBar alloc]
          initWithKind:RoomInfoBarKindChrome
            identifier:delegate->GetIdentifier()
               message:confirm ? base::SysUTF16ToNSString(confirm->GetMessageText())
                               : @""
               buttons:buttons
        sourceLanguage:nil
        targetLanguage:nil
                 press:^(NSInteger index) {
                   if (!weak) {
                     return;
                   }
                   ConfirmInfoBarDelegate* c =
                       weak->delegate()->AsConfirmInfoBarDelegate();
                   if (!c) {
                     return;
                   }
                   const bool remove =
                       (index == 0 && has_ok) ? c->Accept() : c->Cancel();
                   if (remove && weak) {
                     weak->RemoveSelf();
                   }
                 }
               dismiss:^{
                 if (!weak) {
                   return;
                 }
                 weak->delegate()->InfoBarDismissed();
                 if (weak) {
                   weak->RemoveSelf();
                 }
               }];
    infobars_[infobar] = notice;
    [wrapper.delegate webContents:wrapper didAddInfoBar:notice];
  }
  void OnInfoBarRemoved(infobars::InfoBar* infobar, bool) override {
    auto it = infobars_.find(infobar);
    if (it == infobars_.end()) {
      return;
    }
    RoomInfoBar* notice = it->second;
    infobars_.erase(it);
    [notice room_invalidate];
    Removed(notice);
  }
  void OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                         infobars::InfoBar* new_infobar) override {
    OnInfoBarRemoved(old_infobar, false);
    OnInfoBarAdded(new_infobar);
  }
  void OnManagerWillBeDestroyed(infobars::InfoBarManager*) override {
    infobar_observation_.Reset();
  }

  // media_session::mojom::MediaSessionObserver:
  void MediaSessionInfoChanged(
      media_session::mojom::MediaSessionInfoPtr info) override {
    playback_ = !info ? RoomMediaPlaybackStateNone
                : info->playback_state ==
                        media_session::mojom::MediaPlaybackState::kPlaying
                    ? RoomMediaPlaybackStatePlaying
                    : RoomMediaPlaybackStatePaused;
    active_ = info && info->state !=
                          media_session::mojom::MediaSessionInfo::SessionState::kInactive;
    Publish();
  }
  void MediaSessionMetadataChanged(
      const std::optional<media_session::MediaMetadata>& metadata) override {
    metadata_ = metadata;
    Publish();
  }
  void MediaSessionActionsChanged(
      const std::vector<media_session::mojom::MediaSessionAction>& actions)
      override {
    using Action = media_session::mojom::MediaSessionAction;
    RoomMediaSessionActions mask = 0;
    for (Action action : actions) {
      switch (action) {
        case Action::kPlay: mask |= RoomMediaSessionActionPlay; break;
        case Action::kPause: mask |= RoomMediaSessionActionPause; break;
        case Action::kPreviousTrack:
          mask |= RoomMediaSessionActionPreviousTrack;
          break;
        case Action::kNextTrack: mask |= RoomMediaSessionActionNextTrack; break;
        case Action::kSeekBackward:
          mask |= RoomMediaSessionActionSeekBackward;
          break;
        case Action::kSeekForward:
          mask |= RoomMediaSessionActionSeekForward;
          break;
        case Action::kSeekTo: mask |= RoomMediaSessionActionSeekTo; break;
        case Action::kStop: mask |= RoomMediaSessionActionStop; break;
        case Action::kSkipAd: mask |= RoomMediaSessionActionSkipAd; break;
        default: break;
      }
    }
    actions_ = mask;
    Publish();
  }
  void MediaSessionImagesChanged(
      const base::flat_map<media_session::mojom::MediaSessionImageType,
                           std::vector<media_session::MediaImage>>& images)
      override {
    std::optional<media_session::MediaImage> first;
    auto it = images.find(media_session::mojom::MediaSessionImageType::kArtwork);
    if (it != images.end() && !it->second.empty()) {
      first = it->second.front();
    }
    const GURL src = first ? first->src : GURL();
    if (src != artwork_) {
      artwork_ = src;
      artwork_image_ = nil;
      // Chrome's own controls fetch the bitmap the same way: in the page's
      // network context, decoded off the page.
      if (first) {
        content::MediaSession::Get(web_contents())
            ->GetMediaImageBitmap(*first, /*minimum_size_px=*/0,
                                  /*desired_size_px=*/96,
                                  base::BindOnce(&PageServices::ArtworkArrived,
                                                 weak_factory_.GetWeakPtr(),
                                                 src));
      }
    }
    Publish();
  }
  void MediaSessionPositionChanged(
      const std::optional<media_session::MediaPosition>& position) override {
    position_ = position;
    Publish();
  }

  void ArtworkArrived(const GURL& src, const SkBitmap& bitmap) {
    if (src != artwork_ || bitmap.drawsNothing()) {
      return;
    }
    artwork_image_ = skia::SkBitmapToNSImage(bitmap);
    Publish();
  }

  void Publish() {
    RoomWebContents* wrapper =
        [RoomWebContents room_existingWrapperFor:web_contents()];
    if (!wrapper) {
      return;
    }
    RoomMediaSessionInfo* info = nil;
    // Chrome gives every page default metadata (its title and host); a
    // session is the page's only while it has media (not inactive).
    if (metadata_ && active_) {
      info = [[RoomMediaSessionInfo alloc]
          initWithTitle:base::SysUTF16ToNSString(metadata_->title)
                 artist:base::SysUTF16ToNSString(metadata_->artist)
                  album:base::SysUTF16ToNSString(metadata_->album)
             artworkURL:artwork_.is_valid() ? net::NSURLWithGURL(artwork_) : nil
                artwork:artwork_image_
          playbackState:active_ ? playback_ : RoomMediaPlaybackStateNone
                actions:actions_
            hasPosition:position_.has_value()
               duration:position_ ? position_->duration().InSecondsF() : 0
               position:position_ ? position_->GetPosition().InSecondsF() : 0
           playbackRate:position_ ? position_->playback_rate() : 0];
    }
    [wrapper room_setMediaSession:info];
  }

  std::map<infobars::InfoBar*, RoomInfoBar*> infobars_;
  RoomInfoBar* translate_offer_ = nil;
  // The host's Translate started the translation now being reported.
  bool host_requested_translation_ = false;
  base::ScopedObservation<infobars::InfoBarManager,
                          infobars::InfoBarManager::Observer>
      infobar_observation_{this};
  mojo::Receiver<media_session::mojom::MediaSessionObserver> media_receiver_{
      this};
  std::optional<media_session::MediaMetadata> metadata_;
  GURL artwork_;
  NSImage* artwork_image_ = nil;
  RoomMediaPlaybackState playback_ = RoomMediaPlaybackStateNone;
  RoomMediaSessionActions actions_ = 0;
  std::optional<media_session::MediaPosition> position_;
  bool active_ = false;
  base::WeakPtrFactory<PageServices> weak_factory_{this};

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(PageServices);

// The desktop translate offer for Room pages (Chrome's ShowBubble decided to
// offer: the page's language differs, the page is the active tab of the
// last active Browser).
class RoomTranslateBubbleFactory : public TranslateBubbleFactory {
 protected:
  ShowTranslateBubbleResult ShowImplementation(
      BrowserWindow* window,
      content::WebContents* contents,
      translate::TranslateStep step,
      const std::string& source_language,
      const std::string& target_language,
      translate::TranslateErrors error_type) override {
    PageServices* services =
        contents ? PageServices::FromWebContents(contents) : nullptr;
    if (services && services->NoticeTarget()) {
      return services->OnTranslateStep(window, step, source_language,
                                       target_language, error_type);
    }
    // What TranslateBubbleFactory's default does.
    if (!window) {
      return ShowTranslateBubbleResult::kBrowserWindowNotValid;
    }
    return window->ShowTranslateBubble(contents, step, source_language,
                                       target_language, error_type,
                                       /*is_user_gesture=*/false);
  }
};

// MARK: - Capture state, for every page

RoomCaptureState CaptureStateOf(content::WebContents* contents) {
  scoped_refptr<MediaStreamCaptureIndicator> indicator =
      MediaCaptureDevicesDispatcher::GetInstance()
          ->GetMediaStreamCaptureIndicator();
  RoomCaptureState state = 0;
  if (indicator->IsCapturingVideo(contents)) {
    state |= RoomCaptureStateCamera;
  }
  if (indicator->IsCapturingAudio(contents)) {
    state |= RoomCaptureStateMicrophone;
  }
  if (indicator->IsCapturingDisplay(contents)) {
    state |= RoomCaptureStateDisplay;
  }
  if (indicator->IsCapturingTab(contents)) {
    state |= RoomCaptureStateTab;
  }
  if (indicator->IsCapturingWindow(contents)) {
    state |= RoomCaptureStateWindow;
  }
  if (indicator->IsBeingMirrored(contents)) {
    state |= RoomCaptureStateMirrored;
  }
  return state;
}

void PublishCaptureState(content::WebContents* contents) {
  RoomWebContents* wrapper =
      contents ? [RoomWebContents room_existingWrapperFor:contents] : nil;
  if (!wrapper) {
    return;
  }
  const RoomCaptureState state = CaptureStateOf(contents);
  if (state != wrapper.captureState) {
    LOG(INFO) << "RoomCore: capture state " << wrapper.captureState << " -> "
              << state;
  }
  [wrapper room_setCaptureState:state];
}

class CaptureObserver : public MediaStreamCaptureIndicator::Observer {
 public:
  void OnIsCapturingVideoChanged(content::WebContents* contents, bool) override {
    PublishCaptureState(contents);
  }
  void OnIsCapturingAudioChanged(content::WebContents* contents, bool) override {
    PublishCaptureState(contents);
  }
  void OnIsBeingMirroredChanged(content::WebContents* contents, bool) override {
    PublishCaptureState(contents);
  }
  void OnIsCapturingTabChanged(content::WebContents* contents, bool) override {
    PublishCaptureState(contents);
  }
  void OnIsCapturingWindowChanged(content::WebContents* contents,
                                  bool) override {
    PublishCaptureState(contents);
  }
  void OnIsCapturingDisplayChanged(content::WebContents* contents,
                                   bool) override {
    PublishCaptureState(contents);
  }
};

}  // namespace

namespace room {

namespace {
CaptureObserver* g_capture_observer = nullptr;
RoomTranslateBubbleFactory* g_translate_factory = nullptr;
bool g_detached = false;
}  // namespace

void AttachPageServices(content::WebContents* contents) {
  if (!contents) {
    return;
  }
  if (!g_capture_observer && !g_detached) {
    g_capture_observer = new CaptureObserver();
    MediaCaptureDevicesDispatcher::GetInstance()
        ->GetMediaStreamCaptureIndicator()
        ->AddObserver(g_capture_observer);
    g_translate_factory = new RoomTranslateBubbleFactory();
    TranslateBubbleFactory::SetFactory(g_translate_factory);
    // At-exit tasks run in reverse order: this one before the dispatcher
    // singleton (registered by its first GetInstance above) is destroyed.
    base::AtExitManager::RegisterTask(base::BindOnce(&DetachPageServiceObservers));
  }
  AdoptPageDialogs(contents);
  PageServices::CreateForWebContents(contents);
  PublishCaptureState(contents);
}

void DetachPageServiceObservers() {
  g_detached = true;
  // The capture indicator's observer list must be empty when the
  // dispatcher singleton goes at exit (its CHECK).
  if (g_capture_observer) {
    MediaCaptureDevicesDispatcher::GetInstance()
        ->GetMediaStreamCaptureIndicator()
        ->RemoveObserver(g_capture_observer);
    delete g_capture_observer;
    g_capture_observer = nullptr;
  }
  if (g_translate_factory) {
    TranslateBubbleFactory::SetFactory(nullptr);
    delete g_translate_factory;
    g_translate_factory = nullptr;
  }
}

void StopCapturing(content::WebContents* contents, RoomCaptureKinds kinds) {
  if (!contents) {
    return;
  }
  int media_type = 0;
  if (kinds & RoomCaptureKindsUserMedia) {
    media_type |= MediaStreamCaptureIndicator::kUserMedia;
  }
  if (kinds & RoomCaptureKindsDisplayMedia) {
    media_type |= MediaStreamCaptureIndicator::kDisplayMedia |
                  MediaStreamCaptureIndicator::kAllScreensMedia;
  }
  LOG(INFO) << "RoomCore: stop capturing " << media_type;
  MediaCaptureDevicesDispatcher::GetInstance()
      ->GetMediaStreamCaptureIndicator()
      ->StopMediaCapturing(contents, media_type);
}

}  // namespace room
