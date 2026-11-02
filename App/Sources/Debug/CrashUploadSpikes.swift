#if DEBUG
import AppKit
import Engine
import Model

/// Phase 6.3 spike `crashupload` (`scripts/crash-upload-check.sh`): the crash report opt-in end to end. The
/// app runs with `-RoomCrashDSN` pointing at a local `tools/crash-collector/collector.py`; the spike sets
/// Settings ▸ Privacy ▸ Send crash reports to `-RoomCrashPhase` (`on` or `off`), lets the opt-in services
/// apply it, then kills a renderer with `chrome://crash` (Crashpad writes its minidump) and waits for the
/// handler. The script counts what reached the collector and what stayed in the engine's `Crashpad/`.
extension SpikeRunner.Context {
    func crashUploadChecks() async {
        guard let app = AppDelegate.current, let settings = app.store?.settings else { return SpikeRunner.record("error", "no store") }
        let on = UserDefaults.standard.string(forKey: "RoomCrashPhase") == "on"
        settings.update { $0.searchSuggestions = false; $0.crashReports = on }
        let applied = await waitUntil(5) { app.engine.crashUploadsEnabled == on }
        SpikeRunner.record("crash_consent", "phase=\(on ? "on" : "off") setting=\(settings.settings.crashReports) "
            + "engine_uploads=\(app.engine.crashUploadsEnabled) applied=\(applied) reporting=\(app.optIns?.isReportingCrashes ?? false) "
            + "dsn=\(AppDelegate.crashDSN.isEmpty ? "none" : "set")")
        guard let page = await open(URL(string: "http://127.0.0.1:8766/status.html?crash")!) else { return SpikeRunner.record("error", "no page") }
        page.load(URL(string: "chrome://crash")!)
        let gone = await waitUntil(10) { app.promptPresenter?.crashView != nil }
        SpikeRunner.record("crash_renderer", "crashed_page_shown=\(gone)")
        // The handler writes the dump, then (consent given) posts it from its upload thread.
        try? await Task.sleep(for: .seconds(15))
        SpikeRunner.record("crash_waited", "15 s")
    }
}
#endif
