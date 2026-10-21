import AppKit
import Chrome
import Design
import Model
import Store

/// One window's sidebar for its active space: Essentials grid, the outline
/// (space title → pinned/folders → separator with Clear → Today → New Tab),
/// the header's address field and the footer. It writes the stores (the
/// only writers of the model) and asks its `host` for everything that
/// touches a page. Store changes arrive as `SidebarChange`s; only the rows
/// they name are reloaded (`SidebarTree`).
public final class SidebarController: NSObject {
    /// Goes into `SidebarView.bodyView`.
    public let bodyView = SidebarBodyView()
    /// Goes into `SidebarView.headerView`.
    public let addressField = AddressFieldView()
    /// Goes into `SidebarView.accessoryView`: the extensions in the top bar.
    public let extensionBar = ExtensionBarView()
    /// The footer's downloads button (spec §F); the app drives its ring, badge and popover.
    public var downloadsButton: DownloadsButton { footer.downloadsButton }
    let grid = EssentialsGridView()
    let footer = SidebarFooterView()
    /// The footer's media row (4.6); `setMediaRow` shows it.
    let mediaRow = MediaRowView()
    /// A click on the media row: its action and the entry it shows (the tab controller acts).
    public var onMediaRowAction: ((MediaRowAction, UUID) -> Void)?
    /// One list per space of the window, built ahead of a switch; `pane` is
    /// the active space's (`SpacePane`).
    private(set) var panes: [UUID: SpacePane] = [:]
    private(set) var pane: SpacePane
    private var paneByOutline: [ObjectIdentifier: SpacePane] = [:]
    /// The active space's outline and tree.
    var outline: SidebarOutlineView { pane.outline }
    var tree: SidebarTree { pane.tree }

    public let store: RoomStore
    public let windowID: UUID
    public weak var host: SidebarHost? {
        didSet { reloadAll() }
    }
    public weak var toasts: ToastPresenting?
    /// The active space was renamed, edited or replaced (window title, tint).
    public var onSpaceChange: ((Space) -> Void)?
    /// The window's tint should show `theme` (`nil`: neutral): a switch
    /// (`animated`: crossfaded over the slide's `Motion.medium`), an edited
    /// theme, the form's live preview.
    public var onTintChange: ((_ theme: SpaceTheme?, _ animated: Bool) -> Void)?
    /// Confirmation dialogs (Delete Space, the cross-profile warning) answer
    /// through this instead of a modal alert when set (tests).
    public var confirmations: ((_ message: String) -> Bool)?
    /// The space form while it is on screen (`SidebarSpaces`).
    var spaceForm: SpaceFormState?
    /// A space was created from the form (a toast tells about it while the sidebar is hidden, spec §E).
    public var onSpaceCreated: ((Space) -> Void)?
    /// A space's icon in the footer was clicked (the Library gives way to the spaces first, 4.1a).
    public var onFooterSpaceSelected: (() -> Void)?
    /// A drag of sidebar entries began (`true`) or ended: the card shows its split drop zones meanwhile (spec §D).
    public var onEntryDrag: ((Bool) -> Void)?
    /// The routing sheet (spec §B, 4.2): "Space Routing Settings…" (`nil`), or
    /// "Add Route for Domain…" with a new rule prefilled for `host` targeting `space`.
    public var onRoutingSettings: ((_ newRule: (host: String, space: UUID)?) -> Void)?
    /// "Open in New Window" and the drag out of the window (spec §A.9, 4.8a):
    /// the entry in a new window, at `screenPoint` (the drop point) or cascaded
    /// (`nil`). Without a handler neither is offered.
    public var onOpenInNewWindow: ((_ entry: UUID, _ screenPoint: NSPoint?) -> Void)?
    /// The key equivalent a menu action has now (4.4a, the app's `ShortcutTable`):
    /// action id ("togglePin:") → key and modifiers as `NSMenuItem` takes them,
    /// `("", [])` for none. `nil` (tests) keeps the defaults the menus name.
    public var shortcutKey: ((String) -> (key: String, modifiers: NSEvent.ModifierFlags))?
    /// The two-finger swipe and ⌃+wheel in progress (`SidebarSwipe`).
    var swipe = SpaceSwipe()
    var wheel = SpaceWheel()
    #if DEBUG
    /// Lists loaded since launch (a switch to a prepared space loads none).
    public private(set) var debugPaneLoads = 0
    /// Called at the start (`true`) and end of every space switch (spike timing).
    public var debugSwitchTiming: ((Bool) -> Void)?
    /// How long each list took to build, load and warm up after launch (one run-loop turn each).
    public private(set) var debugPrepareTimes: [Duration] = []
    /// Each part of a switch and how long it took (spike timing).
    public var debugSwitchPhase: ((String, Duration) -> Void)?
    #endif

    private var token: ObservationToken?
    private var flagsMonitor: Any?
    private var hoveredNode: OutlineNode?
    /// A click on a selected, changed entry's title resets after the
    /// double-click interval unless a double-click (rename) follows.
    private var pendingReset: DispatchWorkItem?
    var isCommandHeld = false {
        didSet { if isCommandHeld != oldValue { (hoveredCell as? EntryCellView)?.isCommandHeld = isCommandHeld } }
    }
    /// The ⌘/⇧-click group (spec §A.9).
    var multiSelection = MultiSelection()
    /// A drag over the sidebar (`SidebarDragDrop`).
    var drag: DragState?
    /// The keyboard focus row (spec §I.13); its ring shows after keyboard use.
    var focusedNode: OutlineNode?
    var focusRingVisible = false
    /// Clear's slide-out is running.
    var isClearing = false
    /// Stretches Clear's animation (DEBUG captures of the mid-Clear frame).
    var clearSlowdown: Double = 1
    /// Closed tabs for ⇧⌘T, newest last.
    var closedTabs = ClosedTabStack()
    /// The folder preview waiting for its 500 ms dwell, and the one showing (spec §A.6).
    private var pendingFolderPreview: DispatchWorkItem?
    private weak var folderPreview: NSPopover?
    #if DEBUG
    var debugDragImage: NSView?
    #endif

    var sidebar: SidebarStore { store.sidebar }

    /// The incognito window's sidebar (4.8b): its store is ephemeral, the
    /// tree is the Today list under a note, no essentials, no pinned entries,
    /// no space form; pin and essentials commands do not apply.
    public let isIncognito: Bool

