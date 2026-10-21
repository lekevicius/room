#if DEBUG
import AppKit
import ApplicationServices
import Engine
import MediaPlayer
import Model
import Sidebar
import Tabs
import UIKitCore

/// Phase 4.6 spike `media` (`Room -RoomSpike media`; the tour's step `media`
/// through `scripts/media-check.sh`, which serves `research/spikes` on
/// :8776). The fixture is `phase-4.6/media.html` (two tone "tracks" with
/// metadata, a canvas artwork and action handlers that log into `#log`).
/// Sections (`-RoomSpikeOnly` picks): `engine` the controls through the
/// `WebContents` members with the page's log read back; `row` the footer's
/// media row with the fixture playing in a second space; `nowplaying` what
/// Chrome's system media controls put in `MPNowPlayingInfoCenter` and a
/// synthetic play/pause key; `pip` document picture-in-picture in the
/// floating panel and video picture-in-picture's overlay window; `backtotab`
/// both windows' back to tab (B-107, `BackToTabSpike.swift`).
extension SpikeRunner.Context {
    static var mediaBase: String { UserDefaults.standard.string(forKey: "RoomMediaFixtureBase") ?? "http://127.0.0.1:8776" }
    static var mediaPage: URL { URL(string: "\(mediaBase)/phase-4.6/media.html?quiet=1")! }

