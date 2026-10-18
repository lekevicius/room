import Foundation
import JavaScriptCore

/// uBlock Origin's redirect bodies (`src/web_accessible_resources/`: the
/// stand-ins for `googletagmanager_gtm.js`, ad pixels, VAST files…), which
/// uBO's lists name in `$redirect=`. GPLv3 like the scriptlets, so fetched
/// with them from the same tag, never bundled. `src/js/redirect-resources.js`
/// is the index: GitHub's raw host cannot list a directory.
nonisolated public enum UBlockRedirects {
    /// The index, relative to `src/js/` (`UBlockScriptlets.sourceURL`).
    public static let index = "redirect-resources.js"
    public static let baseURL = URL(string: "https://raw.githubusercontent.com/gorhill/uBlock/\(UBlockScriptlets.tag)/src/web_accessible_resources/")!
    /// A guard against a changed layout: 1.75.0 lists 47.
    public static let maximumEntries = 120

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notAnIndex
        case unsafeName(String)
        case tooManyEntries(Int)
        case script(String)

        public var description: String {
            switch self {
            case .notAnIndex: "redirect-resources.js is not one `export default new Map(…)`"
            case let .unsafeName(name): "redirect body name '\(name)' is not a plain file name"
            case let .tooManyEntries(count): "more than \(count) redirect bodies"
            case let .script(message): "JavaScript: \(message)"
            }
        }
    }

    /// One entry of the index.
    public struct Entry: Codable, Hashable, Sendable {
        public var name: String
        public var aliases: [String]
        public var requiresTrust: Bool
        /// Parameters uBO passes in the resource's URL (`click2load.html`).
        public var params: [String]

        public init(name: String, aliases: [String] = [], requiresTrust: Bool = false, params: [String] = []) {
            self.name = name
            self.aliases = aliases
            self.requiresTrust = requiresTrust
            self.params = params
        }
    }

    public static func sourceURL(_ name: String, base: URL = baseURL) -> URL {
        base.appending(path: name)
    }

    /// A file name in that one directory, nothing else.
    public static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && name.count <= 100
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
    }

    /// The index's entries, read in a bare JavaScriptCore context. Entries
    /// that need URL parameters are left out: Room serves a body as a
    /// `data:` URL, which carries none.
    public static func entries(fromIndex text: String) throws -> [Entry] {
        let declaration = "export default new Map("
        guard text.components(separatedBy: declaration).count == 2,
              !text.split(separator: "\n").contains(where: { $0.hasPrefix("import ") || $0.hasPrefix("export ") && !$0.hasPrefix(declaration) })
        else { throw Failure.notAnIndex }
        guard let context = JSContext() else { throw Failure.script("no context") }
        var failure: String?
        context.exceptionHandler = { _, exception in
            failure = failure ?? exception?.toString() ?? "exception"
        }
        context.evaluateScript(text.replacingOccurrences(of: declaration, with: "var __roomRedirects = new Map("))
        let json = context.evaluateScript("""
        JSON.stringify(Array.from(__roomRedirects, ([name, d]) => ({
            name: String(name), aliases: [].concat(d.alias || []).map(String),
            requiresTrust: !!d.requiresTrust, params: [].concat(d.params || []).map(String),
        })))
        """)?.toString() ?? ""
        if let failure { throw Failure.script(failure) }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(json.utf8))
        guard entries.count <= maximumEntries else { throw Failure.tooManyEntries(maximumEntries) }
        if let unsafe = entries.first(where: { !isSafeName($0.name) }) { throw Failure.unsafeName(unsafe.name) }
        return entries.filter(\.params.isEmpty)
    }

    /// Each entry's body through `fetch`, in parallel; a body that fails is
    /// left out (its rules then block without a stand-in).
    public static func bodies(for entries: [Entry],
                              fetch: @escaping @Sendable (String) async throws -> Data) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for entry in entries { group.addTask { (entry.name, try? await fetch(entry.name)) } }
            var bodies: [String: Data] = [:]
            for await (name, data) in group { bodies[name] = data }
            return bodies
        }
    }

    /// adblock-rust's MIME for a file name (its `MimeType::from_extension`);
    /// uBO's extension-less `empty` is text.
    public static func mime(for name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "text/plain" }
        return switch name[name.index(after: dot)...] {
        case "css": "text/css"
        case "gif": "image/gif"
        case "html": "text/html"
        case "js": "application/javascript"
        case "json": "application/json"
        case "mp3": "audio/mp3"
        case "mp4": "video/mp4"
        case "png": "image/png"
        case "txt": "text/plain"
        case "xml": "text/xml"
        default: "application/octet-stream"
        }
    }

    /// Resources for the entries whose body arrived. A body that needs trust
    /// carries the trusted bit; adblock-rust then uses it only for trusted
    /// `+js()`, never as a redirect (Brave leaves it out altogether).
    public static func resources(_ entries: [Entry], bodies: [String: Data]) -> [AdblockResource] {
        entries.compactMap { entry in
            guard let body = bodies[entry.name] else { return nil }
            return AdblockResource(name: entry.name, aliases: entry.aliases, mime: mime(for: entry.name),
                                   content: body.base64EncodedString(),
                                   permission: entry.requiresTrust ? UBlockScriptlets.trustedPermission : nil)
        }
    }
}