    public init(store: RoomStore, windowID: UUID, incognito: Bool = false) {
        self.store = store
        self.windowID = windowID
        isIncognito = incognito
        let spaceID = Self.activeSpace(store: store, windowID: windowID)
        pane = SpacePane(store: store.sidebar, spaceID: spaceID, windowID: windowID,
                         selectedEntry: store.windows.selectedEntry(space: spaceID, window: windowID))
        super.init()
        bodyView.install(grid: grid, footer: footer)
        if incognito {
            // No essentials, and no space to add or form in an incognito window.
            grid.isHidden = true
            footer.plusButton.isHidden = true
        }
        attach(pane)
        outline.events = self
        bodyView.show(pane.scrollView, direction: .forward, animated: false)
        grid.events = self
        grid.dropEvents = self
        grid.registerForDraggedTypes(Self.acceptedDragTypes)
        footer.onSelectSpace = { [weak self] id in
            self?.onFooterSpaceSelected?()
            self?.showSpace(id)
        }
        footer.spaceMenu = { [weak self] id in self?.spaceMenu(id) }
        footer.onReorderSpace = { [weak self] id, index in try? self?.sidebar.moveSpace(id, to: index) }
        footer.dropEvents = self
        bodyView.onScrollWheel = { [weak self] event in self?.handleSpaceScroll(event) ?? false }
        bodyView.onEmptyDoubleClick = { [weak self] in self?.host?.newTab() }
        bodyView.onOverflowClick = { [weak self] in self?.scrollToSelected() }
        bodyView.onScroll = { [weak self] in self?.updateOverflow() }
        footer.plusMenu = { [weak self] in self?.makePlusMenu() ?? NSMenu() }
        addressField.onActivate = { [weak self] in self?.host?.editAddress() }
        addressField.onCopy = { [weak self] in
            guard let self, let id = selectedEntryID else { return }
            copyURL(of: id, markdown: false)
        }
        token = store.sidebar.observe { [weak self] change in self?.apply(change) }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isCommandHeld = event.modifierFlags.contains(.command)
            return event
        }
        reloadAll()
    }

    isolated deinit {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    private static func activeSpace(store: RoomStore, windowID: UUID) -> UUID {
        if let active = store.windows.window(windowID)?.activeSpaceID, store.sidebar.space(active) != nil { return active }
        return store.sidebar.spaces.first?.id ?? UUID()
    }

    // MARK: State

    public var activeSpaceID: UUID { tree.spaceID }
    public var activeSpace: Space? { tree.space }

    /// `container` in this window: a Today list without a window is this window's (schema v9).
    func local(_ container: Container) -> Container {
        if case .today(let space, nil) = container { return .today(space: space, window: windowID) }
        return container
    }

    public var selectedEntryID: UUID? {
        store.windows.selectedEntry(space: tree.spaceID, window: windowID)
    }

    // MARK: Panes

    private func attach(_ pane: SpacePane) {
        let outline = pane.outline
        pane.tree.isIncognito = isIncognito
        // Registered first: setting the data source makes AppKit ask for rows at once.
        panes[pane.spaceID] = pane
        paneByOutline[ObjectIdentifier(outline)] = pane
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(outlineClicked(_:))
        outline.doubleAction = #selector(outlineDoubleClicked(_:))
        outline.registerForDraggedTypes(Self.acceptedDragTypes)
        pane.scrollView.spaceScroll = { [weak self] event in self?.handleSpaceScroll(event) ?? false }
        bodyView.addList(pane.scrollView)
    }

    private func detach(_ pane: SpacePane) {
        panes[pane.spaceID] = nil
        paneByOutline[ObjectIdentifier(pane.outline)] = nil
        pane.outline.dataSource = nil
        pane.outline.delegate = nil
        bodyView.removeList(pane.scrollView)
    }

    func pane(for outlineView: NSOutlineView) -> SpacePane {
        paneByOutline[ObjectIdentifier(outlineView)] ?? pane
    }

    /// The selected entry of `pane`'s space in this window.
    func selectedEntry(in pane: SpacePane) -> UUID? {
        store.windows.selectedEntry(space: pane.spaceID, window: windowID)
    }

    /// The list of `spaceID`, built and loaded if it is not (the cost a
    /// switch would otherwise pay: `SpacePane`).
    @discardableResult
    func preparedPane(_ spaceID: UUID) -> SpacePane? {
        guard sidebar.space(spaceID) != nil else { return nil }
        let target: SpacePane
        if let existing = panes[spaceID] {
            target = existing
        } else {
            target = SpacePane(store: sidebar, spaceID: spaceID, windowID: windowID, selectedEntry: store.windows.selectedEntry(space: spaceID, window: windowID))
            attach(target)
        }
        if !target.isLoaded { load(target) }
        return target
    }

    private func load(_ target: SpacePane) {
        #if DEBUG
        debugPaneLoads += 1
        #endif
        target.tree.selectedEntry = selectedEntry(in: target)
        target.tree.reloadAll()
        bodyView.layoutOffscreen(target.scrollView)
        target.outline.reloadData()
        target.outline.expandItem(nil, expandChildren: true)
        target.isLoaded = true
        updatePill(in: target, animated: false)
        if let id = selectedEntry(in: target), let node = target.tree.displayedNode(for: id) {
            let row = target.outline.row(forItem: node)
            if row >= 0 { target.outline.scrollRowToVisible(row) }
        }
    }

    /// Builds the lists of every space not built yet, one per run-loop turn
    /// (after launch and when spaces are added), so switching never builds one.
    public func prepareSpaces() {
        guard let next = sidebar.spaces.first(where: { panes[$0.id]?.isLoaded != true }) else { return }
        #if DEBUG
        let start = ContinuousClock.now
        defer { debugPrepareTimes.append(ContinuousClock.now - start) }
        #endif
        if let target = preparedPane(next.id), target !== pane { bodyView.warmUp(target.scrollView) }
        DispatchQueue.main.async { [weak self] in self?.prepareSpaces() }
    }

    // MARK: Switching spaces (spec §B)

    /// Shows `spaceID`: its list slides in over `Motion.medium` (crossfade
    /// under Reduce Motion) from the side its icon is on, its remembered
    /// selection comes back into the card, and the window's tint follows
    /// (`onSpaceSwitch`).
    public func showSpace(_ spaceID: UUID, animated: Bool = true) {
        guard spaceID != tree.spaceID, let space = sidebar.space(spaceID), let target = preparedPane(spaceID) else { return }
        let fromIndex = sidebar.spaces.firstIndex { $0.id == tree.spaceID } ?? 0
        let toIndex = sidebar.spaces.firstIndex { $0.id == spaceID } ?? 0
        switchPane(to: target, space: space, direction: SlideDirection(from: fromIndex, to: toIndex), animated: animated)
    }

    /// ⌥⌘→ (`offset` 1) / ⌥⌘← (−1), wrapping around (spec §B).
    public func showAdjacentSpace(_ offset: Int) {
        guard let target = SpaceRules.adjacent(to: tree.spaceID, offset: offset, in: sidebar.spaces) else { return }
        guard let space = sidebar.space(target.id), let next = preparedPane(target.id) else { return }
        // Wrapping keeps the direction of the key: → always slides in from the right.
        switchPane(to: next, space: space, direction: offset > 0 ? .forward : .backward, animated: true)
    }

    /// ⌃1…⌃9, ⌃0 (spec §B).
    public func showSpace(digit: Int) {
        guard let space = SpaceRules.space(forDigit: digit, in: sidebar.spaces) else { return }
        showSpace(space.id)
    }

    /// `slides` false: a swipe already moves the lists (`SidebarSwipe`).
    func switchPane(to target: SpacePane, space: Space, direction: SlideDirection, animated: Bool, slides: Bool = true) {
        #if DEBUG
        debugSwitchTiming?(true)
        defer { debugSwitchTiming?(false) }
        #endif
        #if DEBUG
        var mark = ContinuousClock.now
        func phase(_ name: String) {
            let now = ContinuousClock.now
            debugSwitchPhase?(name, now - mark)
            mark = now
        }
        #else
        func phase(_ name: String) {}
        #endif
        let previousProfile = tree.space?.profileID
        setHovered(nil)
        clearMultiSelection()
        focusedNode = nil
        outline.events = nil
        pane = target
        outline.events = self
        store.windows.setActiveSpace(space.id, window: windowID)
        // The remembered selection's row may peek out of a collapsed folder.
        if target.tree.selectedEntry != selectedEntryID { perform(target.tree.selectionChanged(to: selectedEntryID), in: target, animated: false) }
        updatePill(in: target, animated: false)
        phase("list")
        if slides { bodyView.show(target.scrollView, direction: direction, animated: animated) }
        phase("slide")
        footer.setSpaces(sidebar.spaces, active: space.id, animated: animated)
        phase("footer")
        if space.profileID != previousProfile { reloadGrid(animated: animated) } else { refreshTiles() }
        phase("essentials")
        updateAddressField()
        updateOverflow()
        onTintChange?(space.theme, animated)
        onSpaceChange?(space)
        phase("tint_title")
        if let id = selectedEntryID, let entry = sidebar.entry(id) { host?.activate(entry) } else { host?.deactivate() }
        phase("card")
    }


    /// The host's pages changed (loaded, loading, audible, favicon…).
    public func pageStateDidChange(_ ids: Set<UUID>) {
        for id in ids {
            if let node = tree.displayedNode(for: id) { reconfigure(node) }
            if let tile = grid.tile(for: id) { configureTile(tile) }
        }
        if let selected = selectedEntryID, ids.contains(selected) { updateAddressField() }
    }

    func pageState(_ id: UUID) -> EntryPageState { host?.pageState(for: id) ?? .unloaded }

    /// Loaded and away from its stored URL (spec §A.1 state 3).
    func isChanged(_ entry: Entry) -> Bool {
        pageState(entry.id).isLoaded && EntryRules.isChanged(entry)
    }

    // MARK: Reload

    /// Rebuilds the active list, the grid and the footer from the store; the
    /// other spaces' lists load again before they are next shown.
    func reloadAll() {
        for other in panes.values where other !== pane { other.isLoaded = false }
        tree.selectedEntry = selectedEntryID
        tree.reloadAll()
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        pane.isLoaded = true
        reloadGrid(animated: false)
        footer.setSpaces(sidebar.spaces, active: tree.spaceID, animated: false)
        updateAddressField()
        bodyView.needsLayout = true
        bodyView.layoutSubtreeIfNeeded()
        updatePill(animated: false)
        if let id = selectedEntryID, let node = tree.displayedNode(for: id) {
            let row = outline.row(forItem: node)
            if row >= 0 { outline.scrollRowToVisible(row) }
        }
        if let node = focusedNode, outline.row(forItem: node) < 0 { focusedNode = nil }
        retainMultiSelection()
        updateOverflow()
        if let space = tree.space { onSpaceChange?(space) }
    }

    /// Restore Sidebar… (4.1b): the store's state was replaced wholesale.
    /// Every list is dropped and the window's active space is built again
    /// from the store, as at launch; the ⇧⌘T stack is emptied (its entries
    /// belong to the state that was replaced).
    public func reloadFromStore() {
        setHovered(nil)
        clearMultiSelection()
        focusedNode = nil
        closedTabs = ClosedTabStack()
        outline.events = nil
        for other in Array(panes.values) { detach(other) }
        let spaceID = Self.activeSpace(store: store, windowID: windowID)
        pane = SpacePane(store: sidebar, spaceID: spaceID, windowID: windowID, selectedEntry: store.windows.selectedEntry(space: spaceID, window: windowID))
        attach(pane)
        outline.events = self
        bodyView.show(pane.scrollView, direction: .forward, animated: false)
        if store.windows.window(windowID)?.activeSpaceID != spaceID { store.windows.setActiveSpace(spaceID, window: windowID) }
        reloadAll()
        onTintChange?(tree.space?.theme, false)
        DispatchQueue.main.async { [weak self] in self?.prepareSpaces() }
    }

    private func apply(_ change: SidebarChange) {
        if change.reloaded { return reloadFromStore() }
        if change.removedSpaces.contains(tree.spaceID) || tree.space == nil {
            let next = store.windows.window(windowID)?.activeSpaceID.flatMap { sidebar.space($0) }?.id ?? sidebar.spaces.first?.id
            for removed in change.removedSpaces where removed != tree.spaceID { if let gone = panes[removed] { detach(gone) } }
            let old = pane
            if let next, next != old.spaceID, let space = sidebar.space(next), let target = preparedPane(next) {
                switchPane(to: target, space: space, direction: .backward, animated: true)
            }
            if old !== pane, sidebar.space(old.spaceID) == nil {
                // After its slide out (the list is still on screen until then).
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.medium + 0.05) { [weak self] in
                    guard let self, sidebar.space(old.spaceID) == nil, panes[old.spaceID] === old else { return }
                    detach(old)
                }
            }
            return
        }
        for removed in change.removedSpaces { if let gone = panes[removed] { detach(gone) } }
        // The other spaces' lists follow without animation (they are off screen).
        for other in panes.values where other !== pane && other.isLoaded {
            if let selected = other.tree.selectedEntry, sidebar.entry(selected) == nil { other.tree.selectedEntry = nil }
            perform(other.tree.update(for: change), in: other, animated: false)
        }
        // The selected entry may have been removed; the window store drops it.
        if let selected = tree.selectedEntry, sidebar.entry(selected) == nil { tree.selectedEntry = nil }
        let update = tree.update(for: change)
        perform(update)
        if update.essentialsChanged { reloadGrid(animated: true) }
        for id in change.entries { if let tile = grid.tile(for: id) { configureTile(tile) } }
        if !change.spaces.isEmpty || !change.removedSpaces.isEmpty {
            footer.setSpaces(sidebar.spaces, active: tree.spaceID, animated: true)
            // A new space's list is built in the background before it is first shown.
            if sidebar.spaces.contains(where: { panes[$0.id] == nil }) { DispatchQueue.main.async { [weak self] in self?.prepareSpaces() } }
        }
        if update.spaceChanged, let space = tree.space {
            onSpaceChange?(space)
            if spaceForm == nil { onTintChange?(space.theme, true) }
        }
        updateAddressField()
        retainMultiSelection()
        if let node = focusedNode, outline.row(forItem: node) < 0 { focusedNode = nil }
        updateFocusRing()
        updateOverflow()
    }

    /// Applies row removals/insertions (150 ms ease-out fade, spec §I.1) and reconfigures.
    private func perform(_ update: SidebarTree.Update) {
        perform(update, in: pane, animated: true)
    }

    private func perform(_ update: SidebarTree.Update, in target: SpacePane, animated: Bool) {
        let outline = target.outline
        if update.changesRows {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? Motion.standard : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                outline.beginUpdates()
                for removal in update.removals {
                    outline.removeItems(at: removal.indexes, inParent: removal.parent, withAnimation: animated ? .effectFade : [])
                }
                for insertion in update.insertions {
                    outline.insertItems(at: insertion.indexes, inParent: insertion.parent, withAnimation: animated ? .effectFade : [])
                }
                outline.endUpdates()
            }
            for node in update.insertedExpandable { outline.expandItem(node, expandChildren: true) }
        }
        for node in update.reconfigure { reconfigure(node, in: target) }
        updatePill(in: target, animated: animated)
        if update.changesRows, target === pane {
            outline.refreshHover()
            // Again once the rows' slide has settled (B-109): row(at:) then answers the final layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.standard + 0.05) { [weak outline = target.outline] in
                outline?.refreshHover()
            }
        }
    }

    func reconfigure(_ node: OutlineNode) { reconfigure(node, in: pane) }

    private func reconfigure(_ node: OutlineNode, in target: SpacePane) {
        let row = target.outline.row(forItem: node)
        guard row >= 0, let view = target.outline.view(atColumn: 0, row: row, makeIfNecessary: false) else { return }
        // A row that became a split's group row (or stopped being one) needs the other cell.
        if case .entry(let id) = node.kind, (view is SplitGroupCellView) != (sidebar.splitGroup(of: id) != nil) {
            target.outline.reloadData(forRowIndexes: [row], columnIndexes: [0])
            return
        }
        configure(view, for: node, in: target)
    }

    private func configure(_ view: NSView, for node: OutlineNode, in target: SpacePane) {
        switch (node.kind, view) {
        case (.entry(let id), let cell as SplitGroupCellView):
            guard let group = sidebar.splitGroup(of: id) else { return }
            let selected = selectedEntry(in: target)
            let segments = sidebar.splitMembers(group.id).map { member in
                SplitSegmentModel(entry: member, page: pageState(member.id), isChanged: isChanged(member))
            }
            let level = target.outline.level(forItem: node)
            let depth = sidebar.entry(id)?.kind == .today ? 0 : max(0, level - 1)
            cell.configure(SplitRowModel(group: group.id, segments: segments,
                                         focused: selected.flatMap { group.members.contains($0) ? $0 : nil }, depth: depth))
        case (.entry, let cell as EntryCellView):
            guard let entry = target.tree.entry(node) else { return }
            let level = target.outline.level(forItem: node)
            cell.configure(EntryRowModel(entry: entry, page: pageState(entry.id), isSelected: entry.id == selectedEntry(in: target),
                                         isChanged: isChanged(entry), depth: entry.kind == .today ? 0 : max(0, level - 1)))
        case (.spaceTitle, let cell as SpaceTitleCellView):
            if isIncognito {
                cell.configureNote(SidebarTree.incognitoNote)
            } else if let space = target.tree.space {
                cell.configure(space)
            }
        case (.separator, let cell as SeparatorCellView):
            cell.configure(todayCount: sidebar.today(space: target.spaceID, window: windowID).count)
        default:
            break
        }
    }

    // MARK: Selection

    /// Makes `id` the selected entry of this window's space (or none) and
    /// shows its page.
    public func select(_ id: UUID?) {
        let previous = selectedEntryID
        store.windows.select(id, space: tree.spaceID, window: windowID)
        if let id, sidebar.entry(id) != nil {
            try? sidebar.markActive(id)
            if let entry = sidebar.entry(id) { host?.activate(entry) }
        } else if id == nil {
            host?.deactivate()
        }
        selectionDidChange(from: previous)
    }

    /// Makes `id` the remembered selection of `spaceID` in this window
    /// without showing that space (a link routed to a space that is not
    /// shown, spec §B): the space brings it into the card when it is next
    /// shown. In the shown space it is `select(_:)`.
    public func selectInBackground(_ id: UUID, space spaceID: UUID) {
        guard spaceID != tree.spaceID else { return select(id) }
        store.windows.select(id, space: spaceID, window: windowID)
        try? sidebar.markActive(id)
        if let target = panes[spaceID], target.isLoaded {
            perform(target.tree.selectionChanged(to: id), in: target, animated: false)
            updatePill(in: target, animated: false)
        }
    }

    private func selectionDidChange(from previous: UUID?) {
        perform(tree.selectionChanged(to: selectedEntryID))
        for id in [previous, selectedEntryID].compactMap({ $0 }) {
            if let node = tree.displayedNode(for: id) { reconfigure(node) }
            if let tile = grid.tile(for: id) { configureTile(tile) }
        }
        updateAddressField()
        updateOverflow()
    }

    func updatePill(animated: Bool) { updatePill(in: pane, animated: animated) }

    private func updatePill(in target: SpacePane, animated: Bool) {
        let outline = target.outline
        var selectedRow = -1
        let selected = selectedEntry(in: target)
        if let id = selected, let node = target.tree.displayedNode(for: id) {
            selectedRow = outline.row(forItem: node)
        }
        outline.enumerateAvailableRowViews { rowView, row in
            (rowView as? SidebarRowView)?.isSelectedEntry = row == selectedRow
        }
        guard selectedRow >= 0 else {
            outline.pill.move(to: nil, entry: nil, animated: false)
            return
        }
        outline.pill.move(to: SidebarRowView.pillRect(in: outline.rect(ofRow: selectedRow)), entry: selected, animated: animated)
    }

    private func updateAddressField() {
        let entry = selectedEntryID.flatMap(sidebar.entry)
        let url = entry?.currentURL
        addressField.setURL(url, isSecure: url?.hasPrefix("https://") == true)
    }

    // MARK: Essentials

    private func reloadGrid(animated: Bool) {
        let ids = tree.essentialIDs
        grid.setEntries(ids, animated: animated)
        refreshTiles()
        bodyView.needsLayout = true
    }

    /// Tiles show the active space's selection (essentials are shared by its profile's spaces).
    private func refreshTiles() {
        for id in tree.essentialIDs { if let tile = grid.tile(for: id) { configureTile(tile) } }
    }

    func configureTile(_ tile: EssentialTileView) {
        guard let entry = sidebar.entry(tile.entryID) else { return }
        tile.configure(entry: entry, page: pageState(entry.id), isSelected: entry.id == selectedEntryID,
                       isChanged: isChanged(entry))
    }

    // MARK: Clicks (spec §A.2)

    @objc private func outlineClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? OutlineNode else { return }
        let event = NSApp.currentEvent
        switch node.kind {
        case .newTab:
            host?.newTab()
        case .spaceTitle:
            // A click on the name renames the space inline (spec §B); the incognito note is not a space.
            if !isIncognito, let event, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SpaceTitleCellView,
               cell.nameRect.insetBy(dx: -2, dy: -4).contains(cell.convert(event.locationInWindow, from: nil)) {
                cell.beginRename()
            }
        case .separator:
            break
        case .entry(let rowID):
            // A split's row: the segment under the pointer is the pane clicked (spec §D).
            let id = splitMember(atRow: row, event: event) ?? rowID
            guard let entry = sidebar.entry(id) else { return }
            if event?.modifierFlags.contains(.option) == true, altClick(id) { return }
            let gesture = Self.gesture(event)
            setFocus(node, ring: false)
            if entry.kind == .folder {
                if gesture == .primary { try? sidebar.setFolderCollapsed(id, !entry.isCollapsed) }
                return
            }
            if gesture == .primary { clearMultiSelection() }
            let outcome = ClickRules.outcome(gesture, kind: entry.kind, isSelected: id == selectedEntryID,
                                             isChanged: isChanged(entry), isLoaded: pageState(id).isLoaded)
            if outcome == .reset, let event, clickIsOnTitle(event, row: row) {
                // The first click of a rename double-click must not reset the page.
                let work = DispatchWorkItem { [weak self] in self?.perform(.reset, on: id) }
                pendingReset = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
            } else {
                perform(outcome, on: id)
            }
        }
    }

    static func gesture(_ event: NSEvent?) -> ClickRules.Gesture {
        let flags = event?.modifierFlags ?? []
        if flags.contains(.command) { return .command }
        if flags.contains(.shift) { return .shift }
        return .primary
    }

    @objc private func outlineDoubleClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? OutlineNode, let id = node.entryID,
              let event = NSApp.currentEvent, clickIsOnTitle(event, row: row) else { return }
        pendingReset?.cancel()
        pendingReset = nil
        beginRename(id)
    }

    private func clickIsOnTitle(_ event: NSEvent, row: Int) -> Bool {
        guard let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCellView else { return false }
        let point = cell.convert(event.locationInWindow, from: nil)
        return cell.titleRect.insetBy(dx: 0, dy: -4).contains(point)
    }

    func perform(_ outcome: ClickRules.Outcome, on id: UUID) {
        switch outcome {
        case .select: select(id)
        case .reset: reset(id)
        case .separate: separate(id)
        case .unload: unload(id)
        case .remove: removeEntry(id, undoable: true)
        case .close: close(id)
        case .toggleSelection: toggleSelection(id)
        case .extendSelection: extendSelection(id)
        case .none: break
        }
    }

    func reset(_ id: UUID) {
        try? sidebar.resetToStoredURL(id)
        if let entry = sidebar.entry(id) { host?.reset(entry) }
        pageStateDidChange([id])
    }

    func unload(_ id: UUID) {
        host?.unload(id)
        pageStateDidChange([id])
    }

    /// ⌘-click "Separate from pinned tab": the page continues as a new Today
    /// tab, the permanent entry goes back to its stored URL, unloaded.
    func separate(_ id: UUID) {
        guard let entry = sidebar.entry(id), let live = entry.liveURL,
              let tab = try? sidebar.addEntry(.today, url: live, title: entry.liveTitle, space: tree.spaceID, window: windowID) else { return }
        host?.separate(id, into: tab)
        try? sidebar.resetToStoredURL(id)
        select(tab.id)
        pageStateDidChange([id, tab.id])
    }

    /// Close per `NavigationRules.closeSteps` (Today tab: switch away, unload,
    /// remove; permanent entries follow the ⌘W preference, spec §A.3). What
    /// it closed goes on the ⇧⌘T stack: the removed entry, or a permanent
    /// entry's page (its URL before the reset).
    public func close(_ id: UUID, behavior: PermanentCloseBehavior? = nil) {
        let behavior = behavior ?? store.settings.settings.permanentCloseBehavior
        // A split's pane: only that pane closes (spec §D).
        if let group = sidebar.splitGroup(of: id) { return closePane(id, group: group, behavior: behavior) }
        guard let before = sidebar.entry(id),
              let plan = sidebar.closePlan(for: id, behavior: behavior, space: tree.spaceID, window: windowID) else { return }
        let hadPage = pageState(id).isLoaded
        if plan.steps.contains(.switchAway), selectedEntryID == id { applyFallback(plan.fallback) }
        // A Today tab's entry goes only once its page closed: "stay" in the
        // page's beforeunload dialog keeps both (spec §A.3, 2.6a).
        if plan.steps.contains(.remove), plan.steps.contains(.unload), hadPage, let host {
            host.closePage(id) { [weak self] closed in
                guard let self, closed, self.sidebar.entry(id) != nil else { return }
                if let removed = try? self.sidebar.remove(id) { self.closedTabs.push(.removed([removed])) }
                self.pageStateDidChange([id])
            }
            pageStateDidChange([id])
            return
        }
        if plan.steps.contains(.unload) { host?.unload(id) }
        if plan.steps.contains(.reset) {
            try? sidebar.resetToStoredURL(id)
            // A page that stays loaded (`reset` alone) goes back to the stored URL too.
            if !plan.steps.contains(.unload), let entry = sidebar.entry(id) { host?.reset(entry) }
        }
        if plan.steps.contains(.remove) {
            if let removed = try? sidebar.remove(id) { closedTabs.push(.removed([removed])) }
        } else if hadPage, before.liveURL != nil, plan.steps.contains(.unload) || plan.steps.contains(.reset) {
            closedTabs.push(.page(before))
        }
        pageStateDidChange([id])
    }

    func applyFallback(_ fallback: CloseFallback?) {
        switch fallback {
        case .select(let next): select(next)
        case .newTodayTabAndPalette:
            select(nil)
            host?.newTab()
        case .emptyState, nil: select(nil)
        }
    }

    /// Removes a permanent entry (folders: children move up, spec §A.6), with Undo.
    func removeEntry(_ id: UUID, undoable: Bool) {
        guard let entry = sidebar.entry(id) else { return }
        if selectedEntryID == id, let plan = sidebar.closePlan(for: id, behavior: .close, space: tree.spaceID, window: windowID) {
            applyFallback(plan.fallback)
        }
        host?.unload(id)
        guard let removed = try? sidebar.remove(id) else { return }
        guard undoable else { return }
        let title = EntryLabel.title(entry)
        toasts?.show(Toast(id: "removed", symbol: .info, message: "Removed “\(title)”",
                           action: .init(title: "Undo") { [weak self] in self?.sidebar.restore([removed]) }))
    }

    // MARK: Rename (spec §I.9)

    /// Starts the inline rename of a row (double-click, Enter, menu).
    public func beginRename(_ id: UUID) {
        guard let node = tree.displayedNode(for: id) else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.scrollRowToVisible(row)
        (outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? EntryCellView)?.beginRename()
    }

    private func pulse(_ id: UUID) {
        guard !Motion.reduceMotion, let node = tree.displayedNode(for: id) else { return }
        let row = outline.row(forItem: node)
        guard row >= 0, let rowView = outline.rowView(atRow: row, makeIfNecessary: false) else { return }
        rowView.wantsLayer = true
        guard let layer = rowView.layer else { return }
        let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        func scale(_ factor: CGFloat) -> NSValue {
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, factor, factor, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            return NSValue(caTransform3D: transform)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [scale(1), scale(Motion.renamePulseScale), scale(1)]
        animation.duration = Motion.standard * 2
        layer.add(animation, forKey: "pulse")
    }

    // MARK: Copy

    func copyURL(of id: UUID, markdown: Bool) {
        guard let entry = sidebar.entry(id), let url = entry.currentURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if markdown {
            pasteboard.setString(EntryLabel.markdown(title: EntryLabel.title(entry), url: url), forType: .string)
            toasts?.show(Toast(id: "copy-markdown", symbol: .copyMarkdown, message: "Copied as Markdown"))
        } else {
            pasteboard.setString(url, forType: .string)
            if let link = URL(string: url) { pasteboard.setString(link.absoluteString, forType: .URL) }
            toasts?.show(Toast(id: "copy-url", symbol: .copyURL, message: "Copied URL"))
        }
    }

    // MARK: Hover

    private var hoveredCell: NSView? {
        guard let hoveredNode else { return nil }
        let row = outline.row(forItem: hoveredNode)
        return row >= 0 ? outline.view(atColumn: 0, row: row, makeIfNecessary: false) : nil
    }

    func setHoveredForDebug(_ node: OutlineNode?) { setHovered(node) }
    /// The hovered row's entry (tests).
    var hoveredEntryForTesting: UUID? { hoveredNode?.entryID }

    func setHovered(_ node: OutlineNode?) {
        guard node !== hoveredNode else { return }
        setHover(false, on: hoveredNode)
        hoveredNode = node
        setHover(true, on: node)
        scheduleFolderPreview(for: node)
    }

    /// Resting on a collapsed folder for 500 ms opens its preview (spec §A.6).
    private func scheduleFolderPreview(for node: OutlineNode?) {
        pendingFolderPreview?.cancel()
        pendingFolderPreview = nil
        guard folderPreview == nil, drag == nil, let id = node?.entryID, let folder = sidebar.entry(id), folder.kind == .folder,
              folder.isCollapsed, !descendants(of: id).isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, hoveredNode === node, drag == nil else { return }
            showFolderPreview(id)
        }
        pendingFolderPreview = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DropRules.holdDelay, execute: work)
    }

    /// The preview popover beside a folder's row.
    public func showFolderPreview(_ id: UUID) {
        guard let folder = sidebar.entry(id), let node = tree.displayedNode(for: id) else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        let items = descendants(of: id).map { entry in
            FolderPreviewController.Item(id: entry.id, title: EntryLabel.title(entry), url: entry.currentURL,
                                         domain: EntryLabel.domain(entry.currentURL) ?? EntryLabel.title(entry))
        }
        folderPreview = FolderPreviewController.show(folderName: EntryLabel.title(folder), items: items,
                                                     relativeTo: SidebarRowView.pillRect(in: outline.rect(ofRow: row)), of: outline) {
            [weak self] entry in
            // Opens inside the collapsed folder: the entry peeks under it (Arc).
            self?.clearMultiSelection()
            self?.select(entry)
        }
    }

    private func setHover(_ hovering: Bool, on node: OutlineNode?) {
        guard let node else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        (outline.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView)?.isHovered = hovering
        switch outline.view(atColumn: 0, row: row, makeIfNecessary: false) {
        case let cell as EntryCellView:
            cell.isCommandHeld = hovering && isCommandHeld
            cell.isHovered = hovering
            if !hovering { cell.isHoveringIcon = false }
        case let cell as SpaceTitleCellView:
            cell.isHovered = hovering
        default:
            break
        }
    }
}

