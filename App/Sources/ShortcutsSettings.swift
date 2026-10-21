import AppKit
import Design
import Store
import UIKitCore

/// Settings ▸ Shortcuts sizes (4.4a; chosen: the sections' width, 560 pt since eight sections fit the toolbar at it).
/// 5.7a (B-120): the table takes the pane's height (`SettingsWindowFit`), inside a 20 pt margin.
enum ShortcutsSettingsMetrics {
    static let width: CGFloat = SettingsWindowFit.contentWidth
    static let margin: CGFloat = 20
    static let keyColumnWidth: CGFloat = 120
    static let resetColumnWidth: CGFloat = 28
    static let rowHeight: CGFloat = 34
}

/// Settings ▸ Shortcuts (ROADMAP 4.4a task 1): every action of the menu bar
/// with its key, in an AppKit `NSTableView` (its rows change per keystroke
/// while a key is recorded; PLAN §4 UI framework). Click a key, press the new
/// one: ⌫ removes the key, Esc cancels. A key another action has marks both
/// rows and asks before the new one wins; a key macOS needs is refused with
/// the reason. Writes `Settings.shortcutOverrides`; the app applies them.
final class ShortcutsSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    /// A key that waits for the user's word: `id` would take `key` from `others`.
    struct Pending: Equatable {
        let id: String
        let key: ReservedShortcuts.Shortcut
        let others: [String]
    }

    private let settings: SettingsStore
    private let actions = ShortcutTable.actions
    /// The extensions' commands with keys (4.5): read-only rows after the actions.
    private let extensionCommands: () -> [(extension: String, title: String, shortcut: String)]
    private(set) var extensionRows: [ExtensionShortcutRow] = []
    private(set) var table: ShortcutTable
    private(set) var pending: Pending?
    /// The last refusal or note under the table ("" when none).
    private(set) var message = ""
    private(set) var recordingID: String?

    private let tableView = NSTableView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let confirmButton = NSButton(title: "Use It", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let resetAllButton = NSButton(title: "Reset All", target: nil, action: nil)
    /// The message line with its buttons, hidden while it has nothing to say (5.7a: no empty gap under the table).
    private var promptRow: NSStackView?

    init(settings: SettingsStore, extensionCommands: @escaping () -> [(extension: String, title: String, shortcut: String)] = { [] }) {
        self.settings = settings
        self.extensionCommands = extensionCommands
        table = ShortcutTable(overrides: settings.settings.shortcutOverrides)
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: ShortcutsSettingsMetrics.width, height: SettingsWindowFit.preferredContentHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let intro = NSTextField(wrappingLabelWithString: "Click a shortcut and press the new keys: ⌫ removes it, Esc cancels.")
        intro.font = Typography.secondary
        intro.textColor = .secondaryLabelColor

        let actionColumn = NSTableColumn(identifier: .init("action"))
        actionColumn.title = "Action"
        let keyColumn = NSTableColumn(identifier: .init("key"))
        keyColumn.title = "Shortcut"
        keyColumn.width = ShortcutsSettingsMetrics.keyColumnWidth
        let resetColumn = NSTableColumn(identifier: .init("reset"))
        resetColumn.title = ""
        resetColumn.width = ShortcutsSettingsMetrics.resetColumnWidth
        for column in [actionColumn, keyColumn, resetColumn] { tableView.addTableColumn(column) }
        tableView.rowHeight = ShortcutsSettingsMetrics.rowHeight
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.intercellSpacing = NSSize(width: Spacing.s, height: 0)
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // The table takes the pane's height left by the lines above and below it.
        scroll.setContentHuggingPriority(.defaultLow - 1, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow - 1, for: .vertical)

        messageLabel.font = Typography.secondary
        confirmButton.target = self
        confirmButton.action = #selector(confirmPendingClicked)
        confirmButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancelPendingClicked)
        resetAllButton.target = self
        resetAllButton.action = #selector(resetAllClicked)
        let prompt = NSStackView(views: [messageLabel, confirmButton, cancelButton])
        promptRow = prompt
        prompt.orientation = .horizontal
        prompt.alignment = .centerY
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [NSView(), resetAllButton])
        footer.orientation = .horizontal

        let stack = NSStackView(views: [intro, scroll, prompt, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = Spacing.m
        let margin = ShortcutsSettingsMetrics.margin
        stack.edgeInsets = NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
        for view in [intro, scroll, prompt, footer] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * margin).isActive = true
        }
        view = stack
        refresh()
        observeSettings()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    /// Another writer (the palette, a spike, a second window) changes the overrides: the rows follow.
    private func observeSettings() {
        let overrides = withObservationTracking {
            settings.settings.shortcutOverrides
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in weakSelf.value?.observeSettings() }
        }
        if overrides != table.overrides {
            table = ShortcutTable(overrides: overrides)
            refresh()
        }
    }

    // MARK: Changes (the recorder calls these; the settings spike too)

    /// What a key pressed for `id` does: applied, refused with the reason, or held for confirmation.
    @discardableResult
    func propose(_ key: ReservedShortcuts.Shortcut?, for id: String) -> ShortcutTable.Check {
        recordingID = nil
        pending = nil
        var changed = table
        let result = changed.assign(key, to: id)
        switch result {
        case .ok:
            message = ""
            save(changed)
        case .unchanged:
            message = ""
        case .refused(let reason):
            message = reason
        case .conflict(let others):
            if let key {
                pending = Pending(id: id, key: key, others: others)
                let names = others.map(title).joined(separator: ", ")
                message = "\(key) is \(names)'s shortcut. Use it for \(title(id)) instead?"
            }
        }
        refresh()
        return result
    }

    /// The prompt's "Use It": the newer action takes the key, the others lose it.
    func confirmPending() {
        guard let pending else { return }
        var changed = table
        changed.assign(pending.key, to: pending.id, replacingConflicts: true)
        self.pending = nil
        message = "\(pending.key) is now \(title(pending.id))'s; \(pending.others.map(title).joined(separator: ", ")) has no shortcut."
        save(changed)
        refresh()
    }

    func cancelPending() {
        pending = nil
        message = ""
        refresh()
    }

    func reset(_ id: String) {
        var changed = table
        changed.reset(id)
        pending = nil
        message = ""
        save(changed)
        refresh()
    }

    func resetAll() {
        var changed = table
        changed.resetAll()
        pending = nil
        message = ""
        save(changed)
        refresh()
    }

    /// The recorder of `id` takes the next key press (the settings spike starts it as a click does).
    @discardableResult
    func startRecording(_ id: String) -> Bool {
        guard let row = actions.firstIndex(where: { $0.id == id }) else { return false }
        tableView.scrollRowToVisible(row)
        guard let recorder = tableView.view(atColumn: 1, row: row, makeIfNecessary: true) as? ShortcutRecorderButton else { return false }
        recorder.beginRecording()
        return recorder.isRecording
    }

    /// Scrolls `id`'s row into view (the settings spike's capture).
    func reveal(_ id: String) {
        guard let row = actions.firstIndex(where: { $0.id == id }) else { return }
        tableView.scrollRowToVisible(min(actions.count - 1, row + 3))
    }

    /// A recorder took the keyboard: nothing reloads (that would take the first responder away).
    private func recordingStarted(_ id: String) {
        recordingID = id
        pending = nil
        message = ""
        messageLabel.stringValue = ""
        confirmButton.isHidden = true
        cancelButton.isHidden = true
        promptRow?.isHidden = true
    }

    /// Ids marked on screen: a conflict waiting for an answer, or stored keys two actions share.
    var markedIDs: Set<String> {
        var ids = Set(table.conflicts.values.joined())
        if let pending { ids.insert(pending.id); ids.formUnion(pending.others) }
        return ids
    }

    private func save(_ changed: ShortcutTable) {
        table = changed
        settings.update { $0.shortcutOverrides = changed.overrides }
    }

    private func title(_ id: String) -> String { ShortcutTable.action(id)?.displayTitle ?? id }

    private func refresh() {
        guard isViewLoaded else { return }
        extensionRows = table.extensionRows(extensionCommands())
        tableView.reloadData()
        messageLabel.stringValue = message
        messageLabel.textColor = pending != nil || message.isEmpty ? .labelColor : .systemRed
        confirmButton.title = pending.map { "Use for \(title($0.id))" } ?? "Use It"
        confirmButton.isHidden = pending == nil
        cancelButton.isHidden = pending == nil
        promptRow?.isHidden = message.isEmpty && pending == nil
        resetAllButton.isEnabled = !table.overrides.isEmpty
    }

    @objc private func confirmPendingClicked() { confirmPending() }
    @objc private func cancelPendingClicked() { cancelPending() }
    @objc private func resetAllClicked() { resetAll() }
    @objc private func resetRowClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        reset(actions[sender.tag].id)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { actions.count + extensionRows.count }

    /// An extension command's row (4.5): its extension and title, the key as
    /// text, the Room actions it takes the key from; no recorder, no reset.
    private func extensionRowView(_ row: ExtensionShortcutRow, column: String?) -> NSView? {
        switch column {
        case "action":
            let cell = tableView.makeView(withIdentifier: .init("actionCell"), owner: nil) as? ShortcutActionCell ?? ShortcutActionCell()
            cell.identifier = .init("actionCell")
            let taken = row.conflicts.isEmpty ? "" : " · takes the key from " + row.conflicts.map(title).joined(separator: ", ")
            cell.set(title: "\(row.extensionName): \(row.title)", detail: "Extension · " + ExtensionShortcutRow.note + taken,
                     marked: !row.conflicts.isEmpty)
            return cell
        case "key":
            let label = NSTextField(labelWithString: row.shortcut)
            label.font = Typography.row
            label.textColor = row.conflicts.isEmpty ? .secondaryLabelColor : .systemOrange
            label.toolTip = ExtensionShortcutRow.note
            return label
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < actions.count else { return extensionRowView(extensionRows[row - actions.count], column: tableColumn?.identifier.rawValue) }
        let action = actions[row]
        let marked = markedIDs.contains(action.id)
        switch tableColumn?.identifier.rawValue {
        case "action":
            let cell = tableView.makeView(withIdentifier: .init("actionCell"), owner: nil) as? ShortcutActionCell ?? ShortcutActionCell()
            cell.identifier = .init("actionCell")
            let chapter = action.chapter.map { " · Chapter \($0)" } ?? ""
            cell.set(title: action.displayTitle, detail: action.menu + chapter, marked: marked)
            // Reserved stays an internal property (5.7a, B-120): the tooltip says it, no marker.
            cell.toolTip = action.isReserved ? "Never reaches the page, under any key you give it." : nil
            return cell
        case "key":
            let recorder = tableView.makeView(withIdentifier: .init("keyCell"), owner: nil) as? ShortcutRecorderButton ?? ShortcutRecorderButton()
            recorder.identifier = .init("keyCell")
            let key = table.key(for: action.id)
            recorder.configure(key: key, recording: recordingID == action.id, marked: marked, fixed: action.fixed)
            recorder.toolTip = action.fixed ?? (marked ? conflictNote(action.id) : nil)
            recorder.onStart = { [weak self] in self?.recordingStarted(action.id) }
            recorder.onRecord = { [weak self] key in
                // After the event's turn: the reload replaces the recorder that is handling it.
                DispatchQueue.main.async { self?.propose(key, for: action.id) }
            }
            recorder.onCancel = { [weak self] in
                if self?.recordingID == action.id { self?.recordingID = nil }
            }
            return recorder
        default:
            let button = tableView.makeView(withIdentifier: .init("resetCell"), owner: nil) as? NSButton
                ?? NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Reset")!,
                            target: nil, action: nil)
            button.identifier = .init("resetCell")
            button.isBordered = false
            button.target = self
            button.action = #selector(resetRowClicked(_:))
            button.tag = row
            button.isHidden = !table.isOverridden(action.id)
            button.toolTip = action.defaultKey.map { "Back to \($0)" } ?? "Back to no shortcut"
            return button
        }
    }

    private func conflictNote(_ id: String) -> String {
        guard let key = pending.flatMap({ $0.id == id ? $0.key : nil }) ?? table.key(for: id) else { return "" }
        let others = ShortcutTable.actions.filter { $0.id != id && (table.key(for: $0.id) == key || pending?.others.contains($0.id) == true) }
        return "\(key) is also " + others.map(\.displayTitle).joined(separator: ", ")
    }
}

