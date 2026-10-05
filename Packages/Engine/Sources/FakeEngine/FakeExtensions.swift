import AppKit
import Engine

/// An in-memory `ProfileExtensions` (Phase 3.6a) for host tests: a settable
/// list, the consent questions through the delegate as RoomCore asks them,
/// and the update checks counted.
public final class FakeProfileExtensions: ProfileExtensions {
    public weak var delegate: (any ProfileExtensionsDelegate)?
    /// Setting it tells the delegate, as the engine does after a change.
    public var installed: [InstalledExtension] = [] {
        didSet { delegate?.extensionsDidChange(self) }
    }
    public var isReady = true
    public let managementPageURL = URL(string: "chrome://extensions/")!
    /// Every `checkForUpdates` call's time (`now`), in order.
    public private(set) var updateChecks: [Date] = []
    /// What the next checks report as found.
    public var updatesFound = 0
    public var now: () -> Date = Date.init
    /// Folders `loadUnpacked` was given.
    public private(set) var loadedFolders: [URL] = []
    /// Actions per extension and page (`ObjectIdentifier` of the page; `nil` key: defaults).
    public var actions: [InstalledExtension.ID: ExtensionActionState] = [:]

    public init(installed: [InstalledExtension] = []) {
        self.installed = installed
    }

    private func index(_ id: InstalledExtension.ID) -> Int? { installed.firstIndex { $0.id == id } }

    public func setEnabled(_ enabled: Bool, extension id: InstalledExtension.ID) {
        guard let index = index(id) else { return }
        installed[index].isEnabled = enabled
    }

    public func reload(_ id: InstalledExtension.ID) {
        guard index(id) != nil else { return }
        delegate?.extensionsDidChange(self)
    }

    /// RoomCore's rule: the delegate is asked first; no delegate, no removal.
    public func uninstall(_ id: InstalledExtension.ID) async -> Bool {
        guard let index = index(id), let delegate else { return false }
        let target = installed[index]
        let consent = await withCheckedContinuation { continuation in
            delegate.extensions(self, willUninstall: target) { continuation.resume(returning: $0) }
        }
        guard consent else { return false }
        installed.removeAll { $0.id == id }
        return true
    }

    public func loadUnpacked(at directory: URL) async throws -> InstalledExtension.ID {
        loadedFolders.append(directory)
        let id = "unpacked-\(loadedFolders.count)"
        installed.append(InstalledExtension(id: id, name: directory.lastPathComponent, isUnpacked: true))
        return id
    }

    public func optionsPageURL(for id: InstalledExtension.ID) -> URL? {
        installed.first { $0.id == id }?.optionsPageURL
    }

    public func setPinned(_ pinned: Bool, extension id: InstalledExtension.ID) {
        guard let index = index(id) else { return }
        installed[index].isPinned = pinned
    }

    public func action(for id: InstalledExtension.ID, in webContents: (any WebContents)?) -> ExtensionActionState? {
        actions[id] ?? installed.first { $0.id == id }?.action
    }

    public func checkForUpdates() async -> ExtensionUpdateCheck {
        let asked = installed.filter { !$0.isUnpacked }.count
        guard isReady, asked > 0 else { return ExtensionUpdateCheck(checked: false) }
        updateChecks.append(now())
        return ExtensionUpdateCheck(checked: true, extensions: asked, updatesFound: updatesFound)
    }

    /// An install asking for consent, as the Web Store's "Add to Chrome"
    /// does: the delegate answers; accepted, the extension is installed.
    @discardableResult
    public func simulateInstall(_ request: ExtensionInstallRequest) async -> Bool {
        guard let delegate else { return false }
        let consent = await withCheckedContinuation { continuation in
            delegate.extensions(self, willInstall: request) { continuation.resume(returning: $0) }
        }
        if consent, request.kind == .install, index(request.id) == nil {
            installed.append(InstalledExtension(id: request.id, name: request.name, isFromWebStore: true))
        }
        return consent
    }
}
