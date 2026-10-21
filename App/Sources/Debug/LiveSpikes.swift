#if DEBUG
import AppKit
import Engine
import Model
import Tabs

/// Live-site check `live` (5.0a; `scripts/live-check.sh`, never CI): loads
/// the real sites named in `-RoomLiveSites <file>` (`scripts/live-sites.json`)
/// on the launch's throwaway state with the blocker's defaults (the bundled
/// lists, cookie banners rejected) and reads results from each page. Per
/// site two passes, each in a fresh tab: `off` (the site panel's switch off: nothing
/// blocked, the banner as the site shows it) and then `on` (the defaults).
/// Each pass records the blocked-request count, the elements whose computed
/// `display` is `none` (cosmetic filters hide with `display: none`; `on − off`
/// is only indicative: the two passes load different ads), the ad
/// containers by common names and how many of them are hidden, the visible consent-platform containers from a
/// list of common ones, the selectors the site's entry asks for, and the
/// cookie banner autoconsent answered (`TabController.onCookieBanner`). The
/// script judges the expectations. These are requests the session makes for a
/// check, never ones the product makes.
extension SpikeRunner.Context {
    struct LiveSite: Decodable {
        let name: String
        let url: String
        var settle: Double?
        var present: [String]?
    }

    /// Containers of common consent platforms (OneTrust, Cookiebot, Google's
    /// Funding Choices, Quantcast, Sourcepoint, Didomi, Usercentrics,
    /// consentmanager, TrustArc, CookieYes, Admiral) and YouTube's own dialog.
    static let consentContainers = [
        "#onetrust-banner-sdk", "#CybotCookiebotDialog", ".fc-consent-root", "#qc-cmp2-container",
        "[id^='sp_message_container']", "#didomi-host", "#didomi-popup", "#usercentrics-root", "#cmpbox",
        "#truste-consent-track", ".cky-consent-container", "[class*='admiral']", "ytd-consent-bump-v2-lightbox",
        "tp-yt-paper-dialog#dialog", "#cookie-consent", "#gdpr-consent-tool-wrapper",
    ]

