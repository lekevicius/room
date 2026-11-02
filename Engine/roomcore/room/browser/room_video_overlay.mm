// The video picture-in-picture window's controls, restyled. 5.12 (the user
// on build 26): the playback buttons grow a little under the pointer, the
// origin centred, Chrome's minimize button gone. 5.13 (the user: "native
// liquid glass controls", Dia's window for the vibe): every button sits on a
// frosted disc and the progress row on a frosted capsule, the video blurred
// beneath them (the compositor's backdrop blur with a translucent fill and a
// light rim; AppKit's NSGlassEffectView cannot go beneath Views' buttons, as
// AppKit views draw above the window's compositor layer). Patch 0029 calls
// `DecorateVideoOverlay` once Chrome's views exist and after each of its
// layouts; Chrome's buttons stay the click targets and keep their places.

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
#include "chrome/browser/ui/views/overlay/playback_image_button.h"
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
constexpr int kDecorationsId = 0x524f0003;

constexpr int kOriginMargin = 12;
constexpr int kTopControlsHeight = 34;
constexpr float kHoverScale = 1.1f;
constexpr base::TimeDelta kHoverDuration = base::Milliseconds(150);
// The frosted backdrops: the blur, the fill and rim (white), the disc's
// margin around a button and the capsule's around the progress row.
constexpr float kFrostBlur = 12.f;
constexpr SkAlpha kFrostAlpha = 0x2e;
constexpr SkAlpha kFrostHoverAlpha = 0x4a;
constexpr SkAlpha kFrostRimAlpha = 0x55;
constexpr int kDiscMargin = 6;
constexpr int kCapsuleMargin = 6;

// A frosted shape under a control: the video blurred behind it, a translucent
// white fill and a light rim. It takes no events and follows its control's
// bounds (`Follow`) and hover (`SetHighlighted`).
class FrostView : public views::View {
  METADATA_HEADER(FrostView, views::View)

 public:
  FrostView() {
    SetCanProcessEventsWithinSubtree(false);
    SetPaintToLayer();
    layer()->SetFillsBoundsOpaquely(false);
    layer()->SetBackgroundBlur(kFrostBlur);
    layer()->SetBackdropFilterQuality(0.5f);
  }

  // A disc around `target`'s bounds (the capsule's bounds are set by its owner).
  void Follow(const gfx::Rect& target) {
    const int side = std::max(target.width(), target.height()) + 2 * kDiscMargin;
    SetBoundsRect(gfx::Rect(target.CenterPoint().x() - side / 2, target.CenterPoint().y() - side / 2, side, side));
  }

  void SetHighlighted(bool highlighted) {
    if (highlighted_ == highlighted) {
      return;
    }
    highlighted_ = highlighted;
    SchedulePaint();
  }

  void OnBoundsChanged(const gfx::Rect& previous) override {
    const float radius = std::min(width(), height()) / 2.f;
    layer()->SetRoundedCornerRadius(gfx::RoundedCornersF(radius));
  }

  void OnPaint(gfx::Canvas* canvas) override {
    const gfx::RectF bounds(GetLocalBounds());
    const float radius = std::min(bounds.width(), bounds.height()) / 2.f;
    cc::PaintFlags fill;
    fill.setAntiAlias(true);
    fill.setColor(SkColorSetA(SK_ColorWHITE, highlighted_ ? kFrostHoverAlpha : kFrostAlpha));
    canvas->DrawRoundRect(bounds, radius, fill);
    cc::PaintFlags rim;
    rim.setAntiAlias(true);
    rim.setStyle(cc::PaintFlags::kStroke_Style);
    rim.setStrokeWidth(1.f);
    rim.setColor(SkColorSetA(SK_ColorWHITE, kFrostRimAlpha));
    gfx::RectF inset = bounds;
    inset.Inset(0.5f);
    canvas->DrawRoundRect(inset, radius - 0.5f, rim);
  }

 private:
  bool highlighted_ = false;
};

BEGIN_METADATA(FrostView)
END_METADATA

// Holds the frosted backdrops and the buttons' hover subscriptions for as
// long as the window's controls live; its id marks a window already decorated.
class OverlayDecorations : public views::View {
  METADATA_HEADER(OverlayDecorations, views::View)

 public:
  OverlayDecorations() {
    SetID(kDecorationsId);
    SetCanProcessEventsWithinSubtree(false);
  }

