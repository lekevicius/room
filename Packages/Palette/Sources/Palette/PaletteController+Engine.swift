import AppKit
import Engine
import Omnibox

/// The engine path (Phase 3.5): on RoomCore the palette asks Chrome's
/// `AutocompleteController` per keystroke for history (and, while the
/// suggestions switch is on, search suggestions), maps its matches into
/// Room's bands (`EngineHistoryProvider`, `EngineSuggestProvider`) and ranks
/// them with its own providers through the one scorer. Chrome answers its
/// synchronous pass from inside `start` (HistoryQuick's in-memory index, the
/// typed-URL database), so most history rows land in the keystroke's own
/// turn; asynchronous passes re-rank with the highlighted row kept.
extension PaletteController: AutocompleteControllerDelegate {
    /// The active space's profile's controller, made on first use; `nil` on
    /// engines without an omnibox.
    func currentAutocomplete() -> (any AutocompleteController)? {
        guard let profile = sidebar.activeSpace?.profileID else { return nil }
        if let controller = autocompleteControllers[profile] { return controller }
        guard let controller = makeAutocomplete(profile) else { return nil }
        controller.delegate = self
        autocompleteControllers[profile] = controller
        return controller
    }

    /// Whether the engine's omnibox answers this palette (the spikes report it).
    public var usesEngineAutocomplete: Bool { currentAutocomplete() != nil }

    /// Starts the engine on the current input with the providers the switch allows.
    func startEngine() {
        guard let engine = currentAutocomplete() else {
            engineMatches = []
            return
        }
        if let active = activeAutocomplete, active !== engine { active.stop() }
        activeAutocomplete = engine
        guard !isUnchangedEdit, !input.isEmpty, input.mode != .commands else {
            engine.stop()
            engineMatches = []
            return
        }
        let providers = EngineProviderChoice.providers(for: input, suggestionsEnabled: suggestionsEnabled())
        lastEngineProviders = providers
        startingEngine = true
        engine.start(AutocompleteInput(text: input.text, preventsInlineCompletion: input.preventsInlineCompletion, providers: providers))
        startingEngine = false
        engineMatches = mapped(engine.matches)
    }

    /// The engine's matches as Room's: history into the history band, suggestions (switch on only) into the search band.
    func mapped(_ matches: [AutocompleteMatch]) -> [OmniboxMatch] {
        var mapped = EngineHistoryProvider.matches(from: matches, input: input, in: context)
        if suggestionsEnabled() { mapped += EngineSuggestProvider.matches(from: matches, input: input, engine: context.searchEngine) }
        return mapped
    }

    public func autocompleteControllerDidUpdate(_ controller: any AutocompleteController) {
        // The synchronous pass is read right after `start`.
        guard !startingEngine, isOpen, controller === activeAutocomplete else { return }
        engineMatches = mapped(controller.matches)
        rankKeepingHighlight()
        onEngineUpdate?(controller.isDone)
    }

    func stopEngine() {
        activeAutocomplete?.stop()
        engineMatches = []
        engineRecent = []
        engineRecentRequested = false
    }

    /// The switch went off: the engine's suggestions go at once and nothing it started keeps running.
    func engineSuggestionsOff() {
        guard activeAutocomplete != nil else { return }
        activeAutocomplete?.stop()
        let before = engineMatches.count
        engineMatches.removeAll { $0.provider == .suggest }
        if isOpen, engineMatches.count != before { rankKeepingHighlight() }
    }

    /// ⌘Y: the engine's most recent pages, asked once per open. Not its
    /// most visited: Chromium's `QueryMostVisitedURLs` counts navigation
    /// segments, which imported visits do not have, so the Chapter 2 history
    /// would be missing from it.
    func requestRecentHistory(_ history: any ProfileHistory) {
        guard !engineRecentRequested else { return }
        engineRecentRequested = true
        Task { [weak self] in
            let entries = await history.entries(from: nil, to: nil, limit: OmniboxResult.limit)
            guard let self, self.isOpen, self.engineRecentRequested else { return }
            self.engineRecent = EngineHistoryProvider.recentMatches(from: entries)
            if self.typedText.isEmpty { self.query(preventingInline: true) }
        }
    }

    /// ⇧Delete on a history row from the engine: Chrome's provider drops the
    /// match from its index at once (`DeleteMatch`); an inline host row
    /// removes the host's history (2.4b's rule).
    func deleteEngineHistory(_ match: OmniboxMatch, in history: any ProfileHistory) {
        let url = match.action.url
        if let host = EngineHistoryProvider.deletedHost(for: match) {
            Task { await history.delete(host: host) }
        }
        if let controller = activeAutocomplete, let url,
           let index = controller.matches.firstIndex(where: { $0.destinationURL?.absoluteString == url && $0.isDeletable }) {
            controller.deleteMatch(at: index)
        } else if let url = url.flatMap(URL.init(string:)) {
            history.delete(url: url)
        }
        engineRecent.removeAll { $0.id == match.id }
    }
}
