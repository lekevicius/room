import Foundation

public enum FolderPlacementError: Error, Equatable, Sendable {
    /// The move would nest folders deeper than `FolderRules.maxDepth`.
    case tooDeep(maxDepth: Int)
    /// A folder cannot move into itself or one of its descendants.
    case cycle
    case unknownFolder
}

/// Folder nesting (spec §A.6). Depth counts folders on the path from the
/// pinned root: a top-level folder has depth 1, its subfolder 2, … up to 5
/// (Zen's `zen.folders.max-subfolders`).
public enum FolderRules {
    public static let maxDepth = 5

    /// Depth of `folderID` (1 for a top-level folder); `nil` if a parent is
    /// missing or the chain loops.
    public static func depth(of folderID: UUID, in entries: [UUID: Entry]) -> Int? {
        var depth = 0
        var current: UUID? = folderID
        var visited = Set<UUID>()
        while let id = current {
            guard let folder = entries[id], folder.kind == .folder, visited.insert(id).inserted else { return nil }
            depth += 1
            current = folder.folderID
        }
        return depth
    }

    /// Folder levels in the subtree rooted at `entryID`, including itself
    /// (0 for a non-folder, 1 for a folder without subfolders).
    public static func height(of entryID: UUID, in entries: [UUID: Entry], children: [UUID: [UUID]]) -> Int {
        guard entries[entryID]?.kind == .folder else { return 0 }
        let below = (children[entryID] ?? []).map { height(of: $0, in: entries, children: children) }.max() ?? 0
        return 1 + below
    }

    /// Whether `entryID` may move into `folderID` (`nil` = the pinned root).
    /// The caller converts the entry to pinned first (`EntryRules.converted`).
    public static func validatePlacement(
        of entryID: UUID, into folderID: UUID?, in entries: [UUID: Entry]
    ) throws(FolderPlacementError) {
        guard entries[entryID] != nil, let folderID else { return }
        guard let targetDepth = depth(of: folderID, in: entries) else { throw .unknownFolder }
        // The target must not be the entry or inside it.
        var current: UUID? = folderID
        while let id = current {
            if id == entryID { throw .cycle }
            current = entries[id]?.folderID
        }
        let children = Dictionary(grouping: entries.values.filter { $0.folderID != nil }, by: { $0.folderID! })
            .mapValues { $0.map(\.id) }
        if targetDepth + height(of: entryID, in: entries, children: children) > maxDepth {
            throw .tooDeep(maxDepth: maxDepth)
        }
    }

    /// Whether a new folder may be created inside `parentID` (`nil` = root).
    public static func validateNewFolder(in parentID: UUID?, in entries: [UUID: Entry]) throws(FolderPlacementError) {
        guard let parentID else { return }
        guard let depth = depth(of: parentID, in: entries) else { throw .unknownFolder }
        if depth + 1 > maxDepth { throw .tooDeep(maxDepth: maxDepth) }
    }
}
