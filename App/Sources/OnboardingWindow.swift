import AppKit
import Design
import Integration
import Model
import Omnibox
import Store
import SwiftUI

/// Onboarding (5.7b, B-121), in place of the first-run card: a window of its
/// own over the browser window on a first launch, and from Help ▸ Welcome to
/// Room…. The steps and their rules are `Onboarding` (Integration, tested);
/// this is the window and its SwiftUI leaf (PLAN §4 UI framework). Import
/// reuses the import sheet, over this window; the default-browser step asks
/// macOS through `DefaultBrowser` (a DEBUG spike counts the request instead);
/// the theme step colours the shown space and sets the appearance.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let onboarding: Onboarding
    let model: OnboardingViewModel
    private let onEnd: () -> Void

    init(onboarding: Onboarding, model: OnboardingViewModel, onEnd: @escaping () -> Void) {
        self.onboarding = onboarding
        self.model = model
        self.onEnd = onEnd
        // A panel: key while it shows, never main, so the browser window stays the main window under it
        // (its menus and keys still reach the browser; the tour's main-window checks hold). Not hidden when Room is not active.
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: OnboardingMetrics.width, height: OnboardingMetrics.height),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = false
        window.title = "Welcome to Room"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setAccessibilityIdentifier("onboarding-window")
        super.init(window: window)
        window.delegate = self
        let hosting = NSHostingController(rootView: OnboardingView(onboarding: onboarding, model: model) { [weak self] in self?.close() })
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: OnboardingMetrics.width, height: OnboardingMetrics.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Centred over `parent` (the browser window), inside its screen's visible frame.
    func show(over parent: NSWindow?) {
        guard let window else { return }
        if let parent, let visible = (parent.screen ?? NSScreen.main)?.visibleFrame {
            var frame = window.frame
            frame.origin = NSPoint(x: parent.frame.midX - frame.width / 2, y: parent.frame.midY - frame.height / 2)
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// The close button is Skip Setup.
    func windowWillClose(_ notification: Notification) {
        onboarding.skip()
        onEnd()
    }
}

/// What the steps reach beyond the settings: the import sheet, the default
/// browser, the shown space's colour, and the last import's line.
@MainActor @Observable
final class OnboardingViewModel {
    @ObservationIgnored let defaultBrowser: DefaultBrowser
    @ObservationIgnored let crashReportsUnavailable: Bool
    @ObservationIgnored var openImport: () -> Void = {}
    @ObservationIgnored var makeDefault: () -> Void = {}
    @ObservationIgnored var spaceColor: () -> String? = { nil }
    @ObservationIgnored var setSpaceColor: (String?) -> Void = { _ in }
    @ObservationIgnored var spaceName: () -> String = { "this space" }
    /// The import sheet's summary once something was imported.
    var importSummary: String?
    /// Bumped when the shown space's colour changes (the swatches redraw).
    var colorRevision = 0

    init(defaultBrowser: DefaultBrowser, crashReportsUnavailable: Bool) {
        self.defaultBrowser = defaultBrowser
        self.crashReportsUnavailable = crashReportsUnavailable
    }
}

struct OnboardingView: View {
    let onboarding: Onboarding
    @Bindable var model: OnboardingViewModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.m) {
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: OnboardingMetrics.symbolSize, weight: .regular))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(onboarding.step.title).font(.title).bold()
                    .accessibilityIdentifier("onboarding-title")
                Text(explanation)
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: OnboardingMetrics.width - 4 * OnboardingMetrics.padding)
                content
                    .padding(.top, Spacing.s)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, OnboardingMetrics.padding)
            dots.padding(.bottom, Spacing.m)
            HStack {
                Button("Skip Setup") { onboarding.skip() }
                    .accessibilityIdentifier("onboarding-skip")
                Spacer()
                if !onboarding.isFirst {
                    Button("Back") { onboarding.back() }
                }
                Button(onboarding.isLast ? "Done" : "Continue") { onboarding.next() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding-continue")
            }
            .padding(OnboardingMetrics.padding)
        }
        .frame(width: OnboardingMetrics.width, height: OnboardingMetrics.height)
        .onChange(of: onboarding.ending) { if onboarding.ending != nil { close() } }
    }

    private var symbol: String {
        switch onboarding.step {
        case .welcome: "sidebar.left"
        case .importData: "square.and.arrow.down"
        case .defaultBrowser: "link"
        case .theme: "paintpalette"
        case .search: "magnifyingglass"
        }
    }

    private var explanation: String {
        switch onboarding.step {
        case .welcome:
            "Your tabs live in the sidebar, in spaces. A few choices and you are set: each step can be skipped, "
                + "and everything can be changed later in Settings."
        case .importData:
            "Bookmarks, history, Arc's spaces, passwords from an exported file and extensions from the Chrome Web Store."
        case .defaultBrowser:
            "Links from other apps open in Room, in the space a routing rule names. macOS asks you to confirm."
        case .theme:
            "A colour for “\(model.spaceName())” tints the window; every space can have its own in its Space Settings…."
        case .search:
            "Crash reports and update checks stay off unless you turn them on here or in Settings ▸ Privacy."
        }
    }

    @ViewBuilder private var content: some View {
        switch onboarding.step {
        case .welcome:
            EmptyView()
        case .importData:
            VStack(spacing: Spacing.s) {
                Button("Import from Another Browser…") { model.openImport() }
                    .controlSize(.large)
                    .accessibilityIdentifier("onboarding-import")
                if let summary = model.importSummary {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .defaultBrowser:
            if model.defaultBrowser.isDefault {
                Label("Room is your default browser", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button("Make Room the Default Browser") { model.makeDefault() }
                    .controlSize(.large)
                    .disabled(model.defaultBrowser.isAsking)
                    .accessibilityIdentifier("onboarding-default-browser")
            }
        case .theme:
            VStack(spacing: Spacing.m) {
                swatches
                Picker("Appearance", selection: Binding(get: { onboarding.appearance }, set: { onboarding.appearance = $0 })) {
                    Text("System").tag(AppearanceSetting.system)
                    Text("Light").tag(AppearanceSetting.light)
                    Text("Dark").tag(AppearanceSetting.dark)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        case .search:
            Form {
                Picker("Search with", selection: Binding(get: { onboarding.searchEngine }, set: { onboarding.searchEngine = $0 })) {
                    ForEach(SearchEngines.list(onboarding.settings)) { engine in Text(engine.name).tag(engine.id) }
                }
                Toggle(isOn: Binding(get: { onboarding.crashReports }, set: { onboarding.crashReports = $0 })) {
                    Text("Send crash reports")
                    Text(model.crashReportsUnavailable ? "Not set up in this build yet." : "A crash's report goes to Room's developer.")
                }
                Toggle(isOn: Binding(get: { onboarding.automaticUpdateChecks }, set: { onboarding.automaticUpdateChecks = $0 })) {
                    Text("Check for updates automatically")
                    Text("Asks Room's update server once a day.")
                }
            }
            .formStyle(.columns)
            .fixedSize()
        }
    }

    private var swatches: some View {
        let _ = model.colorRevision
        let current = model.spaceColor()
        return HStack(spacing: Spacing.s) {
            ForEach(OnboardingMetrics.themeSwatches, id: \.self) { hex in
                Button {
                    model.setSpaceColor(hex)
                    model.colorRevision += 1
                } label: {
                    ZStack {
                        Circle()
                            .fill(hex.flatMap(Self.color(hex:)).map(AnyShapeStyle.init) ?? AnyShapeStyle(Color.secondary.opacity(OnboardingMetrics.emptySwatchAlpha)))
                        if hex == nil {
                            Image(systemName: "slash.circle").foregroundStyle(.secondary)
                        }
                        if current?.uppercased() == hex?.uppercased() {
                            Circle().strokeBorder(Color.primary, lineWidth: OnboardingMetrics.swatchRingWidth)
                        }
                    }
                    .frame(width: OnboardingMetrics.swatchSize, height: OnboardingMetrics.swatchSize)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hex.map { "Colour \($0)" } ?? "No colour")
                .accessibilityAddTraits(current?.uppercased() == hex?.uppercased() ? .isSelected : [])
            }
        }
    }

    private var dots: some View {
        HStack(spacing: Spacing.s) {
            ForEach(Onboarding.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step == onboarding.step ? Color.primary : Color.secondary.opacity(OnboardingMetrics.inactiveDotAlpha))
                    .frame(width: OnboardingMetrics.dotSize, height: OnboardingMetrics.dotSize)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(onboarding.step.rawValue + 1) of \(Onboarding.Step.allCases.count)")
    }

    static func color(hex: String) -> Color? {
        guard let hsl = HSLColor(hex: hex) else { return nil }
        let (red, green, blue) = hsl.rgb
        return Color(.sRGB, red: red, green: green, blue: blue)
    }
}

// MARK: - AppDelegate

extension AppDelegate {
    /// After the first window of a launch: onboarding when the state never finished or skipped it (B-121).
    func showOnboardingAtLaunchIfNeeded() {
        guard !onboardingCheckedAtLaunch, let store else { return }
        onboardingCheckedAtLaunch = true
        guard Onboarding.showsAtLaunch(store.settings.settings) else { return }
        NSLog("Room: onboarding shown (first launch)")
        DispatchQueue.main.async { [weak self] in self?.presentOnboarding() }
    }

    /// Help ▸ Welcome to Room…: onboarding again, from the welcome, with the current choices.
    @objc func showOnboarding(_ sender: Any?) {
        ensureWindow()
        presentOnboarding()
    }

    func presentOnboarding() {
        guard let store else { return }
        if let current = onboardingWindow {
            current.onboarding.restart()
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        let settings = store.settings
        let onboarding = Onboarding(read: { [weak settings] in settings?.settings ?? Settings() },
                                    write: { [weak settings] body in settings?.update(body) })
        let model = OnboardingViewModel(defaultBrowser: defaultBrowser, crashReportsUnavailable: optIns?.crashReportsUnavailable ?? true)
        let controller = OnboardingWindowController(onboarding: onboarding, model: model) { [weak self] in
            self?.onboardingWindow = nil
        }
        model.openImport = { [weak self, weak controller, weak model] in
            self?.presentImportSheet(over: controller?.window) { summary in model?.importSummary = summary }
        }
        model.makeDefault = { [weak self] in
            #if DEBUG
            // Spikes never change the Mac's default browser: the request is counted instead.
            if SpikeRunner.requested != nil {
                self?.debugDefaultBrowserRequests += 1
                return
            }
            #endif
            self?.defaultBrowser.setAsDefault()
        }
        model.spaceColor = { [weak self] in self?.sidebar?.activeSpace?.themeColors.first }
        model.spaceName = { [weak self] in self?.sidebar?.activeSpace?.name ?? "this space" }
        model.setSpaceColor = { [weak self] hex in
            guard let self, let store = self.store, let space = sidebar?.activeSpace else { return }
            try? store.sidebar.updateSpace(space.id) { $0.themeColors = hex.map { [$0] } ?? [] }
        }
        onboardingWindow = controller
        controller.show(over: windowController?.window)
    }
}
