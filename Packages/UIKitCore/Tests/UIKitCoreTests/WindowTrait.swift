import Foundation
import Testing

extension Tag {
    /// Suites that create a window or measure the traffic lights (AGENTS.md "Testing").
    @Tag static var window: Self
}

/// GitHub sets `CI`; `xcodegen/ci.yml` sets `ROOM_CI` in the scheme in case
/// xcodebuild does not pass `CI` through to the test process.
nonisolated enum TestEnvironment {
    static var isCI: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["CI"] != nil || environment["ROOM_CI"] != nil
    }
}

extension Trait where Self == ConditionTrait {
    /// Window suites run locally only: CI runners' displays and materials
    /// differ, and three of four red CI runs were runner geometry.
    static var localOnly: Self { .disabled(if: TestEnvironment.isCI, "window suites are skipped on CI") }
}
