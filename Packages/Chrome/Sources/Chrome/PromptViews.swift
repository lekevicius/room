import AppKit
import Design
import Engine

// MARK: - Words

/// What the prompts say (Chrome's wording where Room has none of its own).
enum PromptText {
    static func dialogTitle(_ dialog: PageDialog) -> String {
        switch dialog {
        case .alert(_, let origin), .confirm(_, let origin), .prompt(_, _, let origin):
            if let host = displayHost(origin) { return "\(host) says" }
            return "This page says"
        case .beforeUnload(let isReload, _):
            return isReload ? "Reload this site?" : "Leave this site?"
        case .auth(let challenge):
            return challenge.isProxy ? "Sign in to the proxy" : "Sign in to \(displayHost(challenge.origin) ?? "this site")"
        case .certificate:
            return "This Connection Is Not Private"
        }
    }

    static func displayHost(_ url: URL?) -> String? {
        guard let url, let host = url.host(), !host.isEmpty, url.scheme == "http" || url.scheme == "https" else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func hostAndPort(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// "Use your camera" for each permission (Chrome's phrasing).
    static func permission(_ kind: PermissionRequest.Kind) -> (text: String, symbol: String) {
        switch kind {
        case .camera: ("Use your camera", Symbol.camera.name)
        case .microphone: ("Use your microphone", Symbol.microphone.name)
        case .cameraPanTiltZoom: ("Move your camera", "camera.aperture")
        case .geolocation: ("Know your location", Symbol.location.name)
        case .notifications: ("Show notifications", Symbol.notifications.name)
        case .clipboard: ("See text and images copied to the clipboard", Symbol.clipboard.name)
        case .midiSysex: ("Control and reprogram your MIDI devices", "pianokeys")
        case .protectedMediaIdentifier: ("Identify your device to play protected content", "lock.rectangle")
        case .storageAccess, .topLevelStorageAccess: ("Use cookies and site data it saved on other sites", "externaldrive")
        case .windowManagement: ("Manage windows on all your displays", "macwindow.on.rectangle")
        case .localFonts: ("Use the fonts on your Mac", "textformat")
        case .idleDetection: ("Know when you’re actively using this Mac", "moon.zzz")
        case .keyboardLock: ("Take over your keyboard", "keyboard")
        case .pointerLock: ("Take over your pointer", "cursorarrow")
        case .multipleDownloads: ("Download multiple files", Symbol.downloads.name)
        case .registerProtocolHandler: ("Open a type of link", Symbol.copyURL.name)
        case .fileSystemAccess: ("Edit files on your Mac", "doc")
        case .localNetworkAccess: ("Find and connect to devices on your local network", "network")
        case .sensors: ("Use your Mac’s motion sensors", "gyroscope")
        case .arSession: ("Use augmented reality", "arkit")
        case .vrSession: ("Use virtual reality", "visionpro")
        case .handTracking: ("Track your hands", "hand.raised")
        case .identityProvider: ("Sign you in through another site", Symbol.profile.name)
        case .webAppInstallation: ("Install web apps", "square.and.arrow.down")
        case .capturedSurfaceControl: ("Scroll and zoom the tabs you share", "rectangle.and.hand.point.up.left")
        case .displayCapture: ("Share your screen", "rectangle.on.rectangle")
        }
    }

    /// What is wrong with the certificate, in words.
    static func certificateProblem(_ error: CertificateError) -> String {
        switch error.code {
        case -200: "is for a different site"
        case -201: "has expired or is not yet valid"
        case -202: "is not issued by an authority this Mac trusts"
        case -206: "has been revoked by its issuer"
        case -208, -211: "uses weak cryptography"
        default: "could not be verified"
        }
    }
}

// MARK: - The dialog sheet

/// Dims the page and holds a dialog panel (JavaScript dialogs,
/// `beforeunload`, HTTP auth): tab-modal, clicks on the dim go nowhere.
final class PromptOverlayView: NSView {
    let content: NSView

    init(content: NSView, dims: Bool) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(content)
        if dims { updateDim() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var dims: Bool { !(content is CertificateInterstitialView) }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if dims { updateDim() }
    }

    private func updateDim() {
        let alpha = effectiveAppearance.isDark ? PromptMetrics.dimAlphaDark : PromptMetrics.dimAlphaLight
        layer?.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func layout() {
        super.layout()
        if let panel = content as? DialogPanelView {
            let size = panel.fittingSize
            let width = min(PromptMetrics.dialogWidth, bounds.width - 2 * PromptMetrics.dialogPadding)
            panel.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: PromptMetrics.dialogTopInset, width: width,
                                 height: min(size.height, bounds.height - 2 * PromptMetrics.dialogTopInset))
        } else {
            content.frame = bounds
        }
    }
}

/// The dialog itself: glass panel, title, message, the prompt's or auth's
/// fields, buttons. Return answers the primary button, Esc the escape answer.
final class DialogPanelView: NSView, NSTextFieldDelegate {
    let dialog: PageDialog
    private let respond: (DialogResponse) -> Void
    private let glass = NSGlassEffectView()
    private let stack = NSStackView()
    private var textField: NSTextField?
    private var passwordField: NSSecureTextField?
    /// The control that takes the keyboard when the panel shows.
    private(set) var initialResponder: NSView?

    init(dialog: PageDialog, respond: @escaping (DialogResponse) -> Void) {
        self.dialog = dialog
        self.respond = respond
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func build() {
        glass.cornerRadius = Radius.large
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        let container = NSView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PromptMetrics.dialogSpacing
        stack.edgeInsets = NSEdgeInsets(top: PromptMetrics.dialogPadding, left: PromptMetrics.dialogPadding,
                                        bottom: PromptMetrics.dialogPadding, right: PromptMetrics.dialogPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        glass.contentView = container
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor), glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor), glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor), stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor), stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            widthAnchor.constraint(equalToConstant: PromptMetrics.dialogWidth),
        ])

        let title = label(PromptText.dialogTitle(dialog), font: .systemFont(ofSize: 13, weight: .semibold))
        stack.addArrangedSubview(title)
        setAccessibilityElement(true)
        setAccessibilityRole(.sheet)
        setAccessibilityLabel(title.stringValue)

        switch dialog {
        case .alert(let message, _), .confirm(let message, _):
            addMessage(message)
            addButtons(primary: "OK", cancel: isAlert ? nil : "Cancel")
            initialResponder = self
        case .prompt(let message, let defaultText, _):
            addMessage(message)
            let field = NSTextField(string: defaultText)
            field.delegate = self
            field.setAccessibilityIdentifier("prompt-dialog-field")
            stack.addArrangedSubview(field)
            fill(field)
            textField = field
            addButtons(primary: "OK", cancel: "Cancel")
            initialResponder = field
        case .beforeUnload(let isReload, _):
            addMessage("Changes you made may not be saved.")
            addButtons(primary: isReload ? "Reload" : "Leave", cancel: "Cancel")
            initialResponder = self
        case .auth(let challenge):
            let who = challenge.isProxy ? "The proxy \(PromptText.hostAndPort(challenge.origin))" : PromptText.hostAndPort(challenge.origin)
            addMessage("\(who) requires a username and password.")
            if let realm = challenge.realm, !realm.isEmpty { addMessage("The site says: “\(realm)”", secondary: true) }
            if challenge.origin.scheme == "http", !challenge.isProxy {
                addMessage("Your connection to this site is not private: the password is sent unencrypted.", secondary: true)
            }
            let user = NSTextField(string: "")
            user.placeholderString = "Username"
            user.contentType = .username
            user.delegate = self
            user.setAccessibilityIdentifier("auth-username")
            let password = NSSecureTextField(string: "")
            password.placeholderString = "Password"
            password.contentType = .password
            password.delegate = self
            password.setAccessibilityIdentifier("auth-password")
            user.nextKeyView = password
            password.nextKeyView = user
            for field in [user, password] {
                stack.addArrangedSubview(field)
                fill(field)
            }
            textField = user
            passwordField = password
            addButtons(primary: "Sign In", cancel: "Cancel")
            initialResponder = user
        case .certificate:
            initialResponder = self
        }
    }

    private var isAlert: Bool {
        if case .alert = dialog { return true }
        return false
    }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.isSelectable = true
        label.preferredMaxLayoutWidth = PromptMetrics.dialogWidth - 2 * PromptMetrics.dialogPadding
        return label
    }

    private func addMessage(_ text: String, secondary: Bool = false) {
        guard !text.isEmpty else { return }
        let message = label(text, font: secondary ? Typography.secondary : Typography.row,
                            color: secondary ? .secondaryLabelColor : .labelColor)
        if text.count > 600 {
            // A long message scrolls inside the panel.
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            let textView = NSTextView()
            textView.string = text
            textView.font = Typography.row
            textView.isEditable = false
            textView.drawsBackground = false
            textView.textContainerInset = .zero
            textView.textContainer?.lineFragmentPadding = 0
            textView.autoresizingMask = [.width]
            scroll.documentView = textView
            stack.addArrangedSubview(scroll)
            fill(scroll)
            scroll.heightAnchor.constraint(equalToConstant: PromptMetrics.messageMaxHeight).isActive = true
            return
        }
        stack.addArrangedSubview(message)
        fill(message)
    }

    private func fill(_ view: NSView) {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * PromptMetrics.dialogPadding).isActive = true
    }

    private func addButtons(primary: String, cancel: String?) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        if let cancel {
            let button = NSButton(title: cancel, target: self, action: #selector(cancelClicked))
            button.bezelStyle = .push
            button.keyEquivalent = "\u{1b}"
            button.setAccessibilityIdentifier("dialog-cancel")
            row.addArrangedSubview(button)
        }
        let button = NSButton(title: primary, target: self, action: #selector(primaryClicked))
        button.bezelStyle = .push
        button.keyEquivalent = "\r"
        button.setAccessibilityIdentifier("dialog-primary")
        row.addArrangedSubview(button)
        stack.addArrangedSubview(row)
        fill(row)
    }

    @objc private func primaryClicked() {
        switch dialog {
        case .auth:
            respond(.signIn(user: textField?.stringValue ?? "", password: passwordField?.stringValue ?? ""))
        default:
            respond(PromptRules.returnResponse(for: dialog, text: textField?.stringValue))
        }
    }

    @objc private func cancelClicked() { respond(PromptRules.escapeResponse(for: dialog)) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: primaryClicked()
        case 53: cancelClicked()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { cancelClicked() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            primaryClicked()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelClicked()
            return true
        default:
            return false
        }
    }
}

