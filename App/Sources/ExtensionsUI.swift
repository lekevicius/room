import AppKit
import Chrome
import Engine

/// The consent sheets RoomCore asks for (ROADMAP 3.6a): installing an
/// extension (the Web Store's "Add to Chrome") with what it can do, and
/// removing one. `NSAlert` sheets on the key window (Settings when the user
/// is there, else the browser window); no visual polish (Chapter 5).
final class ExtensionConsentSheets: ExtensionConsentPresenting {
    private let fallbackWindow: () -> NSWindow?

    #if DEBUG
    /// Spikes see each sheet once it is on screen (to capture it) and may
    /// answer it themselves (`true`/`false`); `nil` leaves it to the user.
    static var debugOnShow: ((_ alert: NSAlert, _ window: NSWindow, _ kind: String) -> Bool?)?
    /// Every question asked, in order (spikes log them).
    private(set) static var debugAsked: [(kind: String, name: String, lines: [String])] = []
    #endif

    init(fallbackWindow: @escaping () -> NSWindow?) {
        self.fallbackWindow = fallbackWindow
    }

    private var window: NSWindow? {
        if let key = NSApp.keyWindow, key.isVisible, key.attachedSheet == nil { return key }
        return fallbackWindow()
    }

    func confirmUninstall(_ installed: InstalledExtension, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(installed.name)”?"
        alert.informativeText = "Its data and settings in this profile are deleted."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if let icon = installed.icon32 { alert.icon = icon }
        present(alert, kind: "uninstall", name: installed.name, lines: [], completion: completion)
    }

    func confirmInstall(_ request: ExtensionInstallRequest, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = request.title
        var lines: [String] = []
        for (index, permission) in request.permissions.enumerated() {
            lines.append("• " + permission)
            if index < request.permissionDetails.count {
                lines += request.permissionDetails[index].map { "    " + $0 }
            }
        }
        let heading = request.permissionsHeading.isEmpty ? "" : request.permissionsHeading + "\n"
        alert.informativeText = lines.isEmpty ? "It asks for no special permissions." : heading + lines.joined(separator: "\n")
        alert.addButton(withTitle: request.kind == .install ? "Add Extension" : "Allow")
        alert.addButton(withTitle: "Cancel")
        if let icon = request.icon { alert.icon = icon }
        present(alert, kind: request.kind == .install ? "install" : "permissions", name: request.name,
                lines: request.permissions, completion: completion)
    }

    private func present(_ alert: NSAlert, kind: String, name: String, lines: [String],
                         completion: @escaping (Bool) -> Void) {
        #if DEBUG
        Self.debugAsked.append((kind, name, lines))
        #endif
        guard let window else {
            completion(alert.runModal() == .alertFirstButtonReturn)
            return
        }
        alert.beginSheetModal(for: window) { response in completion(response == .alertFirstButtonReturn) }
        #if DEBUG
        if let answer = Self.debugOnShow?(alert, window, kind) {
            window.endSheet(alert.window, returnCode: answer ? .alertFirstButtonReturn : .alertSecondButtonReturn)
        }
        #endif
    }
}
