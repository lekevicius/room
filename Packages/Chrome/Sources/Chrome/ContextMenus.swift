import AppKit
import Engine

/// What Room adds to a page's context menu (ROADMAP 2.6 task 2): the link
/// and image items Chrome would have, in the palette's words.
public enum RoomMenuAction: Equatable {
    case openLinkInNewTab(URL)
    /// Peek arrives in 2.7; the item is there and disabled until then.
    case openLinkInPeek(URL)
    case copyLink(URL)
    case openImageInNewTab(URL)
    case copyImageAddress(URL)
}

/// Turns the engine's context menu into an `NSMenu` (ROADMAP 2.6 task 2:
/// `MenuModel` → `NSMenu`) with Room's items first. The engine hears exactly
/// once: `select` for one of its items; `cancel` for a Room item or when
/// the menu closes without a choice.
public final class ContextMenu: NSObject, NSMenuDelegate {
    /// Room items carry tags below this; engine ids are kept as they are.
    static let roomTagBase = -1_000_000

    public let menu: NSMenu
    private let model: MenuModel
    private let roomActions: [RoomMenuAction]
    private let perform: (RoomMenuAction) -> Void

    /// `peekAvailable`: whether Open Link in Peek is enabled (Phase 2.7).
    public init(model: MenuModel, element: ContextMenuElement, peekAvailable: Bool = false,
                perform: @escaping (RoomMenuAction) -> Void) {
        self.model = model
        self.perform = perform
        let actions = Self.roomActions(for: element)
        roomActions = actions
        menu = NSMenu()
        super.init()
        menu.autoenablesItems = false
        for (index, action) in actions.enumerated() {
            if index > 0, Self.startsGroup(action) { menu.addItem(.separator()) }
            let item = NSMenuItem(title: Self.title(action), action: #selector(chooseRoom(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Self.roomTagBase - index
            if case .openLinkInPeek = action { item.isEnabled = peekAvailable }
            menu.addItem(item)
        }
        let engineItems = Self.trimmedSeparators(model.items)
        if !actions.isEmpty, !engineItems.isEmpty { menu.addItem(.separator()) }
        add(engineItems, to: menu)
        menu.delegate = self
    }

    /// Room's items for what was clicked: a link's, then an image's.
    static func roomActions(for element: ContextMenuElement) -> [RoomMenuAction] {
        var actions: [RoomMenuAction] = []
        if let link = element.linkURL, link.scheme != "javascript" {
            actions += [.openLinkInNewTab(link), .openLinkInPeek(link), .copyLink(link)]
        }
        if element.mediaType == .image, let source = element.sourceURL, source.scheme != "data" {
            actions += [.openImageInNewTab(source), .copyImageAddress(source)]
        }
        return actions
    }

    static func title(_ action: RoomMenuAction) -> String {
        switch action {
        case .openLinkInNewTab: "Open Link in New Tab"
        case .openLinkInPeek: "Open Link in Peek"
        case .copyLink: "Copy Link"
        case .openImageInNewTab: "Open Image in New Tab"
        case .copyImageAddress: "Copy Image Address"
        }
    }

    private static func startsGroup(_ action: RoomMenuAction) -> Bool {
        if case .openImageInNewTab = action { return true }
        return false
    }

    /// No separator first, last or twice in a row (an engine may leave them where it removed items).
    static func trimmedSeparators(_ items: [MenuItem]) -> [MenuItem] {
        var result: [MenuItem] = []
        for item in items {
            if item.kind == .separator, result.last.map({ $0.kind == .separator }) ?? true { continue }
            result.append(item)
        }
        while result.last?.kind == .separator { result.removeLast() }
        return result
    }

    private func add(_ items: [MenuItem], to menu: NSMenu) {
        for item in items {
            switch item.kind {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let children):
                let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: item.title)
                submenu.autoenablesItems = false
                add(Self.trimmedSeparators(children), to: submenu)
                entry.submenu = submenu
                entry.isEnabled = item.isEnabled
                menu.addItem(entry)
            case .command, .checkbox, .radio:
                let entry = NSMenuItem(title: item.title, action: #selector(chooseEngine(_:)), keyEquivalent: item.keyEquivalent)
                entry.keyEquivalentModifierMask = item.keyEquivalentModifiers
                entry.target = self
                entry.tag = item.id
                entry.isEnabled = item.isEnabled
                entry.state = item.isChecked ? .on : .off
                menu.addItem(entry)
            }
        }
    }

    @objc private func chooseEngine(_ sender: NSMenuItem) {
        model.select(sender.tag)
    }

    @objc private func chooseRoom(_ sender: NSMenuItem) {
        let index = Self.roomTagBase - sender.tag
        guard roomActions.indices.contains(index) else { return }
        model.cancel()
        perform(roomActions[index])
    }

    /// Closed without a choice: the engine hears `cancel`. A choice's action
    /// arrives after this, so the cancel waits for the next turn and is
    /// dropped once the model was answered.
    public func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        DispatchQueue.main.async { [model] in
            MainActor.assumeIsolated { if model.isPending { model.cancel() } }
        }
    }

    /// Shows the menu at `location` in `view` (the page's view, flipped
    /// coordinates as the engine reports them) and keeps itself alive until closed.
    public func popUp(at location: NSPoint, in view: NSView) {
        let point = view.isFlipped ? location : NSPoint(x: location.x, y: view.bounds.height - location.y)
        withExtendedLifetime(self) {
            _ = menu.popUp(positioning: nil, at: point, in: view)
        }
        if model.isPending { model.cancel() }
    }
}
