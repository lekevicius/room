import AppKit
import Chrome
import Design
import Model
import Omnibox
import Store
import SwiftUI

/// A space's theme as the window tints with it: the palette its colours
/// and algorithm produce (`ThemePalette`), and its opacity (0–1).
nonisolated public struct SpaceTheme: Equatable, Sendable {
    public var colors: [String]
    public var opacity: Double

    public init(colors: [String], opacity: Double) {
        self.colors = colors
        self.opacity = opacity
    }
}

extension Space {
    /// `nil` for a space without colours (the neutral window).
    nonisolated public var theme: SpaceTheme? {
        let colors = ThemePalette.colors(themeColors, algorithm: themeAlgorithm)
        return colors.isEmpty ? nil : SpaceTheme(colors: colors, opacity: themeOpacity)
    }
}

/// Spaces in the sidebar (spec §B): the space menu, the creation and edit
/// form, Delete Space with Undo (B-15), Set Profile with the one-time
/// warning, unloading, and drops on the footer's space icons.
extension SidebarController {
    // MARK: Space menu

    /// The space context menu (title row, "…", footer icon), with the
    /// palette's command names (spec §I.10).
    func spaceMenu(_ id: UUID) -> NSMenu? {
        guard let space = sidebar.space(id) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(action(SpaceCommandName.changeName, symbol: .rename) { [weak self] in self?.renameSpace(id) })
        menu.addItem(action(SpaceCommandName.changeIcon, symbol: .changeIcon) { [weak self] in self?.editSpace(id, focus: .icon) })
        menu.addItem(action(SpaceCommandName.editTheme, symbol: .editTheme) { [weak self] in self?.editSpace(id, focus: .theme) })
        let profileItem = NSMenuItem(title: SpaceCommandName.setProfile, action: nil, keyEquivalent: "")
        profileItem.image = Symbol.profile.image()
        let profiles = NSMenu()
        profiles.autoenablesItems = false
        for profile in sidebar.profiles {
            let item = action(profile.name) { [weak self] in self?.setProfile(of: id, to: profile.id) }
            item.state = profile.id == space.profileID ? .on : .off
            profiles.addItem(item)
        }
        profiles.addItem(.separator())
        profiles.addItem(action(SpaceCommandName.newProfile) { [weak self] in self?.newProfile(for: id) })
        profileItem.submenu = profiles
        menu.addItem(profileItem)
        menu.addItem(action(SpaceCommandName.reorderSpaces, symbol: .dragGrip, enabled: sidebar.spaces.count > 1) { [weak self] in
            self?.toasts?.show(Toast(id: "reorder-spaces", symbol: .info, message: "Drag the space icons at the bottom of the sidebar to reorder them"))
        })
        menu.addItem(.separator())
        menu.addItem(action(SpaceCommandName.unloadSpace, symbol: .unload) { [weak self] in self?.unloadSpaces([id]) })
        menu.addItem(action(SpaceCommandName.unloadOtherSpaces, symbol: .unload, enabled: sidebar.spaces.count > 1) { [weak self] in
            guard let self else { return }
            unloadSpaces(sidebar.spaces.map(\.id).filter { $0 != id })
        })
        menu.addItem(action(SpaceCommandName.routingSettings, symbol: .routing, enabled: onRoutingSettings != nil) { [weak self] in
            self?.onRoutingSettings?(nil)
        })
        menu.addItem(.separator())
        menu.addItem(action(CommandName.newSpace, symbol: .newSpace) { [weak self] in self?.newSpace() })
        menu.addItem(action(SpaceCommandName.deleteSpace, symbol: .deleteSpace, enabled: sidebar.spaces.count > 1) { [weak self] in
            self?.confirmDeleteSpace(id)
        })
        return menu
    }

