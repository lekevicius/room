import AppKit
import RoomCore

/// Feature drives use the original Phase 1.4 pages over loopback HTTP.
/// A completed drive is not automatically a functional pass: observations,
/// stub hits, crash logs, and (where needed) native UI must be reviewed.
@MainActor
enum HostFeatureSpike {
    static let names = ["popups", "dialogs", "keys", "audio", "scroll", "transparent",
                        "corners", "band", "form", "extension", "downloads", "permissions",
                        "auth", "certificate", "find", "zoom", "print", "fullscreen", "widevine", "fedcm", "renderer-crash"]

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
        let address = base + (name == "auth" ? "/auth" : original.contains(pageName) ? "/phase-1.4/\(pageName).html" : "/features")
        guard let url = URL(string: address), let page = host.open(url, in: profile, activate: true) else {
            HostSpike.record("error", "failed to create page"); return
        }
        do {
            try await Task.sleep(for: .seconds(2))
            if name == "auth" {
                for action in ["auth-cancel", "auth-supply"] {
                    var handled = false
                    for _ in 0..<100 {
                        if try host.runSpikeAction(action) == 1 { handled = true; break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard handled else { throw HostCDP.Failure("no HTTP auth handler for \(action)") }
                    for _ in 0..<100 {
                        if !page.isLoading { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    HostSpike.record(action, "loading=\(page.isLoading)")
                    if action == "auth-cancel" { page.loadURL(url) }
                }
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
                try await cdp.evaluate("window.onbeforeunload=()=>'';true", userGesture: true)
                _ = try await cdp.call("Page.navigate", ["url": base + "/features"])
                let beforeUnload = cdp.events.contains {
                    ($0["method"] as? String) == "Page.javascriptDialogOpening" &&
                    ($0["params"] as? [String: Any])?["type"] as? String == "beforeunload"
                }
                let stayed = try await cdp.evaluate("location.href === \(quotedAddress)") as? Bool == true
                HostSpike.record("beforeunload-cancelled", beforeUnload && stayed)
                guard beforeUnload && stayed else { throw HostCDP.Failure("beforeunload cancellation did not preserve the page") }
                try await cdp.evaluate("window.onbeforeunload=null;true")
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
                let webAudio = try await cdp.evaluate("""
                (async()=>{const ctx=new AudioContext();await ctx.resume();const osc=ctx.createOscillator();const gain=ctx.createGain();gain.gain.value=0;osc.connect(gain).connect(ctx.destination);const start=ctx.currentTime;osc.start();await new Promise(r=>setTimeout(r,300));const result={state:ctx.state,elapsed:ctx.currentTime-start,sampleRate:ctx.sampleRate};osc.stop();await ctx.close();return {...result,closed:ctx.state==='closed'};})()
                """, userGesture: true)
                HostSpike.record("web-audio", webAudio)
                guard let audio = webAudio as? [String: Any], audio["state"] as? String == "running",
                      let elapsed = audio["elapsed"] as? Double, elapsed > 0.05,
                      audio["closed"] as? Bool == true else { throw HostCDP.Failure("Web Audio did not run and close") }
                HostSpike.record("review-required", "muted oscillator verifies Web Audio lifecycle; audible output remains a listening check")
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
                let worker = try await HostCDP.connect(port: defaults.integer(forKey: "RoomSpikeCDPPort"), pageURL: "/worker.js", targetType: "service_worker", suffixMatch: true)
                defer { worker.close() }
                let operations = try await worker.evaluate("""
                (async()=>{
                    const before=await chrome.tabs.query({});
                    const tab=await chrome.tabs.create({url:'about:blank',active:false});
                    const afterCreate=await chrome.tabs.query({});
                    await chrome.tabs.remove(tab.id);
                    const afterRemove=await chrome.tabs.query({});
                    const window=await chrome.windows.create({url:'about:blank',type:'popup',focused:false});
                    await chrome.windows.remove(window.id);
                    let action;
                    try { await chrome.windows.update(before[0].windowId,{focused:true}); await chrome.action.openPopup({windowId:before[0].windowId}); action='opened'; }
                    catch(e) { action=String(e); }
                    return {before:before.length,afterCreate:afterCreate.length,afterRemove:afterRemove.length,windowCreated:!!window.id,action};
                })()
                """, userGesture: true)
                HostSpike.record("extension-operations", operations)
                HostSpike.record("activation", host.activationSnapshot())
                guard let result = operations as? [String: Any],
                      let before = result["before"] as? Int,
                      result["afterCreate"] as? Int == before + 1,
                      result["afterRemove"] as? Int == before,
                      result["windowCreated"] as? Bool == true else {
                    throw HostCDP.Failure("extension tabs/windows lifecycle did not complete")
                }
                HostSpike.record("review-required", "native extension action UI and popup ownership remain; action API outcome recorded")
            case "certificate":
                let navigation = try await cdp.call("Page.navigate", ["url": secure + "/features"])
                HostSpike.record("certificate-error", navigation["errorText"] ?? "missing")
                guard (navigation["errorText"] as? String)?.contains("ERR_CERT_AUTHORITY_INVALID") == true else {
                    throw HostCDP.Failure("self-signed certificate was not rejected")
                }
                var interstitial = false
                for _ in 0..<100 {
                    interstitial = (try? await cdp.evaluate("!!document.querySelector('#primary-button')")) as? Bool == true
                    if interstitial { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard interstitial else { throw HostCDP.Failure("certificate interstitial button absent") }
                HostSpike.record("certificate-title", try await cdp.evaluate("document.title"))
                try await cdp.evaluate("document.querySelector('#primary-button').click();true", userGesture: true)
                var returned = false
                for _ in 0..<100 {
                    returned = (try? await cdp.evaluate("location.href === \(quotedAddress) && document.readyState === 'complete'")) as? Bool == true
                    if returned { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("certificate-left", returned)
                guard returned else { throw HostCDP.Failure("certificate leave did not restore safe page") }
                HostSpike.record("review-required", "real interstitial leave callback exercised; native pointer/focus remains")
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
                try await cdp.evaluate("const a=document.createElement('a');a.href='/download-slow';a.download='roomcore-slow.bin';document.body.append(a);a.click();true", userGesture: true)
                var downloadGUID: String?
                for _ in 0..<100 {
                    _ = try await cdp.evaluate("true")
                    if let event = cdp.events.last(where: {
                        ($0["method"] as? String)?.hasSuffix("downloadWillBegin") == true &&
                        (($0["params"] as? [String: Any])?["url"] as? String)?.hasSuffix("/download-slow") == true
                    }) {
                        downloadGUID = (event["params"] as? [String: Any])?["guid"] as? String
                        break
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard let downloadGUID else { throw HostCDP.Failure("slow download did not begin") }
                try await cdp.call("Browser.cancelDownload", ["guid": downloadGUID])
                var cancelled = false
                for _ in 0..<100 {
                    _ = try await cdp.evaluate("true")
                    cancelled = cdp.events.contains {
                        guard let params = $0["params"] as? [String: Any] else { return false }
                        return ($0["method"] as? String)?.hasSuffix("downloadProgress") == true &&
                            params["guid"] as? String == downloadGUID && params["state"] as? String == "canceled"
                    }
                    if cancelled { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("download-cancelled", cancelled)
                guard cancelled else { throw HostCDP.Failure("download cancellation did not complete") }
                guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("roomcore-slow.bin").path) else {
                    throw HostCDP.Failure("cancelled file was finalized")
                }
                HostSpike.record("review-required", "CDP selected the destination; native chooser and cancellation still need review")
            case "permissions":
                try await cdp.evaluate("window.permissionResults={}; Notification.requestPermission().then(x=>permissionResults.notification=x); navigator.geolocation.getCurrentPosition(()=>permissionResults.geo=0,e=>permissionResults.geo=e.code); true", userGesture: true)
                var outcomes: [String: Any] = [:]
                var denials = 0
                for _ in 0..<100 {
                    if try host.runSpikeAction("deny-permission") == 1 { denials += 1 }
                    outcomes = try await cdp.evaluate("permissionResults") as? [String: Any] ?? [:]
                    if outcomes.count == 2 { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("permission-denials", denials)
                HostSpike.record("permission-results", outcomes)
                guard outcomes["notification"] as? String == "denied", outcomes["geo"] as? Int == 1 else {
                    throw HostCDP.Failure("permission callbacks did not deny both requests")
                }
                HostSpike.record("review-required", "native anchor/focus still needs review; callbacks used Chrome's real Deny path")
            case "auth":
                let body = try await cdp.evaluate("document.querySelector('h1').textContent")
                HostSpike.record("auth-body", body)
                guard body as? String == "RoomCore features" else { throw HostCDP.Failure("authenticated fixture did not load") }
                HostSpike.record("review-required", "credential/cancel callbacks exercised; native field focus remains")
            case "find", "zoom", "print":
                // Private spike entry point, deliberately absent from public
                // headers. A missing hook is a failure, never a silent pass.
                // Reset is correctly disabled at 100%; exercise it while
                // zoomed in and out, not after opposite steps cancel out.
                let commands = name == "find" ? [37000] : name == "zoom" ? [38001, 38002, 38003, 38002] : [35003]
                for command in commands {
                    try host.runSpikeCommand(command)
                    try await Task.sleep(for: .seconds(1))
                    if name == "zoom" { HostSpike.record("zoom-ratio", try await cdp.evaluate("devicePixelRatio")) }
                }
                if name == "find" {
                    guard try host.runSpikeAction("find-row") == 1 else { throw HostCDP.Failure("find did not start") }
                    HostSpike.record("find-dom-rows", try await cdp.evaluate("document.querySelectorAll('.row').length"))
                    var count = -1
                    var observed: [Int] = []
                    for _ in 0..<100 {
                        count = try host.runSpikeAction("find-count")
                        if observed.last != count { observed.append(count) }
                        if count == 400 { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    HostSpike.record("find-count-updates", observed)
                    HostSpike.record("find-matches", count)
                    guard count == 400 else { throw HostCDP.Failure("expected 400 Row matches") }
                    try host.runSpikeCommand(37001)
                    try host.runSpikeCommand(37003)
                }
            case "fedcm":
                for action in ["fedcm-passive", "fedcm-active"] {
                    let shown = try host.runSpikeAction(action)
                    HostSpike.record(action, shown)
                    guard shown == 1 else { throw HostCDP.Failure("FedCM dialog did not show") }
                    try await Task.sleep(for: .seconds(1))
                    _ = try host.runSpikeAction("fedcm-close")
                }
                HostSpike.record("review-required", "real Chrome failure bubble and loading modal shown and destroyed; identity exchange and native focus remain unverified")
            case "widevine":
                cdp.commandTimeoutSeconds = 75
                // Auxiliary audit: request the real web API on a fresh profile.
                let key = defaults.string(forKey: "RoomSpikeKeySystem") ?? "com.widevine.alpha"
                let quotedKey = String(decoding: try JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed), as: UTF8.self)
                HostSpike.record("key-system", key)
                HostSpike.record("key-system-request-time", Date().timeIntervalSince1970)
                let access = try await cdp.evaluate("navigator.requestMediaKeySystemAccess(\(quotedKey),[{initDataTypes:['cenc'],videoCapabilities:[{contentType:'video/mp4; codecs=\"avc1.42E01E\"'}]}]).then(async x=>({supported:true,keySystem:x.keySystem,keysCreated:!!(await x.createMediaKeys())})).catch(e=>({supported:false,name:e.name,message:e.message}))")
                HostSpike.record("widevine-access", access)
                HostSpike.record("key-system-result-time", Date().timeIntervalSince1970)
                if key == "com.widevine.alpha" {
                    guard let result = access as? [String: Any], result["keysCreated"] as? Bool == true else {
                        throw HostCDP.Failure("Widevine MediaKeys creation failed")
                    }
                }
                try await Task.sleep(for: .seconds(20))
                HostSpike.record("review-required", "inspect NetLog for demand-only CDM update; MediaKeys creation is not licensed playback")
            case "renderer-crash":
                do { _ = try await cdp.call("Page.crash") }
                catch { HostSpike.record("renderer-crash-command", String(describing: error)) }
                var crashed = false
                for _ in 0..<100 {
                    if try host.runSpikeAction("renderer-status") == 3 { crashed = true; break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("renderer-crash-contained", crashed)
                guard crashed else { throw HostCDP.Failure("renderer crash did not leave a live host and Cocoa fallback") }
                cdp.close()
                page.reload()
                try await Task.sleep(for: .seconds(1))
                let recovered = try await HostCDP.connect(port: defaults.integer(forKey: "RoomSpikeCDPPort"), pageURL: address)
                defer { recovered.close() }
                var reloaded = false
                for _ in 0..<100 {
                    if (try? await recovered.evaluate("location.href === \(quotedAddress) && document.readyState === 'complete'")) as? Bool == true,
                       try host.runSpikeAction("renderer-status") == 0 {
                        reloaded = true; break
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                HostSpike.record("renderer-reloaded", reloaded)
                guard reloaded else { throw HostCDP.Failure("renderer reload did not remove the crash fallback") }
                HostSpike.record("review-required", "Chapter 3 needs crash status, accessible retry UI and reporting controls")
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
