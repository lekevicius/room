import Design

/// The sidebar's animations (spec §I.1, audited in 5.1a) and what each
/// becomes under Reduce Motion: movement turns into a crossfade or into the
/// end state at once; what is already a fade stays a fade. Every animated
/// call site asks its case here, so the choice follows `Motion.preferences`.
/// Values and curves are in `docs/design-tokens.md` "Motion" and "Added in
/// Phase 5.1a". The space tint (UIKitCore's `SpaceTintView`) is a colour
/// crossfade over `Motion.medium` with or without Reduce Motion.
public enum SidebarMotion: String, CaseIterable, Sendable {
    /// The selection pill follows its row while rows insert or leave
    /// (`Motion.standard`, ease-out, with the rows; a new selection never slides).
    case pillFollow
    /// Rows insert and leave: the rows below slide, the row fades (`Motion.standard`, ease-out);
    /// a folder's collapse and expand too (its children are rows; the selected child peeks).
    case rows
    /// A space switch: both lists slide by the list's width (`Motion.medium`, ease-out).
    case spaceSlide
    /// The footer's highlight slides to the active space icon, which scales up (`Motion.medium`).
    case spaceIndicator
    /// The other space icons make room while one is dragged (`Motion.standard`).
    case spaceIconReorder
    /// The hovered space's name beside the icons (`Motion.fast`).
    case spaceName
    /// The Essentials grid's tiles move to their new places, and the list under it (`Motion.standard`, ease-out).
    case essentialsReflow
    /// A tile fades in or out (`Motion.standard`, ease-out).
    case essentialFade
    /// A refused drop on a full grid: the shake (`Motion.shake`).
    case refusedDrop
    /// The changed dot appears (`Motion.fast`).
    case changedDot
    /// The favicon and the reset icon swap on hover (`Motion.fast`).
    case resetIconSwap
    /// The favicon crossfades back to the stored icon on reset (`Motion.resetCrossfade`).
    case resetCrossfade
    /// The row pulses 1 → 0.98 → 1 on a committed rename (`Motion.renamePulse`).
    case renamePulse
    /// Clear: the Today rows slide out one after another (`Motion.standard`, `clearStagger`).
    case clearSlide
    /// Clear fades in and out as the pointer enters and leaves the sidebar (`Motion.fast`, B-118).
    case clearReveal
    /// The overflow line's click scrolls to the selected row (`Motion.medium`).
    case scrollToSelected
    /// The favicon's loading ring spins.
    case loadingRing
    /// The audible tab's equaliser.
    case audioIndicator
    /// The folder preview's popover.
    case folderPreview

    /// The variant under Reduce Motion.
    public var reduced: MotionVariant {
        switch self {
        case .pillFollow, .rows, .spaceIndicator, .spaceIconReorder, .essentialsReflow, .renamePulse, .scrollToSelected,
             .loadingRing, .audioIndicator, .folderPreview:
            .instant
        case .spaceSlide, .spaceName, .essentialFade, .refusedDrop, .changedDot, .resetIconSwap, .resetCrossfade,
             .clearSlide, .clearReveal:
            .crossfade
        }
    }

    /// The variant to run now (`Motion.preferences`).
    public var variant: MotionVariant { Motion.reduceMotion ? reduced : .full }

    /// Whether it animates at all now.
    public var animates: Bool { variant != .instant }
}
