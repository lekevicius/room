import AppKit
import Model
import Store

/// One row of the outline. Identity is stable for the life of the tree
/// (NSOutlineView compares items by pointer).
public final class OutlineNode: NSObject, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The space name; its children are the pinned root.
        case spaceTitle
        case entry(UUID)
        /// The 1 px line above the Today tabs, with "Clear".
        case separator
        case newTab
    }

    public let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    public var entryID: UUID? {
        if case .entry(let id) = kind { return id }
        return nil
    }

    public nonisolated override var description: String { "OutlineNode(\(kind))" }
}

/// The children lists NSOutlineView currently believes, for one space, and
/// how a `SidebarChange` updates them. Only the lists of the containers a
/// change names are re-read from the store and compared (plus collapsed
/// lists, whose "peeking" selected child depends on the selection); the
/// tree as a whole is never diffed.
///
/// Outline shape: root = space title, separator, Today tabs, New Tab. The
/// space title's children are the pinned root; a folder's children are its
/// entries. Expandable nodes are always expanded in NSOutlineView; a
/// collapsed folder (or pinned section) simply lists no children, except
/// the selected entry when it is inside (spec §A.6 "peeking").
final class SidebarTree {
    enum ParentKey: Hashable {
        case root
        case pinnedRoot
        case folder(UUID)
    }

    struct Update {
        /// Per parent (nil = root), indexes in the old list, removed first.
        var removals: [(parent: OutlineNode?, indexes: IndexSet)] = []
        /// Per parent, indexes in the new list, inserted after all removals.
        var insertions: [(parent: OutlineNode?, indexes: IndexSet)] = []
        /// Displayed nodes whose content changed (not inserted ones).
        var reconfigure: [OutlineNode] = []
        /// Inserted expandable nodes (to expand after the insert).
        var insertedExpandable: [OutlineNode] = []
        var essentialsChanged = false
        var spaceChanged = false

        var changesRows: Bool { !removals.isEmpty || !insertions.isEmpty }
    }

    let store: SidebarStore
    let spaceID: UUID
    /// The selected entry (peeks out of a collapsed folder).
    var selectedEntry: UUID?

    let spaceTitle = OutlineNode(.spaceTitle)
    let separator = OutlineNode(.separator)
    let newTab = OutlineNode(.newTab)
    private var entryNodes: [UUID: OutlineNode] = [:]
    /// What the outline was last told, per parent.
    private var lists: [ParentKey: [OutlineNode]] = [:]
    /// The parent list each displayed entry node is in.
    private var parentOf: [UUID: ParentKey] = [:]
    /// Essentials last handed to the grid.
    private(set) var essentialIDs: [UUID] = []

    init(store: SidebarStore, spaceID: UUID, selectedEntry: UUID?) {
        self.store = store
        self.spaceID = spaceID
        self.selectedEntry = selectedEntry
        reloadAll()
    }

    var space: Space? { store.space(spaceID) }

    func node(for id: UUID) -> OutlineNode {
        if let node = entryNodes[id] { return node }
        let node = OutlineNode(.entry(id))
        entryNodes[id] = node
        return node
    }

    /// The node if it is in the outline now; a split's pane is shown by its group row.
    func displayedNode(for id: UUID) -> OutlineNode? {
        let row = rowEntry(for: id)
        return parentOf[row] == nil ? nil : entryNodes[row]
    }

    /// The entry whose row shows `id`: its split's anchor (spec §D, one row per split), else itself.
    func rowEntry(for id: UUID) -> UUID {
        guard let group = store.splitGroup(of: id) else { return id }
        return SplitRules.anchor(of: store.splitMembers(group.id)) ?? id
    }

    /// A split's pane that another pane's group row stands for (not listed).
    private func isHiddenPane(_ entry: Entry) -> Bool {
        entry.splitGroupID != nil && rowEntry(for: entry.id) != entry.id
    }

