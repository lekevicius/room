import Engine
import Integration
import Model
import SwiftUI

/// Settings ▸ Privacy ▸ Ads and trackers (B-30): Room's built-in blocker.
/// Everything here is Room's own UI; the engine only receives the result.
/// 5.7a (B-120): the pane keeps the switches and one summary row per list;
/// the list catalogue, the custom rules and the allowed sites open in sheets.
struct ContentBlockingSettingsView: View {
    let controller: ContentBlockingController
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case lists, rules, sites
        var id: String { rawValue }
    }

    private var value: ContentBlockingSettings { controller.settingsValue }

    private func binding<T>(_ keyPath: WritableKeyPath<ContentBlockingSettings, T>) -> Binding<T> {
        Binding(get: { controller.settingsValue[keyPath: keyPath] },
                set: { newValue in controller.update { $0[keyPath: keyPath] = newValue } })
    }

    var body: some View {
        Section {
            Toggle(isOn: binding(\.blockAds)) {
                Text("Block ads")
                Text("EasyList, built into Room.")
            }
            .accessibilityIdentifier("blocking-ads")
            Toggle(isOn: binding(\.blockTrackers)) {
                Text("Block trackers")
                Text("EasyPrivacy, built into Room: analytics, tracking pixels and fingerprinting scripts.")
            }
            .accessibilityIdentifier("blocking-trackers")
            Picker(selection: binding(\.cookieBanners)) {
                Text("Reject").tag(CookieBannerSetting.reject)
                Text("Hide").tag(CookieBannerSetting.hide)
                Text("Leave alone").tag(CookieBannerSetting.off)
            } label: {
                Text("Cookie banners")
                Text(cookieBannerExplanation)
            }
            .accessibilityIdentifier("blocking-cookie-banners")
            LabeledContent {
                Button("Lists…") { sheet = .lists }.accessibilityIdentifier("blocking-lists-button")
            } label: {
                Text("Filter lists")
                Text(listsSummary)
            }
            LabeledContent {
                Button("Edit…") { sheet = .rules }.accessibilityIdentifier("blocking-rules-button")
            } label: {
                Text("Custom rules")
                Text(rulesSummary)
            }
            LabeledContent {
                Button("Edit…") { sheet = .sites }.accessibilityIdentifier("blocking-sites-button")
            } label: {
                Text("Allowed sites")
                Text(sitesSummary)
            }
        } header: {
            Text("Ads and trackers")
        } footer: {
            Text("Blocking runs on this Mac with open-source lists and code (adblock-rust, DuckDuckGo's autoconsent). Turn it off for one site from the site button in the sidebar's header.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(item: $sheet) { which in
            ContentBlockingSheet(controller: controller, which: which) { sheet = nil }
        }
    }

    private var listsSummary: String {
        let builtIn = FilterListCatalog.all.filter { $0.isBundled }.count
        let optional = value.enabledLists.count + value.customLists.filter(\.isEnabled).count
        let rules = controller.ruleCounts.values.reduce(0, +)
        var parts = ["\(builtIn) built in" + (optional > 0 ? ", \(optional) more turned on" : "")]
        if rules > 0 { parts.append("\(rules.formatted()) rules") }
        parts.append(value.automaticListUpdates ? "updated automatically" : "updated with Room")
        return parts.joined(separator: " · ")
    }

    private var rulesSummary: String {
        let count = value.customRules.split(whereSeparator: \.isNewline).count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return count == 0 ? "None." : "\(count) rule\(count == 1 ? "" : "s") of your own."
    }

    private var sitesSummary: String {
        let sites = value.allowedSites
        if sites.isEmpty { return "None: blocking is on everywhere." }
        let shown = sites.prefix(3).joined(separator: ", ")
        return sites.count > 3 ? "\(shown) and \(sites.count - 3) more" : shown
    }

    private var cookieBannerExplanation: String {
        switch value.cookieBanners {
        case .reject: "Room answers the banner for you, choosing only the necessary cookies, and hides it."
        case .hide: "Room hides banners without answering them."
        case .off: "Banners show as the site draws them."
        }
    }
}

/// The blocker's three lists in a sheet over Settings (5.7a, B-120).
struct ContentBlockingSheet: View {
    let controller: ContentBlockingController
    let which: ContentBlockingSettingsView.Sheet
    let dismiss: () -> Void
    @State private var rulesDraft: String?
    @State private var newListURL = ""
    @State private var newSite = ""
    @State private var updating = false

    private var value: ContentBlockingSettings { controller.settingsValue }

    private func binding<T>(_ keyPath: WritableKeyPath<ContentBlockingSettings, T>) -> Binding<T> {
        Binding(get: { controller.settingsValue[keyPath: keyPath] },
                set: { newValue in controller.update { $0[keyPath: keyPath] = newValue } })
    }

