import Engine
import Foundation
import Model

/// What the sheet's options ask for (Phase 4.3a).
public struct ImportOptions: Hashable, Sendable {
    public enum Layout: String, Hashable, Sendable, CaseIterable {
        /// Every bookmark in the target space's pinned list: the bar, then "other", then mobile.
        case oneSpace
        /// One new space per top-level folder; loose bookmarks go to the target space.
        case spacePerFolder
    }

    public enum TargetSpace: Hashable, Sendable {
        case existing(UUID)
        /// A space made for the import (the sheet offers "New space named {source}").
        case new(name: String)
    }

    public var bookmarks = true
    public var history = true
    /// Arc's spaces, essentials, pinned entries and Today tabs.
    public var sidebar = true
    public var layout: Layout = .oneSpace
    /// The bar's top-level links become essentials of the target profile, up to the cap.
    public var barIntoEssentials = false
    public var targetSpace: TargetSpace
    /// The profile of a new target space, of the spaces made per folder and
    /// of the imported history; an existing target space keeps its own.
    public var targetProfile: UUID

    public init(targetSpace: TargetSpace, targetProfile: UUID) {
        self.targetSpace = targetSpace
        self.targetProfile = targetProfile
    }
}

/// What the store holds, as far as the planner needs it (a value made on
/// the main actor from `RoomState`, read off it).
public struct ImportTarget: Hashable, Sendable {
    public var profiles: [Model.Profile]
    public var spaces: [Space]
    /// Normalised URLs (`ImportURL.normalized`) of each space's pinned entries and Today tabs.
    public var spaceURLs: [UUID: Set<String>]
    /// Normalised URLs of each profile's essentials.
    public var essentialURLs: [UUID: Set<String>]
    public var essentialsCount: [UUID: Int]

    public init(state: RoomState) {
        profiles = state.profiles.sorted { $0.position < $1.position }
        spaces = state.spaces.sorted { $0.position < $1.position }
        var spaceURLs: [UUID: Set<String>] = [:]
        var essentialURLs: [UUID: Set<String>] = [:]
        var essentialsCount: [UUID: Int] = [:]
        for entry in state.entries {
            let url = entry.kind == .today ? entry.liveURL : (entry.storedURL ?? entry.liveURL)
            switch entry.kind {
            case .essential:
                essentialsCount[entry.profileID, default: 0] += 1
                if let url { essentialURLs[entry.profileID, default: []].insert(ImportURL.normalized(url)) }
            case .pinned, .today:
                if let url, let space = entry.spaceID { spaceURLs[space, default: []].insert(ImportURL.normalized(url)) }
            case .folder:
                break
            }
        }
        self.spaceURLs = spaceURLs
        self.essentialURLs = essentialURLs
        self.essentialsCount = essentialsCount
    }

    /// Room's default profile: the first one ("Default" on a fresh state).
    public var defaultProfileID: UUID? { profiles.first?.id }
}

/// The preview: what the import will write, counted (the sheet shows it
/// before the button; the tour compares it with the store after).
public struct ImportPreview: Hashable, Sendable {
    public var newProfiles = 0
    public var spaces = 0
    public var folders = 0
    public var pinned = 0
    public var essentials = 0
    public var today = 0
    public var historyURLs = 0
    public var historyVisits = 0
    /// Links skipped because their normalised URL is already in the target
    /// space (or its profile's essentials), or earlier in the same import.
    public var duplicates = 0
    /// Folders deeper than `FolderRules.maxDepth`, whose links went into their depth-5 ancestor.
    public var foldersFlattened = 0
    /// Bar links (or Arc essentials) past the Essentials cap, pinned instead.
    public var essentialsOverflow = 0
    /// Everything left out with a reason (the readers' and the planner's).
    public var skipped: [SkippedItem] = []

    public init() {}

    public var isEmpty: Bool { spaces + folders + pinned + essentials + today + historyURLs == 0 }
}

/// An import ready to apply: the sidebar's part (one `SidebarStore.applyImport`),
/// the history's batches for `ProfileHistory.importEntries` and the preview.
public struct ImportPlan: Sendable {
    public var batch: ImportBatch
    /// `historyBatchSize` URLs per batch.
    public var history: [[HistoryImportEntry]]
    /// The profile the history goes to.
    public var historyProfile: UUID?
    public var preview: ImportPreview
}

/// Maps the readers' values into Room's model (ROADMAP 4.3a task 2), as a
/// pure function: bookmarks into a space's pinned list (or a space per
/// top-level folder), the bar optionally into Essentials up to the cap,
/// Arc's sidebar into spaces with their profiles, essentials, pinned
/// entries and Today tabs, history into engine batches; duplicates by
/// normalised URL skipped and counted; folders clipped at depth 5.
public enum ImportPlanner {
    /// URLs per `importEntries` call (the 3.5 migration's batch, `HistoryMigration.batchSize`).
    public static let historyBatchSize = 2_000
    public static let untitledFolder = "Untitled Folder"

