import AppKit
import CEFBridge
import Engine

// Bridge enums and values → Engine types.

extension Disposition {
    init(_ disposition: RoomCEFDisposition) {
        switch disposition {
        case .currentTab: self = .currentTab
        case .newForegroundTab: self = .newForegroundTab
        case .newBackgroundTab: self = .newBackgroundTab
        case .newPopup: self = .newPopup
        case .newWindow: self = .newWindow
        case .saveToDisk: self = .saveToDisk
        case .offTheRecord: self = .offTheRecord
        case .ignore: self = .ignore
        case .newPictureInPicture: self = .newPictureInPicture
        @unknown default: self = .newForegroundTab
        }
    }
}

extension NavigationAction {
    init(_ request: RoomCEFNavigationRequest) {
        let kind: Kind
        let transition: PageTransition
        switch request.transition {
        case .link: (kind, transition) = (.linkActivated, .link)
        case .typed: (kind, transition) = (.other, .typed)
        case .bookmark: (kind, transition) = (.other, .bookmark)
        case .generated: (kind, transition) = (.other, .generated)
        case .keyword: (kind, transition) = (.other, .keyword)
        case .formSubmit: (kind, transition) = (.formSubmitted, .formSubmit)
        case .reload: (kind, transition) = (.reload, .reload)
        case .backForward: (kind, transition) = (.backForward, .other)
        case .other: (kind, transition) = (.other, .other)
        @unknown default: (kind, transition) = (.other, .other)
        }
        self.init(
            url: URL(string: request.url) ?? URL(string: "about:blank")!,
            referrer: request.referrer.flatMap(URL.init(string:)),
            kind: kind,
            transition: transition,
            disposition: .currentTab,
            isUserGesture: request.userGesture,
            isRedirect: request.redirect
        )
    }
}

extension TerminationStatus {
    init(_ status: RoomCEFTerminationStatus) {
        switch status {
        case .abnormal: self = .abnormal
        case .killed: self = .killed
        case .crashed: self = .crashed
        case .outOfMemory: self = .outOfMemory
        case .launchFailed: self = .launchFailed
        case .integrityFailure: self = .integrityFailure
        case .normal: self = .normal
        @unknown default: self = .abnormal
        }
    }
}

extension PermissionRequest.Kind {
    /// The permission kinds in a CEF permission-prompt bit mask.
    static func kinds(in types: RoomCEFPermissionTypes) -> [PermissionRequest.Kind] {
        let table: [(RoomCEFPermissionTypes, PermissionRequest.Kind)] = [
            (.arSession, .arSession),
            (.cameraPanTiltZoom, .cameraPanTiltZoom),
            (.cameraStream, .camera),
            (.capturedSurfaceControl, .capturedSurfaceControl),
            (.clipboard, .clipboard),
            (.topLevelStorageAccess, .topLevelStorageAccess),
            (.localFonts, .localFonts),
            (.geolocation, .geolocation),
            (.handTracking, .handTracking),
            (.identityProvider, .identityProvider),
            (.idleDetection, .idleDetection),
            (.micStream, .microphone),
            (.midiSysex, .midiSysex),
            (.multipleDownloads, .multipleDownloads),
            (.notifications, .notifications),
            (.keyboardLock, .keyboardLock),
            (.pointerLock, .pointerLock),
            (.protectedMediaIdentifier, .protectedMediaIdentifier),
            (.registerProtocolHandler, .registerProtocolHandler),
            (.storageAccess, .storageAccess),
            (.vrSession, .vrSession),
            (.webAppInstallation, .webAppInstallation),
            (.windowManagement, .windowManagement),
            (.fileSystemAccess, .fileSystemAccess),
            (.sensors, .sensors),
        ]
        var kinds = table.compactMap { types.contains($0.0) ? $0.1 : nil }
        if !types.isDisjoint(with: [.localNetworkAccess, .localNetwork, .loopbackNetwork]) {
            kinds.append(.localNetworkAccess)
        }
        // DISK_QUOTA has no Engine kind; Chromium grants it silently.
        return kinds
    }

    static func kinds(in access: RoomCEFMediaAccess) -> [PermissionRequest.Kind] {
        var kinds: [PermissionRequest.Kind] = []
        if access.contains(.deviceVideo) { kinds.append(.camera) }
        if access.contains(.deviceAudio) { kinds.append(.microphone) }
        if !access.isDisjoint(with: [.desktopVideo, .desktopAudio]) { kinds.append(.displayCapture) }
        return kinds
    }
}

