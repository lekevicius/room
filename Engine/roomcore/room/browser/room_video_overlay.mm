// The video picture-in-picture window's controls, drawn by Room. 5.12 (the
// user on build 26): Dia's look, the origin centred. 5.13 (the user: "native
// liquid glass controls"; then, of frosted shapes under Chrome's buttons,
// "NOTHING is correct here"): Chrome's controls, scrims and title are hidden
// and AppKit's own Liquid Glass controls sit over the video in the window's
// content view (AppKit views draw above the window's compositor layer, so the
// glass samples the video). They act through the window's controller as
// Chrome's buttons did and read the window's state on a short timer. The
// window itself gets rounded corners. Patch 0029 calls the hook once Chrome's
// views exist and after each of its layouts.

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_multi_source_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "chrome/browser/ui/views/overlay/hang_up_button.h"
#include "chrome/browser/ui/views/overlay/playback_image_button.h"
#include "chrome/browser/ui/views/overlay/simple_overlay_window_image_button.h"
#include "chrome/browser/ui/views/overlay/skip_ad_label_button.h"
#include "chrome/browser/ui/views/overlay/toggle_camera_button.h"
#include "chrome/browser/ui/views/overlay/toggle_microphone_button.h"
#include "chrome/browser/ui/views/overlay/video_overlay_window_views.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "room/browser/room_video_overlay.h"
#include "services/media_session/public/cpp/media_position.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/views/controls/label.h"
#include "ui/views/view.h"
#include "ui/views/view_observer.h"
#include "ui/views/view_tracker.h"
#include "ui/views/widget/widget.h"

namespace room {
extern void (*g_video_overlay_hook)(views::View* controls,
                                    views::View* title,
                                    views::Label* origin,
                                    views::View* favicon,
                                    views::Button* back_to_tab,
                                    views::Button* close,
                                    views::View* minimize,
                                    views::View* playback,
                                    bool layout);
}  // namespace room

namespace room {
namespace {

// The view id that marks a window already given Room's controls.
constexpr int kControlsAnchorId = 0x524f0003;
// How often the controls read the window's state (play/pause, position, the
// buttons Chrome would show).
constexpr base::TimeDelta kStateInterval = base::Milliseconds(250);

enum class Action {
  kClose,
  kBackToTab,
  kPlayPause,
  kReplay,
  kForward,
  kPreviousTrack,
  kNextTrack,
  kSkipAd,
  kToggleMute,
  kToggleMicrophone,
  kToggleCamera,
  kHangUp,
  kSeek,
};

// What the controls show, read from the window.
struct ControlsState {
  bool playing = false;
  bool playback = true;  // false: a call's controls instead
  bool live = false;
  bool muted = false;
  bool replay = false;
  bool forward = false;
  bool previous_track = false;
  bool next_track = false;
  bool skip_ad = false;
  bool microphone = false;
  bool microphone_muted = false;
  bool camera = false;
  bool camera_on = false;
  bool hang_up = false;
  double elapsed = 0;   // seconds
  double duration = 0;  // seconds; 0: no position
  std::u16string origin;
};

}  // namespace
}  // namespace room

using room::Action;
using room::ControlsState;

// Metrics (5.13, chosen to match the sidebar's glass: 32 pt circles, the
// window's 16 pt corner).
static const CGFloat kWindowCorner = 16;
static const CGFloat kInset = 10;
static const CGFloat kButton = 32;
static const CGFloat kPlayButton = 44;
static const CGFloat kTransportGap = 14;
static const CGFloat kBarHeight = 32;
static const NSTimeInterval kFade = 0.2;
static const NSTimeInterval kIdleHide = 2.5;
static const NSTimeInterval kExitHide = 0.25;

static NSImage* Symbol(NSString* name, CGFloat size, NSString* label) {
  NSImage* image = [NSImage imageWithSystemSymbolName:name
                             accessibilityDescription:label];
  return [image imageWithSymbolConfiguration:
                    [NSImageSymbolConfiguration
                        configurationWithPointSize:size
                                            weight:NSFontWeightSemibold]];
}

// The glass circle a control sits on (NSGlassEffectView keeps its content
// view in a container of its own, so not simply the superview).
API_AVAILABLE(macos(26.0))
static NSGlassEffectView* GlassOf(NSView* view) {
  for (NSView* up = view.superview; up; up = up.superview) {
    if ([up isKindOfClass:NSGlassEffectView.class]) {
      return static_cast<NSGlassEffectView*>(up);
    }
  }
  return nil;
}

