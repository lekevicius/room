import AppKit
import Design

/// "Update ready — Restart" (5.13, the user: a prominent banner once an update has downloaded and
/// only the restart remains): a Liquid Glass card above the mini-player and the footer, fixed while
/// the list scrolls, with the new version and AppKit's prominent glass button. Restart installs the
/// update and relaunches (Sparkle's immediate installation); quitting installs it too.
final class UpdateBannerView: NSView {
    private let glass = NSGlassEffectView()
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Update ready")
    private let versionLabel = NSTextField(labelWithString: "")
    let restartButton = NSButton(title: "Restart", target: nil, action: nil)
    var onRestart: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass.style = .regular
        glass.cornerRadius = UpdateBannerMetrics.cornerRadius
        addSubview(glass)
        icon.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: UpdateBannerMetrics.iconSize, weight: .regular))
        icon.contentTintColor = .controlAccentColor
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        versionLabel.font = Typography.secondary
        versionLabel.textColor = Palette.sidebarSecondaryLabel
        restartButton.bezelStyle = .glass
        restartButton.tintProminence = .primary
        restartButton.controlSize = .regular
        restartButton.target = self
        restartButton.action = #selector(restartClicked)
        restartButton.setAccessibilityIdentifier("update-restart")
        setAccessibilityIdentifier("update-banner")
        [icon, titleLabel, versionLabel, restartButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func setVersion(_ version: String) {
        versionLabel.stringValue = "Room \(version)"
        setAccessibilityLabel("Update ready: Room \(version)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        let pad = UpdateBannerMetrics.padding
        let iconSide = UpdateBannerMetrics.iconSize + 4
        icon.frame = NSRect(x: pad, y: ((bounds.height - iconSide) / 2).rounded(), width: iconSide, height: iconSide)
        restartButton.sizeToFit()
        let button = restartButton.frame.size
        restartButton.frame = NSRect(x: bounds.width - pad - button.width, y: ((bounds.height - button.height) / 2).rounded(),
                                     width: button.width, height: button.height)
        let textX = icon.frame.maxX + Spacing.s
        let textWidth = max(0, restartButton.frame.minX - Spacing.s - textX)
        let titleHeight = ceil(titleLabel.fittingSize.height)
        let versionHeight = ceil(versionLabel.fittingSize.height)
        let top = ((bounds.height - titleHeight - versionHeight) / 2).rounded()
        titleLabel.frame = NSRect(x: textX, y: top, width: textWidth, height: titleHeight)
        versionLabel.frame = NSRect(x: textX, y: top + titleHeight, width: textWidth, height: versionHeight)
        versionLabel.lineBreakMode = .byTruncatingTail
    }

    @objc private func restartClicked() { onRestart?() }
}

// MARK: - The sidebar's update banner

extension SidebarController {
    /// Shows the update banner for `version` (Restart runs `onRestart`), or hides it (`nil`).
    public func setUpdateBanner(version: String?, onRestart: (() -> Void)? = nil) {
        if bodyView.updateBannerView == nil {
            updateBanner.isHidden = true
            bodyView.updateBannerView = updateBanner
        }
        if let version {
            updateBanner.setVersion(version)
            updateBanner.onRestart = onRestart
        }
        guard updateBanner.isHidden != (version == nil) else { return }
        updateBanner.isHidden = version == nil
        // It rises into its place as the list above it shortens (5.13).
        let animates = updateBanner.window != nil && !Motion.reduceMotion && version != nil
        guard animates else { return bodyView.needsLayout = true }
        updateBanner.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.medium
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            bodyView.needsLayout = true
            bodyView.layoutSubtreeIfNeeded()
            updateBanner.animator().alphaValue = 1
        }
    }

    /// Whether the banner shows (spikes).
    public var isShowingUpdateBanner: Bool { !updateBanner.isHidden && bodyView.updateBannerView != nil }
}
