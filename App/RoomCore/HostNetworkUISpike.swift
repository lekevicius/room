// Feature drives over the private spike hooks: compiled only when the
// framework has them (room_enable_spikes=true; ROOM_SPIKES, set by
// scripts/roomcore-package.sh from the GN args).
#if ROOM_SPIKES
import Foundation
import RoomCore

/// All destinations are owned loopback servers; only their test address-space
/// classification changes. No LAN hardware or external hosts are contacted.
@MainActor
enum HostNetworkUISpike {
    static func permissions(_ cdp: HostCDP) async throws -> [String: Any] {
        try await cdp.evaluate("(async()=>Object.fromEntries(await Promise.all(['local-network','loopback-network','local-network-access'].map(async name=>{try{return [name,(await navigator.permissions.query({name})).state]}catch(e){return [name,e.name]}}))))()") as? [String: Any] ?? [:]
    }

    static func fetch(_ url: String, cdp: HostCDP) async throws {
        let quoted = String(decoding: try JSONSerialization.data(withJSONObject: url + "/network", options: .fragmentsAllowed), as: UTF8.self)
        try await cdp.evaluate("window.__roomNet={pending:true};fetch(\(quoted),{cache:'no-store'}).then(r=>r.text()).then(text=>__roomNet={pending:false,text},e=>__roomNet={pending:false,name:e.name,message:e.message});true", userGesture: true)
    }

    static func result(_ cdp: HostCDP) async throws -> [String: Any] {
        for _ in 0..<100 {
            let value = try await cdp.evaluate("__roomNet") as? [String: Any] ?? [:]
            if value["pending"] as? Bool == false { return value }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HostCDP.Failure("network request remained pending")
    }

    static func prompt(host: HostController, cdp: HostCDP) async throws {
        let hostPrompts = HostPageRecorder.permissionPrompts
        for _ in 0..<100 {
            if try host.runSpikeAction("network-pending") == 1 {
                // A page whose delegate answers prompts gets the host's prompt (3.4a).
                if HostPageRecorder.permissionPrompts > hostPrompts {
                    HostSpike.record("network-host-prompts", HostPageRecorder.permissionPrompts)
                    return
                }
                let count = try host.runSpikeAction("ui-dialog-count")
                if count > 0 {
                    HostSpike.record("network-owned-dialogs", count)
                    return
                }
            }
            let value = try await cdp.evaluate("__roomNet") as? [String: Any] ?? [:]
            if value["pending"] as? Bool == false {
                HostSpike.record("network-no-prompt-result", value)
                throw HostCDP.Failure("network request completed before a real permission prompt")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HostCDP.Failure("network permission prompt did not appear")
    }

    static func run(host: HostController, cdp: HostCDP, page: RoomWebContents, profile: RoomProfile) async throws {
        let defaults = UserDefaults.standard
        let local = defaults.string(forKey: "RoomSpikeLocalURL")!
        let loopback = defaults.string(forKey: "RoomSpikeLoopbackURL")!
        HostSpike.record("network-effective-flags", try host.runSpikeAction("network-flags"))
        HostSpike.record("network-permissions-initial", try await permissions(cdp))
        _ = try host.runSpikeAction("network-reset")
        for (name, url) in [("local-network", local), ("loopback-network", loopback)] {
            try await fetch(url, cdp: cdp)
            try await prompt(host: host, cdp: cdp)
            _ = try host.runSpikeAction("deny-permission")
            let denied = try await result(cdp)
            let deniedState = try await permissions(cdp)
            HostSpike.record("\(name)-denied", ["result": denied, "permissions": deniedState])
            guard denied["name"] as? String == "TypeError", deniedState[name] as? String == "denied" else { throw HostCDP.Failure("network denial not enforced") }
            _ = try host.runSpikeAction("network-reset")
            try await fetch(url, cdp: cdp)
            try await prompt(host: host, cdp: cdp)
            guard try host.runSpikeAction("network-accept") == 1 else { throw HostCDP.Failure("network accept rejected request type") }
            let accepted = try await result(cdp)
            let acceptedState = try await permissions(cdp)
            HostSpike.record("\(name)-accepted", ["result": accepted, "permissions": acceptedState])
            guard accepted["text"] as? String == "Room network fixture", acceptedState[name] as? String == "granted" else { throw HostCDP.Failure("network grant did not permit fixture fetch") }
            try await fetch(url, cdp: cdp)
            let reused = try await result(cdp)
            guard reused["text"] as? String == "Room network fixture", try host.runSpikeAction("network-pending") == 0 else { throw HostCDP.Failure("existing network grant was not reused") }
            HostSpike.record("\(name)-reuse", true)
        }
        // The second reset also reset the first grant. Verify the remaining
        // loopback grant across actual tab destruction within the same origin.
        let address = defaults.string(forKey: "RoomSpikeBaseURL")! + "/features#network-owner"
        let replacement = host.open(URL(string: address)!, in: profile, activate: false)!
        page.close()
        let next = try await HostCDP.connect(port: defaults.integer(forKey: "RoomSpikeCDPPort"), pageURL: address)
        defer { next.close() }
        for _ in 0..<100 {
            if (try? await next.evaluate("location.hash==='#network-owner' && document.readyState==='complete'")) as? Bool == true { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let retained = try await permissions(next)
        HostSpike.record("network-grant-after-owner-close", retained)
        guard retained["loopback-network"] as? String == "granted" else { throw HostCDP.Failure("same-origin grant did not survive tab destruction") }
        _ = try host.runSpikeAction("network-reset")
        let reset = try await permissions(next)
        HostSpike.record("network-revoked", reset)
        guard reset["loopback-network"] as? String == "prompt" else { throw HostCDP.Failure("network grant did not reset") }
        try await fetch(loopback, cdp: next)
        try await prompt(host: host, cdp: next)
        let spare = host.open(URL(string: defaults.string(forKey: "RoomSpikeBaseURL")! + "/features#network-spare")!, in: profile, activate: false)!
        for _ in 0..<100 { if !spare.isLoading { break }; try await Task.sleep(for: .milliseconds(100)) }
        replacement.close()
        var pending = -1
        for _ in 0..<50 {
            pending = try host.runSpikeAction("network-pending")
            if pending == 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("network-pending-owner-close", "closed=\(replacement.isClosed) pending=\(pending)")
        guard replacement.isClosed, pending == 0 else { throw HostCDP.Failure("network permission request survived owner close") }
    }
}
#endif
