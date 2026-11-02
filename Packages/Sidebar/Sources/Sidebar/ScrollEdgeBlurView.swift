import AppKit
import CoreImage
import Design

/// The band behind the sidebar's fixed chrome that the lists scroll under (5.13, the user: "enough to simply
/// let content go under our toolbars", Mail's header for the look): rows passing under it blur, with a hard
/// edge and no tint, so over the sidebar's own background it is invisible. AppKit draws its scroll edge
/// effect only under a window's split view items, toolbar and titlebar accessories (the 5.13 experiment);
/// this is the public route, the view's background filters.
final class ScrollEdgeBlurView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        // The clamped blur has no edge of its own: the band clips it (unclipped it covered the whole list).
        layer?.masksToBounds = true
        // Clamped first, so the blur does not pull transparency in at the band's edges.
        let clamp = CIFilter(name: "CIAffineClamp")
        clamp?.setValue(NSAffineTransform(), forKey: kCIInputTransformKey)
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.setValue(SidebarMetrics.chromeBlurRadius, forKey: kCIInputRadiusKey)
        backgroundFilters = [clamp, blur].compactMap { $0 }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