    func entry(_ node: OutlineNode) -> Entry? { node.entryID.flatMap(store.entry) }

    // MARK: Data source

    func children(of node: OutlineNode?) -> [OutlineNode] {
        guard let key = parentKey(of: node) else { return [] }
        if let list = lists[key] { return list }
        let list = compute(key)
        record(list, for: key)
        return list
    }

    func isExpandable(_ node: OutlineNode) -> Bool {
        switch node.kind {
        case .spaceTitle: true
        case .entry(let id): store.entry(id)?.kind == .folder
        case .separator, .newTab: false
        }
    }

    func parentKey(of node: OutlineNode?) -> ParentKey? {
        guard let node else { return .root }
        switch node.kind {
        case .spaceTitle: return .pinnedRoot
        case .entry(let id): return store.entry(id)?.kind == .folder ? .folder(id) : nil
        case .separator, .newTab: return nil
        }
    }

    func parentNode(for key: ParentKey) -> OutlineNode? {
        switch key {
        case .root: nil
        case .pinnedRoot: spaceTitle
        case .folder(let id): entryNodes[id]
        }
    }

    /// Forgets everything; the outline must `reloadData()`.
    func reloadAll() {
        lists = [:]
        parentOf = [:]
        essentialIDs = space.map { store.essentials(profile: $0.profileID).map(\.id) } ?? []
    }

    // MARK: Changes

    /// The row updates for `change`, with the lists already brought up to date.
    func update(for change: SidebarChange) -> Update {
        var keys = Set<ParentKey>()
        var update = Update()
        for container in change.containers {
            switch container {
            case .essentials(let profile):
                if profile == space?.profileID { update.essentialsChanged = true }
            case .pinned(let space, let folder) where space == spaceID:
                keys.insert(folder.map(ParentKey.folder) ?? .pinnedRoot)
            case .today(let space) where space == spaceID:
                keys.insert(.root)
            default:
                break
            }
        }
        for id in change.entries {
            guard let entry = store.entry(id) else { continue }
            if entry.kind == .essential, entry.profileID == space?.profileID { update.essentialsChanged = true }
            // A folder opened or closed.
            if entry.kind == .folder, lists[.folder(id)] != nil { keys.insert(.folder(id)) }
        }
        if !change.removedEntries.isDisjoint(with: essentialIDs) { update.essentialsChanged = true }
        if change.spaces.contains(spaceID) {
            update.spaceChanged = true
            keys.insert(.pinnedRoot)
            // Set Profile: the grid shows the new profile's essentials.
            if let space, essentialIDs != store.essentials(profile: space.profileID).map(\.id) { update.essentialsChanged = true }
        }
        keys.formUnion(collapsedKeys())
        if update.essentialsChanged {
            essentialIDs = space.map { store.essentials(profile: $0.profileID).map(\.id) } ?? []
        }

        let inserted = apply(keys, into: &update)
        for id in change.entries where !inserted.contains(id) {
            if let node = displayedNode(for: id) { update.reconfigure.append(node) }
        }
        if keys.contains(.root) { update.reconfigure.append(separator) }
        if update.spaceChanged { update.reconfigure.append(spaceTitle) }
        return update
    }

    /// The selection moved: collapsed lists may peek a different child.
    func selectionChanged(to entry: UUID?) -> Update {
        selectedEntry = entry
        var update = Update()
        apply(collapsedKeys(), into: &update)
        return update
    }

