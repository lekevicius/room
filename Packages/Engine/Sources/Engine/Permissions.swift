import Foundation

/// One permission a page asks for.
nonisolated public struct PermissionRequest: Sendable, Hashable {
    public enum Kind: Sendable, Hashable, CaseIterable {
        case camera
        case microphone
        case cameraPanTiltZoom
        case geolocation
        case notifications
        case clipboard
        case midiSysex
        case protectedMediaIdentifier
        case storageAccess
        case topLevelStorageAccess
        case windowManagement
        case localFonts
        case idleDetection
        case keyboardLock
        case pointerLock
        case multipleDownloads
        case registerProtocolHandler
        case fileSystemAccess
        case localNetworkAccess
        case sensors
        case arSession
        case vrSession
        case handTracking
        case identityProvider
        case webAppInstallation
        case capturedSurfaceControl
        /// Screen or window capture (`getDisplayMedia`).
        case displayCapture
    }

    /// macOS's own authorization for what the request needs (camera,
    /// microphone, location, notifications), so the host can explain a
    /// system denial; `.notApplicable` for the rest and where the engine
    /// cannot tell (CEF).
    public enum SystemAuthorization: Sendable, Hashable {
        case notApplicable
        /// macOS has not asked yet; it will when the page gets access.
        case notDetermined
        /// Blocked in System Settings › Privacy & Security: an Allow here
        /// still gives the page nothing.
        case denied
        case authorized
    }

    public var kind: Kind
    /// The requesting origin.
    public var origin: URL
    public var systemAuthorization: SystemAuthorization

    public init(kind: Kind, origin: URL, systemAuthorization: SystemAuthorization = .notApplicable) {
        self.kind = kind
        self.origin = origin
        self.systemAuthorization = systemAuthorization
    }
}

/// The user's answer to a permission prompt; applies to every request in it.
nonisolated public enum PermissionResponse: Sendable, Hashable {
    /// Granted and remembered for the origin.
    case granted
    /// Granted for this page visit only.
    case grantedOnce
    /// Denied and remembered.
    case denied
    /// Closed without answering; the page may ask again.
    case dismissed
}

/// Why Chromium would show a quiet (non-modal) permission prompt.
nonisolated public enum PermissionQuietReason: Sendable, Hashable {
    case enabledInSettings
    case crowdDeny
    case abusiveRequests
    case abusiveContent
    case predictedUnlikelyGrant
}

/// What a site may do, as Chrome keeps it per origin (content settings):
/// the site panel lists and changes these (ROADMAP 2.6 task 3).
nonisolated public enum SitePermission: String, Sendable, Hashable, CaseIterable {
    case geolocation
    case camera
    case microphone
    case notifications
    case clipboard
    case sensors
    case midiSysex
    case popups
    case sound
    case automaticDownloads
    case javascript
    case images
}

/// A site's stored answer for one `SitePermission`.
nonisolated public enum PermissionSetting: Sendable, Hashable {
    /// The site asks each time.
    case ask
    case allow
    case block
}
