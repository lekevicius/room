import AppKit
import Observation

/// Whether Room opens the system's web links, and the request to make it so
/// (ROADMAP 2.8 task 3, PLAN §4 "Default browser", `macos-ui-stack.md` §7.4):
/// `NSWorkspace.setDefaultApplication` for http and https, which asks the
/// user in a system dialog; the dialog's agent can open behind Room, so it
/// is brought forward (Chrome's `shell_integration_mac.mm` does the same).
@Observable
public final class DefaultBrowser {
    public static let schemes = ["http", "https"]
    /// The process that shows the system's "change your default web browser" dialog.
    nonisolated static let confirmationAgent = "com.apple.coreservices.uiagent"

    /// Room handles both schemes (refreshed on `refresh()`, after a request and when Room becomes active).
    public private(set) var isDefault = false
    /// A request is waiting on the system dialog.
    public private(set) var isAsking = false

    @ObservationIgnored private let bundleURL: URL
    @ObservationIgnored private let bundleID: String?
    @ObservationIgnored private var agentLaunchObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var activeObserver: (any NSObjectProtocol)?

    public init(bundle: Bundle = .main) {
        bundleURL = bundle.bundleURL
        bundleID = bundle.bundleIdentifier
        refresh()
        // The answer can also come from System Settings ▸ Desktop & Dock while Room is in the background.
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                                queue: .main) { [weakSelf = WeakBox(self)] _ in
            MainActor.assumeIsolated { weakSelf.value?.refresh() }
        }
    }

    /// The application that opens `scheme` links now.
    public static func handler(for scheme: String) -> URL? {
        guard let probe = URL(string: "\(scheme)://example.com/") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)
    }

    public func refresh() {
        let handled = Self.schemes.allSatisfy { scheme in
            Self.handler(for: scheme).flatMap { Bundle(url: $0)?.bundleIdentifier } == bundleID
        }
        if handled != isDefault { isDefault = handled }
    }

    /// Asks the system to make Room the default browser: one dialog for http
    /// (https follows, without a second dialog when the system already moved it).
    public func setAsDefault() {
        guard !isAsking else { return }
        isAsking = true
        bringConfirmationForward()
        Task {
            for scheme in Self.schemes where Self.handler(for: scheme).flatMap({ Bundle(url: $0)?.bundleIdentifier }) != bundleID {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: bundleURL, toOpenURLsWithScheme: scheme)
                } catch {
                    // The user kept their browser (or the system refused): leave the rest alone.
                    NSLog("Room: default browser for \(scheme) not changed: \(error.localizedDescription)")
                    break
                }
            }
            finishAsking()
        }
    }

    private func finishAsking() {
        if let agentLaunchObserver { NSWorkspace.shared.notificationCenter.removeObserver(agentLaunchObserver) }
        agentLaunchObserver = nil
        isAsking = false
        refresh()
    }

    /// The dialog's agent, running or launched for it, comes to the front.
    private func bringConfirmationForward() {
        if let agent = NSRunningApplication.runningApplications(withBundleIdentifier: Self.confirmationAgent).first {
            Self.activate(agent)
        }
        agentLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let agent = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  agent.bundleIdentifier == Self.confirmationAgent else { return }
            MainActor.assumeIsolated { Self.activate(agent) }
        }
    }

    private static func activate(_ agent: NSRunningApplication) {
        NSApp.yieldActivation(to: agent)
        agent.activate(options: [.activateAllWindows])
    }
}

/// A weak reference that may travel through a `@Sendable` closure and is read back on the main actor.
struct WeakBox<Object: AnyObject>: @unchecked Sendable {
    private weak var object: Object?
    init(_ object: Object) { self.object = object }
    @MainActor var value: Object? { object }
}
