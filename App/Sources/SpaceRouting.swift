import AppKit
import Chrome
import Design
import Model
import Omnibox
import Sidebar
import Store
import SwiftUI
import Tabs

/// Space routing (spec §B, ROADMAP 4.2 task 2): where links from other apps
/// (`URLInbox`) and links a page opens as a new tab land. The decision is
/// `RoutingRules.route` (Model, pure, tested); this class feeds it the store's
/// rules, the settings and the most recent space, opens the tab and shows the
/// toast "Opened in {space} · Switch" when the tab is not in the shown space.
@MainActor
final class SpaceRouter {
    private let store: RoomStore
    /// Every window (4.8a): one router for the app.
    private let windows: RoomWindows
    /// The key window's (or the last key one's) sidebar.
    private var sidebar: SidebarController? { windows.activeRegular?.sidebar }
    /// The rules compiled once per rule set (regexes included): rebuilt only when the store's rules change.
    private var compiled: (rules: [RoutingRule], evaluator: RoutingRules.Evaluator)?

    #if DEBUG
    /// Every decision (the `routing` spike reads it): the URL, the origin, the space and why.
    private(set) var debugLog: [(url: String, origin: RoutingRules.Origin, decision: RoutingRules.Decision?)] = []
    #endif

    init(store: RoomStore, windows: RoomWindows) {
        self.store = store
        self.windows = windows
    }

    var evaluator: RoutingRules.Evaluator {
        let rules = store.sidebar.routingRules
        if let compiled, compiled.rules == rules { return compiled.evaluator }
        let evaluator = RoutingRules.Evaluator(rules)
        compiled = (rules, evaluator)
        return evaluator
    }

    /// "Most Recent Space" (spec §B; v1 has no Little Arc): the space most
    /// recently activated in the key window, i.e. that window's active space
    /// (with several windows, 4.8a: the key window's, else the last key one's).
    var mostRecentSpace: UUID? { sidebar?.activeSpaceID }

    func decide(_ url: String, from origin: RoutingRules.Origin) -> RoutingRules.Decision? {
        let decision = RoutingRules.route(url, from: origin, evaluator: evaluator, settings: store.settings.settings,
                                          spaces: Set(store.sidebar.spaces.map(\.id)), mostRecentSpace: mostRecentSpace)
        #if DEBUG
        debugLog.append((url, origin, decision))
        #endif
        return decision
    }

    /// A link from another app: the rules, then Settings ▸ Links' default. The
    /// target's window is the one showing that space, else the key window
    /// (4.8a); the tab opens in it as a selected Today tab of the target
    /// space, and the toast offers the switch when that space is not the one
    /// it shows.
    @discardableResult
    func openExternal(_ url: URL) -> UUID? {
        guard let key = windows.activeRegular, let keySidebar = key.sidebar else { return nil }
        let space = decide(url.absoluteString, from: .external)?.space ?? keySidebar.activeSpaceID
        let target = windows.showing(space: space) ?? key
        guard let tabs = target.tabs, let sidebar = target.sidebar else { return nil }
        let id = tabs.openNewTab(url: url.absoluteString, inSpace: space, transition: .link)
        if target !== key { windows.focus(target) }
        if space != sidebar.activeSpaceID { announce(space, in: target) }
        return id
    }

    /// The window an external link would open in for `space` (the routing spike reads it).
    func targetWindow(for space: UUID) -> WindowSession? { windows.showing(space: space) ?? windows.activeRegular }

    /// `TabController.routeLink`: the space a link from a page in `source` belongs in.
    func routePageLink(_ url: String, from source: UUID) -> UUID? {
        guard let decision = decide(url, from: .page(space: source)), decision.moved else { return nil }
        return decision.space
    }

    /// "Opened in {space} · Switch" (spec §F; 5 s with its button, `Timing.toastWithAction`) in
    /// `session`'s window (the active one by default).
    func announce(_ space: UUID, in session: WindowSession? = nil) {
        guard let name = store.sidebar.space(space)?.name, let session = session ?? windows.activeRegular else { return }
        let sidebar = session.sidebar
        session.toasts?.show(Toast(id: "routed", symbol: .routing, message: "Opened in \(name)",
                                   action: Toast.Action(title: "Switch") { [weak sidebar] in sidebar?.showSpace(space) }))
    }