static NSString* Time(double seconds) {
  const long total = std::max(0L, static_cast<long>(seconds));
  const long hours = total / 3600, minutes = total / 60 % 60, rest = total % 60;
  return hours > 0 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", hours,
                                                minutes, rest]
                   : [NSString stringWithFormat:@"%ld:%02ld", minutes, rest];
}

// Flipped, as the controls lay out from the top.
@interface RoomFlippedView : NSView
@end

@implementation RoomFlippedView
- (BOOL)isFlipped {
  return YES;
}
@end

// The controls over the video. Clicks off a control fall through to Chrome's
// views (the window drags from anywhere); the pointer over the window shows
// them, its leaving or a still pointer while playing hides them.
API_AVAILABLE(macos(26.0))
@interface RoomVideoControlsView : NSView
- (instancetype)initWithAction:
    (base::RepeatingCallback<void(Action, double)>)action;
- (void)updateState:(const ControlsState&)state;
- (void)showControls;
@end

@implementation RoomVideoControlsView {
  base::RepeatingCallback<void(Action, double)> _action;
  NSView* _group;  // everything that fades
  NSButton* _close;
  NSButton* _back;
  NSGlassEffectView* _originGlass;
  NSTextField* _origin;
  NSButton* _replay;
  NSButton* _play;
  NSButton* _forward;
  NSButton* _previousTrack;
  NSButton* _nextTrack;
  NSButton* _microphone;
  NSButton* _camera;
  NSButton* _hangUp;
  NSButton* _skipAd;
  NSGlassEffectView* _bar;
  NSButton* _mute;
  NSTextField* _elapsed;
  NSTextField* _remaining;
  NSSlider* _slider;
  ControlsState _state;
  BOOL _shown;
  BOOL _inside;
  NSTimer* _hideTimer;
}

- (NSButton*)glassButton:(NSString*)symbol
                   label:(NSString*)label
                    side:(CGFloat)side
                    size:(CGFloat)size
                  action:(SEL)selector {
  // A borderless button on its own glass circle: a glass-bezel button greys
  // its glyph in a window that is never key, which this one never is.
  NSButton* button = [NSButton buttonWithImage:Symbol(symbol, size, label)
                                        target:self
                                        action:selector];
  button.bordered = NO;
  button.imagePosition = NSImageOnly;
  button.toolTip = label;
  button.contentTintColor = NSColor.whiteColor;
  button.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  NSGlassEffectView* glass = [[NSGlassEffectView alloc]
      initWithFrame:NSMakeRect(0, 0, side, side)];
  glass.cornerRadius = side / 2;
  button.frame = glass.bounds;
  glass.contentView = button;
  [_group addSubview:glass];
  return button;
}

- (NSTextField*)timeLabel {
  NSTextField* label = [NSTextField labelWithString:@""];
  label.font = [NSFont monospacedDigitSystemFontOfSize:11
                                                weight:NSFontWeightMedium];
  label.textColor = [NSColor colorWithWhite:1 alpha:0.85];
  [_bar addSubview:label];
  return label;
}

