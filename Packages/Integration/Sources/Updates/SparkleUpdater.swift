import Foundation
import Integration
import Sparkle

/// Sparkle 2 (PLAN §4 Distribution: EdDSA-signed, full-app updates) behind
/// `OptInServices`: the controller is made with its updater stopped, so
/// nothing of Sparkle runs until the user turns automatic checks on or asks
/// for a check. The feed is `SUFeedURL` and the public key `SUPublicEDKey`
/// in Info.plist (`xcodegen/base.yml`); `SUEnableAutomaticChecks` is NO there,
/// so Sparkle never asks on its own and the schedule follows Room's setting.
public final class SparkleUpdater: NSObject, UpdateChecking, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private let feedOverride: String?

    /// `feedOverride`: a dev feed in place of `SUFeedURL` (DEBUG checks against a local appcast).
    public init(feedOverride: String? = nil) {
        self.feedOverride = feedOverride
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    private var updater: SPUUpdater? { controller?.updater }

    public var automaticallyChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater, updater.automaticallyChecksForUpdates != newValue else { return }
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    public var canCheckNow: Bool { updater?.canCheckForUpdates ?? false }

    public func start() throws {
        try updater?.start()
    }

    public func checkNow() {
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    public nonisolated func feedURLString(for updater: SPUUpdater) -> String? { feedOverride }
}
