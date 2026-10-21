import AppKit
import Chrome
import Engine
import Model
import Store
import SwiftUI

/// What Settings ▸ Spaces and Privacy reach in the app (4.4b).
struct ProfileServices {
    /// `nil` when renamed; the reason when refused.
    let rename: (UUID, String) -> String?
    let create: (String) -> Void
    /// The confirmation sheet over the Settings window, then the deletion.
    let delete: (UUID) -> Void
    let counts: (UUID) -> AppDelegate.ProfileDeletionCounts
    /// The routing sheet, a new rule for the space started in it when it has none.
    let routingRules: (UUID) -> Void
    /// The profile's engine profile, made when it has none yet (its data is on disk).
    let engineProfile: (UUID) async -> (any Engine.Profile)?
    /// Clears `kinds` in `period` for one profile or (`nil`) all; the toast's line.
    let clearBrowsingData: (UUID?, BrowsingDataKinds, BrowsingDataPeriod) async -> String
    /// Opens a page as a Today tab in the active space.
    let openPage: (URL) -> Void
}

// MARK: - Spaces & Profiles

/// Settings ▸ Spaces (4.4b, spec §B): the spaces in their order (up and
/// down move them; the footer follows) with each one's routing rules, then
/// routing (5.7a, B-120: every routing setting is here, nowhere else), then
/// the profiles: renamed in place, deleted with a confirmation, created.
struct SpacesSettingsView: View {
    let sidebar: SidebarStore
    let profiles: ProfileServices
    let settings: SettingsStore
    let showAllRules: () -> Void
    @State private var newProfileName = ""

    private var rulesSummary: String {
        let rules = sidebar.routingRules
        let enabled = rules.count { $0.enabled }
        return rules.isEmpty ? "No routing rules." : "\(rules.count) rule\(rules.count == 1 ? "" : "s"), \(enabled) enabled."
    }

    /// The chosen space while it exists; a deleted one reads as Most Recent Space.
    private var externalTarget: Binding<UUID?> {
        Binding(get: {
            settings.settings.externalLinksSpaceID.flatMap { id in sidebar.space(id) != nil ? id : nil }
        }, set: { value in settings.update { $0.externalLinksSpaceID = value } })
    }

