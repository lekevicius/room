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
    /// The Archive gained or lost rows (the Library and the palette reload).
    public var archive = false
    /// The whole state was replaced (Restore Sidebar…): rebuild, do not diff.
    public var reloaded = false
    /// The routing rules changed (schema v8; the routing sheet reloads).
    public var routingRules = false

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
    /// A split has 2…4 panes (spec §D: "Can't add more panes").
    case splitFull
    case unknownSplitGroup(UUID)
    case unknownRoutingRule(UUID)
    /// A routing rule's pattern cannot be saved (an invalid regex, an empty pattern).
    case routingPattern(RoutingRules.PatternError)
    /// An `ImportBatch` refers to a new profile or space it does not list.
    case invalidImport
}

/// A removed entry and where it was, for Undo (Clear, remove).
public struct RemovedEntry: Equatable, Sendable {
    public var entry: Entry
    public var index: Int
}

/// A deleted space with everything it held, for Undo (spec §B). Its entries
/// are in the Archive too (reason `spaceDeleted`, B-15); Undo takes them back
/// out. The routing rules that targeted it were deleted with it (spec §B) and
/// come back with Undo.
public struct RemovedSpace: Equatable, Sendable {
    public var space: Space
    public var index: Int
    public var entries: [Entry]
    public var splitGroups: [SplitGroup]
    public var routingRules: [RoutingRule] = []
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
    /// The Archive (schema v7, spec §A.7 and §H), by id (the archived entry's id).
    public private(set) var archive: [UUID: ArchivedEntry]
    /// Space routing rules (schema v8, spec §B), in position order.
    public private(set) var routingRules: [RoutingRule]

    @ObservationIgnored private var containers: [Container: [UUID]] = [:]
    @ObservationIgnored private var observers: [UUID: (SidebarChange) -> Void] = [:]
    @ObservationIgnored weak var persistence: Persistence?
    /// The store's clock (tests inject one; DEBUG `-RoomClock` sets it in the app).
    @ObservationIgnored public var clock: () -> Timestamp

