import AppKit
import Chrome
import Engine
import Integration
import Model
import Omnibox
import Store
import SwiftUI
import UIKitCore

/// Settings (⌘,), v0 (ROADMAP 2.8 task 2): a toolbar-tabbed window as in
/// every Mac app, one SwiftUI leaf per section (PLAN §4 UI framework). The
/// values live in Model's `Settings`, written through `SettingsStore`.
/// 5.7a (B-120): every pane is one height that fits the display's visible
/// frame (`SettingsWindowFit`) and scrolls inside it; ⌘W closes the window.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Section: String, CaseIterable {
        case general, appearance, search, downloads, shortcuts, spaces, extensions, privacy

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .search: "Search"
            case .downloads: "Downloads"
            case .shortcuts: "Shortcuts"
            case .spaces: "Spaces"
            case .extensions: "Extensions"
            case .privacy: "Privacy"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
            case .search: "magnifyingglass"
            case .downloads: "arrow.down.circle"
            case .shortcuts: "keyboard"
            case .spaces: "square.stack"
            case .extensions: "puzzlepiece.extension"
            case .privacy: "hand.raised"
            }
        }
    }

    private let tabs = SettingsTabsController()
    /// What the sections reach (the import spike calls `showImportSheet` as General's button does).
    let services: SettingsServices
    /// Settings ▸ Shortcuts, the AppKit table (4.4a; the settings spike drives it).
    let shortcuts: ShortcutsSettingsViewController
    /// Each section's controller, in `Section.allCases` order.
    private(set) var panes: [NSViewController] = []
    /// The visible frame the window fits in instead of its screen's (the fit spike's smallest display).
    var visibleFrameOverride: CGRect? {
        didSet { fit() }
    }

    init(settings: SettingsStore, services: SettingsServices) {
        self.services = services
        shortcuts = ShortcutsSettingsViewController(settings: settings,
                                                    extensionCommands: { services.extensions()?.shortcutRows() ?? [] })
        tabs.tabStyle = .toolbar
        for section in Section.allCases {
            let controller: NSViewController
            if section == .shortcuts {
                controller = shortcuts
            } else {
                let hosting = NSHostingController(rootView: SettingsSectionView(section: section, settings: settings, services: services))
                // The pane takes the window's size (`fit`); its Form scrolls inside it.
                hosting.sizingOptions = []
                controller = hosting
            }
            panes.append(controller)
            let item = NSTabViewItem(viewController: controller)
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
        window.delegate = self
        fit()
        window.center()
        fit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `section` (spikes capture each one; 2.8b's first run may point at one).
    func select(_ section: Section) {
        tabs.selectedTabViewItemIndex = Section.allCases.firstIndex(of: section) ?? 0
        window?.title = section.title
        fit()
    }

    /// The visible frame the window has to fit in.
    var visibleFrame: CGRect {
        visibleFrameOverride ?? window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? SettingsWindowFit.smallestVisibleFrame
    }

    /// Every pane at the height the display allows, the window moved inside the visible frame.
    func fit() {
        guard let window else { return }
        let contentHeight = window.contentView?.frame.height ?? 0
        let chrome = contentHeight > 0 ? window.frame.height - contentHeight : SettingsWindowMetrics.fallbackChrome
        let size = NSSize(width: SettingsWindowFit.contentWidth, height: SettingsWindowFit.contentHeight(visible: visibleFrame, chrome: chrome))
        for pane in panes where pane.preferredContentSize != size { pane.preferredContentSize = size }
        var frame = window.frame
        let height = size.height + chrome
        frame.origin.y = frame.maxY - height
        frame.size = NSSize(width: window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).width, height: height)
        frame = SettingsWindowFit.placed(frame, in: visibleFrame)
        if frame != window.frame { window.setFrame(frame, display: window.isVisible) }
    }

    func windowDidChangeScreen(_ notification: Notification) { fit() }
}

enum SettingsWindowMetrics {
    /// The title bar and preference toolbar before the window is laid out (measured 78 pt on macOS 26).
    static let fallbackChrome: CGFloat = 78
}

/// Pages Settings opens as tabs.
enum SettingsPages {
    /// Chromium's own list of sites with stored data (4.4b's bounded attempt).
    static let allSiteData = URL(string: "chrome://settings/content/all")!
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
    let checkForUpdates: () -> Void
    let canCheckForUpdates: () -> Bool
    /// Chrome extensions per profile (3.6a); `nil` on an engine without them (no engine, the fakes).
    let extensions: () -> ExtensionsCenter?
    /// Room's built-in blocker (B-30); `nil` without an engine.
    let contentBlocking: () -> ContentBlockingController?
    /// The page in the browser window's card and its Room profile (4.5:
    /// Settings ▸ Extensions sets site access for its host).
    let shownPage: () -> (page: any WebContents, profile: UUID)?
    /// The spaces and their routing rules (4.2: the Links popup, Settings ▸ Spaces).
    let sidebar: SidebarStore
    /// The routing sheet over the Settings window.
    let showRoutingRules: () -> Void
    /// The import sheet over the browser window (4.3b: General ▸ Import…).
    let showImportSheet: () -> Void
    /// Profiles, permissions and browsing data (4.4b: Spaces, Privacy).
    let profiles: ProfileServices
}

private struct SettingsSectionView: View {
    let section: SettingsWindowController.Section
    let settings: SettingsStore
    let services: SettingsServices
    @State private var clearingData = false
    @State private var sitePermissions = false

    var body: some View {
        Form {
            switch section {
            case .general: general
            case .appearance: appearance
            case .search: search
            case .downloads: downloads
            case .shortcuts: EmptyView()
            case .spaces: spaces
            case .extensions: ExtensionsSettingsView(center: services.extensions(), settings: settings, shownPage: services.shownPage())
            case .privacy: privacy
            }
        }
        .formStyle(.grouped)
        // The window's size (`SettingsWindowController.fit`): the Form scrolls inside it (5.7a, B-120).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Model.Settings, Value>) -> Binding<Value> {
        Binding(get: { settings.settings[keyPath: keyPath] }, set: { value in settings.update { $0[keyPath: keyPath] = value } })
    }

    // MARK: General

    @ViewBuilder private var general: some View {
        Section {
            // 5.7a (B-120): one row.
            LabeledContent("Default browser") {
                if services.defaultBrowser.isDefault {
                    Label("Room", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("default-browser-room")
                } else {
                    Button("Set as Default…") { services.defaultBrowser.setAsDefault() }
                        .disabled(services.defaultBrowser.isAsking)
                }
            }
        }
        Section("Tabs") {
            // Spec §A.3 (4.4a): what ⌘W does to a pinned tab or an Essential.
            Picker(selection: binding(\.permanentCloseBehavior)) {
                ForEach(PermanentCloseBehavior.allCases, id: \.self) { behavior in Text(behavior.settingsTitle).tag(behavior) }
            } label: {
                Text("⌘W on a pinned tab or Essential")
                Text(settings.settings.permanentCloseBehavior.settingsExplanation)
            }
            Picker(selection: binding(\.archiveAfterHours)) {
                ForEach(ArchivePolicy.afterHoursOptions.filter { $0 != ArchivePolicy.never }, id: \.self) { hours in
                    Text(Self.archiveTitle(hours)).tag(hours)
                }
                Divider()
                Text(Self.archiveTitle(ArchivePolicy.never)).tag(ArchivePolicy.never)
            } label: {
                Text("Archive tabs after")
                Text(settings.settings.archiveAfterHours == ArchivePolicy.never
                     ? "Today tabs stay until you close or archive them."
                     : "Today tabs you have not used for this long move to the Archive (⇧⌘L); the selected one and tabs playing sound, "
                        + "using the camera or holding unsaved form input stay.")
            }
            Toggle(isOn: binding(\.peekOffSiteLinks)) {
                Text("Open links to other sites from pinned tabs in Peek")
                Text("Sign-in pages, form posts and redirects still open in the tab. ⇧-click any link to Peek it.")
            }
        }
        Section("Import") {
            LabeledContent {
                Button("Import…") { services.showImportSheet() }
            } label: {
                Text("Import from another browser")
                Text("Bookmarks, history, Arc's sidebar, passwords from an exported CSV and extensions from the Chrome Web Store.")
            }
        }
    }

    static func archiveTitle(_ hours: Int) -> String {
        if hours == ArchivePolicy.never { return "Never" }
        return hours % 24 == 0 && hours >= 168 ? "\(hours / 24) days" : "\(hours) hours"
    }

    // MARK: Spaces (4.2: routing; 4.4b: order, profiles; 5.7a: every routing setting here)

    @ViewBuilder private var spaces: some View {
        SpacesSettingsView(sidebar: services.sidebar, profiles: services.profiles, settings: settings,
                           showAllRules: services.showRoutingRules)
    }

    // MARK: Privacy (2.8b; 4.4b; 5.7a: a short pane, its lists in sheets)

    @ViewBuilder private var privacy: some View {
        if let blocking = services.contentBlocking() {
            ContentBlockingSettingsView(controller: blocking)
        }
        Section {
            LabeledContent {
                Button("Site Permissions…") { sitePermissions = true }
                    .accessibilityIdentifier("privacy-site-permissions")
            } label: {
                Text("Site permissions")
                Text("Camera, microphone, location, notifications and the rest, as each site was answered.")
            }
            LabeledContent {
                Button("Clear Browsing Data…") { clearingData = true }
            } label: {
                Text("Browsing data")
                Text("History, cookies and site data, cached files, download history, autofill and passwords, for a time range.")
            }
            LabeledContent {
                Button("All Site Data…") { services.profiles.openPage(SettingsPages.allSiteData) }
            } label: {
                Text("Site data")
                Text("Every site storing data, in a tab (Chromium's page). For one site: the site button ▸ Clear Site Data.")
            }
        } header: {
            Text("Websites")
        } footer: {
            Text("Passwords, addresses and cards Room saves stay on this Mac, in Room's profile: no account, no sync, no upload.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $clearingData) {
            ClearBrowsingDataSheet(sidebar: services.sidebar, profiles: services.profiles) { clearingData = false }
        }
        .sheet(isPresented: $sitePermissions) {
            SitePermissionsSheet(sidebar: services.sidebar, profiles: services.profiles) { sitePermissions = false }
        }
        Section {
            Toggle(isOn: binding(\.crashReports)) {
                Text("Send crash reports")
                Text(services.crashReportsUnavailable
                     ? "This build has no crash-report project yet: nothing can be sent, whatever this says."
                     : "When Room crashes, a report of the crash goes to Room's developer (Sentry). Off: the reporter is not started.")
            }
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
        } header: {
            Text("Room's own requests")
        } footer: {
            Text("Room sends crash reports and checks for updates only if you turn them on here.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section {
            LabeledContent {
                Text("Not used").foregroundStyle(.secondary)
            } label: {
                Text("Google services")
                Text(PrivacyStatements.googleServices)
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
        Section("App Icon") {
            AppIconPicker(selection: binding(\.appIcon))
            // Only while running: with Room quit, the Dock and Finder show the bundle's icon.
            Text("The Dock shows this icon while Room is open.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section {
            // 5.3b: the sidebar's and the palette's type and row heights (`TextScale`).
            Picker("Sidebar text", selection: binding(\.sidebarTextSize)) {
                Text("Small").tag(SidebarTextSize.small)
                Text("Medium").tag(SidebarTextSize.medium)
                Text("Large").tag(SidebarTextSize.large)
            }
            .pickerStyle(.segmented)
            Text("The size of the sidebar's and the command palette's text and rows.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle("Grey window buttons", isOn: binding(\.monoTrafficLights))
            Text("The close, minimise and zoom buttons are drawn without colour.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Section {
            // 4.7b: the reader page's text (⌥⇧⌘R); applies to a reader page that shows.
            Picker("Reader text size", selection: binding(\.readerTextSize)) {
                Text("Small").tag(ReaderTextSize.small)
                Text("Medium").tag(ReaderTextSize.medium)
                Text("Large").tag(ReaderTextSize.large)
            }
        }
    }

    // MARK: Search (4.4a: the engines list, the default per profile, the keywords, B-64's line)

    @ViewBuilder private var search: some View {
        SearchSettingsView(settings: settings, profiles: services.sidebar.profiles.map { ($0.id, $0.name) })
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
            Toggle(isOn: binding(\.askWhereToSave)) {
                Text("Ask where to save each download")
                Text("A save panel opens for every download, starting in the folder above.")
            }
        }
        Section {
            Picker(selection: binding(\.pdfsOpenInRoom)) {
                Text("Open in Room").tag(true)
                Text("Download").tag(false)
            } label: {
                Text("PDFs")
                Text("Open in Room shows a PDF in Chrome's viewer (find, zoom, print, save); Download saves it to the folder above. Applies at the next launch.")
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

/// Settings ▸ Extensions (ROADMAP 3.6a task 1): each profile's installed
/// extensions with enable, options, reload (unpacked), pin and remove (the
/// consent sheet), Load Unpacked… and Chrome's management page as a tab.
/// Usable, not polished (Chapter 5). Pinned extensions show their action
/// buttons in the sidebar's header (3.6b); side panels are not supported in v1.
struct ExtensionsSettingsView: View {
    let center: ExtensionsCenter?
    let settings: SettingsStore
    /// The browser window's page when Settings opened (site access is set for its host).
    let shownPage: (page: any WebContents, profile: UUID)?
    @State private var loadError: String?
    /// Each extension's directory size on disk (bytes), computed off the main thread.
    @State private var sizes: [String: Int64] = [:]

    /// The profile whose extensions show (5.7a, B-120: a switcher, not every profile at once); `nil` is the shown space's.
    @State private var profileID: UUID?

    private func shownSection(_ center: ExtensionsCenter) -> ExtensionsCenter.ProfileSection? {
        let id = profileID ?? shownPage?.profile
        return center.sections.first { $0.id == id } ?? center.sections.first
    }

    var body: some View {
        if let center, let section = shownSection(center) {
            if center.sections.count > 1 {
                Section {
                    Picker("Profile", selection: Binding(get: { section.id }, set: { profileID = $0 })) {
                        ForEach(center.sections) { section in Text(section.name).tag(section.id) }
                    }
                    .accessibilityIdentifier("extensions-profile")
                }
            }
            Section {
                if section.installed.isEmpty {
                    Text("No extensions. Install from the Chrome Web Store in a tab, or load an unpacked one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(section.installed) { item in row(item, section: section, center: center) }
                HStack {
                    Button("Load Unpacked…") { loadUnpacked(section: section, center: center) }
                    Button("Keyboard Shortcuts…") { center.openShortcutsPage(in: section) }
                        .help("Chrome's page for the extensions' keys, as a tab of this profile")
                    Button("Open chrome://extensions") { center.openManagementPage(in: section) }
                    Spacer()
                }
                if let loadError { Text(loadError).font(.callout).foregroundStyle(.red) }
            } header: {
                Text("Installed")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let check = center.lastCheck {
                        Text("Last update check: \(check.extensions) extensions, \(check.updatesFound) updates.")
                    } else {
                        Text("Room checks installed extensions for updates once a day, and never while none is installed.")
                    }
                    Text("Pinned extensions show in the sidebar's header in this order; the others are in its puzzle-piece menu.")
                    // 5.7a (B-120): 4.5's Notes, beside the list they are about.
                    Text(ExtensionStatements.footer)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Section {
                Text("This engine has no extensions.").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: InstalledExtension, section: ExtensionsCenter.ProfileSection, center: ExtensionsCenter) -> some View {
        HStack(alignment: .top) {
            Group {
                if let icon = item.icon32 ?? item.icon16 {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name).fontWeight(.medium)
                    Text(item.version).foregroundStyle(.secondary)
                    if item.isUnpacked { Text("Unpacked").font(.caption).foregroundStyle(.orange) }
                }
                if !item.summary.isEmpty {
                    Text(item.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    if item.optionsPageURL != nil { Button("Options") { center.openOptions(item, in: section) } }
                    if item.isUnpacked { Button("Reload") { center.reload(item, in: section) } }
                    if item.action != nil {
                        Button(item.isPinned ? "Unpin" : "Pin") { center.setPinned(!item.isPinned, item, in: section) }
                            .accessibilityIdentifier("extension-pin-\(item.id)")
                    }
                    Button("Remove…") { Task { await center.uninstall(item, in: section) } }
                }
                .buttonStyle(.link)
                .font(.callout)
                if item.isEnabled { siteAccess(item, section: section, center: center) }
                Toggle(isOn: Binding(
                    get: { settings.settings.allowsInIncognito(item.id, profile: section.id) },
                    set: { allowed in settings.update { $0.setAllowsInIncognito(allowed, item.id, profile: section.id) } })) {
                    Text("Allow in incognito").font(.callout)
                }
                .toggleStyle(.checkbox)
                .help("The extension runs in this profile's incognito window (⇧⌘N).")
                .accessibilityIdentifier("extension-incognito-\(item.id)")
                DisclosureGroup("Details") { details(item) }
                    .font(.callout)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { item.isEnabled }, set: { center.setEnabled($0, item, in: section) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .task(id: item.directory) { await measure(item) }
    }

    /// Site access for the shown page's host (Chrome's site-access menu, 4.5):
    /// the levels the extension cannot take there are disabled.
    @ViewBuilder
    private func siteAccess(_ item: InstalledExtension, section: ExtensionsCenter.ProfileSection, center: ExtensionsCenter) -> some View {
        let _ = center.actionRevision
        if let shownPage, shownPage.profile == section.id, let url = shownPage.page.url, ["http", "https"].contains(url.scheme ?? ""),
           let host = url.host(),
           let access = center.siteAccess(item.id, profile: section.id, page: shownPage.page) {
            if access.wantsSite {
                Picker(selection: Binding(
                    get: { access.level },
                    set: { level in center.setSiteAccess(level, item.id, profile: section.id, host: host) })) {
                    ForEach(ExtensionSiteAccess.Level.allCases, id: \.self) { level in
                        Text(level == .onSite ? "On \(host)" : ExtensionSiteAccess.title(level))
                            .tag(level)
                            .selectionDisabled(!access.selectable.contains(level))
                    }
                } label: {
                    Text("Site access").font(.callout)
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(!access.canAffect)
                .accessibilityIdentifier("extension-site-access-\(item.id)")
            } else {
                Text("Does not ask for \(host).").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Text("Site access: open a web page of this profile, then choose here or in the site panel.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func details(_ item: InstalledExtension) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Version \(item.version)")
            Text("Size on disk: " + (sizes[item.id].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"))
            Text(item.isFromWebStore ? "From the Chrome Web Store" : item.isUnpacked ? "Unpacked from \(item.directory?.path ?? "a folder")" : "Installed from a file")
            Text("ID \(item.id)").textSelection(.enabled)
            if item.permissionMessages.isEmpty {
                Text("It asks for no special permissions.")
            } else {
                Text("It can:")
                ForEach(item.permissionMessages, id: \.self) { Text("• " + $0) }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
    }

    /// The extension directory's size, summed off the main thread.
    private func measure(_ item: InstalledExtension) async {
        guard let directory = item.directory else { return }
        let bytes = await Task.detached(priority: .utility) { ExtensionStatements.directorySize(directory) }.value
        sizes[item.id] = bytes
    }

    private func loadUnpacked(section: ExtensionsCenter.ProfileSection, center: ExtensionsCenter) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Load"
        panel.message = "Choose the extension's folder (the one with manifest.json)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await center.loadUnpacked(at: url, in: section)
                loadError = nil
            } catch {
                loadError = "\(error)"
            }
        }
    }
}

/// Settings ▸ Extensions' line under the list (4.5's statements; one line since 5.7a).
enum ExtensionStatements {
    static let footer = "Extensions make their own requests (their updates, their own servers). "
        + "Native messaging to desktop apps and side panels do not work in Room."

    /// The bytes of every file under `directory` (nonisolated: Settings runs it off the main thread).
    nonisolated static func directorySize(_ directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}

/// Settings ▸ General's ⌘W popup (spec §A.3's six behaviours, 4.4a): a title and one line each.
extension PermanentCloseBehavior {
    var settingsTitle: String {
        switch self {
        case .resetUnloadSwitch: "Unload, reset and switch away"
        case .unloadSwitch: "Unload and switch away"
        case .resetSwitch: "Reset and switch away"
        case .switchOnly: "Switch away"
        case .reset: "Reset only"
        case .close: "Close it"
        }
    }

    var settingsExplanation: String {
        switch self {
        case .resetUnloadSwitch: "The default: the page is unloaded, goes back to its pinned URL, and the last tab you used is selected."
        case .unloadSwitch: "The page is unloaded but keeps where you were; the last tab you used is selected."
        case .resetSwitch: "The page goes back to its pinned URL and stays loaded; the last tab you used is selected."
        case .switchOnly: "The page stays as it is, loaded; the last tab you used is selected."
        case .reset: "The page goes back to its pinned URL and stays selected."
        case .close: "The tab leaves the sidebar like a Today tab; ⇧⌘T brings it back."
        }
    }
}

enum SearchSettingsMetrics {
    /// The engines list's height (5.7a: about five rows, then it scrolls; chosen).
    static let listHeight: CGFloat = 200
    static let rowPadding: CGFloat = 6
    static let editorWidth: CGFloat = 460
}

/// Settings ▸ Search (ROADMAP 4.4a task 3): each profile's default engine,
/// the engines list (add, edit, remove; URLs shown with %s), the suggestions
/// switch with Chrome's request cadence (B-64). A SwiftUI leaf: nothing here
/// updates per keystroke but the editor's own fields.
struct SearchSettingsView: View {
    let settings: SettingsStore
    let profiles: [(id: UUID, name: String)]
    /// The engine being added or edited, its URLs in %s form.
    @State private var draft: SearchEngineSetting?
    @State private var problem: String?

    private var engines: [SearchEngineSetting] { SearchEngines.list(settings.settings) }

    var body: some View {
        Section {
            ForEach(profiles, id: \.id) { profile in
                Picker(profiles.count == 1 ? "Search engine" : "Search engine for \(profile.name)", selection: defaultBinding(profile.id)) {
                    ForEach(engines) { engine in Text(engine.name).tag(engine.id) }
                }
            }
        } header: {
            Text("Default")
        } footer: {
            Text("What you type in the palette searches the default engine of the shown space's profile.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section {
            // 5.7a (B-120): a list of fixed height that scrolls; Add and Edit open a sheet.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(engines) { engine in
                        row(engine)
                            .padding(.vertical, SearchSettingsMetrics.rowPadding)
                        if engine.id != engines.last?.id { Divider() }
                    }
                }
            }
            .frame(height: SearchSettingsMetrics.listHeight)
            .accessibilityIdentifier("search-engines-list")
            HStack {
                Spacer()
                Button("Add Search Engine…") {
                    problem = nil
                    draft = SearchEngineSetting(id: SearchEngines.newID(), name: "", keyword: "", searchURL: "https://", suggestURL: nil)
                }
            }
        } header: {
            Text("Search engines")
        } footer: {
            Text("Type an engine's keyword and press Tab in the palette to search it (yt, Tab, then what you look for).")
                .font(.callout).foregroundStyle(.secondary)
        }
        .sheet(item: $draft) { engine in
            editor(engine)
        }
        Section {
            Toggle(isOn: Binding(get: { settings.settings.searchSuggestions }, set: { value in settings.update { $0.searchSuggestions = value } })) {
                Text("Show search suggestions")
                Text("With suggestions on, the search engine receives what you type as you type it, several times a second. "
                     + "Off: nothing leaves Room while you type.")
            }
        }
    }

    private func defaultBinding(_ profile: UUID) -> Binding<String> {
        Binding(get: { SearchEngines.defaultID(for: profile, in: settings.settings) },
                set: { id in settings.update { $0.searchEngineByProfile[profile.uuidString] = id } })
    }

    @ViewBuilder private func row(_ engine: SearchEngineSetting) -> some View {
        let blocked = SearchEngines.removalBlocked(engine.id, in: settings.settings, profiles: profiles.map(\.id))
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(engine.name)
                    Text(engine.keyword).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                Text(SearchEngines.displayURL(engine.searchURL)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Edit") {
                problem = nil
                var copy = engine
                copy.searchURL = SearchEngines.displayURL(engine.searchURL)
                copy.suggestURL = engine.suggestURL.map(SearchEngines.displayURL)
                draft = copy
            }
            Button("Remove") { settings.update { SearchEngines.remove(engine.id, in: &$0, profiles: profiles.map(\.id)) } }
                .disabled(blocked != nil)
                .help(blocked ?? "Remove \(engine.name)")
        }
        .buttonStyle(.link)
    }

    private func editor(_ engine: SearchEngineSetting) -> some View {
        let binding = Binding(get: { draft ?? engine }, set: { draft = $0 })
        let isNew = !SearchEngines.list(settings.settings).contains { $0.id == engine.id }
        return VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add Search Engine" : "Edit \(engine.name)").font(.headline)
            Form {
                TextField("Name", text: binding.name)
                TextField("Keyword", text: binding.keyword)
                TextField("Search URL", text: binding.searchURL, prompt: Text("https://example.com/search?q=%s"))
                TextField("Suggestions URL", text: Binding(get: { binding.wrappedValue.suggestURL ?? "" },
                                                           set: { binding.wrappedValue.suggestURL = $0 }),
                          prompt: Text("Optional"))
            }
            .formStyle(.grouped)
            Text("%s stands for the search terms.").font(.callout).foregroundStyle(.secondary)
            if let problem { Text(problem).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    draft = nil
                    problem = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") { save(binding.wrappedValue) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: SearchSettingsMetrics.editorWidth)
    }

    /// Stores the draft (%s back to {searchTerms}) or shows why not.
    func save(_ engine: SearchEngineSetting) {
        var stored = engine
        stored.searchURL = SearchEngines.storedURL(engine.searchURL)
        stored.suggestURL = engine.suggestURL.map(SearchEngines.storedURL)
        var result: SearchEngines.Problem?
        settings.update { value in
            do throws(SearchEngines.Problem) { try SearchEngines.save(stored, in: &value) } catch { result = error }
        }
        problem = result?.message
        if result == nil { draft = nil }
    }
}

