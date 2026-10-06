import Foundation

/// What an import writes into the sidebar (Phase 4.3a): new profiles and
/// spaces, pinned trees, Today tabs and essentials, as plain values built off
/// the main thread by `Import.ImportPlanner` and applied by
/// `SidebarStore.applyImport` in one change (one transaction). Duplicates,
/// the folder-depth clip and the Essentials cap are the planner's; the store
/// re-checks the cap and the depth against what it holds when the batch lands.
public struct ImportBatch: Hashable, Sendable {
    /// A profile that exists, or the batch's `newProfiles[index]`.
    public enum ProfileRef: Hashable, Sendable {
        case existing(UUID)
        case new(Int)
    }

    /// A space that exists, or the batch's `newSpaces[index]`.
    public enum SpaceRef: Hashable, Sendable {
        case existing(UUID)
        case new(Int)
    }

    public struct Link: Hashable, Sendable {
        public var url: String
        public var title: String?

        public init(url: String, title: String?) {
            self.url = url
            self.title = title
        }
    }

    /// A pinned-section node: a link (a pinned entry) or a folder.
    public indirect enum Node: Hashable, Sendable {
        case link(Link)
        case folder(name: String, children: [Node])
    }

    public struct NewSpace: Hashable, Sendable {
        public var name: String
        /// Emoji or SF Symbol name.
        public var icon: String?
        /// `#RRGGBB`, 0–3.
        public var themeColors: [String]
        public var profile: ProfileRef

        public init(name: String, icon: String? = nil, themeColors: [String] = [], profile: ProfileRef) {
            self.name = name
            self.icon = icon
            self.themeColors = themeColors
            self.profile = profile
        }
    }

    /// What goes into one space: pinned nodes appended after its pinned
    /// root, Today tabs appended after its Today list.
    public struct SpaceItems: Hashable, Sendable {
        public var space: SpaceRef
        public var pinned: [Node]
        public var today: [Link]

        public init(space: SpaceRef, pinned: [Node] = [], today: [Link] = []) {
            self.space = space
            self.pinned = pinned
            self.today = today
        }
    }

    /// Essentials appended to a profile's grid (up to `EntryRules.essentialsCap`).
    public struct Essentials: Hashable, Sendable {
        public var profile: ProfileRef
        public var links: [Link]

        public init(profile: ProfileRef, links: [Link]) {
            self.profile = profile
            self.links = links
        }
    }

    /// Names of profiles to create (made unique against the existing ones, as New Profile… does).
    public var newProfiles: [String]
    public var newSpaces: [NewSpace]
    public var spaces: [SpaceItems]
    public var essentials: [Essentials]

    public init(newProfiles: [String] = [], newSpaces: [NewSpace] = [], spaces: [SpaceItems] = [], essentials: [Essentials] = []) {
        self.newProfiles = newProfiles
        self.newSpaces = newSpaces
        self.spaces = spaces
        self.essentials = essentials
    }

    public var isEmpty: Bool { newProfiles.isEmpty && newSpaces.isEmpty && spaces.isEmpty && essentials.isEmpty }
}

/// What `SidebarStore.applyImport` wrote (the summary toast and the tour's
/// comparison with the preview).
public struct ImportApplied: Hashable, Sendable {
    public var profiles: [UUID] = []
    public var spaces: [UUID] = []
    public var folders = 0
    public var pinned = 0
    public var essentials = 0
    public var today = 0
    /// Essentials the grid had no room for when the batch landed (the store
    /// filled up after the plan was made); they are not written.
    public var essentialsRefused = 0
    /// Folders that would have nested deeper than `FolderRules.maxDepth`
    /// when the batch landed; their links went into the deepest allowed folder.
    public var foldersFlattened = 0

    public init() {}
}
