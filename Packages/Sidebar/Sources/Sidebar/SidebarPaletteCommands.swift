import AppKit
import Model
import Store

/// The selected entry's commands as the palette runs them (spec §C command
/// list, Phase 2.4b): the same operations as the context menu, on the selection.
extension SidebarController {
    private var selectedEntry: Entry? { selectedEntryID.flatMap { sidebar.entry($0) } }

    /// The selected entry has a page address (Copy URL, Duplicate apply).
    public var selectedHasURL: Bool { selectedEntry?.currentURL != nil }

    public func copySelectedURL(markdown: Bool) {
        guard let id = selectedEntryID else { return }
        copyURL(of: id, markdown: markdown)
    }

    public func duplicateSelected() {
        guard let id = selectedEntryID else { return }
        duplicate(id)
    }

    public func unloadSelected() {
        guard let id = selectedEntryID else { return }
        unload(id)
    }

    /// A permanent entry away from its stored URL (Reset Pinned Tab applies, spec §A.5).
    public var canResetSelected: Bool { selectedEntry.map(EntryRules.isChanged) ?? false }

    public func resetSelected() {
        guard let id = selectedEntryID, canResetSelected else { return }
        reset(id)
    }

    /// A new top-level folder in the pinned section, renamed inline.
    public func newFolderCommand() { newFolder(parent: nil) }

    /// The other spaces, for "Focus on {space}" and "Move to {space}".
    public var otherSpaces: [Space] { sidebar.spaces.filter { $0.id != tree.spaceID } }

    /// Moves the selected entry (not an essential or a folder) to `space`.
    public func moveSelected(toSpace space: UUID) {
        guard let entry = selectedEntry, entry.kind == .today || entry.kind == .pinned else { return }
        move(entry.id, toSpace: space)
    }

    public var canMoveSelected: Bool { selectedEntry.map { $0.kind == .today || $0.kind == .pinned } ?? false }
}
