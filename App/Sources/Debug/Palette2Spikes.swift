#if DEBUG
import AppKit
import Design
import Engine
import Model
import Omnibox
import Palette
import Store
#if canImport(EngineCEF)
import EngineCEF
#endif

/// Phase 2.4b spikes on the live engine (`Room -RoomSpike <name>`):
/// - `palette2` (with `-RoomSidebarFixture demo`, optionally
///   `-RoomSpikeCaptureDirectory <dir>`): history recording through
///   `didCommitNavigation` on CEF (a typed URL, a script navigation, a
///   same-document `pushState`, a reload, an error page, a search), then
///   captures of the palette with history rows and inline completion, in
///   commands mode and in site-search mode, light and dark.
/// - `suggestcheck` (optionally `-RoomSuggestionsOff YES`, `-RoomSuggestProxy
///   host:port`): types three queries at about 16 keys a second with a pause
///   after each, and reports the suggestion rows seen; the no-network check
///   runs it through a logging proxy.
extension SpikeRunner.Context {
    // MARK: History recording on CEF

    func palette2Checks() async {
        restorePaletteHooks()
        guard let palette else { return SpikeRunner.record("error", "no palette") }
        let history = tabs.store.history
        func settle(_ milliseconds: Int = 600) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
        func loaded() async {
            await settle(300)
            if let page = tabs.current { await waitLoaded(page, timeout: 30) }
            await settle()
        }

        press("⌘T")
        type("example.com")
        press("↩")
        await loaded()
        let typedURL = tabs.current?.url?.absoluteString ?? "nil"
        if let page = tabs.current {
            // A navigation the page starts (renderer-initiated: a link transition).
            _ = await js(page, "location.href = 'https://example.org/'; 1")
            await loaded()
            // Same-document: no new load, only a new address.
            _ = await js(page, "history.pushState({}, '', '/pushed'); 1")
            await settle()
            page.reload()
            await loaded()
        }
        press("⌘L")
        type("https://nonexistent.invalid/")
        press("↩")
        await loaded()
        press("⌘T")
        type("room browser palette")
        press("↩")
        await loaded()
        await settle(800)
        for url in [typedURL, "https://example.org/", "https://example.org/pushed", "https://nonexistent.invalid/"] {
            let visits = (try? history.visits(url: url, profile: historyProfile)) ?? []
            let title = (try? history.row(url: url, profile: historyProfile))?.title ?? "nil"
            SpikeRunner.record("history \(url)", "visits=\(visits.map(\.1.rawValue)) title=\(title)")
        }
        let search = (try? history.search("room browser palette", profile: historyProfile, limit: 3)) ?? []
        SpikeRunner.record("history search page", search.map { "\($0.url) visits=\($0.visitCount)" }.joined(separator: ", "))
        SpikeRunner.record("history rows total", (try? history.count(profile: historyProfile)) ?? -1)

        // The palette finds what was visited, and inline-completes the typed host.
        press("⌘T")
        type("exa")
        SpikeRunner.record("palette exa", "inline=\(palette.result.inlineCompletion ?? "nil") rows=\(palette.result.matches.map { "\($0.provider.rawValue):\($0.title)" })")
        press("⎋")
        await palette2Captures()
    }

    // MARK: Captures

    private func seedCaptureHistory(_ history: History) {
        let now = Date()
        let visits: [(String, String, HistoryTransition, Int)] = [
            ("https://github.com/", "GitHub", .typed, 6),
            ("https://github.com/apple/swift", "apple/swift: The Swift Programming Language", .link, 4),
            ("https://github.com/swiftlang/swift-evolution", "swiftlang/swift-evolution: Proposals for Swift", .link, 2),
            ("https://github.com/groue/GRDB.swift", "groue/GRDB.swift: A toolkit for SQLite databases", .link, 3),
            ("https://gist.github.com/", "Discover gists · GitHub", .link, 1),
            ("https://www.youtube.com/watch?v=jfKfPfyJRdk", "lofi hip hop radio 📚 beats to relax/study to", .link, 3),
            ("https://www.youtube.com/watch?v=rUxyKA_-grg", "lofi beats for coding", .link, 1),
            ("https://news.ycombinator.com/", "Hacker News", .typed, 5),
        ]
        for (url, title, transition, count) in visits {
            for index in 0..<count {
                try? history.recordVisitNow(url: url, title: title, transition: index == 0 ? transition : .link, profile: historyProfile,
                                            at: now.addingTimeInterval(Double(-index) * 3_600))
            }
        }
    }

