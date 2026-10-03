import AppKit
import RoomCore

/// Feature drives use the original Phase 1.4 pages over loopback HTTP.
/// A completed drive is not automatically a functional pass: observations,
/// stub hits, crash logs, and (where needed) native UI must be reviewed.
@MainActor
enum HostFeatureSpike {
    static let names = ["popups", "dialogs", "keys", "audio", "scroll", "transparent",
                        "corners", "band", "form", "extension", "downloads", "permissions",
                        "auth", "certificate", "find", "zoom", "print", "fullscreen"]

    static func run(_ name: String, host: HostController, profile: RoomProfile) async {
        guard names.contains(name) else { HostSpike.record("error", "unknown spike \(name)"); return }
        let defaults = UserDefaults.standard
        guard let base = defaults.string(forKey: "RoomSpikeBaseURL"),
              let secure = defaults.string(forKey: "RoomSpikeSecureURL") else {
            HostSpike.record("error", "use scripts/roomcore-features.sh to start fixtures")
            return
        }
        let pageName = ["dialogs": "popups", "extension": "form", "find": "scroll", "zoom": "scroll"] [name] ?? name
        let original = ["popups", "keys", "audio", "scroll", "transparent", "corners", "band", "form"]
        let address = name == "certificate" ? secure + "/features" :
            base + (name == "auth" ? "/auth" : original.contains(pageName) ? "/phase-1.4/\(pageName).html" : "/features")
        guard let url = URL(string: address), let page = host.open(url, in: profile, activate: true) else {
            HostSpike.record("error", "failed to create page"); return
        }
        do {
            try await Task.sleep(for: .seconds(2))
            // Cert/auth intentionally stop before a successful navigation.
            if name == "auth" || name == "certificate" {
                try await Task.sleep(for: .seconds(5))
                HostSpike.record("prompt-observation", "url=\(page.url?.absoluteString ?? "nil") title=\(page.title) loading=\(page.isLoading)")
                HostSpike.record("review-required", "verify native prompt/interstitial and cancellation; survival alone is not a pass")
                return
            }
            let cdp = try await HostCDP.connect(port: defaults.integer(forKey: "RoomSpikeCDPPort"), pageURL: address)
            defer { cdp.close() }
            try await cdp.call("Page.enable")
            // A target can report its pending URL while its old document is
            // still active. Wait for the committed fixture before using DOM.
            let quotedAddress = String(decoding: try JSONSerialization.data(withJSONObject: address, options: .fragmentsAllowed), as: UTF8.self)
            var ready = false
            for _ in 0..<100 {
                if (try? await cdp.evaluate("location.href === \(quotedAddress) && document.readyState === 'complete'")) as? Bool == true {
                    ready = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard ready else { throw HostCDP.Failure("fixture did not finish loading") }
            switch name {
            case "popups":
                try await cdp.evaluate("document.querySelector('#blank').click(); true", userGesture: true)
                try await cdp.evaluate("document.querySelector('#open').click(); true", userGesture: true)
                try await cdp.evaluate("document.querySelector('#date').showPicker(); true", userGesture: true)
                HostSpike.record("popup-pages", host.pages.count)
            case "dialogs":
                for expression in ["alert('Room spike')", "confirm('Room spike')", "prompt('Room spike', 'value')"] {
                    HostSpike.record("dialog-result", try await cdp.evaluate(expression, userGesture: true))
                }
            case "keys":
                try await cdp.evaluate("document.querySelector('#t').focus(); true")
                try await cdp.call("Input.dispatchKeyEvent", ["type": "keyDown", "key": "a", "code": "KeyA", "text": "a"])
                try await cdp.call("Input.dispatchKeyEvent", ["type": "keyUp", "key": "a", "code": "KeyA"])
                HostSpike.record("page-keys", try await cdp.evaluate("JSON.stringify(window.__keys)"))
                HostSpike.record("review-required", "native reserved shortcuts and Colemak/Cmd routing need AppKit events")
            case "audio":
                try await cdp.evaluate("document.querySelector('#a').play().then(()=>true)", userGesture: true)
                // Audio-service startup can lag play()'s promise. Poll for
                // advancing playback rather than sampling at the 2 s loop edge.
                let playback = try await cdp.evaluate("new Promise(resolve=>{const start=performance.now();const timer=setInterval(()=>{if(a.currentTime>0.05||performance.now()-start>10000){clearInterval(timer);resolve({paused:a.paused,time:a.currentTime,ready:a.readyState,duration:a.duration,elapsed:performance.now()-start})}},100)})")
                HostSpike.record("audio", playback)
                try await cdp.evaluate("a.pause(); true")
                guard let state = playback as? [String: Any],
                      let time = state["time"] as? Double, time > 0.05 else {
                    throw HostCDP.Failure("audio playback clock did not advance")
                }
            case "scroll":
                HostSpike.record("scroll", try await cdp.evaluate("new Promise(resolve=>{let start=performance.now(), frames=0; function step(t){scrollBy(0,8);frames++;if(t-start<3000)requestAnimationFrame(step);else resolve({frames,ms:t-start,y:scrollY})}requestAnimationFrame(step)})"))
            case "transparent":
                try await cdp.call("Emulation.setDefaultBackgroundColorOverride", ["color": ["r": 0, "g": 0, "b": 0, "a": 0]])
                HostSpike.record("background", try await cdp.evaluate("getComputedStyle(document.body).backgroundColor"))
                HostSpike.record("review-required", "capture page and card composite externally")
            case "corners":
                HostSpike.record("background", try await cdp.evaluate("getComputedStyle(document.body).backgroundColor"))
                HostSpike.record("review-required", "verify clipping and hairline in external capture")
            case "band":
                for y in [8, 34] {
                    try await cdp.call("Input.dispatchMouseEvent", ["type": "mousePressed", "x": 200, "y": y, "button": "left", "clickCount": 1])
                    try await cdp.call("Input.dispatchMouseEvent", ["type": "mouseReleased", "x": 200, "y": y, "button": "left", "clickCount": 1])
                }
                HostSpike.record("clicks", try await cdp.evaluate("JSON.stringify(__clicks)"))
                HostSpike.record("review-required", "CDP bypasses native toolbar hit testing; repeat with native input")
            case "form":
                try await cdp.evaluate("for(const [k,v] of Object.entries({name:'Room Spike',email:'room@example.test',street:'1 Test Street',username:'room-spike',password:'spike-only'}))document.querySelector('[name='+k+']').value=v;document.querySelector('form').requestSubmit();true", userGesture: true)
                HostSpike.record("review-required", "save bubbles and subsequent autocomplete dropdown")
            case "extension":
                // Startup extension registration can finish after the first
                // page navigation. Reload after the worker has initialized.
                try await cdp.call("Page.reload")
                try await Task.sleep(for: .seconds(2))
                let marker = try await cdp.evaluate("document.documentElement.dataset.roomSpikeExtension || 'missing'")
                HostSpike.record("content-script", marker)
                guard marker as? String == "content-script-ran" else { throw HostCDP.Failure("extension content script did not run") }
                HostSpike.record("review-required", "extension worker, chrome.tabs, action popup and chrome://extensions")
            case "downloads":
                guard let output = defaults.string(forKey: "RoomSpikeOutput") else {
                    throw HostCDP.Failure("download evidence path missing")
                }
                let directory = URL(fileURLWithPath: output).deletingLastPathComponent()
                    .appendingPathComponent("downloads", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await cdp.call("Browser.setDownloadBehavior", [
                    "behavior": "allow", "downloadPath": directory.path, "eventsEnabled": true,
                ])
                try await cdp.evaluate("document.querySelector('#download').click(); true", userGesture: true)
                let file = directory.appendingPathComponent("roomcore-spike.txt")
                for _ in 0..<100 {
                    if FileManager.default.fileExists(atPath: file.path) { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                let data = try Data(contentsOf: file)
                guard data == Data("RoomCore download fixture\n".utf8) else {
                    throw HostCDP.Failure("download bytes differ: \(data.count)")
                }
                HostSpike.record("download-bytes", data.count)
                HostSpike.record("review-required", "CDP selected the destination; native chooser and cancellation still need review")
            case "permissions":
                try await cdp.evaluate("Notification.requestPermission(); navigator.geolocation.getCurrentPosition(()=>{},()=>{}); true", userGesture: true)
                HostSpike.record("review-required", "native permission prompt must complete/cancel; no capture devices requested")
            case "find", "zoom", "print":
                // Private spike entry point, deliberately absent from public
                // headers. A missing hook is a failure, never a silent pass.
                // Reset is correctly disabled at 100%; exercise it while
                // zoomed in and out, not after opposite steps cancel out.
                let commands = name == "find" ? [37000, 37001] : name == "zoom" ? [38001, 38002, 38003, 38002] : [35003]
                for command in commands {
                    try host.runSpikeCommand(command)
                    try await Task.sleep(for: .seconds(1))
                    if name == "zoom" { HostSpike.record("zoom-ratio", try await cdp.evaluate("devicePixelRatio")) }
                }
            case "fullscreen":
                try await cdp.evaluate("document.documentElement.requestFullscreen().then(()=>true)", userGesture: true)
                HostSpike.record("fullscreen", try await cdp.evaluate("!!document.fullscreenElement"))
                try await cdp.evaluate("document.exitFullscreen().then(()=>true)")
            default: break
            }
            try await Task.sleep(for: .seconds(3))
            HostSpike.record("drive-complete", name)
            HostSpike.record("page-state", "url=\(page.url?.absoluteString ?? "nil") title=\(page.title) closed=\(page.isClosed)")
        } catch {
            HostSpike.record("error", "\(name): \(error)")
        }
    }
}
