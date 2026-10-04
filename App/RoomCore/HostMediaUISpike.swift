import Foundation
import RoomCore

@MainActor
enum HostMediaUISpike {
    static func run(_ name: String, host: HostController, cdp: HostCDP, page: RoomWebContents, profile: RoomProfile) async throws {
        if name == "ui-video" {
            HostSpike.record("media-capabilities", try await cdp.evaluate("({selectAudioOutput:typeof navigator.mediaDevices.selectAudioOutput,setSinkId:typeof HTMLMediaElement.prototype.setSinkId,mediaSession:!!navigator.mediaSession,pictureInPicture:document.pictureInPictureEnabled,documentPictureInPicture:typeof documentPictureInPicture})"))
            guard try host.runSpikeAction("media-mute") == 1 else { throw HostCDP.Failure("could not mute fixture") }
            let result = try await cdp.evaluate("""
            (async()=>{const c=document.createElement('canvas');c.width=160;c.height=90;document.body.append(c);const x=c.getContext('2d');const stream=c.captureStream(15);let frame=0;const timer=setInterval(()=>{x.fillStyle=frame++%2?'#ff0000':'#0000ff';x.fillRect(0,0,160,90)},50);const chunks=[];const r=new MediaRecorder(stream,{mimeType:'video/webm;codecs=vp8'});r.ondataavailable=e=>chunks.push(e.data);const stopped=new Promise(resolve=>r.onstop=resolve);r.start();await new Promise(resolve=>setTimeout(resolve,700));r.stop();await stopped;clearInterval(timer);stream.getTracks().forEach(t=>t.stop());const blob=new Blob(chunks,{type:r.mimeType});const v=document.createElement('video');v.controls=true;v.src=URL.createObjectURL(blob);document.body.append(v);window.__roomVideo=v;await v.play();await new Promise(resolve=>setTimeout(resolve,250));const value={bytes:blob.size,time:v.currentTime,frames:v.getVideoPlaybackQuality().totalVideoFrames,paused:v.paused,mime:r.mimeType};v.pause();v.currentTime=0.1;return value;})()
            """, userGesture: true)
            HostSpike.record("generated-video", result)
            guard let video = result as? [String: Any], (video["frames"] as? Int ?? 0) > 0,
                  (video["time"] as? Double ?? 0) > 0 else { throw HostCDP.Failure("generated video did not play") }
            let pip = try await cdp.evaluate("""
            (async()=>{try{const w=await __roomVideo.requestPictureInPicture();const entered=document.pictureInPictureElement===__roomVideo;for(let i=0;i<20&&(w.width===0||w.height===0);i++)await new Promise(r=>setTimeout(r,100));const size={width:w.width,height:w.height};await document.exitPictureInPicture();return {entered,...size,closed:!document.pictureInPictureElement}}catch(e){return {error:e.name,message:e.message}}})()
            """, userGesture: true)
            HostSpike.record("video-pip", pip)
            guard let pipState = pip as? [String: Any], pipState["entered"] as? Bool == true,
                  pipState["closed"] as? Bool == true, (pipState["width"] as? Int ?? 0) > 0,
                  (pipState["height"] as? Int ?? 0) > 0 else { throw HostCDP.Failure("video PiP did not obtain geometry and close") }
            let audio = try await cdp.evaluate("""
            (async()=>{const c=new AudioContext();await c.resume();const o=c.createOscillator();o.connect(c.destination);o.start();window.__roomAudio={c,o};await new Promise(r=>setTimeout(r,400));return {state:c.state,time:c.currentTime,sampleRate:c.sampleRate}})()
            """, userGesture: true)
            HostSpike.record("muted-tab-audio", audio)
            HostSpike.record("media-engine-state", try host.runSpikeAction("media-state"))
            try await cdp.evaluate("__roomAudio.o.stop();__roomAudio.c.close().then(()=>true)")
            HostSpike.record("review-required", "Generated media only; native PiP focus, audible output, media keys and output-device selection are separate.")
            return
        }
        if name == "ui-document-pip" {
            let value = try await cdp.evaluate("""
            (async()=>{try{const w=await documentPictureInPicture.requestWindow({width:320,height:180});w.document.body.textContent='Room synthetic PiP';const result={opened:!w.closed,width:w.innerWidth,height:w.innerHeight};w.close();await new Promise(r=>setTimeout(r,200));return {...result,closed:w.closed}}catch(e){return {error:e.name,message:e.message}}})()
            """, userGesture: true)
            HostSpike.record("document-pip", value)
            guard let result = value as? [String: Any], result["opened"] as? Bool == true,
                  result["closed"] as? Bool == true else { throw HostCDP.Failure("document PiP did not open and close") }
            let before = Set(try await HostEmbeddedUISpike.targets().compactMap { $0["id"] as? String })
            try await cdp.evaluate("documentPictureInPicture.requestWindow({width:320,height:180}).then(w=>{w.document.body.textContent='Room owner close fixture';return true})", userGesture: true)
            let candidates = try await HostEmbeddedUISpike.targets().filter { target in
                guard let id = target["id"] as? String else { return false }
                return !before.contains(id) && target["type"] as? String == "page"
            }
            HostSpike.record("document-pip-new-targets", candidates.map { ["id": $0["id"] ?? "", "type": $0["type"] ?? "", "url": $0["url"] ?? ""] })
            var added = Set<String>()
            for target in candidates {
                guard let socket = target["webSocketDebuggerUrl"] as? String, let url = URL(string: socket),
                      let id = target["id"] as? String else { continue }
                let candidate = HostCDP(url: url)
                candidate.commandTimeoutSeconds = 3
                let matches = try? await candidate.evaluate("document.body?.textContent === 'Room owner close fixture'")
                candidate.close()
                if matches as? Bool == true { added.insert(id) }
            }
            HostSpike.record("document-pip-owned-targets", added.count)
            guard added.count == 1 else { throw HostCDP.Failure("could not identify owned PiP fixture target") }
            _ = host.open(URL(string: "about:blank")!, in: profile, activate: false)
            page.close()
            var gone = false
            for _ in 0..<50 {
                let live = Set(try await HostEmbeddedUISpike.targets().compactMap { $0["id"] as? String })
                if live.isDisjoint(with: added) { gone = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            HostSpike.record("document-pip-owner-close", "pageClosed=\(page.isClosed) targetGone=\(gone)")
            guard page.isClosed && gone else { throw HostCDP.Failure("document PiP survived its owner's closure") }
            return
        }
        let request: String
        switch name {
        case "ui-camera": request = "navigator.mediaDevices.getUserMedia({video:true})"
        case "ui-microphone": request = "navigator.mediaDevices.getUserMedia({audio:true})"
        case "ui-capture": request = "navigator.mediaDevices.getUserMedia({audio:true,video:true})"
        default: request = "navigator.mediaDevices.getDisplayMedia({video:true,audio:false})"
        }
        try await cdp.evaluate("""
        window.__roomCapture={pending:true};
        (\(request)).then(s=>{window.__roomStream=s;__roomCapture={pending:false,granted:true,tracks:s.getTracks().map(t=>({kind:t.kind,label:t.label,state:t.readyState}))}},e=>{__roomCapture={pending:false,granted:false,name:e.name,message:e.message}});true
        """, userGesture: true)
        var decisions = 0
        var state: [String: Any] = [:]
        for _ in 0..<100 {
            state = try await cdp.evaluate("__roomCapture") as? [String: Any] ?? [:]
            if state["pending"] as? Bool == false { break }
            if name == "ui-screen-share" {
                decisions += max(0, try host.runSpikeAction("ui-dialog-cancel"))
            } else {
                decisions += max(0, try host.runSpikeAction(name == "ui-capture" ? "accept-fake-capture" : "deny-permission"))
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        HostSpike.record("capture-decisions", decisions)
        HostSpike.record("capture-result", state)
        guard state["pending"] as? Bool == false else { throw HostCDP.Failure("capture UI did not settle within probe deadline") }
        if name == "ui-capture" {
            guard decisions == 1, state["granted"] as? Bool == true else { throw HostCDP.Failure("fake capture not accepted through Chrome permission callback") }
            var indicator = 0
            for _ in 0..<50 {
                indicator = try host.runSpikeAction("capture-state")
                if indicator == 3 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            HostSpike.record("capture-indicator-active", indicator)
            guard indicator == 3 else { throw HostCDP.Failure("missing audio/video capture indicator state") }
            guard try host.runSpikeAction("stop-fake-capture") == 1 else { throw HostCDP.Failure("capture stop unavailable") }
            for _ in 0..<50 {
                if try host.runSpikeAction("capture-state") == 0 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let stopped = try await cdp.evaluate("__roomStream.getTracks().every(t=>t.readyState==='ended')")
            HostSpike.record("capture-stopped", stopped)
            HostSpike.record("capture-indicator-after-stop", try host.runSpikeAction("capture-state"))
            guard stopped as? Bool == true, try host.runSpikeAction("capture-state") == 0 else { throw HostCDP.Failure("capture stop left active tracks or indicator") }
        } else {
            guard state["granted"] as? Bool == false else { throw HostCDP.Failure("denial fixture unexpectedly granted capture") }
        }
        HostSpike.record("review-required", "Synthetic media/deny only; native indicators, OS consent and hardware acceptance not established.")
    }
}
