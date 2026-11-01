// The video picture-in-picture window's controls, restyled (5.12, the user on
// build 26: "nicer icons with a subtle scale up on hover, back to tab, URL,
// close header"). Patch 0029 calls `DecorateVideoOverlay` once Chrome's views
// exist and after each of its layouts. Chrome's Back to Tab and Close buttons
// stay the click targets: they are made transparent and stretched over Room's
// labelled pills, which draw beneath them and follow their hover. The origin
// sits centred between the pills, without the favicon; the playback buttons
// grow a little under the pointer. Chrome's minimize button goes.

#import <AppKit/AppKit.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "cc/paint/paint_flags.h"
#include "chrome/browser/ui/views/overlay/video_overlay_window_views.h"
#include "room/browser/room_video_overlay.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/compositor/layer.h"
#include "ui/compositor/layer_animator.h"
#include "ui/compositor/scoped_layer_animation_settings.h"
#include "ui/gfx/animation/tween.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/font_list.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/transform.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/text_constants.h"
#include "ui/views/controls/button/button.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/controls/label.h"
#include "ui/views/view.h"
#include "ui/views/view_tracker.h"
#include "ui/views/view_utils.h"

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

// View ids of Room's views inside Chrome's controls container.
constexpr int kBackPillId = 0x524f0001;
constexpr int kClosePillId = 0x524f0002;
constexpr int kDecorationsId = 0x524f0003;

constexpr int kPillHeight = 28;
constexpr int kPillMargin = 8;
constexpr int kPillPadding = 11;
constexpr int kPillIconSize = 13;
constexpr int kPillGap = 6;
constexpr int kOriginMargin = 12;
constexpr float kHoverScale = 1.1f;
constexpr base::TimeDelta kHoverDuration = base::Milliseconds(150);
constexpr SkAlpha kPillAlpha = 0x33;
constexpr SkAlpha kPillHoverAlpha = 0x55;

// An SF Symbol in white at `size` points (the window's controls are white on
// its dark scrim), as Views' image.
gfx::ImageSkia SymbolImage(NSString* name, int size) {
  NSImage* symbol = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
  NSImageSymbolConfiguration* config = [[NSImageSymbolConfiguration
      configurationWithPointSize:size
                          weight:NSFontWeightSemibold]
      configurationByApplyingConfiguration:[NSImageSymbolConfiguration
                                               configurationWithPaletteColors:@[ NSColor.whiteColor ]]];
  NSImage* image = [symbol imageWithSymbolConfiguration:config];
  return image ? gfx::Image(image).AsImageSkia() : gfx::ImageSkia();
}

// "Back to Tab" or "Close": a rounded translucent pill with a symbol and a
// label. It takes no events (Chrome's button over it does) and brightens
// while that button is hovered or pressed.
class OverlayPill : public views::View {
  METADATA_HEADER(OverlayPill, views::View)

 public:
  OverlayPill(NSString* symbol, const std::u16string& text, int id) {
    SetID(id);
    SetCanProcessEventsWithinSubtree(false);
    icon_ = AddChildView(std::make_unique<views::ImageView>());
    icon_->SetImage(ui::ImageModel::FromImageSkia(SymbolImage(symbol, kPillIconSize - 2)));
    label_ = AddChildView(std::make_unique<views::Label>(text));
    label_->SetEnabledColor(SK_ColorWHITE);
    label_->SetBackgroundColor(SK_ColorTRANSPARENT);
    label_->SetAutoColorReadabilityEnabled(false);
    label_->SetFontList(gfx::FontList().DeriveWithSizeDelta(0).DeriveWithWeight(gfx::Font::Weight::MEDIUM));
  }

  int PreferredWidth() const {
    return 2 * kPillPadding + kPillIconSize + kPillGap + label_->GetPreferredSize().width();
  }

  void Follow(views::Button* button) {
    subscription_ = button->AddStateChangedCallback(base::BindRepeating(
        [](OverlayPill* pill, views::Button* button) {
          pill->SetHighlighted(button->GetState() == views::Button::STATE_HOVERED ||
                               button->GetState() == views::Button::STATE_PRESSED);
        },
        base::Unretained(this), base::Unretained(button)));
  }

  void Layout(PassKey) override {
    const int y = (height() - kPillIconSize) / 2;
    icon_->SetBounds(kPillPadding, y, kPillIconSize, kPillIconSize);
    const int x = kPillPadding + kPillIconSize + kPillGap;
    label_->SetBounds(x, 0, width() - x - kPillPadding, height());
  }

  void OnPaint(gfx::Canvas* canvas) override {
    cc::PaintFlags flags;
    flags.setAntiAlias(true);
    flags.setColor(SkColorSetA(SK_ColorWHITE, highlighted_ ? kPillHoverAlpha : kPillAlpha));
    canvas->DrawRoundRect(gfx::RectF(GetLocalBounds()), height() / 2.f, flags);
  }

 private:
  void SetHighlighted(bool highlighted) {
    if (highlighted_ == highlighted) {
      return;
    }
    highlighted_ = highlighted;
    SchedulePaint();
  }

  raw_ptr<views::ImageView> icon_ = nullptr;
  raw_ptr<views::Label> label_ = nullptr;
  bool highlighted_ = false;
  base::CallbackListSubscription subscription_;
};

BEGIN_METADATA(OverlayPill)
END_METADATA

// Holds the playback buttons' hover subscriptions for as long as the window's
// controls live; its id marks a window already decorated.
class OverlayDecorations : public views::View {
  METADATA_HEADER(OverlayDecorations, views::View)

