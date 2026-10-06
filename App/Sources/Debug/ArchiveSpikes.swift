#if DEBUG
import AppKit
import Chrome
import Library
import Model
import Omnibox
import Store
import UIKitCore

/// Phase 4.1a spike `archive` (`-RoomSidebarFixture archive`, optionally
/// `-RoomClock <ISO date>` and `-RoomSpikeCaptureDirectory <dir>`; the tour
/// step `archive` in group `lifecycle`):
/// 1. the launch sweep's result on the fixture (spec §A.7: the old Today tabs
///    go, the selected, the split-with-a-pinned and the young ones stay) and
///    the rows in the database after a flush;
/// 2. the store's clock moved 13 h on, a second sweep (the young tabs go);
/// 3. the Library (⇧⌘L's path): its rows by kind and reason, a capture;
///    Restore of a row of space "Two" from it (back at the top of that
///    space's Today, selected, the row gone);
/// 4. Clear (⇧⌘K's path, with its slide) writes reason `clear` rows; the
///    toast's Undo takes them back out;
/// 5. the palette: an archived title typed after ⌘T shows a History row
///    with the "Archived" chip; Enter restores it, selected;
/// 6. Delete Space writes `spaceDeleted` rows (B-15); the toast's Undo
///    brings the space and takes the rows out;
/// 7. ⌘Y opens the Library at History; Esc returns to the spaces;
///    Clear Archive (confirmed) empties it.
extension SpikeRunner.Context {
    private var app: AppDelegate? { AppDelegate.current }

