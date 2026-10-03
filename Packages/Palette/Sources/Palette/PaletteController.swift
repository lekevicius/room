import AppKit
import Design
import Engine
import Model
import Observation
import Omnibox
import Sidebar
import Store
import Tabs

/// The ⌘T / ⌘L palette of one window (spec §C): an in-window overlay over
/// the card (or docked on the header's address field), the Omnibox pipeline
/// behind its field, and the commit semantics of `PaletteSemantics` carried
/// out on the tab controller and the sidebar.
public final class PaletteController: NSObject, NSTextFieldDelegate {
    public enum Presentation: Equatable {
        /// Centred over the card, 18% down (spec §C).
        case centered
        /// Over the header's address field, the results dropping below it (a click on the field, spec §C).
        case docked
    }

    private weak var hostView: NSView?
    private let tabs: TabController
    private let sidebar: SidebarController
    public var omnibox = Omnibox()
    /// The card's frame in `hostView` (the palette centres over it).
    public var contentRect: () -> NSRect = { .zero }
    /// The header's address field in `hostView`, when the sidebar shows it.
    public var addressFieldRect: () -> NSRect? = { nil }
    /// Favicons for entry rows (the tab controller's live or cached icons).
    public var favicon: (UUID) -> (image: NSImage?, isLoaded: Bool) = { _ in (nil, false) }
    /// The clock for typed-text memory and recency (tests inject one).
    public var now: () -> Date = Date.init
    /// Called after every query with its main-thread duration (DEBUG measurements).
    public var onQueryTimed: ((Duration) -> Void)?

    public private(set) var mode: PaletteMode?
    public private(set) var presentation: Presentation = .centered
    /// The rows, in display order.
    public private(set) var result = OmniboxResult()
    public private(set) var highlightedIndex: Int?
    /// What the user typed (without inline completion).
    public private(set) var typedText = ""

    private var overlay: PaletteOverlayView?
    private var context = OmniboxContext()
    private var memory = TypedTextMemory(lifetime: Timing.typedTextMemory)
    private weak var previousResponder: NSResponder?
    /// ⌘Enter: the field editor has no command for it, and a key equivalent
    /// reaches the panel only in the key window; a local monitor sees it first.
    private var keyMonitor: Any?

    public init(hostView: NSView, tabs: TabController, sidebar: SidebarController) {
        self.hostView = hostView
        self.tabs = tabs
        self.sidebar = sidebar
    }

    public var isOpen: Bool { mode != nil }

    // MARK: Opening and closing

    /// ⌘T: opens empty; closes the palette if it is open (Arc).
    public func toggleNew() {
        if isOpen { return dismiss() }
        open(.new, presentation: .centered)
    }

    /// ⌘L (`docked` false) or a click on the header field (`docked` true):
    /// prefilled with the current URL, selected. Without a page in the card
    /// it is ⌘T. Closes the palette if it is open.
    public func toggleEdit(docked: Bool) {
        if isOpen { return dismiss() }
        guard let id = tabs.currentEntryID, let entry = sidebar.store.sidebar.entry(id) else {
            return open(.new, presentation: .centered)
        }
        let url = tabs.current?.url?.absoluteString ?? entry.currentURL ?? ""
        let docked = docked && addressFieldRect() != nil
        open(.edit(entry: id, url: url), presentation: docked ? .docked : .centered)
    }

