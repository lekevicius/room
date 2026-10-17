import Engine
import Foundation
import Integration
import Model
import Observation
import Store

/// Room's built-in blocker on the app's side (B-30): turns Settings ▸
/// Privacy into the engine's configuration, keeps the downloaded lists, and
/// fetches a list only when the user asked for it: turning on an optional
/// list, adding one by URL, Update Now, or the "Update lists automatically"
/// switch (off by default; CLAUDE.md "no network calls the user did not ask
/// for"). The bundled lists (App/Resources/ContentBlocking) need no network.
@Observable
final class ContentBlockingController {
    /// One downloaded list's facts, kept beside the files.
    struct ListRecord: Codable, Hashable {
        var fetched: Date
        var expiry: TimeInterval?
        var ruleCount: Int
        var title: String?
    }

    enum ListStatus: Hashable {
        case idle
        case downloading
        case failed(String)
    }

    private(set) var records: [String: ListRecord] = [:]
    private(set) var status: [String: ListStatus] = [:]
    private(set) var lastReport: ContentBlockingReport?
    /// Rules per list id of the lists in use (bundled ones counted once).
    private(set) var ruleCounts: [String: Int] = [:]

    @ObservationIgnored private let engine: any ContentBlocking
    @ObservationIgnored private let siteResolver: (URL) -> String?
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let bundleDirectory: URL
    @ObservationIgnored private let listsDirectory: URL
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var lastApplied: ContentBlockingConfiguration?
    @ObservationIgnored private var updateTimer: Timer?
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var applyAgain = false

    init(engine: any ContentBlocking, settings: SettingsStore, stateDirectory: URL,
         site: @escaping (URL) -> String?,
         bundleDirectory: URL = Bundle.main.resourceURL!.appending(path: "ContentBlocking")) {
        self.engine = engine
        siteResolver = site
        self.settings = settings
        self.bundleDirectory = bundleDirectory
        listsDirectory = stateDirectory.appending(path: "ContentBlocking/Lists")
        cacheDirectory = stateDirectory.appending(path: "ContentBlocking/Engine")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        records = Self.readRecords(at: recordsURL)
    }

    var settingsValue: ContentBlockingSettings { settings.settings.contentBlocking }

    /// The first configuration, before any page loads (a page's requests
    /// are matched by the factories made when it commits), then every
    /// change of the settings.
    func start() async {
        await apply()
        observe()
    }

    // MARK: Settings ▸ Privacy

    func update(_ body: (inout ContentBlockingSettings) -> Void) {
        settings.update { body(&$0.contentBlocking) }
    }

    /// The site panel's switch: blocking on `site` (a registrable domain).
    func setBlocking(_ blocking: Bool, on site: String) {
        update { $0.setBlocking(blocking, on: site) }
    }

    /// The registrable domain the user typed ("news.example.co.uk" or a
    /// URL → "example.co.uk"), by the engine's Public Suffix List.
    func site(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        return url.flatMap(siteResolver)
    }

    func addCustomList(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        update { settings in
            guard !settings.customLists.contains(where: { $0.url == url }) else { return }
            settings.customLists.append(CustomFilterList(url: url))
        }
    }

    func removeCustomList(_ id: UUID) {
        update { $0.customLists.removeAll { $0.id == id } }
        try? FileManager.default.removeItem(at: fileURL(for: id.uuidString))
        records[id.uuidString] = nil
        writeRecords()
    }

    /// Update Now: every list in use that has a source, bundled ones included.
    func updateNow() async {
        let ids = sourcesInUse().map(\.id)
        await download(ids, reason: "update now")
        await apply()
    }

    // MARK: Applying

