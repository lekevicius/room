import Testing
@testable import Infra

/// 5.0a: the Debug app (`app.room.desktop.dev`) never shares a folder with the user's Room.
@Suite struct AppPathsTests {
    @Test func debugIdentityHasItsOwnFolder() {
        #expect(AppPaths.folderName(bundleIdentifier: AppPaths.releaseBundleIdentifier) == "Room")
        #expect(AppPaths.folderName(bundleIdentifier: AppPaths.devBundleIdentifier) == "Room Dev")
        #expect(AppPaths.folderName(bundleIdentifier: nil) == "Room")
    }
}