    /// The routing sheet's "Try a URL": where a link from another app with
    /// this text would open, in words.
    func tryURL(_ text: String) -> String {
        guard let url = URLFixup.url(from: text) else { return "" }
        let decision = RoutingRules.route(url, from: .external, evaluator: evaluator, settings: store.settings.settings,
                                          spaces: Set(store.sidebar.spaces.map(\.id)), mostRecentSpace: mostRecentSpace)
        guard let decision, let name = store.sidebar.space(decision.space)?.name else { return "No space to open it in" }
        switch decision.reason {
        case .rule(let id):
            let position = (store.sidebar.routingRules.firstIndex { $0.id == id } ?? 0) + 1
            return "Opens in \(name) (rule \(position))"
        case .chosenDefault, .mostRecentSpace, .sourceSpace:
            return "Opens in the default: \(name)"
        }
    }
}

// MARK: - The routing sheet (ROADMAP 4.2 task 3)

extension AppDelegate {
    /// The space menu's "Space Routing Settings…", Settings ▸ Spaces and the
    /// tab menu's "Add Route for Domain…" (with `newRule` prefilled): a sheet
    /// over `parent` (the browser window unless Settings asked).
    func showRoutingRules(newRule: (host: String, space: UUID)? = nil, over parent: NSWindow? = nil) {
        guard let store, let router = spaceRouter else { return }
        if let sheet = routingSheet {
            // Already open: a prefill starts a new rule in it.
            if let newRule { routingModel?.beginNew(match: .contains, pattern: newRule.host, target: newRule.space) }
            sheet.makeKeyAndOrderFront(nil)
            return
        }
        guard let window = parent ?? windowController?.window else { return }
        let model = RoutingRulesModel(sidebar: store.sidebar, router: router)
        if let newRule { model.beginNew(match: .contains, pattern: newRule.host, target: newRule.space) }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: RoutingSheetMetrics.width, height: RoutingSheetMetrics.height),
                             styleMask: [.titled], backing: .buffered, defer: true)
        sheet.contentViewController = NSHostingController(rootView: RoutingRulesSheet(model: model) { [weak self] in
            self?.closeRoutingRules()
        })
        routingSheet = sheet
        routingModel = model
        window.makeKeyAndOrderFront(nil)
        window.beginSheet(sheet)
    }

    func closeRoutingRules() {
        guard let sheet = routingSheet else { return }
        routingSheet = nil
        routingModel = nil
        sheet.sheetParent?.endSheet(sheet)
    }
}

/// The sheet's size (chosen; looks are Chapter 5's).
enum RoutingSheetMetrics {
    static let width: CGFloat = 560
    static let height: CGFloat = 520
}

/// The routing sheet's state: the rule being edited or added, its inline
/// error, the "Try a URL" text. The list itself is the store's rules
/// (observed), so every change lands at once and is written with the state.
@MainActor @Observable
final class RoutingRulesModel {
    enum Editing: Equatable {
        case none
        case new
        case rule(UUID)
    }

    let sidebar: SidebarStore
    let router: SpaceRouter
    var editing: Editing = .none
    var match: RoutingMatch = .contains
    var pattern = ""
    var target: UUID?
    var selection: UUID?
    var tryText = ""
    /// The store's refusal of the last save (an invalid pattern is shown before it, from `patternError`).
    var saveError: String?

    init(sidebar: SidebarStore, router: SpaceRouter) {
        self.sidebar = sidebar
        self.router = router
    }

    /// The pattern's problem, shown inline while typing; a pattern with one cannot be saved.
    var patternError: String? {
        guard editing != .none, !pattern.isEmpty else { return nil }
        return RoutingRules.validate(match, pattern: pattern)?.message
    }

    var canSave: Bool { editing != .none && target != nil && RoutingRules.validate(match, pattern: pattern) == nil }

    func beginNew(match: RoutingMatch = .contains, pattern: String = "", target: UUID? = nil) {
        editing = .new
        self.match = match
        self.pattern = pattern
        self.target = target ?? router.mostRecentSpace ?? sidebar.spaces.first?.id
        saveError = nil
    }

    func beginEdit(_ id: UUID) {
        guard let rule = sidebar.routingRules.first(where: { $0.id == id }) else { return }
        editing = .rule(id)
        match = rule.match
        pattern = rule.pattern
        target = rule.targetSpaceID
        selection = id
        saveError = nil
    }

    func cancelEdit() {
        editing = .none
        saveError = nil
    }