    private var title: String {
        switch which {
        case .lists: "Filter Lists"
        case .rules: "Custom Rules"
        case .sites: "Allowed Sites"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding([.top, .horizontal], 20)
            Form {
                switch which {
                case .lists: lists
                case .rules: customRules
                case .sites: allowedSites
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                if which == .rules {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Apply") {
                        if let draft = rulesDraft { controller.update { $0.customRules = draft } }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rulesDraft == nil || rulesDraft == value.customRules)
                } else {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: ContentBlockingSheetMetrics.width, height: ContentBlockingSheetMetrics.height)
    }

    // MARK: Lists

    @ViewBuilder private var lists: some View {
        Section {
            ForEach(FilterListCatalog.all) { info in
                listRow(info)
            }
            ForEach(value.customLists) { custom in
                LabeledContent {
                    HStack {
                        statusView(custom.id.uuidString)
                        Toggle("", isOn: Binding(
                            get: { controller.settingsValue.customLists.first { $0.id == custom.id }?.isEnabled ?? false },
                            set: { on in controller.update { s in
                                if let i = s.customLists.firstIndex(where: { $0.id == custom.id }) { s.customLists[i].isEnabled = on }
                            } }))
                            .labelsHidden()
                        Button("Remove", role: .destructive) { controller.removeCustomList(custom.id) }
                            .buttonStyle(.borderless)
                    }
                } label: {
                    Text(custom.title)
                    Text(custom.url.absoluteString).lineLimit(1).truncationMode(.middle)
                }
            }
            HStack {
                TextField("List URL", text: $newListURL, prompt: Text("https://…/list.txt"))
                    .accessibilityIdentifier("blocking-new-list")
                Button("Add List") {
                    if let url = URL(string: newListURL.trimmingCharacters(in: .whitespaces)) {
                        controller.addCustomList(url)
                        newListURL = ""
                    }
                }
                .disabled(URL(string: newListURL)?.scheme?.hasPrefix("http") != true)
            }
            Toggle(isOn: binding(\.automaticListUpdates)) {
                Text("Update lists automatically")
                Text("Room fetches each list in use from its own server when the list says it is due (daily to weekly). Off: the built-in lists update with Room, the others only with Update Now.")
            }
            .accessibilityIdentifier("blocking-automatic-updates")
            LabeledContent {
                Button(updating ? "Updating…" : "Update Now") {
                    updating = true
                    Task {
                        await controller.updateNow()
                        updating = false
                    }
                }
                .disabled(updating)
            } label: {
                Text(reportLine)
            }
        } header: {
            Text("Lists")
        } footer: {
            Text("Turning on a list that is not built in, or adding one by URL, downloads it from the address shown.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func listRow(_ info: FilterListInfo) -> some View {
        LabeledContent {
            HStack {
                statusView(info.id)
                if !info.isBundled {
                    Toggle("", isOn: Binding(
                        get: { controller.settingsValue.enabledLists.contains(info.id) },
                        set: { on in controller.update { $0.setList(info.id, enabled: on) } }))
                        .labelsHidden()
                        .accessibilityIdentifier("blocking-list-\(info.id)")
                }
            }
        } label: {
            Text(info.title)
            Text(listDetail(info))
        }
    }

    private func listDetail(_ info: FilterListInfo) -> String {
        var parts = [info.summary]
        if info.isBundled {
            parts.append("Built in")
        } else {
            parts.append("From \(info.sourceURL.host() ?? "")")
        }
        parts.append(info.licence)
        if let count = controller.ruleCounts[info.id] {
            parts.append("\(count.formatted()) rules")
        }
        if let fetched = controller.records[info.id]?.fetched {
            parts.append("updated \(fetched.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func statusView(_ id: String) -> some View {
        switch controller.status[id] ?? .idle {
        case .downloading: ProgressView().controlSize(.small)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(message)
        case .idle: EmptyView()
        }
    }

    private var reportLine: String {
        guard let report = controller.lastReport else { return "Loading the lists…" }
        let rules = controller.ruleCounts.values.reduce(0, +)
        let size = ByteCountFormatter.string(fromByteCount: Int64(report.engineBytes), countStyle: .memory)
        var line = "\(rules.formatted()) rules in use, \(size)"
        if !report.problems.isEmpty { line += " · \(report.problems.count) unreadable" }
        if value.enabledLists.contains(where: { FilterListCatalog.info($0)?.isTrusted == true }) {
            switch controller.scriptletStatus {
            case .downloading: line += " · fetching uBlock Origin's scriptlets"
            case .failed: line += " · uBlock Origin's scriptlets unavailable"
            case .idle:
                if let scriptlets = controller.scriptlets {
                    line += " · uBlock Origin \(scriptlets.tag): \(scriptlets.count) scriptlets"
                    if let redirects = scriptlets.redirects { line += ", \(redirects) redirect bodies" }
                }
            }
        }
        return line
    }

    // MARK: Custom rules

    @ViewBuilder private var customRules: some View {
        Section {
            TextEditor(text: Binding(get: { rulesDraft ?? value.customRules }, set: { rulesDraft = $0 }))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
                .accessibilityLabel("Custom rules")
                .accessibilityIdentifier("blocking-custom-rules")
        } footer: {
            Text("One rule per line in filter-list syntax, e.g. ||ads.example.com^ or example.com##.banner.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Allowed sites

    @ViewBuilder private var allowedSites: some View {
        Section {
            if value.allowedSites.isEmpty {
                Text("None: blocking is on everywhere.").foregroundStyle(.secondary)
            }
            ForEach(value.allowedSites, id: \.self) { site in
                LabeledContent(site) {
                    Button("Block Again") { controller.setBlocking(true, on: site) }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Site", text: $newSite, prompt: Text("example.com"))
                    .accessibilityIdentifier("blocking-new-site")
                Button("Allow") {
                    if let site = controller.site(of: newSite) { controller.setBlocking(false, on: site) }
                    newSite = ""
                }
                .disabled(controller.site(of: newSite) == nil)
            }
        } header: {
            Text("Allowed sites")
        } footer: {
            Text("Nothing is blocked or hidden on these sites, and their cookie banners are left alone.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

enum ContentBlockingSheetMetrics {
    /// Chosen: the Settings window's width less its margins; the lists scroll inside.
    static let width: CGFloat = 540
    static let height: CGFloat = 480
}
