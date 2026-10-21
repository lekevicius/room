import Design
import Testing
@testable import Tabs

@Suite("Reduce Motion: the ⌃Tab switcher (spec §I.1)")
struct TabsReduceMotionTests {
    /// Spec §I.1: the switcher's appearance is a fade, and stays one under Reduce Motion.
    @Test("Toggling the injected preference keeps the switcher's fade")
    func variants() {
        defer { Motion.preferences = .system }
        Motion.preferences = .fixed(reduceMotion: false)
        #expect(TabsMotion.switcherAppear.variant == .full)
        Motion.preferences = .fixed(reduceMotion: true)
        #expect(TabsMotion.switcherAppear.variant == .crossfade)
    }
}
