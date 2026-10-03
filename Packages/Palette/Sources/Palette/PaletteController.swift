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
    /// The local providers plus history over the store's database.
    public var omnibox: Omnibox
    /// The card's frame in `hostView` (the palette centres over it).
    public var contentRect: () -> NSRect = { .zero }
    /// The header's address field in `hostView`, when the sidebar shows it.
    public var addressFieldRect: () -> NSRect? = { nil }
    /// Favicons for entry rows (the tab controller's live or cached icons).
    public var favicon: (UUID) -> (image: NSImage?, isLoaded: Bool) = { _ in (nil, false) }
    /// A site's cached favicon for a history row, by the page's URL.
    public var siteFavicon: (String) -> NSImage? = { _ in nil }
    /// The commands that can run now (spec §C list; the app decides), asked once per open.
    public var commands: () -> [OmniboxCommand] = { [] }
    /// Runs a command by identifier after the palette closed.
    public var onCommand: ((String) -> Void)?
    /// The default engine (Settings ▸ Search).
    public var searchEngine: () -> SearchEngine = { .google }
    /// The suggestions switch (Settings ▸ Search), read on every use so it holds at once.
    public var suggestionsEnabled: () -> Bool = { false }
    /// Search suggestions; `nil` sends nothing.
    public var suggest: SuggestClient? {
        didSet { suggest?.isEnabled = { [weak self] in self?.suggestionsEnabled() ?? false } }
    }
    /// Paste & Go's clipboard (a fake in tests).
    public var clipboard: any PaletteClipboard = SystemClipboard()
    /// The clock for typed-text memory and recency (tests inject one).
    public var now: () -> Date = Date.init
    /// Called after every query with its main-thread duration (DEBUG measurements).
    public var onQueryTimed: ((Duration) -> Void)?
    /// Called after every query with the snapshot, providers and ranking-plus-rows durations (DEBUG measurements).
    public var onQueryPhases: ((_ snapshot: Duration, _ providers: Duration, _ rows: Duration) -> Void)?

    public private(set) var mode: PaletteMode?
    public private(set) var presentation: Presentation = .centered
    /// The rows, in display order.
    public private(set) var result = OmniboxResult()
    public private(set) var highlightedIndex: Int?
    /// What the user typed (without inline completion).
    public private(set) var typedText = ""
    /// The site-search chip in the field (`yt` + Tab), if any.
    public private(set) var siteSearch: SiteSearch?
    /// How many times the sidebar snapshot was built (DEBUG measurements, tests).
    public private(set) var contextBuilds = 0

    /// The overlay while open (`nil` when closed).
    private var overlay: PaletteOverlayView?
    /// Built once and reused: building the glass and the hosting view cost
    /// most of the open's main-thread time (2.4a measurement).
    private var builtOverlay: PaletteOverlayView?
    private var context = OmniboxContext()
    /// The snapshot is built on the first keystroke of an open, not at the
    /// open (an empty palette needs none; 2.4a measured the open at 25.8 ms).
    private var contextIsCurrent = false
    /// The input the rows were last computed for.
    private var input = OmniboxInput(text: "")
    /// The synchronous providers' matches for `input`.
    private var localMatches: [OmniboxMatch] = []
    /// The last suggestions and the query they answer.
    private var suggestions: (query: String, items: [String]) = ("", [])
    /// The clipboard probably holds a URL (Paste & Go), as of `clipboardChangeCount`.
    private var clipboardHasURL = false
    /// ⌘Y: the empty field lists the most frecent history.
    private var listsRecentHistory = false
    private var clipboardChangeCount: Int?
    /// Each entry's snapshot as of the last open, reused while the entry is unchanged.
    private var entryCache: [UUID: (entry: Entry, snapshot: OmniboxEntry)] = [:]
    private var memory = TypedTextMemory(lifetime: Timing.typedTextMemory)
    private weak var previousResponder: NSResponder?
    /// ⌘Enter: the field editor has no command for it, and a key equivalent
    /// reaches the panel only in the key window; a local monitor sees it first.
    private var keyMonitor: Any?

    public init(hostView: NSView, tabs: TabController, sidebar: SidebarController) {
        self.hostView = hostView
        self.tabs = tabs
        self.sidebar = sidebar
        omnibox = Omnibox(providers: Omnibox.localProviders + [HistoryProvider(history: tabs.store.history)])
    }

    public var isOpen: Bool { mode != nil }

    // MARK: Opening and closing

    /// ⌘T: opens empty; closes the palette if it is open (Arc).
    public func toggleNew() {
        if isOpen { return dismiss() }
        open(.new, presentation: .centered)
    }

    /// ⌘Y: the palette lists recent history until something is typed
    /// (shortcuts.md; the engine's history page arrives in Chapter 3); again closes it.
    public func toggleHistory() {
        if isOpen { return dismiss() }
        listsRecentHistory = true
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
        contextIsCurrent = false
        siteSearch = nil
        previousResponder = hostView.window?.firstResponder
        let overlay = preparedOverlay()
        let panel = overlay.panel
        panel.setChip(nil)
        overlay.frame = hostView.bounds
        overlay.layer?.removeAllAnimations()
        overlay.alphaValue = 1
        // The overlay stays in the view tree between opens, hidden: adding it
        // moved the rows' hosting view into the window on every open (2.4b profile).
        if overlay.superview !== hostView || hostView.subviews.last !== overlay {
            hostView.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        overlay.isHidden = false
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
                  field.window?.firstResponder === field.currentEditor() else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
        if case .new = mode { detectClipboardURL() }
    }

    /// Keys the field editor has no command for: ⌘Enter, and ⇧Delete /
    /// ⌘⌥Delete on a removable history row (spec §C). `true`: handled.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76, flags.contains(.command) {
            commit(modifier: .command)
            return true
        }
        // 51: Delete (backspace), 117: forward delete.
        if event.keyCode == 51 || event.keyCode == 117 {
            let chord = flags.subtracting([.function, .numericPad, .capsLock])
            if chord == .shift || chord == [.command, .option] { return deleteHighlightedSuggestion() }
        }
        return false
    }

    /// Builds the overlay ahead of the first ⌘T and puts it in the window,
    /// hidden (the app calls it once the window is up).
    public func prewarm() {
        let overlay = preparedOverlay()
        guard !isOpen else { return }
        overlay.isHidden = true
        if let hostView, overlay.superview !== hostView {
            overlay.frame = hostView.bounds
            hostView.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        overlay.panel.frame = NSRect(x: 0, y: 0, width: PaletteMetrics.width, height: PaletteMetrics.fieldHeight)
        overlay.panel.layoutSubtreeIfNeeded()
    }

    private func preparedOverlay() -> PaletteOverlayView {
        if let builtOverlay { return builtOverlay }
        let overlay = PaletteOverlayView(frame: hostView?.bounds ?? .zero)
        overlay.autoresizingMask = [.width, .height]
        overlay.onClickOutside = { [weak self] in self?.dismiss() }
        let panel = overlay.panel
        panel.field.delegate = self
        panel.rows.onHover = { [weak self] index in self?.highlight(index) }
        panel.rows.onDelete = { [weak self] index in self?.deleteSuggestion(at: index) }
        panel.rows.onClick = { [weak self] index, flags in
            self?.highlight(index)
            self?.commit(modifier: Self.modifier(flags))
        }
        builtOverlay = overlay
        return overlay
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
        suggest?.cancel()
        suggestions = ("", [])
        localMatches = []
        siteSearch = nil
        listsRecentHistory = false
        mode = nil
        result = OmniboxResult()
        highlightedIndex = nil
        self.overlay = nil
        let window = overlay.window
        if Motion.reduceMotion || window == nil {
            hideIfClosed(overlay)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fast
                overlay.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.hideIfClosed(overlay) }
            }
        }
        guard restoringFocus, let window else { return }
        if let view = previousResponder as? NSView, view.window === window, !(view is NSText) {
            window.makeFirstResponder(view)
        } else {
            focusPage(in: window)
        }
    }

    /// Hidden, not removed; unless it reopened during the fade.
    private func hideIfClosed(_ overlay: PaletteOverlayView) {
        guard self.overlay !== overlay else { return }
        overlay.isHidden = true
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

    /// The providers' snapshot of the sidebar and the commands, built on the
    /// first query of an open that needs it. Unchanged entries reuse their
    /// last snapshot and match keys (6 ms for 500 entries otherwise, Debug
    /// build, 2.4a measurement).
    private func ensureContext() {
        guard !contextIsCurrent else { return }
        context = makeContext()
        contextIsCurrent = true
        contextBuilds += 1
    }

    private func makeContext() -> OmniboxContext {
        let store = sidebar.store.sidebar
        let activeSpace = sidebar.activeSpace
        let spaceNames = Dictionary(store.spaces.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var cache: [UUID: (entry: Entry, snapshot: OmniboxEntry)] = [:]
        var entries: [OmniboxEntry] = []
        entries.reserveCapacity(store.entries.count)
        for entry in store.entries.values {
            guard entry.kind != .folder else { continue }
            // Essentials belong to a profile: only the active space's profile's are reachable.
            if entry.kind == .essential, let profile = activeSpace?.profileID, entry.profileID != profile { continue }
            let spaceName = entry.spaceID.flatMap { spaceNames[$0] }
            let snapshot: OmniboxEntry
            if let cached = entryCache[entry.id], cached.entry == entry, cached.snapshot.spaceName == spaceName {
                snapshot = cached.snapshot
            } else {
                snapshot = OmniboxEntry(id: entry.id, kind: entry.kind, title: EntryLabel.title(entry), url: entry.currentURL,
                                        storedURL: entry.storedURL, spaceID: entry.spaceID, spaceName: spaceName,
                                        lastActiveAt: entry.lastActiveAt?.date)
            }
            cache[entry.id] = (entry, snapshot)
            entries.append(snapshot)
        }
        entryCache = cache
        return OmniboxContext(entries: entries, activeSpaceID: sidebar.activeSpaceID, activeProfileID: activeSpace?.profileID,
                              currentEntryID: tabs.currentEntryID,
                              searchEngine: searchEngine(), commands: commands(), now: now(), reusingKeysFrom: context)
    }

    /// ⌘L with the URL untouched shows no rows: Enter reloads (spec §C).
    private var isUnchangedEdit: Bool {
        guard case .edit(_, let url) = mode else { return false }
        return typedText == url
    }

    private func query(preventingInline: Bool) {
        let start = ContinuousClock.now
        var snapshotDone: ContinuousClock.Instant?
        input = OmniboxInput(field: typedText, siteSearch: siteSearch, preventsInlineCompletion: preventingInline)
        if isUnchangedEdit {
            localMatches = []
        } else if input.isEmpty && input.mode == .normal {
            // Nothing typed: no snapshot needed; Paste & Go when the clipboard
            // holds a URL; recent history after ⌘Y.
            localMatches = pasteAndGoMatch.map { [$0] } ?? []
            if listsRecentHistory, let history = omnibox.providers.lazy.compactMap({ $0 as? HistoryProvider }).first {
                localMatches += history.recentMatches(in: OmniboxContext(activeProfileID: sidebar.activeSpace?.profileID, now: now()))
            }
        } else {
            ensureContext()
            snapshotDone = ContinuousClock.now
            localMatches = omnibox.candidates(for: input, in: context)
        }
        let providersDone = ContinuousClock.now
        keepSuggestions(for: input)
        rank(keepingHighlight: false)
        requestSuggestions()
        let end = ContinuousClock.now
        onQueryTimed?(end - start)
        let snapshot = (snapshotDone ?? start) - start
        onQueryPhases?(snapshot, providersDone - start - snapshot, end - providersDone)
    }

    /// The rows from the local matches and the suggestions that have arrived.
    /// When suggestions arrive the highlighted row stays the same row.
    private func rank(keepingHighlight: Bool) {
        let highlightedID = highlightedIndex.flatMap { result.matches.indices.contains($0) ? result.matches[$0].id : nil }
        let suggested = SuggestClient.matches(for: suggestions.items, engine: context.searchEngine)
        result = OmniboxResult(ranking: localMatches + suggested, input: input)
        if keepingHighlight, let highlightedID, let index = result.matches.firstIndex(where: { $0.id == highlightedID }) {
            highlightedIndex = index
        } else {
            highlightedIndex = result.isEmpty ? nil : 0
            applyInlineCompletion()
        }
        updateRows()
    }

    // MARK: Search suggest (ROADMAP 2.4 task 6)

    /// Suggestions for an older query stay while they still start with what is typed (no flicker).
    private func keepSuggestions(for input: OmniboxInput) {
        let typed = input.trimmed.lowercased()
        guard input.mode == .normal, !typed.isEmpty, !isUnchangedEdit, suggestionsEnabled() else {
            suggestions = ("", [])
            return
        }
        suggestions.items = suggestions.items.filter { $0.lowercased().hasPrefix(typed) }
    }

    private func requestSuggestions() {
        guard let suggest else { return }
        guard input.mode == .normal, !input.isEmpty, !isUnchangedEdit, suggestionsEnabled() else { return suggest.cancel() }
        let query = input.trimmed
        suggest.request(query, engine: context.searchEngine) { [weak self] items in
            guard let self, self.isOpen, self.input.mode == .normal, self.input.trimmed == query else { return }
            self.suggestions = (query, items)
            self.rank(keepingHighlight: true)
        }
    }

    /// The Settings switch changed: turned off, nothing more is sent and the
    /// suggestions shown go at once (CLAUDE.md).
    public func suggestionsSettingChanged() {
        guard !suggestionsEnabled() else { return }
        suggest?.cancel()
        guard !suggestions.items.isEmpty else { return }
        suggestions = ("", [])
        if isOpen { rank(keepingHighlight: true) }
    }

    // MARK: Paste & Go (spec §C top hit)

    private var pasteAndGoMatch: OmniboxMatch? {
        guard case .new = mode, clipboardHasURL, clipboardChangeCount == clipboard.changeCount else { return nil }
        return OmniboxMatch(id: "paste-and-go", provider: .verbatim, relevance: Relevance.verbatimURL, action: .pasteAndGo,
                            title: "Paste and Go", detail: "Link on the clipboard", icon: .symbol(Symbol.paste.name))
    }

    /// Asks whether the clipboard holds a URL without reading it (no paste
    /// prompt); the answer is kept until the clipboard changes.
    private func detectClipboardURL() {
        let count = clipboard.changeCount
        guard clipboardChangeCount != count else { return }
        clipboardHasURL = false
        clipboard.detectURL { [weak self] found in
            guard let self else { return }
            self.clipboardChangeCount = count
            self.clipboardHasURL = found
            if found, self.isOpen, case .new = self.mode, self.typedText.isEmpty, self.siteSearch == nil {
                self.query(preventingInline: true)
            }
        }
    }

    /// What Paste & Go commits: the clipboard's text as a URL, or a search for it.
    private func pastedAction() -> MatchAction? {
        guard let text = clipboard.readString()?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let url = URLFixup.url(from: text) { return .navigate(url: url) }
        let engine = searchEngine()
        return .search(query: text, url: engine.searchURL(for: text))
    }

    // MARK: Site search (spec §C)

    /// `yt` + Tab (or Enter on the hint row): the chip, an empty field, that site's searches.
    public func enterSiteSearch(_ site: SiteSearch) {
        guard isOpen else { return }
        siteSearch = site
        overlay?.panel.setChip(site.name)
        setText("")
    }

    /// Backspace in an empty field leaves the chip.
    public func exitSiteSearch() {
        guard siteSearch != nil else { return }
        siteSearch = nil
        overlay?.panel.setChip(nil)
        query(preventingInline: true)
    }

    // MARK: Deleting suggestions (spec §C)

    /// ⇧Delete, ⌘⌥Delete or the row's ×: removes a history suggestion (an
    /// inline host suggestion removes its host). `false` when the
    /// highlighted row is not removable (the key then edits the text).
    @discardableResult
    public func deleteHighlightedSuggestion() -> Bool {
        guard let index = highlightedIndex else { return false }
        return deleteSuggestion(at: index)
    }

    @discardableResult
    public func deleteSuggestion(at index: Int) -> Bool {
        guard result.matches.indices.contains(index), result.matches[index].isDeletable else { return false }
        let match = result.matches[index]
        guard let profile = sidebar.activeSpace?.profileID else { return false }
        do {
            if let host = HistoryProvider.deletedHost(for: match) {
                try tabs.store.history.delete(host: host, profile: profile)
            } else if let url = match.action.url {
                try tabs.store.history.delete(url: url, profile: profile)
            }
        } catch {
            NSLog("Room: history suggestion not removed: \(error)")
            return false
        }
        // The completion goes with it and does not come back on this text.
        overlay?.panel.field.stringValue = input.mode == .commands ? ">" + input.text : typedText
        query(preventingInline: true)
        if !result.isEmpty { highlight(min(index, result.matches.count - 1)) }
        return true
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
        let rows = result.matches.enumerated().map { index, match in row(for: match, startsGroup: index > 0 && match.group != result.matches[index - 1].group) }
        // No rows: the panel shrinks to the field and clips the list, whose
        // slots keep their last content, so the next keystroke updates rows in
        // place instead of filling empty ones (a query's first keystroke cost
        // 24 ms, mostly SwiftUI drawing rows from nothing, 2.4b measurement).
        // Unchanged rows are not reassigned either.
        if !rows.isEmpty, model.rows != rows { model.rows = rows }
        if !rows.isEmpty, model.highlighted != highlightedIndex { model.highlighted = highlightedIndex }
        overlay.panel.visibleRowCount = rows.count
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
        case .site(let url): icon = .favicon(siteFavicon(url), domain: EntryLabel.domain(url) ?? match.title, dimmed: false)
        case .symbol(let name): icon = .systemName(name)
        }
        let hint: String? = switch match.action {
        case .switchToEntry: "Switch to Tab"
        case .command: "Run"
        default: nil
        }
        return PaletteRow(id: match.id, icon: icon, title: match.title, detail: match.detail, hint: hint, spaceName: match.spaceName,
                          startsGroup: startsGroup, isDeletable: match.isDeletable)
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
        guard isOpen, let field = overlay?.panel.field else { return }
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
        guard isOpen else { return false }
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
            tab()
        case #selector(NSResponder.insertBacktab(_:)):
            cycleGroup(backwards: true)
        case #selector(NSResponder.deleteBackward(_:)):
            // Backspace in an empty field leaves the site-search chip (spec §C).
            guard siteSearch != nil, typedText.isEmpty else { return false }
            exitSiteSearch()
        default:
            return false
        }
        return true
    }

    /// ⇥: from an empty field, commands (`>`, spec §C); after a site-search
    /// keyword, its chip; otherwise the next group.
    public func tab() {
        if typedText.isEmpty, siteSearch == nil {
            setText(">")
            overlay?.panel.field.currentEditor()?.selectedRange = NSRange(location: 1, length: 0)
        } else if siteSearch == nil, input.mode == .normal, let site = SiteSearch.matching(typedText, in: context.siteSearches) {
            enterSiteSearch(site)
        } else {
            cycleGroup(backwards: false)
        }
    }

    public func moveHighlight(_ offset: Int) {
        guard !result.isEmpty else { return }
        let current = highlightedIndex ?? (offset > 0 ? -1 : result.matches.count)
        highlight(min(max(0, current + offset), result.matches.count - 1))
    }

    /// ⇥ / ⇧⇥: the next (previous) group's first row (spec §C).
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
        var matchAction = match?.action
        // Paste & Go reads the clipboard now, and only now.
        if matchAction == .pasteAndGo {
            guard let pasted = pastedAction() else { return }
            matchAction = pasted
        }
        let action = PaletteSemantics.commit(mode: mode, action: matchAction, textUnchanged: isUnchangedEdit, modifier: modifier,
                                             hasCurrent: tabs.currentEntryID != nil)
        if case .enterSiteSearch(let keyword) = action, let site = context.siteSearches.first(where: { $0.keyword == keyword }) {
            return enterSiteSearch(site)
        }
        guard action != .none else { return }
        if let entry = mode.entry { memory.forget(entry) }
        let transition = Self.transition(for: matchAction, siteSearch: siteSearch)
        let window = overlay?.window
        close(restoringFocus: false)
        perform(action, from: mode, transition: transition)
        if let window { focusPage(in: window) }
    }

    /// How a committed page starts, for history (a search results page
    /// weighs less than a typed URL; a keyword search is a keyword).
    static func transition(for action: MatchAction?, siteSearch: SiteSearch?) -> PageTransition {
        guard case .search = action else { return .typed }
        return siteSearch == nil ? .generated : .keyword
    }

    private func perform(_ action: CommitAction, from mode: PaletteMode, transition: PageTransition) {
        switch action {
        case .openTab(let url, let background):
            if background {
                tabs.openBackgroundTab(url: url, transition: transition)
            } else {
                tabs.openNewTab(url: url, transition: transition)
            }
        case .navigateCurrent(let url):
            tabs.navigateSelected(to: url, transition: transition)
        case .reloadCurrent:
            if let page = tabs.current {
                page.reload()
            } else if case .edit(_, let url) = mode, !url.isEmpty {
                tabs.navigateSelected(to: url)
            }
        case .switchTo(let entry, let space):
            if let space, space != sidebar.activeSpaceID { sidebar.showSpace(space) }
            sidebar.select(entry)
        case .runCommand(let id):
            onCommand?(id)
        case .enterSiteSearch, .none:
            break
        }
    }

    #if DEBUG
    /// The panel, while open (captures).
    public var debugPanel: NSView? { overlay?.panel }
    #endif
}
