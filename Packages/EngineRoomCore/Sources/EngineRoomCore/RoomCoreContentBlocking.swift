import Engine
import Foundation
import RoomCore

/// `ContentBlocking` over `RoomContentBlocker` (B-30): adblock-rust in
/// `//room`, one engine for every profile; the configuration is handed over
/// whole and the engine is rebuilt (or read from its cache) off the main thread.
@MainActor
final class RoomCoreContentBlocking: ContentBlocking {
    private let blocker = RoomContentBlocker.shared

    func apply(_ configuration: ContentBlockingConfiguration) async -> ContentBlockingReport {
        let config = RoomContentBlockerConfiguration()
        config.enabled = configuration.isEnabled
        config.lists = configuration.lists.map {
            RoomContentBlockerList(fileURL: $0.fileURL, hostsFormat: $0.isHostsFormat, trusted: $0.isTrusted)
        }
        config.customRules = configuration.customRules
        config.resourcesURL = configuration.resourcesURL
        config.cacheDirectoryURL = configuration.cacheDirectory
        config.allowedSites = configuration.allowedSites
        config.cookieBanners = switch configuration.cookieBanners {
        case .off: .off
        case .hide: .hide
        case .reject: .reject
        }
        config.cookieScriptURL = configuration.cookieScriptURL
        return await withCheckedContinuation { continuation in
            blocker.apply(config) { report in
                continuation.resume(returning: ContentBlockingReport(
                    problems: report.problems.split(whereSeparator: \.isNewline).map(String.init),
                    fromCache: report.fromCache,
                    buildMilliseconds: report.buildMilliseconds,
                    engineBytes: report.engineBytes))
            }
        }
    }

    func wouldBlock(_ url: URL, from source: URL, type: ContentBlockingRequestType) -> Bool {
        blocker.wouldBlockURL(url, sourceURL: source, requestType: type.rawValue)
    }
}
