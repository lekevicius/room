import Engine
import FakeEngine
import Foundation
import Testing
@testable import Chrome

@Suite("The site panel: permission state per origin (ROADMAP 2.6 task 3)")
struct SitePanelTests {
    @Test("Nothing stored shows the default; a row offers Ask only for permissions a site asks for")
    func mapping() {
        #expect(SitePanelRules.effective(nil, for: .geolocation) == .ask)
        #expect(SitePanelRules.effective(nil, for: .popups) == .block)
        #expect(SitePanelRules.effective(nil, for: .javascript) == .allow)
        #expect(SitePanelRules.effective(.block, for: .camera) == .block)
        // A stored value a row cannot show falls back to the default.
        #expect(SitePanelRules.effective(.ask, for: .sound) == .allow)
        #expect(SitePanelRules.options(for: .notifications) == [.ask, .allow, .block])
        #expect(SitePanelRules.options(for: .popups) == [.allow, .block])
        #expect(SitePanelRules.storedValue(for: .ask, permission: .camera) == nil)
        #expect(SitePanelRules.storedValue(for: .allow, permission: .popups) == .allow)
        #expect(SitePanelRules.optionTitle(.block, for: .popups) == "Block (default)")
        #expect(SitePanelRules.optionTitle(.allow, for: .popups) == "Allow")
    }

    @Test("Rows: location, camera, microphone, notifications always, then whatever the site has a setting for")
    func rows() {
        #expect(SitePanelRules.rows(stored: [:]) == [.geolocation, .camera, .microphone, .notifications])
        #expect(SitePanelRules.rows(stored: [.popups: .allow, .camera: .block]) == [.geolocation, .camera, .microphone, .notifications, .popups])
    }

    @Test("The origin is scheme, host and port of web pages only")
    func origin() {
        #expect(SitePanelRules.origin(of: URL(string: "https://a.example:8443/x?y#z"))?.absoluteString == "https://a.example:8443")
        #expect(SitePanelRules.origin(of: URL(string: "about:blank")) == nil)
        #expect(SitePanelRules.origin(of: URL(string: "file:///tmp/a.html")) == nil)
    }

    @Test("Changing a row writes the page's profile for its origin only; the default removes it; Reset clears all; a reload is offered")
    func modelOnFakeProfile() async throws {
        let engine = FakeApplication()
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let profile = try engine.profile(named: "Work")
        let origin = URL(string: "https://a.example")!
        var reloads = 0
        let model = SitePanelModel(origin: origin, security: SecurityState(level: .secure), profile: profile) { reloads += 1 }
        #expect(!model.needsReload)
        model.set(.block, for: .notifications)
        model.set(.allow, for: .popups)
        #expect(profile.permissionSetting(.notifications, for: origin) == .block)
        #expect(profile.permissionSetting(.notifications, for: URL(string: "https://b.example")!) == nil)
        #expect(model.rows.contains(.popups))
        #expect(model.needsReload)
        model.set(.ask, for: .notifications)
        #expect(profile.permissionSetting(.notifications, for: origin) == nil)
        await model.resetPermissions()
        #expect(profile.permissionSettings["https://a.example"]?.isEmpty ?? true)
        // B-43: the reset also forgets the site's certificate decisions.
        #expect(profile.clearedSiteData.contains { $0.0 == .permissions && $0.1 == origin })
        #expect(!model.hasStoredSettings)
        model.reload()
        #expect(reloads == 1 && !model.needsReload)
    }

    @Test("An engine that answers with the default (an effective value) does not make a row the site's own")
    func defaultsAreNotStored() throws {
        let engine = FakeApplication()
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let profile = try engine.profile(named: "Default")
        let origin = URL(string: "https://a.example")!
        profile.setPermissionSetting(.allow, for: .javascript, origin: origin)
        profile.setPermissionSetting(.ask, for: .clipboard, origin: origin)
        profile.setPermissionSetting(.block, for: .popups, origin: origin)
        profile.setPermissionSetting(.allow, for: .geolocation, origin: origin)
        let model = SitePanelModel(origin: origin, security: .none, profile: profile) {}
        #expect(model.rows == [.geolocation, .camera, .microphone, .notifications])
        #expect(model.setting(.geolocation) == .allow)
        #expect(model.hasStoredSettings)
    }

    @Test("Clear site data asks the page's profile for cookies and storage of the origin")
    func clearData() async throws {
        let engine = FakeApplication()
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let profile = try engine.profile(named: "Default")
        let origin = URL(string: "https://a.example")!
        let model = SitePanelModel(origin: origin, security: .none, profile: profile) {}
        await model.clearSiteData()
        #expect(profile.clearedSiteData.count == 1)
        #expect(profile.clearedSiteData.first?.types == [.cookies, .storage])
        #expect(profile.clearedSiteData.first?.origin == origin)
        #expect(model.siteDataCleared)
    }
}