    private func palette2Captures() async {
        guard let palette, let directoryPath = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        seedCaptureHistory(tabs.store.history)
        // Captures without live suggestions: deterministic, and no third-party text in the repository.
        // The setting comes back as it was: later runs on the same state (the grand tour) read it.
        let suggestionsWere = tabs.store.settings.settings.searchSuggestions
        defer { tabs.store.settings.update { $0.searchSuggestions = suggestionsWere } }
        tabs.store.settings.update { $0.searchSuggestions = false }
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        if let id = store.today(space: sidebar.activeSpaceID).first(where: { $0.currentURL?.contains("wikipedia") == true })?.id {
            sidebar.select(id)
        }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let suffix = dark ? "dark" : "light"
            var pageImage: NSImage?
            if let page = tabs.current {
                await waitLoaded(page, timeout: 30)
                try? await Task.sleep(for: .seconds(2))
                pageImage = await PageDriver.capture(page, "page capture")
            }
            let states: [(String, () async -> Void)] = [
                ("history-inline", { self.press("⌘T"); self.type("gi") }),
                ("commands", { self.press("⌘T"); self.press("⇥") }),
                ("commands-filtered", { self.press("⌘T"); self.type(">re") }),
                ("site-search", {
                    self.press("⌘T")
                    self.type("yt")
                    self.press("⇥")
                    self.type("lofi")
                }),
            ]
            for (name, show) in states {
                await show()
                try? await Task.sleep(for: .milliseconds(500))
                palette.debugPanel?.displayIfNeeded()
                SpikeRunner.record("state_\(name)_\(suffix)", "field=\(palette.typedText) chip=\(palette.siteSearch?.name ?? "-") "
                    + "inline=\(palette.result.inlineCompletion ?? "-") rows=\(palette.result.matches.map(\.title))")
                SpikeRunner.record("capture_\(name)_\(suffix)", writeComposite(page: pageImage, pageView: tabs.current?.nativeView,
                                                                              overlay: palette.debugPanel,
                                                                              to: directory.appending(path: "\(UserDefaults.standard.string(forKey: "RoomCapturePrefix") ?? "phase-2.4b")-palette-\(name)-\(suffix).png")))
                palette.dismiss()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        NSApp.appearance = nil
    }

    // MARK: Search suggest end to end

    func suggestCheck() async {
        restorePaletteHooks()
        guard let palette else { return SpikeRunner.record("error", "no palette") }
        let settings = tabs.store.settings
        // `-RoomSuggestionsOff` holds for this run only: later runs on the same state (the grand tour) read the setting.
        let suggestionsWere = settings.settings.searchSuggestions
        defer { settings.update { $0.searchSuggestions = suggestionsWere } }
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { settings.update { $0.searchSuggestions = false } }
        SpikeRunner.record("suggestions", settings.settings.searchSuggestions ? "on" : "off")
        SpikeRunner.record("engine", settings.settings.searchEngine)
        SpikeRunner.record("proxy", UserDefaults.standard.string(forKey: "RoomSuggestProxy") ?? "none")
        // The selected page finishes loading first: the check is about what typing sends.
        if let page = tabs.current { await waitLoaded(page, timeout: 30) }
        try? await Task.sleep(for: .seconds(3))
        SpikeRunner.record("typing_start_epoch_ms", Int(Date().timeIntervalSince1970 * 1000))
        var seen: [String] = []
        for query in ["swift concurrency", "weather in vilnius", "room browser"] {
            press("⌘T")
            for character in query {
                type(String(character))
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? await Task.sleep(for: .milliseconds(1200))
            let rows = palette.result.matches.filter { $0.provider == .suggest }.map(\.title)
            seen.append("\(query): \(rows)")
            press("⎋")
            try? await Task.sleep(for: .milliseconds(200))
        }
        SpikeRunner.record("typing_end_epoch_ms", Int(Date().timeIntervalSince1970 * 1000))
        for line in seen { SpikeRunner.record("suggest_rows", line) }
    }
}

extension SpikeRunner.Context {
    /// The active space's profile: history follows it (ROADMAP 2.5).
    var historyProfile: UUID { sidebar.activeSpace?.profileID ?? History.orphanProfile }
}
#endif
