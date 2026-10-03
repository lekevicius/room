import Model

/// The click table of spec §A.2 (and §A.9's multi-select clicks) as a pure function.
public enum ClickRules {
    public enum Gesture: Equatable, Sendable {
        case primary
        /// ⌘-click.
        case command
        /// ⇧-click.
        case shift
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
        /// Add to or take out of the multi-selection (⌘-click, §A.9).
        case toggleSelection
        /// Select the range from the anchor (⇧-click, §A.9).
        case extendSelection
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
            return kind == .folder ? .none : .toggleSelection
        case .shift:
            return kind == .folder ? .none : .extendSelection
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
