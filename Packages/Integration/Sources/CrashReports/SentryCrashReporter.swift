import Foundation
import Integration
import Sentry

/// Sentry's Apple SDK (PLAN §4 Distribution) behind `OptInServices`: started
/// only when the user opted in and the build has a DSN, closed when they opt
/// out. Crash reports only: no sessions, tracing, network breadcrumbs or
/// personal data (the consent is for crash reports). The engine's helper
/// processes (Crashpad) are Chapter 3 (PLAN §7 risk 10).
public final class SentryCrashReporter: CrashReporting {
    public init() {}

    public func start(dsn: String) {
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.enableAutoSessionTracking = false
            options.enableAutoPerformanceTracing = false
            options.enableNetworkBreadcrumbs = false
            options.enableNetworkTracking = false
            options.enableCaptureFailedRequests = false
            options.tracesSampleRate = 0
        }
    }

    public func stop() {
        SentrySDK.close()
    }
}
