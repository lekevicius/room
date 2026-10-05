#if DEBUG
import AppKit
import Chrome
import Engine
import UIKitCore

/// Phase 3.6a spikes (`Room -RoomSpike <name>`):
/// - `extensions`: the unpacked fixture (`research/spikes/phase-3.6/extension`)
///   through `ProfileExtensions`: loaded, listed with its action, badge and
///   icons; `chrome.tabs.query` from its service worker against Room's tabs;
///   disable, enable, reload, pin; `chrome://extensions` in a tab with its
///   toggle clicked; the options page as a Today tab; Settings ▸ Extensions
///   captured; uninstall asking consent (cancelled once, then accepted).
/// - `webstore`: installs from the Chrome Web Store in a Room tab
///   (`-RoomWebstoreIDs id,id,…`, default the ROADMAP's three): the store
///   page's button clicked as a user would, Room's consent sheet captured and
///   accepted, the install awaited, the effect on a page, the service
///   worker's state, then uninstall with consent (`-RoomWebstoreKeep YES`
///   keeps them: the seed state for the update checks).
/// - `extupdate`: on a state with an installed extension, the timer's next
///   fire is logged, then one `checkForUpdates` through the host's center;
///   `-RoomExtensionsIdle <s>` idles first (the net-log's idle window).
extension SpikeRunner.Context {
    private var extApp: AppDelegate? { AppDelegate.current }

    /// research/screenshots/phase-3.6a (or the tour's capture directory).
    private var extShots: URL {
        let url = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? SpikeRunner.pagesDirectory.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "screenshots/phase-3.6a")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func extCapture(_ window: NSWindow, _ name: String) {
        let file = extShots.appending(path: "\(name).png")
        let written = (try? WindowSnapshot.writePNG(window, to: file)) != nil
        SpikeRunner.record("capture", written ? file.lastPathComponent : "failed: \(name)")
    }

    private func extSection() -> ExtensionsCenter.ProfileSection? {
        extApp?.extensions?.sections.first
    }

    private func describe(_ item: InstalledExtension) -> String {
        let action = item.action.map { "title=\"\($0.title)\" badge=\"\($0.badgeText)\" icon=\($0.icon.map { NSStringFromSize($0.size) } ?? "nil") popup=\($0.hasPopup)" } ?? "none"
        return "name=\"\(item.name)\" version=\(item.version) enabled=\(item.isEnabled) unpacked=\(item.isUnpacked) "
            + "store=\(item.isFromWebStore) pinned=\(item.isPinned) icon16=\(item.icon16.map { NSStringFromSize($0.size) } ?? "nil") "
            + "icon32=\(item.icon32.map { NSStringFromSize($0.size) } ?? "nil") options=\(item.optionsPageURL?.lastPathComponent ?? "nil") "
            + "action{\(action)} permissions=\(item.permissionMessages) hosts=\(item.hostPermissions)"
    }

