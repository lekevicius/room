import Foundation
import RoomCore

/// Directly host Chrome's actual extension popup; does not fake a toolbar.
@MainActor
enum HostExtensionUISpike {
    static func open(host: HostController) async throws -> (HostCDP, String) {
        var opened = false
        for _ in 0..<50 {
            if try host.runSpikeAction("extension-popup-open") == 1 { opened = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard opened else { throw HostCDP.Failure("fixture extension popup could not be created") }
        let result = try await HostEmbeddedUISpike.frontend(prefix: "chrome-extension://", suffix: "/popup.html")
        for _ in 0..<100 {
            if try host.runSpikeAction("extension-popup-state") & 7 == 7 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let state = try host.runSpikeAction("extension-popup-state")
        HostSpike.record("extension-popup-state", state)
        guard state & 7 == 7 else { throw HostCDP.Failure("extension popup not visibly owned by Room") }
        return result
    }

    static func gone(_ id: String) async throws -> Bool {
        for _ in 0..<50 {
            if !(try await HostEmbeddedUISpike.targets().contains { $0["id"] as? String == id }) { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    static func runDevice(host: HostController, profile: RoomProfile) async throws {
        let (popup, popupID) = try await open(host: host)
        let address = try await popup.evaluate("location.href") as! String
        popup.close()
        _ = try host.runSpikeAction("extension-popup-close")
        guard try await gone(popupID) else { throw HostCDP.Failure("setup popup did not close") }
        guard host.open(URL(string: address)!, in: profile, activate: true) != nil else { throw HostCDP.Failure("extension tab unavailable") }
        let cdp = try await HostCDP.connect(port: UserDefaults.standard.integer(forKey: "RoomSpikeCDPPort"), pageURL: address)
        defer { cdp.close() }
        for _ in 0..<50 {
            if (try? await cdp.evaluate("document.readyState==='complete'")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("extension-device-origin", try await cdp.evaluate("({origin:location.origin,usb:typeof navigator.usb})"))
        try await cdp.evaluate("window.__roomExtensionDevice={pending:true};navigator.usb.requestDevice({filters:[{vendorId:65535,productId:65535}]}).then(()=>__roomExtensionDevice={granted:true},e=>__roomExtensionDevice={name:e.name,message:e.message});true", userGesture: true)
        var result: [String: Any] = [:]
        for _ in 0..<100 {
            result = try await cdp.evaluate("__roomExtensionDevice") as? [String: Any] ?? [:]
            if result["pending"] == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("extension-device-result", result)
        guard result["name"] as? String == "NotFoundError" else { throw HostCDP.Failure("extension chooser did not safely cancel or reject") }
        HostSpike.record("boundary", "No extension device grant; rejection is not functional chooser support.")
    }

    static func run(host: HostController, page: RoomWebContents, profile: RoomProfile) async throws {
        let (popup, id) = try await open(host: host)
        defer { popup.close() }
        HostSpike.record("extension-popup-content", try await popup.evaluate("({text:document.body.innerText,focus:document.hasFocus(),url:location.href})"))
        let before = try host.runSpikeAction("extension-popup-size")
        try await popup.evaluate("document.body.style.cssText='margin:0;width:360px;height:240px';true")
        var after = before
        for _ in 0..<50 {
            after = try host.runSpikeAction("extension-popup-size")
            if after != before && after > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("extension-popup-resize", "before=\(before / 10000)x\(before % 10000) after=\(after / 10000)x\(after % 10000)")
        guard after != before, after > 0 else { throw HostCDP.Failure("extension popup did not follow content resize") }
        _ = try host.runSpikeAction("extension-popup-close")
        let closed = try await gone(id)
        HostSpike.record("extension-popup-close", closed)
        guard closed else { throw HostCDP.Failure("popup target survived explicit close") }
        let (owned, secondID) = try await open(host: host)
        owned.close()
        _ = host.open(URL(string: "about:blank")!, in: profile, activate: false)
        page.close()
        let ownerClosed = try await gone(secondID)
        HostSpike.record("extension-popup-owner-close", "pageClosed=\(page.isClosed) targetGone=\(ownerClosed)")
        guard page.isClosed && ownerClosed else { throw HostCDP.Failure("popup target survived owner close") }
        HostSpike.record("boundary", "Direct Chrome popup host only. action.openPopup still requires the real Room extension container/toolbar; native focus/appearance remains reviewer acceptance.")
    }
}