- (instancetype)initWithAction:
    (base::RepeatingCallback<void(Action, double)>)action {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _action = std::move(action);
    self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.wantsLayer = YES;
    _group = [[RoomFlippedView alloc] initWithFrame:NSZeroRect];
    _group.wantsLayer = YES;
    _group.alphaValue = 0;
    [self addSubview:_group];

    _close = [self glassButton:@"xmark" label:@"Close" side:kButton size:13
                        action:@selector(closeClicked:)];
    _back = [self glassButton:@"pip.exit" label:@"Back to Tab" side:kButton
                         size:13 action:@selector(backClicked:)];
    _originGlass = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
    _originGlass.cornerRadius = kButton / 2;
    _origin = [NSTextField labelWithString:@""];
    _origin.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _origin.textColor = NSColor.whiteColor;
    _origin.alignment = NSTextAlignmentCenter;
    _origin.lineBreakMode = NSLineBreakByTruncatingHead;
    [_originGlass addSubview:_origin];
    [_group addSubview:_originGlass];

    _replay = [self glassButton:@"gobackward.10" label:@"Back 10 Seconds"
                           side:kButton size:14 action:@selector(replayClicked:)];
    _previousTrack = [self glassButton:@"backward.end.fill" label:@"Previous Track"
                                  side:kButton size:13
                                action:@selector(previousClicked:)];
    _play = [self glassButton:@"pause.fill" label:@"Pause" side:kPlayButton
                         size:20 action:@selector(playClicked:)];
    _nextTrack = [self glassButton:@"forward.end.fill" label:@"Next Track"
                              side:kButton size:13 action:@selector(nextClicked:)];
    _forward = [self glassButton:@"goforward.10" label:@"Forward 10 Seconds"
                            side:kButton size:14 action:@selector(forwardClicked:)];
    _microphone = [self glassButton:@"mic.fill" label:@"Mute Microphone"
                               side:kButton size:14
                             action:@selector(microphoneClicked:)];
    _camera = [self glassButton:@"video.fill" label:@"Turn Off Camera"
                           side:kButton size:14 action:@selector(cameraClicked:)];
    _hangUp = [self glassButton:@"phone.down.fill" label:@"Hang Up"
                           side:kButton size:14 action:@selector(hangUpClicked:)];
    GlassOf(_hangUp).tintColor =
        NSColor.systemRedColor;

    _skipAd = [NSButton buttonWithTitle:@"Skip Ad"
                                 target:self
                                 action:@selector(skipAdClicked:)];
    _skipAd.bezelStyle = NSBezelStyleGlass;
    _skipAd.borderShape = NSControlBorderShapeCapsule;
    _skipAd.controlSize = NSControlSizeLarge;
    [_group addSubview:_skipAd];

    _bar = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
    _bar.cornerRadius = kBarHeight / 2;
    [_group addSubview:_bar];
    _mute = [NSButton buttonWithImage:Symbol(@"speaker.wave.2.fill", 12, @"Mute")
                               target:self
                               action:@selector(muteClicked:)];
    _mute.bordered = NO;
    _mute.imagePosition = NSImageOnly;
    _mute.contentTintColor = NSColor.whiteColor;
    _mute.toolTip = @"Mute";
    [_bar addSubview:_mute];
    _elapsed = [self timeLabel];
    _remaining = [self timeLabel];
    _remaining.alignment = NSTextAlignmentRight;
    _slider = [NSSlider sliderWithValue:0
                               minValue:0
                               maxValue:1
                                 target:self
                                 action:@selector(sliderMoved:)];
    _slider.controlSize = NSControlSizeSmall;
    _slider.continuous = YES;
    [_bar addSubview:_slider];
    [self updateState:ControlsState()];
  }
  return self;
}

- (BOOL)isFlipped {
  return YES;
}

// Only the controls take clicks, and only while shown.
- (NSView*)hitTest:(NSPoint)point {
  if (!_shown) {
    return nil;
  }
  NSView* hit = [super hitTest:point];
  return hit == self || hit == _group || hit == _bar || hit == _originGlass ||
                 hit == _origin
             ? nil
             : hit;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  for (NSTrackingArea* area in self.trackingAreas) {
    [self removeTrackingArea:area];
  }
  [self addTrackingArea:[[NSTrackingArea alloc]
                            initWithRect:NSZeroRect
                                 options:NSTrackingMouseEnteredAndExited |
                                         NSTrackingMouseMoved |
                                         NSTrackingActiveAlways |
                                         NSTrackingInVisibleRect
                                   owner:self
                                userInfo:nil]];
}

- (void)mouseEntered:(NSEvent*)event {
  _inside = YES;
  [self showControls];
}

- (void)mouseMoved:(NSEvent*)event {
  _inside = YES;
  [self showControls];
}

- (void)mouseExited:(NSEvent*)event {
  _inside = NO;
  [self scheduleHide:kExitHide];
}

- (void)showControls {
  [self setShown:YES];
  [self scheduleHide:kIdleHide];
}

- (void)scheduleHide:(NSTimeInterval)delay {
  [_hideTimer invalidate];
  __weak RoomVideoControlsView* weakSelf = self;
  _hideTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                               repeats:NO
                                                 block:^(NSTimer* timer) {
                                                   [weakSelf idleTimerFired];
                                                 }];
}

- (void)idleTimerFired {
  // Paused, the controls stay while the pointer is over the window; the
  // pointer on a control keeps them too.
  const NSPoint point = [self.superview convertPoint:self.window.mouseLocationOutsideOfEventStream
                                            fromView:nil];
  const BOOL overControl = _inside && [self hitTest:point] != nil;
  if (_inside && (!_state.playing || overControl || _slider.highlighted)) {
    [self scheduleHide:kIdleHide];
    return;
  }
  [self setShown:NO];
}

