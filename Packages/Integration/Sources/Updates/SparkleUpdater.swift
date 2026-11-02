import Foundation
import Integration
import Sparkle

/// Sparkle 2 (PLAN §4 Distribution: EdDSA-signed, full-app updates) behind
/// `OptInServices`: the controller is made with its updater stopped, so
/// nothing of Sparkle runs until the user turns automatic checks on or asks
/// for a check. The feed is `SUFeedURL` and the public key `SUPublicEDKey`
/// in Info.plist (`xcodegen/base.yml`); `SUEnableAutomaticChecks` is NO there,
/// so Sparkle never asks on its own and the schedule follows Room's setting.
/// 5.13 (the user: "download updates automatically by default - we want people on latest"): an
/// update found is downloaded at once (`SUAutomaticallyUpdate`, `automaticallyDownloadsUpdates`)
/// and installs when Room quits; Room's sidebar shows a Restart banner meanwhile
/// (`onReadyToInstall`, from Sparkle's `willInstallUpdateOnQuit`).
public final class SparkleUpdater: NSObject, UpdateChecking, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private let feedOverride: String?
    public var onReadyToInstall: ((_ version: String, _ installNow: @escaping @MainActor () -> Void) -> Void)?

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
        updater?.automaticallyDownloadsUpdates = true
    }

    public func checkNow() {
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    public nonisolated func feedURLString(for updater: SPUUpdater) -> String? { feedOverride }

    /// The update is downloaded and installs on quit: Room offers the restart itself (its banner),
    /// so Sparkle's scheduler does not remind. Sparkle calls this on the main thread.
    public nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                                    immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        nonisolated(unsafe) let install = immediateInstallHandler
        return MainActor.assumeIsolated {
            guard let onReadyToInstall else { return false }
            onReadyToInstall(version) { install() }
            return true
        }
    }
}