    var body: some View {
        Section {
            ForEach(Array(sidebar.spaces.enumerated()), id: \.element.id) { index, space in
                let rules = sidebar.routingRules.count { $0.targetSpaceID == space.id }
                let profile = sidebar.profiles.first { $0.id == space.profileID }?.name ?? "?"
                LabeledContent {
                    HStack(spacing: 6) {
                        Button("Routing…") { profiles.routingRules(space.id) }
                        Button { move(space.id, to: index - 1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                            .help("Move up")
                        Button { move(space.id, to: index + 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == sidebar.spaces.count - 1)
                            .help("Move down")
                    }
                } label: {
                    Text(space.name)
                    Text("\(profile) · " + (rules == 0 ? "no routing rules" : "\(rules) routing rule\(rules == 1 ? "" : "s")"))
                }
            }
        } header: {
            Text("Spaces")
        } footer: {
            Text("The order is the footer's order and ⌃1…⌃9's.").font(.callout).foregroundStyle(.secondary)
        }
        Section {
            // Spec §B (4.2): the default for external links no rule matches, and routing between spaces.
            Picker(selection: externalTarget) {
                Text("Most Recent Space").tag(UUID?.none)
                Divider()
                ForEach(sidebar.spaces, id: \.id) { space in Text(space.name).tag(UUID?.some(space.id)) }
            } label: {
                Text("Open external links in")
                Text("Links from other apps that no routing rule matches. The most recent space is the one you used last.")
            }
            Toggle(isOn: Binding(get: { settings.settings.routeLinksBetweenSpaces },
                                 set: { value in settings.update { $0.routeLinksBetweenSpaces = value } })) {
                Text("Route links between spaces")
                Text("A link you open as a new tab from a page goes to the space a routing rule names. Peek and links that open in place stay.")
            }
            LabeledContent {
                Button("Routing Rules…") { showAllRules() }
            } label: {
                Text("Routing rules")
                Text("Rules send a link to a space by its address. \(rulesSummary)")
            }
        } header: {
            Text("Routing")
        }
        Section {
            ForEach(Array(sidebar.profiles.enumerated()), id: \.element.id) { index, profile in
                ProfileRow(profile: profile, isDefault: index == 0, counts: profiles.counts(profile.id), services: profiles)
            }
            HStack {
                TextField("New profile", text: $newProfileName, prompt: Text("Name"))
                    .accessibilityLabel("New profile name")
                    .onSubmit(addProfile)
                Button("New Profile") { addProfile() }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Profiles")
        } footer: {
            Text("Each profile keeps its own cookies, history, passwords and site permissions; a space uses one. "
                 + "Renaming keeps its data. The Default profile cannot be deleted.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func move(_ id: UUID, to index: Int) {
        guard index >= 0, index < sidebar.spaces.count else { return }
        try? sidebar.moveSpace(id, to: index)
    }

    private func addProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        profiles.create(name)
        newProfileName = ""
    }
}

/// One profile: its name edited in place (Return renames), its spaces and
/// tabs counted, Delete.
private struct ProfileRow: View {
    let profile: Model.Profile
    let isDefault: Bool
    let counts: AppDelegate.ProfileDeletionCounts
    let services: ProfileServices
    @State private var name = ""
    @State private var refusal: String?

    var body: some View {
        LabeledContent {
            Button("Delete…") { services.delete(profile.id) }
                .disabled(isDefault)
                .help(isDefault ? "The Default profile cannot be deleted." : "Deletes the profile and its data; its tabs go to the Archive.")
        } label: {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Profile name")
                .onSubmit(commit)
                .onAppear { name = profile.name }
                .onChange(of: profile.name) { _, new in name = new }
            Text(refusal ?? "\(counts.spaces) space\(counts.spaces == 1 ? "" : "s"), \(counts.entries) tab\(counts.entries == 1 ? "" : "s")"
                 + (isDefault ? " · Default" : ""))
                .foregroundStyle(refusal == nil ? Color.secondary : Color.red)
        }
    }

    private func commit() {
        refusal = services.rename(profile.id, name)
        if refusal != nil { name = profile.name }
    }
}

// MARK: - Privacy

/// Settings ▸ Privacy ▸ Site Permissions… (4.4b; a sheet since 5.7a, B-120,
/// laid out as Safari's Websites pane): the permission types on the left,
/// every site with its own setting for the chosen one on the right, each
/// changed or reset (the site panel's types and choices), in one profile.
struct SitePermissionsSheet: View {
    let sidebar: SidebarStore
    let profiles: ProfileServices
    let dismiss: () -> Void
    @State private var profileID: UUID?
    @State private var permission: SitePermission? = .notifications
    @State private var entries: [ContentSettingEntry] = []
    @State private var engineProfile: (any Engine.Profile)?

    private var shown: SitePermission { permission ?? .notifications }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(SitePermission.allCases, id: \.self, selection: $permission) { permission in
                    Label(SitePanelRules.title(for: permission), systemImage: SitePanelRules.symbol(for: permission)).tag(permission)
                }
                .listStyle(.sidebar)
                .frame(width: SitePermissionsMetrics.typesWidth)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(SitePanelRules.title(for: shown)) for the websites below:").font(.callout)
                    List {
                        if entries.isEmpty {
                            Text("No site has its own setting.").foregroundStyle(.secondary)
                        }
                        ForEach(entries, id: \.pattern) { entry in row(entry) }
                    }
                    .listStyle(.bordered)
                    .accessibilityIdentifier("site-permissions-list")
                    Text("Other websites: \(SitePanelRules.optionTitle(SitePanelRules.defaultSetting(for: shown), for: shown)) (Chromium's default).")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            Divider()
            HStack {
                if sidebar.profiles.count > 1 {
                    Picker("Profile", selection: Binding(get: { profileID ?? sidebar.profiles.first?.id }, set: { profileID = $0 })) {
                        ForEach(sidebar.profiles, id: \.id) { profile in Text(profile.name).tag(UUID?.some(profile.id)) }
                    }
                    .fixedSize()
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: SitePermissionsMetrics.width, height: SitePermissionsMetrics.height)
        .task(id: TaskKey(profile: profileID ?? sidebar.profiles.first?.id, permission: shown)) { await reload() }
    }

    @ViewBuilder private func row(_ entry: ContentSettingEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.pattern).lineLimit(1).truncationMode(.middle)
                if entry.isEmbedded { Text("Where it is embedded in another site").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Picker("", selection: Binding(get: { entry.setting }, set: { set($0, entry) })) {
                ForEach(SitePanelRules.options(for: shown), id: \.self) { option in
                    Text(SitePanelRules.optionTitle(option, for: shown)).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button("Reset") { set(nil, entry) }
                .buttonStyle(.link)
                .disabled(entry.origin == nil)
                .help("Back to the default for other websites")
        }
    }

    private struct TaskKey: Hashable {
        let profile: UUID?
        let permission: SitePermission
    }

    private func reload() async {
        guard let id = profileID ?? sidebar.profiles.first?.id else { return }
        engineProfile = await profiles.engineProfile(id)
        entries = engineProfile?.contentSettings(ofType: shown) ?? []
    }

    private func set(_ setting: PermissionSetting?, _ entry: ContentSettingEntry) {
        guard let origin = entry.origin, let engineProfile else { return }
        engineProfile.setPermissionSetting(setting, for: shown, origin: origin)
        entries = engineProfile.contentSettings(ofType: shown)
    }
}

enum SitePermissionsMetrics {
    /// Chosen: Safari's Websites pane proportions inside the 560 pt Settings window's sheet.
    static let width: CGFloat = 640
    static let height: CGFloat = 420
    static let typesWidth: CGFloat = 200
}

/// Clear browsing data… (4.4b): the kinds, the period, the profile.
struct ClearBrowsingDataSheet: View {
    let sidebar: SidebarStore
    let profiles: ProfileServices
    let dismiss: () -> Void
    @State private var kinds: BrowsingDataKinds = [.history, .cookiesAndSiteData, .cache]
    @State private var period: BrowsingDataPeriod = .lastHour
    @State private var profileID: UUID?
    @State private var clearing = false

    static let kindRows: [(kind: BrowsingDataKinds, title: String, detail: String, short: String)] = [
        (.history, "Browsing history", "Pages you visited; the palette's history", "history"),
        (.cookiesAndSiteData, "Cookies and site data", "Signs you out of most sites", "cookies"),
        (.cache, "Cached images and files", "Pages load again from the network", "cached files"),
        (.downloads, "Download history", "The downloads list; the files stay", "download history"),
        (.autofill, "Autofill form data", "Saved form entries and addresses", "autofill data"),
        (.passwords, "Passwords", "Saved passwords of this profile", "passwords"),
    ]

    static func periodTitle(_ period: BrowsingDataPeriod) -> String {
        switch period {
        case .lastHour: "Last hour"
        case .lastDay: "Last 24 hours"
        case .lastWeek: "Last 7 days"
        case .lastFourWeeks: "Last 4 weeks"
        case .allTime: "All time"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clear Browsing Data").font(.headline)
            Form {
                Picker("Time range", selection: $period) {
                    ForEach(BrowsingDataPeriod.allCases, id: \.self) { Text(Self.periodTitle($0)).tag($0) }
                }
                if sidebar.profiles.count > 1 {
                    Picker("Profile", selection: $profileID) {
                        Text("All Profiles").tag(UUID?.none)
                        ForEach(sidebar.profiles, id: \.id) { profile in Text(profile.name).tag(UUID?.some(profile.id)) }
                    }
                }
                ForEach(Self.kindRows, id: \.title) { kind, title, detail, _ in
                    Toggle(isOn: Binding(get: { kinds.contains(kind) }, set: { on in if on { kinds.insert(kind) } else { kinds.remove(kind) } })) {
                        Text(title)
                        Text(detail)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clear") {
                    clearing = true
                    Task {
                        _ = await profiles.clearBrowsingData(profileID, kinds, period)
                        clearing = false
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(kinds.isEmpty || clearing)
            }
        }
        .padding(20)
        .frame(width: ClearBrowsingDataMetrics.width)
    }
}

enum ClearBrowsingDataMetrics {
    static let width: CGFloat = 420
}

/// Settings ▸ Privacy's Google services line (4.4b's statements, the user's
/// decisions of 2026-10-06: B-63, B-68, B-72, B-74, Safe Browsing). 5.7a
/// (B-120): one summary row; the Notes section and its Zoom and Autoplay
/// lines (behaviours, not settings) went.
enum PrivacyStatements {
    static let googleServices = "Translation, Safe Browsing, Enhanced Spell Check and suggested strong passwords each need Google's servers: "
        + "Room does not offer them. Spelling is checked on this Mac by macOS; passwords you type are saved."
}
