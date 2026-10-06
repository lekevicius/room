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
/// the profiles: renamed in place, deleted with a confirmation, created.
struct SpacesSettingsView: View {
    let sidebar: SidebarStore
    let profiles: ProfileServices
    let rulesSummary: String
    let showAllRules: () -> Void
    @State private var newProfileName = ""

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
            LabeledContent {
                Button("Routing Rules…") { showAllRules() }
            } label: {
                Text("Space routing")
                Text("Rules send links from other apps, and links between spaces when that is on (General ▸ Links), to a space. \(rulesSummary)")
            }
        }
        Section {
            ForEach(Array(sidebar.profiles.enumerated()), id: \.element.id) { index, profile in
                ProfileRow(profile: profile, isDefault: index == 0, counts: profiles.counts(profile.id), services: profiles)
            }
            HStack {
                TextField("New profile", text: $newProfileName, prompt: Text("Name"))
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

/// Settings ▸ Privacy's site permissions (4.4b): a permission type, then
/// every site with its own setting for it in the chosen profile, each changed
/// or reset (the site panel's types and choices).
struct SitePermissionsView: View {
    let sidebar: SidebarStore
    let profiles: ProfileServices
    @State private var profileID: UUID?
    @State private var permission: SitePermission = .notifications
    @State private var entries: [ContentSettingEntry] = []
    @State private var engineProfile: (any Engine.Profile)?

    var body: some View {
        Section {
            if sidebar.profiles.count > 1 {
                Picker("Profile", selection: Binding(get: { profileID ?? sidebar.profiles.first?.id }, set: { profileID = $0 })) {
                    ForEach(sidebar.profiles, id: \.id) { profile in Text(profile.name).tag(UUID?.some(profile.id)) }
                }
            }
            Picker("Permission", selection: $permission) {
                ForEach(SitePermission.allCases, id: \.self) { permission in
                    Label(SitePanelRules.title(for: permission), systemImage: SitePanelRules.symbol(for: permission)).tag(permission)
                }
            }
            if entries.isEmpty {
                Text("No site has its own setting. Sites use the default: \(SitePanelRules.optionTitle(SitePanelRules.defaultSetting(for: permission), for: permission)).")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries, id: \.pattern) { entry in
                LabeledContent {
                    HStack(spacing: 6) {
                        Picker("", selection: Binding(get: { entry.setting }, set: { set($0, entry) })) {
                            ForEach(SitePanelRules.options(for: permission), id: \.self) { option in
                                Text(SitePanelRules.optionTitle(option, for: permission)).tag(option)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Reset") { set(nil, entry) }
                            .disabled(entry.origin == nil)
                    }
                } label: {
                    Text(entry.pattern)
                    if entry.isEmbedded { Text("Where it is embedded in another site").foregroundStyle(.secondary) }
                }
            }
        } header: {
            Text("Site permissions")
        } footer: {
            Text("What sites asked for and what you chose, here or from the site button in the sidebar's header. Reset returns a site to the default.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .task(id: TaskKey(profile: profileID ?? sidebar.profiles.first?.id, permission: permission)) { await reload() }
        // A prompt answered or the site panel used while Settings was away: the list is read again when it shows.
        .onAppear { Task { await reload() } }
    }

    private struct TaskKey: Hashable {
        let profile: UUID?
        let permission: SitePermission
    }

    private func reload() async {
        guard let id = profileID ?? sidebar.profiles.first?.id else { return }
        engineProfile = await profiles.engineProfile(id)
        entries = engineProfile?.contentSettings(ofType: permission) ?? []
    }

    private func set(_ setting: PermissionSetting?, _ entry: ContentSettingEntry) {
        guard let origin = entry.origin, let engineProfile else { return }
        engineProfile.setPermissionSetting(setting, for: permission, origin: origin)
        entries = engineProfile.contentSettings(ofType: permission)
    }
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

/// The one-line statements of Settings ▸ Privacy (4.4b; the user's
/// decisions of 2026-10-06: B-63, B-68, B-72, B-74, B-27, Safe Browsing).
enum PrivacyStatements {
    static let lines: [(title: String, text: String)] = [
        ("Translation", "Room does not offer page translation: it needs a Google API key, which Room does not ship."),
        ("Password suggestions", "Room does not suggest strong passwords: Chromium offers them only with Google's password sync, which Room does not have. Passwords you type are saved."),
        ("Spelling", "Spelling is checked on this Mac by macOS. Enhanced Spell Check, which sends what you type to Google, is not offered."),
        ("Safe Browsing", "Off: Room does not check the pages you open against Google's list of dangerous sites."),
        ("Zoom", "Zoom applies per site, as in Chrome: zooming one page zooms the site's other pages, and the level is remembered."),
        ("Extensions", "Extensions you install make their own requests (their updates and their own servers): those are the extension's, not Room's."),
    ]
}