    public static func plan(_ scan: ImportScan, options: ImportOptions, target: ImportTarget) -> ImportPlan {
        var builder = Builder(target: target, options: options, sourceName: scan.source.kind == .bookmarksFile ? "Bookmarks"
                                                                                                               : scan.source.kind.displayName)
        if options.sidebar, let sidebar = scan.sidebar?.value {
            builder.preview.skipped += sidebar.skipped
            builder.addSidebar(sidebar)
        }
        if options.bookmarks, let bookmarks = scan.bookmarks?.value {
            builder.preview.skipped += bookmarks.skipped
            builder.addBookmarks(bookmarks)
        }
        var history: [[HistoryImportEntry]] = []
        if options.history, let imported = scan.history?.value {
            builder.preview.skipped += imported.skipped
            history = builder.historyBatches(imported)
        }
        let historyProfile: UUID = if case .existing(let id) = options.targetSpace, let space = target.spaces.first(where: { $0.id == id }) {
            space.profileID
        } else {
            options.targetProfile
        }
        return ImportPlan(batch: builder.batch, history: history, historyProfile: history.isEmpty ? nil : historyProfile,
                          preview: builder.preview)
    }

    struct Builder {
        let target: ImportTarget
        let options: ImportOptions
        let sourceName: String
        var batch = ImportBatch()
        var preview = ImportPreview()
        var spaceSeen: [ImportBatch.SpaceRef: Set<String>] = [:]
        var profileSeen: [ImportBatch.ProfileRef: Set<String>] = [:]
        var essentialsCount: [ImportBatch.ProfileRef: Int] = [:]
        var spaceProfile: [ImportBatch.SpaceRef: ImportBatch.ProfileRef] = [:]
        /// The import's items per space, in the order the spaces were first used.
        var items: [ImportBatch.SpaceRef: ImportBatch.SpaceItems] = [:]
        var itemOrder: [ImportBatch.SpaceRef] = []
        var essentials: [ImportBatch.ProfileRef: [ImportBatch.Link]] = [:]
        var essentialsOrder: [ImportBatch.ProfileRef] = []

        init(target: ImportTarget, options: ImportOptions, sourceName: String) {
            self.target = target
            self.options = options
            self.sourceName = sourceName
        }

        // MARK: Spaces and profiles

        mutating func profileRef(_ id: UUID) -> ImportBatch.ProfileRef {
            let ref = ImportBatch.ProfileRef.existing(id)
            if profileSeen[ref] == nil {
                profileSeen[ref] = target.essentialURLs[id] ?? []
                essentialsCount[ref] = target.essentialsCount[id] ?? 0
            }
            return ref
        }

        mutating func newProfile(_ name: String) -> ImportBatch.ProfileRef {
            batch.newProfiles.append(name)
            preview.newProfiles += 1
            let ref = ImportBatch.ProfileRef.new(batch.newProfiles.count - 1)
            profileSeen[ref] = []
            essentialsCount[ref] = 0
            return ref
        }

        mutating func existingSpace(_ id: UUID) -> ImportBatch.SpaceRef? {
            guard let space = target.spaces.first(where: { $0.id == id }) else { return nil }
            let ref = ImportBatch.SpaceRef.existing(id)
            if spaceProfile[ref] == nil {
                spaceProfile[ref] = profileRef(space.profileID)
                spaceSeen[ref] = target.spaceURLs[id] ?? []
            }
            return ref
        }

        mutating func newSpace(_ name: String, icon: String? = nil, colors: [String] = [], profile: ImportBatch.ProfileRef) -> ImportBatch.SpaceRef {
            batch.newSpaces.append(ImportBatch.NewSpace(name: name, icon: icon, themeColors: colors, profile: profile))
            preview.spaces += 1
            let ref = ImportBatch.SpaceRef.new(batch.newSpaces.count - 1)
            spaceProfile[ref] = profile
            spaceSeen[ref] = []
            return ref
        }

        /// The options' target space, made when first needed.
        var targetSpaceRef: ImportBatch.SpaceRef?
        mutating func targetSpace() -> ImportBatch.SpaceRef {
            if let targetSpaceRef { return targetSpaceRef }
            let ref: ImportBatch.SpaceRef
            switch options.targetSpace {
            case .existing(let id):
                ref = existingSpace(id) ?? newSpace(sourceName, profile: profileRef(options.targetProfile))
            case .new(let name):
                ref = newSpace(name.isEmpty ? sourceName : name, profile: profileRef(options.targetProfile))
            }
            targetSpaceRef = ref
            return ref
        }