/// The action column: the title and the menu it is in.
private final class ShortcutActionCell: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        detail.font = Typography.secondary
        detail.textColor = .secondaryLabelColor
        title.font = Typography.row
        title.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xs),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(title text: String, detail menu: String, marked: Bool) {
        title.stringValue = text
        title.textColor = marked ? .systemOrange : .labelColor
        detail.stringValue = menu
    }
}

/// A key cell: shows the key, and after a click records the next key press
/// (key equivalents included: the window offers them to its views before the
/// menu bar, so ⌘W is recorded, not run).
final class ShortcutRecorderButton: NSButton {
    var onStart: (() -> Void)?
    var onRecord: ((ReservedShortcuts.Shortcut?) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isRecording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        controlSize = .small
        target = self
        action = #selector(clicked)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var key: ReservedShortcuts.Shortcut?
    private var marked = false

    func configure(key: ReservedShortcuts.Shortcut?, recording: Bool, marked: Bool, fixed: String?) {
        self.key = key
        self.marked = marked
        isRecording = recording
        isEnabled = fixed == nil
        updateTitle()
    }

    private func updateTitle() {
        let text = isRecording ? "Type shortcut…" : (key?.description ?? "—")
        attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: marked ? NSColor.systemOrange : (isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor),
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    @objc private func clicked() { beginRecording() }

    /// Takes the next key press (a click, or the settings spike).
    func beginRecording() {
        guard isEnabled, window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        updateTitle()
        onStart?()
    }

    private func endRecording() {
        isRecording = false
        updateTitle()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            endRecording()
            onCancel?()
        }
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers.isEmpty, event.keyCode == 53 {
            endRecording()
            onCancel?()
            return
        }
        let shortcut: ReservedShortcuts.Shortcut?
        if modifiers.isEmpty, event.keyCode == 51 || event.keyCode == 117 {
            shortcut = nil
        } else if let recorded = ReservedShortcuts.shortcut(for: event) {
            shortcut = recorded
        } else {
            return NSSound.beep()
        }
        endRecording()
        onRecord?(shortcut)
    }
}