// MARK: - NSOutlineView data source and delegate

extension SidebarController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        pane(for: outlineView).tree.children(of: item as? OutlineNode).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        pane(for: outlineView).tree.children(of: item as? OutlineNode)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? OutlineNode).map(pane(for: outlineView).tree.isExpandable) ?? false
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool { false }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        switch (item as? OutlineNode)?.kind {
        case .spaceTitle: SidebarMetrics.spaceTitleRowHeight
        case .separator: SidebarMetrics.separatorRowHeight
        default: SidebarMetrics.rowHeight
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? OutlineNode)?.entryID != nil
    }

    /// AppKit never changes the selection by itself: it mirrors the
    /// multi-selection, which clicks change through `ClickRules`.
    public func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        multiSelectionRows
    }

    // MARK: Drag and drop (SidebarDragDrop)

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let id = (item as? OutlineNode)?.entryID, let entry = sidebar.entry(id), !isClearing else { return nil }
        if let group = sidebar.splitGroup(of: id) { return pasteboardItem(forSplit: group) }
        return pasteboardItem(for: entry)
    }

    public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                            forItems draggedItems: [Any]) {
        session.animatesToStartingPositionsOnCancelOrFail = true
        liftDraggingItems(session)
        draggingSessionWillBegin(session, ids: draggedItems.compactMap { ($0 as? OutlineNode)?.entryID })
    }

    public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                            operation: NSDragOperation) {
        let ids = drag?.ids ?? []
        draggingSessionEnded()
        dragEnded(ids, at: screenPoint, operation: operation)
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
                            proposedChildIndex index: Int) -> NSDragOperation {
        let operation = outlineDragUpdated(info)
        // The target is ours (`DropRules`); AppKit only needs a valid one and draws nothing.
        if !operation.isEmpty { outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex) }
        return operation
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        outlineAcceptDrop(info)
    }

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        // Reused: allocating and attaching a row view per scrolled-in row was a third of its cost (2.2b profile).
        let rowView = outlineView.makeView(withIdentifier: SidebarRowView.identifier, owner: self) as? SidebarRowView ?? SidebarRowView()
        rowView.identifier = SidebarRowView.identifier
        switch (item as? OutlineNode)?.kind {
        case .spaceTitle, .separator: rowView.showsHover = false
        default: rowView.showsHover = true
        }
        return rowView
    }

    public func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let rowView = rowView as? SidebarRowView, let node = outlineView.item(atRow: row) as? OutlineNode else { return }
        let isActive = pane(for: outlineView) === pane
        let target = pane(for: outlineView)
        rowView.isSelectedEntry = node.entryID != nil && node.entryID == selectedEntry(in: target).map(target.tree.rowEntry)
        rowView.isHovered = isActive && node === hoveredNode
        rowView.isMultiSelected = isActive && (node.entryID.map(multiSelection.contains) ?? false)
        rowView.showsFocusRing = isActive && focusRingVisible && node === focusedNode && outlineView.window?.firstResponder === outlineView
            && outlineView.window?.isKeyWindow == true
        rowView.isDropTarget = false
        rowView.alphaValue = node.entryID.map { drag?.ids.contains($0) == true } == true ? SidebarMetrics.draggedRowAlpha : 1
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }
        let view: NSView
        switch node.kind {
        case .entry(let id) where sidebar.splitGroup(of: id) != nil:
            view = outlineView.makeView(withIdentifier: SplitGroupCellView.identifier, owner: self) as? SplitGroupCellView ?? SplitGroupCellView()
        case .entry:
            let cell = outlineView.makeView(withIdentifier: EntryCellView.identifier, owner: self) as? EntryCellView ?? EntryCellView()
            cell.actions = self
            cell.isHovered = node === hoveredNode
            view = cell
        case .spaceTitle:
            let cell = outlineView.makeView(withIdentifier: SpaceTitleCellView.identifier, owner: self) as? SpaceTitleCellView
                ?? SpaceTitleCellView()
            cell.onToggle = { [weak self] in self?.togglePinnedCollapsed() }
            cell.onMore = { [weak self] button in self?.showSpaceMenu(at: button) }
            cell.onRenameEnded = { [weak self] name in self?.spaceRenameEnded(name) }
            view = cell
        case .separator:
            let cell = outlineView.makeView(withIdentifier: SeparatorCellView.identifier, owner: self) as? SeparatorCellView
                ?? SeparatorCellView()
            cell.clearButton.target = self
            cell.clearButton.action = #selector(clearToday(_:))
            view = cell
        case .newTab:
            view = outlineView.makeView(withIdentifier: NewTabCellView.identifier, owner: self) ?? NewTabCellView()
        }
        configure(view, for: node, in: pane(for: outlineView))
        return view
    }

    func togglePinnedCollapsed() {
        try? sidebar.updateSpace(tree.spaceID) { $0.pinnedCollapsed.toggle() }
    }
}

