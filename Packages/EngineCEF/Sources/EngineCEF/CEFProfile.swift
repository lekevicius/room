import AppKit
import CEFBridge
import Engine

/// `Profile` over a `CefRequestContext`: its own cookie jar, cache and site
/// settings under `<root_cache_path>/Profiles/<name>`.
public final class CEFProfile: Profile {
    /// CEF does not expose Chromium's exit type.
    public var lastExitWasClean: Bool? { nil }
    public let name: String
    public weak var downloadsDelegate: (any DownloadsDelegate)?

    let context: RoomCEFRequestContext
    private let liveContents = NSHashTable<CEFWebContents>.weakObjects()
    private var downloadControls: [DownloadItem.ID: RoomCEFDownloadControl] = [:]
    private var suggestedNames: [DownloadItem.ID: String] = [:]

    init(name: String, context: RoomCEFRequestContext) {
        self.name = name
        self.context = context
    }

    /// Web contents of this profile that have a live browser.
    public var webContents: [CEFWebContents] { liveContents.allObjects }

    /// `configuration.hostWindow` is ignored: CEF has no browser objects
    /// (the page is a `SetAsChild` view the app places).
    public func createWebContents(_ configuration: WebContentsConfiguration) throws -> any WebContents {
        try makeWebContents(configuration)
    }

    /// `createWebContents` returning the concrete type.
    public func makeWebContents(_ configuration: WebContentsConfiguration = WebContentsConfiguration()) throws -> CEFWebContents {
        try CEFWebContents(profile: self, configuration: configuration)
    }

    func register(_ contents: CEFWebContents) { liveContents.add(contents) }
    func unregister(_ contents: CEFWebContents) { liveContents.remove(contents) }

    // MARK: Downloads

    func willBeginDownload(_ item: DownloadItem, completion: @escaping (URL?) -> Void) {
        guard let downloadsDelegate else {
            completion(nil)
            return
        }
        suggestedNames[item.id] = item.suggestedFilename
        downloadsDelegate.profile(self, willBeginDownload: item, completion: completion)
    }

    func didUpdateDownload(_ item: DownloadItem, control: RoomCEFDownloadControl) {
        var item = item
        // CEF's updates carry an empty suggested name (2.6b): the one from OnBeforeDownload stands.
        if item.suggestedFilename.isEmpty, let name = suggestedNames[item.id] { item.suggestedFilename = name }
        switch item.state {
        case .inProgress, .interrupted: downloadControls[item.id] = control
        case .complete, .cancelled:
            downloadControls[item.id] = nil
            suggestedNames[item.id] = nil
        }
        downloadsDelegate?.profile(self, didUpdateDownload: item)
    }

    public func pauseDownload(id: DownloadItem.ID) { downloadControls[id]?.pause() }
    public func resumeDownload(id: DownloadItem.ID) { downloadControls[id]?.resume() }
    public func cancelDownload(id: DownloadItem.ID) { downloadControls[id]?.cancel() }

    // MARK: Site data

    /// CEF has no favicon database; the app caches what `WebContents.favicon` delivers.
    public func favicon(for pageURL: URL) async -> NSImage? { nil }

    public func clearSiteData(_ types: SiteDataTypes, for origin: URL?) async throws {
        if types.contains(.cookies) {
            await withCheckedContinuation { continuation in
                context.deleteCookies(forURL: origin?.absoluteString) { continuation.resume() }
            }
        }
        if types.contains(.cache) {
            // CEF clears the HTTP cache for all origins only.
            await withCheckedContinuation { continuation in
                context.clearHTTPCache { continuation.resume() }
            }
        }
        if types.contains(.httpAuthCredentials) {
            await withCheckedContinuation { continuation in
                context.clearHTTPAuthCredentials { continuation.resume() }
            }
        }
        if types.contains(.permissions) {
            await withCheckedContinuation { continuation in
                context.clearCertificateExceptions { continuation.resume() }
            }
        }
        if types.contains(.storage) {
            // Emulated over CDP; needs a live page in this profile.
            guard let page = webContents.first else {
                throw EngineError.notSupported("CEFProfile.clearSiteData(.storage) without a live page")
            }
            let origins = origin.map { [$0] } ?? []
            guard !origins.isEmpty else {
                throw EngineError.notSupported("CEFProfile.clearSiteData(.storage) for all origins")
            }
            for origin in origins {
                let value = "\(origin.scheme ?? "https")://\(origin.host ?? "")" + (origin.port.map { ":\($0)" } ?? "")
                _ = try await page.devToolsMethod("Storage.clearDataForOrigin", params: ["origin": value, "storageTypes": "all"])
            }
        }
    }

    // MARK: Site permissions (content settings)

    public func permissionSetting(_ permission: SitePermission, for origin: URL) -> PermissionSetting? {
        switch context.contentSetting(forURL: origin.absoluteString, type: RoomCEFContentSettingType(permission)) {
        case .allow, .sessionOnly: .allow
        case .block: .block
        case .ask: .ask
        case .default: nil
        @unknown default: nil
        }
    }

    public func setPermissionSetting(_ setting: PermissionSetting?, for permission: SitePermission, origin: URL) {
        let value: RoomCEFContentSettingValue = switch setting {
        case .allow?: .allow
        case .block?: .block
        case .ask?: .ask
        case nil: .default
        }
        context.setContentSetting(value, forURL: origin.absoluteString, type: RoomCEFContentSettingType(permission))
    }

    // Chrome-only capabilities: not available on CEF.
    public var history: (any ProfileHistory)? { nil }
    public var bookmarks: (any ProfileBookmarks)? { nil }
    public var extensions: (any ProfileExtensions)? { nil }
    public func makeAutocompleteController() -> (any AutocompleteController)? { nil }
}

extension RoomCEFContentSettingType {
    init(_ permission: SitePermission) {
        self = switch permission {
        case .geolocation: .geolocation
        case .camera: .camera
        case .microphone: .microphone
        case .notifications: .notifications
        case .clipboard: .clipboard
        case .sensors: .sensors
        case .midiSysex: .midiSysex
        case .popups: .popups
        case .sound: .sound
        case .automaticDownloads: .automaticDownloads
        case .javascript: .javaScript
        case .images: .images
        }
    }
}