        /// The profile spaces made per folder use: the target space's.
        mutating func targetProfile() -> ImportBatch.ProfileRef {
            if case .existing(let id) = options.targetSpace, let space = target.spaces.first(where: { $0.id == id }) {
                return profileRef(space.profileID)
            }
            return profileRef(options.targetProfile)
        }

        // MARK: Admission

        /// `link` as an entry of `space` (or, for an essential, of `profile`),
        /// or `nil` when its scheme cannot be opened or its URL is a duplicate.
        mutating func admit(_ link: ImportedLink, space: ImportBatch.SpaceRef?, essentialOf profile: ImportBatch.ProfileRef? = nil) -> ImportBatch.Link? {
            if let scheme = ImportURL.refusedScheme(link.url) {
                preview.skipped.append(SkippedItem(link.title.isEmpty ? link.url : link.title, reason: "a \(scheme): link"))
                return nil
            }
            let key = ImportURL.normalized(link.url)
            let spaceProfile = space.flatMap { self.spaceProfile[$0] }
            let seen = (space.flatMap { spaceSeen[$0]?.contains(key) } ?? false)
                || ((profile ?? spaceProfile).flatMap { profileSeen[$0]?.contains(key) } ?? false)
            if seen {
                preview.duplicates += 1
                return nil
            }
            if let profile { profileSeen[profile, default: []].insert(key) } else if let space { spaceSeen[space, default: []].insert(key) }
            return ImportBatch.Link(url: link.url.trimmingCharacters(in: .whitespacesAndNewlines), title: link.title.isEmpty ? nil : link.title)
        }

        func isDuplicate(_ link: ImportedLink, space: ImportBatch.SpaceRef?, profile: ImportBatch.ProfileRef?) -> Bool {
            let key = ImportURL.normalized(link.url)
            return (space.flatMap { spaceSeen[$0]?.contains(key) } ?? false) || (profile.flatMap { profileSeen[$0]?.contains(key) } ?? false)
        }

        mutating func items(_ space: ImportBatch.SpaceRef, _ body: (inout ImportBatch.SpaceItems) -> Void) {
            if items[space] == nil {
                items[space] = ImportBatch.SpaceItems(space: space)
                itemOrder.append(space)
            }
            body(&items[space]!)
            batch.spaces = itemOrder.compactMap { items[$0] }
        }

        /// Pinned nodes for a container at `depth` (0 = the pinned root),
        /// folders past `FolderRules.maxDepth` flattened into it.
        mutating func pinned(_ nodes: [ImportedNode], depth: Int, space: ImportBatch.SpaceRef) -> [ImportBatch.Node] {
            var result: [ImportBatch.Node] = []
            for node in nodes {
                switch node {
                case .link(let link):
                    if let admitted = admit(link, space: space) {
                        result.append(.link(admitted))
                        preview.pinned += 1
                    }
                case .folder(let folder):
                    if depth + 1 > FolderRules.maxDepth {
                        preview.foldersFlattened += 1
                        result += pinned(folder.children, depth: depth, space: space)
                    } else {
                        preview.folders += 1
                        let children = pinned(folder.children, depth: depth + 1, space: space)
                        result.append(.folder(name: folder.title.isEmpty ? ImportPlanner.untitledFolder : folder.title, children: children))
                    }
                }
            }
            return result
        }

        /// An essential of `profile`, or `false` when the grid is full (the caller pins it instead).
        mutating func addEssential(_ link: ImportedLink, profile: ImportBatch.ProfileRef, space: ImportBatch.SpaceRef?) -> Bool {
            guard EntryRules.canAddEssential(currentCount: essentialsCount[profile] ?? 0) else { return false }
            if let admitted = admit(link, space: space, essentialOf: profile) {
                if essentials[profile] == nil { essentialsOrder.append(profile) }
                essentials[profile, default: []].append(admitted)
                essentialsCount[profile, default: 0] += 1
                preview.essentials += 1
                batch.essentials = essentialsOrder.compactMap { ref in essentials[ref].map { ImportBatch.Essentials(profile: ref, links: $0) } }
            }
            return true
        }

        // MARK: Bookmarks