// MARK: - Row and tile events

extension SidebarController: SidebarOutlineEvents, EntryRowActions, EssentialTileEvents, EssentialsDropEvents {
    func outlineMiddleClicked(row: Int) {
        guard let rowID = (outline.item(atRow: row) as? OutlineNode)?.entryID else { return }
        let id = splitMember(atRow: row, event: NSApp.currentEvent) ?? rowID
        guard let entry = sidebar.entry(id) else { return }
        perform(ClickRules.outcome(.middle, kind: entry.kind, isSelected: id == selectedEntryID, isChanged: isChanged(entry),
                                   isLoaded: pageState(id).isLoaded), on: id)
    }

    func outlineEmptyAreaDoubleClicked() { host?.newTab() }

    func outlineMenu(forRow row: Int) -> NSMenu? {
        guard let node = outline.item(atRow: row) as? OutlineNode else { return nil }
        if node.kind == .spaceTitle { return isIncognito ? nil : spaceMenu(tree.spaceID) }
        guard let rowID = node.entryID else { return nil }
        return menu(forClicked: splitMember(atRow: row, event: NSApp.currentEvent) ?? rowID)
    }

    func outlineHoverChanged(row: Int?) {
        setHovered(row.flatMap { outline.item(atRow: $0) as? OutlineNode })
    }

