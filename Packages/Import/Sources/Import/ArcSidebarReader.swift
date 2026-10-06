import Foundation

/// Arc's `StorableSidebar.json` (Arc's own file beside its `User Data`;
/// undocumented and changed between Arc versions, so read tolerantly:
/// unknown keys are ignored, an item missing what it needs is skipped with
/// a count). The shape open-source Arc export tools describe:
/// `sidebar.containers[]`, the one with `spaces` and `items`; both arrays
/// either alternate ids and objects or hold objects only. A space has `id`,
/// `title`, `profile` (`{"default": true}` or `{"custom": {"_0":
/// {"directoryBasename": "Profile 1"}}}`), `containerIDs` (`["unpinned",
/// id, "pinned", id]`) and `customInfo` (`iconType.emoji_v2` or `emoji`;
/// `windowTheme.primaryColorPalette.midTone` as 0–1 RGB). An item has `id`,
/// `parentID`, `childrenIds`, `title` and `data`: `tab.savedURL`/`savedTitle`,
/// `list` (a folder), `splitView` (its tabs join the parent), `itemContainer`
/// (a space's root or an essentials grid); anything else (easels, notes,
/// boosts) is skipped. `topAppsContainerIDs` alternates a profile and the
/// id of that profile's essentials container.
public enum ArcSidebarReader {
    /// `profileNames`: directory basename → name, from `User Data/Local State`.
    public static func read(_ data: Data, profileNames: [String: String] = [:]) throws(ImportError) -> ImportedSidebar {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) } catch {
            throw ImportError(.malformed, .arcSidebar, "not JSON")
        }
        guard let containers = ((json as? [String: Any])?["sidebar"] as? [String: Any])?["containers"] as? [Any] else {
            throw ImportError(.malformed, .arcSidebar, "no sidebar.containers")
        }
        guard let container = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil && $0["items"] != nil }) else {
            throw ImportError(.malformed, .arcSidebar, "no container with spaces and items")
        }
        let spaceObjects = objects(container["spaces"])
        var items: [String: [String: Any]] = [:]
        for item in objects(container["items"]) {
            if let id = item["id"] as? String { items[id] = item }
        }
        var result = ImportedSidebar()
        var skipped: [SkippedItem] = []
        var profiles: [String: ImportedProfile] = [:]
        var profileOrder: [String] = []
        func profileKey(_ value: Any?) -> String {
            let key = Self.profileKey(value)
            if profiles[key] == nil {
                let isDefault = key == ImportedProfile.defaultKey
                profiles[key] = ImportedProfile(key: key, name: isDefault ? (profileNames["Default"] ?? "Default") : (profileNames[key] ?? key),
                                                isDefault: isDefault)
                profileOrder.append(key)
            }
            return key
        }

        func label(_ item: [String: Any]) -> String {
            let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any]
            return (item["title"] as? String) ?? (tab?["savedTitle"] as? String) ?? (item["id"] as? String) ?? "(item)"
        }
        /// A tab item as a link; `nil` (skipped) without a URL.
        func link(_ item: [String: Any]) -> ImportedLink? {
            guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any] else { return nil }
            guard let url = tab["savedURL"] as? String, !url.isEmpty else {
                skipped.append(SkippedItem(label(item), reason: "a tab without a URL"))
                return nil
            }
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (tab["savedTitle"] as? String) ?? ""
            return ImportedLink(url: url, title: title, guid: item["id"] as? String)
        }
        /// The children of `id` as nodes, in `childrenIds` order.
        func nodes(of id: String, visited: inout Set<String>) -> [ImportedNode] {
            guard let parent = items[id], visited.insert(id).inserted else { return [] }
            var result: [ImportedNode] = []
            for childID in (parent["childrenIds"] as? [String]) ?? [] {
                guard let child = items[childID] else {
                    skipped.append(SkippedItem(childID, reason: "missing item"))
                    continue
                }
                let data = (child["data"] as? [String: Any]) ?? [:]
                if data["tab"] != nil {
                    if let link = link(child) { result.append(.link(link)) }
                } else if data["list"] != nil {
                    result.append(.folder(ImportedFolder(title: (child["title"] as? String) ?? "", children: nodes(of: childID, visited: &visited),
                                                         guid: childID)))
                } else if data["splitView"] != nil {
                    result += nodes(of: childID, visited: &visited)
                } else {
                    skipped.append(SkippedItem(label(child), reason: "unsupported item (\(data.keys.sorted().first ?? "no data"))"))
                }
            }
            return result
        }

        for space in spaceObjects {
            guard let id = space["id"] as? String else {
                skipped.append(SkippedItem((space["title"] as? String) ?? "(space)", reason: "a space without an id"))
                continue
            }
            let ids = pairs(space["containerIDs"])
            var visited = Set<String>()
            let pinned = ids["pinned"].map { nodes(of: $0, visited: &visited) } ?? []
            let today = (ids["unpinned"].map { nodes(of: $0, visited: &visited) } ?? []).flatMap(\.links)
            let info = space["customInfo"] as? [String: Any]
            result.spaces.append(ImportedSpace(id: id, name: (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space",
                                               icon: icon(info), colors: color(info).map { [$0] } ?? [],
                                               profileKey: profileKey(space["profile"]), pinned: pinned, today: today))
        }
        // Essentials: profile, container id, profile, container id, …
        let topApps = (container["topAppsContainerIDs"] as? [Any]) ?? []
        var index = 0
        while index + 1 < topApps.count {
            let key = profileKey(topApps[index])
            if let containerID = topApps[index + 1] as? String {
                var visited = Set<String>()
                result.essentials[key, default: []] += nodes(of: containerID, visited: &visited).flatMap(\.links)
            }
            index += 2
        }
        result.profiles = profileOrder.compactMap { profiles[$0] }
        result.skipped = skipped
        return result
    }

    /// The objects of an array that may alternate ids and objects.
    static func objects(_ value: Any?) -> [[String: Any]] {
        ((value as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
    }

    /// `["unpinned", id, "pinned", id]` (or with `{"unpinned": {}}` keys) as a dictionary.
    static func pairs(_ value: Any?) -> [String: String] {
        let list = (value as? [Any]) ?? []
        var result: [String: String] = [:]
        var index = 0
        while index + 1 < list.count {
            let key = (list[index] as? String) ?? ((list[index] as? [String: Any])?.keys.first)
            if let key, let id = list[index + 1] as? String { result[key] = id }
            index += 2
        }
        return result
    }

    static func profileKey(_ value: Any?) -> String {
        guard let object = value as? [String: Any] else { return ImportedProfile.defaultKey }
        if object["default"] != nil { return ImportedProfile.defaultKey }
        if let custom = object["custom"] as? [String: Any] {
            let inner = (custom["_0"] as? [String: Any]) ?? custom
            if let directory = inner["directoryBasename"] as? String, !directory.isEmpty { return directory }
        }
        return ImportedProfile.defaultKey
    }

    static func icon(_ info: [String: Any]?) -> String? {
        guard let icon = info?["iconType"] as? [String: Any] else { return nil }
        return (icon["emoji_v2"] as? String) ?? (icon["emoji"] as? String)
    }

    /// `#RRGGBB` from `windowTheme.primaryColorPalette.midTone`.
    static func color(_ info: [String: Any]?) -> String? {
        guard let theme = info?["windowTheme"] as? [String: Any],
              let mid = (theme["primaryColorPalette"] as? [String: Any])?["midTone"] as? [String: Any],
              let red = (mid["red"] as? NSNumber)?.doubleValue, let green = (mid["green"] as? NSNumber)?.doubleValue,
              let blue = (mid["blue"] as? NSNumber)?.doubleValue else { return nil }
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

extension ImportedNode {
    /// Every link of this subtree, in order (a folder's tabs when only links fit, e.g. Today).
    var links: [ImportedLink] {
        switch self {
        case .link(let link): [link]
        case .folder(let folder): folder.children.flatMap(\.links)
        }
    }
}
