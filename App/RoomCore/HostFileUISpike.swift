import AppKit
import RoomCore

/// Only isolated fixture dialogs in this process; never chooses a user file.
@MainActor
enum HostFileUISpike {
    static var panels: [NSSavePanel] {
        NSApp.windows.compactMap { $0 as? NSSavePanel }.filter(\.isVisible)
    }

    static func panel() async throws -> NSSavePanel {
        for _ in 0..<100 {
            if let panel = panels.first {
                HostSpike.record("file-panel", "class=\(type(of: panel)) sheet=\(panel.sheetParent != nil) parent=\(String(describing: panel.sheetParent.map { type(of: $0) }))")
                return panel
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HostCDP.Failure("actual native file panel not visible")
    }

    static func panelGone(_ panel: NSSavePanel) async throws -> Bool {
        for _ in 0..<50 {
            if !panel.isVisible { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    static func trigger(_ expression: String, cdp: HostCDP) async throws {
        try await cdp.evaluate("window.__roomFileResult={pending:true,count:0}; (\(expression)).then(()=>{__roomFileResult={pending:false,count:1,granted:true}},e=>{__roomFileResult={pending:false,count:1,name:e.name,message:e.message}});true", userGesture: true)
    }

    static func run(_ name: String, host: HostController, cdp: HostCDP, page: RoomWebContents, profile: RoomProfile) async throws {
        guard panels.isEmpty else { throw HostCDP.Failure("unrelated file panel already visible") }
        if name == "ui-download-close" {
            let output = UserDefaults.standard.string(forKey: "RoomSpikeOutput")!
            let directory = URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("downloads")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await cdp.call("Browser.setDownloadBehavior", ["behavior": "allow", "downloadPath": directory.path, "eventsEnabled": true])
            try await cdp.evaluate("const a=document.createElement('a');a.href='/download-slow';a.download='roomcore-slow.bin';document.body.append(a);a.click();true", userGesture: true)
            var guid: String?
            for _ in 0..<100 {
                _ = try await cdp.evaluate("true")
                guid = cdp.events.last { ($0["method"] as? String)?.hasSuffix("downloadWillBegin") == true }?["params"].flatMap { ($0 as? [String: Any])?["guid"] as? String }
                if guid != nil { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let guid else { throw HostCDP.Failure("no pending download") }
            let decision = try host.runSpikeAction("download-close-decision")
            HostSpike.record("download-close-decision", "state=\(decision) panels=\(panels.count)")
            try await cdp.call("Browser.cancelDownload", ["guid": guid])
            guard decision == 3 else { throw HostCDP.Failure("close decision differs from known immediate-confirm boundary") }
            HostSpike.record("blocked", "Real active download plus direct BrowserWindow close-decision call auto-confirms cancellation without asking. Ordinary macOS non-private window close skips this question; product application/private-profile close decisions need an owned async UI contract. No browser close was simulated as a user approval.")
            return
        }
        if name == "ui-download-destination" {
            guard try host.runSpikeAction("download-prompt-enable") == 1 else { throw HostCDP.Failure("download prompt pref unavailable") }
            try await cdp.call("Browser.setDownloadBehavior", ["behavior": "default", "eventsEnabled": true])
            try await cdp.evaluate("document.querySelector('#download').click();true", userGesture: true)
            let chooser = try await panel()
            chooser.cancel(nil)
            guard try await panelGone(chooser) else { throw HostCDP.Failure("destination panel did not close") }
            var cancelled = false
            for _ in 0..<100 {
                _ = try await cdp.evaluate("true")
                cancelled = cdp.events.contains { event in
                    (event["method"] as? String)?.hasSuffix("downloadProgress") == true && (event["params"] as? [String: Any])?["state"] as? String == "canceled"
                }
                if cancelled { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            HostSpike.record("download-destination-cancelled", cancelled)
            guard cancelled else { throw HostCDP.Failure("destination cancel did not cancel download") }
            return
        }
        if name == "ui-file-input" {
            try await cdp.evaluate("document.body.innerHTML='<input id=fixture type=file>';window.__roomCancel=0;fixture.addEventListener('cancel',()=>__roomCancel++);fixture.click();true", userGesture: true)
            let chooser = try await panel()
            chooser.cancel(nil)
            guard try await panelGone(chooser) else { throw HostCDP.Failure("input panel did not close") }
            var count = 0
            for _ in 0..<50 {
                count = try await cdp.evaluate("__roomCancel") as? Int ?? 0
                if count > 0 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let files = try await cdp.evaluate("fixture.files.length") as? Int
            HostSpike.record("file-input-cancel", "callbacks=\(count) files=\(files ?? -1)")
            guard count == 1, files == 0 else { throw HostCDP.Failure("input cancel callback incorrect") }
            try await cdp.evaluate("fixture.click();true", userGesture: true)
        } else {
            for expression in ["showOpenFilePicker()", "showSaveFilePicker({suggestedName:'roomcore-unused.txt'})", "showDirectoryPicker()"] {
                HostSpike.record("filesystem-trigger", expression)
                try await trigger(expression, cdp: cdp)
                let chooser = try await panel()
                chooser.cancel(nil)
                guard try await panelGone(chooser) else { throw HostCDP.Failure("filesystem panel did not close") }
                var result: [String: Any] = [:]
                for _ in 0..<50 {
                    result = try await cdp.evaluate("__roomFileResult") as? [String: Any] ?? [:]
                    if result["pending"] as? Bool == false { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("filesystem-result", result)
                guard result["name"] as? String == "AbortError", result["count"] as? Int == 1 else { throw HostCDP.Failure("filesystem cancel did not reject exactly once") }
            }
            try await trigger("showOpenFilePicker()", cdp: cdp)
        }
        let owned = try await panel()
        _ = host.open(URL(string: "about:blank")!, in: profile, activate: false)
        page.close()
        let closed = try await panelGone(owned)
        HostSpike.record("file-panel-owner-close", "pageClosed=\(page.isClosed) panelGone=\(closed)")
        if !closed { owned.cancel(nil) }
        guard page.isClosed && closed else { throw HostCDP.Failure("file panel survived owner close; cleaned up explicitly") }
        HostSpike.record("boundary", "No user file chosen or persistent filesystem grant created. Native navigation/selection and grant revocation remain separate acceptance.")
    }
}
