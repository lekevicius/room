import Design

/// The ⌃Tab switcher's animation (5.1b) and its Reduce Motion variant.
public enum TabsMotion: String, CaseIterable, Sendable {
    /// The list fades in once ⌃ has been held `Timing.tabSwitcherDelay` (`Motion.fast`, ease-out,
    /// as the palette's fade; chosen: the spec gives the switcher no animation). It goes at once.
    case switcherAppear

    /// The variant under Reduce Motion: it is a fade already.
    public var reduced: MotionVariant {
        switch self {
        case .switcherAppear: .crossfade
        }
    }

    /// The variant to run now (`Motion.preferences`).
    public var variant: MotionVariant { Motion.reduceMotion ? reduced : .full }
}
