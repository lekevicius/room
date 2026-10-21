import Design
import Testing
@testable import UIKitCore

@Suite("Reduce Motion: the window (spec §I.1, §E)")
struct WindowReduceMotionTests {
    /// Spec §I.1: the hidden sidebar's slide becomes a crossfade under Reduce
    /// Motion; the traffic lights, the tint and the inactive fade stay fades.
    @Test("Toggling the injected preference turns the reveal's slide into a crossfade")
    func variants() {
        defer { Motion.preferences = .system }
        Motion.preferences = .fixed(reduceMotion: false)
        for motion in WindowMotion.allCases { #expect(motion.variant == .full, "\(motion)") }
        Motion.preferences = .fixed(reduceMotion: true)
        for motion in WindowMotion.allCases { #expect(motion.variant == .crossfade, "\(motion)") }
    }
}