    /// Re-reads `keys` from the store and records removals/insertions.
    /// Returns the ids of inserted entries.
    @discardableResult
    private func apply(_ keys: Set<ParentKey>, into update: inout Update) -> Set<UUID> {
        var inserted = Set<UUID>()
        var removedFolders: [UUID] = []
        // Parents first, so a folder dropped from its parent is not refreshed as a parent too.
        for key in keys.sorted(by: { depth($0) < depth($1) }) {
            guard let old = lists[key] else { continue }
            if case .folder(let id) = key, parentOf[id] == nil || inserted.contains(id) {
                // Gone, or (re)inserted in this update: NSOutlineView reads
                // its children afresh when it is expanded.
                forgetLists(under: id)
                continue
            }
            let new = compute(key)
            let difference = new.map(\.kind).difference(from: old.map(\.kind))
            guard !difference.isEmpty else { continue }
            var removals = IndexSet()
            var insertions = IndexSet()
            for step in difference {
                switch step {
                case .remove(let offset, let kind, _):
                    removals.insert(offset)
                    if case .entry(let id) = kind, parentOf[id] == key {
                        parentOf[id] = nil
                        removedFolders.append(id)
                    }
                case .insert(let offset, let kind, _):
                    insertions.insert(offset)
                    if case .entry(let id) = kind {
                        inserted.insert(id)
                        if isExpandable(new[offset]) { update.insertedExpandable.append(new[offset]) }
                    }
                }
            }
            record(new, for: key)
            let parent = parentNode(for: key)
            if !removals.isEmpty { update.removals.append((parent, removals)) }
            if !insertions.isEmpty { update.insertions.append((parent, insertions)) }
        }
        // A folder that left the outline takes its lists with it; they are
        // read again if it comes back.
        for id in removedFolders where parentOf[id] == nil { forgetLists(under: id) }
        return inserted
    }

    private func forgetLists(under folder: UUID) {
        guard let list = lists.removeValue(forKey: .folder(folder)) else { return }
        for node in list {
            guard let id = node.entryID, parentOf[id] == .folder(folder) else { continue }
            parentOf[id] = nil
            forgetLists(under: id)
        }
    }

    private func record(_ list: [OutlineNode], for key: ParentKey) {
        lists[key] = list
        for node in list {
            if let id = node.entryID { parentOf[id] = key }
        }
    }

    private func depth(_ key: ParentKey) -> Int {
        switch key {
        case .root: 0
        case .pinnedRoot: 1
        case .folder(let id): 1 + (FolderRules.depth(of: id, in: store.entries) ?? 0)
        }
    }

    /// Displayed lists that are collapsed (their peek follows the selection).
    private func collapsedKeys() -> Set<ParentKey> {
        var keys = Set<ParentKey>()
        if space?.pinnedCollapsed == true, lists[.pinnedRoot] != nil { keys.insert(.pinnedRoot) }
        for key in lists.keys {
            if case .folder(let id) = key, store.entry(id)?.isCollapsed == true { keys.insert(key) }
        }
        return keys
    }

    private func compute(_ key: ParentKey) -> [OutlineNode] {
        guard let space else { return [] }
        switch key {
        case .root:
            return [spaceTitle, separator] + store.today(space: spaceID).filter { !isHiddenPane($0) }.map { node(for: $0.id) } + [newTab]
        case .pinnedRoot:
            let entries = store.pinned(space: spaceID).filter { !isHiddenPane($0) }
            return (space.pinnedCollapsed ? peek(in: entries) : entries).map { node(for: $0.id) }
        case .folder(let id):
            let entries = store.pinned(space: spaceID, folder: id).filter { !isHiddenPane($0) }
            let collapsed = store.entry(id)?.isCollapsed == true
            return (collapsed ? peek(in: entries) : entries).map { node(for: $0.id) }
        }
    }

    /// The selected entry if it is somewhere under `entries` (a collapsed list shows only it; a split's pane, its group row).
    private func peek(in entries: [Entry]) -> [Entry] {
        guard let selectedEntry, let selected = store.entry(rowEntry(for: selectedEntry)) else { return [] }
        func contains(_ list: [Entry]) -> Bool {
            list.contains { $0.id == selected.id || ($0.kind == .folder && contains(store.pinned(space: spaceID, folder: $0.id))) }
        }
        return contains(entries) ? [selected] : []
    }
}
