import AppKit
import Chrome
import Design
import Engine
import Model
import Observation
import Store

/// The Library in the sidebar (spec §H; ROADMAP 4.1a, PLAN §4 "Library,
/// archive, backups"): ⇧⌘L puts it in place of the spaces view, between the
/// header and the footer, which stay. A search field, then three collapsible
/// sections in one table: the Archive by day (Restore, ×, Clear Archive…),
/// Downloads (the host's list: Open, Show in Finder, Remove) and History (the
/// active space's profile's `ProfileHistory` by day, or a query's matches with
/// `history-archive.json`'s marked "Archived", B-66; delete per row and per
/// host). An item restores (Archive) or opens as a page in the card (History,
/// Downloads open their file); there are no Library pages to navigate.
public final class LibraryController: NSObject {
    public let view = LibraryView()

    /// The active space's profile's history (nil without an engine).
    public var history: () -> (any ProfileHistory)? = { nil }
    /// The active space's profile (the archived history file is per profile).
    public var profileID: () -> UUID? = { nil }
    /// `history-archive.json` beside the database (B-66).
    public var historyArchiveURL: URL?
    /// A History row was chosen: open it as a page in the card.
    public var onOpen: ((URL) -> Void)?
    /// An archived row was chosen: restore it (the app selects it).
    public var onRestore: ((UUID) -> Void)?
    /// Esc with an empty search field, or the window asked to leave.
    public var onClose: (() -> Void)?
    /// Confirmation sheets answer through this instead of an alert when set (spikes).
    public var confirmations: ((_ message: String) -> Bool)?

    private let store: RoomStore
    private let downloads: DownloadList
    private var rows: [LibraryRow] = []
    private var collapsed: Set<LibrarySection> = []
    private var historyItems: [LibraryHistoryItem] = []
    private var historyGeneration = 0
    private var archiveFile: HistoryArchive.File?
    private var archiveFileLoaded = false
    private var faviconImages: [Int64: NSImage] = [:]
    private var token: ObservationToken?
    /// Called after the rows were rebuilt (spikes wait on it).
    public var onReload: (() -> Void)?

