#if DEBUG
import AppKit
import Engine
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#endif
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// Phase 4.8b spike `incognito` (`Room -RoomSpike incognito`; the tour's step
/// `incognito` through `scripts/incognito-check.sh`, which serves
/// `research/spikes` on :8777 and the 2.5 cookie page on :8765).
/// Sections (`-RoomSpikeOnly` picks): `engine` the two members on RoomCore
/// directly (a page moved between two windows' Browsers keeps its history
/// and view; the off-the-record twin made, a cookie set in it absent from
/// the regular profile, the twin closed and gone, a new twin without it).
extension SpikeRunner.Context {
    static let incognitoBase = "http://127.0.0.1:8777/phase-4.8/"
    static let incognitoCookies = "http://127.0.0.1:8765/cookies.html"

    func incognitoChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        await activate()
        if runs("engine") { await incognitoEngine() }
    }

    /// The engine profile of the active window's space (waits for its delivery).
    func activeEngineProfile(_ app: AppDelegate) async -> (any Engine.Profile)? {
        guard let session = app.activeWindow, let sidebar = session.sidebar, let store = app.store,
              let profileID = store.sidebar.space(sidebar.activeSpaceID)?.profileID else { return nil }
        _ = await waitUntil(15) { session.tabs?.engineProfiles[profileID] != nil }
        return session.tabs?.engineProfiles[profileID]
    }

    /// A scratch host view for a page the spike made itself, in `window`'s content.
    @discardableResult
    func hostScratch(_ page: any WebContents, in window: NSWindow?) -> Bool {
        guard let content = window?.contentView else { return false }
        let view = page.nativeView
        view.removeFromSuperview()
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        content.addSubview(view)
        return true
    }

    // MARK: engine

    func incognitoEngine() async {
        #if ROOM_ENGINE_ROOMCORE
        guard let app = AppDelegate.current, let w1 = app.windows.all.first,
              let profile = await activeEngineProfile(app) as? RoomCoreProfile else {
            return SpikeRunner.record("error", "engine: no RoomCore profile")
        }
        app.newRoomWindow(nil)
        _ = await waitUntil(5) { app.windows.all.count == 2 }
        guard let w2 = app.windows.all.last, w2 !== w1, let window1 = w1.window, let window2 = w2.window else {
            return SpikeRunner.record("error", "engine: no second window")
        }
        // A page in window 1's Browser with two entries.
        guard let page = try? profile.makeWebContents(WebContentsConfiguration(hostWindow: window1)) else {
            return SpikeRunner.record("error", "engine: no page")
        }
        hostScratch(page, in: window1)
        page.load(URL(string: Self.incognitoBase + "a.html")!, transition: .typed, fromAddressBar: true)
        await waitLoaded(page, timeout: 15)
        page.load(URL(string: Self.incognitoBase + "next-a.html")!, transition: .link, fromAddressBar: false)
        _ = await waitUntil(15) { !page.isLoading && page.url?.lastPathComponent == "next-a.html" && page.canGoBack }
        let chromiumView = page.nativeView.subviews.first
        func browsers() -> String {
            profile.spikeBrowsers.map { browser in
                let name = browser.window === window1 ? "w1" : browser.window === window2 ? "w2" : "other"
                return "\(name):\(browser.webContents.count)"
            }.joined(separator: ",")
        }
        let before = "browsers=\(browsers()) url=\(page.url?.lastPathComponent ?? "nil") canGoBack=\(page.canGoBack) history=\(await js(page, "history.length"))"
        SpikeRunner.record("engine_before_move", before)
        let start = ContinuousClock.now
        var moveError = "none"
        do { try page.move(toHostWindow: window2) } catch { moveError = "\(error)" }
        hostScratch(page, in: window2)
        let moveMs = ms(since: start)
        await nextRunLoopTurn()
        let sameView = page.nativeView.subviews.first.map { $0 === chromiumView } ?? false
        let history = await js(page, "history.length")
        let capture = try? await page.captureViewport()
        SpikeRunner.record("engine_move", String(format: "in %.1f ms ", moveMs)
            + "error=\(moveError) browsers=\(browsers()) host_window=\(page.configuration.hostWindow === window2 ? "w2" : "?") "
            + "url=\(page.url?.lastPathComponent ?? "nil") canGoBack=\(page.canGoBack) history=\(history) "
            + "same_chromium_view=\(sameView) view_in_w2=\(page.nativeView.window === window2) "
            + "capture=\(capture.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "failed") state=\(page.state)")
        page.goBack()
        _ = await waitUntil(15) { !page.isLoading && page.url?.lastPathComponent == "a.html" }
        SpikeRunner.record("engine_move_back", "url=\(page.url?.lastPathComponent ?? "nil") canGoForward=\(page.canGoForward)")
        var refused = "none"
        page.close()
        _ = await waitUntil(5) { page.state == .closed }
        do { try page.move(toHostWindow: window1) } catch { refused = "\(error)" }
        SpikeRunner.record("engine_move_closed", "refused=\(refused)")

        // The off-the-record twin.
        let twinStart = ContinuousClock.now
        guard let twin = try? profile.makeOffTheRecord() else { return SpikeRunner.record("engine_twin", "failed") }
        let twinMs = ms(since: twinStart)
        let again = (try? profile.makeOffTheRecord()) === twin
        let nested: String
        do { _ = try twin.offTheRecord(); nested = "allowed" } catch { nested = "\(error)" }
        SpikeRunner.record("engine_twin", String(format: "made in %.1f ms ", twinMs)
            + "exists=\(profile.hasOffTheRecordProfile) same_on_second_call=\(again) twin_of_twin=\(nested) history=\(twin.history == nil ? "none" : "some")")
        guard let secret = try? twin.makeWebContents(WebContentsConfiguration(hostWindow: window2)),
              let regular = try? profile.makeWebContents(WebContentsConfiguration(hostWindow: window1)) else {
            return SpikeRunner.record("error", "engine: no twin page")
        }
        hostScratch(secret, in: window2)
        hostScratch(regular, in: window1)
        secret.load(URL(string: Self.incognitoCookies + "?set=incognito-engine")!, transition: .typed, fromAddressBar: true)
        await waitLoaded(secret, timeout: 15)
        regular.load(URL(string: Self.incognitoCookies)!, transition: .typed, fromAddressBar: true)
        await waitLoaded(regular, timeout: 15)
        SpikeRunner.record("engine_cookie", "twin=\(await js(secret, "document.cookie")) regular=\(await js(regular, "document.cookie"))")
        let rows = await profile.history?.entries(from: nil, to: nil, limit: 200) ?? []
        SpikeRunner.record("engine_history", "regular_rows=\(rows.count) incognito_rows=\(rows.filter { $0.url.absoluteString.contains("incognito-engine") }.count)")

        secret.close()
        _ = await waitUntil(5) { secret.state == .closed }
        let closeStart = ContinuousClock.now
        profile.closeOffTheRecord()
        let gone = await waitUntil(20) { !profile.hasOffTheRecordProfile }
        SpikeRunner.record("engine_twin_closed", String(format: "gone=%@ after %.0f ms", gone ? "true" : "false", ms(since: closeStart)))
        guard let next = try? profile.makeOffTheRecord(), let fresh = try? next.makeWebContents(WebContentsConfiguration(hostWindow: window2)) else {
            return SpikeRunner.record("engine_new_twin", "failed")
        }
        hostScratch(fresh, in: window2)
        fresh.load(URL(string: Self.incognitoCookies)!, transition: .typed, fromAddressBar: true)
        await waitLoaded(fresh, timeout: 15)
        SpikeRunner.record("engine_new_twin", "new_object=\(next !== twin) cookie=\(await js(fresh, "document.cookie"))")

        // "Open Link in Incognito Window" from a regular page (patches/0014's
        // hook answers the twin's Browser, B-50): didCreate with the
        // off-the-record disposition, a page of the twin, then moved.
        let probe = IncognitoProbeDelegate()
        regular.uiDelegate = probe
        regular.load(URL(string: Self.incognitoBase + "a.html")!, transition: .typed, fromAddressBar: true)
        await waitLoaded(regular, timeout: 15)
        window1.makeKeyAndOrderFront(nil)
        if let point = await PageDriver.center(of: "#next", in: regular, "incognito: the link") {
            PageDriver.click(regular, at: point, button: .rightMouseDown, "incognito: right-click the link")
        }
        _ = await waitUntil(10) { probe.created != nil }
        if let created = probe.created {
            await waitLoaded(created.page, timeout: 15)
            let inTwin = next.webContents.contains { $0 === created.page }
            let twinBrowsersBefore = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            var moved = "none"
            do { try created.page.move(toHostWindow: window2); hostScratch(created.page, in: window2) } catch { moved = "\(error)" }
            await nextRunLoopTurn()
            let twinBrowsersAfter = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            SpikeRunner.record("engine_otr_open", "menu_item=\(probe.itemTitle ?? "none") disposition=\(created.disposition) in_twin=\(inTwin) "
                + "in_regular=\(profile.webContents.contains { $0 === created.page }) url=\(created.page.url?.lastPathComponent ?? "nil") "
                + "referrer=\(await js(created.page, "document.referrer")) opener=\(await js(created.page, "String(window.opener === null)")) "
                + "twin_browsers_before=\(twinBrowsersBefore) move_error=\(moved) twin_browsers_after=\(twinBrowsersAfter)")
            created.page.close()
        } else {
            SpikeRunner.record("engine_otr_open", "failed: menu_item=\(probe.itemTitle ?? "none") items=\(probe.titles.prefix(12).joined(separator: "|"))")
        }
        // Again with no page of the twin open: the hook makes the twin a
        // Browser in the opener's window, which the move empties and closes.
        fresh.close()
        _ = await waitUntil(5) { next.webContents.isEmpty }
        await nextRunLoopTurn()
        let second = IncognitoProbeDelegate()
        regular.uiDelegate = second
        window1.makeKeyAndOrderFront(nil)
        _ = await waitUntil(3) { NSApp.keyWindow === window1 }
        if let point = await PageDriver.center(of: "#next", in: regular, "incognito: the link again") {
            PageDriver.click(regular, at: point, button: .rightMouseDown, "incognito: right-click the link again")
        }
        _ = await waitUntil(10) { second.created != nil }
        if let created = second.created {
            await waitLoaded(created.page, timeout: 15)
            let before = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            var moved = "none"
            do { try created.page.move(toHostWindow: window2); hostScratch(created.page, in: window2) } catch { moved = "\(error)" }
            _ = await waitUntil(3) { next.spikeBrowsers.allSatisfy { $0.window === window2 } }
            let after = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            SpikeRunner.record("engine_otr_open_no_twin_page", "disposition=\(created.disposition) in_twin=\(next.webContents.contains { $0 === created.page }) "
                + "url=\(created.page.url?.lastPathComponent ?? "nil") twin_browsers_before=\(before) move_error=\(moved) twin_browsers_after=\(after) "
                + "state=\(created.page.state) history=\(await js(created.page, "history.length"))")
            created.page.close()
        } else {
            SpikeRunner.record("engine_otr_open_no_twin_page", "failed: menu_item=\(second.itemTitle ?? "none") items=\(second.titles.count) twin_pages=\(next.webContents.count) key=\(NSApp.keyWindow === window1 ? "w1" : "other")")
        }
        regular.close()
        profile.closeOffTheRecord()
        let goneAgain = await waitUntil(20) { !profile.hasOffTheRecordProfile }
        SpikeRunner.record("engine_twin_closed_again", "gone=\(goneAgain)")
        #else
        SpikeRunner.record("error", "engine: RoomCore only")
        #endif
    }

    /// One turn of the main queue.
    func nextRunLoopTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
}

/// Answers the engine's context menu with "Open Link in Incognito Window" and
/// records the page it opens (the `engine` section).
@MainActor
final class IncognitoProbeDelegate: WebContentsUIDelegate {
    private(set) var created: (page: any WebContents, disposition: Disposition)?
    private(set) var itemTitle: String?
    private(set) var titles: [String] = []

    func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        titles = menu.items.map(\.title)
        if let item = menu.items.first(where: { $0.title.localizedCaseInsensitiveContains("incognito") }) {
            itemTitle = item.title
            menu.select(item.id)
        } else {
            menu.cancel()
        }
        return true
    }

    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?, disposition: Disposition) {
        created = (newContents, disposition)
    }
}
#endif