    func resetButtonClicked(_ entry: UUID) {
        if isCommandHeld, entry == selectedEntryID { separate(entry) } else { reset(entry) }
    }

    func closeButtonClicked(_ entry: UUID) { close(entry) }

    func audioButtonClicked(_ entry: UUID) {
        host?.setMuted(!pageState(entry).isMuted, entry: entry)
        pageStateDidChange([entry])
    }

    func renameEnded(_ id: UUID, label: String?, committed: Bool) {
        if committed, let entry = sidebar.entry(id) {
            let before = entry.customLabel
            try? sidebar.rename(id, to: label)
            if sidebar.entry(id)?.customLabel != before {
                pulse(id)
                toasts?.show(Toast(id: "renamed", symbol: .rename, message: entry.kind == .folder ? "Folder renamed" : "Tab renamed"))
            }
        }
        outline.window?.makeFirstResponder(outline)
    }

    func tileClicked(_ id: UUID, gesture: ClickRules.Gesture) {
        guard let entry = sidebar.entry(id) else { return }
        if gesture == .primary { clearMultiSelection() }
        perform(ClickRules.outcome(gesture, kind: entry.kind, isSelected: id == selectedEntryID, isChanged: isChanged(entry),
                                   isLoaded: pageState(id).isLoaded), on: id)
    }

