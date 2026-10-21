import Design
import Testing
@testable import Card

@Suite("Reduce Motion: Peek and the split view (spec §I.1)")
struct CardReduceMotionTests {
    /// Spec §I.1: Peek's open from the click becomes a fade under Reduce
    /// Motion (and its close and the pane header stay fades); the drop
    /// preview's slide ends at once; the split's layout never animates.
    static let expected: [CardMotion: MotionVariant] = [
        .peekOpen: .crossfade, .peekClose: .crossfade, .paneHeader: .crossfade, .dropPreview: .instant, .splitLayout: .instant,
    ]

    @Test("Toggling the injected preference switches Peek and the split to their crossfade or instant variants")
    func variants() {
        defer { Motion.preferences = .system }
        Motion.preferences = .fixed(reduceMotion: false)
        for motion in CardMotion.allCases where motion != .splitLayout { #expect(motion.variant == .full, "\(motion)") }
        #expect(CardMotion.splitLayout.variant == .instant)
        Motion.preferences = .fixed(reduceMotion: true)
        for motion in CardMotion.allCases { #expect(motion.variant == Self.expected[motion], "\(motion)") }
        #expect(Set(Self.expected.keys) == Set(CardMotion.allCases))
    }
}
