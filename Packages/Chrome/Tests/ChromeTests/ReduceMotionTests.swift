import Design
import Testing
@testable import Chrome

@Suite("Reduce Motion: the page chrome (spec §I.1, §F)")
struct ChromeReduceMotionTests {
    /// Spec §I.1: every animation honours Reduce Motion with a crossfade in
    /// place of movement (5.1b): toasts fade in and out, the bounce is a fade;
    /// the pop, the flight, the ring's growth and spin and the popovers' own
    /// animation end at once; a dialog's fade stays a fade.
    static let expected: [ChromeMotion: MotionVariant] = [
        .toastIn: .crossfade, .toastPop: .instant, .toastOut: .crossfade, .downloadFlyIn: .instant, .downloadBounce: .crossfade,
        .downloadProgress: .instant, .downloadSpinner: .instant, .popover: .instant, .promptFade: .crossfade,
    ]

    @Test("Toggling the injected preference switches every chrome animation to its crossfade or instant variant")
    func variants() {
        defer { Motion.preferences = .system }
        Motion.preferences = .fixed(reduceMotion: false)
        for motion in ChromeMotion.allCases {
            #expect(motion.variant == .full, "\(motion)")
            #expect(motion.animates, "\(motion)")
        }
        Motion.preferences = .fixed(reduceMotion: true)
        for motion in ChromeMotion.allCases {
            #expect(motion.variant == Self.expected[motion], "\(motion)")
            #expect(motion.animates == (motion.variant == .crossfade), "\(motion)")
        }
        #expect(Set(Self.expected.keys) == Set(ChromeMotion.allCases))
    }
}
