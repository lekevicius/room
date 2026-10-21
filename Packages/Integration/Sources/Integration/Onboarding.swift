import Model
import Observation

/// Onboarding (5.7b, B-121), in place of Chapter 2's first-run card: a short
/// sequence in a window of its own: welcome, import from another browser (the
/// import sheet), the default browser, a theme for the first space and the
/// window's appearance, then the search engine and the two opt-ins. Shown on
/// a first launch (`showsAtLaunch`) and from Help ▸ Welcome to Room…; every
/// step can be skipped (Continue without a choice) and the whole of it left
/// with Skip Setup or the window's close button.
///
/// The rules: the state is `Settings.firstRunDone` (the card's field, so a
/// state that finished the card never sees onboarding); a choice is written
/// as it is made (closing halfway keeps it); skipping writes `firstRunDone`
/// and nothing else, so the opt-ins stay off and the engine stays as it was;
/// shown again from the Help menu it starts at the welcome with the current
/// choices and leaves `firstRunDone` alone until it ends.
@Observable
public final class Onboarding {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, importData, defaultBrowser, theme, search

        public var title: String {
            switch self {
            case .welcome: "Welcome to Room"
            case .importData: "Bring your bookmarks"
            case .defaultBrowser: "Your default browser"
            case .theme: "Make it yours"
            case .search: "Search and privacy"
            }
        }
    }

    /// How it ended: finished at the last step, or skipped (Skip Setup, the close button).
    public enum Ending: Equatable, Sendable {
        case finished
        case skipped(at: Step)
    }

    @ObservationIgnored private let read: () -> Settings
    @ObservationIgnored private let write: ((inout Settings) -> Void) -> Void

    public private(set) var step: Step = .welcome
    /// Set once it ended (the window closes on it).
    public private(set) var ending: Ending?

    /// `read` and `write` reach the settings store (`SettingsStore.settings` / `update`).
    public init(read: @escaping () -> Settings, write: @escaping ((inout Settings) -> Void) -> Void) {
        self.read = read
        self.write = write
    }

    /// A first launch: a state that never finished or skipped it (nor the card before it).
    public static func showsAtLaunch(_ settings: Settings) -> Bool { !settings.firstRunDone }

    public var settings: Settings { read() }

    public var isFirst: Bool { step == Step.allCases.first }
    public var isLast: Bool { step == Step.allCases.last }

    /// Continue: the next step (skipping this one when nothing was chosen); at the last, finished.
    public func next() {
        guard ending == nil else { return }
        if let following = Step(rawValue: step.rawValue + 1) {
            step = following
        } else {
            end(.finished)
        }
    }

    public func back() {
        guard ending == nil, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Skip Setup or the close button, at any step.
    public func skip() {
        guard ending == nil else { return }
        end(.skipped(at: step))
    }

    /// Help ▸ Welcome to Room… while it shows, or after it ended: from the welcome again.
    public func restart() {
        ending = nil
        step = .welcome
    }

    private func end(_ how: Ending) {
        ending = how
        write { $0.firstRunDone = true }
    }

    // MARK: Choices (written as they are made)

    public var searchEngine: String {
        get { read().searchEngine }
        set { write { $0.searchEngine = newValue } }
    }

    public var crashReports: Bool {
        get { read().crashReports }
        set { write { $0.crashReports = newValue } }
    }

    public var automaticUpdateChecks: Bool {
        get { read().automaticUpdateChecks }
        set { write { $0.automaticUpdateChecks = newValue } }
    }

    public var appearance: AppearanceSetting {
        get { read().appearance }
        set { write { $0.appearance = newValue } }
    }
}
