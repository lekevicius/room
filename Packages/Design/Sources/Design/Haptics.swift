import AppKit

/// The trackpad's haptic ticks (ROADMAP 5.5 task 6): only on alignment
/// points, a place the dragged thing snaps or lands on (the sidebar's
/// insertion line, a drop target row, the Essentials slot, a space icon's
/// reorder slot, the split divider's equal point); never on hover. Every tick
/// goes through here, so the audit is one `grep` and spikes can count them.
public enum Haptics {
    /// Alignment ticks asked for since launch (spikes read it; a Mac with no
    /// Force Touch trackpad counts them all the same).
    public private(set) static var alignmentCount = 0

    /// A drag reached a new alignment point.
    public static func alignment() {
        alignmentCount += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