    func tileResetClicked(_ id: UUID) { resetButtonClicked(id) }

    func tileMenu(_ id: UUID) -> NSMenu? { menu(forClicked: id) }
}

/// The sidebar below the header: Essentials, the lists (one per space,
/// only the active one shown, with the overflow indicators at their edges,
/// spec §I.11), the footer. Space switches slide the lists (spec §B); the
/// grid and the footer stay put. A double-click on its empty background is
/// a new tab (spec §F).
public final class SidebarBodyView: NSView {
    private(set) var grid: EssentialsGridView?
    private(set) var footer: SidebarFooterView?
    /// Clips the lists while they slide.
    let listContainer = ListContainerView()
    /// The list on screen (a space's scroll view, or the new-space form).
    private(set) weak var activeList: NSView?
    private let overflowTop = OverflowIndicatorView(edge: .top)
    private let overflowBottom = OverflowIndicatorView(edge: .bottom)
    var onEmptyDoubleClick: (() -> Void)?
    var onOverflowClick: (() -> Void)? {
        didSet {
            overflowTop.onClick = onOverflowClick
            overflowBottom.onClick = onOverflowClick
        }
    }
    /// The active list scrolled.
    var onScroll: (() -> Void)?
    /// Scroll events over the grid, the footer and the gaps (space swipes, ⌃+wheel).
    var onScrollWheel: ((NSEvent) -> Bool)?
    /// Stretches the slide (DEBUG captures of a mid-slide frame).
    var slideSlowdown: Double = 1
    /// A card above the footer at the rows' width (2.8b: the first-run card); the list ends above it.
    /// It moves with the sidebar into the hidden sidebar's overlay.
    public var accessoryView: NSView? {
        didSet {
            guard accessoryView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let accessoryView { addSubview(accessoryView) }
            needsLayout = true
        }
    }
    /// The accessory's height at a width (its content wraps).
    public var accessoryHeight: ((CGFloat) -> CGFloat)?
    /// The media row (4.6) directly above the footer, in the spaces view and
    /// the Library alike; hidden while nothing plays elsewhere.
    var mediaRowView: NSView? {
        didSet {
            guard mediaRowView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let mediaRowView { addSubview(mediaRowView) }
            needsLayout = true
        }
    }
    /// A view in place of the spaces view (the essentials, the lists, the
    /// accessory) between the header and the footer, which stay: the Library
    /// (⇧⌘L, 4.1a). `nil` shows the spaces again.
    public var replacementView: NSView? {
        didSet {
            guard replacementView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            let replaced = replacementView != nil
            grid?.isHidden = replaced
            listContainer.isHidden = replaced
            accessoryView?.isHidden = replaced
            if let replacementView {
                addSubview(replacementView)
                setOverflow(above: false, below: false)
            }
            needsLayout = true
        }
    }
    /// Finishes the running slide at once (a new switch starts from the end state).
    private var finishSlide: (() -> Void)?
    /// The lists under a two-finger swipe: the current one and its neighbour.
    private var interactive: (current: NSView, neighbour: NSView?, sign: CGFloat)?

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { true }

    func install(grid: EssentialsGridView, footer: SidebarFooterView) {
        self.grid = grid
        self.footer = footer
        footer.onEmptyDoubleClick = { [weak self] in self?.onEmptyDoubleClick?() }
        listContainer.wantsLayer = true
        listContainer.layer?.masksToBounds = true
        addSubview(grid)
        addSubview(listContainer)
        addSubview(footer)
        addSubview(overflowTop)
        addSubview(overflowBottom)
    }

    /// Adds a list (hidden until shown).
    func addList(_ view: NSView) {
        guard view.superview !== listContainer else { return }
        view.isHidden = true
        view.wantsLayer = true
        view.frame = listContainer.bounds
        listContainer.addSubview(view)
        if let scrollView = view as? NSScrollView {
            NotificationCenter.default.addObserver(self, selector: #selector(clipViewScrolled(_:)),
                                                   name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }
    }

    func removeList(_ view: NSView) {
        if let scrollView = view as? NSScrollView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }
        if activeList === view { activeList = nil }
        view.removeFromSuperview()
    }

    @objc private func clipViewScrolled(_ notification: Notification) {
        guard (notification.object as? NSView)?.superview === activeList else { return }
        onScroll?()
    }

    func setOverflow(above: Bool, below: Bool) {
        overflowTop.isHidden = !above
        overflowBottom.isHidden = !below
    }

    // MARK: Switching lists (spec §B, §I.1)

    /// Shows `incoming` in place of the active list: both slide horizontally
    /// by the list's width over `Motion.medium`, ease-out (`direction`: which
    /// side the new one comes from); under Reduce Motion they crossfade.
    /// Compositor-only (layer animations on lists that already have their
    /// rows), so the first frame does not wait on any reload.
    func show(_ incoming: NSView, direction: SlideDirection, animated: Bool, completion: (() -> Void)? = nil) {
        finishSlide?()
        cancelInteractive()
        let outgoing = activeList
        activeList = incoming
        incoming.frame = listContainer.bounds
        incoming.isHidden = false
        guard animated, let outgoing, outgoing !== incoming, listContainer.bounds.width > 0, window != nil else {
            if let outgoing, outgoing !== incoming { outgoing.isHidden = true }
            needsLayout = true
            completion?()
            return
        }
        let width = listContainer.bounds.width
        animate(incoming, from: Self.offsetTransform(width * direction.sign), to: CATransform3DIdentity,
                outgoing, from: CATransform3DIdentity, to: Self.offsetTransform(-width * direction.sign), completion: completion)
    }

