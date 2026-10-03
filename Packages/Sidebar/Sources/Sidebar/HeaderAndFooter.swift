import AppKit
import Design
import Model

/// The header's compact address field (spec §C): the site button, the
/// selected page's domain only, and a Copy URL button on hover; the full
/// URL is the tooltip. A click edits the address (⌘L docked, Phase 2.4).
public final class AddressFieldView: NSView {
    var onActivate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSiteButton: (() -> Void)?

    private let siteButton = NSButton()
    private let domainField = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var hovering = false { didSet { if hovering != oldValue { updateHover() } } }
    private var url: String?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityIdentifier("address-field")
        setAccessibilityRole(.button)
        siteButton.isBordered = false
        siteButton.imagePosition = .imageOnly
        siteButton.contentTintColor = .secondaryLabelColor
        siteButton.target = self
        siteButton.action = #selector(siteClicked)
        siteButton.setAccessibilityIdentifier("site-button")
        domainField.font = Typography.row
        // A domain that does not fit keeps both ends: "devel…apple.com" (2.2a review).
        domainField.lineBreakMode = .byTruncatingMiddle
        domainField.cell?.truncatesLastVisibleLine = true
        copyButton.image = Symbol.copyURL.image(pointSize: 12, accessibilityDescription: "Copy URL")
        copyButton.isBordered = false
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.toolTip = "Copy URL (⇧⌘C)"
        copyButton.isHidden = true
        copyButton.setAccessibilityIdentifier("copy-url")
        addSubview(siteButton)
        addSubview(domainField)
        addSubview(copyButton)
        setURL(nil, isSecure: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var wantsUpdateLayer: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: SidebarMetrics.addressFieldHeight)
    }

    public override var fittingSize: NSSize {
        NSSize(width: bounds.width, height: SidebarMetrics.addressFieldHeight)
    }

    /// The selected page's URL (`nil`: the placeholder).
    func setURL(_ url: String?, isSecure: Bool) {
        self.url = url
        if let url, let domain = EntryLabel.domain(url) ?? Optional(url) {
            domainField.stringValue = domain
            domainField.textColor = .labelColor
            toolTip = url
        } else {
            domainField.stringValue = "Search or enter URL"
            domainField.textColor = .placeholderTextColor
            toolTip = nil
        }
        let symbol: Symbol = url == nil ? .search : (isSecure ? .siteSecure : .siteInfo)
        siteButton.image = symbol.image(pointSize: 11, accessibilityDescription: "Site Information")
        siteButton.isEnabled = url != nil
        setAccessibilityLabel(url ?? "Search or enter URL")
        updateHover()
    }

    public override func updateLayer() {
        layer?.cornerRadius = Radius.small
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Palette.sidebarHover.cgColor
    }

    public override func layout() {
        super.layout()
        let side = bounds.height
        let padding = SidebarMetrics.addressFieldPadding
        let icon = SidebarMetrics.faviconSize
        siteButton.frame = NSRect(x: padding, y: 0, width: icon, height: side)
        let copyWidth: CGFloat = copyButton.isHidden ? 0 : side
        copyButton.frame = NSRect(x: bounds.width - side, y: 0, width: side, height: side)
        let x = siteButton.frame.maxX + padding
        let height = ceil(domainField.cell?.cellSize.height ?? 16)
        domainField.frame = NSRect(x: x, y: ((bounds.height - height) / 2).rounded(),
                                   width: max(0, bounds.width - x - max(copyWidth, padding)), height: height)
    }

    private func updateHover() {
        copyButton.isHidden = !(hovering && url != nil)
        needsLayout = true
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    public override func mouseEntered(with event: NSEvent) { hovering = true }
    public override func mouseExited(with event: NSEvent) { hovering = false }

    public override func mouseDown(with event: NSEvent) {}

    public override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    @objc private func copyClicked() { onCopy?() }
    @objc private func siteClicked() { onSiteButton?() }
}

/// The bottom bar (spec §F), a placeholder until 2.5/2.6: downloads button
/// (disabled until 2.6), the space icons (hidden with one space; switching
/// is 2.5) and the "+" menu.
final class SidebarFooterView: NSView {
    let downloadsButton = NSButton()
    let plusButton = NSButton()
    private let spaceIcons = NSStackView()
    /// Builds the "+" menu when it opens.
    var plusMenu: (() -> NSMenu)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        downloadsButton.image = Symbol.downloads.image(pointSize: 14, accessibilityDescription: "Downloads")
        downloadsButton.isBordered = false
        downloadsButton.imagePosition = .imageOnly
        downloadsButton.contentTintColor = .secondaryLabelColor
        downloadsButton.isEnabled = false
        downloadsButton.toolTip = "Downloads (Phase 2.6)"
        downloadsButton.setAccessibilityIdentifier("downloads")
        plusButton.image = Symbol.newTab.image(pointSize: 14, accessibilityDescription: "New")
        plusButton.isBordered = false
        plusButton.imagePosition = .imageOnly
        plusButton.contentTintColor = .secondaryLabelColor
        plusButton.target = self
        plusButton.action = #selector(plusClicked)
        plusButton.setAccessibilityIdentifier("footer-plus")
        spaceIcons.orientation = .horizontal
        spaceIcons.spacing = Spacing.s
        addSubview(downloadsButton)
        addSubview(spaceIcons)
        addSubview(plusButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    /// One dot (or the space's emoji) per space; hidden with ≤ 1 space (spec §B).
    func setSpaces(_ spaces: [Space], active: UUID?) {
        spaceIcons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard spaces.count > 1 else { return }
        for space in spaces {
            let isActive = space.id == active
            let view: NSView
            if let icon = space.icon, icon.unicodeScalars.first?.properties.isEmoji == true {
                let label = NSTextField(labelWithString: icon)
                label.font = Typography.secondary
                label.alphaValue = isActive ? 1 : 0.5
                view = label
            } else {
                let image = NSImageView(image: (isActive ? Symbol.space : Symbol.spaceInactive).image(pointSize: 6) ?? NSImage())
                image.contentTintColor = isActive ? .labelColor : .tertiaryLabelColor
                view = image
            }
            view.toolTip = space.name
            view.setAccessibilityLabel(space.name)
            spaceIcons.addArrangedSubview(view)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = SidebarMetrics.footerButtonSize
        let inset = SidebarMetrics.rowHorizontalInset + Spacing.xs
        let y = ((bounds.height - side) / 2).rounded()
        downloadsButton.frame = NSRect(x: inset, y: y, width: side, height: side)
        plusButton.frame = NSRect(x: bounds.width - inset - side, y: y, width: side, height: side)
        let size = spaceIcons.fittingSize
        spaceIcons.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                                  width: size.width, height: size.height)
    }

    @objc private func plusClicked() {
        guard let menu = plusMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: plusButton.frame.minX, y: plusButton.frame.minY), in: self)
    }
}
