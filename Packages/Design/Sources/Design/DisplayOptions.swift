import AppKit
import Synchronization

/// System Settings ▸ Accessibility ▸ Display (5.3b, ROADMAP 5.3 task 5): Increase
/// contrast, Reduce transparency and Differentiate without colour, as the
/// tokens read them. Injected like `Motion.preferences`: the system's switches
/// in production (`DisplayOptions.source = .system`, refreshed on
/// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`), fixed
/// values in tests and DEBUG's `-RoomIncreaseContrast`, `-RoomReduceTransparency`
/// and `-RoomDifferentiateWithoutColor` launch flags. Room never changes the
/// system's settings.
nonisolated public struct DisplayOptions: Sendable, Equatable, CustomStringConvertible {
    /// Hairlines and secondary text take their high-contrast tokens.
    public var increaseContrast: Bool
    /// Solid fills in place of the window's material and the overlays' glass.
    public var reduceTransparency: Bool
    /// The changed dot and the audible glyph carry a shape, not colour alone.
    public var differentiateWithoutColor: Bool

    public init(increaseContrast: Bool = false, reduceTransparency: Bool = false, differentiateWithoutColor: Bool = false) {
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    /// No option on: the design's tokens.
    public static let standard = DisplayOptions()

    public var description: String {
        let on = [increaseContrast ? "increaseContrast" : nil, reduceTransparency ? "reduceTransparency" : nil,
                  differentiateWithoutColor ? "differentiateWithoutColor" : nil].compactMap { $0 }
        return on.isEmpty ? "standard" : on.joined(separator: "+")
    }

    /// Where the values come from.
    public enum Source: Sendable, Equatable {
        /// The system's switches (`NSWorkspace.accessibilityDisplayShould…`).
        case system
        /// A fixed answer (tests, the DEBUG launch flags, the matrix's columns).
        case fixed(DisplayOptions)
    }

    /// The switches as the system has them now.
    @MainActor public static var system: DisplayOptions {
        let workspace = NSWorkspace.shared
        return DisplayOptions(increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                              reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                              differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor)
    }

    /// What the tokens read now. Not isolated: dynamic colours resolve it while they draw.
    public static var current: DisplayOptions { storage.withLock { $0 } }
    private static let storage = Mutex(DisplayOptions())

    /// The values' source; setting it applies it at once (`refresh`).
    @MainActor public static var source: Source = .system {
        didSet { refresh() }
    }

    /// Posted on the main thread when `current` changed (the views that hold resolved colours or
    /// shapes apply them again; `redraw` has already marked every window's views).
    public static let didChange = Notification.Name("RoomDisplayOptionsDidChange")

    /// Reads `source` into `current`; on a change posts `didChange` and redraws Room's windows.
    @MainActor public static func refresh() {
        let value: DisplayOptions = switch source {
        case .system: system
        case .fixed(let options): options
        }
        let changed = storage.withLock { stored -> Bool in
            guard stored != value else { return false }
            stored = value
            return true
        }
        guard changed else { return }
        NotificationCenter.default.post(name: didChange, object: nil)
        for window in NSApp?.windows ?? [] { redraw(window.contentView) }
    }

    private nonisolated(unsafe) static var observer: (any NSObjectProtocol)?

    /// Production: follow the system's switches, now and whenever one changes (a live toggle in
    /// System Settings reaches every window). Called once at launch.
    @MainActor public static func followSystem() {
        if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { refresh() }
            }
        }
        refresh()
    }

    /// Every view under `view` draws and lays out again (dynamic colours resolve anew), and the
    /// ones that keep resolved values apply them again.
    @MainActor static func redraw(_ view: NSView?) {
        guard let view else { return }
        view.needsDisplay = true
        view.needsLayout = true
        (view as? any DisplayOptionsObserving)?.displayOptionsDidChange()
        for subview in view.subviews { redraw(subview) }
    }
}

/// A view that holds colours or shapes resolved from `DisplayOptions` outside `draw`/`updateLayer`/`layout`.
@MainActor public protocol DisplayOptionsObserving: AnyObject {
    func displayOptionsDidChange()
}
