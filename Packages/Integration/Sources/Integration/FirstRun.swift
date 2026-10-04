import Model

/// The first-run card's state (ROADMAP 2.8 task 4), all of it in `Settings`:
/// it shows until the user finishes it, once; Settings ▸ General brings it
/// back. Each choice is written as it is made, so closing Room halfway keeps
/// what was chosen; the opt-ins stay off unless switched on here or in
/// Settings ▸ Privacy. The search engine is the field the palette reads.
public final class FirstRun {
    private let read: () -> Settings
    private let write: ((inout Settings) -> Void) -> Void

    /// `read` and `write` reach the settings store (`SettingsStore.settings` / `update`):
    /// a SwiftUI view reading through them observes the store.
    public init(read: @escaping () -> Settings, write: @escaping ((inout Settings) -> Void) -> Void) {
        self.read = read
        self.write = write
    }

    public var isShowing: Bool { !read().firstRunDone }

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

    /// Done: the card goes and does not come back by itself.
    public func finish() { write { $0.firstRunDone = true } }

    /// Settings ▸ General ▸ Show Welcome Card: the card again, with the current choices.
    public func showAgain() { write { $0.firstRunDone = false } }
}
