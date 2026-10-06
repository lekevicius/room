import AppKit
import Design
import Engine
import Observation
import SwiftUI

/// The site panel's decisions (ROADMAP 2.6 task 3: permissions per origin,
/// clear site data), as pure functions.
public enum SitePanelRules {
    /// Rows shown whatever is stored (Chrome's page info lists these first).
    public static let alwaysShown: [SitePermission] = [.geolocation, .camera, .microphone, .notifications]

    /// What applies when the site has nothing stored (Chromium's defaults).
    public static func defaultSetting(for permission: SitePermission) -> PermissionSetting {
        switch permission {
        case .popups: .block
        case .sound, .javascript, .images, .sensors: .allow
        case .geolocation, .camera, .microphone, .notifications, .clipboard, .midiSysex, .automaticDownloads: .ask
        }
    }

    /// The choices a row offers: permissions a site asks for have Ask; the
    /// rest are allowed or blocked.
    public static func options(for permission: SitePermission) -> [PermissionSetting] {
        defaultSetting(for: permission) == .ask ? [.ask, .allow, .block] : [.allow, .block]
    }

    /// What the row shows: the stored value, or the default when nothing is
    /// stored (or the stored value is not one of the row's choices).
    public static func effective(_ stored: PermissionSetting?, for permission: SitePermission) -> PermissionSetting {
        guard let stored, options(for: permission).contains(stored) else { return defaultSetting(for: permission) }
        return stored
    }

    /// The rows: the always-shown four, then any other permission the site
    /// has a setting for, in `SitePermission` order.
    public static func rows(stored: [SitePermission: PermissionSetting]) -> [SitePermission] {
        SitePermission.allCases.filter { alwaysShown.contains($0) || stored[$0] != nil }
    }

    /// Choosing the default stores nothing (the site follows the default).
    public static func storedValue(for choice: PermissionSetting, permission: SitePermission) -> PermissionSetting? {
        choice == defaultSetting(for: permission) ? nil : choice
    }

    public static func title(for permission: SitePermission) -> String {
        switch permission {
        case .geolocation: "Location"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .notifications: "Notifications"
        case .clipboard: "Clipboard"
        case .sensors: "Motion sensors"
        case .midiSysex: "MIDI devices"
        case .popups: "Pop-ups and redirects"
        case .sound: "Sound"
        case .automaticDownloads: "Automatic downloads"
        case .javascript: "JavaScript"
        case .images: "Images"
        }
    }

    public static func symbol(for permission: SitePermission) -> String {
        switch permission {
        case .geolocation: Symbol.location.name
        case .camera: Symbol.camera.name
        case .microphone: Symbol.microphone.name
        case .notifications: Symbol.notifications.name
        case .clipboard: Symbol.clipboard.name
        case .sensors: "gyroscope"
        case .midiSysex: "pianokeys"
        case .popups: "macwindow.on.rectangle"
        case .sound: Symbol.audible.name
        case .automaticDownloads: Symbol.downloads.name
        case .javascript: "curlybraces"
        case .images: "photo"
        }
    }

    public static func optionTitle(_ setting: PermissionSetting, for permission: SitePermission) -> String {
        let title = switch setting {
        case .ask: "Ask"
        case .allow: "Allow"
        case .block: "Block"
        }
        return setting == defaultSetting(for: permission) ? "\(title) (default)" : title
    }

    /// The panel's connection line.
    public static func connection(_ state: SecurityState) -> (text: String, symbol: Symbol) {
        switch state.level {
        case .secure: (state.hasMixedContent ? "Connection is secure, parts of the page are not" : "Connection is secure", .siteSecure)
        case .insecure: ("Connection is not secure", .siteInsecure)
        case .dangerous: ("Certificate error: the connection is not private", .siteInsecure)
        case .none: ("Local or internal page", .siteInfo)
        }
    }

    /// The origin a page's settings belong to (`scheme://host[:port]`), or
    /// `nil` for pages without one (about:, data:, file:).
    public static func origin(of url: URL?) -> URL? {
        guard let url, let scheme = url.scheme, ["http", "https"].contains(scheme), let host = url.host(), !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url
    }
}

/// One page's site panel: its origin's permissions in the page's profile.
@Observable
public final class SitePanelModel {
    public let origin: URL
    public let security: SecurityState
    @ObservationIgnored private weak var profile: (any Profile)?
    @ObservationIgnored private let reloadPage: () -> Void
    public private(set) var stored: [SitePermission: PermissionSetting] = [:]
    /// A setting changed since the panel opened: the page needs a reload.
    public private(set) var needsReload = false
    public private(set) var siteDataCleared = false
    public private(set) var isClearing = false
    /// The Extensions section (4.5); `nil` without an extension system.
    public let extensions: SitePanelExtensions?

    public init(origin: URL, security: SecurityState, profile: any Profile, extensions: SitePanelExtensions? = nil,
                reload: @escaping () -> Void) {
        self.origin = origin
        self.security = security
        self.profile = profile
        self.extensions = extensions
        reloadPage = reload
        refresh()
    }

