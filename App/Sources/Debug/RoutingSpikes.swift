#if DEBUG
import AppKit
import Chrome
import Engine
import Model
import Store
import UIKitCore

/// Phase 4.2 spike `routing` (`-RoomSidebarFixture routing`, 2.7's site on
/// :8770; `scripts/routing-check.sh`, the tour step `routing` in group
/// `appintegration`). External links are handed to Room through
/// `AppDelegate.application(_:open:)`, the delegate method AppKit calls for
/// `open -a`, AppleScript's `open location` and another app's link (the same
/// path into `URLInbox` 2.8b's runs measured), called directly with the URL.
/// 1. the rules as the store holds them; an invalid regex refused (the model);
/// 2. an external link matching the `contains` rule lands in Work as its
///    selection, the shown space unchanged, with "Opened in Work · Switch";
///    the `equals` rule (host) sends one to Play;
/// 3. one no enabled rule matches (the disabled rule would) lands in the most
///    recent space, selected in the card, without the toast;
/// 4. the toast's Switch shows Work with the routed tab in the card; the next
///    unmatched link goes to Work, now the most recent space; a chosen default
///    space (Settings ▸ Links) takes the next one;
/// 5. a link from a page (`target=_blank`, then ⌘-click) with "Route links
///    between spaces" off stays under its opener; on, it goes to Work with the toast;
/// 6. the routing sheet: Add Route for Domain's prefill, Try a URL, the
///    inline refusal of an invalid regex, a capture;
/// 7. the rules in the database after a flush; the settings back to their defaults.
extension SpikeRunner.Context {
    private var routingApp: AppDelegate? { AppDelegate.current }

