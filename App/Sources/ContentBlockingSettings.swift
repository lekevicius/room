import Engine
import Integration
import Model
import SwiftUI

/// Settings ▸ Privacy ▸ Ads and trackers (B-30): Room's built-in blocker.
/// Everything here is Room's own UI; the engine only receives the result.
struct ContentBlockingSettingsView: View {
    let controller: ContentBlockingController
    @State private var rulesDraft: String?
    @State private var newListURL = ""
    @State private var newSite = ""
    @State private var updating = false

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
        } header: {
            Text("Ads and trackers")
        } footer: {
            Text("Blocking runs on this Mac with open-source lists and code (adblock-rust, DuckDuckGo's autoconsent). Turn it off for one site from the site button in the sidebar's header.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        lists
        customRules
        allowedSites
    }

    private var cookieBannerExplanation: String {
        switch value.cookieBanners {
        case .reject: "Room answers the banner for you, choosing only the necessary cookies, and hides it."
        case .hide: "Room hides banners without answering them."
        case .off: "Banners show as the site draws them."
        }
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
        return line
    }

    // MARK: Custom rules

    @ViewBuilder private var customRules: some View {
        Section {
            TextEditor(text: Binding(get: { rulesDraft ?? value.customRules }, set: { rulesDraft = $0 }))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .accessibilityIdentifier("blocking-custom-rules")
            HStack {
                Text("One rule per line in filter-list syntax, e.g. ||ads.example.com^ or example.com##.banner.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Apply") {
                    if let draft = rulesDraft { controller.update { $0.customRules = draft } }
                    rulesDraft = nil
                }
                .disabled(rulesDraft == nil || rulesDraft == value.customRules)
            }
        } header: {
            Text("Custom rules")
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
