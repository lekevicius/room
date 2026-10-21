import Design
import Testing
@testable import Sidebar

@Suite("Reduce Motion (spec §I.1)")
struct ReduceMotionTests {
    /// Spec §I.1: every animation honours Reduce Motion with a crossfade in
    /// place of movement. What each sidebar animation becomes (5.1a): the
    /// movement-only ones end at once, the slides and the fades crossfade.
    static let expected: [SidebarMotion: MotionVariant] = [
        .pillFollow: .instant, .rows: .instant, .spaceSlide: .crossfade, .spaceIndicator: .instant, .spaceIconReorder: .instant,
        .spaceName: .crossfade, .essentialsReflow: .instant, .essentialFade: .crossfade, .refusedDrop: .crossfade,
        .changedDot: .crossfade, .resetIconSwap: .crossfade, .resetCrossfade: .crossfade, .renamePulse: .instant,
        .clearSlide: .crossfade, .clearReveal: .crossfade, .scrollToSelected: .instant, .loadingRing: .instant, .audioIndicator: .instant, .folderPreview: .instant,
    ]

    @Test("Toggling the injected preference switches every sidebar animation to its crossfade or instant variant")
    func variants() {
        defer { Motion.preferences = .system }
        Motion.preferences = .fixed(reduceMotion: false)
        for motion in SidebarMotion.allCases {
            #expect(motion.variant == .full, "\(motion)")
            #expect(motion.animates, "\(motion)")
        }
        Motion.preferences = .fixed(reduceMotion: true)
        #expect(Motion.reduceMotion)
        for motion in SidebarMotion.allCases {
            #expect(motion.variant == Self.expected[motion], "\(motion)")
            #expect(motion.variant != .full, "\(motion) has no reduced variant")
            #expect(motion.animates == (motion.variant == .crossfade), "\(motion)")
        }
        #expect(Set(Self.expected.keys) == Set(SidebarMotion.allCases))
    }
}