extension RoomCEFPermissionResult {
    init(_ response: PermissionResponse) {
        switch response {
        // CEF has no "this time only" result.
        case .granted, .grantedOnce: self = .accept
        case .denied: self = .deny
        case .dismissed: self = .dismiss
        }
    }
}

extension MenuItem {
    init(_ item: RoomCEFMenuItem) {
        let kind: Kind
        switch item.type {
        case .command: kind = .command
        case .check: kind = .checkbox
        case .radio: kind = .radio(group: item.groupID)
        case .separator: kind = .separator
        case .submenu: kind = .submenu(item.submenu.map(MenuItem.init))
        @unknown default: kind = .command
        }
        self.init(
            id: item.type == .separator ? -1 : item.commandID,
            kind: kind,
            title: item.title.replacingOccurrences(of: "&", with: ""),
            isEnabled: item.enabled,
            isChecked: item.checked,
            keyEquivalent: item.keyEquivalent,
            keyEquivalentModifiers: item.keyEquivalentModifiers
        )
    }
}

extension ContextMenuElement {
    init(_ params: RoomCEFContextMenuParams) {
        let mediaType: MediaType
        switch params.mediaType {
        case .none: mediaType = .none
        case .image: mediaType = .image
        case .video: mediaType = .video
        case .audio: mediaType = .audio
        case .canvas: mediaType = .canvas
        case .file: mediaType = .file
        case .plugin: mediaType = .plugin
        @unknown default: mediaType = .none
        }
        self.init(
            location: params.location,
            pageURL: params.pageURL.flatMap(URL.init(string:)),
            frameURL: params.frameURL.flatMap(URL.init(string:)),
            linkURL: params.linkURL.flatMap(URL.init(string:)),
            // CEF: no link text.
            linkText: nil,
            sourceURL: params.sourceURL.flatMap(URL.init(string:)),
            mediaType: mediaType,
            selectionText: params.selectionText,
            isEditable: params.editable,
            misspelledWord: params.misspelledWord,
            dictionarySuggestions: params.dictionarySuggestions
        )
    }
}

extension FileChooserRequest.Mode {
    init(_ mode: RoomCEFFileDialogMode) {
        switch mode {
        case .open: self = .open
        case .openMultiple: self = .openMultiple
        case .openFolder: self = .openFolder
        case .save: self = .save
        @unknown default: self = .open
        }
    }
}

extension DownloadItem {
    init(_ item: RoomCEFDownloadItem) {
        let state: State
        if item.complete {
            state = .complete
        } else if item.canceled {
            state = .cancelled
        } else if item.interrupted {
            state = .interrupted
        } else {
            state = .inProgress
        }
        self.init(
            id: String(item.identifier),
            url: URL(string: item.url) ?? URL(string: "about:blank")!,
            suggestedFilename: item.suggestedFileName,
            destination: item.fullPath.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
            mimeType: item.mimeType,
            receivedBytes: item.receivedBytes,
            totalBytes: item.totalBytes >= 0 ? item.totalBytes : nil,
            currentSpeed: item.currentSpeed,
            state: state,
            isPaused: item.paused,
            // CEF reports no resumability; paused and interrupted items accept Resume().
            canResume: item.paused || item.interrupted,
            startTime: item.startTime ?? Date()
        )
    }
}

/// Zoom factor (1 = 100%) ↔ Chromium zoom level (factor = 1.2^level).
enum ZoomConversion {
    static func level(forFactor factor: Double) -> Double {
        factor > 0 ? log(factor) / log(1.2) : 0
    }

    static func factor(forLevel level: Double) -> Double {
        pow(1.2, level)
    }
}

/// Parses the CSS colors `getComputedStyle` and `<meta name=theme-color>`
/// produce: `rgb()`/`rgba()` (comma or space syntax) and `#rgb`/`#rrggbb`.
enum CSSColor {
    static func parse(_ string: String?) -> NSColor? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("#") { return hex(String(raw.dropFirst())) }
        guard raw.hasPrefix("rgb"), let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")") else {
            return nil
        }
        let body = raw[raw.index(after: open)..<close]
        let parts = body.split(whereSeparator: { ", /".contains($0) }).compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        guard parts.count >= 3 else { return nil }
        let alpha = parts.count >= 4 ? parts[3] : 1
        return NSColor(srgbRed: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: alpha)
    }

    private static func hex(_ digits: String) -> NSColor? {
        var expanded = digits
        if digits.count == 3 { expanded = digits.map { "\($0)\($0)" }.joined() }
        guard expanded.count == 6, let value = UInt32(expanded, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
