import AppKit
import Chrome
import Integration
import Model
import Omnibox
import Store
import SwiftUI

/// Settings (⌘,), v0 (ROADMAP 2.8 task 2): a toolbar-tabbed window as in
/// every Mac app, one SwiftUI leaf per section (PLAN §4 UI framework). The
/// values live in Model's `Settings`, written through `SettingsStore`; the
/// rest of the window (shortcuts, profiles) lands in 4.4. 2.8b adds the
/// default browser and the welcome card to General, and Privacy for the two
/// opt-ins.
final class SettingsWindowController: NSWindowController {
    enum Section: String, CaseIterable {
        case general, appearance, search, downloads, privacy

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .search: "Search"
            case .downloads: "Downloads"
            case .privacy: "Privacy"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .search: "magnifyingglass"
            case .downloads: "arrow.down.circle"
            case .privacy: "hand.raised"
            }
        }
    }

    private let tabs = SettingsTabsController()

    init(settings: SettingsStore, services: SettingsServices) {
        tabs.tabStyle = .toolbar
        for section in Section.allCases {
            let hosting = NSHostingController(rootView: SettingsSectionView(section: section, settings: settings, services: services))
            // The window takes each section's height as it is chosen.
            hosting.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: hosting)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
            item.identifier = section.rawValue
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = Section.general.title
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `section` (spikes capture each one; 2.8b's first run may point at one).
    func select(_ section: Section) {
        tabs.selectedTabViewItemIndex = Section.allCases.firstIndex(of: section) ?? 0
        window?.title = section.title
    }
}

/// The window's title follows the chosen section, as in System Settings' panes.
private final class SettingsTabsController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label { view.window?.title = label }
    }
}

/// What Settings reaches beyond the settings values (2.8b).
struct SettingsServices {
    let defaultBrowser: DefaultBrowser
    /// No Sentry project in this build: the switch is kept, nothing can be sent.
    let crashReportsUnavailable: Bool
    let showWelcomeCard: () -> Void
    let checkForUpdates: () -> Void
    let canCheckForUpdates: () -> Bool
}

private struct SettingsSectionView: View {
    let section: SettingsWindowController.Section
    let settings: SettingsStore
    let services: SettingsServices

    var body: some View {
        Form {
            switch section {
            case .general: general
            case .appearance: appearance
            case .search: search
            case .downloads: downloads
            case .privacy: privacy
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Model.Settings, Value>) -> Binding<Value> {
        Binding(get: { settings.settings[keyPath: keyPath] }, set: { value in settings.update { $0[keyPath: keyPath] = value } })
    }

    // MARK: General

    @ViewBuilder private var general: some View {
        Section("Default browser") {
            LabeledContent {
                if services.defaultBrowser.isDefault {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else {
                    Button("Set as Default…") { services.defaultBrowser.setAsDefault() }
                        .disabled(services.defaultBrowser.isAsking)
                }
            } label: {
                Text(services.defaultBrowser.isDefault ? "Room is your default browser" : "Room is not your default browser")
                Text("Links you open in other apps open in Room's window, as Today tabs in the active space.")
            }
        }
        Section("Links") {
            Toggle(isOn: binding(\.peekOffSiteLinks)) {
                Text("Open links to other sites from pinned tabs in Peek")
                Text("Sign-in pages, form posts and redirects still open in the tab. ⇧-click any link to Peek it.")
            }
        }
        Section {
            LabeledContent {
                Button("Show Welcome Card") { services.showWelcomeCard() }
            } label: {
                Text("Welcome card")
                Text("The first-run choices in the sidebar: search engine, default browser, crash reports and updates.")
            }
        }
    }

    // MARK: Privacy (2.8b)

    @ViewBuilder private var privacy: some View {
        Section {
            Toggle(isOn: binding(\.crashReports)) {
                Text("Send crash reports")
                Text(services.crashReportsUnavailable
                     ? "This build has no crash-report project yet: nothing can be sent, whatever this says."
                     : "When Room crashes, a report of the crash goes to Room's developer (Sentry). Off: the reporter is not started.")
            }
        } header: {
            Text("Room sends crash reports and checks for updates only if you turn them on here.")
        }
        Section {
            Toggle(isOn: binding(\.automaticUpdateChecks)) {
                Text("Check for updates automatically")
                Text("Asks Room's update server once a day (Sparkle). Off: Room asks only when you choose Check for Updates or Check Now.")
            }
            LabeledContent {
                Button("Check Now") { services.checkForUpdates() }
                    .disabled(!services.canCheckForUpdates())
            } label: {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
            }
        }
    }

    // MARK: Appearance

    @ViewBuilder private var appearance: some View {
        Section {
            Picker("Appearance", selection: binding(\.appearance)) {
                Text("System").tag(AppearanceSetting.system)
                Text("Light").tag(AppearanceSetting.light)
                Text("Dark").tag(AppearanceSetting.dark)
            }
            .pickerStyle(.segmented)
        }
        Section {
            Picker("Sidebar", selection: binding(\.sidebarSide)) {
                Text("Left").tag(SidebarSide.left)
                Text("Right").tag(SidebarSide.right)
            }
            .pickerStyle(.segmented)
            Text("With the sidebar on the right, the window's buttons float over the page's top-left corner.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Search

    @ViewBuilder private var search: some View {
        Section {
            Picker("Search engine", selection: binding(\.searchEngine)) {
                ForEach(SearchEngine.all) { engine in Text(engine.name).tag(engine.id) }
            }
            Toggle(isOn: binding(\.searchSuggestions)) {
                Text("Show search suggestions")
                Text("Sends what you type in the palette to the search engine. Off: nothing leaves Room while you type.")
            }
        }
    }

    // MARK: Downloads

    /// The download folder (spec §F, ROADMAP 2.6 task 1); `nil` in Settings is ~/Downloads.
    private var folder: URL {
        DownloadRules.folder(setting: settings.settings.downloadDirectory, downloads: Self.downloadsFolder)
    }

    private static var downloadsFolder: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    @ViewBuilder private var downloads: some View {
        Section {
            LabeledContent("Save downloads to") {
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(FileManager.default.displayName(atPath: folder.path)).foregroundStyle(.secondary)
                    Button("Change…") { chooseFolder() }
                }
            }
            if settings.settings.downloadDirectory != nil {
                Button("Use the Downloads Folder") { settings.update { $0.downloadDirectory = nil } }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.update { $0.downloadDirectory = url.standardizedFileURL == Self.downloadsFolder.standardizedFileURL ? nil : url.path }
    }
}
