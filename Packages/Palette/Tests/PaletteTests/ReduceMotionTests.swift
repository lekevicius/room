import Design
import Testing
@testable import Palette

@Suite("Reduce Motion: the palette (spec §I.1)")
struct PaletteReduceMotionTests {
    /// Spec §I.1: the palette opens with a scale and a fade; under Reduce
    /// Motion the scale goes and both the open and the close are fades.
    @Test("Toggling the injected preference turns the palette's open and close into fades")
    func variants() {
        defer { Motion.preferences = .system }
        Motion.preferences = .fixed(reduceMotion: false)
        for motion in PaletteMotion.allCases { #expect(motion.variant == .full, "\(motion)") }
        Motion.preferences = .fixed(reduceMotion: true)
        for motion in PaletteMotion.allCases { #expect(motion.variant == .crossfade, "\(motion)") }
    }
}