    /// "…" on the title row.
    func showSpaceMenu(at button: NSButton) {
        guard let menu = spaceMenu(tree.spaceID) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 2), in: button)
    }

    // MARK: Rename (spec §B: inline on the title row)

    /// Change Name…: the title row of `id`'s list edits in place (the space is shown first).
    public func renameSpace(_ id: UUID) {
        if id != tree.spaceID { showSpace(id, animated: false) }
        let row = outline.row(forItem: tree.spaceTitle)
        guard row >= 0 else { return }
        outline.scrollRowToVisible(row)
        (outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SpaceTitleCellView)?.beginRename()
    }

    func spaceRenameEnded(_ name: String?) {
        if let name { try? sidebar.updateSpace(tree.spaceID) { $0.name = name } }
        outline.window?.makeFirstResponder(outline)
    }

    // MARK: Form (spec §B)

    /// "+" ▸ New Space, the palette's New Space, a swipe past the last space.
    public func newSpace() { newSpace(revealed: nil) }

    /// `revealed`: the form a swipe already brought on screen.
    func newSpace(revealed: SpaceFormHostingView?) {
        presentSpaceForm(SpaceFormModel(mode: .create, space: nil, profiles: sidebar.profiles,
                                        defaultProfile: tree.space?.profileID ?? sidebar.profiles.first?.id ?? UUID(),
                                        placeholderName: SpaceRules.defaultName(existing: sidebar.spaces.map(\.name))),
                         alreadyShown: revealed)
    }

    /// Change Icon…, Edit Theme…: the form on `id`, focused on that part.
    public func editSpace(_ id: UUID, focus: SpaceFormFocus = .name) {
        guard let space = sidebar.space(id) else { return }
        if id != tree.spaceID { showSpace(id, animated: false) }
        presentSpaceForm(SpaceFormModel(mode: .edit(id), space: space, profiles: sidebar.profiles, defaultProfile: space.profileID,
                                        placeholderName: space.name, focus: focus))
    }

    /// The form takes the list's place: it slides in from the right (or is
    /// already on screen, revealed by a swipe past the last space).
    func presentSpaceForm(_ model: SpaceFormModel, alreadyShown view: SpaceFormHostingView? = nil) {
        if let current = spaceForm, current.view !== view { dismissSpaceForm(animated: false) }
        let hosting = view ?? makeSpaceFormView()
        hosting.rootView = SpaceFormView(model: model, onCommit: { [weak self] in self?.commitSpaceForm() },
                                         onCancel: { [weak self] in self?.dismissSpaceForm(animated: true) },
                                         onThemeChange: { [weak self] in self?.previewTheme() })
        spaceForm = SpaceFormState(view: hosting, model: model, returnSpace: tree.spaceID)
        setHovered(nil)
        if view == nil { bodyView.show(hosting, direction: .forward, animated: true) }
        hosting.window?.makeFirstResponder(hosting)
    }

    /// A form view in the list container (hidden until shown).
    func makeSpaceFormView() -> SpaceFormHostingView {
        let model = SpaceFormModel(mode: .create, space: nil, profiles: sidebar.profiles, defaultProfile: tree.space?.profileID ?? UUID(),
                                   placeholderName: "Space")
        let view = SpaceFormHostingView(rootView: SpaceFormView(model: model, onCommit: {}, onCancel: {}, onThemeChange: {}))
        view.setAccessibilityIdentifier("space-form")
        bodyView.addList(view)
        return view
    }

    /// The window shows the form's colours while they are edited.
    private func previewTheme() {
        guard let model = spaceForm?.model else { return }
        let colors = ThemePalette.colors(model.themeColors, algorithm: model.algorithm)
        onTintChange?(colors.isEmpty ? nil : SpaceTheme(colors: colors, opacity: model.opacity), false)
    }

    /// Enter: creates the space (and its new profile) and shows it, or saves the edit.
    func commitSpaceForm() {
        guard let form = spaceForm else { return }
        let model = form.model
        let name = model.name.trimmingCharacters(in: .whitespaces).isEmpty ? model.placeholderName
            : model.name.trimmingCharacters(in: .whitespaces)
        var profileID = model.profileID
        if let newProfile = model.newProfileName { profileID = sidebar.createProfile(name: newProfile).id }
        switch model.mode {
        case .create:
            guard let space = try? sidebar.createSpace(name: name, profile: profileID, icon: model.icon, themeColors: model.themeColors,
                                                       themeAlgorithm: model.algorithm, themeOpacity: model.opacity),
                  let target = preparedPane(space.id) else { return }
            closeSpaceForm()
            bodyView.show(target.scrollView, direction: .forward, animated: false)
            switchPane(to: target, space: space, direction: .forward, animated: true, slides: false)
            onSpaceCreated?(space)
        case .edit(let id):
            try? sidebar.updateSpace(id) {
                $0.name = name
                $0.icon = model.icon
                $0.themeColors = model.themeColors
                $0.themeAlgorithm = model.algorithm
                $0.themeOpacity = model.opacity
            }
            if profileID != sidebar.space(id)?.profileID { setProfile(of: id, to: profileID) }
            dismissSpaceForm(animated: true)
        }
    }

    /// Esc: back to the list the form replaced; the tint goes back too.
    func dismissSpaceForm(animated: Bool) {
        guard let form = spaceForm else { return }
        let back = preparedPane(form.returnSpace) ?? pane
        bodyView.show(back.scrollView, direction: .backward, animated: animated) { [weak self] in
            guard let self, spaceForm?.view !== form.view else { return }
            bodyView.removeList(form.view)
        }
        spaceForm = nil
        if let space = tree.space { onTintChange?(space.theme, animated) }
        outline.window?.makeFirstResponder(outline)
    }

    /// The form leaves without a slide (a created space takes its place).
    private func closeSpaceForm() {
        guard let form = spaceForm else { return }
        spaceForm = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.medium + 0.05) { [weak self] in
            guard let self, spaceForm?.view !== form.view else { return }
            bodyView.removeList(form.view)
        }
    }

    public var isSpaceFormOpen: Bool { spaceForm != nil }

    // MARK: Delete (spec §B, B-15)

    func confirmDeleteSpace(_ id: UUID) {
        guard let space = sidebar.space(id), sidebar.spaces.count > 1 else { return }
        let count = sidebar.entries.values.filter { $0.spaceID == id && $0.kind != .folder }.count
        let alert = NSAlert()
        alert.messageText = "Delete “\(space.name)”?"
        alert.informativeText = count == 0 ? "The space is empty."
            : "Its \(count) pinned \(count == 1 ? "entry and Today tab go" : "entries and Today tabs go") to the Archive (⇧⌘L)."
        alert.addButton(withTitle: "Delete Space")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard confirm(alert) else { return }
        deleteSpace(id)
    }

    /// Deletes a space with an Undo toast; its entries go to the Archive
    /// (reason `spaceDeleted`, B-15), and Undo takes them back out.
    public func deleteSpace(_ id: UUID) {
        guard let space = sidebar.space(id) else { return }
        let entries = sidebar.entries.values.filter { $0.spaceID == id }.map(\.id)
        for entry in entries { host?.unload(entry) }
        guard let removed = try? sidebar.deleteSpace(id) else { return }
        toasts?.show(Toast(id: "space-deleted", symbol: .deleteSpace, message: "Deleted “\(space.name)”",
                           action: .init(title: "Undo") { [weak self] in
                               guard let self else { return }
                               sidebar.restoreSpace(removed)
                               showSpace(removed.space.id)
                           }, duration: Timing.undoToast))
    }

    // MARK: Profiles (spec §B "Containers")

    /// Set Profile ▸: the space's tabs move to the other cookie jar (and
    /// load again there), after the one-time warning.
    public func setProfile(of spaceID: UUID, to profileID: UUID) {
        guard let space = sidebar.space(spaceID), space.profileID != profileID else { return }
        let moving = sidebar.entries.values.filter { $0.spaceID == spaceID && $0.kind != .folder }
        guard warnCrossProfile(moving.count, into: space, profile: profileID) else { return }
        _ = try? sidebar.setSpaceProfile(spaceID, to: profileID)
    }

    private func newProfile(for spaceID: UUID) {
        let row = outline.row(forItem: tree.spaceTitle)
        let anchor = row >= 0 ? outline.rect(ofRow: row) : outline.visibleRect
        TextEntryPopover.show(title: SpaceCommandName.newProfile, text: "", relativeTo: anchor, of: outline) { [weak self] name in
            guard let self else { return nil }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "A profile needs a name" }
            let profile = sidebar.createProfile(name: trimmed)
            setProfile(of: spaceID, to: profile.id)
            return nil
        }
    }

    /// The one-time "Logins and cookies won't carry over" dialog (spec §B)
    /// before `count` tabs move into a space of another profile. `true`:
    /// go ahead (also when it was confirmed before).
    func warnCrossProfile(_ count: Int, into space: Space, profile: UUID? = nil) -> Bool {
        guard count > 0, !store.settings.settings.crossProfileMoveWarned else { return true }
        let target = profile ?? space.profileID
        let name = sidebar.profiles.first { $0.id == target }?.name ?? "another profile"
        let alert = NSAlert()
        alert.messageText = "Logins and cookies won't carry over"
        alert.informativeText = "“\(space.name)” uses the profile “\(name)”. Tabs moved there load again in it, "
            + "signed out of sites you are signed in to elsewhere. This is shown once."
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")
        guard confirm(alert) else { return false }
        store.settings.update { $0.crossProfileMoveWarned = true }
        return true
    }

    /// Runs a confirmation (tests replace `confirmations`).
    func confirm(_ alert: NSAlert) -> Bool {
        if let confirmations { return confirmations(alert.messageText) }
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Unloading

    /// Unload Space / Unload All Other Spaces: every page of those spaces
    /// closes except the one in the card.
    public func unloadSpaces(_ ids: [UUID]) {
        let spaces = Set(ids)
        let unloaded = sidebar.entries.values.filter { entry in
            entry.spaceID.map(spaces.contains) == true && entry.id != selectedEntryID && pageState(entry.id).isLoaded
        }.map(\.id)
        for id in unloaded { host?.unload(id) }
        for id in unloaded { if let node = tree.displayedNode(for: id) { reconfigure(node) } }
        for target in panes.values where target !== pane && spaces.contains(target.spaceID) { target.isLoaded = false }
    }

    // MARK: Moving entries between spaces

    /// The entries `ids` (not essentials) to `space`: Today tabs on top of
    /// its Today list, pinned entries and folders at the end of its pinned
    /// list. Warns once when they change profile. Returns whether they moved.
    @discardableResult
    func moveEntries(_ ids: [UUID], toSpace spaceID: UUID) -> Bool {
        guard let space = sidebar.space(spaceID) else { return false }
        let moving = ids.compactMap(sidebar.entry).filter { $0.kind != .essential && $0.spaceID != spaceID }
        guard !moving.isEmpty else { return false }
        let crossing = ProfileRules.crossingEntries(moving, into: space, entries: sidebar.entries)
        guard warnCrossProfile(crossing.count, into: space) else { return false }
        if let selected = selectedEntryID, moving.contains(where: { $0.id == selected }),
           let plan = sidebar.closePlan(for: selected, behavior: .close, space: tree.spaceID) {
            applyFallback(plan.fallback)
        }
        let today = moving.filter { $0.kind == .today }.map(\.id)
        let pinned = moving.filter { $0.kind != .today }.map(\.id)
        if !today.isEmpty { try? sidebar.move(today, to: .today(space: spaceID), insertingAt: 0) }
        if !pinned.isEmpty { try? sidebar.move(pinned, to: .pinned(space: spaceID, folder: nil), insertingAt: .max) }
        clearMultiSelection()
        toasts?.show(Toast(id: "moved", symbol: .moveTo, message: "Moved to \(space.name)"))
        return true
    }
}

