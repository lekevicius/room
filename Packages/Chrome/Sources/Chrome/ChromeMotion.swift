import Design

/// The page chrome's animations (spec §F, §I.1; audited in 5.1b) and what
/// each becomes under Reduce Motion: movement and scale turn into a
/// crossfade or into the end state at once; what is already a fade stays a
/// fade. Every animated call site in Chrome asks its case here, so the
/// choice follows `Motion.preferences`. Values in `docs/design-tokens.md`
/// "Motion" and "Added in Phase 5.1b".
public enum ChromeMotion: String, CaseIterable, Sendable {
    /// A toast springs in (`Motion.toast`: rises `toastInOffset`, grows from `toastInScale`, fades in).
    case toastIn
    /// The same id again: the toast pops (`toastPopScale` over `toastPopUp`, back over `toastPopDown`).
    case toastPop
    /// A toast leaves: fades and shrinks to `toastOutScale` over `Motion.toastOut`.
    case toastOut
    /// A new download's icon flies on an arc into the downloads button (`DownloadsMetrics.flyDuration`).
    case downloadFlyIn
    /// The downloads button bounces on a finished download (`Motion.toast`).
    case downloadBounce
    /// The download ring grows to the new progress (`Motion.medium`, ease-out).
    case downloadProgress
    /// The ring spins while a size is unknown.
    case downloadSpinner
    /// The popovers (downloads, the site panel, a permission prompt) animate in and out (AppKit's).
    case popover
    /// A page's dialog fades in over the page (`Motion.fast`).
    case promptFade

    /// The variant under Reduce Motion.
    public var reduced: MotionVariant {
        switch self {
        case .toastPop, .downloadFlyIn, .downloadProgress, .downloadSpinner, .popover:
            .instant
        case .toastIn, .toastOut, .downloadBounce, .promptFade:
            .crossfade
        }
    }

    /// The variant to run now (`Motion.preferences`).
    public var variant: MotionVariant { Motion.reduceMotion ? reduced : .full }

    /// Whether it animates at all now.
    public var animates: Bool { variant != .instant }
}
