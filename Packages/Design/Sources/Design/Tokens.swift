import AppKit

/// Spacing scale (points). Everything in the chrome snaps to these.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
}

/// Corner radii (points). All rounded chrome uses `.continuous` corner curves.
public enum Radius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 12
}

/// Sidebar geometry (feature spec §E).
public enum SidebarMetrics {
    public static let defaultWidth: CGFloat = 240
    public static let minWidth: CGFloat = 180
    public static let maxWidth: CGFloat = 500
    /// Dragging the splitter below this width snaps the sidebar closed.
    public static let snapCloseWidth: CGFloat = 120
    /// Hit area of the splitter, centred on the sidebar/card boundary.
    public static let splitterHitWidth: CGFloat = 8
    /// Height of the header row that sits beside the traffic lights.
    public static let headerHeight: CGFloat = 52
    /// Gap between the zoom button and the first header element.
    public static let headerLeadingGap: CGFloat = Spacing.m
    /// Inset from the sidebar edges for header elements when no traffic lights are beside them.
    public static let edgeInset: CGFloat = Spacing.l
    /// Saturation and opacity applied to the sidebar content while the window is inactive (spec §I.12).
    public static let inactiveSaturation: CGFloat = 0.8
    public static let inactiveContentAlpha: CGFloat = 0.6
}

/// The inset page card (PLAN §2.4).
public enum CardMetrics {
    /// Gap between the card and the window edge on the top, trailing and bottom sides.
    /// Measured from Dia's window (6pt); the ROADMAP's first guess was 8.
    public static let inset: CGFloat = 6
    /// Gap on the sidebar side while the sidebar is open (the card butts against it).
    public static let sidebarSideInset: CGFloat = 0
    /// Continuous corner; fitted to Dia's card (its curve reaches the fill
    /// ~3pt along the diagonal, 12pt reaches it at ~3.75pt). ROADMAP guessed 12.
    public static let cornerRadius: CGFloat = Radius.medium
    public static let borderWidth: CGFloat = 1
    public static let shadowRadius: CGFloat = 4
    public static let shadowOffset = CGSize(width: 0, height: -1)
    public static let shadowOpacityLight: Float = 0.15
    public static let shadowOpacityDark: Float = 0.35
}

/// Type styles. SF Pro through the system font so vibrancy and Dynamic Type-ish scaling behave.
public enum Typography {
    /// Sidebar rows, address field.
    public static var row: NSFont { .systemFont(ofSize: 13, weight: .regular) }
    /// Space title in the sidebar header.
    public static var spaceTitle: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
    /// Sublabels, footer labels, badges.
    public static var secondary: NSFont { .systemFont(ofSize: 11, weight: .regular) }
}

/// Window and overlay materials.
public enum Materials {
    /// The window-wide material behind the sidebar and around the card (Dia's neutral look).
    public static let window: NSVisualEffectView.Material = .sidebar
    public static let windowBlending: NSVisualEffectView.BlendingMode = .behindWindow
    /// Opacity range of the space tint gradient over the window material.
    public static let tintOpacityRange: ClosedRange<CGFloat> = 0.10...0.25
    /// Default tint opacity (top of the gradient; the bottom fades to the lower bound).
    public static let tintOpacity: CGFloat = 0.18
}

/// Animation timing. Durations in seconds.
public enum Motion {
    /// Palette open, hover fades.
    public static let fast: TimeInterval = 0.12
    /// Row insert/remove, hover-reveal dwell, keep-open grace.
    public static let standard: TimeInterval = 0.15
    /// Space switch slide, tint crossfade, sidebar reveal.
    public static let medium: TimeInterval = 0.25
    /// Peek open, selection pill.
    public static let slow: TimeInterval = 0.35

    /// A spring described like SwiftUI's `Spring(duration:bounce:)`.
    public struct Spring: Sendable, Equatable {
        public let duration: TimeInterval
        public let bounce: Double

        public init(duration: TimeInterval, bounce: Double) {
            self.duration = duration
            self.bounce = bounce
        }

        /// A Core Animation spring for `keyPath` with these parameters.
        public func animation(keyPath: String) -> CASpringAnimation {
            let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            animation.keyPath = keyPath
            animation.duration = animation.settlingDuration
            return animation
        }
    }

    /// Selection pill moving between rows (spec §I.1).
    public static let pill = Spring(duration: 0.35, bounce: 0.15)
    /// Toast in, download-button bounce (spec §F).
    public static let toast = Spring(duration: 0.5, bounce: 0.2)
    /// Layout changes without overshoot (sidebar open/close, splitter snap).
    public static let smooth = Spring(duration: 0.25, bounce: 0)
}
