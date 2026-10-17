import Foundation
import Integration
import Model
import Testing

@Suite("Content blocking: lists the engine reads (B-30)")
struct ContentBlockingPlanTests {
    let bundle = URL(filePath: "/App/Resources/ContentBlocking")
    func ids(_ plan: ContentBlockingPlan) -> [String] { plan.lists.map(\.id) }

    @Test("Out of the box: EasyList, EasyPrivacy and the cookie list, from the bundle, nothing to download")
    func defaults() {
        let plan = ContentBlockingPlan.make(settings: ContentBlockingSettings(), bundleDirectory: bundle, downloads: [:])
        #expect(ids(plan) == ["easylist", "easyprivacy", "easylist-cookie"])
        #expect(plan.lists[0].fileURL == bundle.appending(path: "easylist.txt"))
        #expect(plan.missing.isEmpty && plan.isEnabled && plan.cookieBanners == .reject)
    }

    @Test("Each switch takes its lists out; with everything off the engine is off")
    func switches() {
        var settings = ContentBlockingSettings()
        settings.blockAds = false
        #expect(ids(.make(settings: settings, bundleDirectory: bundle, downloads: [:])) == ["easyprivacy", "easylist-cookie"])
        settings.blockTrackers = false
        settings.cookieBanners = .hide
        #expect(ids(.make(settings: settings, bundleDirectory: bundle, downloads: [:])) == ["easylist-cookie"])
        settings.cookieBanners = .off
        let off = ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle, downloads: [:])
        #expect(off.lists.isEmpty && !off.isEnabled)
        settings.customRules = "||ads.example^\n"
        #expect(ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle, downloads: [:]).isEnabled)
    }

    @Test("A downloaded update replaces the bundled copy")
    func updateWins() {
        let update = URL(filePath: "/Lists/easylist.txt")
        let plan = ContentBlockingPlan.make(settings: ContentBlockingSettings(), bundleDirectory: bundle,
                                            downloads: ["easylist": update])
        #expect(plan.lists.first { $0.id == "easylist" }?.fileURL == update)
    }

    @Test("An optional list turned on is missing until downloaded, and follows its category's switch")
    func optionalLists() {
        var settings = ContentBlockingSettings()
        settings.setList("ublock-filters", enabled: true)
        let before = ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle, downloads: [:])
        #expect(before.missing == ["ublock-filters"] && !ids(before).contains("ublock-filters"))
        let file = URL(filePath: "/Lists/ublock-filters.txt")
        #expect(ids(.make(settings: settings, bundleDirectory: bundle, downloads: ["ublock-filters": file])).contains("ublock-filters"))
        settings.blockAds = false
        let adsOff = ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle, downloads: ["ublock-filters": file])
        #expect(!ids(adsOff).contains("ublock-filters") && adsOff.missing.isEmpty)
    }

    @Test("Custom lists: enabled ones are read once downloaded, disabled ones never")
    func customLists() {
        var settings = ContentBlockingSettings()
        let on = CustomFilterList(url: URL(string: "https://lists.example/mine.txt")!)
        let off = CustomFilterList(url: URL(string: "https://lists.example/old.txt")!, isEnabled: false)
        settings.customLists = [on, off]
        let plan = ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle, downloads: [:])
        #expect(plan.missing == [on.id.uuidString])
        let file = URL(filePath: "/Lists/mine.txt")
        let downloaded = ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle,
                                                  downloads: [on.id.uuidString: file, off.id.uuidString: file])
        #expect(ids(downloaded).filter { $0 == on.id.uuidString || $0 == off.id.uuidString } == [on.id.uuidString])
    }
}

@Suite("Content blocking: the per-site switch and settings (B-30)")
struct ContentBlockingSettingsTests {
    @Test("Turning blocking off for a site allows it once, lower-cased; turning it on again removes it")
    func perSiteSwitch() {
        var settings = ContentBlockingSettings()
        settings.setBlocking(false, on: "Example.COM")
        settings.setBlocking(false, on: "example.com")
        settings.setBlocking(false, on: "another.org")
        #expect(settings.allowedSites == ["another.org", "example.com"])
        #expect(!settings.blocks(on: "EXAMPLE.com") && settings.blocks(on: "news.example"))
        settings.setBlocking(true, on: "example.com")
        #expect(settings.allowedSites == ["another.org"])
    }

    @Test("Settings stored before blocking existed decode to blocking on, updates off")
    func decodesDefaults() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"crashReports":true}"#.utf8))
        #expect(old.contentBlocking == ContentBlockingSettings())
        #expect(old.contentBlocking.blockAds && old.contentBlocking.blockTrackers)
        #expect(old.contentBlocking.cookieBanners == .reject && !old.contentBlocking.automaticListUpdates)
        let partial = try JSONDecoder().decode(ContentBlockingSettings.self, from: Data(#"{"blockAds":false}"#.utf8))
        #expect(!partial.blockAds && partial.blockTrackers)
    }
}

@Suite("Content blocking: list text and the update schedule (B-30)")
struct FilterListTextTests {
    let list = """
    [Adblock Plus 2.0]
    ! Title: EasyList
    ! Expires: 4 days (update frequency)
    ! Homepage: https://easylist.to/
    ||ads.example^
    example.com##.banner
    @@||ads.example/ok.js
    """

    @Test("Title, expiry and rule count from the header and body")
    func header() {
        #expect(FilterListText.title(of: list) == "EasyList")
        #expect(FilterListText.expiry(of: list) == TimeInterval(4 * 86_400))
        #expect(FilterListText.expiry(of: "! Expires: 12 hours") == TimeInterval(12 * 3_600))
        #expect(FilterListText.expiry(of: "! Expires: soon") == nil)
        #expect(FilterListText.ruleCount(list) == 3)
        #expect(FilterListText.ruleCount("# hosts\n0.0.0.0 ads.example\n") == 1)
    }

    @Test("An HTML error page is not a list")
    func notAList() {
        #expect(FilterListText.looksLikeFilterList(list))
        #expect(!FilterListText.looksLikeFilterList("<!DOCTYPE html><html><body>404</body></html>"))
    }

    @Test("A list is due after its expiry, never sooner than a day nor later than a week")
    func schedule() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        #expect(FilterListSchedule.isDue(lastFetched: nil, expiry: nil, now: fetched))
        #expect(!FilterListSchedule.isDue(lastFetched: fetched, expiry: 4 * 86_400, now: fetched + 3 * 86_400))
        #expect(FilterListSchedule.isDue(lastFetched: fetched, expiry: 4 * 86_400, now: fetched + 4 * 86_400))
        #expect(!FilterListSchedule.isDue(lastFetched: fetched, expiry: 8 * 3_600, now: fetched + 12 * 3_600))
        #expect(FilterListSchedule.isDue(lastFetched: fetched, expiry: nil, now: fetched + 7 * 86_400))
        #expect(FilterListSchedule.interval(expiry: 30 * 86_400) == FilterListSchedule.maximumInterval)
    }
}
