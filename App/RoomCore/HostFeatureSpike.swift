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
                try await Task.sleep(for: .seconds(2))
                HostSpike.record("audio", try await cdp.evaluate("({paused:a.paused,time:a.currentTime})"))
                try await cdp.evaluate("a.pause(); true")
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
                HostSpike.record("content-script", try await cdp.evaluate("document.documentElement.dataset.roomSpikeExtension || 'missing'"))
                HostSpike.record("review-required", "extension worker, chrome.tabs, action popup and chrome://extensions")
            case "downloads":
                try await cdp.evaluate("document.querySelector('#download').click(); true", userGesture: true)
            case "permissions":
                try await cdp.evaluate("Notification.requestPermission(); navigator.geolocation.getCurrentPosition(()=>{},()=>{}); true", userGesture: true)
                HostSpike.record("review-required", "native permission prompt must complete/cancel; no capture devices requested")
            case "find", "zoom", "print":
                // Private spike entry point, deliberately absent from public
                // headers. A missing hook is a failure, never a silent pass.
                let commands = name == "find" ? [37000, 37001] : name == "zoom" ? [38001, 38003, 38002] : [35003]
                for command in commands {
                    try host.runSpikeCommand(command)
                    try await Task.sleep(for: .seconds(1))
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