    func routingChecks() async {
        guard let app = routingApp, let store = app.store, let sidebar = app.sidebar, let router = app.spaceRouter else {
            return SpikeRunner.record("error", "routing: no store, sidebar or router")
        }
        let model = store.sidebar
        func space(_ name: String) -> Space? { model.spaces.first { $0.name == name } }
        guard let home = space("Space"), let work = space("Work"), let play = space("Play") else {
            return SpikeRunner.record("error", "routing: the fixture has no spaces Space, Work and Play")
        }
        func name(_ id: UUID?) -> String { id.flatMap { model.space($0)?.name } ?? "none" }
        func settle(_ milliseconds: Int = 400) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
        func toast() -> String {
            guard let toast = app.debugToastCenter?.currentToast, toast.id == "routed" else { return "none" }
            return "\"\(toast.message)\" button=\(toast.action?.title ?? "none")"
        }
        func dismissToast() { app.debugToastCenter?.dismiss(id: "routed") }
        let site = "http://127.0.0.1:8770/"

        // 1. The rules; an invalid regex is refused and nothing is saved.
        SpikeRunner.record("rules", model.routingRules.map { "\($0.position + 1). \($0.match.rawValue) \($0.pattern) → \(name($0.targetSpaceID))"
            + ($0.enabled ? "" : " (disabled)") }.joined(separator: " | "))
        let count = model.routingRules.count
        do {
            try model.addRoutingRule(.regex, pattern: "([a-z", target: work.id)
            SpikeRunner.record("invalid_regex", "refused=false")
        } catch {
            let message = if case .routingPattern(let problem) = error { problem.message } else { "\(error)" }
            SpikeRunner.record("invalid_regex", "refused=true rules \(count) → \(model.routingRules.count) message=\(message)")
        }

        /// Hands Room `url` as another app would, then waits for its entry.
        func external(_ url: String) async -> Entry? {
            dismissToast()
            app.application(NSApp, open: [URL(string: url)!])
            _ = await waitUntil(5) { model.entries.values.contains { $0.liveURL == url } }
            guard let entry = model.entries.values.first(where: { $0.liveURL == url }) else { return nil }
            if let page = app.tabs?.contents(for: entry.id) { await waitLoaded(page, timeout: 10) }
            await settle(300)
            return model.entry(entry.id)
        }
        func describe(_ entry: Entry?) -> String {
            guard let entry else { return "no tab" }
            let selectedThere = store.windows.selectedEntry(space: entry.spaceID ?? home.id, window: sidebar.windowID) == entry.id
            let loaded = app.tabs?.contents(for: entry.id)?.url?.absoluteString ?? "not loaded"
            return "space=\(name(entry.spaceID)) selected in its space=\(selectedThere) shown space=\(name(sidebar.activeSpaceID)) "
                + "in the card=\(app.tabs?.currentEntryID == entry.id) page=\(loaded) toast=\(toast())"
        }

        // 2. Rules.
        let contains = await external(site + "other.html?route=work")
        SpikeRunner.record("external_rule_contains", describe(contains))
        let equals = await external("http://localhost:8770/other.html?n=1")
        SpikeRunner.record("external_rule_equals", describe(equals))

        // 3. No enabled rule: the most recent space (the shown one).
        let plain = await external(site + "site.html?plain")
        SpikeRunner.record("external_no_rule", describe(plain))

        // 4. Switch from the toast, then the most recent space and the chosen default.
        let again = await external(site + "other.html?route=work&n=2")
        let switchAction = app.debugToastCenter?.currentToast?.action
        SpikeRunner.record("toast_before_switch", toast())
        switchAction?.handler()
        _ = await waitUntil(3) { sidebar.activeSpaceID == work.id }
        if let id = again?.id, let page = app.tabs?.contents(for: id) { await waitLoaded(page, timeout: 10) }
        await settle(600)
        SpikeRunner.record("toast_switch", "shown space=\(name(sidebar.activeSpaceID)) card=\(app.tabs?.currentEntryID == again?.id ? "the routed tab" : "other") "
            + "page=\(app.tabs?.current?.url?.absoluteString ?? "nil")")
        let recent = await external(site + "other.html?recent")
        SpikeRunner.record("external_most_recent", describe(recent))
        store.settings.update { $0.externalLinksSpaceID = play.id }
        let chosen = await external(site + "other.html?chosen")
        SpikeRunner.record("external_chosen_default", describe(chosen))
        store.settings.update { $0.externalLinksSpaceID = nil }

        // 5. Links from a page in Space: off, then on.
        sidebar.showSpace(home.id, animated: false)
        await settle(600)
        guard let homeTab = model.today(space: home.id).first(where: { $0.liveURL == site + "site.html" }),
              let page = app.tabs?.contents(for: homeTab.id) ?? {
                  sidebar.select(homeTab.id)
                  return app.tabs?.contents(for: homeTab.id)
              }() else {
            return SpikeRunner.record("error", "routing: no home page")
        }
        if sidebar.selectedEntryID != homeTab.id { sidebar.select(homeTab.id) }
        await waitLoaded(page)
        await settle(400)
        func addLink(_ id: String, _ href: String, blank: Bool) async {
            _ = await js(page, """
                (() => { const a = document.createElement('a'); a.id = '\(id)'; a.href = '\(href)'; \(blank ? "a.target = '_blank';" : "")
                a.textContent = '\(id)'; a.style.cssText = 'display:block;font-size:24px;padding:8px'; document.body.prepend(a); return 0 })()
                """)
        }
        func pageLink(_ id: String, _ href: String, blank: Bool, command: Bool = false) async -> String {
            dismissToast()
            await addLink(id, href, blank: blank)
            await settle(200)
            await click(page, "#\(id)", modifiers: command ? .command : [])
            _ = await waitUntil(5) { model.entries.values.contains { $0.liveURL == href } }
            await settle(500)
            guard let entry = model.entries.values.first(where: { $0.liveURL == href }) else { return "no tab" }
            let today = model.today(space: home.id).map(\.id)
            let under = today.firstIndex(of: entry.id).map { $0 == (today.firstIndex(of: homeTab.id) ?? -2) + 1 } ?? false
            return "\(describe(entry)) under its opener=\(under)"
        }
        SpikeRunner.record("cross_space_off_blank", await pageLink("r1", site + "other.html?route=work&from=page1", blank: true))
        sidebar.select(homeTab.id)
        await settle(400)
        store.settings.update { $0.routeLinksBetweenSpaces = true }
        SpikeRunner.record("cross_space_on_blank", await pageLink("r2", site + "other.html?route=work&from=page2", blank: true))
        sidebar.select(homeTab.id)
        await settle(400)
        SpikeRunner.record("cross_space_on_command_click", await pageLink("r3", site + "other.html?route=work&from=page3", blank: false, command: true))
        SpikeRunner.record("cross_space_on_no_rule", await pageLink("r4", site + "other.html?from=page4", blank: true))
        store.settings.update { $0.routeLinksBetweenSpaces = false }

        // 6. The sheet: "Add Route for Domain…" prefilled, Try a URL, an invalid regex inline.
        app.showRoutingRules(newRule: ("127.0.0.1", home.id))
        await settle(800)
        if let sheet = app.routingSheet, let editor = app.routingModel {
            SpikeRunner.record("sheet", "shown=\(sheet.isVisible && window.attachedSheet === sheet) editing=\(editor.editing == .new) "
                + "match=\(editor.match.rawValue) pattern=\(editor.pattern) target=\(name(editor.target)) rules listed=\(model.routingRules.count)")
            editor.tryText = "localhost:8770/anything"
            let tryRule = editor.tryResult
            editor.tryText = "example.com"
            let tryDefault = editor.tryResult
            await settle(300)
            SpikeRunner.record("sheet_try_url", "localhost:8770/anything → \(tryRule); example.com → \(tryDefault)")
            if let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") {
                let url = URL(fileURLWithPath: directory).appending(path: "phase-4.2-routing-sheet.png")
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                sheet.displayIfNeeded()
                SpikeRunner.record("capture_sheet", (try? WindowSnapshot.writePNG(sheet, to: url)) != nil ? url.lastPathComponent : "failed")
            }
            editor.match = .regex
            editor.pattern = "([a-z"
            await settle(200)
            let refused = !editor.canSave && !editor.save()
            SpikeRunner.record("sheet_invalid_regex", "inline=\(editor.patternError ?? "none") save refused=\(refused) rules=\(model.routingRules.count)")
            editor.match = .contains
            editor.pattern = "127.0.0.1:8770/sheet"
            let saved = editor.save()
            let rule = model.routingRules.last
            SpikeRunner.record("sheet_save", "saved=\(saved) rules=\(model.routingRules.count) last=\(rule.map { "\($0.match.rawValue) \($0.pattern) → \(name($0.targetSpaceID))" } ?? "none")")
            if let rule { editor.remove(rule.id) }
            app.closeRoutingRules()
            await settle(400)
            SpikeRunner.record("sheet_closed", app.routingSheet == nil && window.attachedSheet == nil)
        } else {
            SpikeRunner.record("sheet", "shown=false")
        }

        // 7. Written with the state.
        store.flush()
        let persisted = (try? store.persistence.writer.database.loadState().state.routingRules.count) ?? -1
        SpikeRunner.record("rules_in_database", "\(persisted) of \(model.routingRules.count)")
        #if DEBUG
        SpikeRunner.record("decisions", router.debugLog.map { item -> String in
            let origin: String = if case .page(let source) = item.origin { "page@\(name(source))" } else { "external" }
            let reason: String = switch item.decision?.reason {
            case .rule(let id)?: "rule \((model.routingRules.firstIndex { $0.id == id } ?? -1) + 1)"
            case .chosenDefault?: "chosen default"
            case .mostRecentSpace?: "most recent"
            case .sourceSpace?: "source space"
            case nil: "none"
            }
            return "\(item.url.replacingOccurrences(of: site, with: "/")) \(origin) → \(name(item.decision?.space)) (\(reason))"
        }.joined(separator: " | "))
        #endif
    }
}
#endif
