import Foundation
import Engine
import RoomCore

/// `ProfileHistory` over `RoomProfileHistory` (Chromium's `HistoryService`
/// for the profile, Phase 3.5).
public final class RoomCoreHistory: ProfileHistory {
    let history: RoomProfileHistory

    init(history: RoomProfileHistory) {
        self.history = history
    }

    /// `QueryHistory` with the text, duplicates removed.
    public func search(_ text: String, limit: Int) async -> [HistoryEntry] {
        await withCheckedContinuation { continuation in
            history.search(text, maxCount: limit) { continuation.resume(returning: $0.map(HistoryEntry.init)) }
        }
    }

    /// `QueryHistory` with a time range and no text.
    public func entries(from start: Date?, to end: Date?, limit: Int) async -> [HistoryEntry] {
        await withCheckedContinuation { continuation in
            history.entries(from: start, to: end, maxCount: limit) { continuation.resume(returning: $0.map(HistoryEntry.init)) }
        }
    }

    /// `QueryURLAndVisits`.
    public func visits(for url: URL) async -> (entry: HistoryEntry, visits: [HistoryVisit])? {
        await withCheckedContinuation { continuation in
            history.visits(for: url) { entry, visits in
                guard let entry else { return continuation.resume(returning: nil) }
                continuation.resume(returning: (HistoryEntry(entry), visits.map { HistoryVisit(time: $0.time, transition: PageTransition($0.transition)) }))
            }
        }
    }

    /// `QueryMostVisitedURLs` (TopSites' scoring).
    public func mostVisited(limit: Int) async -> [HistoryEntry] {
        await withCheckedContinuation { continuation in
            history.mostVisited(maxCount: limit) { continuation.resume(returning: $0.map(HistoryEntry.init)) }
        }
    }

    /// `DeleteURLs`.
    public func delete(url: URL) {
        history.delete([url])
    }

    /// `QueryHistory` on hostnames, then `DeleteURLs` for the exact host's.
    @discardableResult
    public func delete(host: String) async -> Int {
        await withCheckedContinuation { continuation in
            history.deleteHost(host) { continuation.resume(returning: $0) }
        }
    }

    /// `AddPagesWithDetails`, then the earlier visits with their times (a `HistoryDBTask`).
    public func importEntries(_ entries: [HistoryImportEntry]) async -> HistoryImportResult {
        let imports = entries.map { entry in
            RoomHistoryImportEntry(url: entry.url, title: entry.title,
                                   visits: entry.visits.map { RoomHistoryVisit(time: $0.time, transition: RoomHistoryTransition($0.transition)) })
        }
        return await withCheckedContinuation { continuation in
            history.importEntries(imports) { result in
                continuation.resume(returning: HistoryImportResult(urls: result.urls, visits: result.visits,
                                                                   expiredVisits: result.expiredVisits, expiredURLs: result.expiredURLs))
            }
        }
    }
}

/// `AutocompleteController` over `RoomAutocompleteController` (Chromium's
/// omnibox `AutocompleteController` with `ChromeAutocompleteProviderClient`).
/// Chromium fixes a controller's providers at construction, so RoomCore keeps
/// one per provider set and the host's per-call choice picks one.
public final class RoomCoreAutocompleteController: NSObject, AutocompleteController, RoomAutocompleteControllerDelegate {
    public weak var delegate: (any AutocompleteControllerDelegate)?
    public private(set) var matches: [AutocompleteMatch] = []
    let controller: RoomAutocompleteController

    init(controller: RoomAutocompleteController) {
        self.controller = controller
        super.init()
        controller.delegate = self
    }

    public func start(_ input: AutocompleteInput) {
        controller.start(text: input.text, cursorPosition: input.cursorPosition ?? (input.text as NSString).length,
                         preventInlineAutocomplete: input.preventsInlineCompletion, keywordMode: input.keywordMode,
                         providers: RoomAutocompleteProviders(input.providers))
    }

    public func stop() {
        controller.stop()
    }

    public var isDone: Bool { controller.isDone }

    public func deleteMatch(at index: Int) {
        controller.deleteMatch(at: index)
    }

    public func autocompleteControllerDidUpdateResult(_ controller: RoomAutocompleteController) {
        matches = controller.matches.map(AutocompleteMatch.init)
        delegate?.autocompleteControllerDidUpdate(self)
    }
}

extension HistoryEntry {
    init(_ entry: RoomHistoryEntry) {
        self.init(url: entry.url, title: entry.title, visitCount: entry.visitCount, typedCount: entry.typedCount, lastVisit: entry.lastVisit)
    }
}

extension PageTransition {
    init(_ transition: RoomHistoryTransition) {
        self = switch transition {
        case .typed: .typed
        case .bookmark: .bookmark
        case .generated: .generated
        case .keyword: .keyword
        case .formSubmit: .formSubmit
        case .reload: .reload
        case .other: .other
        default: .link
        }
    }
}

extension RoomHistoryTransition {
    init(_ transition: PageTransition) {
        self = switch transition {
        case .link: .link
        case .typed: .typed
        case .bookmark: .bookmark
        case .generated: .generated
        case .keyword: .keyword
        case .formSubmit: .formSubmit
        case .reload: .reload
        case .other: .other
        }
    }
}

extension RoomAutocompleteProviders {
    init(_ providers: AutocompleteProviders) {
        var value: RoomAutocompleteProviders = []
        if providers.contains(.historyQuick) { value.insert(.historyQuick) }
        if providers.contains(.historyURL) { value.insert(.historyURL) }
        if providers.contains(.bookmark) { value.insert(.bookmark) }
        if providers.contains(.shortcuts) { value.insert(.shortcuts) }
        if providers.contains(.openTab) { value.insert(.openTab) }
        if providers.contains(.search) { value.insert(.search) }
        self = value
    }
}

extension AutocompleteProviders {
    init(_ providers: RoomAutocompleteProviders) {
        var value: AutocompleteProviders = []
        if providers.contains(.historyQuick) { value.insert(.historyQuick) }
        if providers.contains(.historyURL) { value.insert(.historyURL) }
        if providers.contains(.bookmark) { value.insert(.bookmark) }
        if providers.contains(.shortcuts) { value.insert(.shortcuts) }
        if providers.contains(.openTab) { value.insert(.openTab) }
        if providers.contains(.search) { value.insert(.search) }
        self = value
    }
}

extension AutocompleteMatch {
    init(_ match: RoomAutocompleteMatch) {
        let kind: AutocompleteMatchKind = switch match.type {
        case .urlWhatYouTyped: .urlWhatYouTyped
        case .historyURL: .historyURL
        case .historyTitle: .historyTitle
        case .historyBody: .historyBody
        case .historyKeyword: .historyKeyword
        case .navSuggest: .navSuggest
        case .searchWhatYouTyped: .searchWhatYouTyped
        case .searchHistory: .searchHistory
        case .searchSuggest: .searchSuggest
        case .searchOtherEngine: .searchOtherEngine
        case .bookmarkTitle: .bookmarkTitle
        case .openTab: .openTab
        default: .other
        }
        self.init(contents: match.contents, description: match.matchDescription, destinationURL: match.destinationURL,
                  fillIntoEdit: match.fillIntoEdit, inlineCompletion: match.inlineAutocompletion, relevance: match.relevance, kind: kind,
                  provider: AutocompleteProviders(match.provider), isDeletable: match.isDeletable, hasTabMatch: match.hasTabMatch,
                  allowedToBeDefault: match.allowedToBeDefault)
    }
}
