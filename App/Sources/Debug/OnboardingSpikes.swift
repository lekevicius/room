#if DEBUG
import AppKit
import Design
import Integration
import Model

/// 5.7b (B-121): onboarding in the review sheet's matrix (`-RoomSpike matrix
/// -RoomSpikeOnly onboarding`): each step in its window, and the import
/// sheet over it. The window's checks are `appintegration2`'s `firstrun`.
extension SpikeRunner.Context {
    var onboardingNotes: [String] {
        [String(format: "Onboarding (5.7b, B-121): a window of its own, %.0f × %.0f pt, padding %.0f, the step's symbol %.0f pt, "
                + "dots %.0f pt, swatches %.0f pt; Skip Setup at every step, Back, Continue / Done (Return). "
                + "Steps: welcome, import (the import sheet over the window), default browser, theme (the shown space's colour, "
                + "the appearance), search and the two opt-ins.",
                OnboardingMetrics.width, OnboardingMetrics.height, OnboardingMetrics.padding, OnboardingMetrics.symbolSize,
                OnboardingMetrics.dotSize, OnboardingMetrics.swatchSize)]
    }

    func onboardingStates() -> [MatrixState] {
        guard let app = AppDelegate.current else { return [] }
        func open(at step: Onboarding.Step) async {
            app.presentOnboarding()
            _ = await waitUntil(3) { app.onboardingWindow?.window?.isVisible == true }
            guard let onboarding = app.onboardingWindow?.onboarding else { return }
            while onboarding.step != step, onboarding.ending == nil { onboarding.next() }
            try? await Task.sleep(for: .milliseconds(500))
        }
        func shoot() async -> CGImage? {
            guard let target = app.onboardingWindow?.window else { return nil }
            if matrixActive { target.makeKeyAndOrderFront(nil) } else { window.makeKeyAndOrderFront(nil) }
            try? await Task.sleep(for: .milliseconds(400))
            return await matrixShot(in: target, scale: 0.5)
        }
        let settingsBefore = sidebar.store.settings.settings
        func close() async {
            app.closeImportSheet()
            app.onboardingWindow?.onboarding.skip()
            _ = await waitUntil(2) { app.onboardingWindow == nil }
            // The matrix leaves the state as it found it.
            sidebar.store.settings.update { $0 = settingsBefore }
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
        }
        var states = Onboarding.Step.allCases.map { step in
            MatrixState(label: step.title, setup: { await open(at: step) }, shoot: { await shoot() }, teardown: { await close() })
        }
        states.insert(MatrixState(label: "Import: the sheet over onboarding", setup: {
            await open(at: .importData)
            app.onboardingWindow?.model.openImport()
            _ = await self.waitUntil(3) { app.importSheet != nil }
            try? await Task.sleep(for: .milliseconds(600))
        }, shoot: { await shoot() }, teardown: { await close() }), at: 2)
        return states
    }
}
#endif
