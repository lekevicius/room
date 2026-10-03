import Model

/// The click table of spec §A.2 as a pure function.
public enum ClickRules {
    public enum Gesture: Equatable, Sendable {
        case primary
        /// ⌘-click.
        case command
        case middle
    }

    public enum Outcome: Equatable, Sendable {
        /// Make it the selected entry (loads the page if unloaded).
        case select
        /// Navigate back to the stored URL.
        case reset
        /// Reset, and keep the current page as a new Today tab (⌘-click).
        case separate
        /// Drop the page; the entry stays.
        case unload
        /// Unpin and remove (pinned entry that is already unloaded).
        case remove
        /// Close a Today tab.
        case close
        case none
    }

    /// `isChanged` is the loaded page's state: an unloaded entry is never changed.
    public static func outcome(_ gesture: Gesture, kind: EntryKind, isSelected: Bool, isChanged: Bool,
                               isLoaded: Bool) -> Outcome {
        let permanentTab = kind == .essential || kind == .pinned
        switch gesture {
        case .primary:
            if isSelected { return permanentTab && isChanged && isLoaded ? .reset : .none }
            return .select
        case .command:
            if isSelected && permanentTab && isChanged && isLoaded { return .separate }
            // Multi-select toggling is Phase 2.2b; until then ⌘-click selects.
            return isSelected ? .none : .select
        case .middle:
            switch kind {
            case .today: return .close
            case .essential: return isLoaded ? .unload : .none
            case .pinned: return isLoaded ? .unload : .remove
            case .folder: return .none
            }
        }
    }
}
