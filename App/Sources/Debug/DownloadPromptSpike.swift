#if DEBUG
import AppKit
import Engine
import Model

/// `downloadprompt` (B-106, 5.0a): Settings ▸ Downloads ▸ "Ask where to save
/// each download" on, as the user's by-hand step 34 did it: the setting
/// through the store (as the Settings toggle writes it), nothing set on the
/// profile by the spike, then the step's URL opened as a new tab (typed) and
/// as a link click, each answered by cancelling the panel. Records whether a
/// save panel showed, as a sheet, and what the list and the folder hold.
/// Needs the 2.6 server on :8766 (scripts/test-servers.sh).
extension SpikeRunner.Context {
    func downloadPromptChecks() async {
        guard let app = AppDelegate.current, let store = app.store, let list = app.downloads?.list else {
            return SpikeRunner.record("error", "downloadprompt: no store or downloads")
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "room-downloadprompt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store.settings.update {
            $0.askWhereToSave = true
            $0.downloadDirectory = folder.path
        }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("downloadprompt_setting", "askWhereToSave=\(store.settings.settings.askWhereToSave)")
        func panel() async -> NSSavePanel? {
            _ = await waitUntil(8) { NSApp.windows.contains { $0 is NSSavePanel && $0.isVisible } }
            return NSApp.windows.compactMap { $0 as? NSSavePanel }.first { $0.isVisible }
        }
        func answer(_ shown: NSSavePanel) async {
            if let parent = shown.sheetParent { parent.endSheet(shown, returnCode: .cancel) } else { shown.cancel(nil) }
            _ = await waitUntil(5) { !shown.isVisible }
        }
        // 1. Typed: a new tab on the download URL (the by-hand step).
        let typed = URL(string: "http://127.0.0.1:8766/download?name=asked.bin&size=200000")!
        let rowsBefore = list.rows.count
        _ = session.newPage(typed, hidden: false, select: true)
        if let shown = await panel() {
            SpikeRunner.record("downloadprompt_typed", "panel=true sheet=\(shown.sheetParent != nil) proposed=\(shown.nameFieldStringValue)")
            await answer(shown)
        } else {
            SpikeRunner.record("downloadprompt_typed", "panel=false rows \(rowsBefore) → \(list.rows.count) "
                + "files=\((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])")
        }
        try? await Task.sleep(for: .milliseconds(800))
        // 2. A link click on a loaded page.
        let page = await open(URL(string: "http://127.0.0.1:8766/downloads.html")!)
        if let page {
            _ = await PageDriver.evaluateWithGesture(page, "const a=document.createElement('a');a.href='http://127.0.0.1:8766/download?name=clicked.bin&size=2000';"
                + "document.body.append(a);a.click();0", "download clicked")
            if let shown = await panel() {
                SpikeRunner.record("downloadprompt_link", "panel=true sheet=\(shown.sheetParent != nil) proposed=\(shown.nameFieldStringValue)")
                await answer(shown)
            } else {
                SpikeRunner.record("downloadprompt_link", "panel=false files=\((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])")
            }
        }
        try? await Task.sleep(for: .milliseconds(800))
        SpikeRunner.record("downloadprompt_after", "listed=\(list.rows.map(\.item.suggestedFilename)) "
            + "files=\((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])")
        store.settings.update {
            $0.askWhereToSave = false
            $0.downloadDirectory = nil
        }
    }
}
#endif