// MARK: - Drops on space icons (spec §B, §I.7)

extension SidebarController: SpaceIconDropEvents {
    func spaceIconDragOperation(_ info: any NSDraggingInfo, space: UUID) -> NSDragOperation {
        let ids = draggedEntryIDs(info)
        if !ids.isEmpty {
            return ids.compactMap(sidebar.entry).contains { $0.kind != .essential && $0.spaceID != space } ? .move : []
        }
        return URLFixup.dropURLs(from: info.draggingPasteboard).isEmpty ? [] : .copy
    }

    /// Resting on an icon switches to the space; the drag goes on into its list.
    func spaceIconDragHeld(_ space: UUID) {
        guard space != tree.spaceID else { return }
        showSpace(space)
    }

    func spaceIconDrop(_ info: any NSDraggingInfo, space: UUID) -> Bool {
        let ids = draggedEntryIDs(info)
        if !ids.isEmpty { return moveEntries(ids, toSpace: space) }
        let urls = URLFixup.dropURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        for (offset, url) in urls.enumerated() { _ = try? sidebar.addEntry(.today, url: url, space: space, at: offset) }
        if let name = sidebar.space(space)?.name {
            toasts?.show(Toast(id: "added", symbol: .newTab, message: urls.count == 1 ? "Added to \(name)" : "\(urls.count) tabs added to \(name)"))
        }
        return true
    }
}

/// The form on screen and the space it came from.
struct SpaceFormState {
    let view: SpaceFormHostingView
    let model: SpaceFormModel
    let returnSpace: UUID
}

/// Space command names (spec §B menu; the palette uses the same words).
public enum SpaceCommandName {
    public static let changeName = "Change Name…"
    public static let changeIcon = "Change Icon…"
    public static let editTheme = "Edit Theme…"
    public static let setProfile = "Set Profile"
    public static let newProfile = "New Profile…"
    public static let reorderSpaces = "Reorder Spaces"
    public static let unloadSpace = "Unload Space"
    public static let unloadOtherSpaces = "Unload All Other Spaces"
    public static let routingSettings = "Space Routing Settings…"
    public static let deleteSpace = "Delete Space…"
    public static let nextSpace = "Next Space"
    public static let previousSpace = "Previous Space"
}
