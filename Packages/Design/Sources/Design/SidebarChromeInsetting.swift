import AppKit

/// A sidebar body that fills the whole sidebar and starts its own content `chromeTop` points down, so
/// its lists scroll under the header (5.13, the user: "enough to simply let content go under our toolbars").
@MainActor
public protocol SidebarChromeInsetting: AnyObject {
    var chromeTop: CGFloat { get set }
}
