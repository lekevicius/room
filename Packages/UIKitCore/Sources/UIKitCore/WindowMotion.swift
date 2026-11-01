import Design

/// The window's own animations (spec §E, §I.1, §I.12; audited in 5.1b) and
/// what each becomes under Reduce Motion.
public enum WindowMotion: String, CaseIterable, Sendable {
    /// The hidden sidebar slides in over the page (`Motion.revealIn`, ease-out) and out
    /// (`Motion.revealOut`, ease-in) after `Timing.revealDwell` in the edge band (B-114).
    case reveal
    /// ⌘S docks the sidebar or hides it (5.11, the user on build 25: "very fast animation, not just
    /// appear"): it slides in from the window's edge as the card narrows beside it, or out as the card
    /// widens (`Motion.dock`, ease-in-out); under Reduce Motion the card moves at once and the sidebar fades.
    case dock
    /// The traffic lights fade in with the reveal's slide and out with it (B-114); quickly on ⌘S.
    case trafficLights
    /// A space's tint crossfades on a switch (`Motion.medium`, ease-in-out).
    case spaceTint
    /// An inactive window's sidebar content fades to `SidebarMetrics.inactiveContentAlpha` (`Motion.standard`).
    case windowActivity

    /// The variant under Reduce Motion: the slide becomes a fade; the fades stay fades.
    public var reduced: MotionVariant {
        switch self {
        case .reveal, .dock, .trafficLights, .spaceTint, .windowActivity: .crossfade
        }
    }

    /// The variant to run now (`Motion.preferences`).
    public var variant: MotionVariant { Motion.reduceMotion ? reduced : .full }
}
