#if DEBUG
import AppKit
import Engine
import Model
import Omnibox
import Palette
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
import RoomCore
#endif

/// Phase 3.5 checks on the engine path, run by `palette2` after its history
/// checks (`Room -RoomSpike palette2`): a visit recorded by Chromium appears
/// in `ProfileHistory` and in the palette while the store's table does not
/// grow; ⌘Y lists Chrome's history; the providers asked per keystroke;
/// `IDC_FOCUS_LOCATION` through `RoomAppController`'s command dispatch
/// reaching the host's field; the security chip's state for a secure and an
/// insecure page beside what Chrome's `LocationBarModel` reports.
extension SpikeRunner.Context {
    func engineChecks() async {
        guard let palette, let history = tabs.engineProfiles[historyProfile]?.history else {
            return SpikeRunner.record("engine_checks", "skipped: the engine keeps no history (CEF)")
        }
        func settle(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
        func loaded() async {
            await settle(300)
            if let page = tabs.current { await waitLoaded(page, timeout: 30) }
            await settle(800)
        }
        SpikeRunner.record("engine_autocomplete", palette.usesEngineAutocomplete)

        // A visit on RoomCore: Chrome records it; the store's table stays as it was.
        let storeBefore = (try? tabs.store.history.count(profile: historyProfile)) ?? -1
        let marker = "https://example.org/?room35=\(Int(Date().timeIntervalSince1970))"
        press("⌘L")
        type(marker)
        press("↩")
        await loaded()
        await settle(1_000)
        let storeAfter = (try? tabs.store.history.count(profile: historyProfile)) ?? -1
        SpikeRunner.record("store_history_rows_around_a_navigation", "before=\(storeBefore) after=\(storeAfter)")
        let found = await history.visits(for: URL(string: marker)!)
        SpikeRunner.record("engine_visit_recorded", "visits=\(found?.visits.map { HistoryTransition($0.transition).rawValue } ?? []) "
            + "title=\(found?.entry.title ?? "nil")")
        press("⌘T")
        type("room35")
        await settle(800)
        let rows = palette.result.matches.filter { $0.provider == .history }
        SpikeRunner.record("palette_room35", "found=\(rows.contains { $0.action.url == marker }) providers=\(palette.lastEngineProviders.map(Self.describe) ?? "none") "
            + "rows=\(rows.map(\.title))")
        press("⎋")
        await settle(300)

        // ⌘Y: Chrome's most visited pages.
        palette.toggleHistory()
        await settle(800)
        let recent = palette.result.matches.filter { $0.provider == .history }
        SpikeRunner.record("cmd_y", "rows=\(recent.count) first=\(recent.first?.detail ?? recent.first?.title ?? "none")")
        palette.dismiss()
        await settle(300)

        // IDC_FOCUS_LOCATION through RoomAppController's -commandDispatch: (the Chrome command path).
        let before = session.pageDelegate.focusLocationBarRequests
        let dispatched = Self.dispatchChromeCommand(39_001)
        await settle(400)
        SpikeRunner.record("idc_focus_location_dispatch", "\(dispatched) requests=\(session.pageDelegate.focusLocationBarRequests - before) "
            + "palette_open=\(palette.isOpen) mode=\(palette.mode.map { String(describing: $0) } ?? "none")")
        if palette.isOpen { palette.dismiss() }
        await settle(300)
        #if ROOM_ENGINE_ROOMCORE
        let browser = (tabs.engineProfiles[historyProfile] as? RoomCoreProfile)?.spikeBrowsers.first
        // The same command executed on the window's Browser (chrome::ExecuteCommand → SetFocusToLocationBar).
        let beforeBrowser = session.pageDelegate.focusLocationBarRequests
        let executed = browser?.perform(NSSelectorFromString("roomSpikeCommand:"), with: NSNumber(value: 39_001))?
            .takeUnretainedValue() as? NSNumber
        await settle(400)
        SpikeRunner.record("idc_focus_location_browser", "executed=\(executed?.boolValue ?? false) "
            + "requests=\(session.pageDelegate.focusLocationBarRequests - beforeBrowser) palette_open=\(palette.isOpen)")
        if palette.isOpen { palette.dismiss() }
        await settle(300)
        #endif

        // The chip: the host's security state (what the site button shows) beside Chrome's LocationBarModel.
        for (name, url) in [("chip_secure", "https://example.com/"), ("chip_insecure", "http://http.badssl.com/")] {
            press("⌘L")
            type(url)
            press("↩")
            await loaded()
            await settle(1_000)
            var chrome = "n/a"
            #if ROOM_ENGINE_ROOMCORE
            if let level = browser?.perform(NSSelectorFromString("roomSpikeAction:"), with: "location-bar-security")?
                .takeUnretainedValue() as? NSNumber {
                chrome = Self.securityLevelName(level.intValue)
            }
            #endif
            SpikeRunner.record(name, "page=\(tabs.current?.url?.absoluteString ?? "nil") host=\(tabs.current.map { String(describing: $0.securityState.level) } ?? "nil") "
                + "location_bar_model=\(chrome)")
        }
    }

    /// `+[AppController sharedController]` (patch 0013: RoomAppController) `-commandDispatch:` with a tagged item.
    static func dispatchChromeCommand(_ command: Int) -> String {
        let shared = NSSelectorFromString("sharedController")
        guard let appController: AnyObject = NSClassFromString("AppController"), appController.responds(to: shared),
              let controller = appController.perform(shared)?.takeUnretainedValue() as? NSObject else { return "dispatched=false (no AppController)" }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.tag = command
        controller.perform(NSSelectorFromString("commandDispatch:"), with: item)
        return "dispatched=true controller=\(Swift.type(of: controller))"
    }

    /// `security_state::SecurityLevel`'s names (components/security_state/core/security_state.h).
    static func securityLevelName(_ level: Int) -> String {
        switch level {
        case 0: "NONE"
        case 3: "SECURE"
        case 5: "DANGEROUS"
        case 6: "WARNING"
        default: "level \(level)"
        }
    }

    static func describe(_ providers: AutocompleteProviders) -> String {
        var names: [String] = []
        if providers.contains(.historyQuick) { names.append("historyQuick") }
        if providers.contains(.historyURL) { names.append("historyURL") }
        if providers.contains(.bookmark) { names.append("bookmark") }
        if providers.contains(.shortcuts) { names.append("shortcuts") }
        if providers.contains(.openTab) { names.append("openTab") }
        if providers.contains(.search) { names.append("search") }
        return names.joined(separator: "+")
    }
}
#endif
