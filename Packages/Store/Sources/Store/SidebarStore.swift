import Foundation
import Model
import Observation

/// An ordered list of sibling entries.
public enum Container: Hashable, Sendable {
    case essentials(profile: UUID)
    /// The pinned root of a space (`folder == nil`) or a folder's children.
    case pinned(space: UUID, folder: UUID?)
    case today(space: UUID)

    public var section: EntrySection {
        switch self {
        case .essentials: .essentials
        case .pinned: .pinned
        case .today: .today
        }
    }
}

extension Entry {
    public var container: Container {
        switch kind {
        case .essential: .essentials(profile: profileID)
        case .pinned, .folder: .pinned(space: spaceID!, folder: folderID)
        case .today: .today(space: spaceID!)
        }
    }
}

/// What a mutation touched, delivered to observers after it is applied so
/// views can reload exactly those rows (no diffing of the whole tree).
public struct SidebarChange: Equatable, Sendable {
    /// Inserted, updated or moved entries.
    public var entries: Set<UUID> = []
    public var removedEntries: Set<UUID> = []
    /// Containers whose membership or order changed.
    public var containers: Set<Container> = []
    /// Spaces or profiles were added, removed, reordered or edited.
    public var spaces: Set<UUID> = []
    public var removedSpaces: Set<UUID> = []

    public var isEmpty: Bool { self == SidebarChange() }
}

public enum SidebarError: Error, Equatable {
    case unknownEntry(UUID)
    case unknownSpace(UUID)
    case unknownProfile(UUID)
    case conversion(EntryConversionError)
    case folder(FolderPlacementError)
    /// The folder is not in the target space's pinned section.
    case folderNotInSpace
    case lastSpace
    case invalidKind
}

/// A removed entry and where it was, for Undo (Clear, remove).
public struct RemovedEntry: Equatable, Sendable {
    public var entry: Entry
    public var index: Int
}

/// One node of a space's pinned tree.
public struct PinnedNode: Equatable, Sendable {
    public var entry: Entry
    public var children: [PinnedNode]
}

/// A value snapshot of what one space's sidebar shows.
public struct SpaceSnapshot: Equatable, Sendable {
    public var space: Space
    public var essentials: [Entry]
    public var pinned: [PinnedNode]
    public var today: [Entry]
}

/// The only writer of profiles, spaces, entries and split groups.
@Observable
public final class SidebarStore {
    public private(set) var profiles: [Profile]
    /// Ordered by position.
    public private(set) var spaces: [Space]
    public private(set) var entries: [UUID: Entry]
    public private(set) var splitGroups: [UUID: SplitGroup]

    @ObservationIgnored private var containers: [Container: [UUID]] = [:]
    @ObservationIgnored private var observers: [UUID: (SidebarChange) -> Void] = [:]
    @ObservationIgnored weak var persistence: Persistence?
    @ObservationIgnored let clock: () -> Timestamp