    public init(store: RoomStore, downloads: DownloadList) {
        self.store = store
        self.downloads = downloads
        super.init()
        let table = view.tableView
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked(_:))
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        view.searchField.delegate = self
        view.searchField.target = self
        view.searchField.action = #selector(searchChanged(_:))
        view.onCancel = { [weak self] in self?.cancel() }
        token = store.sidebar.observe { [weak self] change in
            guard change.archive || !change.removedSpaces.isEmpty || !change.spaces.isEmpty else { return }
            self?.rebuild()
        }
        observeDownloads()
    }

    // MARK: Showing

    /// Rebuilds everything and puts the keyboard in the search field; with
    /// `section` (⌘Y: History) that section is expanded and scrolled to.
    public func show(section: LibrarySection? = nil) {
        if let section { collapsed.remove(section) }
        rebuild()
        loadHistory()
        if let section { scroll(to: section) }
        view.window?.makeFirstResponder(view.searchField)
    }

    /// The keyboard is in the Library (its search field's editor or its table).
    public var hasKeyboard: Bool {
        guard let responder = view.window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    public var query: String { view.searchField.stringValue.trimmingCharacters(in: .whitespaces) }

    /// Types `text` into the search field (spikes; the field's own edits arrive the same way).
    public func search(_ text: String) {
        view.searchField.stringValue = text
        queryChanged()
    }

    public func setCollapsed(_ section: LibrarySection, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(section) } else { collapsed.remove(section) }
        rebuild()
    }

    /// The rows by kind (the spike's line).
    public var summary: String { LibraryContent.summary(rows) }
    public var currentRows: [LibraryRow] { rows }

    private func scroll(to section: LibrarySection) {
        guard let index = rows.firstIndex(where: { if case .header(section, _, _) = $0 { true } else { false } }) else { return }
        let table = view.tableView
        let rect = table.rect(ofRow: index)
        table.scroll(NSPoint(x: 0, y: rect.minY))
    }

    private func cancel() {
        if !view.searchField.stringValue.isEmpty {
            search("")
        } else {
            onClose?()
        }
    }

    // MARK: Data

    private func rebuild() {
        let downloadRows = downloads.rows.map { row in
            LibraryDownload(id: row.id, name: (row.item.destination ?? row.destination)?.lastPathComponent ?? row.item.suggestedFilename,
                            url: row.item.url, detail: DownloadRules.detail(for: row.item),
                            isFinished: DownloadRules.isFinished(row.item.state))
        }
        rows = LibraryContent.rows(collapsed: collapsed, archive: Array(store.sidebar.archive.values), downloads: downloadRows,
                                   history: historyItems, query: query)
        view.tableView.reloadData()
        onReload?()
    }

    private func observeDownloads() {
        let weakSelf = LibraryWeak(self)
        _ = withObservationTracking {
            downloads.rows
        } onChange: {
            Task { @MainActor in
                weakSelf.value?.rebuild()
                weakSelf.value?.observeDownloads()
            }
        }
    }

    @objc private func searchChanged(_ sender: Any?) { queryChanged() }

    private func queryChanged() {
        rebuild()
        loadHistory()
    }

    /// The History section's rows: the last week by day, or the query's
    /// matches (the engine's, then the archived file's, marked).
    public func loadHistory() {
        historyGeneration += 1
        let generation = historyGeneration
        guard let history = history() else {
            historyItems = []
            rebuild()
            return
        }
        let query = query
        let profile = profileID()
        Task { [weak self] in
            let entries: [HistoryEntry]
            if query.isEmpty {
                let start = Calendar.current.date(byAdding: .day, value: -LibraryMetrics.historyDays,
                                                  to: Calendar.current.startOfDay(for: Date()))
                entries = await history.entries(from: start, to: nil, limit: LibraryMetrics.historyLimit)
            } else {
                entries = await history.search(query, limit: LibraryMetrics.searchLimit)
            }
            var items = entries.map { LibraryHistoryItem(url: $0.url, title: $0.title.isEmpty ? $0.url.absoluteString : $0.title,
                                                         lastVisit: $0.lastVisit) }
            if !query.isEmpty, let self {
                let file = await self.loadArchiveFile()
                items += LibraryContent.archivedHistory(file, profile: profile, query: query, excluding: Set(items.map(\.url)),
                                                        limit: LibraryMetrics.searchLimit)
            }
            guard let self, generation == self.historyGeneration else { return }
            historyItems = items
            rebuild()
        }
    }

    /// `history-archive.json`, read once off the main thread (it can be tens of MB, B-66).
    private func loadArchiveFile() async -> HistoryArchive.File? {
        if archiveFileLoaded { return archiveFile }
        guard let url = historyArchiveURL else { return nil }
        let file = await Task.detached(priority: .userInitiated) { HistoryArchive.read(from: url) }.value
        archiveFile = file
        archiveFileLoaded = true
        return file
    }

    // MARK: Actions

    /// Restore (the row's button, a click on the row, the palette's Enter goes elsewhere).
    public func restore(_ id: UUID) { onRestore?(id) }

    public func deleteArchived(_ id: UUID) { store.sidebar.deleteArchived([id]) }

    /// "Clear Archive…": after the confirmation sheet, every row goes.
    public func clearArchive() {
        let count = store.sidebar.archivedCount
        guard count > 0 else { return }
        let message = "Clear the Archive?"
        let detail = count == 1 ? "1 archived tab is removed for good." : "\(count) archived tabs are removed for good."
        if let confirmations {
            if confirmations(message) { store.sidebar.clearArchive() }
            return
        }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail + " This cannot be undone."
        alert.addButton(withTitle: "Clear Archive")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if let window = view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.store.sidebar.clearArchive() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            store.sidebar.clearArchive()
        }
    }

    public func openDownload(_ id: String) { downloads.open(id) }
    public func revealDownload(_ id: String) { downloads.reveal(id) }

    /// Remove: out of the host's list and the engine's download history
    /// (`Profile.removeDownload`, B-59), so a relaunch does not list it; a
    /// running download is cancelled first.
    public func removeDownload(_ id: String) { downloads.remove(id) }

    public func deleteHistory(_ url: URL) {
        history()?.delete(url: url)
        historyItems.removeAll { $0.url == url && !$0.isArchived }
        rebuild()
    }

    public func deleteHistory(host: String) {
        guard let history = history() else { return }
        Task { [weak self] in
            await history.delete(host: host)
            self?.loadHistory()
        }
    }

    private func toggle(_ section: LibrarySection) {
        if collapsed.contains(section) { collapsed.remove(section) } else { collapsed.insert(section) }
        rebuild()
    }

    /// A click on a row: a header collapses or expands its section; an item does its primary action.
    @objc private func rowClicked(_ sender: Any?) {
        let index = view.tableView.clickedRow
        guard rows.indices.contains(index) else { return }
        perform(rows[index])
    }

    private func perform(_ row: LibraryRow) {
        switch row {
        case .header(let section, _, _): toggle(section)
        case .archived(let entry): restore(entry.id)
        case .download(let download): download.isFinished ? openDownload(download.id) : revealDownload(download.id)
        case .history(let item): onOpen?(item.url)
        case .day, .empty: break
        }
    }

    // MARK: Images

    func favicon(_ id: Int64?) -> NSImage? {
        guard let id else { return nil }
        if let image = faviconImages[id] { return image }
        guard let png = store.favicons.png(id), let image = NSImage(data: png) else { return nil }
        faviconImages[id] = image
        return image
    }

    func favicon(host: String) -> NSImage? {
        favicon(store.favicons.id(forHost: host) ?? store.favicons.id(forHost: "www." + host))
    }

    func spaceName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return store.sidebar.space(id)?.name ?? "Deleted space"
    }
}

// MARK: - Table

