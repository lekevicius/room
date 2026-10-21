#if DEBUG
import AppKit
import Engine
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
import RoomCore
#endif

/// `media -RoomSpikeOnly backtotab` (B-107, 5.0a): picture-in-picture's back
/// to tab selects and shows the opener's tab. The fixture `phase-3.7/pip.html`
/// opens video PiP (Chrome's overlay) and then another tab is selected: the
/// overlay's back-to-tab path (`ExitPictureInPictureViaWindowUi(kCloseWindowAndFocusOpener)`,
/// the dev framework's `pip-back-to-tab` spike action; the button's own click
/// is a computer-use check) must select the opener's entry again. Then
/// document PiP's panel: its Back to Tab button selects the opener's entry
/// and closes the panel. Needs research/spikes on :8776 (scripts/media-check.sh,
/// scripts/test-servers.sh).
extension SpikeRunner.Context {
    func mediaBackToTab() async {
        guard let app = AppDelegate.current, let panels = app.pictureInPicture else {
            return SpikeRunner.record("error", "backtotab: no picture-in-picture panels")
        }
        let url = URL(string: "\(Self.mediaBase)/phase-3.7/pip.html")!
        guard let opener = await open(url), let openerEntry = tabs.entryID(for: opener) else {
            return SpikeRunner.record("error", "backtotab: pip.html did not open")
        }
        let otherURL = URL(string: "\(Self.mediaBase)/phase-4.6/media.html?quiet=1")!
        // 1. Video PiP, another tab selected, back to tab.
        await click(opener, "#video-pip")
        let entered = await waitUntil(5) { self.overlayWindow() != nil }
        guard let other = await open(otherURL), let otherEntry = tabs.entryID(for: other) else {
            return SpikeRunner.record("error", "backtotab: the second tab did not open")
        }
        try? await Task.sleep(for: .milliseconds(500))
        let before = sidebar.selectedEntryID == otherEntry
        #if ROOM_ENGINE_ROOMCORE
        let browser = tabs.engineProfiles.values.compactMap { ($0 as? RoomCoreProfile)?.spikeBrowsers.first }.first
        let answer = SpikeRunner.spikeHook(browser, "roomSpikeAction:", "pip-back-to-tab" as NSString)?.intValue ?? -98
        #else
        let answer = -99
        #endif
        let selected = await waitUntil(5) { self.sidebar.selectedEntryID == openerEntry }
        let shown = selected && tabs.current === opener
        let gone = await waitUntil(5) { self.overlayWindow() == nil }
        SpikeRunner.record("backtotab_video", "overlay=\(entered) other_selected_before=\(before) hook=\(answer) "
            + "opener_selected=\(selected) opener_shown=\(shown) overlay_closed=\(gone)")
        // 2. Document PiP's panel button.
        await click(opener, "#doc-pip")
        guard await waitUntil(8, { !panels.items.isEmpty }), let item = panels.items.first else {
            return SpikeRunner.record("backtotab_document", "no panel")
        }
        sidebar.select(otherEntry)
        try? await Task.sleep(for: .milliseconds(500))
        let otherBefore = sidebar.selectedEntryID == otherEntry
        let button = item.panel.titlebarAccessoryViewControllers.first?.view as? NSButton
        if let button { button.performClick(nil) } else { panels.backToTab(item) }
        let docSelected = await waitUntil(5) { self.sidebar.selectedEntryID == openerEntry }
        let docClosed = await waitUntil(5) { panels.items.isEmpty && !item.panel.isVisible }
        SpikeRunner.record("backtotab_document", "button=\(button?.accessibilityLabel() ?? "none") other_selected_before=\(otherBefore) "
            + "opener_selected=\(docSelected) opener_shown=\(tabs.current === opener) panel_closed=\(docClosed) opener_alive=\(opener.state)")
    }
}
#endif