    private func observe() {
        withObservationTracking {
            _ = settings.settings.contentBlocking
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in
                guard let self = weakSelf.value else { return }
                await self.apply()
                self.observe()
            }
        }
    }

    func apply() async {
        if applying {
            applyAgain = true
            return
        }
        applying = true
        defer { applying = false }
        repeat {
            applyAgain = false
            let current = settingsValue
            var plan = ContentBlockingPlan.make(settings: current, bundleDirectory: bundleDirectory, downloads: downloads())
            // Lists the user just turned on or added: their first download is the request.
            if !plan.missing.isEmpty {
                await download(plan.missing.filter { status[$0] != .downloading }, reason: "turned on")
                plan = ContentBlockingPlan.make(settings: current, bundleDirectory: bundleDirectory, downloads: downloads())
            }
            scheduleUpdates(current.automaticListUpdates)
            let configuration = ContentBlockingConfiguration(
                isEnabled: plan.isEnabled,
                lists: plan.lists.map { ContentBlockingList(fileURL: $0.fileURL, isHostsFormat: $0.isHostsFormat) },
                customRules: plan.customRules,
                resourcesURL: bundleDirectory.appending(path: "redirect-resources.json"),
                cacheDirectory: cacheDirectory,
                allowedSites: plan.allowedSites,
                cookieBanners: CookieBannerMode(current.cookieBanners),
                cookieScriptURL: bundleDirectory.appending(path: "autoconsent-room.js"))
            guard configuration != lastApplied else { continue }
            lastApplied = configuration
            let report = await engine.apply(configuration)
            lastReport = report
            countRules(plan.lists)
            NSLog("Room: content blocking %@: %d lists, %@ in %.0f ms, %d bytes%@",
                  plan.isEnabled ? "on" : "off", plan.lists.count, report.fromCache ? "cached" : "built",
                  report.buildMilliseconds, report.engineBytes,
                  report.problems.isEmpty ? "" : ", problems: " + report.problems.joined(separator: "; "))
        } while applyAgain
    }

    private func countRules(_ lists: [PlannedFilterList]) {
        var counts: [String: Int] = [:]
        for list in lists {
            if let record = records[list.id], list.fileURL == fileURL(for: list.id) {
                counts[list.id] = record.ruleCount
            } else if let cached = ruleCounts[list.id] {
                counts[list.id] = cached
            } else if let text = try? String(contentsOf: list.fileURL, encoding: .utf8) {
                counts[list.id] = FilterListText.ruleCount(text)
            }
        }
        ruleCounts = counts
    }

    // MARK: Lists on disk

    private var recordsURL: URL { listsDirectory.appending(path: "lists.json") }

    private func fileURL(for id: String) -> URL { listsDirectory.appending(path: "\(id).txt") }

    private func downloads() -> [String: URL] {
        var files: [String: URL] = [:]
        for id in records.keys where FileManager.default.fileExists(atPath: fileURL(for: id).path) {
            files[id] = fileURL(for: id)
        }
        return files
    }

    /// The lists in use that can be fetched: catalogue lists (bundled ones
    /// for their updates) and enabled custom lists.
    private func sourcesInUse() -> [(id: String, url: URL)] {
        let current = settingsValue
        let plan = ContentBlockingPlan.make(settings: current, bundleDirectory: bundleDirectory, downloads: downloads())
        let inUse = Set(plan.lists.map(\.id)).union(plan.missing)
        var sources: [(id: String, url: URL)] = []
        for info in FilterListCatalog.all where inUse.contains(info.id) {
            sources.append((info.id, info.sourceURL))
        }
        for custom in current.customLists where custom.isEnabled && inUse.contains(custom.id.uuidString) {
            sources.append((custom.id.uuidString, custom.url))
        }
        return sources
    }

    private func sourceURL(for id: String) -> URL? {
        if let info = FilterListCatalog.info(id) { return info.sourceURL }
        return settingsValue.customLists.first { $0.id.uuidString == id }?.url
    }

    private func download(_ ids: [String], reason: String) async {
        guard !ids.isEmpty else { return }
        try? FileManager.default.createDirectory(at: listsDirectory, withIntermediateDirectories: true)
        // In parallel, each on the main actor between its awaits.
        let fetches = ids.compactMap { id -> Task<Void, Never>? in
            guard let url = sourceURL(for: id) else { return nil }
            status[id] = .downloading
            return Task { await self.fetch(id: id, from: url, reason: reason) }
        }
        for fetch in fetches { await fetch.value }
        writeRecords()
    }

    private func fetch(id: String, from url: URL, reason: String) async {
        NSLog("Room: content blocking: fetching %@ (%@): %@", id, reason, url.absoluteString)
        do {
            var request = URLRequest(url: url)
            request.setValue("text/plain", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard let text = String(data: data, encoding: .utf8), FilterListText.looksLikeFilterList(text) else {
                throw URLError(.cannotParseResponse)
            }
            try data.write(to: fileURL(for: id), options: .atomic)
            records[id] = ListRecord(fetched: .now, expiry: FilterListText.expiry(of: text),
                                     ruleCount: FilterListText.ruleCount(text), title: FilterListText.title(of: text))
            status[id] = .idle
            if let uuid = UUID(uuidString: id), let title = FilterListText.title(of: text) {
                update { settings in
                    if let index = settings.customLists.firstIndex(where: { $0.id == uuid }) {
                        settings.customLists[index].title = title
                    }
                }
            }
        } catch {
            NSLog("Room: content blocking: %@ failed: %@", id, error.localizedDescription)
            status[id] = .failed(error.localizedDescription)
        }
    }

    // MARK: Automatic updates (opt-in)

    private func scheduleUpdates(_ on: Bool) {
        guard on else {
            updateTimer?.invalidate()
            updateTimer = nil
            return
        }
        guard updateTimer == nil else { return }
        let timer = Timer(timeInterval: 3_600, repeats: true) { [weakSelf = MainActorWeak(self)] _ in
            Task { @MainActor in await weakSelf.value?.updateDueLists() }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        Task { await updateDueLists() }
    }

    private func updateDueLists() async {
        guard settingsValue.automaticListUpdates else { return }
        let due = sourcesInUse().filter {
            FilterListSchedule.isDue(lastFetched: records[$0.id]?.fetched, expiry: records[$0.id]?.expiry, now: .now)
        }
        guard !due.isEmpty else { return }
        await download(due.map(\.id), reason: "automatic update")
        await apply()
    }

    private static func readRecords(at url: URL) -> [String: ListRecord] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: ListRecord].self, from: data)) ?? [:]
    }

    private func writeRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(at: listsDirectory, withIntermediateDirectories: true)
        try? data.write(to: recordsURL, options: .atomic)
    }
}

extension CookieBannerMode {
    init(_ setting: CookieBannerSetting) {
        switch setting {
        case .reject: self = .reject
        case .hide: self = .hide
        case .off: self = .off
        }
    }
}
