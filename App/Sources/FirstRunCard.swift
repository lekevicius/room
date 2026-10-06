import AppKit
import Design
import Integration
import Omnibox
import SwiftUI

/// The first-run card (ROADMAP 2.8 task 4, `macos-ui-stack.md` §7.4: an
/// in-sidebar card, never a modal): import from another browser (4.3b), the default search engine, the
/// default-browser offer and the two opt-ins, in the sidebar above its
/// footer (`SidebarBodyView.accessoryView`), so it shows docked on either
/// side and in the hidden sidebar's overlay. An AppKit surface with a
/// SwiftUI leaf inside (PLAN §4 UI framework).
final class FirstRunCardView: NSView {
    /// A controller for its `sizeThatFits(in:)` (the height at the sidebar's width).
    private let hosting: NSHostingController<FirstRunCardContent>

    /// "Import from another browser…" (4.3b): the import sheet.
    let onImport: () -> Void

    init(firstRun: FirstRun, defaultBrowser: DefaultBrowser, crashReportsUnavailable: Bool, onImport: @escaping () -> Void,
         onDone: @escaping () -> Void) {
        self.onImport = onImport
        hosting = NSHostingController(rootView: FirstRunCardContent(firstRun: firstRun, defaultBrowser: defaultBrowser,
                                                              crashReportsUnavailable: crashReportsUnavailable, onImport: onImport,
                                                              onDone: onDone))
        super.init(frame: .zero)
        setAccessibilityIdentifier("first-run-card")
        wantsLayer = true
        layer?.cornerRadius = FirstRunMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.shadowOpacity = FirstRunMetrics.shadowOpacity
        layer?.shadowRadius = FirstRunMetrics.shadowRadius
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        // Frame-based inside the card: the sidebar asks for its height at its width.
        hosting.sizingOptions = []
        addSubview(hosting.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.sidebarSelection.cgColor
        layer?.shadowColor = Palette.cardShadow.cgColor
    }

    override func layout() {
        super.layout()
        hosting.view.frame = bounds.insetBy(dx: FirstRunMetrics.padding, dy: FirstRunMetrics.padding)
    }

    /// The card's height at `width`: its content wraps.
    func height(forWidth width: CGFloat) -> CGFloat {
        let inner = max(0, width - 2 * FirstRunMetrics.padding)
        let size = hosting.sizeThatFits(in: CGSize(width: inner, height: .greatestFiniteMagnitude))
        return ceil(size.height) + 2 * FirstRunMetrics.padding
    }
}

private struct FirstRunCardContent: View {
    let firstRun: FirstRun
    let defaultBrowser: DefaultBrowser
    let crashReportsUnavailable: Bool
    let onImport: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FirstRunMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Room").font(.headline)
                Text("Crash reports and update checks stay off unless you turn them on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Import from another browser…", action: onImport)
            Picker("Search with", selection: Binding(get: { firstRun.searchEngine }, set: { firstRun.searchEngine = $0 })) {
                ForEach(SearchEngine.all) { engine in Text(engine.name).tag(engine.id) }
            }
            .pickerStyle(.menu)
            defaultBrowserRow
            Toggle(isOn: Binding(get: { firstRun.crashReports }, set: { firstRun.crashReports = $0 })) {
                Text("Send crash reports")
                Text(crashReportsUnavailable ? "Not set up in this build yet." : "A crash's report goes to Room's developer.")
            }
            .toggleStyle(.checkbox)
            Toggle(isOn: Binding(get: { firstRun.automaticUpdateChecks }, set: { firstRun.automaticUpdateChecks = $0 })) {
                Text("Check for updates automatically")
                Text("Asks Room's update server once a day.")
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Done", action: onDone)
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var defaultBrowserRow: some View {
        if defaultBrowser.isDefault {
            Label("Room is your default browser", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button("Make Room Your Default Browser") { defaultBrowser.setAsDefault() }
                .disabled(defaultBrowser.isAsking)
        }
    }
}