    func liveChecks() async {
        guard let path = UserDefaults.standard.string(forKey: "RoomLiveSites"),
              let data = FileManager.default.contents(atPath: path),
              let sites = try? JSONDecoder().decode([LiveSite].self, from: data) else {
            return SpikeRunner.record("error", "live: no -RoomLiveSites file")
        }
        guard let blocking = AppDelegate.current?.contentBlocking else {
            return SpikeRunner.record("error", "live: no blocker (no engine?)")
        }
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        blocking.update { $0 = ContentBlockingSettings() }
        await blocking.apply()
        SpikeRunner.record("live_lists", "built=\(blocking.lastReport.map { "\($0.engineBytes) bytes" } ?? "no report") "
            + blocking.ruleCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        var banners: [String] = []
        tabs.onCookieBanner = { _, platform, optedOut in banners.append("\(platform):\(optedOut ? "opted-out" : "not-opted-out")") }
        for site in sites where only.isEmpty || only.contains(site.name) {
            guard let url = URL(string: site.url), let domain = blocking.site(of: site.url) else {
                SpikeRunner.record("live_\(site.name)", "error bad url \(site.url)")
                continue
            }
            var page: (any WebContents)?
            for pass in ["off", "on"] {
                blocking.setBlocking(pass == "on", on: domain)
                await blocking.apply()
                banners = []
                let start = Date()
                // A fresh tab per pass (a reload of a heavy page, delfi.lt, left it without a live document).
                page?.close()
                page = await open(url, timeout: 30)
                guard let page else {
                    SpikeRunner.record("live_\(site.name)_\(pass)", "error: the page did not open")
                    break
                }
                // A heavy page may still report loading at the timeout; its document is what is read.
                _ = await waitUntilAsync(30) { await self.js(page, "document.readyState") == "\"complete\"" }
                let loaded = Date().timeIntervalSince(start)
                try? await Task.sleep(for: .seconds(site.settle ?? 8))
                let probe = Self.liveProbe(present: site.present ?? [], host: url.host() ?? "")
                var read = "error"
                for attempt in 0..<4 {
                    do {
                        read = try await page.executeJavaScript(probe)
                        break
                    } catch {
                        read = "error(\(error))"
                        if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
                    }
                }
                SpikeRunner.record("live_\(site.name)_\(pass)", String(format: "load_s=%.1f blocked=%ld ", loaded, page.blockedRequestCount)
                    + "probe=\(read) cookie_banner=\(banners.isEmpty ? "none" : banners.joined(separator: ","))")
            }
            blocking.setBlocking(true, on: domain)
            page?.close()
            try? await Task.sleep(for: .milliseconds(500))
        }
        tabs.onCookieBanner = nil
        blocking.update { $0 = ContentBlockingSettings() }
        await blocking.apply()
    }

    /// The bundled lists' element-hiding selectors (EasyList and the EasyList
    /// Cookie List) that apply on `host`: the generic `##` rules and the
    /// `domain##` rules naming it (exceptions, procedural and scriptlet rules
    /// left out). What the engine's cosmetic filters hide, read from the files.
    static func listSelectors(for host: String) -> [String] {
        guard let folder = Bundle.main.resourceURL?.appending(path: "ContentBlocking") else { return [] }
        var selectors: [String] = []
        for name in ["easylist.txt", "easylist-cookie.txt"] {
            guard let text = try? String(contentsOf: folder.appending(path: name), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let range = line.range(of: "##"), !line.hasPrefix("!") else { continue }
                let domains = line[line.startIndex..<range.lowerBound]
                let selector = String(line[range.upperBound...])
                if domains.contains("#") || selector.contains(":-abp-") || selector.contains(":has-text") || selector.hasPrefix("+js") { continue }
                if !domains.isEmpty {
                    let names = domains.split(separator: ",").map(String.init)
                    guard names.contains(where: { !$0.hasPrefix("~") && (host == $0 || host.hasSuffix("." + $0)) }) else { continue }
                }
                selectors.append(selector)
            }
        }
        return selectors
    }

    /// One JSON object: the page's host, hidden and total elements in the
    /// body, iframes, the visible consent containers and which of `present` exist.
    static func liveProbe(present: [String], host: String) -> String {
        let lists = String(data: (try? JSONEncoder().encode(listSelectors(for: host))) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        let containers = consentContainers.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" }.joined(separator: ",")
        let wanted = present.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" }.joined(separator: ",")
        return """
        (() => {
          const skip = new Set(['SCRIPT','STYLE','META','LINK','TITLE','TEMPLATE','NOSCRIPT','BR','SOURCE','TRACK','PARAM','BASE']);
          let hidden = 0, total = 0;
          for (const e of document.querySelectorAll('body *')) {
            if (skip.has(e.tagName)) continue;
            total++;
            if (getComputedStyle(e).display === 'none') hidden++;
          }
          const visible = (e) => { const r = e.getBoundingClientRect(); const s = getComputedStyle(e);
            return r.width * r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0; };
          const banners = [\(containers)].filter(sel => { try { return [...document.querySelectorAll(sel)].some(visible); } catch (_) { return false; } });
          // Ad containers by the names ad servers and sites give them (EasyList's generic hiding targets these).
          const adLike = [...document.querySelectorAll("[id^='div-gpt-ad'],[id*='google_ads'],ins.adsbygoogle,.adsbygoogle,[data-ad-slot],[data-google-query-id],"
            + "[id^='ad-'],[id^='ad_'],[class^='ad-'],[class*=' ad-'],[class*='advert'],[id*='banner'],[class*='banner'],[class*='reklam'],[id*='reklam']")];
          const adHidden = adLike.filter(e => getComputedStyle(e).display === 'none').length;
          // The lists' hiding selectors that apply here: elements they match, and of those hidden.
          const allSels = \(lists);
          // Only the selectors whose first id or class occurs on the page (the rest cannot match).
          const names = new Set();
          for (const e of document.querySelectorAll('[id],[class]')) {
            if (e.id) names.add('#' + e.id);
            for (const c of e.classList) names.add('.' + c);
          }
          const sels = allSels.filter(sel => { const m = sel.match(/[#.][A-Za-z0-9_-]+/); return !m || names.has(m[0]); });
          const matched = new Set();
          for (let i = 0; i < sels.length; i += 300) {
            const chunk = sels.slice(i, i + 300);
            try { document.querySelectorAll(chunk.join(',')).forEach(e => matched.add(e)); }
            catch (_) { for (const sel of chunk) { try { document.querySelectorAll(sel).forEach(e => matched.add(e)); } catch (_) {} } }
          }
          let listHidden = 0;
          for (const e of matched) if (getComputedStyle(e).display === 'none') listHidden++;
          const present = [\(wanted)].filter(sel => { try { return document.querySelector(sel) !== null; } catch (_) { return false; } });
          return { host: location.host, hidden, total, adLike: adLike.length, adHidden, listSelectors: allSels.length, listCandidates: sels.length, listMatched: matched.size, listHidden, iframes: document.querySelectorAll('iframe').length, banners, present };
        })()
        """
    }
}
#endif
