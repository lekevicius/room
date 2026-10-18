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
/// uBlock Origin's scriptlets (GPLv3, never bundled) come with uBO's lists:
/// fetched from the pinned tag when the first one is turned on, converted in
/// JavaScriptCore and merged with Room's redirect bodies (`UBlockScriptlets`).
@Observable
final class ContentBlockingController {
    /// One downloaded list's facts, kept beside the files.
    struct ListRecord: Codable, Hashable {
        var fetched: Date
        var expiry: TimeInterval?
        var ruleCount: Int
        var title: String?
    }

    /// uBO's scriptlets as converted, kept beside the lists.
    struct ScriptletsRecord: Codable, Hashable {
        var tag: String
        var fetched: Date
        var count: Int
    }

    enum ListStatus: Hashable {
        case idle
        case downloading
        case failed(String)
    }

    private(set) var records: [String: ListRecord] = [:]
    private(set) var status: [String: ListStatus] = [:]
    private(set) var scriptlets: ScriptletsRecord?
    private(set) var scriptletStatus: ListStatus = .idle
    private(set) var lastReport: ContentBlockingReport?
    /// Rules per list id of the lists in use (bundled ones counted once).
    private(set) var ruleCounts: [String: Int] = [:]

    @ObservationIgnored private let engine: any ContentBlocking
    @ObservationIgnored private let siteResolver: (URL) -> String?
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let bundleDirectory: URL
    @ObservationIgnored private let listsDirectory: URL
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let scriptletsDirectory: URL
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
        scriptletsDirectory = stateDirectory.appending(path: "ContentBlocking/Scriptlets")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        records = Self.readRecords(at: recordsURL)
        scriptlets = (try? Data(contentsOf: scriptletsRecordURL)).flatMap { try? JSONDecoder().decode(ScriptletsRecord.self, from: $0) }
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
        await updateScriptletsIfStale(reason: "update now")
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
            // uBO's lists bring uBO's scriptlets; turning the first one on is their request too.
            let wantsScriptlets = UBlockScriptlets.needed(by: plan.lists)
            if wantsScriptlets, !hasScriptlets, scriptletStatus != .downloading {
                await fetchScriptlets(reason: "turned on")
            }
            scheduleUpdates(current.automaticListUpdates)
            let configuration = ContentBlockingConfiguration(
                isEnabled: plan.isEnabled,
                lists: plan.lists.map {
                    ContentBlockingList(fileURL: $0.fileURL, isHostsFormat: $0.isHostsFormat, isTrusted: $0.isTrusted)
                },
                customRules: plan.customRules,
                resourcesURL: wantsScriptlets && hasScriptlets ? await mergedResources() : roomResourcesURL,
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

    /// Settings' rule counts, off the main thread (reading the bundled lists
    /// takes a few hundred milliseconds; the first page does not wait for it).
    private func countRules(_ lists: [PlannedFilterList]) {
        var counts: [String: Int] = [:]
        var toCount: [(id: String, url: URL)] = []
        for list in lists {
            if let record = records[list.id], list.fileURL == fileURL(for: list.id) {
                counts[list.id] = record.ruleCount
            } else if let cached = ruleCounts[list.id] {
                counts[list.id] = cached
            } else {
                toCount.append((list.id, list.fileURL))
            }
        }
        ruleCounts = counts
        guard !toCount.isEmpty else { return }
        let items = toCount.map { ListFile(id: $0.id, url: $0.url) }
        Task { [weakSelf = MainActorWeak(self)] in
            let counted = await Task.detached(priority: .utility) { Self.countRules(in: items) }.value
            guard let self = weakSelf.value else { return }
            for (id, count) in counted { self.ruleCounts[id] = count }
        }
    }

    struct ListFile: Sendable {
        let id: String
        let url: URL
    }

    nonisolated private static func countRules(in files: [ListFile]) -> [(String, Int)] {
        files.compactMap { file in
            guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { return nil }
            return (file.id, FilterListText.ruleCount(text))
        }
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

    // MARK: uBlock Origin's scriptlets

    private var roomResourcesURL: URL { bundleDirectory.appending(path: "redirect-resources.json") }
    private var scriptletsURL: URL { scriptletsDirectory.appending(path: "ublock-scriptlets.json") }
    private var scriptletsRecordURL: URL { scriptletsDirectory.appending(path: "ublock-scriptlets-record.json") }
    /// Room's redirect bodies and uBO's scriptlets: the engine's resources while a uBO list is on.
    private var mergedResourcesURL: URL { scriptletsDirectory.appending(path: "resources.json") }

    var hasScriptlets: Bool { scriptlets != nil && FileManager.default.fileExists(atPath: scriptletsURL.path) }

    /// A new pinned tag (a Room update) is fetched only on the user's next
    /// request: Update Now or an automatic update. Until then the old ones serve.
    private func updateScriptletsIfStale(reason: String) async {
        let plan = ContentBlockingPlan.make(settings: settingsValue, bundleDirectory: bundleDirectory, downloads: downloads())
        guard UBlockScriptlets.needed(by: plan.lists), scriptlets?.tag != UBlockScriptlets.tag,
              scriptletStatus != .downloading else { return }
        await fetchScriptlets(reason: reason)
    }

    /// uBO's modules from the pinned tag, linked and evaluated in
    /// JavaScriptCore off the main thread; the result is adblock-rust resources.
    private func fetchScriptlets(reason: String) async {
        NSLog("Room: content blocking: fetching uBlock Origin %@ scriptlets (%@): %@",
              UBlockScriptlets.tag, reason, UBlockScriptlets.baseURL.absoluteString)
        scriptletStatus = .downloading
        let session = session
        let started = ContinuousClock.now
        do {
            let resources = try await Task.detached(priority: .userInitiated) {
                let modules = try await ScriptletModules.collect { path in
                    try await Self.text(at: UBlockScriptlets.sourceURL(path), session: session)
                }
                let scriptlets = try ScriptletModules.scriptlets(fromLinked: try ScriptletModules.link(modules))
                return ScriptletResources.resources(from: scriptlets)
            }.value
            try FileManager.default.createDirectory(at: scriptletsDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(resources).write(to: scriptletsURL, options: .atomic)
            let record = ScriptletsRecord(tag: UBlockScriptlets.tag, fetched: .now, count: resources.count)
            try JSONEncoder().encode(record).write(to: scriptletsRecordURL, options: .atomic)
            scriptlets = record
            scriptletStatus = .idle
            let missing = ScriptletResources.missingDependencies(resources)
            NSLog("Room: content blocking: %d uBlock Origin scriptlets in %.0f ms%@", resources.count,
                  (ContinuousClock.now - started) / .milliseconds(1),
                  missing.isEmpty ? "" : ", missing dependencies: " + missing.joined(separator: ", "))
        } catch {
            NSLog("Room: content blocking: uBlock Origin scriptlets failed: %@", String(describing: error))
            scriptletStatus = .failed(String(describing: error))
        }
    }

    /// Writes Room's resources merged with uBO's (only when they changed, so
    /// the engine's cache key holds); Room's alone when that fails.
    private func mergedResources() async -> URL {
        let room = roomResourcesURL, ublock = scriptletsURL, merged = mergedResourcesURL
        let written = await Task.detached(priority: .userInitiated) { () -> Bool in
            do {
                let decoder = JSONDecoder()
                let resources = ScriptletResources.merge(
                    room: try decoder.decode([AdblockResource].self, from: Data(contentsOf: room)),
                    added: try decoder.decode([AdblockResource].self, from: Data(contentsOf: ublock)))
                let data = try JSONEncoder().encode(resources)
                if (try? Data(contentsOf: merged)) != data { try data.write(to: merged, options: .atomic) }
                return true
            } catch {
                NSLog("Room: content blocking: merging resources failed: %@", String(describing: error))
                return false
            }
        }.value
        return written ? merged : room
    }

    nonisolated private static func text(at url: URL, session: URLSession) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLErrorKey: url])
        }
        guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return text
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
        let staleScriptlets = scriptlets.map { $0.tag != UBlockScriptlets.tag } ?? false
        guard !due.isEmpty || staleScriptlets else { return }
        await download(due.map(\.id), reason: "automatic update")
        await updateScriptletsIfStale(reason: "automatic update")
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
