import AppKit
import Design
import Model
import Sidebar
import Store
import SwiftUI

/// The space window (5.7b, B-122): a space's name, icon, theme, profile and
/// routes in a window of its own, opened from Settings ▸ Spaces (Edit…) and
/// from the space's menu in the sidebar (Space Settings…, Change Icon…, Edit
/// Theme…, Space Routing Settings…), and for a new space ("+" ▸ New Space,
/// the palette, a swipe past the last space). The sidebar holds no editor.
/// The form (`SpaceFormView`, Sidebar) writes on Save or Create and the
/// opening window's tint previews the theme meanwhile; the routes below it
/// are the store's rules for the space, written as they change (as the
/// routing sheet's are). Return saves, Esc or the close button cancels.
final class SpaceWindowController: NSWindowController, NSWindowDelegate {
    let model: SpaceFormModel
    /// The routes section's state (`nil` for a new space).
    let routes: SpaceRoutesModel?
    /// The sidebar that asked: its window previews the theme and shows a created space.
    private weak var sidebar: SidebarController?
    private let onClose: () -> Void
    private var closing = false

    init(model: SpaceFormModel, sidebar: SidebarController, store: SidebarStore, router: SpaceRouter?,
         openRules: @escaping (_ newRuleFor: UUID?, _ over: NSWindow?) -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.routes = model.spaceID.map { SpaceRoutesModel(store: store, space: $0) }
        self.sidebar = sidebar
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SpaceWindowMetrics.width, height: SpaceWindowMetrics.height),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: SpaceWindowMetrics.width, height: SpaceWindowMetrics.minHeight)
        window.setAccessibilityIdentifier("space-window")
        super.init(window: window)
        window.delegate = self
        let routesView: AnyView = routes.map { routes in
            AnyView(SpaceRoutesSection(model: routes) { [weak window] in openRules(nil, window) })
        } ?? AnyView(SpaceRoutesPlaceholder())
        let content = SpaceFormView(model: model, routes: routesView,
                                    onCommit: { [weak self] in self?.commit() },
                                    onCancel: { [weak self] in self?.cancel() },
                                    onThemeChange: { [weak self] in self?.previewTheme() })
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        updateTitle(store: store)
        fit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateTitle(store: SidebarStore) {
        guard let window else { return }
        if let id = model.spaceID, let space = store.space(id) {
            window.title = "\(space.name) — Space Settings"
        } else {
            window.title = "New Space"
        }
    }

    /// At most the display's visible frame (less a margin), centred over the browser window.
    private func fit() {
        guard let window else { return }
        let parent = sidebar?.bodyView.window
        let visible = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        let height = max(SpaceWindowMetrics.minHeight,
                         min(SpaceWindowMetrics.height, visible.height - 2 * SpaceWindowMetrics.screenMargin - titleBarHeight))
        window.setContentSize(NSSize(width: SpaceWindowMetrics.width, height: height))
        var frame = window.frame
        if let parent {
            frame.origin = NSPoint(x: parent.frame.midX - frame.width / 2, y: parent.frame.midY - frame.height / 2)
        } else {
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        }
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        window.setFrame(frame, display: false)
    }

    private var titleBarHeight: CGFloat {
        guard let window else { return 0 }
        return window.frame.height - window.contentLayoutRect.height
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func previewTheme() { sidebar?.previewTheme(model) }

    /// Create or Save; the window closes.
    @discardableResult
    func commit() -> UUID? {
        let id = sidebar?.commitSpaceForm(model)
        finish()
        return id
    }

    /// Cancel, Esc, the close button: nothing written, the tint goes back.
    func cancel() {
        sidebar?.endThemePreview(animated: true)
        finish()
    }

    private func finish() {
        guard !closing else { return }
        closing = true
        window?.close()
        onClose()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }
        sidebar?.endThemePreview(animated: true)
        closing = true
        onClose()
    }
}

/// The routes for one space: the store's rules that send links here, each
/// switched on or off or removed, and a new one added in place; written as
/// they change (the routing sheet's way). The whole list (every space, in
/// order, Try a URL) stays the routing sheet's (All Rules…).
@MainActor @Observable
final class SpaceRoutesModel {
    @ObservationIgnored let store: SidebarStore
    let space: UUID
    var match: RoutingMatch = .contains
    var pattern = ""
    var error: String?

