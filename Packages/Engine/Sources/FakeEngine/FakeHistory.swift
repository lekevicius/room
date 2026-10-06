import Foundation
import Engine

/// An in-memory `ProfileHistory` (Phase 3.5) for host tests: the palette's
/// engine path, ⌘Y and the Chapter 2 import. Answers at once.
public final class FakeHistory: ProfileHistory {
    /// URLs by spec, with their visits.
    public private(set) var entries: [String: (entry: HistoryEntry, visits: [HistoryVisit])] = [:]
    /// Every `importEntries` call's size, in order (the migration-once rule).
    public private(set) var importCalls: [Int] = []
    /// Visits older than this are left out of an import (Chromium keeps 90 days).
    public var retention: TimeInterval = 90 * 86_400
    public var now: () -> Date = Date.init

    public init() {}

    /// Records a visit as browsing would.
    public func addVisit(_ url: URL, title: String, transition: PageTransition = .link, at time: Date? = nil) {
        let time = time ?? now()
        var record = entries[url.absoluteString] ?? (HistoryEntry(url: url, title: title), [])
        record.entry.title = title
        record.entry.visitCount += 1
        if transition == .typed { record.entry.typedCount += 1 }
        record.entry.lastVisit = max(record.entry.lastVisit ?? time, time)
        record.visits.append(HistoryVisit(time: time, transition: transition))
        entries[url.absoluteString] = record
    }

    /// Clear browsing data's history kind: every visit at or after `start`
    /// (`nil`: all) goes, and a URL left without visits with it.
    public func deleteVisits(since start: Date?) {
        for (key, record) in entries {
            let kept = record.visits.filter { visit in start.map { visit.time < $0 } ?? false }
            if kept.isEmpty {
                entries[key] = nil
            } else if kept.count != record.visits.count {
                var entry = record.entry
                entry.visitCount = kept.count
                entry.lastVisit = kept.map(\.time).max()
                entries[key] = (entry, kept)
            }
        }
    }

    public func search(_ text: String, limit: Int) async -> [HistoryEntry] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        return Array(sortedByRecency.filter { entry in
            let haystack = (entry.title + " " + entry.url.absoluteString).lowercased()
            return words.allSatisfy(haystack.contains)
        }.prefix(limit > 0 ? limit : .max))
    }

    public func entries(from start: Date?, to end: Date?, limit: Int) async -> [HistoryEntry] {
        Array(sortedByRecency.filter { entry in
            guard let last = entry.lastVisit else { return false }
            return (start.map { last >= $0 } ?? true) && (end.map { last < $0 } ?? true)
        }.prefix(limit > 0 ? limit : .max))
    }

    public func visits(for url: URL) async -> (entry: HistoryEntry, visits: [HistoryVisit])? {
        entries[url.absoluteString]
    }

    public func mostVisited(limit: Int) async -> [HistoryEntry] {
        Array(entries.values.map(\.entry).sorted { ($0.visitCount, $0.lastVisit ?? .distantPast) > ($1.visitCount, $1.lastVisit ?? .distantPast) }
            .prefix(limit))
    }

    public func delete(url: URL) {
        entries[url.absoluteString] = nil
    }

    @discardableResult
    public func delete(host: String) async -> Int {
        let bare = Self.bare(host)
        let doomed = entries.keys.filter { URL(string: $0).flatMap { $0.host() }.map(Self.bare) == bare }
        for key in doomed { entries[key] = nil }
        return doomed.count
    }

    public func importEntries(_ imports: [HistoryImportEntry]) async -> HistoryImportResult {
        importCalls.append(imports.count)
        var result = HistoryImportResult()
        let cutoff = now().addingTimeInterval(-retention)
        for item in imports {
            let kept = item.visits.filter { $0.transition != .reload && $0.time >= cutoff }
            result.expiredVisits += item.visits.filter { $0.time < cutoff }.count
            guard !kept.isEmpty else {
                result.expiredURLs += 1
                continue
            }
            for visit in kept { addVisit(item.url, title: item.title ?? "", transition: visit.transition, at: visit.time) }
            result.urls += 1
            result.visits += kept.count
        }
        return result
    }

    private var sortedByRecency: [HistoryEntry] {
        entries.values.map(\.entry).sorted { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
    }

    static func bare(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}

/// An `AutocompleteController` over a `FakeHistory`, shaped like Chromium's:
/// the synchronous pass reaches the delegate from inside `start`, history
/// matches carry Chromium-like relevances, a typed host completes inline,
/// and `.search` adds the suggestions a test gives (`suggestions`), as the
/// engine's SearchProvider would.
public final class FakeAutocompleteController: AutocompleteController {
    public weak var delegate: (any AutocompleteControllerDelegate)?
    public private(set) var matches: [AutocompleteMatch] = []
    public private(set) var isDone = true
    /// Every input `start` received, in order (the switch rule's evidence).
    public private(set) var starts: [AutocompleteInput] = []
    public private(set) var stops = 0
    public private(set) var deletedIndices: [Int] = []
    /// The engine's search suggestions for a text (only used with `.search`).
    public var suggestions: (String) -> [String] = { _ in [] }

    private let history: FakeHistory

    public init(history: FakeHistory) {
        self.history = history
    }

    public func start(_ input: AutocompleteInput) {
        starts.append(input)
        let text = input.text.lowercased()
        var result: [AutocompleteMatch] = []
        if input.providers.contains(.historyQuick) || input.providers.contains(.historyURL), !text.isEmpty {
            let rows = history.entries.values.map(\.entry).filter { entry in
                (entry.title + " " + entry.url.absoluteString).lowercased().contains(text)
            }.sorted { ($0.typedCount, $0.visitCount, $0.url.absoluteString) > ($1.typedCount, $1.visitCount, $1.url.absoluteString) }
            for (index, row) in rows.prefix(8).enumerated() {
                let host = row.url.host().map(FakeHistory.bare) ?? ""
                let inline = index == 0 && !input.preventsInlineCompletion && row.typedCount > 0 && host.hasPrefix(text) && host.count > text.count
                    ? String(host.dropFirst(text.count)) : ""
                result.append(AutocompleteMatch(contents: row.url.absoluteString, description: row.title, destinationURL: row.url,
                                                fillIntoEdit: host, inlineCompletion: inline, relevance: 1400 - index * 50,
                                                kind: .historyURL, provider: .historyQuick, isDeletable: true,
                                                allowedToBeDefault: !inline.isEmpty))
            }
        }
        if input.providers.contains(.search), !text.isEmpty {
            for (index, suggestion) in suggestions(input.text).enumerated() {
                result.append(AutocompleteMatch(contents: suggestion, destinationURL: URL(string: "https://search.example/?q=\(index)"),
                                                fillIntoEdit: suggestion, relevance: 600 - index, kind: .searchSuggest, provider: .search))
            }
        }
        matches = result.sorted { $0.relevance > $1.relevance }
        isDone = true
        delegate?.autocompleteControllerDidUpdate(self)
    }

    /// An asynchronous pass: the result becomes `matches`, then the delegate hears it.
    public func simulateUpdate(_ matches: [AutocompleteMatch], done: Bool = true) {
        self.matches = matches
        isDone = done
        delegate?.autocompleteControllerDidUpdate(self)
    }

    public func stop() {
        stops += 1
        isDone = true
    }

    public func deleteMatch(at index: Int) {
        guard matches.indices.contains(index), matches[index].isDeletable else { return }
        deletedIndices.append(index)
        if let url = matches[index].destinationURL { history.delete(url: url) }
        matches.remove(at: index)
        delegate?.autocompleteControllerDidUpdate(self)
    }
}
