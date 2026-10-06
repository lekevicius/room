import Foundation
@testable import Import

/// `research/spikes/phase-4.3` in this checkout (README there: how each
/// fixture was made). Resolved from this file's path, which holds under
/// `swift test` and under CI's `xcodebuild test` alike.
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "research/spikes/phase-4.3", directoryHint: .isDirectory)

    static func url(_ path: String) -> URL { directory.appending(path: path) }

    static func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }

    /// A scratch directory removed by the caller's `defer`.
    static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension ImportedNode {
    var title: String {
        switch self {
        case .link(let link): link.title
        case .folder(let folder): folder.title
        }
    }

    var folder: ImportedFolder? { if case .folder(let folder) = self { folder } else { nil } }
    var link: ImportedLink? { if case .link(let link) = self { link } else { nil } }
}
