import AppKit

/// What a double-click on a titlebar does, from the user's setting
/// (System Settings ▸ Desktop & Dock ▸ "Double-click a window's title bar to").
/// The optional toolbar is a titlebar (`PageToolbarView`); the page is not
/// (B-32: the card's drag band went in 5.6b, and a double-click on the page
/// under the window's titlebar stays the page's, `RoomWindow.sendEvent`).
public enum TitlebarDoubleClick {
    public static func perform(in window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}