- (void)setShown:(BOOL)shown {
  if (_shown == shown) {
    return;
  }
  _shown = shown;
  [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
    context.duration = kFade;
    context.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    self->_group.animator.alphaValue = shown ? 1 : 0;
  }];
}

- (void)updateState:(const ControlsState&)state {
  const BOOL relayout =
      state.playback != _state.playback || state.live != _state.live ||
      state.replay != _state.replay || state.forward != _state.forward ||
      state.previous_track != _state.previous_track ||
      state.next_track != _state.next_track || state.skip_ad != _state.skip_ad ||
      state.microphone != _state.microphone || state.camera != _state.camera ||
      state.hang_up != _state.hang_up || state.origin != _state.origin ||
      (state.duration > 0) != (_state.duration > 0);
  _state = state;
  _play.image = Symbol(state.playing ? @"pause.fill" : @"play.fill", 20,
                       state.playing ? @"Pause" : @"Play");
  _play.toolTip = state.playing ? @"Pause" : @"Play";
  _mute.image = Symbol(state.muted ? @"speaker.slash.fill" : @"speaker.wave.2.fill",
                       12, state.muted ? @"Unmute" : @"Mute");
  _mute.toolTip = state.muted ? @"Unmute" : @"Mute";
  _microphone.image = Symbol(state.microphone_muted ? @"mic.slash.fill" : @"mic.fill", 14,
                             state.microphone_muted ? @"Unmute Microphone" : @"Mute Microphone");
  _camera.image = Symbol(state.camera_on ? @"video.fill" : @"video.slash.fill", 14,
                         state.camera_on ? @"Turn Off Camera" : @"Turn On Camera");
  _origin.stringValue = base::SysUTF16ToNSString(state.origin);
  // The position, unless the pointer drags the slider.
  if (!(NSEvent.pressedMouseButtons & 1) || !_slider.highlighted) {
    _slider.doubleValue = state.duration > 0 ? state.elapsed / state.duration : 0;
    _elapsed.stringValue = Time(state.elapsed);
    _remaining.stringValue = state.live ? @"Live" : Time(state.duration);
  }
  if (relayout) {
    self.needsLayout = YES;
  }
}