    init(state: RoomState, clock: @escaping () -> Timestamp = { .now }) {
        profiles = state.profiles.sorted { $0.position < $1.position }
        spaces = state.spaces.sorted { $0.position < $1.position }
        entries = Dictionary(state.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        splitGroups = Dictionary(state.splitGroups.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        archive = Dictionary(state.archive.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        routingRules = state.routingRules.sorted { $0.position < $1.position }
        self.clock = clock
        rebuildContainers()
    }

    private func rebuildContainers() {
        containers = [:]
        let grouped = Dictionary(grouping: entries.values, by: \.container)
        for (container, members) in grouped {
            containers[container] = members.sorted { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }.map(\.id)
        }
        for container in Array(containers.keys) { renumber(container) }
        var ignored = SidebarChange()
        normalizeSplitGroups(into: &ignored)
    }

    /// Restore Sidebar… (spec §H, 4.1b): the spaces, entries, split groups,
    /// the Archive and the routing rules become `state`'s. Profiles only grow (B-22): the current
    /// ones stay and the backup's missing ones come back. One change with
    /// `reloaded` set: views rebuild instead of applying it row by row.
    public func replace(with state: RoomState) {
        let oldEntries = Set(entries.keys)
        let oldSpaces = Set(spaces.map(\.id))
        var merged = profiles
        for profile in state.profiles where !merged.contains(where: { $0.id == profile.id }) { merged.append(profile) }
        profiles = merged.sorted { $0.position < $1.position }
        spaces = state.spaces.sorted { $0.position < $1.position }
        entries = Dictionary(state.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        splitGroups = Dictionary(state.splitGroups.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        archive = Dictionary(state.archive.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        routingRules = state.routingRules.sorted { $0.position < $1.position }
        rebuildContainers()
        var change = SidebarChange(archive: true)
        change.reloaded = true
        change.routingRules = true
        change.entries = Set(entries.keys)
        change.removedEntries = oldEntries.subtracting(entries.keys)
        change.spaces = Set(spaces.map(\.id))
        change.removedSpaces = oldSpaces.subtracting(spaces.map(\.id))
        change.containers = Set(containers.keys)
        commit(change)
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

    /// A new profile (cookie jar). Names are unique ignoring case ("Work 2"):
    /// the engine keeps one directory per name.
    @discardableResult
    public func createProfile(name: String) -> Profile {
        let profile = Profile(name: SpaceRules.uniqueName(name, existing: profiles.map(\.name)), position: profiles.count)
        profiles.append(profile)
        commit(SidebarChange(spaces: [profile.id]))
        return profile
    }

    /// A new space at `index` (default: the end), with its look (spec §B form).
    @discardableResult
    public func createSpace(name: String, profile profileID: UUID, icon: String? = nil, themeColors: [String] = [],
                            themeAlgorithm: ThemeAlgorithm = .floating, themeOpacity: Double = 0.5,
                            at index: Int? = nil) throws(SidebarError) -> Space {
        guard profiles.contains(where: { $0.id == profileID }) else { throw .unknownProfile(profileID) }
        let space = Space(name: name, icon: icon, themeColors: Array(themeColors.prefix(ThemePalette.maxColors)),
                          themeAlgorithm: themeAlgorithm, themeOpacity: themeOpacity, profileID: profileID, position: spaces.count)
        spaces.insert(space, at: min(max(index ?? spaces.count, 0), spaces.count))
        for i in spaces.indices { spaces[i].position = i }
        commit(SidebarChange(spaces: Set(spaces.map(\.id))))
        return self.space(space.id)!
    }

    /// "Set Profile" (spec §B): the space and everything in it (pinned
    /// entries, folders, Today tabs) move to `profileID`'s cookie jar; the
    /// profile's essentials show in it from now on. Returns the entries
    /// that changed profile (their pages load again in the new one).
    @discardableResult
    public func setSpaceProfile(_ spaceID: UUID, to profileID: UUID) throws(SidebarError) -> [Entry] {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { throw .unknownSpace(spaceID) }
        guard profiles.contains(where: { $0.id == profileID }) else { throw .unknownProfile(profileID) }
        guard spaces[index].profileID != profileID else { return [] }
        spaces[index].profileID = profileID
        var change = SidebarChange(spaces: [spaceID])
        var moved: [Entry] = []
        for entry in entries.values where entry.spaceID == spaceID {
            entries[entry.id]?.profileID = profileID
            change.entries.insert(entry.id)
            if entry.kind != .folder { moved.append(entry) }
        }
        commit(change)
        return moved
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

    /// Deletes a space with its pinned entries and Today tabs; every entry
    /// with a page goes to the Archive (reason `spaceDeleted`, B-15). The
    /// last space cannot be deleted. Returns what it removed, for
    /// `restoreSpace` (Undo).
    @discardableResult
    public func deleteSpace(_ id: UUID) throws(SidebarError) -> RemovedSpace {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { throw .unknownSpace(id) }
        guard spaces.count > 1 else { throw .lastSpace }
        let removed = RemovedSpace(space: spaces[index], index: index, entries: entries.values.filter { $0.spaceID == id },
                                   splitGroups: [], routingRules: routingRules.filter { $0.targetSpaceID == id })
        let groupsBefore = splitGroups
        var change = SidebarChange()
        let now = clock()
        for entry in entries.values where entry.spaceID == id {
            addArchiveRow(entry, reason: .spaceDeleted, at: now, change: &change)
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
        normalizeSplitGroups(into: &change)
        if !removed.routingRules.isEmpty {
            routingRules.removeAll { $0.targetSpaceID == id }
            renumberRoutingRules()
            change.routingRules = true
        }
        spaces.removeAll { $0.id == id }
        for i in spaces.indices { spaces[i].position = i }
        change.removedSpaces = [id]
        change.spaces = Set(spaces.map(\.id))
        commit(change)
        var result = removed
        result.splitGroups = groupsBefore.values.filter { splitGroups[$0.id] == nil }
        return result
    }

    /// Undo of `deleteSpace`: the space back at its place with its entries
    /// in their containers and order (split groups it ended come back too).
    /// Nothing happens if a space with its id exists again.
    public func restoreSpace(_ removed: RemovedSpace) {
        guard space(removed.space.id) == nil else { return }
        var restored = removed.space
        if !profiles.contains(where: { $0.id == restored.profileID }), let first = profiles.first { restored.profileID = first.id }
        spaces.insert(restored, at: min(max(removed.index, 0), spaces.count))
        for i in spaces.indices { spaces[i].position = i }
        for group in removed.splitGroups where splitGroups[group.id] == nil { splitGroups[group.id] = group }
        var change = SidebarChange(spaces: Set(spaces.map(\.id)))
        for var entry in removed.entries.sorted(by: { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }) {
            entry.profileID = restored.profileID
            if let group = entry.splitGroupID, splitGroups[group] == nil { entry.splitGroupID = nil }
            entries[entry.id] = entry
            containers[entry.container, default: []].append(entry.id)
            change.entries.insert(entry.id)
            change.containers.insert(entry.container)
        }
        for container in change.containers { renumber(container, change: &change) }
        for entry in removed.entries where archive.removeValue(forKey: entry.id) != nil { change.archive = true }
        // The space's rules back at their places (their positions as they were before the deletion).
        for rule in removed.routingRules.sorted(by: { $0.position < $1.position })
        where !routingRules.contains(where: { $0.id == rule.id }) {
            routingRules.insert(rule, at: min(max(rule.position, 0), routingRules.count))
            change.routingRules = true
        }
        renumberRoutingRules()
        normalizeSplitGroups(into: &change)
        commit(change)
    }

    // MARK: Import (Phase 4.3a)

    /// Writes an import (`ImportBatch`, planned off the main thread by
    /// `Import.ImportPlanner`) as one change, so the writer commits it in one
    /// transaction: new profiles (names made unique, as New Profile… does;
    /// none is renamed or deleted, B-22), new spaces at the end, pinned
    /// trees appended to each space's pinned root, Today tabs appended to its
    /// Today list, essentials appended to each profile's grid. Every
    /// reference is checked before anything changes. What no longer fits
    /// when the batch lands is not forced: essentials past the cap are
    /// refused and folders deeper than `FolderRules.maxDepth` give their
    /// links to the deepest allowed folder (both counted).
    @discardableResult
    public func applyImport(_ batch: ImportBatch) throws(SidebarError) -> ImportApplied {
        func check(_ ref: ImportBatch.ProfileRef) throws(SidebarError) {
            switch ref {
            case .existing(let id): guard profiles.contains(where: { $0.id == id }) else { throw .unknownProfile(id) }
            case .new(let index): guard batch.newProfiles.indices.contains(index) else { throw .invalidImport }
            }
        }
        for space in batch.newSpaces { try check(space.profile) }
        for essentials in batch.essentials { try check(essentials.profile) }
        for items in batch.spaces {
            switch items.space {
            case .existing(let id): guard space(id) != nil else { throw .unknownSpace(id) }
            case .new(let index): guard batch.newSpaces.indices.contains(index) else { throw .invalidImport }
            }
        }
        guard !batch.isEmpty else { return ImportApplied() }

        var applied = ImportApplied()
        var change = SidebarChange()
        let now = clock()
        var newProfileIDs: [UUID] = []
        for name in batch.newProfiles {
            let profile = Profile(name: SpaceRules.uniqueName(name, existing: profiles.map(\.name)), position: profiles.count)
            profiles.append(profile)
            newProfileIDs.append(profile.id)
            change.spaces.insert(profile.id)
        }
        applied.profiles = newProfileIDs
        func profileID(_ ref: ImportBatch.ProfileRef) -> UUID {
            switch ref {
            case .existing(let id): id
            case .new(let index): newProfileIDs[index]
            }
        }
        var newSpaceIDs: [UUID] = []
        for item in batch.newSpaces {
            let space = Space(name: item.name, icon: item.icon, themeColors: Array(item.themeColors.prefix(ThemePalette.maxColors)),
                              profileID: profileID(item.profile), position: spaces.count)
            spaces.append(space)
            newSpaceIDs.append(space.id)
        }
        applied.spaces = newSpaceIDs
        if !newSpaceIDs.isEmpty { change.spaces.formUnion(spaces.map(\.id)) }

        for items in batch.spaces {
            let spaceID: UUID = switch items.space {
            case .existing(let id): id
            case .new(let index): newSpaceIDs[index]
            }
            guard let space = space(spaceID) else { continue }
            func add(_ nodes: [ImportBatch.Node], folder: UUID?, depth: Int) {
                for node in nodes {
                    switch node {
                    case .link(let link):
                        let entry = Entry(kind: .pinned, spaceID: spaceID, profileID: space.profileID, folderID: folder,
                                          storedURL: link.url, storedTitle: link.title, createdAt: now)
                        appendImported(entry, change: &change)
                        applied.pinned += 1
                    case .folder(let name, let children):
                        guard depth < FolderRules.maxDepth else {
                            applied.foldersFlattened += 1
                            add(children, folder: folder, depth: depth)
                            continue
                        }
                        let entry = Entry(kind: .folder, spaceID: spaceID, profileID: space.profileID, folderID: folder,
                                          customLabel: name, createdAt: now)
                        appendImported(entry, change: &change)
                        applied.folders += 1
                        add(children, folder: entry.id, depth: depth + 1)
                    }
                }
            }
            add(items.pinned, folder: nil, depth: 0)
            for link in items.today {
                let entry = Entry(kind: .today, spaceID: spaceID, profileID: space.profileID, createdAt: now,
                                  liveURL: link.url, liveTitle: link.title)
                appendImported(entry, change: &change)
                applied.today += 1
            }
        }
        for item in batch.essentials {
            let profile = profileID(item.profile)
            var count = essentials(profile: profile).count
            for link in item.links {
                guard EntryRules.canAddEssential(currentCount: count) else {
                    applied.essentialsRefused += 1
                    continue
                }
                let entry = Entry(kind: .essential, spaceID: nil, profileID: profile, storedURL: link.url, storedTitle: link.title,
                                  createdAt: now)
                appendImported(entry, change: &change)
                applied.essentials += 1
                count += 1
            }
        }
        commit(change)
        return applied
    }

    /// `insert` at the end without renumbering the container (its positions
    /// are contiguous): an import of thousands of bookmarks into one folder
    /// stays linear.
    private func appendImported(_ entry: Entry, change: inout SidebarChange) {
        var entry = entry
        let container = entry.container
        entry.position = containers[container]?.count ?? 0
        containers[container, default: []].append(entry.id)
        entries[entry.id] = entry
        change.entries.insert(entry.id)
        change.containers.insert(container)
    }

    // MARK: Routing rules (schema v8, spec §B)

    /// A new rule at `index` (default: the end). The pattern is checked
    /// first: an invalid regex or an empty pattern is refused and nothing is
    /// saved; the target must be a space.
    @discardableResult
    public func addRoutingRule(_ match: RoutingMatch, pattern: String, target: UUID, enabled: Bool = true,
                               at index: Int? = nil) throws(SidebarError) -> RoutingRule {
        if let error = RoutingRules.validate(match, pattern: pattern) { throw .routingPattern(error) }
        guard space(target) != nil else { throw .unknownSpace(target) }
        let rule = RoutingRule(match: match, pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                               targetSpaceID: target, enabled: enabled)
        routingRules.insert(rule, at: min(max(index ?? routingRules.count, 0), routingRules.count))
        renumberRoutingRules()
        commit(SidebarChange(routingRules: true))
        return routingRules.first { $0.id == rule.id }!
    }

    /// Edits a rule's match kind, pattern, target or enabled flag (not its id
    /// or position); the pattern is checked as in `addRoutingRule`.
    public func updateRoutingRule(_ id: UUID, _ body: (inout RoutingRule) -> Void) throws(SidebarError) {
        guard let index = routingRules.firstIndex(where: { $0.id == id }) else { throw .unknownRoutingRule(id) }
        var rule = routingRules[index]
        body(&rule)
        rule.id = id
        rule.position = routingRules[index].position
        rule.pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = RoutingRules.validate(rule.match, pattern: rule.pattern) { throw .routingPattern(error) }
        guard space(rule.targetSpaceID) != nil else { throw .unknownSpace(rule.targetSpaceID) }
        guard rule != routingRules[index] else { return }
        routingRules[index] = rule
        commit(SidebarChange(routingRules: true))
    }

    public func removeRoutingRule(_ id: UUID) {
        guard let index = routingRules.firstIndex(where: { $0.id == id }) else { return }
        routingRules.remove(at: index)
        renumberRoutingRules()
        commit(SidebarChange(routingRules: true))
    }

    /// Reorders: the rule moves to `index` in the list (earlier wins).
    public func moveRoutingRule(_ id: UUID, to index: Int) throws(SidebarError) {
        guard let from = routingRules.firstIndex(where: { $0.id == id }) else { throw .unknownRoutingRule(id) }
        let before = routingRules.map(\.id)
        let rule = routingRules.remove(at: from)
        routingRules.insert(rule, at: min(max(index, 0), routingRules.count))
        renumberRoutingRules()
        guard routingRules.map(\.id) != before else { return }
        commit(SidebarChange(routingRules: true))
    }

    private func renumberRoutingRules() {
        for i in routingRules.indices where routingRules[i].position != i { routingRules[i].position = i }
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
    /// `index` counts the container without the moved entry.
    public func move(_ id: UUID, to container: Container, at index: Int) throws(SidebarError) {
        guard let entry = entries[id] else { throw .unknownEntry(id) }
        let space = try targetSpace(for: container, moving: entry)
        try validateFolderTarget(container, moving: [id])
        let essentialsCount = essentials(profile: space.profileID).filter { $0.id != id }.count
        let converted = try convert(entry, to: container, in: space, essentialsCount: essentialsCount)

        var change = SidebarChange()
        detach(id, change: &change)
        insert(converted, at: index, change: &change)
        if converted.kind == .folder, converted.spaceID != entry.spaceID || converted.profileID != entry.profileID {
            reassignSubtree(of: id, to: space, change: &change)
        }
        normalizeSplitGroups(into: &change)
        commit(change)
    }

    /// Drag and drop (§A.9): moves `ids`, in this order, to `container`,
    /// together at `index`, which counts the container as it is now, moved
    /// entries included (the drop position the user sees). Kinds convert by
    /// section; the Essentials cap counts every entry that would become an
    /// essential; if any entry is refused nothing changes. An entry whose
    /// folder is moved too stays inside it. One change for the whole move.
    public func move(_ ids: [UUID], to container: Container, insertingAt index: Int) throws(SidebarError) {
        let moving = try topLevel(ids)
        guard let first = moving.first else { return }
        let space = try targetSpace(for: container, moving: first)
        try validateFolderTarget(container, moving: moving.map(\.id))
        let movingIDs = Set(moving.map(\.id))
        var essentialsCount = essentials(profile: space.profileID).filter { !movingIDs.contains($0.id) }.count
        var converted: [Entry] = []
        for entry in moving {
            converted.append(try convert(entry, to: container, in: space, essentialsCount: essentialsCount))
            if container.section == .essentials { essentialsCount += 1 }
        }
        let current = containers[container] ?? []
        let clamped = min(max(index, 0), current.count)
        let target = clamped - current.prefix(clamped).filter(movingIDs.contains).count

        var change = SidebarChange()
        for entry in moving { detach(entry.id, change: &change) }
        for (offset, entry) in converted.enumerated() {
            insert(entry, at: target + offset, change: &change)
            let original = moving[offset]
            if entry.kind == .folder, entry.spaceID != original.spaceID || entry.profileID != original.profileID {
                reassignSubtree(of: entry.id, to: space, change: &change)
            }
        }
        normalizeSplitGroups(into: &change)
        commit(change)
    }

    /// ⌥-drag (§A.9): copies of `ids` inserted together at `index` in
    /// `container` (counting it as it is now), converted to its section.
    /// Folders are not copied. The copies have no page yet and no MRU
    /// history; a Today copy carries the original's page URL. Returns them.
    @discardableResult
    public func duplicate(_ ids: [UUID], to container: Container, at index: Int) throws(SidebarError) -> [Entry] {
        let originals = try ids.map { id throws(SidebarError) -> Entry in
            guard let entry = entries[id] else { throw .unknownEntry(id) }
            guard entry.kind != .folder else { throw .invalidKind }
            return entry
        }
        guard let first = originals.first else { return [] }
        let space = try targetSpace(for: container, moving: first)
        try validateFolderTarget(container, moving: [])
        var essentialsCount = essentials(profile: space.profileID).count
        var copies: [Entry] = []
        for original in originals {
            var copy = original
            copy.id = UUID()
            copy.createdAt = clock()
            copy.lastActiveAt = nil
            copy.splitGroupID = nil
            if original.kind.isPermanent { copy.liveURL = nil; copy.liveTitle = nil }
            copies.append(try convert(copy, to: container, in: space, essentialsCount: essentialsCount))
            if container.section == .essentials { essentialsCount += 1 }
        }
        var change = SidebarChange()
        for (offset, copy) in copies.enumerated() { insert(copy, at: index + offset, change: &change) }
        commit(change)
        return copies.compactMap { entries[$0.id] }
    }

    /// Whether `move(ids, to: container, …)` would succeed (drag validation).
    public func canMove(_ ids: [UUID], to container: Container) -> Result<Void, SidebarError> {
        do {
            let moving = try topLevel(ids)
            guard let first = moving.first else { return .success(()) }
            let space = try targetSpace(for: container, moving: first)
            try validateFolderTarget(container, moving: moving.map(\.id))
            let movingIDs = Set(moving.map(\.id))
            var essentialsCount = essentials(profile: space.profileID).filter { !movingIDs.contains($0.id) }.count
            for entry in moving {
                _ = try convert(entry, to: container, in: space, essentialsCount: essentialsCount)
                if container.section == .essentials { essentialsCount += 1 }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// The space whose section `container` is (for essentials: the moved
    /// entry's space if it shares the profile, else the profile's first space).
    private func targetSpace(for container: Container, moving entry: Entry) throws(SidebarError) -> Space {
        switch container {
        case .essentials(let profile):
            let current = entry.spaceID.flatMap { self.space($0) }
            guard let match = current?.profileID == profile ? current : spaces.first(where: { $0.profileID == profile }) else {
                throw .unknownProfile(profile)
            }
            return match
        case .pinned(let spaceID, _), .today(let spaceID):
            guard let match = self.space(spaceID) else { throw .unknownSpace(spaceID) }
            return match
        }
    }

    private func validateFolderTarget(_ container: Container, moving ids: [UUID]) throws(SidebarError) {
        guard case .pinned(let spaceID, let folder?) = container else { return }
        try validateFolder(folder, in: spaceID)
        for id in ids {
            do { try FolderRules.validatePlacement(of: id, into: folder, in: entries) } catch { throw .folder(error) }
        }
    }

    private func convert(_ entry: Entry, to container: Container, in space: Space, essentialsCount: Int) throws(SidebarError) -> Entry {
        var converted: Entry
        do { converted = try EntryRules.converted(entry, to: container.section, in: space, essentialsCount: essentialsCount) } catch {
            throw .conversion(error)
        }
        if case .pinned(_, let folder) = container { converted.folderID = folder }
        return converted
    }

    /// `ids` without duplicates and without entries inside a folder that is
    /// also listed (they move with it), in the given order.
    private func topLevel(_ ids: [UUID]) throws(SidebarError) -> [Entry] {
        var seen = Set<UUID>()
        var result: [Entry] = []
        let listed = Set(ids)
        for id in ids where seen.insert(id).inserted {
            guard let entry = entries[id] else { throw .unknownEntry(id) }
            var parent = entry.folderID
            var nested = false
            while let folder = parent {
                if listed.contains(folder) { nested = true; break }
                parent = entries[folder]?.folderID
            }
            if !nested { result.append(entry) }
        }
        return result
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
        normalizeSplitGroups(into: &change)
        commit(change)
        return RemovedEntry(entry: entry, index: index)
    }

    /// Clear (⇧⌘K): every Today tab of the space goes to the Archive (reason
    /// `clear`, spec §A.7); returns them for Undo (`restore`, which takes
    /// their rows back out).
    @discardableResult
    public func clearToday(space spaceID: UUID) -> [RemovedEntry] {
        let removed = today(space: spaceID).enumerated().map { RemovedEntry(entry: $0.element, index: $0.offset) }
        guard !removed.isEmpty else { return [] }
        var change = SidebarChange()
        containers[.today(space: spaceID)] = nil
        change.containers.insert(.today(space: spaceID))
        let now = clock()
        for item in removed {
            addArchiveRow(item.entry, reason: .clear, at: now, change: &change)
            entries[item.entry.id] = nil
            change.removedEntries.insert(item.entry.id)
        }
        normalizeSplitGroups(into: &change)
        commit(change)
        return removed
    }

    /// Undo of `remove`/`clearToday`/`archive`: puts entries back where they
    /// were (skipping any whose space or parent folder is gone); an entry
    /// that comes back leaves the Archive.
    public func restore(_ removed: [RemovedEntry]) {
        var change = SidebarChange()
        for item in removed.sorted(by: { $0.index < $1.index }) where entries[item.entry.id] == nil {
            var entry = item.entry
            if let spaceID = entry.spaceID, space(spaceID) == nil { continue }
            if archive.removeValue(forKey: entry.id) != nil { change.archive = true }
            if let folder = entry.folderID, entries[folder] == nil { entry.folderID = nil }
            if let group = entry.splitGroupID, splitGroups[group] == nil { entry.splitGroupID = nil }
            if entry.kind == .essential,
               !EntryRules.canAddEssential(currentCount: essentials(profile: entry.profileID).count) { continue }
            insert(entry, at: item.index, change: &change)
            // Back into the split it left, at the end, if the split is still there and has room.
            if let group = entry.splitGroupID, var split = splitGroups[group], !split.members.contains(entry.id) {
                if SplitRules.canAdd(toCount: split.members.count) {
                    split.members.append(entry.id)
                    split.ratios = SplitRules.equalRatios(layout: split.layout, count: split.members.count)
                    splitGroups[group] = split
                    touchSplit(split, &change)
                } else {
                    entries[entry.id]?.splitGroupID = nil
                }
            }
        }
        commit(change)
    }

    // MARK: Archive (schema v7, spec §A.7 and §H)

    /// Archives entries: each leaves the sidebar and, when it has a page to
    /// come back to, becomes a row of the Archive with `reason` (the sweep's
    /// `auto`, "Archive" and "Archive Below"'s `manual`). Folders are
    /// skipped. Returns what was removed and where, for Undo (`restore`).
    @discardableResult
    public func archive(_ ids: [UUID], reason: ArchiveReason) -> [RemovedEntry] {
        let now = clock()
        var change = SidebarChange()
        var removed: [RemovedEntry] = []
        // Positions before anything moves, so `restore` puts them back in order.
        let targets = ids.compactMap { entries[$0] }.filter { $0.kind != .folder }
        var seen = Set<UUID>()
        let indexed = targets.filter { seen.insert($0.id).inserted }
            .map { RemovedEntry(entry: $0, index: containers[$0.container]?.firstIndex(of: $0.id) ?? 0) }
        for item in indexed {
            detach(item.entry.id, change: &change)
            addArchiveRow(item.entry, reason: reason, at: now, change: &change)
            entries[item.entry.id] = nil
            change.removedEntries.insert(item.entry.id)
            change.entries.remove(item.entry.id)
            removed.append(item)
        }
        guard !removed.isEmpty else { return [] }
        normalizeSplitGroups(into: &change)
        commit(change)
        return removed
    }

    /// Restore from the Archive (spec §H): the row becomes a Today tab at
    /// the top of its space, or of `activeSpace` when its space is gone (then
    /// in that space's profile); the row is deleted. The tab counts as used
    /// now, so the next sweep does not take it again. Returns the new entry.
    @discardableResult
    public func restore(archived id: UUID, activeSpace: UUID?) throws(SidebarError) -> Entry {
        guard let row = archive[id] else { throw .unknownEntry(id) }
        let target = row.spaceID.flatMap { self.space($0) } ?? activeSpace.flatMap { self.space($0) } ?? spaces.first
        guard let target else { throw .unknownSpace(row.spaceID ?? id) }
        let now = clock()
        let entry = Entry(id: entries[row.id] == nil ? row.id : UUID(), kind: .today, spaceID: target.id,
                          profileID: target.profileID, faviconID: row.faviconID, createdAt: now, lastActiveAt: now,
                          liveURL: row.url, liveTitle: row.title, navigationState: row.navigationState)
        var change = SidebarChange()
        archive[id] = nil
        change.archive = true
        insert(entry, at: 0, change: &change)
        commit(change)
        return entries[entry.id]!
    }

    /// The × of a Library row: rows leave the Archive for good.
    public func deleteArchived(_ ids: [UUID]) {
        var change = SidebarChange()
        for id in ids where archive.removeValue(forKey: id) != nil { change.archive = true }
        commit(change)
    }

    /// "Clear Archive" (after its confirmation).
    public func clearArchive() {
        guard !archive.isEmpty else { return }
        archive = [:]
        commit(SidebarChange(archive: true))
    }

    /// The Archive's retention at the sweep (B-80, `ArchiveRetention`): old
    /// rows go, rows past the shorter span lose their navigation state.
    /// Returns what it did.
    @discardableResult
    public func applyArchiveRetention(now: Timestamp, rows: TimeInterval, navigationState: TimeInterval) -> ArchiveRetention.Plan {
        let plan = ArchiveRetention.plan(archive.values, now: now, rows: rows, navigationState: navigationState)
        guard !plan.isEmpty else { return plan }
        for id in plan.prune { archive[id] = nil }
        for id in plan.dropNavigationState { archive[id]?.navigationState = nil }
        commit(SidebarChange(archive: true))
        return plan
    }

    private func addArchiveRow(_ entry: Entry, reason: ArchiveReason, at time: Timestamp, change: inout SidebarChange) {
        guard let row = ArchivedEntry(entry, reason: reason, at: time) else { return }
        archive[row.id] = row
        change.archive = true
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

    /// The engine's serialised back/forward list of the entry's page
    /// (`WebContents.navigationState`, Phase 3.7b). Written with the next
    /// state write (the debounced single transaction, 2.1); no observer hears
    /// it: nothing on screen shows it, and it changes with every commit and
    /// scroll-state update of a page.
    public func setNavigationState(_ id: UUID, _ state: Data?) throws(SidebarError) {
        guard var entry = entries[id] else { throw .unknownEntry(id) }
        guard entry.navigationState != state else { return }
        entry.navigationState = state
        entries[id] = entry
        persistence?.scheduleWrite()
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

    // MARK: Split groups (spec §D)

    /// The split `id` is a pane of.
    public func splitGroup(of id: UUID) -> SplitGroup? { entries[id]?.splitGroupID.flatMap { splitGroups[$0] } }

    /// A split's panes in order.
    public func splitMembers(_ group: UUID) -> [Entry] { splitGroups[group]?.members.compactMap { entries[$0] } ?? [] }

    /// A split of `members` (2…4, in pane order); members leave any split
    /// they were in. Only pinned entries and Today tabs are panes (an
    /// essential joins as a copy, spec §D / Zen).
    @discardableResult
    public func createSplitGroup(_ members: [UUID], layout: SplitLayout = .hbox) throws(SidebarError) -> SplitGroup {
        var ids: [UUID] = []
        for id in members where !ids.contains(id) { ids.append(id) }
        guard ids.count >= 2, ids.count <= SplitRules.maxPanes else { throw .splitFull }
        try validatePanes(ids)
        var change = SidebarChange()
        for id in ids { leaveSplit(id, change: &change) }
        let group = SplitGroup(layout: layout, ratios: SplitRules.equalRatios(layout: layout, count: ids.count), members: ids)
        splitGroups[group.id] = group
        for id in ids { entries[id]?.splitGroupID = group.id }
        touchSplit(group, &change)
        commit(change)
        return group
    }

    /// `id` becomes pane `index` (clamped) of `group`, leaving any other split; sizes become equal.
    public func addToSplitGroup(_ id: UUID, group groupID: UUID, at index: Int? = nil) throws(SidebarError) {
        guard var group = splitGroups[groupID] else { throw .unknownSplitGroup(groupID) }
        guard !group.members.contains(id) else { return }
        guard SplitRules.canAdd(toCount: group.members.count) else { throw .splitFull }
        try validatePanes([id])
        var change = SidebarChange()
        leaveSplit(id, change: &change)
        group = splitGroups[groupID] ?? group
        group.members.insert(id, at: min(max(index ?? group.members.count, 0), group.members.count))
        group.ratios = SplitRules.equalRatios(layout: group.layout, count: group.members.count)
        splitGroups[groupID] = group
        entries[id]?.splitGroupID = groupID
        touchSplit(group, &change)
        commit(change)
    }

    /// `id` leaves its split (it stays in the sidebar); a split left with one pane dissolves.
    public func removeFromSplitGroup(_ id: UUID) {
        var change = SidebarChange()
        leaveSplit(id, change: &change)
        commit(change)
    }

    /// Unsplit (⌥⌘U, "Separate All Tabs"): every pane becomes a normal entry again.
    public func dissolveSplitGroup(_ groupID: UUID) {
        guard let group = splitGroups.removeValue(forKey: groupID) else { return }
        var change = SidebarChange()
        for id in group.members where entries[id]?.splitGroupID == groupID { entries[id]?.splitGroupID = nil }
        touchSplit(group, &change)
        commit(change)
    }

    /// ⌥⌘G / ⌥⌘V / ⌥⌘H: a new layout starts with equal sizes.
    public func setSplitLayout(_ groupID: UUID, _ layout: SplitLayout) throws(SidebarError) {
        guard var group = splitGroups[groupID] else { throw .unknownSplitGroup(groupID) }
        guard group.layout != layout else { return }
        group.layout = layout
        group.ratios = SplitRules.equalRatios(layout: layout, count: group.members.count)
        splitGroups[groupID] = group
        var change = SidebarChange()
        touchSplit(group, &change, containers: false)
        commit(change)
    }

    /// A resizer drag ended (or a double-click equalised): sizes that do not fit the layout become equal.
    public func setSplitRatios(_ groupID: UUID, _ ratios: [Double]) throws(SidebarError) {
        guard var group = splitGroups[groupID] else { throw .unknownSplitGroup(groupID) }
        let normalized = SplitRules.normalizedRatios(ratios, layout: group.layout, count: group.members.count)
        guard normalized != group.ratios else { return }
        group.ratios = normalized
        splitGroups[groupID] = group
        var change = SidebarChange()
        touchSplit(group, &change, containers: false)
        commit(change)
    }

    /// The pane header's grip: pane `from` moves to `to`.
    public func moveSplitMember(_ groupID: UUID, from: Int, to: Int) throws(SidebarError) {
        guard var group = splitGroups[groupID] else { throw .unknownSplitGroup(groupID) }
        guard group.members.indices.contains(from), group.members.indices.contains(to), from != to else { return }
        group.ratios = SplitRules.ratiosAfterMove(group.ratios, layout: group.layout, from: from, to: to)
        group.members.insert(group.members.remove(at: from), at: to)
        splitGroups[groupID] = group
        var change = SidebarChange()
        touchSplit(group, &change)
        commit(change)
    }

    /// A drop in a pane's centre: `id` takes `pane`'s place, `pane` leaves the split.
    public func replaceSplitMember(_ pane: UUID, with id: UUID) throws(SidebarError) {
        guard let groupID = entries[pane]?.splitGroupID, var group = splitGroups[groupID],
              let index = group.members.firstIndex(of: pane) else { throw .unknownEntry(pane) }
        guard pane != id, !group.members.contains(id) else { return }
        try validatePanes([id])
        var change = SidebarChange()
        leaveSplit(id, change: &change)
        group = splitGroups[groupID] ?? group
        group.members[index] = id
        splitGroups[groupID] = group
        entries[pane]?.splitGroupID = nil
        entries[id]?.splitGroupID = groupID
        touch(pane, &change)
        touchSplit(group, &change)
        commit(change)
    }

    private func validatePanes(_ ids: [UUID]) throws(SidebarError) {
        for id in ids {
            guard let entry = entries[id] else { throw .unknownEntry(id) }
            guard entry.kind == .pinned || entry.kind == .today else { throw .invalidKind }
        }
    }

    private func leaveSplit(_ id: UUID, change: inout SidebarChange) {
        guard let groupID = entries[id]?.splitGroupID else { return }
        entries[id]?.splitGroupID = nil
        touch(id, &change)
        guard var group = splitGroups[groupID] else { return }
        group.members.removeAll { $0 == id }
        group.ratios = SplitRules.equalRatios(layout: group.layout, count: group.members.count)
        splitGroups[groupID] = group
        normalizeSplitGroups(into: &change)
        if let kept = splitGroups[groupID] { touchSplit(kept, &change) }
    }

    /// Every member and (unless `containers` is false) the lists they sit in:
    /// the group row stands for hidden members, so those lists are read again.
    private func touchSplit(_ group: SplitGroup, _ change: inout SidebarChange, containers: Bool = true) {
        for id in group.members {
            change.entries.insert(id)
            if containers, let entry = entries[id] { change.containers.insert(entry.container) }
        }
    }

    private func touch(_ id: UUID, _ change: inout SidebarChange) {
        change.entries.insert(id)
        if let entry = entries[id] { change.containers.insert(entry.container) }
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

    /// Splits hold only entries that still point at them and can be panes
    /// (an entry that became an essential, or was removed, leaves); a split
    /// under two panes dissolves and its survivor becomes a normal entry.
    private func normalizeSplitGroups(into change: inout SidebarChange) {
        for (groupID, var group) in splitGroups {
            let kept = group.members.filter { id in
                guard let entry = entries[id], entry.splitGroupID == groupID else { return false }
                return entry.kind == .pinned || entry.kind == .today
            }
            // Members recorded only on the entry side (older state) join at the end.
            let strays = entries.values.filter { $0.splitGroupID == groupID && !kept.contains($0.id) && ($0.kind == .pinned || $0.kind == .today) }
                .sorted { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }.map(\.id)
            let members = Array((kept + strays).prefix(SplitRules.maxPanes))
            if members.count < 2 {
                splitGroups[groupID] = nil
                for entry in entries.values where entry.splitGroupID == groupID {
                    entries[entry.id]?.splitGroupID = nil
                    touch(entry.id, &change)
                }
                continue
            }
            for entry in entries.values where entry.splitGroupID == groupID && !members.contains(entry.id) {
                entries[entry.id]?.splitGroupID = nil
                touch(entry.id, &change)
            }
            guard members != group.members else { continue }
            group.members = members
            group.ratios = SplitRules.normalizedRatios(group.ratios, layout: group.layout, count: members.count)
            if group.layout != .grid, group.ratios.count != members.count {
                group.ratios = SplitRules.equalRatios(layout: group.layout, count: members.count)
            }
            splitGroups[groupID] = group
            touchSplit(group, &change)
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

// MARK: - Archive queries (the Library and the palette)

extension SidebarStore {
    /// Archived rows matching `text` (every word, in the title or URL), newest first.
    public func archivedEntries(matching text: String = "") -> [ArchivedEntry] {
        ArchiveSearch.matching(archive.values, text: text)
    }

    /// Archived rows matching `text`, grouped by the day they were archived, newest first.
    public func archivedByDay(matching text: String = "", calendar: Calendar = .current) -> [(day: Date, rows: [ArchivedEntry])] {
        ArchiveSearch.byDay(archivedEntries(matching: text), calendar: calendar)
    }

    public var archivedCount: Int { archive.count }

    /// Rows per reason (the tour's counts).
    public func archivedCount(reason: ArchiveReason) -> Int { archive.values.count { $0.reason == reason } }
}