    func archiveChecks() async {
        guard let app, let store = app.store, let sweeper = app.archiveSweeper, let library = app.library else {
            return SpikeRunner.record("error", "archive: no store, sweeper or library")
        }
        let sidebar = store.sidebar
        func titles(_ ids: [UUID]) -> String {
            ids.map { id in (sidebar.archive[id]?.title ?? sidebar.entry(id)?.liveTitle ?? id.uuidString)
                .replacingOccurrences(of: "Archive Fixture ", with: "") }.sorted().joined(separator: ",")
        }
        func reasons() -> String {
            ArchiveReason.allCases.map { "\($0.rawValue)=\(sidebar.archivedCount(reason: $0))" }.joined(separator: " ")
        }
        func entry(titled title: String) -> Entry? {
            // By its fixture URL too: a page that loaded (the selection) carries the page's title (4.1b).
            let slug = "archive=" + title.replacingOccurrences(of: " ", with: "-").lowercased()
            return sidebar.entries.values.first { $0.liveTitle == "Archive Fixture \(title)" || $0.liveURL?.hasSuffix(slug) == true }
        }
        func row(titled title: String) -> ArchivedEntry? {
            sidebar.archive.values.first { $0.title == "Archive Fixture \(title)" }
        }
        func settle(_ milliseconds: Int = 400) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
        func databaseRows() -> Int {
            store.flush()
            return (try? store.persistence.writer.database.archivedRowCount()) ?? -1
        }

        // 0. The clock.
        let offset = AppDelegate.debugClockOffset
        SpikeRunner.record("clock", "injected=\(offset != nil) offset_s=\(String(format: "%.0f", offset ?? 0)) "
            + "store=\(ISO8601DateFormatter().string(from: sidebar.clock().date))")
        guard let two = sidebar.spaces.first(where: { $0.name == "Two" }), let first = sidebar.spaces.first else {
            return SpikeRunner.record("error", "archive: the fixture has no space Two")
        }

        // 1. The launch sweep.
        let launch = sweeper.log.first?.archived ?? []
        SpikeRunner.record("launch_sweep", "archived=\(launch.count) [\(titles(launch))]")
        let kept = ["Selected", "Split", "Young", "Two Young"].map { "\($0)=\(entry(titled: $0) != nil)" }.joined(separator: " ")
        SpikeRunner.record("launch_sweep_kept", kept)
        SpikeRunner.record("archive_rows", "\(sidebar.archivedCount) \(reasons())")
        SpikeRunner.record("database_archive_rows", databaseRows())

        // 2. Thirteen hours later.
        let base = sidebar.clock()
        sidebar.clock = { Timestamp(milliseconds: base.milliseconds + 13 * 3_600_000) }
        let later = sweeper.sweep()
        SpikeRunner.record("sweep_after_13h", "archived=\(later.count) [\(titles(later))]")
        SpikeRunner.record("sweep_after_13h_kept", "Selected=\(entry(titled: "Selected") != nil) Split=\(entry(titled: "Split") != nil)")

        // 3. The Library and a Restore from it.
        app.toggleLibrary(nil)
        await settle(600)
        SpikeRunner.record("library_shown", app.isLibraryShown)
        SpikeRunner.record("library_rows", library.summary)
        if let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") {
            let url = URL(fileURLWithPath: directory).appending(path: "phase-4.1a-library.png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            window.displayIfNeeded()
            SpikeRunner.record("capture_library", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
        }
        if let target = row(titled: "Two Old A") {
            library.restore(target.id)
            await settle(600)
            let restored = sidebar.entries[target.id] ?? entry(titled: "Two Old A")
            let top = restored.map { sidebar.today(space: two.id).first?.id == $0.id } ?? false
            SpikeRunner.record("library_restore", "space=\(restored?.spaceID == two.id ? "Two" : "other") top=\(top) "
                + "selected=\(app.sidebar?.selectedEntryID == restored?.id) row_gone=\(sidebar.archive[target.id] == nil) "
                + "library_still_shown=\(app.isLibraryShown)")
        } else {
            SpikeRunner.record("error", "archive: no row Two Old A to restore")
        }
        app.hideLibrary()
        await settle()

        // 4. Clear and its Undo.
        app.sidebar?.showSpace(first.id, animated: false)
        await settle()
        let todayBefore = sidebar.today(space: first.id).count
        let clearBefore = sidebar.archivedCount(reason: .clear)
        app.sidebar?.clearTodayTabs()
        let cleared = await waitUntil(5) { sidebar.archivedCount(reason: .clear) > clearBefore }
        let clearRows = sidebar.archivedCount(reason: .clear) - clearBefore
        SpikeRunner.record("clear", "today_before=\(todayBefore) rows_clear=\(clearRows) done=\(cleared) "
            + "toast=\(app.debugToastCenter?.currentToast?.message ?? "none")")
        if let undo = app.debugToastCenter?.currentToast?.action {
            undo.handler()
            await settle()
        }
        SpikeRunner.record("clear_undo", "today=\(sidebar.today(space: first.id).count) rows_clear=\(sidebar.archivedCount(reason: .clear))")

        // 5. The palette's Archived chip and Enter.
        restorePaletteHooks()
        if let palette, let target = row(titled: "Old 1") {
            press("⌘T")
            await settle()
            type("archive fixture old 1")
            await settle(800)
            let match = palette.result.matches.first { if case .restoreArchived(target.id, _) = $0.action { true } else { false } }
            SpikeRunner.record("palette_archived_row", match.map { "title=\($0.title) chip=\($0.spaceName ?? "none") group=\($0.group)" }
                ?? "missing rows=\(palette.result.matches.map(\.title))")
            if let match, let index = palette.result.matches.firstIndex(of: match) {
                for _ in 0..<index { press("↓") }
                await settle(200)
                SpikeRunner.record("palette_highlighted", palette.highlightedIndex == index)
                press("↩")
                await settle(800)
                let restored = sidebar.entries[target.id] ?? entry(titled: "Old 1")
                SpikeRunner.record("palette_restore", "selected=\(app.sidebar?.selectedEntryID == restored?.id && restored != nil) "
                    + "space=\(restored?.spaceID == first.id ? "Space" : "other") row_gone=\(sidebar.archive[target.id] == nil)")
            } else {
                press("⎋")
            }
        } else {
            SpikeRunner.record("error", "archive: no palette or no row Old 1")
        }
        await settle()

        // 6. Delete Space through the Archive (B-15) and its Undo.
        let twoEntries = sidebar.entries.values.filter { $0.spaceID == two.id && $0.kind != .folder }.count
        app.sidebar?.confirmations = { _ in true }
        app.sidebar?.deleteSpace(two.id)
        await settle()
        SpikeRunner.record("delete_space", "entries=\(twoEntries) rows_spaceDeleted=\(sidebar.archivedCount(reason: .spaceDeleted)) "
            + "space_gone=\(sidebar.space(two.id) == nil) toast=\(app.debugToastCenter?.currentToast?.message ?? "none")")
        if let undo = app.debugToastCenter?.currentToast?.action {
            undo.handler()
            await settle()
        }
        SpikeRunner.record("delete_space_undo", "space_back=\(sidebar.space(two.id) != nil) rows_spaceDeleted=\(sidebar.archivedCount(reason: .spaceDeleted))")

        // 7. ⌘Y, Esc, Clear Archive.
        app.showHistory(nil)
        await settle(800)
        let historyHeader = library.currentRows.contains { if case .header(.history, _, false) = $0 { true } else { false } }
        SpikeRunner.record("cmd_y", "library_shown=\(app.isLibraryShown) history_expanded=\(historyHeader) "
            + "search_has_keyboard=\(library.hasKeyboard)")
        press("⎋")
        await settle()
        SpikeRunner.record("esc_returns", "library_shown=\(app.isLibraryShown)")
        SpikeRunner.record("archive_rows_before_clear_archive", "\(sidebar.archivedCount) \(reasons())")
        library.confirmations = { _ in true }
        library.clearArchive()
        await settle()
        SpikeRunner.record("clear_archive", "rows=\(sidebar.archivedCount) database_rows=\(databaseRows())")
    }
}
#endif
