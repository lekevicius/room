import Design

/// The card's animations (spec §I.1, §I.6, §D; audited in 5.1b) and what each
/// becomes under Reduce Motion. Peek and the split view (App) ask their case here.
public enum CardMotion: String, CaseIterable, Sendable {
    /// Peek opens: the card grows from the click to its place (`Motion.slow`, a spring
    /// without bounce, from `PeekMetrics.openStartScale`); the dim and the card fade in (`Motion.fast`).
    case peekOpen
    /// Peek closes: a fade out (`Motion.fast`).
    case peekClose
    /// A split pane's header shows on hover at the pane's top and hides (`Motion.fast`).
    case paneHeader
    /// The drop preview moves to the zone under a dragged entry (`Motion.fast`).
    case dropPreview
    /// A split is made, gains or loses a pane, or changes layout: the panes take their
    /// frames at once in both (chosen: a page resized every frame relays out every frame;
    /// spec §D gives no animation).
    case splitLayout

    /// The variant under Reduce Motion.
    public var reduced: MotionVariant {
        switch self {
        case .peekOpen, .peekClose, .paneHeader: .crossfade
        case .dropPreview, .splitLayout: .instant
        }
    }

    /// The variant to run now (`Motion.preferences`).
    public var variant: MotionVariant {
        if self == .splitLayout { return .instant }
        return Motion.reduceMotion ? reduced : .full
    }

    /// Whether it animates at all now.
    public var animates: Bool { variant != .instant }
}