- (void)layout {
  [super layout];
  const NSRect bounds = self.bounds;
  _group.frame = bounds;
  const CGFloat width = NSWidth(bounds), height = NSHeight(bounds);
  // Top: Close, the origin on its own glass, Back to Tab.
  GlassOf(_close).frame = NSMakeRect(kInset, kInset, kButton, kButton);
  GlassOf(_back).frame = NSMakeRect(width - kInset - kButton, kInset, kButton, kButton);
  const CGFloat room = NSMinX(GlassOf(_back).frame) - NSMaxX(GlassOf(_close).frame) - 2 * 8;
  const CGFloat text = std::min<CGFloat>(ceil(_origin.fittingSize.width) + 24, room);
  _originGlass.hidden = _state.origin.empty() || room < 60;
  _originGlass.frame = NSMakeRect(round((width - text) / 2), kInset, std::max<CGFloat>(0, text), kButton);
  const CGFloat lineHeight = ceil(_origin.fittingSize.height);
  _origin.frame = NSMakeRect(12, round((kButton - lineHeight) / 2), std::max<CGFloat>(0, text - 24), lineHeight);

  // Centre: the playback buttons Chrome would show, or a call's.
  NSArray<NSButton*>* row;
  if (_state.playback) {
    NSMutableArray<NSButton*>* buttons = [NSMutableArray array];
    if (_state.previous_track) [buttons addObject:_previousTrack];
    if (_state.replay && !_state.live) [buttons addObject:_replay];
    [buttons addObject:_play];
    if (_state.forward && !_state.live) [buttons addObject:_forward];
    if (_state.next_track) [buttons addObject:_nextTrack];
    row = buttons;
  } else {
    NSMutableArray<NSButton*>* buttons = [NSMutableArray array];
    if (_state.microphone) [buttons addObject:_microphone];
    if (_state.camera) [buttons addObject:_camera];
    if (_state.hang_up) [buttons addObject:_hangUp];
    row = buttons;
  }
  for (NSButton* button in @[ _replay, _play, _forward, _previousTrack, _nextTrack, _microphone, _camera, _hangUp ]) {
    GlassOf(button).hidden = ![row containsObject:button];
  }
  CGFloat total = 0;
  for (NSButton* button in row) {
    total += (button == _play ? kPlayButton : kButton) + (total > 0 ? kTransportGap : 0);
  }
  CGFloat x = round((width - total) / 2);
  const CGFloat middle = round(height / 2);
  for (NSButton* button in row) {
    const CGFloat side = button == _play ? kPlayButton : kButton;
    GlassOf(button).frame = NSMakeRect(x, middle - side / 2, side, side);
    x += side + kTransportGap;
  }

  // Bottom: mute, the times around the slider (no position: mute alone).
  const BOOL position = _state.playback && _state.duration > 0;
  const CGFloat barWidth = position ? width - 2 * kInset : kBarHeight;
  _bar.hidden = !_state.playback;
  _bar.frame = NSMakeRect(kInset, height - kInset - kBarHeight, barWidth, kBarHeight);
  _mute.frame = NSMakeRect(4, 4, kBarHeight - 8, kBarHeight - 8);
  for (NSView* view in @[ _elapsed, _remaining, _slider ]) {
    view.hidden = !position;
  }
  const CGFloat timeWidth = ceil(std::max(_elapsed.fittingSize.width, [_remaining.stringValue sizeWithAttributes:@{NSFontAttributeName : _remaining.font}].width)) + 2;
  const CGFloat timeHeight = ceil(_elapsed.fittingSize.height);
  const CGFloat timeY = round((kBarHeight - timeHeight) / 2);
  _elapsed.frame = NSMakeRect(NSMaxX(_mute.frame) + 4, timeY, timeWidth, timeHeight);
  _remaining.frame = NSMakeRect(barWidth - 12 - timeWidth, timeY, timeWidth, timeHeight);
  const CGFloat sliderHeight = ceil(_slider.fittingSize.height);
  _slider.frame = NSMakeRect(NSMaxX(_elapsed.frame) + 8, round((kBarHeight - sliderHeight) / 2),
                             std::max<CGFloat>(0, NSMinX(_remaining.frame) - 8 - NSMaxX(_elapsed.frame) - 8), sliderHeight);

  // Skip Ad above the bar's trailing end.
  _skipAd.hidden = !_state.skip_ad;
  const NSSize skip = _skipAd.fittingSize;
  _skipAd.frame = NSMakeRect(width - kInset - skip.width, NSMinY(_bar.frame) - 8 - skip.height, skip.width, skip.height);
}

- (void)closeClicked:(id)sender {
  _action.Run(Action::kClose, 0);
}
- (void)backClicked:(id)sender {
  _action.Run(Action::kBackToTab, 0);
}
- (void)playClicked:(id)sender {
  _action.Run(Action::kPlayPause, 0);
}
- (void)replayClicked:(id)sender {
  _action.Run(Action::kReplay, 0);
}
- (void)forwardClicked:(id)sender {
  _action.Run(Action::kForward, 0);
}
- (void)previousClicked:(id)sender {
  _action.Run(Action::kPreviousTrack, 0);
}
- (void)nextClicked:(id)sender {
  _action.Run(Action::kNextTrack, 0);
}
- (void)skipAdClicked:(id)sender {
  _action.Run(Action::kSkipAd, 0);
}
- (void)muteClicked:(id)sender {
  _action.Run(Action::kToggleMute, 0);
}
- (void)microphoneClicked:(id)sender {
  _action.Run(Action::kToggleMicrophone, 0);
}
- (void)cameraClicked:(id)sender {
  _action.Run(Action::kToggleCamera, 0);
}
- (void)hangUpClicked:(id)sender {
  _action.Run(Action::kHangUp, 0);
}

// Dragging moves the times; letting go seeks.
- (void)sliderMoved:(NSSlider*)slider {
  const double elapsed = slider.doubleValue * _state.duration;
  _elapsed.stringValue = Time(elapsed);
  if (NSApp.currentEvent.type == NSEventTypeLeftMouseUp || !(NSEvent.pressedMouseButtons & 1)) {
    _action.Run(Action::kSeek, elapsed);
  }
  [self showControls];
}

@end

namespace room {
namespace {

// Lives in Chrome's (hidden) controls container for as long as the window's
// views do: owns Room's AppKit controls, reads the window's state for them and
// carries out their clicks.
class RoomControls : public views::View, public views::ViewObserver {
  METADATA_HEADER(RoomControls, views::View)

