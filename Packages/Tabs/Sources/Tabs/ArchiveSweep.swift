import Engine
import Foundation
import Model
import Store

/// The archive sweep (spec §A.7): Today tabs unused for longer than Settings
/// ▸ "Archive tabs after" leave the sidebar for the Archive. The rules are
/// `ArchivePolicy`'s; this gathers what it needs from the window's pages
/// (the engine's discard blockers: sound, capture, unsaved form input) and
/// the selection, unloads the pages it archives and writes the rows.
extension TabController {
    /// What the engine says about each loaded page, as the policy's exemptions.
    var archiveExemptions: [UUID: ArchivePolicy.Exemption] {
        var result: [UUID: ArchivePolicy.Exemption] = [:]
        for (id, page) in pages {
            var exemption: ArchivePolicy.Exemption = []
            let contents = page.contents
            if contents.isAudible { exemption.insert(.audible) }
            guard contents.state == .alive else {
                if !exemption.isEmpty { result[id] = exemption }
                continue
            }
            let blockers = contents.discardBlockers
            if !blockers.isDisjoint(with: [.audible, .recentlyAudible]) { exemption.insert(.audible) }
            if blockers.contains(.capturing) { exemption.insert(.capturing) }
            if !blockers.isDisjoint(with: [.formInteractions, .userEdits]) { exemption.insert(.dirtyForm) }
            if blockers.contains(.pictureInPicture) { exemption.insert(.pictureInPicture) }
            if !exemption.isEmpty { result[id] = exemption }
        }
        return result
    }

    /// Runs the sweep once at `now` (the store's clock): returns the archived
    /// entries. The window's selection and on-screen panes, and every space's
    /// selected entry in every window, are never taken.
    @discardableResult
    public func sweepArchive(now: Timestamp) -> [UUID] {
        let sidebar = store.sidebar
        // This window's Today tabs (schema v9): each window sweeps its own.
        let today = windowID.map { sidebar.todayEntries(window: $0) } ?? sidebar.spaces.flatMap { sidebar.today(space: $0.id) }
        guard !today.isEmpty else { return [] }
        let selected = visibleEntryIDs.union(store.windows.selectedEntries).union(currentEntryID.map { [$0] } ?? [])
        let ids = ArchivePolicy.toArchive(today: today, now: now, afterHours: store.settings.settings.archiveAfterHours,
                                          selected: selected, exemptions: archiveExemptions,
                                          splitGroups: sidebar.splitGroups, entries: sidebar.entries)
        guard !ids.isEmpty else { return [] }
        for id in ids { unload(id) }
        sidebar.archive(ids, reason: .auto)
        NSLog("Room: archived \(ids.count) Today tab(s) unused for \(store.settings.settings.archiveAfterHours) h")
        return ids
    }
}
