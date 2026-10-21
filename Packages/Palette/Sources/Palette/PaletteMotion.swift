import Design

/// The palette's animations (spec §I.1, audited in 5.1b) and what each
/// becomes under Reduce Motion: the open's scale goes and its fade stays;
/// the close is a fade either way.
public enum PaletteMotion: String, CaseIterable, Sendable {
    /// Open: scale `PaletteMetrics.openScale` → 1 with a fade, `Motion.fast`, ease-out.
    case open
    /// Close: a fade out over `Motion.fast`.
    case close

    /// The variant under Reduce Motion.
    public var reduced: MotionVariant {
        switch self {
        case .open, .close: .crossfade
        }
    }

    /// The variant to run now (`Motion.preferences`).
    public var variant: MotionVariant { Motion.reduceMotion ? reduced : .full }
}