 public:
  OverlayDecorations() {
    SetID(kDecorationsId);
    SetCanProcessEventsWithinSubtree(false);
  }

  void Grow(views::Button* button) {
    button->SetPaintToLayer();
    button->layer()->SetFillsBoundsOpaquely(false);
    subscriptions_.push_back(button->AddStateChangedCallback(base::BindRepeating(
        [](views::Button* button) {
          const bool hovered = button->GetState() == views::Button::STATE_HOVERED ||
                               button->GetState() == views::Button::STATE_PRESSED;
          gfx::Transform transform;
          if (hovered) {
            const gfx::PointF center = gfx::RectF(button->GetLocalBounds()).CenterPoint();
            transform.Translate(center.x(), center.y());
            transform.Scale(kHoverScale, kHoverScale);
            transform.Translate(-center.x(), -center.y());
          }
          ui::ScopedLayerAnimationSettings settings(button->layer()->GetAnimator());
          settings.SetTransitionDuration(kHoverDuration);
          settings.SetTweenType(gfx::Tween::EASE_OUT);
          button->layer()->SetTransform(transform);
        },
        base::Unretained(button))));
  }

 private:
  std::vector<base::CallbackListSubscription> subscriptions_;
};

BEGIN_METADATA(OverlayDecorations)
END_METADATA

// The decorated windows' controls and titles (spikes show them).
std::vector<std::unique_ptr<views::ViewTracker>>& Decorated() {
  static base::NoDestructor<std::vector<std::unique_ptr<views::ViewTracker>>> views;
  return *views;
}

void Decorate(views::View* controls,
              views::View* title,
              views::Label* origin,
              views::View* favicon,
              views::Button* back_to_tab,
              views::Button* close,
              views::View* minimize,
              views::View* playback) {
  if (controls->GetViewByID(kDecorationsId)) {
    return;
  }
  auto* decorations = controls->AddChildView(std::make_unique<OverlayDecorations>());
  std::erase_if(Decorated(), [](const auto& tracker) { return !tracker->view(); });
  Decorated().push_back(std::make_unique<views::ViewTracker>(controls));
  Decorated().push_back(std::make_unique<views::ViewTracker>(title));
  // The pills go beneath Chrome's buttons, which stay on top for the clicks.
  auto back_pill = std::make_unique<OverlayPill>(@"arrow.up.left", u"Back to Tab", kBackPillId);
  back_pill->Follow(back_to_tab);
  controls->AddChildViewAt(std::move(back_pill), controls->GetIndexOf(back_to_tab).value());
  auto close_pill = std::make_unique<OverlayPill>(@"xmark", u"Close", kClosePillId);
  close_pill->Follow(close);
  controls->AddChildViewAt(std::move(close_pill), controls->GetIndexOf(close).value());
  for (views::Button* button : {back_to_tab, close}) {
    button->SetPaintToLayer();
    button->layer()->SetOpacity(0);
  }
  minimize->SetVisible(false);
  favicon->SetVisible(false);
  origin->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  origin->SetEnabledColor(SK_ColorWHITE);
  origin->SetElideBehavior(gfx::ELIDE_HEAD);
  for (views::View* child : playback->children()) {
    if (auto* button = views::AsViewClass<views::Button>(child)) {
      decorations->Grow(button);
    }
  }
}

void Layout(views::View* controls,
            views::View* title,
            views::Label* origin,
            views::Button* back_to_tab,
            views::Button* close,
            views::View* minimize) {
  auto* back_pill = static_cast<OverlayPill*>(controls->GetViewByID(kBackPillId));
  auto* close_pill = static_cast<OverlayPill*>(controls->GetViewByID(kClosePillId));
  if (!back_pill || !close_pill) {
    return;
  }
  const int width = controls->width();
  const gfx::Rect back(kPillMargin, kPillMargin, back_pill->PreferredWidth(), kPillHeight);
  const int close_width = close_pill->PreferredWidth();
  const gfx::Rect close_rect(width - kPillMargin - close_width, kPillMargin, close_width, kPillHeight);
  back_pill->SetBoundsRect(back);
  close_pill->SetBoundsRect(close_rect);
  back_to_tab->SetBoundsRect(back);
  close->SetBoundsRect(close_rect);
  minimize->SetBoundsRect(gfx::Rect());
  minimize->SetVisible(false);
  // The origin between the pills, centred on the window, at their height.
  title->SetBounds(0, 0, width, kPillMargin + kPillHeight);
  const int side = std::max(back.right(), width - close_rect.x()) + kOriginMargin;
  origin->SetBounds(side, kPillMargin, std::max(0, width - 2 * side), kPillHeight);
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
  if (!layout) {
    Decorate(controls, title, origin, favicon, back_to_tab, close, minimize, playback);
  }
  Layout(controls, title, origin, back_to_tab, close, minimize);
}

}  // namespace

void InstallVideoOverlayHook() {
  g_video_overlay_hook = &VideoOverlayHook;
}

int DebugShowVideoOverlayControls() {
  int shown = 0;
  for (const auto& tracker : Decorated()) {
    views::View* view = tracker->view();
    // Each window's controls container (the titles share its widget).
    if (!view || view->GetID() == kDecorationsId || !view->GetViewByID(kDecorationsId)) {
      continue;
    }
    if (auto* window = static_cast<VideoOverlayWindowViews*>(view->GetWidget())) {
      window->ForceControlsVisibleForTesting(true, true);
      shown++;
    }
  }
  return shown;
}

}  // namespace room