    public func open(_ mode: PaletteMode, presentation: Presentation) {
        guard let hostView, !isOpen else { return }
        self.mode = mode
        self.presentation = presentation
        context = makeContext()
        previousResponder = hostView.window?.firstResponder
        let overlay = PaletteOverlayView(frame: hostView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onClickOutside = { [weak self] in self?.dismiss() }
        let panel = overlay.panel
        panel.field.delegate = self
        panel.rows.onHover = { [weak self] index in self?.highlight(index) }
        panel.rows.onClick = { [weak self] index, flags in
            self?.highlight(index)
            self?.commit(modifier: Self.modifier(flags))
        }
        hostView.addSubview(overlay, positioned: .above, relativeTo: nil)
        self.overlay = overlay
        // Typed text kept for this tab (45 s) comes back with the caret at its end.
        let remembered = mode.entry.flatMap { memory.take(for: $0, at: now()) }
        let text = remembered ?? mode.prefill
        panel.field.stringValue = text
        typedText = text
        query(preventingInline: true)
        layout()
        hostView.window?.makeFirstResponder(panel.field)
        if remembered == nil {
            panel.field.currentEditor()?.selectAll(nil)
        } else {
            panel.field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        panel.animateIn()
        observeSelection()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let field = self.overlay?.panel.field, event.window === field.window,
                  event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command),
                  field.window?.firstResponder === field.currentEditor() else { return event }
            self.commit(modifier: .command)
            return nil
        }
    }

    /// Closed without a commit (a click outside, ⌘T/⌘L again, a tab
    /// switch): edited ⌘L text is kept for that tab (spec §C, 45 s).
    public func dismiss() {
        guard let mode else { return }
        if let entry = mode.entry, typedText != mode.prefill {
            memory.remember(typedText, for: entry, at: now())
        }
        close(restoringFocus: true)
    }