    private func animate(_ incoming: NSView, from inStart: CATransform3D, to inEnd: CATransform3D,
                         _ outgoing: NSView, from outStart: CATransform3D, to outEnd: CATransform3D, completion: (() -> Void)?) {
        guard let inLayer = incoming.layer, let outLayer = outgoing.layer else { return }
        var finished = false
        let finish: () -> Void = { [weak self, weak incoming, weak outgoing] in
            guard !finished else { return }
            finished = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            outgoing?.isHidden = self?.activeList !== outgoing
            for layer in [incoming?.layer, outgoing?.layer].compactMap({ $0 }) {
                layer.removeAnimation(forKey: "slide")
                layer.removeAnimation(forKey: "fade")
                layer.transform = CATransform3DIdentity
                layer.opacity = 1
            }
            CATransaction.commit()
            self?.finishSlide = nil
            completion?()
        }
        finishSlide = finish
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { finish() }
        if Motion.reduceMotion {
            // Crossfade only (spec §I.1).
            inLayer.transform = CATransform3DIdentity
            outLayer.transform = CATransform3DIdentity
            inLayer.add(basic("opacity", from: 0, to: 1), forKey: "fade")
            outLayer.add(basic("opacity", from: 1, to: 0), forKey: "fade")
            outLayer.opacity = 0
        } else {
            inLayer.transform = inEnd
            outLayer.transform = outEnd
            inLayer.add(basic("transform", from: NSValue(caTransform3D: inStart), to: NSValue(caTransform3D: inEnd)), forKey: "slide")
            outLayer.add(basic("transform", from: NSValue(caTransform3D: outStart), to: NSValue(caTransform3D: outEnd)), forKey: "slide")
        }
        CATransaction.commit()
    }

    private static func basic(_ keyPath: String, from: Any, to: Any) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = Motion.medium
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }

    private func basic(_ keyPath: String, from: Any, to: Any) -> CABasicAnimation {
        let animation = Self.basic(keyPath, from: from, to: to)
        animation.duration *= slideSlowdown
        return animation
    }

    static func offsetTransform(_ x: CGFloat) -> CATransform3D { CATransform3DMakeTranslation(x, 0, 0) }

    // MARK: Two-finger swipe (spec §B)

    /// The lists follow the fingers: `progress` in list widths (+ = towards
    /// the neighbour on the right); `neighbour` slides in from that side
    /// (`nil` at an end: the current list rubber-bands alone).
    func trackSwipe(current: NSView, neighbour: NSView?, progress: CGFloat) {
        finishSlide?()
        let sign: CGFloat = progress >= 0 ? 1 : -1
        if let interactive, interactive.current !== current || interactive.neighbour !== neighbour {
            cancelInteractive()
        }
        interactive = (current, neighbour, sign)
        let width = listContainer.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current.layer?.transform = Self.offsetTransform(-progress * width)
        if let neighbour {
            if neighbour.isHidden {
                neighbour.frame = listContainer.bounds
                neighbour.isHidden = false
            }
            neighbour.layer?.transform = Self.offsetTransform((sign - progress) * width)
        }
        CATransaction.commit()
    }

    /// Ends a swipe: to the neighbour (it becomes the active list) or back.
    func endSwipe(toNeighbour: Bool, completion: (() -> Void)? = nil) {
        guard let (current, neighbour, sign) = interactive else {
            completion?()
            return
        }
        interactive = nil
        let width = listContainer.bounds.width
        let currentNow = current.layer?.presentation()?.transform ?? current.layer?.transform ?? CATransform3DIdentity
        if toNeighbour, let neighbour {
            let neighbourNow = neighbour.layer?.presentation()?.transform ?? neighbour.layer?.transform ?? CATransform3DIdentity
            activeList = neighbour
            animate(neighbour, from: neighbourNow, to: CATransform3DIdentity, current, from: currentNow,
                    to: Self.offsetTransform(-sign * width), completion: completion)
        } else if let neighbour {
            let neighbourNow = neighbour.layer?.presentation()?.transform ?? neighbour.layer?.transform ?? CATransform3DIdentity
            activeList = current
            animate(current, from: currentNow, to: CATransform3DIdentity, neighbour, from: neighbourNow,
                    to: Self.offsetTransform(sign * width), completion: completion)
        } else {
            CATransaction.begin()
            CATransaction.setCompletionBlock { completion?() }
            current.layer?.transform = CATransform3DIdentity
            current.layer?.add(basic("transform", from: NSValue(caTransform3D: currentNow),
                                          to: NSValue(caTransform3D: CATransform3DIdentity)), forKey: "slide")
            CATransaction.commit()
        }
    }

    private func cancelInteractive() {
        guard let (current, neighbour, _) = interactive else { return }
        interactive = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current.layer?.transform = CATransform3DIdentity
        neighbour?.layer?.transform = CATransform3DIdentity
        if let neighbour, neighbour !== activeList { neighbour.isHidden = true }
        CATransaction.commit()
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onEmptyDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        if onScrollWheel?(event) == true { return }
        super.scrollWheel(with: event)
    }

    public override func layout() {
        super.layout()
        let inset = SidebarMetrics.rowHorizontalInset
        let width = max(0, bounds.width - 2 * inset)
        let gridHeight = grid?.height(forWidth: width) ?? 0
        // The sidebar view leaves `addressRowGap` above the body: the grid starts at its top.
        grid?.frame = NSRect(x: inset, y: 0, width: width, height: gridHeight)
        let top = gridHeight > 0 ? (grid?.frame.maxY ?? 0) + SidebarMetrics.essentialsGap : 0
        let footerHeight = SidebarMetrics.footerHeight
        footer?.frame = NSRect(x: 0, y: bounds.height - footerHeight, width: bounds.width, height: footerHeight)
        var bodyBottom = bounds.height - footerHeight
        if let mediaRowView, !mediaRowView.isHidden {
            let height = MediaRowMetrics.height
            mediaRowView.frame = NSRect(x: inset, y: bodyBottom - height, width: width, height: height)
            bodyBottom = mediaRowView.frame.minY - MediaRowMetrics.gap
        }
        if let replacementView {
            replacementView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bodyBottom))
            return
        }
        var listBottom = bodyBottom
        if let accessoryView, !accessoryView.isHidden {
            let height = ceil(accessoryHeight?(width) ?? accessoryView.fittingSize.height)
            accessoryView.frame = NSRect(x: inset, y: listBottom - FirstRunMetrics.gapAboveFooter - height, width: width, height: height)
            listBottom = accessoryView.frame.minY - FirstRunMetrics.gapAboveList
        }
        listContainer.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, listBottom - top))
        for list in listContainer.subviews {
            list.frame = listContainer.bounds
            guard !list.isHidden, let outline = (list as? NSScrollView)?.documentView as? NSOutlineView else { continue }
            outline.sizeLastColumnToFit()
            outline.tile()
        }
        let hit = SidebarMetrics.overflowHitHeight
        overflowTop.frame = NSRect(x: 0, y: listContainer.frame.minY, width: bounds.width, height: hit)
        overflowBottom.frame = NSRect(x: 0, y: listContainer.frame.maxY - hit, width: bounds.width, height: hit)
        onScroll?()
    }

    /// The hidden sidebar showed again (its overlay): the overflow lines are measured again.
    public override func viewDidUnhide() {
        super.viewDidUnhide()
        // After the pass that shows it, when every ancestor has its frame.
        DispatchQueue.main.async { [weak self] in self?.onScroll?() }
    }

    /// Makes a hidden list's visible rows and draws them once, transparent
    /// and under the active list, so its first switch only composites
    /// (row views are made on first display; the first switch to each space
    /// took ~100 ms without this, Phase 2.5 spike).
    func warmUp(_ list: NSView) {
        guard list !== activeList, list.isHidden, window != nil else { return }
        list.frame = listContainer.bounds
        list.alphaValue = 0
        list.isHidden = false
        listContainer.addSubview(list, positioned: .below, relativeTo: activeList)
        list.layoutSubtreeIfNeeded()
        list.displayIfNeeded()
        list.isHidden = true
        list.alphaValue = 1
    }

    /// Lays out a list that is not on screen yet (a pane built ahead of a switch).
    func layoutOffscreen(_ list: NSView) {
        list.frame = listContainer.bounds
        guard let outline = (list as? NSScrollView)?.documentView as? NSOutlineView else { return }
        outline.sizeLastColumnToFit()
        outline.tile()
    }
}

/// The clipping box the lists slide in.
final class ListContainerView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

#if DEBUG
/// Hooks for the app's DEBUG snapshot runner (no UI driving in sessions).
extension SidebarController {
    /// Shows the hover state of an entry's row or tile as if the pointer were on it
    /// (`onIcon`: over the favicon / reset icon; `command`: ⌘ held).
    public func debugHover(_ id: UUID?, onIcon: Bool = false, command: Bool = false) {
        setHoveredForDebug(id.flatMap { tree.displayedNode(for: $0) })
        isCommandHeld = command
        if let id, let node = tree.displayedNode(for: id) {
            let row = outline.row(forItem: node)
            if row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCellView {
                cell.isHoveringIcon = onIcon
                cell.isCommandHeld = command
            }
        }
    }

    /// B-108: the pill's frame and the selected row's pill rect, in the outline's coordinates.
    public var debugPillAndRow: (pill: NSRect, row: NSRect)? {
        guard let id = selectedEntryID, let node = tree.displayedNode(for: id), !outline.pill.isHidden else { return nil }
        let row = outline.row(forItem: node)
        return row >= 0 ? (outline.pill.frame, SidebarRowView.pillRect(in: outline.rect(ofRow: row))) : nil
    }

