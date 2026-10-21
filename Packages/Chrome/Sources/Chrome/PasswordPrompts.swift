import AppKit
import Design
import Engine

// MARK: - Rules

/// The password save and update popover's rules (ROADMAP 5.8 task 2): which
/// answer each key and button gives, what each kind offers, the words.
public enum PasswordOfferRules {
    /// Chrome's password manager page, opened as a tab by Manage.
    public static let managerURL = URL(string: "chrome://password-manager")!

    /// Return and Enter save (the default button); Esc closes, Not Now.
    public static func response(forKeyCode keyCode: UInt16) -> PasswordOfferResponse? {
        switch keyCode {
        case 36, 76: .save
        case 53: .notNow
        default: nil
        }
    }

    /// A click elsewhere or the popover closing for any reason of the user's.
    public static let closeResponse = PasswordOfferResponse.notNow
    /// Manage closes the popover without saving.
    public static let manageResponse = PasswordOfferResponse.notNow

    /// "Never for This Site" is a save offer's only (Chrome's update bubble has none).
    public static func offersNever(_ kind: PasswordOffer.Kind) -> Bool {
        kind == .save
    }

    public static func title(_ offer: PasswordOffer) -> String {
        let host = PromptText.displayHost(offer.origin) ?? PromptText.hostAndPort(offer.origin)
        return offer.kind == .save ? "Save password for “\(host)”?" : "Update password for “\(host)”?"
    }

    public static func primaryTitle(_ kind: PasswordOffer.Kind) -> String {
        kind == .save ? "Save" : "Update"
    }

    /// The saved confirmation's words after `response`, or `nil` when nothing was saved.
    public static func confirmation(_ offer: PasswordOffer, after response: PasswordOfferResponse) -> String? {
        guard response == .save else { return nil }
        let host = PromptText.displayHost(offer.origin) ?? PromptText.hostAndPort(offer.origin)
        return offer.kind == .save ? "Password saved for \(host)" : "Password updated for \(host)"
    }

    /// The confirmation's toast id (one at a time).
    public static let confirmationToastID = "password-saved"
}

// MARK: - The popover

/// The save or update offer on the site button: the key, the question, the
/// username and the masked password, Never for This Site (save only), Not
/// Now, Save or Update (the default button), and Manage Passwords.
final class PasswordOfferViewController: NSViewController {
    let pending: PagePrompts.PendingPasswordOffer
    private let respond: (PasswordOfferResponse) -> Void
    private let manage: () -> Void

    init(pending: PagePrompts.PendingPasswordOffer, respond: @escaping (PasswordOfferResponse) -> Void, manage: @escaping () -> Void) {
        self.pending = pending
        self.respond = respond
        self.manage = manage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let offer = pending.offer
        let stack = PasswordOfferView { [weak self] response in self?.respond(response) }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Spacing.m
        stack.edgeInsets = NSEdgeInsets(top: Spacing.l, left: Spacing.l, bottom: Spacing.l, right: Spacing.l)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = Spacing.s
        let icon = NSImageView(image: Symbol.password.image() ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let title = NSTextField(wrappingLabelWithString: PasswordOfferRules.title(offer))
        title.font = Typography.headline
        title.setAccessibilityIdentifier("password-offer-title")
        header.addArrangedSubview(icon)
        header.addArrangedSubview(title)
        stack.addArrangedSubview(header)

        let username = NSTextField(labelWithString: offer.username.isEmpty ? "No username" : offer.username)
        username.font = Typography.row
        username.textColor = offer.username.isEmpty ? .tertiaryLabelColor : .labelColor
        username.lineBreakMode = .byTruncatingMiddle
        username.setAccessibilityIdentifier("password-offer-username")
        let password = NSTextField(labelWithString: offer.maskedPassword)
        password.font = Typography.row
        password.setAccessibilityLabel("Password, hidden")
        password.setAccessibilityIdentifier("password-offer-password")
        let grid = NSGridView(views: [[Self.caption("Username"), username], [Self.caption("Password"), password]])
        grid.rowSpacing = Spacing.xs
        grid.columnSpacing = Spacing.m
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        stack.addArrangedSubview(grid)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = Spacing.s
        if PasswordOfferRules.offersNever(offer.kind) {
            let never = NSButton(title: "Never for This Site", target: self, action: #selector(neverClicked))
            never.setAccessibilityIdentifier("password-offer-never")
            buttons.addArrangedSubview(never)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)
        let notNow = NSButton(title: "Not Now", target: self, action: #selector(notNowClicked))
        notNow.setAccessibilityIdentifier("password-offer-not-now")
        buttons.addArrangedSubview(notNow)
        let save = NSButton(title: PasswordOfferRules.primaryTitle(offer.kind), target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"
        save.setAccessibilityIdentifier("password-offer-save")
        buttons.addArrangedSubview(save)
        stack.addArrangedSubview(buttons)

        let manage = NSButton(title: "Manage Passwords…", target: self, action: #selector(manageClicked))
        manage.isBordered = false
        manage.font = Typography.secondary
        manage.contentTintColor = .linkColor
        manage.setAccessibilityIdentifier("password-offer-manage")
        stack.addArrangedSubview(manage)

        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Spacing.l).isActive = true
        stack.widthAnchor.constraint(equalToConstant: PromptMetrics.permissionWidth).isActive = true
        stack.setAccessibilityIdentifier("password-offer")
        stack.setAccessibilityLabel(PasswordOfferRules.title(offer))
        view = stack
    }

    private static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Typography.row
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func saveClicked() { respond(.save) }
    @objc private func notNowClicked() { respond(.notNow) }
    @objc private func neverClicked() { respond(.never) }
    @objc private func manageClicked() {
        respond(PasswordOfferRules.manageResponse)
        manage()
    }
}

/// The popover's root: Return saves and Esc answers Not Now through
/// `PasswordOfferRules` when the keyboard is in the popover but no button
/// takes the key.
final class PasswordOfferView: NSStackView {
    private let respond: (PasswordOfferResponse) -> Void

    init(respond: @escaping (PasswordOfferResponse) -> Void) {
        self.respond = respond
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let response = PasswordOfferRules.response(forKeyCode: event.keyCode) else { return super.keyDown(with: event) }
        respond(response)
    }

    override func cancelOperation(_ sender: Any?) {
        respond(PasswordOfferRules.closeResponse)
    }
}