// MARK: - The certificate interstitial

/// Room's page for a certificate error (ROADMAP 2.6: "our page, proceed only
/// for non-HSTS"): it covers the page until answered. Go Back is the
/// default; the way through is behind Show Details and exists only when the
/// error can be bypassed.
final class CertificateInterstitialView: NSView {
    let error: CertificateError
    private let respond: (DialogResponse) -> Void
    private let column = NSStackView()
    private let details = NSStackView()
    private let detailsButton = NSButton()
    let goBack = NSButton()

    init(error: CertificateError, respond: @escaping (DialogResponse) -> Void) {
        self.error = error
        self.respond = respond
        super.init(frame: .zero)
        wantsLayer = true
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.cardBackground.cgColor
    }

    private var host: String { PromptText.hostAndPort(error.url) }

    private func build() {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(PromptText.dialogTitle(.certificate(error)))
        setAccessibilityIdentifier("certificate-interstitial")
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.widthAnchor.constraint(equalToConstant: PromptMetrics.interstitialWidth),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 120).withPriority(.defaultHigh),
            column.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
        ])

        let icon = NSImageView(image: Symbol.siteInsecure.image(pointSize: PromptMetrics.interstitialIconSize, weight: .regular) ?? NSImage())
        icon.contentTintColor = .systemRed
        column.addArrangedSubview(icon)
        let title = NSTextField(labelWithString: PromptText.dialogTitle(.certificate(error)))
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        column.addArrangedSubview(title)
        column.addArrangedSubview(paragraph(
            "The certificate of \(host) \(PromptText.certificateProblem(error)). Someone could be pretending to be the site "
                + "to read what you send it, such as passwords, messages or card numbers."))
        let code = NSTextField(labelWithString: error.description)
        code.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        code.textColor = .secondaryLabelColor
        code.isSelectable = true
        column.addArrangedSubview(code)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        goBack.title = "Go Back"
        goBack.bezelStyle = .push
        goBack.keyEquivalent = "\r"
        goBack.target = self
        goBack.action = #selector(goBackClicked)
        goBack.setAccessibilityIdentifier("certificate-go-back")
        detailsButton.title = "Show Details"
        detailsButton.bezelStyle = .push
        detailsButton.target = self
        detailsButton.action = #selector(toggleDetails)
        buttons.addArrangedSubview(goBack)
        buttons.addArrangedSubview(detailsButton)
        column.setCustomSpacing(24, after: code)
        column.addArrangedSubview(buttons)

        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 10
        details.isHidden = true
        if error.isOverridable {
            details.addArrangedSubview(paragraph(
                "If you know this site and expect it to use this certificate (a device or server on your own network, for "
                    + "example), you can visit it anyway. The connection is not private."))
            let proceed = NSButton(title: "Visit \(host) Anyway", target: self, action: #selector(proceedClicked))
            proceed.bezelStyle = .push
            proceed.hasDestructiveAction = true
            proceed.setAccessibilityIdentifier("certificate-proceed")
            details.addArrangedSubview(proceed)
        } else {
            details.addArrangedSubview(paragraph(Self.whyNot(error)))
        }
        column.setCustomSpacing(24, after: buttons)
        column.addArrangedSubview(details)
    }

    /// Why there is no way through.
    static func whyNot(_ error: CertificateError) -> String {
        let host = PromptText.hostAndPort(error.url)
        if !CertificateRules.overridableCodes.contains(error.code) {
            return "This kind of certificate error can’t be bypassed, so \(host) can’t be visited now."
        }
        return "\(host) may require a secure connection (HSTS), so it can’t be visited despite this error. "
            + "This version of Room can only bypass certificate errors for local addresses."
    }

    private func paragraph(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = PromptMetrics.interstitialWidth
        label.widthAnchor.constraint(equalToConstant: PromptMetrics.interstitialWidth).isActive = true
        return label
    }

    @objc private func goBackClicked() { respond(.cancel) }
    @objc private func proceedClicked() { respond(.proceed) }

    @objc func toggleDetails() {
        details.isHidden.toggle()
        detailsButton.title = details.isHidden ? "Show Details" : "Hide Details"
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { return goBackClicked() }
        super.keyDown(with: event)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - The permission popover

/// "“example.com” wants to" with a row per permission and Allow / Don't
/// Allow (and Allow This Time for camera, microphone and location).
final class PermissionPromptViewController: NSViewController {
    let pending: PagePrompts.PendingPermission
    private let respond: (PermissionResponse) -> Void

    init(pending: PagePrompts.PendingPermission, respond: @escaping (PermissionResponse) -> Void) {
        self.pending = pending
        self.respond = respond
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let host = PromptText.displayHost(pending.requests.first?.origin) ?? pending.requests.first?.origin.absoluteString ?? "This page"
        let title = NSTextField(wrappingLabelWithString: "“\(host)” wants to")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)
        var seen: Set<String> = []
        for request in pending.requests {
            let (text, symbol) = PromptText.permission(request.kind)
            guard seen.insert(text).inserted else { continue }
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = Typography.row
            row.addArrangedSubview(icon)
            row.addArrangedSubview(label)
            stack.addArrangedSubview(row)
        }
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)
        let deny = NSButton(title: "Don’t Allow", target: self, action: #selector(denyClicked))
        deny.setAccessibilityIdentifier("permission-deny")
        buttons.addArrangedSubview(deny)
        if PromptRules.offersOneTimeGrant(pending.requests) {
            let once = NSButton(title: "Allow This Time", target: self, action: #selector(onceClicked))
            once.setAccessibilityIdentifier("permission-allow-once")
            buttons.addArrangedSubview(once)
        }
        let allow = NSButton(title: "Allow", target: self, action: #selector(allowClicked))
        allow.keyEquivalent = "\r"
        allow.setAccessibilityIdentifier("permission-allow")
        buttons.addArrangedSubview(allow)
        stack.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        stack.widthAnchor.constraint(equalToConstant: PromptMetrics.permissionWidth).isActive = true
        stack.setAccessibilityIdentifier("permission-prompt")
        view = stack
    }

    @objc private func denyClicked() { respond(.denied) }
    @objc private func onceClicked() { respond(.grantedOnce) }
    @objc private func allowClicked() { respond(.granted) }
}

// MARK: - Presentation

/// Keeps the card and the popover in step with `PagePrompts`: the visible
/// dialog as a sheet (or the certificate interstitial) in `host`, which
/// covers the page; the visible permission prompt as a popover on the
/// header's site button. Focus moves into a dialog and back to the page.
public final class PagePromptPresenter: NSObject, NSPopoverDelegate {
    private let prompts: PagePrompts
    private weak var host: NSView?
    /// The view and rect the permission popover points at (the site button), or `nil` for the card's top-left.
    private let permissionAnchor: () -> (view: NSView, rect: NSRect)?
    private let focusPage: () -> Void
    private let crashes: PageCrashes?
    /// The current page's host, for the crashed-page view.
    private let pageHost: (ObjectIdentifier) -> String?
    private var shownCrash: (page: ObjectIdentifier, view: CrashedPageView)?
    private var shownDialog: (id: Int, view: PromptOverlayView)?
    private var shownPermission: (id: Int, popover: NSPopover)?
    /// Set while Room closes the popover itself (a tab switch): not an answer.
    private var closingPopover = false

    public init(prompts: PagePrompts, crashes: PageCrashes? = nil, host: NSView,
                permissionAnchor: @escaping () -> (view: NSView, rect: NSRect)?,
                pageHost: @escaping (ObjectIdentifier) -> String? = { _ in nil }, focusPage: @escaping () -> Void) {
        self.prompts = prompts
        self.crashes = crashes
        self.host = host
        self.permissionAnchor = permissionAnchor
        self.pageHost = pageHost
        self.focusPage = focusPage
        super.init()
        prompts.onChange = { [weak self] in self?.update() }
        crashes?.onChange = { [weak self] in self?.update() }
    }

    /// The crashed-page view on screen (DEBUG captures, spikes).
    public var crashView: NSView? { shownCrash?.view }

    /// The dialog view on screen (DEBUG captures, spikes).
    public var dialogView: NSView? { shownDialog?.view }
    /// The permission popover's content on screen (DEBUG captures, spikes).
    public var permissionView: NSView? { shownPermission?.popover.contentViewController?.view }

    public func update() {
        updateCrash()
        updateDialog()
        updatePermission()
    }

    /// The focused page's prompt layer (the card's, Peek's; 2.7b: a pane's):
    /// what is shown moves there, nothing is answered.
    public func setHost(_ host: NSView) {
        guard host !== self.host else { return }
        shownCrash?.view.removeFromSuperview()
        shownCrash = nil
        shownDialog?.view.removeFromSuperview()
        shownDialog = nil
        if let shown = shownPermission {
            closingPopover = true
            shown.popover.close()
            closingPopover = false
            shownPermission = nil
        }
        self.host = host
        update()
    }

    /// The crashed-page view under any dialog, while the page in the card is crashed.
    private func updateCrash() {
        let page = prompts.currentPage
        let status = crashes?.status(of: page)
        if let shown = shownCrash, shown.page != page || status == nil {
            let hadFocus = Self.contains(shown.view, responder: shown.view.window?.firstResponder)
            shown.view.removeFromSuperview()
            shownCrash = nil
            if hadFocus, status == nil { focusPage() }
        }
        guard shownCrash == nil, let page, let status, let host else { return }
        let view = CrashedPageView(status: status, host: pageHost(page)) { [weak crashes] in crashes?.reload(page) }
        view.frame = host.bounds
        view.autoresizingMask = [.width, .height]
        host.addSubview(view, positioned: .below, relativeTo: nil)
        shownCrash = (page, view)
        if shownDialog == nil { view.window?.makeFirstResponder(view) }
    }

    private func updateDialog() {
        let visible = prompts.visibleDialog
        guard visible?.id != shownDialog?.id else { return }
        if let shown = shownDialog {
            let hadFocus = Self.contains(shown.view, responder: shown.view.window?.firstResponder)
            shown.view.removeFromSuperview()
            shownDialog = nil
            if hadFocus, visible == nil { focusPage() }
        }
        guard let visible, let host else { return }
        let id = visible.id
        let respond: (DialogResponse) -> Void = { [weak prompts] in prompts?.respond($0, to: id) }
        let content: NSView
        let firstResponder: NSView
        if case .certificate(let error) = visible.dialog {
            let interstitial = CertificateInterstitialView(error: error, respond: respond)
            content = interstitial
            firstResponder = interstitial
        } else {
            let panel = DialogPanelView(dialog: visible.dialog, respond: respond)
            content = panel
            firstResponder = panel.initialResponder ?? panel
        }
        let overlay = PromptOverlayView(content: content, dims: !(content is CertificateInterstitialView))
        overlay.frame = host.bounds
        overlay.autoresizingMask = [.width, .height]
        host.addSubview(overlay)
        shownDialog = (id, overlay)
        overlay.layoutSubtreeIfNeeded()
        if !Motion.reduceMotion, overlay.window != nil {
            overlay.alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = Motion.fast; overlay.animator().alphaValue = 1 }
        }
        overlay.window?.makeFirstResponder(firstResponder)
        if let field = firstResponder as? NSTextField { field.currentEditor()?.selectAll(nil) }
    }

    private func updatePermission() {
        let visible = prompts.visiblePermission
        guard visible?.id != shownPermission?.id else { return }
        if let shown = shownPermission {
            closingPopover = true
            shown.popover.close()
            closingPopover = false
            shownPermission = nil
        }
        guard let visible, let host, host.window != nil else { return }
        let id = visible.id
        let controller = PermissionPromptViewController(pending: visible) { [weak prompts] response in
            prompts?.respondToPermission(response, to: id)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        shownPermission = (id, popover)
        if let anchor = permissionAnchor(), anchor.view.window != nil {
            popover.show(relativeTo: anchor.rect, of: anchor.view, preferredEdge: .maxY)
        } else {
            // No header (hidden sidebar): the card's top-left corner.
            let corner = NSRect(x: 12, y: host.isFlipped ? 0 : host.bounds.height - 1, width: 24, height: 1)
            popover.show(relativeTo: corner, of: host, preferredEdge: host.isFlipped ? .maxY : .minY)
        }
    }

    /// Closed by a click elsewhere or Esc: the prompt is dismissed (the page may ask again).
    public func popoverDidClose(_ notification: Notification) {
        guard !closingPopover, let popover = notification.object as? NSPopover, let shown = shownPermission,
              shown.popover === popover else { return }
        shownPermission = nil
        prompts.respondToPermission(.dismissed, to: shown.id)
    }

    private static func contains(_ view: NSView, responder: NSResponder?) -> Bool {
        if let textView = responder as? NSTextView, textView.isFieldEditor, let field = textView.delegate as? NSView {
            return field.isDescendant(of: view)
        }
        return (responder as? NSView)?.isDescendant(of: view) ?? false
    }
}