        mutating func addBookmarks(_ bookmarks: ImportedBookmarks) {
            let space = targetSpace()
            let profile = spaceProfile[space] ?? targetProfile()
            var rootNodes: [ImportedNode] = []
            for node in bookmarks.bar {
                if options.barIntoEssentials, case .link(let link) = node, ImportURL.refusedScheme(link.url) == nil {
                    if !addEssential(link, profile: profile, space: space) {
                        // Pinned instead; a duplicate is counted as one when it is skipped there.
                        if !isDuplicate(link, space: space, profile: profile) { preview.essentialsOverflow += 1 }
                        rootNodes.append(node)
                    }
                } else {
                    rootNodes.append(node)
                }
            }
            rootNodes += bookmarks.other + bookmarks.mobile
            switch options.layout {
            case .oneSpace:
                let nodes = pinned(rootNodes, depth: 0, space: space)
                if !nodes.isEmpty { items(space) { $0.pinned += nodes } }
            case .spacePerFolder:
                for node in rootNodes {
                    switch node {
                    case .link:
                        let nodes = pinned([node], depth: 0, space: space)
                        if !nodes.isEmpty { items(space) { $0.pinned += nodes } }
                    case .folder(let folder):
                        guard !folder.children.isEmpty else {
                            preview.skipped.append(SkippedItem(folder.title.isEmpty ? ImportPlanner.untitledFolder : folder.title,
                                                               reason: "an empty folder (no space made)"))
                            continue
                        }
                        let folderSpace = newSpace(folder.title.isEmpty ? ImportPlanner.untitledFolder : folder.title, profile: targetProfile())
                        let nodes = pinned(folder.children, depth: 0, space: folderSpace)
                        items(folderSpace) { $0.pinned += nodes }
                    }
                }
            }
        }

        // MARK: Arc

        mutating func addSidebar(_ sidebar: ImportedSidebar) {
            var profiles: [String: ImportBatch.ProfileRef] = [:]
            func profile(_ key: String) -> ImportBatch.ProfileRef {
                if let ref = profiles[key] { return ref }
                let imported = sidebar.profiles.first { $0.key == key }
                let ref: ImportBatch.ProfileRef
                if key == ImportedProfile.defaultKey || imported?.isDefault == true, let id = target.defaultProfileID {
                    ref = profileRef(id)
                } else {
                    let name = imported?.name ?? key
                    if let match = target.profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        ref = profileRef(match.id)
                    } else {
                        ref = newProfile(name)
                    }
                }
                profiles[key] = ref
                return ref
            }
            let spaces = sidebar.spaces.map { space in
                newSpace(space.name, icon: space.icon, colors: space.colors, profile: profile(space.profileKey))
            }
            // Essentials first (the grid shows in every space of the profile), overflow pinned in the profile's first space.
            var overflow: [ImportBatch.SpaceRef: [ImportedNode]] = [:]
            let keys = sidebar.profiles.map(\.key).filter { sidebar.essentials[$0] != nil }
                + sidebar.essentials.keys.filter { key in !sidebar.profiles.contains { $0.key == key } }.sorted()
            for key in keys {
                let ref = profile(key)
                let home = zip(sidebar.spaces, spaces).first { profile($0.0.profileKey) == ref }?.1
                for link in sidebar.essentials[key] ?? [] where !addEssential(link, profile: ref, space: nil) {
                    if let home {
                        if !isDuplicate(link, space: home, profile: ref) { preview.essentialsOverflow += 1 }
                        overflow[home, default: []].append(.link(link))
                    } else {
                        preview.skipped.append(SkippedItem(link.title.isEmpty ? link.url : link.title, reason: "Essentials full"))
                    }
                }
            }
            for (space, ref) in zip(sidebar.spaces, spaces) {
                let nodes = pinned(space.pinned + (overflow[ref] ?? []), depth: 0, space: ref)
                let today = space.today.compactMap { admit($0, space: ref) }
                preview.today += today.count
                items(ref) {
                    $0.pinned += nodes
                    $0.today += today
                }
            }
        }

        // MARK: History

        mutating func historyBatches(_ history: ImportedHistory) -> [[HistoryImportEntry]] {
            var entries: [HistoryImportEntry] = []
            for row in history.urls {
                if let scheme = ImportURL.refusedScheme(row.url) {
                    preview.skipped.append(SkippedItem(row.url, reason: "a \(scheme): page"))
                    continue
                }
                guard let url = URL(string: row.url) else {
                    preview.skipped.append(SkippedItem(row.url, reason: "not a URL"))
                    continue
                }
                let visits = row.visits.map { HistoryVisit(time: $0.time, transition: PageTransition($0.transition)) }
                entries.append(HistoryImportEntry(url: url, title: row.title.isEmpty ? nil : row.title, visits: visits))
                preview.historyVisits += visits.count
            }
            preview.historyURLs = entries.count
            return stride(from: 0, to: entries.count, by: ImportPlanner.historyBatchSize).map {
                Array(entries[$0..<min($0 + ImportPlanner.historyBatchSize, entries.count)])
            }
        }
    }
}

extension PageTransition {
    init(_ transition: ImportedTransition) {
        self = switch transition {
        case .link: .link
        case .typed: .typed
        case .bookmark: .bookmark
        case .generated: .generated
        case .keyword: .keyword
        case .formSubmit: .formSubmit
        case .reload: .reload
        case .other: .other
        }
    }
}