 public:
  explicit RoomControls(VideoOverlayWindowViews* window) : window_(window) {
    SetID(kControlsAnchorId);
    SetCanProcessEventsWithinSubtree(false);
  }

  ~RoomControls() override { [view_ removeFromSuperview]; }

  // Once the widget has its NSWindow: the controls over its content view, the
  // window rounded. The controls are the content view's sibling, not its
  // subview: Chrome's content view answers every hit test itself (the root
  // view, or nil for a drag), so a subview would never get a click.
  void Attach() {
    NSWindow* window = window_->GetNativeWindow().GetNativeNSWindow();
    NSView* content = window.contentView;
    NSView* frame = content.superview;
    if (!window || !content || !frame || view_.superview == frame) {
      return;
    }
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    content.wantsLayer = YES;
    content.layer.cornerRadius = kWindowCorner;
    content.layer.cornerCurve = kCACornerCurveContinuous;
    content.layer.masksToBounds = YES;
    if (!view_) {
      if (@available(macOS 26.0, *)) {
        view_ = [[RoomVideoControlsView alloc]
            initWithAction:base::BindRepeating(&RoomControls::Perform,
                                               weak_factory_.GetWeakPtr())];
      } else {
        return;
      }
    }
    view_.frame = content.frame;
    view_.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [frame addSubview:view_ positioned:NSWindowAbove relativeTo:content];
    [window invalidateShadow];
    Update();
    // Shown for a moment as the window opens (Chrome showed its title too).
    ShowForTesting();
    timer_.Start(FROM_HERE, kStateInterval,
                 base::BindRepeating(&RoomControls::Update, base::Unretained(this)));
  }

  // After each of Chrome's layouts: keep Chrome's own controls hidden, follow
  // the window's size.
  void AfterLayout(views::View* controls, views::View* title) {
    KeepHidden(controls);
    KeepHidden(title);
    // The scrims: the window's views after the video (which follows the background) up to the title.
    if (views::View* holder = title->parent()) {
      const std::optional<size_t> background = holder->GetIndexOf(window_->GetWindowBackgroundView());
      const std::optional<size_t> title_index = holder->GetIndexOf(title);
      if (background && title_index) {
        for (size_t i = *background + 2; i < *title_index; ++i) {
          KeepHidden(holder->children()[i]);
        }
      }
    }
    Attach();
    if (view_) {
      NSView* content = view_.window.contentView;
      if (content && !NSEqualRects(view_.frame, content.frame)) {
        view_.frame = content.frame;
      }
      [view_.window invalidateShadow];
    }
  }

  void ShowForTesting() {
    if (@available(macOS 26.0, *)) {
      [((RoomVideoControlsView*)view_) showControls];
    }
  }

 private:
  // Chrome shows its controls, title and scrims again on hover (its fade
  // animation sets each visible on every step); they go straight back.
  void KeepHidden(views::View* view) {
    if (!hidden_.IsObservingSource(view)) {
      hidden_.AddObservation(view);
    }
    view->SetVisible(false);
  }

  // views::ViewObserver:
  void OnViewVisibilityChanged(views::View* observed,
                               views::View* starting,
                               bool visible) override {
    if (observed == starting && visible) {
      observed->SetVisible(false);
    }
  }
  void OnViewIsDeleting(views::View* observed) override {
    hidden_.RemoveObservation(observed);
  }

  content::VideoPictureInPictureWindowController* controller() const {
    return static_cast<content::VideoPictureInPictureWindowController*>(
        window_->GetController());
  }