    public var host: String { origin.host() ?? origin.absoluteString }
    public var rows: [SitePermission] { SitePanelRules.rows(stored: stored) }

    public func setting(_ permission: SitePermission) -> PermissionSetting {
        SitePanelRules.effective(stored[permission], for: permission)
    }

    public func set(_ choice: PermissionSetting, for permission: SitePermission) {
        guard choice != setting(permission) else { return }
        profile?.setPermissionSetting(SitePanelRules.storedValue(for: choice, permission: permission), for: permission, origin: origin)
        refresh()
        needsReload = true
    }

    public var hasStoredSettings: Bool { !stored.isEmpty }

    /// Every permission back to its default, and the site's certificate
    /// decisions with them ("Visit … Anyway" is forgotten: B-43).
    public func resetPermissions() async {
        for permission in stored.keys { profile?.setPermissionSetting(nil, for: permission, origin: origin) }
        refresh()
        needsReload = true
        do {
            try await profile?.clearSiteData(.permissions, for: origin)
        } catch {
            NSLog("Room: resetting permissions for \(origin): \(error)")
        }
        refresh()
    }

    /// Cookies and storage of this origin (the engine's profile; no network).
    public func clearSiteData() async {
        guard let profile, !isClearing else { return }
        isClearing = true
        defer { isClearing = false }
        do {
            try await profile.clearSiteData([.cookies, .storage], for: origin)
            siteDataCleared = true
            needsReload = true
        } catch {
            NSLog("Room: clearing site data for \(origin): \(error)")
        }
    }

    public func reload() {
        reloadPage()
        needsReload = false
    }

    private func refresh() {
        guard let profile else { return }
        var values: [SitePermission: PermissionSetting] = [:]
        // An engine may answer with the effective value, the default included: only a
        // value other than the default counts as the site's own (2.6b).
        for permission in SitePermission.allCases {
            if let value = profile.permissionSetting(permission, for: origin), value != SitePanelRules.defaultSetting(for: permission) {
                values[permission] = value
            }
        }
        stored = values
    }
}

/// The site panel's Extensions section (B-30, ROADMAP 4.5): the profile's
/// extensions that want this page's site, each with its site access (On
/// click, On this site, On all sites, as the extension can take them), Run
/// for one that waits on this page, and a menu (Pin/Unpin, Options,
/// Manage…). After Run the row offers to keep the extension on this site.
@Observable
public final class SitePanelExtensions {
    public struct Row: Identifiable, Equatable {
        public let id: InstalledExtension.ID
        public let name: String
        public let icon: NSImage?
        public let access: ExtensionSiteAccess
        public let isPinned: Bool
        public let hasAction: Bool
        public let hasOptions: Bool
    }

    @ObservationIgnored private let center: ExtensionsCenter
    @ObservationIgnored private let profile: UUID
    @ObservationIgnored private weak var page: (any WebContents)?
    @ObservationIgnored private let manage: () -> Void
    public let host: String
    public private(set) var rows: [Row] = []
    /// Extensions Run let run on this page (the row then offers "Always on this site").
    public private(set) var ranHere: Set<InstalledExtension.ID> = []

    public init(center: ExtensionsCenter, profile: UUID, page: any WebContents, host: String, manage: @escaping () -> Void) {
        self.center = center
        self.profile = profile
        self.page = page
        self.host = host
        self.manage = manage
        refresh()
    }

    public func refresh() {
        guard let page else { return rows = [] }
        let section = center.section(profile: profile)
        rows = center.extensionsWantingSite(profile: profile, page: page).map { item, access in
            let current = section?.installed.first { $0.id == item.id } ?? item
            return Row(id: item.id, name: item.name, icon: item.icon16, access: access, isPinned: current.isPinned,
                       hasAction: item.action != nil, hasOptions: item.optionsPageURL != nil)
        }
    }

    public func setAccess(_ level: ExtensionSiteAccess.Level, for id: InstalledExtension.ID) {
        center.setSiteAccess(level, id, profile: profile, host: host)
        if level != .onClick { ranHere.remove(id) }
        refresh()
    }

    /// Run: what the extension waits for runs on this page (activeTab).
    public func run(_ id: InstalledExtension.ID) {
        guard let page, center.runBlocked(id, profile: profile, page: page) else { return refresh() }
        ranHere.insert(id)
        refresh()
    }

    public func togglePin(_ id: InstalledExtension.ID) {
        guard let section = center.section(profile: profile), let item = section.installed.first(where: { $0.id == id }) else { return }
        center.setPinned(!item.isPinned, item, in: section)
        refresh()
    }

    public func openOptions(_ id: InstalledExtension.ID) {
        guard let section = center.section(profile: profile), let item = section.installed.first(where: { $0.id == id }) else { return }
        center.openOptions(item, in: section)
    }