    private func close(restoringFocus: Bool) {
        guard isOpen, let overlay else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        mode = nil
        result = OmniboxResult()
        highlightedIndex = nil
        self.overlay = nil
        let window = overlay.window
        overlay.panel.field.delegate = nil
        if Motion.reduceMotion || window == nil {
            overlay.removeFromSuperview()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fast
                overlay.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { overlay.removeFromSuperview() }
            }
        }
        guard restoringFocus, let window else { return }
        if let view = previousResponder as? NSView, view.window === window, !(view is NSText) {
            window.makeFirstResponder(view)
        } else {
            focusPage(in: window)
        }
    }

    /// Focus returns to the page (ROADMAP 2.4 task 1): the first view in its
    /// tree that takes the keyboard (CEF's render view inside our container).
    private func focusPage(in window: NSWindow) {
        guard let root = tabs.current?.nativeView else {
            window.makeFirstResponder(nil)
            return
        }
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.acceptsFirstResponder {
                window.makeFirstResponder(view)
                return
            }
            queue += view.subviews
        }
        window.makeFirstResponder(root)
    }

    /// A tab switch while open (⌘1, ⌃Tab, a sidebar click through the menu) dismisses it.
    private func observeSelection() {
        let opened = tabs.currentEntryID
        withObservationTracking {
            _ = tabs.currentEntryID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                if self.tabs.currentEntryID != opened { self.dismiss() } else { self.observeSelection() }
            }
        }
    }

    /// Places the panel for the current window layout (also on every window layout pass).
    public func layout() {
        guard let overlay, let hostView else { return }
        overlay.frame = hostView.bounds
        let bounds = hostView.bounds
        let margin = PaletteMetrics.windowMargin
        let height = PalettePanelView.height(rowCount: result.matches.count, groupCount: groupCount)
        var frame: NSRect
        if presentation == .docked, let anchor = addressFieldRect() {
            let width = max(anchor.width, min(PaletteMetrics.width, bounds.width - anchor.minX - margin))
            // Centred on the field, but never over the window's top edge.
            let top = max(CardMetrics.inset, anchor.midY - PaletteMetrics.fieldHeight / 2)
            frame = NSRect(x: anchor.minX, y: hostView.isFlipped ? top : bounds.height - top - height, width: width, height: height)
        } else {
            let card = contentRect()
            let width = min(PaletteMetrics.width, bounds.width - 2 * margin)
            let x = min(max(margin, card.midX - width / 2), bounds.width - margin - width)
            let y = card.minY + card.height * PaletteMetrics.topFraction
            frame = NSRect(x: x, y: hostView.isFlipped ? y : bounds.height - y - height, width: width, height: height)
        }
        overlay.panel.frame = frame.integral
        overlay.panel.needsLayout = true
    }

    private var groupCount: Int {
        result.matches.indices.filter { $0 == 0 || result.matches[$0].group != result.matches[$0 - 1].group }.count
    }

    // MARK: Querying

    private func makeContext() -> OmniboxContext {
        let store = sidebar.store.sidebar
        let activeSpace = sidebar.activeSpace
        let entries = store.entries.values.compactMap { entry -> OmniboxEntry? in
            guard entry.kind != .folder else { return nil }
            // Essentials belong to a profile: only the active space's profile's are reachable.
            if entry.kind == .essential, let profile = activeSpace?.profileID, entry.profileID != profile { return nil }
            return OmniboxEntry(id: entry.id, kind: entry.kind, title: EntryLabel.title(entry), url: entry.currentURL,
                                storedURL: entry.storedURL, spaceID: entry.spaceID, spaceName: entry.spaceID.flatMap { store.space($0)?.name },
                                lastActiveAt: entry.lastActiveAt?.date)
        }
        return OmniboxContext(entries: entries, activeSpaceID: sidebar.activeSpaceID, currentEntryID: tabs.currentEntryID,
                              searchEngine: .google, now: now())
    }

    /// ⌘L with the URL untouched shows no rows: Enter reloads (spec §C).
    private var isUnchangedEdit: Bool {
        guard case .edit(_, let url) = mode else { return false }
        return typedText == url
    }

    private func query(preventingInline: Bool) {
        let start = ContinuousClock.now
        if isUnchangedEdit {
            result = OmniboxResult()
        } else {
            result = omnibox.result(for: OmniboxInput(text: typedText, preventsInlineCompletion: preventingInline), in: context)
        }
        highlightedIndex = result.isEmpty ? nil : 0
        applyInlineCompletion()
        updateRows()
        onQueryTimed?(ContinuousClock.now - start)
    }

    /// History's top hit completes the typed text in the field, the
    /// completion selected so the next keystroke replaces it (spec §C; 2.4b's provider).
    private func applyInlineCompletion() {
        guard let completion = result.inlineCompletion, let field = overlay?.panel.field else { return }
        field.stringValue = typedText + completion
        let typedLength = (typedText as NSString).length
        field.currentEditor()?.selectedRange = NSRange(location: typedLength, length: (completion as NSString).length)
    }

    private func updateRows() {
        guard let overlay else { return }
        let model = overlay.panel.rows
        model.rows = result.matches.enumerated().map { index, match in row(for: match, startsGroup: index > 0 && match.group != result.matches[index - 1].group) }
        model.highlighted = highlightedIndex
        layout()
    }

    private func row(for match: OmniboxMatch, startsGroup: Bool) -> PaletteRow {
        let icon: PaletteRow.Icon
        switch match.icon {
        case .entry(let id):
            let page = favicon(id)
            icon = .favicon(page.image, domain: EntryLabel.domain(match.action.url) ?? match.title, dimmed: !page.isLoaded)
        case .search: icon = .symbol(.search)
        case .url: icon = .symbol(.openURL)
        case .symbol: icon = .symbol(.commands)
        }
        let hint: String? = if case .switchToEntry = match.action { "Switch to Tab" } else { nil }
        return PaletteRow(id: match.id, icon: icon, title: match.title, detail: match.detail, hint: hint, spaceName: match.spaceName,
                          startsGroup: startsGroup)
    }

    private func highlight(_ index: Int?) {
        guard let index, result.matches.indices.contains(index) else { return }
        highlightedIndex = index
        overlay?.panel.rows.highlighted = index
    }

    /// The user's edit of the field (`NSTextFieldDelegate`); also the entry
    /// point for DEBUG measurements and tests.
    public func setText(_ text: String) {
        overlay?.panel.field.stringValue = text
        textChanged(to: text)
    }

    private func textChanged(to text: String) {
        // A deletion (the new text is a prefix of what was there) never completes inline.
        let deleting = typedText.hasPrefix(text) && text.count < typedText.count
        typedText = text
        query(preventingInline: deleting)
    }

    public func controlTextDidChange(_ notification: Notification) {
        guard let field = overlay?.panel.field else { return }
        // With an inline completion selected, the field holds more than was typed.
        var text = field.stringValue
        if let editor = field.currentEditor(), editor.selectedRange.length > 0,
           NSMaxRange(editor.selectedRange) == (text as NSString).length {
            text = (text as NSString).substring(to: editor.selectedRange.location)
        }
        textChanged(to: text)
    }

    // MARK: Keys (field-editor commands, ROADMAP 2.4 task 1)

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            moveHighlight(-1)
        case #selector(NSResponder.moveDown(_:)):
            moveHighlight(1)
        case #selector(NSResponder.insertNewline(_:)):
            commit(modifier: Self.modifier(NSApp.currentEvent?.modifierFlags ?? []))
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            // ⌥Enter arrives as this command.
            commit(modifier: .option)
        case #selector(NSResponder.cancelOperation(_:)):
            escape()
        case #selector(NSResponder.insertTab(_:)):
            cycleGroup(backwards: false)
        case #selector(NSResponder.insertBacktab(_:)):
            cycleGroup(backwards: true)
        default:
            return false
        }
        return true
    }

    public func moveHighlight(_ offset: Int) {
        guard !result.isEmpty else { return }
        let current = highlightedIndex ?? (offset > 0 ? -1 : result.matches.count)
        highlight(min(max(0, current + offset), result.matches.count - 1))
    }

    /// ⇥ / ⇧⇥: the next (previous) group's first row (spec §C). Tab from
    /// an empty field enters commands in 2.4b.
    public func cycleGroup(backwards: Bool) {
        guard let next = result.groupStart(after: highlightedIndex ?? 0, backwards: backwards) else { return }
        highlight(next)
    }

    /// Esc: ⌘L with edited text restores the URL, selected; otherwise closes (spec §C).
    public func escape() {
        guard let mode else { return }
        switch PaletteSemantics.escape(mode: mode, text: typedText) {
        case .restore(let url):
            setText(url)
            overlay?.panel.field.currentEditor()?.selectAll(nil)
        case .close:
            if let entry = mode.entry { memory.forget(entry) }
            close(restoringFocus: true)
        }
    }

    static func modifier(_ flags: NSEvent.ModifierFlags) -> CommitModifier {
        if flags.contains(.option) { return .option }
        if flags.contains(.command) { return .command }
        return .none
    }

    // MARK: Committing

    /// Enter / ⌘Enter / ⌥Enter, or a click on a row.
    public func commit(modifier: CommitModifier) {
        guard let mode else { return }
        let match = highlightedIndex.flatMap { result.matches.indices.contains($0) ? result.matches[$0] : nil }
        let action = PaletteSemantics.commit(mode: mode, action: match?.action, textUnchanged: isUnchangedEdit, modifier: modifier,
                                             hasCurrent: tabs.currentEntryID != nil)
        guard action != .none else { return }
        if let entry = mode.entry { memory.forget(entry) }
        let window = overlay?.window
        close(restoringFocus: false)
        perform(action, from: mode)
        if let window { focusPage(in: window) }
    }

    private func perform(_ action: CommitAction, from mode: PaletteMode) {
        switch action {
        case .openTab(let url, let background):
            if background { tabs.openBackgroundTab(url: url) } else { tabs.openNewTab(url: url) }
        case .navigateCurrent(let url):
            tabs.navigateSelected(to: url)
        case .reloadCurrent:
            if let page = tabs.current {
                page.reload()
            } else if case .edit(_, let url) = mode, !url.isEmpty {
                tabs.navigateSelected(to: url)
            }
        case .switchTo(let entry, let space):
            if let space, space != sidebar.activeSpaceID { sidebar.showSpace(space) }
            sidebar.select(entry)
        case .runCommand, .none:
            break
        }
    }

    #if DEBUG
    /// The panel, while open (captures).
    public var debugPanel: NSView? { overlay?.panel }
    #endif
}