    /// Saves the rule being edited; `false` (and the reason inline) when the store refuses it.
    @discardableResult
    func save() -> Bool {
        guard let target else { return false }
        do throws(SidebarError) {
            switch editing {
            case .none: return false
            case .new:
                selection = try sidebar.addRoutingRule(match, pattern: pattern, target: target).id
            case .rule(let id):
                let (match, pattern) = (match, pattern)
                try sidebar.updateRoutingRule(id) { rule in
                    rule.match = match
                    rule.pattern = pattern
                    rule.targetSpaceID = target
                }
            }
        } catch {
            switch error {
            case .routingPattern(let problem): saveError = problem.message
            default: saveError = "The rule could not be saved."
            }
            return false
        }
        editing = .none
        saveError = nil
        return true
    }

    func remove(_ id: UUID) {
        if case .rule(id) = editing { editing = .none }
        sidebar.removeRoutingRule(id)
        if selection == id { selection = nil }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = sidebar.routingRules.firstIndex(where: { $0.id == id }) else { return }
        try? sidebar.moveRoutingRule(id, to: index + offset)
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        try? sidebar.updateRoutingRule(id) { $0.enabled = enabled }
    }

    func spaceName(_ id: UUID) -> String { sidebar.space(id)?.name ?? "?" }

    var tryResult: String { tryText.isEmpty ? "" : router.tryURL(tryText) }

    static func describe(_ match: RoutingMatch) -> String {
        switch match {
        case .contains: "URL contains"
        case .equals: "Domain is"
        case .regex: "URL matches regex"
        }
    }
}

/// The sheet (a SwiftUI leaf in an `NSHostingController`, AGENTS.md: the
/// list updates on edits, not per keystroke).
struct RoutingRulesSheet: View {
    @Bindable var model: RoutingRulesModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Space Routing").font(.headline)
            Text("Links from other apps open in the space of the first rule they match, else in the default from Settings ▸ General ▸ Links. "
                 + "With \u{201C}Route links between spaces\u{201D} on, links you open as new tabs from a page follow the rules too.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            rules
            editor
            tryField
            HStack {
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(model.editing == .none ? .defaultAction : nil)
            }
        }
        .padding(20)
        .frame(width: RoutingSheetMetrics.width, height: RoutingSheetMetrics.height)
    }

    @ViewBuilder private var rules: some View {
        let rules = model.sidebar.routingRules
        if rules.isEmpty {
            Text("No rules yet.").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $model.selection) {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(get: { rule.enabled }, set: { model.setEnabled(rule.id, $0) }))
                            .labelsHidden().toggleStyle(.checkbox)
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(RoutingRulesModel.describe(rule.match)).foregroundStyle(.secondary)
                        Text(rule.pattern).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("→ \(model.spaceName(rule.targetSpaceID))").lineLimit(1)
                        Button { model.move(rule.id, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(index == 0).help("Move Up")
                        Button { model.move(rule.id, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(index == rules.count - 1).help("Move Down")
                        Button { model.beginEdit(rule.id) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help("Edit")
                        Button { model.remove(rule.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove")
                    }
                    .opacity(rule.enabled ? 1 : 0.5)
                    .tag(rule.id)
                }
            }
            .frame(maxHeight: .infinity)
        }
        HStack {
            Button("Add Rule") { model.beginNew() }.disabled(model.editing != .none)
            Spacer()
        }
    }

    @ViewBuilder private var editor: some View {
        if model.editing != .none {
            GroupBox(model.editing == .new ? "New rule" : "Edit rule") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("", selection: $model.match) {
                            ForEach(RoutingMatch.allCases, id: \.self) { Text(RoutingRulesModel.describe($0)).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        TextField(model.match == .equals ? "example.com" : model.match == .regex ? "^https://.*\\.example\\.com/" : "github.com/room",
                                  text: $model.pattern)
                            .onSubmit { if model.canSave { model.save() } }
                    }
                    HStack {
                        Picker("Open in", selection: $model.target) {
                            ForEach(model.sidebar.spaces, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .fixedSize()
                        Spacer()
                        Button("Cancel") { model.cancelEdit() }.keyboardShortcut(.cancelAction)
                        Button("Save") { model.save() }.keyboardShortcut(.defaultAction).disabled(!model.canSave)
                    }
                    if let error = model.patternError ?? model.saveError {
                        Text(error).font(.callout).foregroundStyle(Color(nsColor: .systemRed)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(4)
            }
        }
    }

    private var tryField: some View {
        HStack {
            TextField("Try a URL", text: $model.tryText)
            Text(model.tryResult).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
