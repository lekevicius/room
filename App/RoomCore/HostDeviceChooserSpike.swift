import Foundation

/// Real chooser callbacks through CDP; never select or connect to a device.
@MainActor
enum HostDeviceChooserSpike {
    static func run(_ name: String, host: HostController, cdp: HostCDP) async throws {
        let request: String
        var browserCDP: HostCDP?
        defer { browserCDP?.close() }
        switch name {
        case "ui-usb":
            request = "navigator.usb.requestDevice({filters:[{vendorId:65535,productId:65535}]})"
        case "ui-hid":
            request = "navigator.hid.requestDevice({filters:[{vendorId:65535,productId:65535}]})"
        case "ui-serial":
            request = "navigator.serial.requestPort({filters:[{usbVendorId:65535,usbProductId:65535}]})"
        case "ui-bluetooth":
            // BluetoothEmulation is bound to the browser agent, not a page.
            let browser = try await HostCDP.connectBrowser(port: UserDefaults.standard.integer(forKey: "RoomSpikeCDPPort"))
            browserCDP = browser
            try await browser.call("BluetoothEmulation.enable", ["state": "powered-on", "leSupported": true])
            request = "navigator.bluetooth.requestDevice({filters:[{namePrefix:'RoomCoreNoDeviceFixture'}]})"
        default:
            throw HostCDP.Failure("unknown chooser probe")
        }
        try await cdp.call("DeviceAccess.enable")
        HostSpike.record("ui-probe-trigger", name)
        try await cdp.evaluate("""
            window.__roomDeviceProbe={pending:true};
            (\(request)).then(value=>{
                __roomDeviceProbe={pending:false,granted:!Array.isArray(value)||value.length>0,empty:Array.isArray(value)&&value.length===0};
            },error=>{__roomDeviceProbe={pending:false,name:error.name,message:error.message}});
            true
            """, userGesture: true)
        var cancelled = false
        var shown = false
        var result: [String: Any] = [:]
        for _ in 0..<100 {
            result = try await cdp.evaluate("__roomDeviceProbe") as? [String: Any] ?? [:]
            if !cancelled {
                let count = try host.runSpikeAction("ui-dialog-count")
                if count > 0 {
                    shown = true
                    HostSpike.record("chooser-owned-dialogs", count)
                }
            }
            if !cancelled,
               let event = cdp.events.first(where: { $0["method"] as? String == "DeviceAccess.deviceRequestPrompted" }),
               let params = event["params"] as? [String: Any], let id = params["id"] as? String {
                HostSpike.record("chooser-device-count", (params["devices"] as? [Any])?.count ?? -1)
                try await cdp.call("DeviceAccess.cancelPrompt", ["id": id])
                cancelled = true
                HostSpike.record("chooser-cancel-issued", true)
            }
            if !cancelled && shown {
                cancelled = try host.runSpikeAction("ui-dialog-cancel") > 0
                HostSpike.record("chooser-dialog-cancel-issued", cancelled)
            }
            if result["pending"] as? Bool == false { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("chooser-result", result)
        guard shown, cancelled, result["pending"] as? Bool == false,
              result["granted"] as? Bool != true else {
            throw HostCDP.Failure("chooser did not complete through its cancel path")
        }
        HostSpike.record("review-required", "Chrome chooser cancellation only; native focus/anchor and real device grants remain unverified")
    }
}
