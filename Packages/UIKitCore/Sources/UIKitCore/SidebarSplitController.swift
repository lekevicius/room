import AppKit
import Design

/// The experiment (branch experiment/split-sidebar, the user: "we might not merge this if it feels
/// hacky"): AppKit draws its scroll edge effect (the blur behind fixed chrome) only under toolbar items,
/// titlebar accessories and split item accessories, and only when an `NSSplitViewController` is the
/// window's content controller with the sidebar as its sidebar item (5.13's spike). So the window's
/// content is this controller: the sidebar view in its sidebar item, the rest of the window (card,
/// palette, toasts) in its content item. The sidebar's chrome stays Room's own views; two transparent
/// accessories that take no clicks tell AppKit how far the chrome reaches at the top and the bottom,
/// and the space lists run the sidebar's whole height under it.
public final class SidebarSplitController: NSSplitViewController {
    public let sidebarItem: NSSplitViewItem
    private let contentItem: NSSplitViewItem
    private let topAccessory = ChromeAccessoryController()
    private let bottomAccessory = ChromeAccessoryController()
    /// The user dragged the divider: the sidebar's new width.
    var onWidthChange: ((CGFloat) -> Void)?
    private var chrome: (top: CGFloat, bottom: CGFloat) = (0, 0)
    private var applyingWidth = false

    init(rootView: BrowserWindowView) {
        let sidebarController = NSViewController()
        let host = SidebarItemView()
        // Room's window material and the space's tint behind the sidebar too (the window's own is the content item's).
        rootView.materialView.mirror = host.material
        host.sidebarView = rootView.sidebarView
        sidebarController.view = host
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = SidebarMetrics.minWidth
        sidebarItem.maximumThickness = SidebarMetrics.maxWidth
        sidebarItem.allowsFullHeightLayout = true
        let contentController = NSViewController()
        contentController.view = rootView
        contentItem = NSSplitViewItem(viewController: contentController)
        super.init(nibName: nil, bundle: nil)
        rootView.hostsSidebarOutside = true
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        sidebarItem.addTopAlignedAccessoryViewController(topAccessory)
        sidebarItem.addBottomAlignedAccessoryViewController(bottomAccessory)
        host.onLayout = { [weak self] in self?.updateAccessories() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSidebarWidth(_ width: CGFloat) {
        guard !sidebarItem.isCollapsed, isViewLoaded, splitView.subviews.count > 1 else { return }
        applyingWidth = true
        splitView.setPosition(width, ofDividerAt: 0)
        applyingWidth = false
    }

    func setSidebarCollapsed(_ collapsed: Bool, animated: Bool) {
        guard sidebarItem.isCollapsed != collapsed else { return }
        if animated, !Motion.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.dock
                sidebarItem.animator().isCollapsed = collapsed
            }
        } else {
            sidebarItem.isCollapsed = collapsed
        }
    }

    func setChrome(top: CGFloat, bottom: CGFloat) {
        guard (top, bottom) != chrome else { return }
        chrome = (top, bottom)
        updateAccessories()
    }

    /// The top accessory starts under the titlebar band; it reaches down to the chrome's bottom edge.
    private func updateAccessories() {
        guard let host = sidebarItem.viewController.view as? SidebarItemView else { return }
        let titlebar = max(0, host.safeAreaInsets.top - topAccessory.height)
        topAccessory.height = max(0, chrome.top - titlebar)
        bottomAccessory.height = max(0, chrome.bottom)
    }

    public override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard !applyingWidth, !sidebarItem.isCollapsed, let width = splitView.subviews.first?.frame.width, width > 0 else { return }
        onWidthChange?(width)
    }
}

/// A transparent accessory of a given height: it only tells AppKit where the chrome is (soft edge).
private final class ChromeAccessoryController: NSSplitViewItemAccessoryViewController {
    private var heightConstraint: NSLayoutConstraint?

    var height: CGFloat = 0 {
        didSet { if height != oldValue { heightConstraint?.constant = height } }
    }

    override func loadView() {
        let view = PassThroughView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let constraint = view.heightAnchor.constraint(equalToConstant: height)
        constraint.isActive = true
        heightConstraint = constraint
        self.view = view
        automaticallyAppliesContentInsets = false
        if #available(macOS 26.1, *) { preferredScrollEdgeEffectStyle = .soft }
    }
}

/// Draws nothing and takes no clicks.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The sidebar item's view: the sidebar fills it.
final class SidebarItemView: NSView {
    var onLayout: (() -> Void)?
    let material = WindowMaterialView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material.frame = bounds
        material.autoresizingMask = [.width, .height]
        addSubview(material)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var sidebarView: SidebarView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let sidebarView {
                sidebarView.autoresizingMask = [.width, .height]
                sidebarView.frame = bounds
                addSubview(sidebarView)
            }
        }
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        material.frame = bounds
        sidebarView?.frame = bounds
        onLayout?()
    }
}
