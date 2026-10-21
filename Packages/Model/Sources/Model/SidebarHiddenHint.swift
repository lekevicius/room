import Foundation

/// The "Sidebar hidden" toast (spec §E): shown once per state, the first
/// time a splitter drag snaps the sidebar closed, naming the key that brings
/// it back as Settings ▸ Shortcuts has it now (5.6b).
public enum SidebarHiddenHint {
    /// True the first time only: the state remembers that it was shown.
    public static func take(_ settings: inout Settings) -> Bool {
        guard !settings.sidebarHiddenHintShown else { return false }
        settings.sidebarHiddenHintShown = true
        return true
    }

    /// The toast's line with View ▸ Show Sidebar's key (`nil`: the user removed it).
    public static func message(toggleKey: String?) -> String {
        guard let toggleKey, !toggleKey.isEmpty else { return "Sidebar hidden — View ▸ Show Sidebar brings it back" }
        return "Sidebar hidden — press \(toggleKey) to bring it back"
    }
}