extension LibraryController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header: LibraryMetrics.sectionRowHeight
        case .day, .empty: LibraryMetrics.dayRowHeight
        case .archived, .download, .history: LibraryMetrics.itemRowHeight
        }
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let section, let count, let isCollapsed):
            let cell = reuse(LibraryHeaderCell.self, in: tableView)
            var action: (String, () -> Void)?
            if section == .archive, count > 0, !isCollapsed {
                let clear: () -> Void = { [weak self] in self?.clearArchive() }
                action = ("Clear Archive…", clear)
            }
            cell.configure(title: section.title, count: count, collapsed: isCollapsed, action: action)
            return cell
        case .day(_, let date):
            let cell = reuse(LibraryLabelCell.self, in: tableView)
            cell.configure(Self.dayTitle(date))
            return cell
        case .empty(_, let text):
            let cell = reuse(LibraryLabelCell.self, in: tableView)
            cell.configure(text)
            return cell
        case .archived(let entry):
            let cell = reuse(LibraryItemCell.self, in: tableView)
            cell.configure(icon: favicon(entry.faviconID) ?? favicon(host: entry.domain) ?? Symbol.archive.image(),
                           title: entry.displayTitle, subtitle: entry.domain, chip: spaceName(entry.spaceID),
                           buttons: [
                               (.restore, "Restore", { [weak self] in self?.restore(entry.id) }),
                               (.closeTab, "Remove from Archive", { [weak self] in self?.deleteArchived(entry.id) }),
                           ])
            return cell
        case .download(let download):
            let cell = reuse(LibraryItemCell.self, in: tableView)
            cell.configure(icon: Symbol.downloads.image(), title: download.name, subtitle: download.detail, chip: nil,
                           buttons: [
                               (.showInFinder, "Show in Finder", { [weak self] in self?.revealDownload(download.id) }),
                               (.closeTab, "Remove from List", { [weak self] in self?.removeDownload(download.id) }),
                           ])
            return cell
        case .history(let item):
            let cell = reuse(LibraryItemCell.self, in: tableView)
            cell.configure(icon: favicon(host: item.host) ?? Symbol.history.image(), title: item.title, subtitle: item.host,
                           chip: item.isArchived ? "Archived" : nil,
                           buttons: item.isArchived ? [] : [
                               (.closeTab, "Delete from History", { [weak self] in self?.deleteHistory(item.url) }),
                           ])
            return cell
        }
    }

    private func reuse<Cell: NSView>(_ type: Cell.Type, in tableView: NSTableView) -> Cell {
        let identifier = NSUserInterfaceItemIdentifier(String(describing: type))
        if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? Cell { return cell }
        let cell = Cell(frame: .zero)
        cell.identifier = identifier
        return cell
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if date == .distantPast || calendar.startOfDay(for: .distantPast) == date { return "Earlier" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

// MARK: - Context menu

extension LibraryController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let index = view.tableView.clickedRow
        guard rows.indices.contains(index) else { return }
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(LibraryMenuAction.perform(_:)), keyEquivalent: "")
            let target = LibraryMenuAction(action)
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        switch rows[index] {
        case .archived(let entry):
            add("Restore") { [weak self] in self?.restore(entry.id) }
            add("Remove from Archive") { [weak self] in self?.deleteArchived(entry.id) }
        case .download(let download):
            if download.isFinished { add("Open") { [weak self] in self?.openDownload(download.id) } }
            add("Show in Finder") { [weak self] in self?.revealDownload(download.id) }
            add("Remove from List") { [weak self] in self?.removeDownload(download.id) }
        case .history(let item):
            add("Open") { [weak self] in self?.onOpen?(item.url) }
            add("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
            }
            if !item.isArchived {
                menu.addItem(.separator())
                add("Delete from History") { [weak self] in self?.deleteHistory(item.url) }
                add("Delete All from \(item.host)") { [weak self] in self?.deleteHistory(host: item.host) }
            }
        case .header(.archive, let count, _) where count > 0:
            add("Clear Archive…") { [weak self] in self?.clearArchive() }
        case .header, .day, .empty:
            break
        }
    }
}

// MARK: - Search field

extension LibraryController: NSSearchFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            // Down from the field: the first item a click would act on.
            if let first = rows.firstIndex(where: { if case .header = $0 { false } else if case .day = $0 { false } else { true } }) {
                view.tableView.scrollRowToVisible(first)
            }
            return false
        }
        return false
    }

    public func controlTextDidChange(_ obj: Notification) { queryChanged() }
}

/// A closure as a menu item's target (kept alive by `representedObject`).
final class LibraryMenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func perform(_ sender: Any?) { action() }
}

/// A weak reference that may travel through a `@Sendable` closure
/// (`withObservationTracking`'s `onChange`) and is dereferenced only on the
/// main actor (AGENTS.md: never capture a main-actor `self` there).
struct LibraryWeak<Object: AnyObject>: @unchecked Sendable {
    private weak var object: Object?
    init(_ object: Object) { self.object = object }
    @MainActor var value: Object? { object }
}