    /// B-109: holds the outline's pointer still over `id`'s row (nil: the real pointer again)
    /// and re-evaluates hover as a layout change does; the hovered entry after it.
    @discardableResult
    public func debugStillPointer(over id: UUID?) -> UUID? {
        if let id, let node = tree.displayedNode(for: id) {
            let rect = outline.rect(ofRow: outline.row(forItem: node))
            let point = NSPoint(x: rect.midX, y: rect.midY)
            outline.pointerLocation = { point }
        } else if id == nil {
            outline.pointerLocation = { [weak outline] in
                guard let outline, let window = outline.window else { return nil }
                return outline.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            }
        }
        outline.refreshHover()
        return hoveredNode?.entryID
    }

    /// The hovered row's entry and whether its cell shows the close button.
    public var debugHoveredEntry: (id: UUID?, closeShown: Bool) {
        guard let node = hoveredNode, let id = node.entryID else { return (nil, false) }
        let row = outline.row(forItem: node)
        let cell = row >= 0 ? outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCellView : nil
        return (id, cell?.debugCloseButtonShown ?? false)
    }

    /// Rebuilds everything from the store (timing the full reload).
    public func debugReloadAll() { reloadAll() }

    /// The row's cell of an entry on screen, if it has one (4.7b: the reader glyph).
    public func debugRowView(for id: UUID) -> NSView? {
        guard let node = tree.displayedNode(for: id) else { return nil }
        let row = outline.row(forItem: node)
        return row >= 0 ? outline.view(atColumn: 0, row: row, makeIfNecessary: false) : nil
    }

    /// The context menu a right-click on `id` shows (4.4a: its keys follow the shortcut table).
    public func debugContextMenu(for id: UUID) -> NSMenu? { menu(for: id) }

    /// The menu a right-click on `id` opens: the group's with a multi-selection (5.0b).
    public func debugClickedMenu(for id: UUID) -> NSMenu? { menu(forClicked: id) }

    /// The cell class showing `id`'s row (a split's pane: its group row).
    public func debugRowCellKind(_ id: UUID) -> String {
        guard let node = tree.displayedNode(for: id) else { return "none" }
        let row = outline.row(forItem: node)
        guard row >= 0, let view = outline.view(atColumn: 0, row: row, makeIfNecessary: true) else { return "none" }
        return String(describing: type(of: view))
    }

    /// Whether `id` has a row of its own.
    public func debugIsListed(_ id: UUID) -> Bool { outline.row(forItem: tree.node(for: id)) >= 0 }

    /// The rows the outline shows, as kinds (4.8b: the incognito tree), and whether the essentials grid shows.
    public var debugRowKinds: [String] {
        (0..<outline.numberOfRows).compactMap { row in
            switch (outline.item(atRow: row) as? OutlineNode)?.kind {
            case .spaceTitle?: isIncognito ? "note" : "space"
            case .separator?: "separator"
            case .newTab?: "newtab"
            case .entry(let id)?: sidebar.entry(id)?.kind.rawValue ?? "entry"
            case nil: nil
            }
        }
    }
    public var debugEssentialsShown: Bool { !grid.isHidden }
    /// The Essentials grid's tiles in order, as this window draws them (5.0b).
    public var debugEssentialIDs: [UUID] { grid.order }

    /// The title an entry's row draws now (4.8a: a rename in another window shows here at once).
    public func debugRowTitle(for id: UUID) -> String? {
        guard let node = tree.displayedNode(for: id) else { return nil }
        let row = outline.row(forItem: node)
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? EntryCellView else { return nil }
        return cell.titleField.stringValue
    }

    /// A drag of `id` from this sidebar ending at `screenPoint` with no target (4.8a's drag out; the
    /// mouse drag itself is by hand).
    public func debugDragEnded(_ id: UUID, at screenPoint: NSPoint) { dragEnded([id], at: screenPoint, operation: []) }

    /// Spaces whose list is built and loaded.
    public var debugPreparedSpaces: Int { panes.values.filter(\.isLoaded).count }

    /// Reloads `space`'s list from scratch off screen (what a switch would
    /// cost without prepared lists: `SpacePane`).
    public func debugReloadPane(_ space: UUID) {
        guard let target = panes[space], target !== pane else { return }
        target.isLoaded = false
        preparedPane(space)
    }

    /// Space switches run `factor` times slower (a mid-slide capture).
    public func debugSetSlideSlowdown(_ factor: Double) { bodyView.slideSlowdown = factor }

    /// The footer's name label as if the pointer were on `space`'s icon.
    public func debugHoverSpaceIcon(_ space: UUID?) { footer.debugHover(space) }

    /// The space form on screen, as Edit Theme… or New Space shows it.
    public func debugShowSpaceForm(edit space: UUID?) {
        if let space { editSpace(space, focus: .theme) } else { newSpace() }
    }

    public func debugDismissSpaceForm() { dismissSpaceForm(animated: false) }

    public var debugOutline: NSOutlineView { outline }

    /// ⌘-click on an entry (multi-selection).
    public func debugToggleSelection(_ id: UUID) { toggleSelection(id) }

    public func debugClearMultiSelection() { clearMultiSelection() }

    /// Keyboard focus with its ring, as after ↑/↓.
    public func debugFocus(_ id: UUID?) {
        outline.window?.makeFirstResponder(outline)
        setFocus(id.flatMap { tree.displayedNode(for: $0) }, ring: id != nil)
    }

    /// The feedback of a drag of `ids` with the pointer over `id`'s row at
    /// `fraction` of its height (`held`: after the 500 ms hold): the dimmed
    /// source rows, the insertion line or drop-onto highlight, and the
    /// lifted image at the pointer (drawn in the outline; a real drag draws
    /// it in its own window). `nil` ends it.
    public func debugShowDrag(_ ids: [UUID]?, over id: UUID? = nil, fraction: CGFloat = 0.1, held: Bool = false) {
        debugDragImage?.removeFromSuperview()
        debugDragImage = nil
        guard let ids, let id, let node = tree.displayedNode(for: id) else {
            if let dragged = drag?.ids { setDragging(dragged, dimmed: false) }
            drag = nil
            hideDropFeedback()
            return
        }
        drag = DragState(ids: ids)
        setDragging(ids, dimmed: true)
        let row = outline.row(forItem: node)
        let rowRect = outline.rect(ofRow: row)
        let single = ids.count == 1 && sidebar.entry(ids[0])?.kind != .folder
        let target = DropRules.target(debugDropRow(row), at: row, rowCount: outline.numberOfRows, fraction: fraction, held: held,
                                      space: tree.spaceID, single: single)
        showFeedback(for: target)
        guard let first = ids.first, let entry = sidebar.entry(first) else { return }
        let pill = SidebarRowView.pillRect(in: rowRect)
        let image = DragImage.row(entry, page: pageState(first), size: pill.size, appearance: outline.effectiveAppearance)
        var frame = DragImage.frame(for: image, around: pill)
        // Under the pointer, grabbed near its top edge (the line above stays visible).
        frame.origin.x += 8
        frame.origin.y = rowRect.minY + rowRect.height * fraction - DragImage.margin + 6
        let view = NSImageView(frame: frame)
        view.image = image
        view.imageScaling = .scaleNone
        outline.addSubview(view)
        debugDragImage = view
    }

    private func debugDropRow(_ row: Int) -> DropRules.Row? {
        guard let node = outline.item(atRow: row) as? OutlineNode, let id = node.entryID, let entry = sidebar.entry(id) else {
            return nil
        }
        let depth = entry.kind == .today ? 0 : max(0, outline.level(forRow: row) - 1)
        return .entry(id: id, kind: entry.kind, container: entry.container, index: entry.position, depth: depth,
                      showsChildren: entry.kind == .folder && !tree.children(of: node).isEmpty)
    }

    /// Clear's animation runs `factor` times slower (for a mid-Clear capture).
    public func debugSetClearSlowdown(_ factor: Double) { clearSlowdown = factor }

    /// The grid's "12/12" badge, as over a full grid during a drag.
    public func debugShowEssentialsFull(_ show: Bool) {
        grid.showFullBadge(show ? "\(essentialsCount)/\(EntryRules.essentialsCap)" : nil)
    }

    /// The folder preview's window, if one is showing.
    public var debugFolderPreviewWindow: NSWindow? { folderPreview?.contentViewController?.view.window }

    /// The empty grid's drop slot, as during a drag.
    public func debugShowDropSlot(_ show: Bool) {
        grid.showsDropSlot = show
        bodyView.needsLayout = true
        bodyView.layoutSubtreeIfNeeded()
    }
}
#endif
