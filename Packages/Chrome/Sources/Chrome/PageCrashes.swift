import AppKit
import Design
import Engine
import Observation

/// Pages whose renderer went away (`processGone`) and that have not loaded
/// since (ROADMAP 2.6, exit checklist): the card shows the crashed-page view
/// over such a page while it is the one in the card. A reload, a navigation
/// or the page closing ends it.
public final class PageCrashes {
    private struct Crash {
        weak var page: (any WebContents)?
        let status: TerminationStatus
    }

    private var crashes: [ObjectIdentifier: Crash] = [:]
    /// Called after a page crashed or recovered.
    public var onChange: (() -> Void)?

    public init() {}

    /// A renderer that ended normally (the page closed) is not a crash.
    public static func showsCrashView(for status: TerminationStatus) -> Bool {
        status != .normal
    }

    public func status(of page: ObjectIdentifier?) -> TerminationStatus? {
        page.flatMap { crashes[$0]?.status }
    }

    public func crashed(_ page: any WebContents, status: TerminationStatus) {
        guard Self.showsCrashView(for: status) else { return }
        let id = ObjectIdentifier(page)
        crashes[id] = Crash(page: page, status: status)
        watch(page, id: id)
        onChange?()
    }

    /// The view's Reload button.
    public func reload(_ id: ObjectIdentifier) {
        guard let page = crashes[id]?.page else { return recovered(id) }
        recovered(id)
        page.reload()
    }

    public func pageClosed(_ page: any WebContents) {
        recovered(ObjectIdentifier(page))
    }

    private func recovered(_ id: ObjectIdentifier) {
        guard crashes.removeValue(forKey: id) != nil else { return }
        onChange?()
    }

    /// Loading again (a reload, a navigation) or closing ends the crash.
    private func watch(_ page: any WebContents, id: ObjectIdentifier) {
        let ref = PageRef(page)
        withObservationTracking {
            _ = (page.isLoading, page.state)
        } onChange: { [weak self] in
            // Fires before the new value is stored; read it on the next turn.
            Task { @MainActor in
                guard let self, self.crashes[id] != nil else { return }
                guard let page = ref.page, !page.isLoading, page.state == .alive else { return self.recovered(id) }
                self.watch(page, id: id)
            }
        }
    }
}

/// A weak page reference that can cross into an observation's `Task`.
final class PageRef {
    weak var page: (any WebContents)?
    init(_ page: any WebContents) { self.page = page }
}

/// What the card shows over a page whose renderer went away: Chrome's "Aw,
/// Snap!" in Room's words, with Reload (Return).
final class CrashedPageView: NSView {
    private let column = NSStackView()
    let reloadButton = NSButton()
    private let reload: () -> Void

    init(status: TerminationStatus, host: String?, reload: @escaping () -> Void) {
        self.reload = reload
        super.init(frame: .zero)
        wantsLayer = true
        build(status: status, host: host)
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

    static func title(for status: TerminationStatus) -> String {
        switch status {
        case .outOfMemory: "This Page Ran Out of Memory"
        case .killed: "This Page Was Stopped"
        case .launchFailed, .integrityFailure: "This Page Couldn’t Start"
        case .normal, .abnormal, .crashed: "This Page Crashed"
        }
    }

    static func code(for status: TerminationStatus) -> String {
        switch status {
        case .normal: "RESULT_CODE_NORMAL_EXIT"
        case .abnormal: "RESULT_CODE_ABNORMAL_EXIT"
        case .killed: "RESULT_CODE_KILLED"
        case .crashed: "RESULT_CODE_CRASHED"
        case .outOfMemory: "RESULT_CODE_OUT_OF_MEMORY"
        case .launchFailed: "RESULT_CODE_LAUNCH_FAILED"
        case .integrityFailure: "RESULT_CODE_INTEGRITY_FAILURE"
        }
    }

    private func build(status: TerminationStatus, host: String?) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(Self.title(for: status))
        setAccessibilityIdentifier("crashed-page")
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let top = column.topAnchor.constraint(equalTo: topAnchor, constant: 120)
        top.priority = .defaultHigh
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.widthAnchor.constraint(equalToConstant: PromptMetrics.interstitialWidth),
            top,
            column.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 24),
        ])
        let icon = NSImageView(image: Symbol.pageCrashed.image(pointSize: PromptMetrics.interstitialIconSize) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        column.addArrangedSubview(icon)
        let title = NSTextField(labelWithString: Self.title(for: status))
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        column.addArrangedSubview(title)
        let what = host.map { "Something went wrong while showing \($0)." } ?? "Something went wrong while showing this page."
        let text = NSTextField(wrappingLabelWithString: what + " Reload to try again; what you typed into the page may be lost.")
        text.font = .systemFont(ofSize: 14)
        text.textColor = .secondaryLabelColor
        text.preferredMaxLayoutWidth = PromptMetrics.interstitialWidth
        text.widthAnchor.constraint(equalToConstant: PromptMetrics.interstitialWidth).isActive = true
        column.addArrangedSubview(text)
        let code = NSTextField(labelWithString: Self.code(for: status))
        code.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        code.textColor = .secondaryLabelColor
        code.isSelectable = true
        column.addArrangedSubview(code)
        reloadButton.title = "Reload"
        reloadButton.bezelStyle = .push
        reloadButton.keyEquivalent = "\r"
        reloadButton.target = self
        reloadButton.action = #selector(reloadClicked)
        reloadButton.setAccessibilityIdentifier("crashed-page-reload")
        column.setCustomSpacing(24, after: code)
        column.addArrangedSubview(reloadButton)
    }

    @objc private func reloadClicked() { reload() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { return reloadClicked() }
        super.keyDown(with: event)
    }
}