  // A disc under `button` (in its parent, beneath it), brightening and growing with its hover.
  void Frost(views::Button* button, bool grows) {
    views::View* parent = button->parent();
    auto* frost = parent->AddChildViewAt(std::make_unique<FrostView>(), parent->GetIndexOf(button).value());
    discs_.push_back({button, frost});
    if (grows) {
      button->SetPaintToLayer();
      button->layer()->SetFillsBoundsOpaquely(false);
    }
    subscriptions_.push_back(button->AddStateChangedCallback(base::BindRepeating(
        [](views::Button* button, FrostView* frost, bool grows) {
          const bool hovered = button->GetState() == views::Button::STATE_HOVERED ||
                               button->GetState() == views::Button::STATE_PRESSED;
          frost->SetHighlighted(hovered);
          if (!grows) {
            return;
          }
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
        base::Unretained(button), base::Unretained(frost), grows)));
  }

  // The capsule under the progress row, in `playback`.
  void FrostProgress(views::View* playback) {
    capsule_ = playback->AddChildViewAt(std::make_unique<FrostView>(), 0);
  }

  // After Chrome's layout: each disc on its button (hidden with it), the capsule around the
  // progress bar and the timestamp.
  void Follow(views::View* playback) {
    for (auto& [button, frost] : discs_) {
      frost->SetVisible(button->GetVisible());
      frost->Follow(button->bounds());
    }
    if (!capsule_) {
      return;
    }
    gfx::Rect row;
    for (views::View* child : playback->children()) {
      if (child == capsule_.get() || !child->GetVisible() || views::IsViewClass<views::Button>(child) ||
          views::IsViewClass<FrostView>(child)) {
        continue;
      }
      // The progress bar and the timestamp: the views in the bottom quarter.
      if (child->bounds().y() > playback->height() * 3 / 4 && !child->bounds().IsEmpty()) {
        row.Union(child->bounds());
      }
    }
    capsule_->SetVisible(!row.IsEmpty());
    row.Inset(-kCapsuleMargin);
    capsule_->SetBoundsRect(row);
  }

 private:
  std::vector<std::pair<raw_ptr<views::Button>, raw_ptr<FrostView>>> discs_;
  raw_ptr<FrostView> capsule_ = nullptr;
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
  decorations->Frost(back_to_tab, /*grows=*/false);
  decorations->Frost(close, /*grows=*/false);
  minimize->SetVisible(false);
  favicon->SetVisible(false);
  origin->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  origin->SetEnabledColor(SK_ColorWHITE);
  origin->SetElideBehavior(gfx::ELIDE_HEAD);
  decorations->FrostProgress(playback);
  // A copy: frosting adds views to `playback`.
  const std::vector<views::View*> children(playback->children().begin(), playback->children().end());
  for (views::View* child : children) {
    if (auto* button = views::AsViewClass<views::Button>(child)) {
      decorations->Frost(button, /*grows=*/true);
    }
  }
}

void Layout(views::View* controls,
            views::View* title,
            views::Label* origin,
            views::Button* back_to_tab,
            views::Button* close,
            views::View* minimize,
            views::View* playback) {
  auto* decorations = static_cast<OverlayDecorations*>(controls->GetViewByID(kDecorationsId));
  if (!decorations) {
    return;
  }
  minimize->SetBoundsRect(gfx::Rect());
  minimize->SetVisible(false);
  decorations->Follow(playback);
  // The origin centred on the window between the top buttons, at their height.
  const int width = controls->width();
  int side = 0;
  for (views::Button* button : {back_to_tab, close}) {
    const gfx::Rect bounds = button->bounds();
    side = std::max(side, bounds.CenterPoint().x() < width / 2 ? bounds.right() : width - bounds.x());
  }
  const int margin = side + kOriginMargin;
  title->SetBounds(0, 0, width, kTopControlsHeight + kOriginMargin);
  origin->SetBounds(margin, 0, std::max(0, width - 2 * margin), kTopControlsHeight + kOriginMargin);
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
  Layout(controls, title, origin, back_to_tab, close, minimize, playback);
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
      // The largest playback button (play/pause) as the pointer over it leaves it.
      if (views::Button* play = window->play_pause_controls_view_for_testing()) {
        play->SetState(views::Button::STATE_HOVERED);
      }
      shown++;
    }
  }
  return shown;
}

}  // namespace room