  void Update() {
    if (!view_) {
      return;
    }
    ControlsState state;
    state.playing = window_->playback_state_for_testing() ==
                    VideoOverlayWindowViews::PlaybackState::kPlaying;
    views::View* playback = window_->playback_controls_container_for_testing();
    state.playback = !playback || playback->GetVisible();
    state.live = window_->room_is_live();
    if (auto* c = controller()) {
      state.muted = c->GetMuteStatus();
    }
    auto visible = [](views::View* view) { return view && view->GetVisible(); };
    state.replay = visible(window_->replay_10_seconds_button_for_testing());
    state.forward = visible(window_->forward_10_seconds_button_for_testing());
    state.previous_track = visible(window_->previous_track_controls_view_for_testing());
    state.next_track = visible(window_->next_track_controls_view_for_testing());
    state.skip_ad = visible(window_->skip_ad_controls_view_for_testing());
    if (auto* microphone = window_->toggle_microphone_button_for_testing()) {
      state.microphone = microphone->GetVisible();
      state.microphone_muted = microphone->is_muted_for_testing();
    }
    if (auto* camera = window_->toggle_camera_button_for_testing()) {
      state.camera = camera->GetVisible();
      state.camera_on = camera->is_turned_on_for_testing();
    }
    state.hang_up = visible(window_->hang_up_button_for_testing());
    const media_session::MediaPosition& position = window_->room_media_position();
    state.duration = position.duration().InSecondsF();
    state.elapsed = std::clamp(position.GetPosition().InSecondsF(), 0.0, std::max(0.0, state.duration));
    if (auto* origin = window_->origin_for_testing()) {
      state.origin = std::u16string(origin->GetText());
    }
    if (@available(macOS 26.0, *)) {
      [((RoomVideoControlsView*)view_) updateState:state];
    }
  }

  void Perform(Action action, double seconds) {
    auto* c = controller();
    if (!c) {
      return;
    }
    const media_session::MediaPosition& position = window_->room_media_position();
    constexpr base::TimeDelta kSeek = base::Seconds(10);
    switch (action) {
      case Action::kClose:
        c->Close(/*should_pause_video=*/true);
        return;  // the window and this view go
      case Action::kBackToTab:
        c->CloseAndFocusInitiator();
        return;
      case Action::kPlayPause:
        c->TogglePlayPause();
        break;
      case Action::kReplay:
        c->SeekTo(std::max(base::TimeDelta(), position.GetPosition() - kSeek));
        break;
      case Action::kForward:
        c->SeekTo(std::min(position.GetPosition() + kSeek, position.duration()));
        break;
      case Action::kPreviousTrack:
        c->PreviousTrack();
        break;
      case Action::kNextTrack:
        c->NextTrack();
        break;
      case Action::kSkipAd:
        c->SkipAd();
        break;
      case Action::kToggleMute:
        c->RequestMute(!c->GetMuteStatus());
        break;
      case Action::kToggleMicrophone:
        c->ToggleMicrophone();
        break;
      case Action::kToggleCamera:
        c->ToggleCamera();
        break;
      case Action::kHangUp:
        c->HangUp();
        break;
      case Action::kSeek:
        c->SeekTo(base::Seconds(seconds));
        break;
    }
    Update();
  }

  raw_ptr<VideoOverlayWindowViews> window_;
  // A RoomVideoControlsView (macOS 26; typed as its base outside the checks).
  NSView* __strong view_ = nil;
  base::RepeatingTimer timer_;
  base::ScopedMultiSourceObservation<views::View, views::ViewObserver> hidden_{this};
  base::WeakPtrFactory<RoomControls> weak_factory_{this};
};

BEGIN_METADATA(RoomControls)
END_METADATA

// The windows' controls containers (spikes show their controls).
std::vector<std::unique_ptr<views::ViewTracker>>& Decorated() {
  static base::NoDestructor<std::vector<std::unique_ptr<views::ViewTracker>>> views;
  return *views;
}

void VideoOverlayHook(views::View* controls,
                      views::View* title,
                      views::Label* origin,
                      views::View* favicon,
                      views::Button* back_to_tab,
                      views::Button* close,
                      views::View* minimize,
                      views::View* playback,
                      bool layout) {
  auto* room_controls = static_cast<RoomControls*>(controls->GetViewByID(kControlsAnchorId));
  if (!room_controls) {
    auto* window = static_cast<VideoOverlayWindowViews*>(controls->GetWidget());
    if (!window) {
      return;
    }
    room_controls = controls->AddChildView(std::make_unique<RoomControls>(window));
    std::erase_if(Decorated(), [](const auto& tracker) { return !tracker->view(); });
    Decorated().push_back(std::make_unique<views::ViewTracker>(room_controls));
  }
  room_controls->AfterLayout(controls, title);
}

}  // namespace

void InstallVideoOverlayHook() {
  g_video_overlay_hook = &VideoOverlayHook;
}

int DebugShowVideoOverlayControls() {
  int shown = 0;
  for (const auto& tracker : Decorated()) {
    if (auto* controls = static_cast<RoomControls*>(tracker->view())) {
      controls->ShowForTesting();
      shown++;
    }
  }
  return shown;
}

}  // namespace room