    public func openManagement() { manage() }
}

/// The site panel in a popover on the header's site button (the card's
/// top-left corner without a header), as the permission prompt (2.6a).
public final class SitePanel: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    public private(set) var model: SitePanelModel?

    public override init() {}

    public var isShown: Bool { popover?.isShown == true }
    /// The panel's content on screen (DEBUG captures, spikes).
    public var contentView: NSView? { popover?.contentViewController?.view }

    public func show(_ model: SitePanelModel, relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !Motion.reduceMotion
        let controller = NSHostingController(rootView: SitePanelView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover
        self.model = model
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    public func close() {
        popover?.performClose(nil)
        popover = nil
    }

    public func popoverDidClose(_ notification: Notification) {
        popover = nil
        model = nil
    }
}

struct SitePanelView: View {
    let model: SitePanelModel
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.host).font(.headline).lineLimit(1).truncationMode(.middle)
                let connection = SitePanelRules.connection(model.security)
                Label(connection.text, systemImage: connection.symbol.name)
                    .font(Font(Typography.secondary))
                    .foregroundStyle(model.security.level == .secure ? .secondary : Color(nsColor: .systemRed))
            }
            Divider()
            Text("Permissions").font(Font(Typography.secondary)).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(model.rows, id: \.self) { permission in
                    GridRow {
                        Image(systemName: SitePanelRules.symbol(for: permission))
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(SitePanelRules.title(for: permission))
                        Picker(SitePanelRules.title(for: permission), selection: Binding(
                            get: { model.setting(permission) },
                            set: { model.set($0, for: permission) })) {
                            ForEach(SitePanelRules.options(for: permission), id: \.self) { option in
                                Text(SitePanelRules.optionTitle(option, for: permission)).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                        .accessibilityIdentifier("site-permission-\(permission.rawValue)")
                    }
                }
            }
            if model.hasStoredSettings {
                Button("Reset Permissions") { Task { await model.resetPermissions() } }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("site-reset-permissions")
            }
            if let extensions = model.extensions, !extensions.rows.isEmpty {
                Divider()
                SitePanelExtensionsView(model: extensions)
            }
            Divider()
            HStack {
                Text(model.siteDataCleared ? "Cookies and site data cleared" : "Cookies and site data")
                    .foregroundStyle(model.siteDataCleared ? .secondary : .primary)
                Spacer()
                Button("Clear…") { confirmClear = true }
                    .disabled(model.isClearing)
                    .accessibilityIdentifier("site-clear-data")
            }
            .confirmationDialog("Clear cookies and site data for \(model.host)?", isPresented: $confirmClear) {
                Button("Clear", role: .destructive) { Task { await model.clearSiteData() } }
            } message: {
                Text("You will be signed out of \(model.host) in this profile.")
            }
            if model.needsReload {
                HStack {
                    Text("Reload to apply the changes").font(Font(Typography.secondary)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reload") { model.reload() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("site-reload")
                }
            }
        }
        .padding(16)
        .frame(width: SitePanelMetrics.width)
    }
}

struct SitePanelExtensionsView: View {
    let model: SitePanelExtensions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Extensions").font(Font(Typography.secondary)).foregroundStyle(.secondary)
            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Group {
                            if let icon = row.icon { Image(nsImage: icon).resizable() } else { Image(systemName: Symbol.extensions.name) }
                        }
                        .frame(width: 16, height: 16)
                        Text(row.name).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        if row.access.wantsToRun {
                            Button("Run") { model.run(row.id) }
                                .accessibilityIdentifier("site-extension-run-\(row.id)")
                        }
                        Picker(row.name, selection: Binding(get: { row.access.level }, set: { model.setAccess($0, for: row.id) })) {
                            ForEach(ExtensionSiteAccess.Level.allCases, id: \.self) { level in
                                Text(ExtensionSiteAccess.title(level)).tag(level)
                                    .selectionDisabled(!row.access.selectable.contains(level))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .disabled(!row.access.canAffect)
                        .accessibilityIdentifier("site-extension-access-\(row.id)")
                        Menu {
                            if row.hasAction { Button(row.isPinned ? "Unpin" : "Pin") { model.togglePin(row.id) } }
                            if row.hasOptions { Button("Options") { model.openOptions(row.id) } }
                            Button("Manage Extensions…") { model.openManagement() }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    if model.ranHere.contains(row.id), row.access.level == .onClick {
                        HStack {
                            Text("Ran on this page.").font(Font(Typography.secondary)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Always on \(model.host)") { model.setAccess(.onSite, for: row.id) }
                                .buttonStyle(.link)
                                .disabled(!row.access.selectable.contains(.onSite))
                                .accessibilityIdentifier("site-extension-keep-\(row.id)")
                        }
                    }
                }
            }
        }
    }
}

/// The panel's width (chosen, as the permission popover's).
public enum SitePanelMetrics {
    public static let width: CGFloat = PromptMetrics.permissionWidth
}
