import Testing
@testable import Design

@Suite("Reduce Motion: the controls' feedback (spec §I.1, B-111)")
struct ControlReduceMotionTests {
    /// Spec §I.1: every animation honours Reduce Motion with a crossfade in
    /// place of movement. The press's scale becomes a dim; the hover stays a fade.
    @Test("Toggling the injected preference switches the press and the hover to their crossfades")
    func variants() {
        defer { Motion.preferences = .system }
        Motion.preferences = .fixed(reduceMotion: false)
        for motion in ControlMotion.allCases { #expect(motion.variant == .full, "\(motion)") }
        Motion.preferences = .fixed(reduceMotion: true)
        #expect(ControlMotion.press.variant == .crossfade)
        #expect(ControlMotion.hoverFade.variant == .crossfade)
    }
}