    /// A script that returns `JSON.stringify(object)`: the object (the engine
    /// hands back the JSON of the returned string) and the plain text.
    private func jsObject(_ page: any WebContents, _ script: String) async -> (text: String, object: [String: Any]?) {
        let raw = await js(page, script)
        var value = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed)
        if let string = value as? String {
            value = try? JSONSerialization.jsonObject(with: Data(string.utf8), options: .fragmentsAllowed)
            return (string, value as? [String: Any])
        }
        return (raw, value as? [String: Any])
    }

    /// Shows `page` in the card again (an extension may have opened a tab over it).
    private func reselect(_ page: any WebContents) {
        if let entry = session.store.today(space: session.sidebar.activeSpaceID).first(where: { tabs.contents(for: $0.id) === page }) {
            session.sidebar.select(entry.id)
        }
    }

    /// The page's viewport into research/screenshots/phase-3.6a, given up after `seconds`
    /// (a capture of a page that is not on screen never answers).
    private func capturePage(_ page: any WebContents, _ name: String, seconds: Double = 8) async {
        reselect(page)
        try? await Task.sleep(for: .milliseconds(500))
        final class Once { var answered = false }
        let once = Once()
        let image: NSImage? = await withCheckedContinuation { continuation in
            Task { @MainActor in
                let image = await PageDriver.capture(page, name)
                if !once.answered { once.answered = true; continuation.resume(returning: image) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if !once.answered { once.answered = true; continuation.resume(returning: nil) }
            }
        }
        guard let image, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return SpikeRunner.record("capture", "failed: \(name) (no answer in \(Int(seconds)) s)")
        }
        try? png.write(to: extShots.appending(path: "\(name).png"))
        SpikeRunner.record("capture", "\(name).png")
    }

    private func installed(_ id: String) -> InstalledExtension? {
        extSection()?.installed.first { $0.id == id }
    }

    /// Consent sheets: captured once per kind, answered by `answers` in order (then accepted).
    private func answerConsent(_ answers: [Bool], captureAs prefix: String) {
        var queue = answers
        var captured: Set<String> = []
        ExtensionConsentSheets.debugOnShow = { [weak self] alert, window, kind in
            alert.window.displayIfNeeded()
            if captured.insert(kind).inserted, let self {
                self.extCapture(alert.window, "\(prefix)-\(kind)-sheet")
                self.extCapture(window, "\(prefix)-\(kind)-window")
            }
            let answer = queue.isEmpty ? true : queue.removeFirst()
            SpikeRunner.record("consent_\(kind)", "\"\(alert.messageText)\" answer=\(answer ? "accept" : "cancel") "
                + "text=\(alert.informativeText.replacingOccurrences(of: "\n", with: " | "))")
            return answer
        }
    }

    // MARK: extensions (task 1)

    func extensionsChecks() async {
        guard let app = extApp, let center = app.extensions, let section = extSection() else {
            return SpikeRunner.record("extensions", "skipped: the engine has no extensions")
        }
        SpikeRunner.record("extensions_ready", "\(section.extensions.isReady) installed=\(section.installed.count)")
        _ = await waitUntil(10) { section.extensions.isReady }
        let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
        let id: String
        do {
            let start = ContinuousClock.now
            id = try await section.extensions.loadUnpacked(at: fixture)
            SpikeRunner.record("load_unpacked", "id=\(id) in \(String(format: "%.0f", ms(since: start))) ms")
        } catch {
            return SpikeRunner.record("error", "load unpacked: \(error)")
        }
        _ = await waitUntil(5) { installed(id)?.icon16 != nil && installed(id)?.action?.icon != nil }
        guard let item = installed(id) else { return SpikeRunner.record("error", "the fixture is not in `installed`") }
        SpikeRunner.record("installed_entry", describe(item))

        // Two pages: the content script runs, asks the worker what chrome.tabs sees.
        let revisionBefore = center.actionRevision
        _ = await open(URL(string: "https://example.com/")!)
        guard let page = await open(URL(string: "https://example.org/")!) else { return SpikeRunner.record("error", "no page") }
        _ = await waitUntil(10) { true }
        var answer = "null"
        for _ in 0..<50 {
            answer = await js(page, "JSON.stringify(Object.assign({}, document.documentElement.dataset))")
            if answer.contains("roomFixtureTabs") { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let hostPages = session.pages.count
        SpikeRunner.record("content_script_and_tabs_query", "\(answer) host_today_pages=\(hostPages)")
        _ = await waitUntil(3) { center.actionRevision > revisionBefore }
        let pageAction = section.extensions.action(for: id, in: page)
        let defaults = section.extensions.action(for: id, in: nil)
        SpikeRunner.record("badge", "page=\"\(pageAction?.badgeText ?? "nil")\" default=\"\(defaults?.badgeText ?? "nil")\" "
            + "color=\(defaults?.badgeBackgroundColor.map { "\($0)" } ?? "nil") action_updates=\(center.actionRevision - revisionBefore) "
            + "last=\(center.lastActionUpdate.map { "\($0.id) perPage=\($0.perPage)" } ?? "none")")

        // Disable, enable, reload, pin.
        section.extensions.setEnabled(false, extension: id)
        let disabled = await waitUntil(5) { installed(id)?.isEnabled == false }
        section.extensions.setEnabled(true, extension: id)
        let enabled = await waitUntil(5) { installed(id)?.isEnabled == true }
        section.extensions.reload(id)
        try? await Task.sleep(for: .seconds(1))
        let reloaded = await waitUntil(5) { installed(id)?.isEnabled == true }
        let pinnedAtInstall = installed(id)?.isPinned ?? false
        section.extensions.setPinned(!pinnedAtInstall, extension: id)
        let toggledPin = await waitUntil(5) { installed(id)?.isPinned == !pinnedAtInstall }
        section.extensions.setPinned(pinnedAtInstall, extension: id)
        let pinned = await waitUntil(5) { installed(id)?.isPinned == pinnedAtInstall }
            && toggledPin
        SpikeRunner.record("manage", "disabled=\(disabled) enabled=\(enabled) reloaded_and_enabled=\(reloaded) pin_toggled_and_back=\(pinned) pinned_at_install=\(pinnedAtInstall) "
            + "list=\(extSection()?.installed.map(\.name) ?? [])")

        // chrome://extensions in a tab; its toggle through Chrome's own UI.
        center.openManagementPage(in: section)
        try? await Task.sleep(for: .seconds(1))
        if let management = tabs.current {
            await waitLoaded(management)
            try? await Task.sleep(for: .seconds(1.5))
            let toggle = "(() => { const m = document.querySelector('extensions-manager'); const list = m && m.shadowRoot.querySelector('extensions-item-list');"
                + " const item = list && list.shadowRoot.querySelector('extensions-item#\(id)'); const t = item && item.shadowRoot.querySelector('#enableToggle');"
                + " if (!t) return JSON.stringify({found: false, items: list ? list.shadowRoot.querySelectorAll('extensions-item').length : -1});"
                + " const r = t.getBoundingClientRect(); return JSON.stringify({found: true, checked: t.checked, x: r.x + r.width / 2, y: r.y + r.height / 2}) })()"
            let (state, parsed) = await jsObject(management, toggle)
            SpikeRunner.record("chrome_extensions_page", "url=\(management.url?.absoluteString ?? "nil") title=\(management.title ?? "nil") toggle=\(state)")
            if let object = parsed, object["found"] as? Bool == true, let x = object["x"] as? Double, let y = object["y"] as? Double {
                PageDriver.click(management, at: CGPoint(x: x, y: y), "chrome://extensions toggle")
                let off = await waitUntil(5) { installed(id)?.isEnabled == false }
                SpikeRunner.record("chrome_extensions_toggle", "registrar disabled=\(off) after=\(await jsObject(management, toggle).text)")
                await capturePage(management, "chrome-extensions")
                PageDriver.click(management, at: CGPoint(x: x, y: y), "chrome://extensions toggle back")
                let on = await waitUntil(5) { installed(id)?.isEnabled == true }
                SpikeRunner.record("chrome_extensions_toggle_back", "registrar enabled=\(on)")
            }
        }

        // The options page as a Today tab.
        if let fresh = installed(id) {
            center.openOptions(fresh, in: section)
            try? await Task.sleep(for: .seconds(1))
            if let options = tabs.current {
                await waitLoaded(options)
                try? await Task.sleep(for: .seconds(1))
                SpikeRunner.record("options_page", "url=\(options.url?.absoluteString ?? "nil") title=\(options.title ?? "nil") "
                    + "state=\(await js(options, "document.getElementById('state') ? document.getElementById('state').textContent : null")) "
                    + "today_tab=\(tabs.currentEntryID.flatMap { session.store.entry($0) }.map { "\($0.kind)" } ?? "none")")
            }
        }

        // Settings ▸ Extensions.
        app.showSettings(nil)
        try? await Task.sleep(for: .milliseconds(600))
        if let settings = app.debugSettingsWindow, let settingsWindow = settings.window {
            settings.select(.extensions)
            try? await Task.sleep(for: .milliseconds(800))
            SpikeRunner.record("settings_extensions", "title=\(settingsWindow.title) size=\(NSStringFromSize(settingsWindow.frame.size))")
            extCapture(settingsWindow, "settings-extensions")
            settingsWindow.close()
        }
        await activate()

        // Uninstall asks first: cancelled once, then accepted.
        answerConsent([false, true], captureAs: "fixture")
        guard let target = installed(id) else { return }
        let kept = await center.uninstall(target, in: section)
        SpikeRunner.record("uninstall_cancelled", "removed=\(kept) still_installed=\(installed(id) != nil)")
        let removed = await center.uninstall(target, in: section)
        _ = await waitUntil(5) { installed(id) == nil }
        SpikeRunner.record("uninstall_accepted", "removed=\(removed) still_installed=\(installed(id) != nil) "
            + "asked=\(ExtensionConsentSheets.debugAsked.map { "\($0.kind):\($0.name)" })")
        ExtensionConsentSheets.debugOnShow = nil
    }

    // MARK: webstore (task 2)

    private static let webstoreDefaults = [
        "ddkjiahejlhfcafbddmgiahcphecmpfh",  // uBlock Origin Lite
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa",  // 1Password
        "eimadpbcbfnmbkopoojfekhnkhdbieeh",  // Dark Reader
    ]

    func webstoreChecks() async {
        guard let center = extApp?.extensions, let section = extSection() else {
            return SpikeRunner.record("webstore", "skipped: the engine has no extensions")
        }
        _ = await waitUntil(10) { section.extensions.isReady }
        let ids = UserDefaults.standard.string(forKey: "RoomWebstoreIDs")?.split(separator: ",").map(String.init) ?? Self.webstoreDefaults
        let keep = UserDefaults.standard.bool(forKey: "RoomWebstoreKeep")
        answerConsent([], captureAs: "webstore")
        var userAgentLogged = false
        for id in ids {
            SpikeRunner.record("phase", String(format: "install_%@ %.3f", id, Date().timeIntervalSince1970))
            guard let store = await open(URL(string: "https://chromewebstore.google.com/detail/\(id)")!, timeout: 45) else {
                SpikeRunner.record("error", "\(id): no store page"); continue
            }
            if !userAgentLogged {
                userAgentLogged = true
                SpikeRunner.record("user_agent", await js(store, "navigator.userAgent"))
                SpikeRunner.record("user_agent_brands", await js(store,
                    "navigator.userAgentData ? JSON.stringify(navigator.userAgentData.brands) : null"))
                SpikeRunner.record("webstore_private_api", await js(store, "typeof chrome !== 'undefined' && chrome.webstorePrivate ? Object.keys(chrome.webstorePrivate).length : 'absent (isolated world)'"))
            }
            // Google's cookie consent page (consent.google.com, shown from an EU address on a
            // fresh profile) first: the privacy-preserving answer, Reject all, as a user would click it.
            if store.url?.host()?.hasPrefix("consent.") == true || store.title == "Before you continue" {
                let reject = "(() => { const b = [...document.querySelectorAll('button, input[type=submit]')].find(b => /reject all/i.test(b.textContent || b.value)); "
                    + "if (!b) return JSON.stringify({found: false, buttons: [...document.querySelectorAll('button')].map(b => b.textContent.trim()).slice(0, 6)}); "
                    + "b.scrollIntoView({block: 'center'}); const r = b.getBoundingClientRect(); return JSON.stringify({found: true, x: r.x + r.width / 2, y: r.y + r.height / 2}) })()"
                let (text, button) = await jsObject(store, reject)
                SpikeRunner.record("consent_page_\(id)", "url=\(store.url?.host() ?? "nil") reject=\(text)")
                if let button, button["found"] as? Bool == true, let x = button["x"] as? Double, let y = button["y"] as? Double {
                    PageDriver.click(store, at: CGPoint(x: x, y: y), "consent: Reject all")
                    _ = await waitUntil(20) { store.url?.host() == "chromewebstore.google.com" && !store.isLoading }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            // The store renders its button after its scripts run.
            let finder = "(() => { const b = [...document.querySelectorAll('button')].find(b => /^\\s*(Add to|Remove from)/i.test(b.textContent)); "
                + "if (!b) return JSON.stringify({found: false, notes: [...document.querySelectorAll('div,span')].map(e => e.textContent).filter(t => /not (supported|compatible)|switch to chrome|available on chrome/i.test(t)).slice(0, 3)}); "
                + "b.scrollIntoView({block: 'center'}); const r = b.getBoundingClientRect(); return JSON.stringify({found: true, text: b.textContent.trim(), disabled: b.disabled, x: r.x + r.width / 2, y: r.y + r.height / 2}) })()"
            var state = "{}"
            var parsed: [String: Any]?
            for _ in 0..<60 {
                (state, parsed) = await jsObject(store, finder)
                if parsed?["found"] as? Bool == true { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            SpikeRunner.record("store_page_\(id)", "title=\(store.title ?? "nil") button=\(state)")
            guard let object = parsed, object["found"] as? Bool == true, let x = object["x"] as? Double, let y = object["y"] as? Double else {
                await capturePage(store, "store-\(id)")
                continue
            }
            if installed(id) == nil, (object["text"] as? String)?.hasPrefix("Add") == true {
                let start = ContinuousClock.now
                PageDriver.click(store, at: CGPoint(x: x, y: y), "Add to Chrome")
                let done = await waitUntil(90) { installed(id) != nil }
                SpikeRunner.record("install_\(id)", "installed=\(done) in \(String(format: "%.1f", ms(since: start) / 1000)) s "
                    + "store_button_after=\(await jsObject(store, finder).text)")
                if !done {
                    let text = await js(store, "document.body.innerText.slice(0, 600)")
                    SpikeRunner.record("store_text_\(id)", text)
                    continue
                }
            }
            _ = await waitUntil(5) { installed(id)?.icon16 != nil }
            if let item = installed(id) { SpikeRunner.record("installed_\(id)", describe(item)) }
            await effects(of: id, section: section, center: center)
            // 3.6b's exit: the popup from the header's button (-RoomWebstorePopups YES).
            if UserDefaults.standard.bool(forKey: "RoomWebstorePopups"), let page = await open(URL(string: "https://example.com/")!) {
                try? await Task.sleep(for: .seconds(2))
                await webstorePopupChecks(id, page: page)
            }
            SpikeRunner.record("phase", String(format: "installed_%@ %.3f", id, Date().timeIntervalSince1970))
        }
        // Settings ▸ Extensions with the installs.
        if let app = extApp {
            app.showSettings(nil)
            try? await Task.sleep(for: .milliseconds(600))
            if let settings = app.debugSettingsWindow, let settingsWindow = settings.window {
                settings.select(.extensions)
                try? await Task.sleep(for: .milliseconds(1_000))
                extCapture(settingsWindow, "settings-extensions-webstore")
                settingsWindow.close()
            }
            await activate()
        }
        SpikeRunner.record("settings_list", "\(extSection()?.installed.map { "\($0.name) \($0.version) enabled=\($0.isEnabled)" } ?? [])")
        guard !keep else {
            // The seed state for the update-check runs: the extensions stay, the pages go (a
            // restored page would make its own requests in the idle window).
            for entry in session.store.today(space: session.sidebar.activeSpaceID) { _ = try? session.store.remove(entry.id) }
            try? await Task.sleep(for: .seconds(2))
            return SpikeRunner.record("webstore_kept", "\(ids.filter { installed($0) != nil }) today_left=\(session.store.today(space: session.sidebar.activeSpaceID).count)")
        }
        for id in ids {
            guard let item = installed(id) else { continue }
            let removed = await center.uninstall(item, in: section)
            _ = await waitUntil(5) { installed(id) == nil }
            SpikeRunner.record("uninstall_\(id)", "removed=\(removed) gone=\(installed(id) == nil)")
        }
        ExtensionConsentSheets.debugOnShow = nil
    }

    /// What each of the three does on a page, and its service worker.
    private func effects(of id: String, section: ExtensionsCenter.ProfileSection, center: ExtensionsCenter) async {
        let revision = center.actionRevision
        // An install may open the extension's welcome page (chrome.tabs.create → a Today tab).
        SpikeRunner.record("tabs_after_install_\(id)", "\(session.pages.compactMap { $0.url?.host() ?? $0.url?.scheme })")
        guard let page = await open(URL(string: "https://example.com/")!) else { return }
        try? await Task.sleep(for: .seconds(3))
        reselect(page)
        switch id {
        case "eimadpbcbfnmbkopoojfekhnkhdbieeh":  // Dark Reader: the page goes dark
            let probe = "JSON.stringify({styles: document.querySelectorAll('style.darkreader').length, "
                + "background: getComputedStyle(document.body).backgroundColor, html: getComputedStyle(document.documentElement).backgroundColor})"
            SpikeRunner.record("effect_\(id)", await js(page, probe))
            await capturePage(page, "dark-reader-example-com")
        case "ddkjiahejlhfcafbddmgiahcphecmpfh":  // uBO Lite: an ad script request is blocked
            let probe = "new Promise(r => { const s = document.createElement('script'); s.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js';"
                + " s.onload = () => r('loaded'); s.onerror = () => r('blocked or failed'); document.head.appendChild(s); })"
            SpikeRunner.record("effect_\(id)", await js(page, probe))
        default:  // 1Password: its content script and its action
            let probe = "JSON.stringify({elements: [...document.querySelectorAll('*')].filter(e => /1password|onepassword/i.test(e.tagName + ' ' + (e.id || ''))).map(e => e.tagName.toLowerCase()).slice(0, 5)})"
            SpikeRunner.record("effect_\(id)", await js(page, probe))
        }
        _ = await waitUntil(3) { center.actionRevision > revision }
        let action = section.extensions.action(for: id, in: page)
        SpikeRunner.record("action_\(id)", "title=\"\(action?.title ?? "nil")\" badge=\"\(action?.badgeText ?? "nil")\" enabled=\(action?.isEnabled ?? false) "
            + "popup=\(action?.hasPopup ?? false) updates=\(center.actionRevision - revision)")
        // The service worker, as Chrome's own internals page lists it.
        tabs.openNewTab(url: "chrome://serviceworker-internals/")
        if let internals = tabs.current {
            await waitLoaded(internals)
            try? await Task.sleep(for: .seconds(1.5))
            let probe = "(() => { const t = document.body.innerText; const i = t.indexOf('chrome-extension://\(id)/'); "
                + "return i < 0 ? 'not listed' : t.slice(i, i + 400).replace(/\\n+/g, ' | ') })()"
            SpikeRunner.record("service_worker_\(id)", await js(internals, probe))
        }
    }

    // MARK: extupdate (task 3)

    func extensionUpdateCheck() async {
        guard let center = extApp?.extensions, let section = extSection() else {
            return SpikeRunner.record("extupdate", "skipped: the engine has no extensions")
        }
        SpikeRunner.record("phase", String(format: "launch %.3f", Self.processStartDate().timeIntervalSince1970))
        _ = await waitUntil(10) { section.extensions.isReady }
        SpikeRunner.record("installed", "\(section.installed.map { "\($0.name) \($0.version) store=\($0.isFromWebStore)" })")
        SpikeRunner.record("timer", "last=\(extApp?.store?.settings.settings.extensionsLastUpdateCheck.map { "\($0)" } ?? "nil") "
            + "next=\(center.debugNextUpdateCheck.map { "\($0)" } ?? "nil")")
        let idle = UserDefaults.standard.double(forKey: "RoomExtensionsIdle")
        if idle > 0 {
            SpikeRunner.record("phase", String(format: "idle %.3f", Date().timeIntervalSince1970))
            try? await Task.sleep(for: .seconds(idle))
        }
        guard !UserDefaults.standard.bool(forKey: "RoomExtensionsNoCheck") else { return }
        SpikeRunner.record("phase", String(format: "check %.3f", Date().timeIntervalSince1970))
        let start = ContinuousClock.now
        await center.checkForUpdatesNow()
        SpikeRunner.record("check", "\(center.lastCheck.map { "checked=\($0.checked) extensions=\($0.extensions) found=\($0.updatesFound)" } ?? "nil") "
            + "in \(String(format: "%.0f", ms(since: start))) ms; last=\(extApp?.store?.settings.settings.extensionsLastUpdateCheck.map { "\($0)" } ?? "nil")")
        SpikeRunner.record("phase", String(format: "after_check %.3f", Date().timeIntervalSince1970))
        try? await Task.sleep(for: .seconds(20))
    }
}
#endif