    func mediaChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        await activate()
        if runs("engine") { await mediaEngine() }
        if runs("row") { await mediaRow() }
        if runs("nowplaying") { await mediaNowPlaying() }
        if runs("pip") { await mediaPictureInPicture() }
        if runs("backtotab") { await mediaBackToTab() }
    }

    func mediaLog(_ page: any WebContents) async -> String {
        await js(page, "document.querySelector('#log').textContent")
    }

    func mediaState(_ page: any WebContents) async -> String {
        await js(page, "document.querySelector('#state').textContent")
    }

    func describe(_ session: MediaSessionInfo?) -> String {
        guard let session else { return "none" }
        let actions = session.actions.map(\.rawValue).sorted().joined(separator: ",")
        let position = session.position.map { String(format: "%.1f/%.1f@%.1f", $0.position, $0.duration, $0.rate) } ?? "none"
        return "title=\"\(session.title)\" artist=\"\(session.artist)\" state=\(session.playbackState) actions=[\(actions)] "
            + "position=\(position) artwork_url=\(session.artworkURL?.scheme ?? "none") artwork_png=\(session.artwork?.count ?? 0)B"
    }

    /// Opens the fixture and starts track 0 with a click; the session playing.
    func startMediaFixture(select: Bool = true) async -> (any WebContents)? {
        guard let page = await open(Self.mediaPage, select: select) else {
            SpikeRunner.record("error", "media: the fixture did not open")
            return nil
        }
        try? await Task.sleep(for: .milliseconds(300))
        await click(page, "#play")
        let playing = await waitUntil(8) { page.mediaSession?.playbackState == .playing }
        if !playing { SpikeRunner.record("error", "media: no playing session (log \(await mediaLog(page)))") }
        return page
    }

    /// Calls `control` and waits for the page's log to end with `mark` and `settled` to hold.
    func mediaControl(_ page: any WebContents, _ name: String, mark: String, _ control: () -> Void,
                      settled: @escaping () -> Bool = { true }) async {
        let start = ContinuousClock.now
        control()
        var logged = false
        var waited = ContinuousClock.now
        while ms(since: start) < 5000 {
            let log = await mediaLog(page)
            if log.hasSuffix(mark) || log.hasSuffix("\(mark)\"") { logged = true; waited = ContinuousClock.now; break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let logMs = Double((waited - start).components.attoseconds) / 1e15 + Double((waited - start).components.seconds) * 1000
        let ok = await waitUntil(5) { settled() }
        SpikeRunner.record("engine_\(name)", String(format: "page_logged=%@ in %.0f ms settled=%@ session: %@ page: %@", "\(logged)",
                                                      logged ? logMs : -1, "\(ok)", describe(page.mediaSession), await mediaState(page)))
    }

    // MARK: engine: the members over content::MediaSession

    func mediaEngine() async {
        guard let page = await startMediaFixture() else { return }
        _ = await waitUntil(5) { page.mediaSession?.artwork != nil && page.mediaSession?.position != nil }
        SpikeRunner.record("engine_session", describe(page.mediaSession) + " audible=\(page.isAudible)")
        await mediaControl(page, "pause", mark: "pause", { page.mediaPause() }) { page.mediaSession?.playbackState == .paused }
        await mediaControl(page, "play", mark: "play", { page.mediaPlay() }) { page.mediaSession?.playbackState == .playing }
        await mediaControl(page, "next", mark: "nexttrack", { page.mediaNextTrack() }) { page.mediaSession?.title == "Room Tone B" }
        await mediaControl(page, "previous", mark: "previoustrack", { page.mediaPreviousTrack() }) { page.mediaSession?.title == "Room Tone A" }
        await mediaControl(page, "seek", mark: "seekto 12.0", { page.mediaSeek(to: 12) }) {
            (page.mediaSession?.position?.position ?? 0) >= 11.5
        }
        SpikeRunner.record("engine_log", await mediaLog(page))
        // Closed: a paused session elsewhere would be the next sections' media row.
        if let entry = tabs.entryID(for: page) { sidebar.close(entry) }
        _ = await waitUntil(3) { page.state == .closed }
    }

    /// Simplifies the spike's own timing line: the time until `condition` holds, or -1.
    func timeUntil(_ seconds: Double, _ condition: () -> Bool) async -> Double {
        let start = ContinuousClock.now
        return await waitUntil(seconds, condition) ? ms(since: start) : -1
    }

    func describeRow() -> String {
        guard let row = sidebar.mediaRowContent else { return "hidden" }
        let image = row.image.map { String(format: "%.0fx%.0f", $0.size.width, $0.size.height) } ?? "none"
        let frame = sidebar.mediaRowFrameInWindow.map { NSStringFromRect($0) } ?? "none"
        return "title=\"\(row.title)\" subtitle=\"\(row.subtitle)\" playing=\(row.isPlaying) next=\(row.canGoNext) image=\(image) frame=\(frame)"
    }

    func captureMedia(_ name: String, window target: NSWindow? = nil) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "phase-4.6-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let shot = target ?? window
        shot.displayIfNeeded()
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(shot, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    /// Waits for the page's log to end with `mark`; the time, or -1.
    func pageLogged(_ page: any WebContents, _ mark: String, within seconds: Double = 5) async -> Double {
        let start = ContinuousClock.now
        while ms(since: start) < seconds * 1000 {
            let log = await mediaLog(page)
            if log.hasSuffix(mark) || log.hasSuffix("\(mark)\"") { return ms(since: start) }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return -1
    }

    // MARK: row: the footer's media row with the fixture in a second space

    func mediaRow() async {
        let first = sidebar.activeSpaceID
        SpikeRunner.record("row_initial", describeRow())
        guard let profile = store.space(first)?.profileID, let two = try? store.createSpace(name: "Media", profile: profile) else {
            return SpikeRunner.record("error", "media: no second space")
        }
        sidebar.showSpace(two.id, animated: false)
        try? await Task.sleep(for: .milliseconds(400))
        guard let page = await startMediaFixture(), let entry = tabs.entryID(for: page) else { return }
        _ = await waitUntil(5) { page.mediaSession?.artwork != nil }
        SpikeRunner.record("row_while_selected", describeRow())
        // Back to the first space: the media entry is not on screen.
        let start = ContinuousClock.now
        sidebar.showSpace(first, animated: false)
        let shown = await waitUntil(5) { self.sidebar.mediaRowContent?.entry == entry }
        SpikeRunner.record("row_shown", String(format: "%@ in %.0f ms (space switch → row) %@", "\(shown)", ms(since: start), describeRow()))
        try? await Task.sleep(for: .milliseconds(300))
        captureMedia("media-row")
        // Pause and play from the row.
        sidebar.debugPressMediaRow(.playPause)
        let paused = await pageLogged(page, "pause")
        let rowPaused = await timeUntil(5) { self.sidebar.mediaRowContent?.isPlaying == false }
        SpikeRunner.record("row_pause", String(format: "page_logged %.0f ms, row shows Play %.0f ms; session %@; page %@", paused, rowPaused,
                                               "\(page.mediaSession?.playbackState ?? .none)", await mediaState(page)))
        sidebar.debugPressMediaRow(.playPause)
        let played = await pageLogged(page, "play")
        let rowPlaying = await timeUntil(5) { self.sidebar.mediaRowContent?.isPlaying == true }
        SpikeRunner.record("row_play", String(format: "page_logged %.0f ms, row shows Pause %.0f ms; session %@; page %@", played, rowPlaying,
                                              "\(page.mediaSession?.playbackState ?? .none)", await mediaState(page)))
        sidebar.debugPressMediaRow(.next)
        let next = await pageLogged(page, "nexttrack")
        let retitled = await timeUntil(5) { self.sidebar.mediaRowContent?.title == "Room Tone B" }
        SpikeRunner.record("row_next", String(format: "page_logged %.0f ms, row retitled %.0f ms; %@", next, retitled, describeRow()))
        // A click on the row selects its entry (its space shows); the row hides.
        let clickStart = ContinuousClock.now
        sidebar.debugPressMediaRow(.select)
        let selected = await waitUntil(5) { self.tabs.currentEntryID == entry && self.sidebar.activeSpaceID == two.id }
        let hidden = await waitUntil(5) { self.sidebar.mediaRowContent == nil }
        SpikeRunner.record("row_select", String(format: "selected=%@ space=%@ row_hidden=%@ in %.0f ms", "\(selected)",
                                                sidebar.activeSpaceID == two.id ? "Media" : "other", "\(hidden)", ms(since: clickStart)))
        // Back to the first space, then ×: hidden until a session starts again.
        sidebar.showSpace(first, animated: false)
        let back = await waitUntil(5) { self.sidebar.mediaRowContent?.entry == entry }
        sidebar.debugPressMediaRow(.dismiss)
        let dismissed = await waitUntil(3) { self.sidebar.mediaRowContent == nil }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("row_dismiss", "back=\(back) hidden=\(dismissed) still_hidden_after_500ms=\(sidebar.mediaRowContent == nil) "
            + "page_playing=\(page.mediaSession?.playbackState == .playing)")
        page.mediaPause()
        _ = await waitUntil(3) { page.mediaSession?.playbackState == .paused }
        // A person's pause, then play a moment later.
        try? await Task.sleep(for: .milliseconds(300))
        page.mediaPlay()
        let again = await timeUntil(5) { self.sidebar.mediaRowContent?.entry == entry }
        SpikeRunner.record("row_next_session", String(format: "row back after the page played again: %.0f ms", again))
        SpikeRunner.record("row_log", await mediaLog(page))
        sidebar.close(entry)
        _ = await waitUntil(3) { page.state == .closed }
    }

    // MARK: nowplaying: Chrome's system media controls and a media key

    func nowPlayingInfo() -> String {
        let center = MPNowPlayingInfoCenter.default()
        guard let info = center.nowPlayingInfo else { return "nowPlayingInfo=nil state=\(center.playbackState.rawValue)" }
        let title = info[MPMediaItemPropertyTitle] as? String ?? "nil"
        let artist = info[MPMediaItemPropertyArtist] as? String ?? "nil"
        let duration = info[MPMediaItemPropertyPlaybackDuration] as? Double
        let elapsed = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
        let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double
        let art = info[MPMediaItemPropertyArtwork] != nil
        return "title=\"\(title)\" artist=\"\(artist)\" duration=\(duration.map { String(format: "%.1f", $0) } ?? "nil") "
            + "elapsed=\(elapsed.map { String(format: "%.1f", $0) } ?? "nil") rate=\(rate.map { String(format: "%.1f", $0) } ?? "nil") "
            + "artwork=\(art) state=\(center.playbackState.rawValue) keys=\(info.keys.count)"
    }

    func mediaNowPlaying() async {
        guard let page = await startMediaFixture() else { return }
        _ = await waitUntil(5) { MPNowPlayingInfoCenter.default().nowPlayingInfo != nil }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("nowplaying_playing", nowPlayingInfo())
        let commands = MPRemoteCommandCenter.shared()
        SpikeRunner.record("nowplaying_commands", "play=\(commands.playCommand.isEnabled) pause=\(commands.pauseCommand.isEnabled) "
            + "toggle=\(commands.togglePlayPauseCommand.isEnabled) next=\(commands.nextTrackCommand.isEnabled) "
            + "previous=\(commands.previousTrackCommand.isEnabled) seek=\(commands.changePlaybackPositionCommand.isEnabled)")
        // A synthetic play/pause key (NX_KEYTYPE_PLAY) posted to the HID tap: macOS routes it to the Now Playing app.
        let trusted = AXIsProcessTrusted()
        let posted = postMediaKey(16)
        let keyMs = await pageLogged(page, "pause", within: 3)
        SpikeRunner.record("nowplaying_media_key", String(format: "posted=%@ ax_trusted=%@ page_paused=%@ (%.0f ms) session %@ now_playing %@",
                                                          "\(posted)", "\(trusted)", "\(keyMs >= 0)", keyMs,
                                                          "\(page.mediaSession?.playbackState ?? .none)", nowPlayingInfo()))
        if keyMs >= 0 {
            page.mediaPlay()
            _ = await waitUntil(3) { page.mediaSession?.playbackState == .playing }
        }
        // MediaRemote's command (what Control Center's button sends) to the Now Playing app.
        let sent = sendMediaRemoteCommand(1) // kMRPause
        let remoteMs = await pageLogged(page, "pause", within: 3)
        SpikeRunner.record("nowplaying_mediaremote_pause", String(format: "sent=%@ page_paused=%@ (%.0f ms) now_playing %@", sent,
                                                                  "\(remoteMs >= 0)", remoteMs, nowPlayingInfo()))
        page.mediaPause()
        _ = await waitUntil(3) { page.mediaSession?.playbackState == .paused }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("nowplaying_paused", nowPlayingInfo())
        SpikeRunner.record("nowplaying_log", await mediaLog(page))
        if let entry = tabs.entryID(for: page) { sidebar.close(entry) }
        _ = await waitUntil(3) { page.state == .closed }
    }

    /// Posts a media key down and up (`NSEvent.otherEvent`, subtype 8) to the HID event tap.
    func postMediaKey(_ key: Int) -> Bool {
        var posted = false
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 8,
                                                 data1: (key << 16) | (state << 8), data2: -1),
                  let cgEvent = event.cgEvent else { return false }
            cgEvent.post(tap: .cghidEventTap)
            posted = true
        }
        return posted
    }

    /// `MRMediaRemoteSendCommand` (MediaRemote.framework, private) if it loads.
    func sendMediaRemoteCommand(_ command: Int32) -> String {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else { return "no framework" }
        guard let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return "no symbol" }
        typealias Send = @convention(c) (Int32, CFDictionary?) -> Bool
        return "\(unsafeBitCast(symbol, to: Send.self)(command, nil))"
    }

    // MARK: pip: document PiP in the floating panel, video PiP's overlay window

    func blockerNames(_ page: any WebContents) -> String {
        let names = page.discardBlockers.names
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    /// A visible window above the normal level that is not Room's (Chrome's video overlay).
    func overlayWindow() -> NSWindow? {
        NSApp.windows.first { candidate in
            candidate.isVisible && candidate !== window && !(candidate is NSPanel) && candidate.level != .normal
        }
    }

    func windowList() -> String {
        NSApp.windows.filter(\.isVisible).map { window in
            "\(window.className)\(window.level == .floating ? "(floating)" : "") \(NSStringFromRect(window.frame))"
        }.joined(separator: "; ")
    }

    func mediaPictureInPicture() async {
        guard let app = AppDelegate.current, let panels = app.pictureInPicture else {
            return SpikeRunner.record("error", "media: no picture-in-picture panels")
        }
        let url = URL(string: "\(Self.mediaBase)/phase-3.7/pip.html")!
        guard let page = await open(url), let entry = tabs.entryID(for: page) else { return SpikeRunner.record("error", "media: pip.html did not open") }
        try? await Task.sleep(for: .milliseconds(500))
        let card = window.convertToScreen(controller.rootView.convert(controller.rootView.currentLayout.card, to: nil))
        // 1. Document PiP: the panel, then the page's own window.close().
        var start = ContinuousClock.now
        var shownMs = -1.0
        panels.debugOnShow = { [weak self] _ in if let self { shownMs = self.ms(since: start) } }
        let todayBefore = store.today(space: sidebar.activeSpaceID).count
        await click(page, "#doc-pip")
        let opened = await waitUntil(8) { !panels.items.isEmpty }
        if let item = panels.items.first {
            _ = await waitUntil(5) { item.contents.url != nil && !item.contents.isLoading }
            let panel = item.panel
            let content = panel.contentRect(forFrameRect: panel.frame)
            SpikeRunner.record("docpip_panel", String(format: "opened=%@ in %.0f ms requested=%@ content=%.0fx%.0f frame=%@ level_floating=%@ "
                                                      + "nonactivating=%@ hides_on_deactivate=%@ all_spaces=%@ card_top_right=(%.0f,%.0f) "
                                                      + "panel_top_right=(%.0f,%.0f) today_tabs %d→%d page=%@",
                                                      "\(opened)", shownMs, item.requestedSize.map { NSStringFromSize($0) } ?? "none",
                                                      content.width, content.height, NSStringFromRect(panel.frame), "\(panel.level == .floating)",
                                                      "\(panel.styleMask.contains(.nonactivatingPanel))", "\(panel.hidesOnDeactivate)",
                                                      "\(panel.collectionBehavior.contains(.canJoinAllSpaces))", card.maxX, card.maxY,
                                                      panel.frame.maxX, panel.frame.maxY, todayBefore,
                                                      store.today(space: sidebar.activeSpaceID).count, await js(item.contents, "document.body.textContent")))
            SpikeRunner.record("docpip_opener", "log=\(await js(page, "document.querySelector('#log').textContent")) "
                + "opener_alive=\(page.state) blockers=\(blockerNames(page))")
            try? await Task.sleep(for: .milliseconds(1500))
            captureMedia("docpip-panel", window: panel)
            captureMedia("docpip-opener-window")
            // What the engine painted (independent of the window server's capture).
            if let image = try? await item.contents.captureViewport() {
                let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory")
                if let directory, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: directory).appending(path: "phase-4.6-docpip-viewport.png"))
                }
                SpikeRunner.record("docpip_viewport", String(format: "%.0fx%.0f visible_in_panel=%@ hidden=%@", image.size.width, image.size.height,
                                                             "\(item.contents.nativeView.window === panel)", "\(item.contents.nativeView.isHiddenOrHasHiddenAncestor)"))
            } else {
                SpikeRunner.record("docpip_viewport", "no capture")
            }
            start = ContinuousClock.now
            var closedMs = -1.0
            panels.debugOnClose = { [weak self] _ in if let self { closedMs = self.ms(since: start) } }
            _ = await js(item.contents, "window.close(), 'closing'")
            let closed = await waitUntil(5) { panels.items.isEmpty && !panel.isVisible }
            SpikeRunner.record("docpip_page_close", String(format: "panel_closed=%@ in %.0f ms opener_alive=%@ entry_kept=%@", "\(closed)", closedMs,
                                                           "\(page.state)", "\(store.entry(entry) != nil)"))
        } else {
            SpikeRunner.record("docpip_panel", "opened=false log=\(await js(page, "document.querySelector('#log').textContent")) "
                + "today_tabs \(todayBefore)→\(store.today(space: sidebar.activeSpaceID).count)")
        }
        // 2. The user closes the panel: the page closes, the opener stays.
        try? await Task.sleep(for: .milliseconds(500))
        await click(page, "#doc-pip")
        if await waitUntil(8, { !panels.items.isEmpty }), let item = panels.items.first {
            let pipPage = item.contents
            item.panel.performClose(nil)
            let gone = await waitUntil(5) { pipPage.state == .closed }
            SpikeRunner.record("docpip_user_close", "page_closed=\(gone) panels=\(panels.items.count) opener_alive=\(page.state)")
        } else {
            SpikeRunner.record("docpip_user_close", "no panel")
        }
        // 3. The opener closes (its entry closed): the panel goes with it.
        try? await Task.sleep(for: .milliseconds(500))
        await click(page, "#doc-pip")
        if await waitUntil(8, { !panels.items.isEmpty }), let item = panels.items.first {
            let panel = item.panel
            start = ContinuousClock.now
            sidebar.close(entry)
            let gone = await waitUntil(5) { panels.items.isEmpty && !panel.isVisible }
            SpikeRunner.record("docpip_opener_close", String(format: "panel_closed=%@ in %.0f ms", "\(gone)", ms(since: start)))
        } else {
            SpikeRunner.record("docpip_opener_close", "no panel")
        }
        // 4. Video PiP: Chrome's overlay window in the process.
        guard let video = await open(url) else { return }
        try? await Task.sleep(for: .milliseconds(500))
        let before = windowList()
        await click(video, "#video-pip")
        let entered = await waitUntil(5) { self.overlayWindow() != nil }
        try? await Task.sleep(for: .milliseconds(500))
        let overlay = overlayWindow()
        let videoLog = await js(video, "document.querySelector('#log').textContent")
        let overlayText: String = overlay.map { "\($0.className) \(NSStringFromRect($0.frame)) level=\($0.level.rawValue)" } ?? "none"
        SpikeRunner.record("videopip_window", "overlay=\(entered) log=\(videoLog) window=\(overlayText) blockers=\(blockerNames(video))")
        SpikeRunner.record("videopip_windows", "before: \(before) | during: \(windowList())")
        if let overlay { captureMedia("video-pip-overlay", window: overlay) }
        _ = await js(video, "document.exitPictureInPicture().then(() => 'left', e => 'error ' + e.name)")
        let left = await waitUntil(5) { !NSApp.windows.contains { $0.isVisible && $0 === overlay } }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("videopip_exit", "overlay_gone=\(left) log=\(await js(video, "document.querySelector('#log').textContent")) after: \(windowList())")
    }
}
#endif
