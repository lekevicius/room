import Foundation
import RoomCore

@MainActor
enum HostAutofillUISpike {
    static func key(_ key: String, code: Int, cdp: HostCDP) async throws {
        try await cdp.call("Input.dispatchKeyEvent", ["type": "keyDown", "key": key, "code": key, "windowsVirtualKeyCode": code])
        try await cdp.call("Input.dispatchKeyEvent", ["type": "keyUp", "key": key, "code": key, "windowsVirtualKeyCode": code])
    }

    static func run(_ name: String, host: HostController, cdp: HostCDP, page: RoomWebContents, profile: RoomProfile) async throws {
        if name == "ui-passwords" {
            let state = try host.runSpikeAction("password-presentation")
            HostSpike.record("password-presentation", state)
            guard state == 1 else { throw HostCDP.Failure("unexpected password presentation prerequisites") }
            HostSpike.record("blocked", "Actual TabDialogs password presentation returns before model-state dispatch: Room has no ToolbarButtonProvider. This shared prerequisite blocks both save and update bubbles; no credential storage or save/update acceptance claimed.")
            return
        }
        if name == "ui-card-save" {
            for decision in ["cancel", "accept"] {
                guard try host.runSpikeAction("card-save") == 1 else { throw HostCDP.Failure("local card controller unavailable") }
                var shown = 0
                for _ in 0..<50 {
                    shown = try host.runSpikeAction("ui-dialog-count")
                    if shown > 0 { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("card-owned-dialogs", shown)
                guard shown == 1 else { throw HostCDP.Failure("local card bubble missing") }
                _ = try host.runSpikeAction("ui-dialog-\(decision)")
                var callbacks = 0
                for _ in 0..<50 {
                    callbacks = try host.runSpikeAction("card-decisions")
                    let remaining = try host.runSpikeAction("ui-dialog-count")
                    if callbacks == 1 && remaining == 0 { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("card-\(decision)", callbacks)
                guard callbacks == 1 else { throw HostCDP.Failure("local card decision did not complete once") }
            }
            _ = try host.runSpikeAction("card-save")
            var ownerBubble = false
            for _ in 0..<50 {
                if try host.runSpikeAction("ui-dialog-count") == 1 { ownerBubble = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard ownerBubble else { throw HostCDP.Failure("owner-close card bubble never became visible") }
            _ = host.open(URL(string: UserDefaults.standard.string(forKey: "RoomSpikeBaseURL")! + "/features")!, in: profile, activate: false)
            page.close()
            var remaining = -1
            for _ in 0..<50 {
                remaining = try host.runSpikeAction("ui-dialog-count")
                if remaining == 0 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let ownerCallbacks = try host.runSpikeAction("card-decisions")
            HostSpike.record("card-owner-closed", "closed=\(page.isClosed) dialogs=\(remaining) callbacks=\(ownerCallbacks)")
            guard page.isClosed, remaining == 0 else { throw HostCDP.Failure("card bubble survived owner destruction") }
            HostSpike.record("boundary", "Synthetic local save controller callbacks only; no actual payment, upload, account or persistent card save.")
            return
        }
        guard try host.runSpikeAction("address-seed") == 1 else { throw HostCDP.Failure("address seed unavailable") }
        var profiles = 0
        for _ in 0..<100 {
            profiles = try host.runSpikeAction("address-profiles")
            if profiles > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("stored-synthetic-profiles", profiles)
        guard profiles == 1 else { throw HostCDP.Failure("synthetic address was not persisted in isolated profile") }
        try await cdp.evaluate("""
            document.body.innerHTML=`<form><label>Name<input id=name autocomplete=name></label><label>Street<input id=street autocomplete=street-address></label><label>City<input id=city autocomplete=address-level2></label><label>State<input id=state autocomplete=address-level1></label><label>Zip<input id=zip autocomplete=postal-code></label><label>Email<input id=email autocomplete=email></label></form>`;true
            """)
        try await Task.sleep(for: .seconds(1))
        page.focus()
        _ = try host.runSpikeAction("address-diagnostics")
        let point = try await cdp.evaluate("(()=>{let r=document.getElementById('name').getBoundingClientRect();return {x:r.x+10,y:r.y+10}})()") as! [String: Any]
        for type in ["mousePressed", "mouseReleased"] {
            try await cdp.call("Input.dispatchMouseEvent", ["type": type, "x": point["x"]!, "y": point["y"]!, "button": "left", "clickCount": 1])
        }
        HostSpike.record("suggestion-input-before", try await cdp.evaluate("({active:document.activeElement?.id,focus:document.hasFocus(),secure:isSecureContext})"))
        // AutofillAgent filters caret/value state. Explicitly focus the field
        // and provide a prefix through real input dispatch before querying.
        try await cdp.evaluate("document.getElementById('name').focus();true")
        try await cdp.call("Input.insertText", ["text": "R"])
        try await key("ArrowDown", code: 40, cdp: cdp)
        HostSpike.record("suggestion-input-after", try await cdp.evaluate("({active:document.activeElement?.id,value:document.activeElement?.value,focus:document.hasFocus(),secure:isSecureContext})"))
        var suggestions = 0
        for _ in 0..<50 {
            suggestions = try host.runSpikeAction("address-suggestions")
            if suggestions > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try host.runSpikeAction("address-diagnostics")
        HostSpike.record("address-suggestions", suggestions)
        guard suggestions > 0 else { throw HostCDP.Failure("actual field did not show saved-address suggestions") }
        try await key("ArrowDown", code: 40, cdp: cdp)
        try await key("Enter", code: 13, cdp: cdp)
        var values: [String: Any] = [:]
        for _ in 0..<50 {
            values = try await cdp.evaluate("Object.fromEntries([...document.querySelectorAll('input')].map(e=>[e.id,e.value]))") as? [String: Any] ?? [:]
            if values["street"] as? String == "1 Test Street" { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("address-filled", values)
        guard values["name"] as? String == "Room Fixture", values["street"] as? String == "1 Test Street" else { throw HostCDP.Failure("suggestion selection did not fill the synthetic address") }
    }
}