    init(state: RoomState, clock: @escaping () -> Timestamp = { .now }) {
        profiles = state.profiles.sorted { $0.position < $1.position }
        spaces = state.spaces.sorted { $0.position < $1.position }
        entries = Dictionary(state.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        splitGroups = Dictionary(state.splitGroups.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.clock = clock
        let grouped = Dictionary(grouping: entries.values, by: \.container)
        for (container, members) in grouped {
            containers[container] = members.sorted { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }.map(\.id)
        }
        for container in Array(containers.keys) { renumber(container) }
    }

    // MARK: Observation

    /// Calls `handler` after every mutation; keep the token alive.
    public func observe(_ handler: @escaping (SidebarChange) -> Void) -> ObservationToken {
        let id = UUID()
        observers[id] = handler
        return ObservationToken { [weak self] in self?.observers[id] = nil }
    }

    private func commit(_ change: SidebarChange) {
        guard !change.isEmpty else { return }
        persistence?.scheduleWrite()
        for observer in observers.values { observer(change) }
    }

    // MARK: Queries

    public func space(_ id: UUID) -> Space? { spaces.first { $0.id == id } }

    public func entry(_ id: UUID) -> Entry? { entries[id] }

    public func entries(in container: Container) -> [Entry] {
        (containers[container] ?? []).compactMap { entries[$0] }
    }

    public func essentials(profile: UUID) -> [Entry] { entries(in: .essentials(profile: profile)) }

    public func pinned(space: UUID, folder: UUID? = nil) -> [Entry] { entries(in: .pinned(space: space, folder: folder)) }

    public func today(space: UUID) -> [Entry] { entries(in: .today(space: space)) }

    public func isChanged(_ id: UUID) -> Bool { entries[id].map(EntryRules.isChanged) ?? false }

    /// Essentials, pinned (expanded, visible order), Today: ⌘1–9 and ⌥⌘↑/↓.
    public func sidebarOrder(space spaceID: UUID) -> [Entry] {
        guard let space = space(spaceID) else { return [] }
        var children: [UUID: [Entry]] = [:]
        for (container, ids) in containers {
            if case .pinned(spaceID, let folder?) = container { children[folder] = ids.compactMap { entries[$0] } }
        }
        return NavigationRules.sidebarOrder(
            essentials: essentials(profile: space.profileID), pinnedRoot: pinned(space: spaceID),
            pinnedChildren: children, today: today(space: spaceID), pinnedCollapsed: space.pinnedCollapsed)
    }

    /// Every selectable entry of the space, most recently used first.
    public func mruOrder(space: UUID) -> [Entry] {
        NavigationRules.mruOrder(selectable(space: space))
    }

    /// What ⌘W does to `id` and where the selection goes.
    public func closePlan(for id: UUID, behavior: PermanentCloseBehavior, space: UUID) -> (steps: CloseSteps, fallback: CloseFallback?)? {
        guard let entry = entries[id] else { return nil }
        let steps = NavigationRules.closeSteps(for: entry.kind, behavior: behavior)
        let fallback = steps.contains(.switchAway)
            ? NavigationRules.closeFallback(closing: entry, order: selectable(space: space)) : nil
        return (steps, fallback)
    }

    /// Selectable entries in sidebar order, including children of collapsed folders.
    private func selectable(space spaceID: UUID) -> [Entry] {
        guard let space = space(spaceID) else { return [] }
        var result = essentials(profile: space.profileID)
        func walk(_ folder: UUID?) {
            for entry in pinned(space: spaceID, folder: folder) {
                if entry.kind == .folder { walk(entry.id) } else { result.append(entry) }
            }
        }
        walk(nil)
        result += today(space: spaceID)
        return result
    }

    public func snapshot(space spaceID: UUID) -> SpaceSnapshot? {
        guard let space = space(spaceID) else { return nil }
        func nodes(_ folder: UUID?) -> [PinnedNode] {
            pinned(space: spaceID, folder: folder).map { PinnedNode(entry: $0, children: $0.kind == .folder ? nodes($0.id) : []) }
        }
        return SpaceSnapshot(space: space, essentials: essentials(profile: space.profileID), pinned: nodes(nil),
                             today: today(space: spaceID))
    }

    // MARK: Profiles and spaces

    @discardableResult
    public func createProfile(name: String) -> Profile {
        let profile = Profile(name: name, position: profiles.count)
        profiles.append(profile)
        commit(SidebarChange(spaces: [profile.id]))
        return profile
    }

    @discardableResult
    public func createSpace(name: String, profile profileID: UUID, icon: String? = nil) throws(SidebarError) -> Space {
        guard profiles.contains(where: { $0.id == profileID }) else { throw .unknownProfile(profileID) }
        let space = Space(name: name, icon: icon, profileID: profileID, position: spaces.count)
        spaces.append(space)
        commit(SidebarChange(spaces: [space.id]))
        return space
    }

    /// Edits name, icon, theme or the pinned-collapsed flag (not id, profile or position).
    public func updateSpace(_ id: UUID, _ body: (inout Space) -> Void) throws(SidebarError) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { throw .unknownSpace(id) }
        var space = spaces[index]
        body(&space)
        space.id = id
        space.profileID = spaces[index].profileID
        space.position = spaces[index].position
        guard space != spaces[index] else { return }
        spaces[index] = space
        commit(SidebarChange(spaces: [id]))
    }

    public func moveSpace(_ id: UUID, to index: Int) throws(SidebarError) {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { throw .unknownSpace(id) }
        let space = spaces.remove(at: from)
        spaces.insert(space, at: min(max(index, 0), spaces.count))
        for i in spaces.indices { spaces[i].position = i }
        commit(SidebarChange(spaces: Set(spaces.map(\.id))))
    }

    /// Deletes a space with its pinned entries and Today tabs (the Archive
    /// that keeps them is Chapter 4.1). The last space cannot be deleted.
    public func deleteSpace(_ id: UUID) throws(SidebarError) {
        guard spaces.contains(where: { $0.id == id }) else { throw .unknownSpace(id) }
        guard spaces.count > 1 else { throw .lastSpace }
        var change = SidebarChange()
        for entry in entries.values where entry.spaceID == id {
            entries[entry.id] = nil
            change.removedEntries.insert(entry.id)
        }
        for container in Array(containers.keys) {
            switch container {
            case .pinned(id, _), .today(id):
                containers[container] = nil
                change.containers.insert(container)
            default: break
            }
        }
        dropSplitMembership(of: change.removedEntries, into: &change)
        spaces.removeAll { $0.id == id }
        for i in spaces.indices { spaces[i].position = i }
        change.removedSpaces = [id]
        change.spaces = Set(spaces.map(\.id))
        commit(change)
    }

    // MARK: Entries

    /// Adds a tab entry (not a folder). Pinned entries and essentials store
    /// `url` and start unloaded; Today tabs get it as their live page.
    @discardableResult
    public func addEntry(_ kind: EntryKind, url: String?, title: String? = nil, space spaceID: UUID,
                         folder: UUID? = nil, at index: Int? = nil) throws(SidebarError) -> Entry {
        guard kind != .folder else { throw .invalidKind }
        guard let space = space(spaceID) else { throw .unknownSpace(spaceID) }
        var entry = Entry(kind: kind, spaceID: kind == .essential ? nil : spaceID, profileID: space.profileID,
                          createdAt: clock())
        switch kind {
        case .essential:
            guard EntryRules.canAddEssential(currentCount: essentials(profile: space.profileID).count) else {
                throw .conversion(.essentialsFull(cap: EntryRules.essentialsCap))
            }
            entry.storedURL = url
            entry.storedTitle = title
        case .pinned:
            if let folder { try validateFolder(folder, in: spaceID) }
            entry.folderID = folder
            entry.storedURL = url
            entry.storedTitle = title
        case .today, .folder:
            entry.liveURL = url
            entry.liveTitle = title
        }
        var change = SidebarChange()
        insert(entry, at: index, change: &change)
        commit(change)
        return entries[entry.id]!
    }

    @discardableResult
    public func addFolder(name: String, space spaceID: UUID, parent: UUID? = nil, at index: Int? = nil) throws(SidebarError) -> Entry {
        guard let space = space(spaceID) else { throw .unknownSpace(spaceID) }
        if let parent { try validateFolder(parent, in: spaceID) }
        do { try FolderRules.validateNewFolder(in: parent, in: entries) } catch { throw .folder(error) }
        let folder = Entry(kind: .folder, spaceID: spaceID, profileID: space.profileID, folderID: parent,
                           customLabel: name, createdAt: clock())
        var change = SidebarChange()
        insert(folder, at: index, change: &change)
        commit(change)
        return entries[folder.id]!
    }

    /// Moves an entry to `container` at `index` (clamped), converting its
    /// kind when the section changes (§A.9). Folders move with their subtree.
    public func move(_ id: UUID, to container: Container, at index: Int) throws(SidebarError) {
        guard let entry = entries[id] else { throw .unknownEntry(id) }
        let space: Space
        switch container {
        case .essentials(let profile):
            let current = entry.spaceID.flatMap { self.space($0) }
            guard let match = current?.profileID == profile ? current : spaces.first(where: { $0.profileID == profile }) else {
                throw .unknownProfile(profile)
            }
            space = match
        case .pinned(let spaceID, let folder):
            guard let match = self.space(spaceID) else { throw .unknownSpace(spaceID) }
            if let folder {
                try validateFolder(folder, in: spaceID)
                do { try FolderRules.validatePlacement(of: id, into: folder, in: entries) } catch { throw .folder(error) }
            }
            space = match
        case .today(let spaceID):
            guard let match = self.space(spaceID) else { throw .unknownSpace(spaceID) }
            space = match
        }
        let essentialsCount = essentials(profile: space.profileID).filter { $0.id != id }.count
        var converted: Entry
        do { converted = try EntryRules.converted(entry, to: container.section, in: space, essentialsCount: essentialsCount) } catch {
            throw .conversion(error)
        }
        if case .pinned(_, let folder) = container { converted.folderID = folder }

        var change = SidebarChange()
        detach(id, change: &change)
        insert(converted, at: index, change: &change)
        if converted.kind == .folder, converted.spaceID != entry.spaceID || converted.profileID != entry.profileID {
            reassignSubtree(of: id, to: space, change: &change)
        }
        commit(change)
    }

    /// Removes an entry. A folder's children move up into its parent, in its
    /// place (§A.6 Delete). Returns what was removed and where, for Undo.
    @discardableResult
    public func remove(_ id: UUID) throws(SidebarError) -> RemovedEntry {
        guard let entry = entries[id] else { throw .unknownEntry(id) }
        var change = SidebarChange()
        let index = detach(id, change: &change)
        if entry.kind == .folder {
            for (offset, child) in pinned(space: entry.spaceID!, folder: id).enumerated() {
                var moved = child
                detach(child.id, change: &change)
                moved.folderID = entry.folderID
                insert(moved, at: index + offset, change: &change)
            }
            containers[.pinned(space: entry.spaceID!, folder: id)] = nil
        }
        entries[id] = nil
        change.removedEntries.insert(id)
        change.entries.remove(id)
        dropSplitMembership(of: [id], into: &change)
        commit(change)
        return RemovedEntry(entry: entry, index: index)
    }

    /// Clear (⇧⌘K): removes every Today tab of the space; returns them for Undo.
    @discardableResult
    public func clearToday(space spaceID: UUID) -> [RemovedEntry] {
        let removed = today(space: spaceID).enumerated().map { RemovedEntry(entry: $0.element, index: $0.offset) }
        guard !removed.isEmpty else { return [] }
        var change = SidebarChange()
        containers[.today(space: spaceID)] = nil
        change.containers.insert(.today(space: spaceID))
        for item in removed {
            entries[item.entry.id] = nil
            change.removedEntries.insert(item.entry.id)
        }
        dropSplitMembership(of: change.removedEntries, into: &change)
        commit(change)
        return removed
    }

    /// Undo of `remove`/`clearToday`: puts entries back where they were
    /// (skipping any whose space or parent folder is gone).
    public func restore(_ removed: [RemovedEntry]) {
        var change = SidebarChange()
        for item in removed.sorted(by: { $0.index < $1.index }) where entries[item.entry.id] == nil {
            var entry = item.entry
            if let spaceID = entry.spaceID, space(spaceID) == nil { continue }
            if let folder = entry.folderID, entries[folder] == nil { entry.folderID = nil }
            if let group = entry.splitGroupID, splitGroups[group] == nil { entry.splitGroupID = nil }
            if entry.kind == .essential,
               !EntryRules.canAddEssential(currentCount: essentials(profile: entry.profileID).count) { continue }
            insert(entry, at: item.index, change: &change)
        }
        commit(change)
    }

    // MARK: Entry edits

    /// Rename (`nil` clears the label and shows the page title again).
    public func rename(_ id: UUID, to label: String?) throws(SidebarError) {
        try update(id) { $0.customLabel = label?.isEmpty == true ? nil : label }
    }

    public func setCustomIcon(_ id: UUID, _ icon: String?) throws(SidebarError) {
        try update(id) { $0.customIcon = icon }
    }

    public func setFolderCollapsed(_ id: UUID, _ collapsed: Bool) throws(SidebarError) {
        try update(id) { if $0.kind == .folder { $0.isCollapsed = collapsed } }
    }

    /// The page an entry shows (from the engine in 2.3).
    public func setLivePage(_ id: UUID, url: String?, title: String?) throws(SidebarError) {
        try update(id) {
            $0.liveURL = url
            $0.liveTitle = title
        }
    }

    public func setFavicon(_ id: UUID, _ faviconID: Int64?) throws(SidebarError) {
        try update(id) { $0.faviconID = faviconID }
    }

    /// Selection touches the MRU key.
    public func markActive(_ id: UUID, at time: Timestamp? = nil) throws(SidebarError) {
        let time = time ?? clock()
        try update(id) { $0.lastActiveAt = time }
    }

    /// "Reset to pinned URL": the live page goes back to the stored URL.
    public func resetToStoredURL(_ id: UUID) throws(SidebarError) {
        try update(id) {
            guard $0.kind.isPermanent, $0.kind != .folder, $0.liveURL != nil else { return }
            $0.liveURL = $0.storedURL
            $0.liveTitle = $0.storedTitle
        }
    }

    /// "Replace pinned URL with current".
    public func replaceStoredURLWithCurrent(_ id: UUID) throws(SidebarError) {
        try update(id) {
            guard $0.kind.isPermanent, $0.kind != .folder, let live = $0.liveURL else { return }
            $0.storedURL = live
            $0.storedTitle = $0.liveTitle
        }
    }

    /// "Edit pinned URL…".
    public func setStoredURL(_ id: UUID, _ url: String) throws(SidebarError) {
        try update(id) { if $0.kind == .pinned || $0.kind == .essential { $0.storedURL = url } }
    }

    private func update(_ id: UUID, _ body: (inout Entry) -> Void) throws(SidebarError) {
        guard var entry = entries[id] else { throw .unknownEntry(id) }
        let before = entry
        body(&entry)
        guard entry != before else { return }
        entries[id] = entry
        commit(SidebarChange(entries: [id]))
    }

    // MARK: Split groups (data only; the UI is Phase 2.7)

    @discardableResult
    public func createSplitGroup(_ members: [UUID], layout: SplitLayout = .hbox) throws(SidebarError) -> SplitGroup {
        for id in members where entries[id] == nil { throw .unknownEntry(id) }
        let group = SplitGroup(layout: layout, ratios: Array(repeating: 1 / Double(members.count), count: members.count))
        splitGroups[group.id] = group
        var change = SidebarChange()
        for id in members {
            entries[id]?.splitGroupID = group.id
            change.entries.insert(id)
        }
        commit(change)
        return group
    }

    // MARK: Internals

    private func validateFolder(_ folder: UUID, in spaceID: UUID) throws(SidebarError) {
        guard let entry = entries[folder], entry.kind == .folder, entry.spaceID == spaceID else { throw .folderNotInSpace }
    }

    private func insert(_ entry: Entry, at index: Int?, change: inout SidebarChange) {
        let container = entry.container
        var ids = containers[container] ?? []
        ids.insert(entry.id, at: min(max(index ?? ids.count, 0), ids.count))
        containers[container] = ids
        entries[entry.id] = entry
        renumber(container, change: &change)
        change.entries.insert(entry.id)
        change.containers.insert(container)
    }

    /// Takes an entry out of its container (the entry stays in `entries`);
    /// returns its former index.
    @discardableResult
    private func detach(_ id: UUID, change: inout SidebarChange) -> Int {
        guard let entry = entries[id] else { return 0 }
        let container = entry.container
        var ids = containers[container] ?? []
        let index = ids.firstIndex(of: id) ?? ids.count
        ids.removeAll { $0 == id }
        containers[container] = ids.isEmpty ? nil : ids
        renumber(container, change: &change)
        change.containers.insert(container)
        return index
    }

    private func renumber(_ container: Container) {
        var ignored = SidebarChange()
        renumber(container, change: &ignored)
    }

    private func renumber(_ container: Container, change: inout SidebarChange) {
        for (index, id) in (containers[container] ?? []).enumerated() where entries[id]?.position != index {
            entries[id]?.position = index
            change.entries.insert(id)
        }
    }

    /// A folder moved to another space: its descendants follow.
    private func reassignSubtree(of folderID: UUID, to space: Space, change: inout SidebarChange) {
        guard let oldSpace = entries.values.first(where: { $0.folderID == folderID })?.spaceID else { return }
        let old = Container.pinned(space: oldSpace, folder: folderID)
        let ids = containers[old] ?? []
        containers[old] = nil
        containers[.pinned(space: space.id, folder: folderID)] = ids.isEmpty ? nil : ids
        for id in ids {
            entries[id]?.spaceID = space.id
            entries[id]?.profileID = space.profileID
            change.entries.insert(id)
            if entries[id]?.kind == .folder { reassignSubtree(of: id, to: space, change: &change) }
        }
    }

    /// Split groups need two members; a lone survivor leaves its group.
    private func dropSplitMembership(of removed: Set<UUID>, into change: inout SidebarChange) {
        for (groupID, _) in splitGroups {
            let members = entries.values.filter { $0.splitGroupID == groupID }
            if members.count < 2 {
                splitGroups[groupID] = nil
                for member in members {
                    entries[member.id]?.splitGroupID = nil
                    change.entries.insert(member.id)
                }
            }
        }
    }

    var stateEntries: [Entry] { Array(entries.values) }
}

/// Keeps an observer registered while alive.
public final class ObservationToken {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) { self.cancellation = cancellation }

    public func cancel() {
        cancellation?()
        cancellation = nil
    }

    isolated deinit { cancel() }
}
