// Feature drives over the private spike hooks: compiled only when the
// framework has them (room_enable_spikes=true; ROOM_SPIKES, set by
// scripts/roomcore-package.sh from the GN args).
#if ROOM_SPIKES
import Foundation

/// Probe real embedded Chrome frontends. CDP drives their DOM, not native UI.
@MainActor
enum HostEmbeddedUISpike {
    static func targets() async throws -> [[String: Any]] {
        let port = UserDefaults.standard.integer(forKey: "RoomSpikeCDPPort")
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/json/list")!)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    static func frontend(prefix: String, suffix: String = "") async throws -> (HostCDP, String) {
        for _ in 0..<150 {
            if let target = try await targets().first(where: { ($0["url"] as? String)?.hasPrefix(prefix) == true && ($0["url"] as? String)?.hasSuffix(suffix) == true }),
               let socket = target["webSocketDebuggerUrl"] as? String, let url = URL(string: socket),
               let id = target["id"] as? String {
                HostSpike.record("frontend-target", ["url": target["url"] ?? "", "type": target["type"] ?? "", "id": id])
                return (HostCDP(url: url), id)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("frontend-targets-at-timeout", try await targets().map { ["url": $0["url"] ?? "", "type": $0["type"] ?? ""] })
        throw HostCDP.Failure("no actual frontend for \(prefix)")
    }

    static func run(_ name: String, host: HostController) async throws {
        if name == "ui-devtools" {
            try host.runSpikeCommand(40004)
            let (frontend, _) = try await frontend(prefix: "devtools://")
            defer { frontend.close() }
            var state = 0
            for _ in 0..<100 {
                state = try host.runSpikeAction("devtools-state")
                if state & 8 != 0 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            HostSpike.record("devtools-owner-state", state)
            HostSpike.record("devtools-frontend", try await frontend.evaluate("({url:location.href,ready:document.readyState,title:document.title,bodyChildren:document.body?.children.length})"))
            guard state & 2 != 0 else { throw HostCDP.Failure("no DevToolsWindow for inspected tab") }
            if state & 1 == 0 {
                HostSpike.record("blocked", "Docking prerequisite absent: no DevtoolsUIController registered on Room window. Undocked frontend/window evidence only; resize/redock/focus not accepted.")
            } else {
                throw HostCDP.Failure("unexpected docking controller requires explicit dock/resize/focus verification")
            }
            return
        }
        for attempt in 1...2 {
            try host.runSpikeCommand(35003)
            let (preview, id) = try await frontend(prefix: "chrome://print/")
            defer { preview.close() }
            var state: [String: Any] = [:]
            for _ in 0..<150 {
                state = try await preview.evaluate("""
                (()=>{const a=document.querySelector('print-preview-app');const p=a?.shadowRoot?.querySelector('print-preview-preview-area');return {ready:document.readyState,state:a?.state ?? -1,pages:a?.documentSettings_?.pageCount ?? 0,previewState:p?.previewState ?? -1,error:a?.error_ ?? null,embeds:Array.from(document.querySelectorAll('embed')).map(e=>e.src)}})()
                """) as? [String: Any] ?? [:]
                if state["state"] as? Int == 1, (state["pages"] as? Int ?? 0) > 0,
                   state["previewState"] as? String == "display-preview" { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            HostSpike.record("print-preview-\(attempt)", state)
            guard state["state"] as? Int == 1, (state["pages"] as? Int ?? 0) > 0,
                  state["previewState"] as? String == "display-preview" else {
                throw HostCDP.Failure("print frontend did not generate preview pages")
            }
            if attempt == 1 {
                let bytes = try host.runSpikeAction("print-preview-pdf")
                HostSpike.record("generated-preview-pdf-bytes", bytes)
                guard bytes > 0 else { throw HostCDP.Failure("no completed preview PDF data") }
            }
            // Cancellation destroys the target, so its reply may lose the race
            // with detach. Accept only confirmed target disappearance below.
            do {
            // Dispatch the actual WebUI cancel control, not Page.printToPDF.
            try await preview.evaluate("""
            (()=>{function find(root){const c=root.querySelector('.cancel-button');if(c)return c;for(const e of root.querySelectorAll('*'))if(e.shadowRoot){const r=find(e.shadowRoot);if(r)return r;}}const b=find(document);if(!b)throw Error('no cancel button');b.click();return true;})()
            """, userGesture: true)
            } catch {
                HostSpike.record("preview-cancel-transport", String(describing: error))
            }
            var closed = false
            for _ in 0..<50 {
                if !(try await targets().contains { $0["id"] as? String == id }) { closed = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            HostSpike.record("print-preview-closed-\(attempt)", closed)
            guard closed else { throw HostCDP.Failure("preview target remained after cancel") }
        }
        HostSpike.record("review-required", "Preview PDF bytes exported from Chrome preview; native Save-to-PDF panel and focus remain separate.")
    }
}
#endif
