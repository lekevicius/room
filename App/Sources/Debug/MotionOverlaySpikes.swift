#if DEBUG
import AppKit
import Card
import Chrome
import Design
import Engine
import Model
import Sidebar
import Tabs
import UIKitCore

/// `motion` `-RoomSpikeOnly overlays` (5.1b): the motion harness on what lies
/// over the sidebar and the card. Each named animation runs through the code
/// its click, key or event runs: the palette's open and close, Peek's open
/// from a click and its close, the hidden sidebar's reveal and its traffic
/// lights (B-114), the ⌃Tab switcher, a toast's spring, its pop and its
/// leave, the download fly-in and the button's bounce, a split's creation and
/// layout change, and the controls' hover and press (B-111). The probe and
/// the table are 5.1a's (`MotionProbe`).
extension SpikeRunner.Context {
    func overlayMotion(probe: MotionProbe, fixture: MotionFixture, base: String) async -> [MotionProbe.Result] {
        var rows: [MotionProbe.Result] = []
        func run(_ name: String, minimum: TimeInterval = 0.1, _ trigger: () -> Void) async {
            let result = await probe.measure(name, minimum: minimum, trigger: trigger)
            SpikeRunner.record("motion_\(name)", result.line)
            rows.append(result)
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let app = AppDelegate.current, let session = app.activeWindow else {
            SpikeRunner.record("error", "motion overlays: no window session")
            return rows
        }
        let root = controller.rootView

        // The palette (spec §I.1: scale 0.96 → 1 and fade, 120 ms).
        if let palette = session.palette {
            // The window's first open, then a later one.
            await run("palette_open_first") { palette.toggleNew() }
            await run("palette_close") { palette.dismiss() }
            await run("palette_open") { palette.toggleNew() }
            await run("palette_close_again") { palette.dismiss() }
        }

        // Peek from a click in the page (spec §I.6: grows from the click, 350 ms), and its close.
        if let page = tabs.current, let peek = session.peek {
            let card = root.currentLayout.card
            session.lastClick = (CGPoint(x: card.minX + card.width * 0.3, y: card.minY + card.height * 0.4), ProcessInfo.processInfo.systemUptime)
            await run("peek_open") { tabs.openPeek(URL(string: "\(base)?peek")!, from: page) }
            SpikeRunner.record("peek_shown", "\(peek.isShown)")
            if let shown = tabs.shownPeek { await waitLoaded(shown, timeout: 10) }
            await run("peek_close") { tabs.closeShownPeek() }
        }

        // The ⌃Tab switcher (its fade; 5.1b).
        if let switcher = session.switcher {
            await run("switcher_show_first") { switcher.debugShow() }
            SpikeRunner.record("switcher_shown", "\(switcher.debugPanel != nil)")
            await run("switcher_end") { switcher.debugEnd() }
            await run("switcher_show") { switcher.debugShow() }
            await run("switcher_end_again") { switcher.debugEnd() }
        }

        // Toasts (spec §F: spring in, the same id pops, fade + scale out). SwiftUI animates
        // them in its own render loop, so the read-back may list none: the frames are the measure.
        if let toasts = session.toasts {
            let toast = Toast(id: "motion-toast", symbol: .copyURL, message: "Copied URL", duration: 30)
            await run("toast_in", minimum: Motion.toast.duration) { toasts.show(toast) }
            await run("toast_pop", minimum: Motion.toastPopUp + Motion.toastPopDown) { toasts.show(toast) }
            await run("toast_out", minimum: Motion.toastOut) { toasts.dismiss(id: toast.id) }
        }

        // Downloads (spec §F): the fly-in arc into the button, and the bounce.
        let button = sidebar.downloadsButton
        if button.window != nil {
            let card = root.currentLayout.card
            let image = NSWorkspace.shared.icon(for: .data)
            await run("download_fly_in") {
                DownloadFlyIn.run(image: image, from: NSPoint(x: card.midX, y: card.midY), to: button.target(in: root), in: root) {}
            }
            try? await Task.sleep(for: .milliseconds(600))
            await run("download_bounce") { button.bounce() }
        }

        // The controls (B-111): Reload's hover and press in the top bar, the downloads button's press.
        if let reload = Self.view(in: root, identifier: "nav-reload") as? HoverButton {
            await run("button_hover_in") { reload.feedback.setHovering(true) }
            await run("button_press_in") { reload.highlight(true) }
            await run("button_press_release") { reload.highlight(false) }
            await run("button_hover_out") { reload.feedback.setHovering(false) }
        } else {
            SpikeRunner.record("error", "motion: no Reload button")
        }
        await run("downloads_press_in") { button.feedback.setPressed(true) }
        await run("downloads_press_release") { button.feedback.setPressed(false) }

        // A split (spec §D): made from two Today tabs, its layout changed, undone.
        if fixture.today.count >= 4 {
            sidebar.select(fixture.today[2])
            if let page = tabs.contents(for: fixture.today[3]) { await waitLoaded(page, timeout: 10) } else if let entry = store.entry(fixture.today[3]) {
                tabs.loadInBackground(entry)
            }
            try? await Task.sleep(for: .milliseconds(600))
            await run("split_create") { sidebar.joinIntoSplit(fixture.today[3], with: fixture.today[2]) }
            await run("split_layout_vbox") { sidebar.setSplitLayout(.vbox) }
            await run("split_unsplit") { sidebar.unsplit() }
            sidebar.select(fixture.today[2])
            try? await Task.sleep(for: .milliseconds(400))
        }

        // The hidden sidebar (spec §E as amended by B-114): ⌘S hides it and the traffic lights
        // fade; the reveal slides it in with the traffic lights, and out.
        await run("sidebar_hide") { controller.isSidebarOpen = false }
        try? await Task.sleep(for: .milliseconds(300))
        await run("reveal_in") { controller.reveal.togglePin() }
        SpikeRunner.record("reveal_traffic_lights", "shown=\(controller.reveal.isShown) buttons visible=\(window.standardWindowButton(.closeButton)?.isHidden == false)")
        await run("reveal_out") { controller.reveal.togglePin() }
        // The dwell end to end: a pointer resting in the band to the overlay in place.
        post(.mouseMoved, at: CGPoint(x: 600, y: 300))
        try? await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        await run("reveal_dwell_slide", minimum: Timing.revealDwell + Motion.revealIn) { post(.mouseMoved, at: CGPoint(x: 1, y: 300)) }
        _ = await waitUntil(2) { controller.reveal.isShown && !root.isOverlayAnimating }
        SpikeRunner.record("reveal_band_to_in_place", String(format: "%.0f ms (dwell %d ms + slide %d ms; before B-114 150 + 250)", ms(since: start),
                                                                Int(Timing.revealDwell * 1000), Int(Motion.revealIn * 1000)))
        post(.mouseMoved, at: CGPoint(x: 700, y: 400))
        _ = await waitUntil(2) { !controller.reveal.isShown && !root.isOverlayAnimating }
        await run("sidebar_dock") { controller.isSidebarOpen = true }
        try? await Task.sleep(for: .milliseconds(300))
        return rows
    }

    /// The first view under `root` with this accessibility identifier.
    static func view(in root: NSView, identifier: String) -> NSView? {
        if root.accessibilityIdentifier() == identifier { return root }
        for subview in root.subviews {
            if let found = view(in: subview, identifier: identifier) { return found }
        }
        return nil
    }
}
#endif