    init(store: SidebarStore, space: UUID) {
        self.store = store
        self.space = space
    }

    var rules: [RoutingRule] { store.routingRules.filter { $0.targetSpaceID == space } }

    /// The typed pattern's problem, shown while typing.
    var patternError: String? { pattern.isEmpty ? nil : RoutingRules.validate(match, pattern: pattern)?.message }

    var canAdd: Bool { !pattern.isEmpty && RoutingRules.validate(match, pattern: pattern) == nil }

    /// Adds the typed rule for this space; `false` when refused.
    @discardableResult
    func add() -> Bool {
        guard canAdd else { return false }
        do throws(SidebarError) {
            _ = try store.addRoutingRule(match, pattern: pattern, target: space)
            pattern = ""
            error = nil
            return true
        } catch {
            self.error = "The route could not be added."
            return false
        }
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) { try? store.updateRoutingRule(id) { $0.enabled = enabled } }

    func remove(_ id: UUID) { store.removeRoutingRule(id) }
}

private struct SpaceRoutesSection: View {
    @Bindable var model: SpaceRoutesModel
    let openAllRules: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Routes").font(.subheadline).foregroundStyle(.secondary)
            Text("Links from other apps that match open in this space.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.rules.isEmpty {
                Text("No routes yet.").font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("space-window-no-routes")
            }
            ForEach(model.rules, id: \.id) { rule in
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(get: { rule.enabled }, set: { model.setEnabled(rule.id, $0) }))
                        .labelsHidden().toggleStyle(.checkbox)
                        .accessibilityLabel("Route enabled")
                    Text(RoutingRulesModel.describe(rule.match)).foregroundStyle(.secondary)
                    Text(rule.pattern).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { model.remove(rule.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Remove").accessibilityLabel("Remove route")
                }
                .opacity(rule.enabled ? 1 : 0.5)
            }
            HStack(spacing: 6) {
                Picker("", selection: $model.match) {
                    ForEach(RoutingMatch.allCases, id: \.self) { Text(RoutingRulesModel.describe($0)).tag($0) }
                }
                .labelsHidden().fixedSize()
                .accessibilityLabel("Route match")
                TextField("", text: $model.pattern, prompt: Text(model.match == .equals ? "example.com" : "github.com/room"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Route pattern")
                    .accessibilityIdentifier("space-window-route-pattern")
                    .onSubmit { model.add() }
                Button("Add") { model.add() }
                    .disabled(!model.canAdd)
            }
            if let message = model.patternError ?? model.error {
                Text(message).font(.caption).foregroundStyle(Color(nsColor: .systemRed)).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("All Rules…", action: openAllRules)
                    .help("Every space's rules in order, and Try a URL")
            }
        }
    }
}

/// A new space has no routes until it exists.
private struct SpaceRoutesPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Routes").font(.subheadline).foregroundStyle(.secondary)
            Text("Routes for links from other apps can be added once the space is created (its Space Settings…).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - AppDelegate

extension AppDelegate {
    /// The space window for `space` (`nil`: a new space), focused on `focus`, previewing in `sidebar`'s window
    /// (the active one by default). One at a time: asking again for another space replaces it.
    func showSpaceWindow(_ space: UUID?, focus: SpaceFormFocus = .name, from sidebar: SidebarController? = nil) {
        guard let store, let sidebar = sidebar ?? self.sidebar else { return }
        if let current = spaceWindow {
            if current.model.spaceID == space, space != nil {
                current.show()
                return
            }
            current.cancel()
        }
        guard let model = sidebar.spaceFormModel(for: space, focus: focus) else { return }
        let controller = SpaceWindowController(model: model, sidebar: sidebar, store: store.sidebar, router: spaceRouter,
                                               openRules: { [weak self] _, window in self?.showRoutingRules(over: window) },
                                               onClose: { [weak self] in self?.spaceWindow = nil })
        spaceWindow = controller
        controller.show()
    }
}
