import Foundation
import JavaScriptCore

/// uBlock Origin's scriptlets for Room's blocker (B-30): the `+js(…)` bodies
/// uBO's own lists call (YouTube and anti-adblock fixes). They are GPLv3, so
/// Room never ships them: the app fetches uBO's modules from the pinned tag
/// when the user turns on a uBlock list (an explicit request), turns them into
/// adblock-rust resources in JavaScriptCore, and merges those with Room's own
/// redirect bodies for the engine, with uBO's own redirect bodies
/// (`UBlockRedirects`; research/notes/adblock-approach.md §9.8).
nonisolated public enum UBlockScriptlets {
    /// The uBlock Origin release the scriptlets come from. Bump deliberately
    /// with `+js()` changes in uBO's lists; the app refetches only on the
    /// user's next request (Update Now, automatic updates, a list turned on).
    public static let tag = "1.75.0"
    /// The module that collects every scriptlet (`builtinScriptlets`), relative to `src/js/`.
    public static let entry = "resources/scriptlets.js"
    /// uBO's `src/js/` at `tag`.
    public static let baseURL = URL(string: "https://raw.githubusercontent.com/gorhill/uBlock/\(tag)/src/js/")!
    /// A guard against a changed layout: 1.75.0 has 35 modules.
    public static let maximumModules = 120
    /// The permission bit `adblock_ffi.rs` grants trusted lists (uBO's `requiresTrust`).
    public static let trustedPermission = 1

    /// Where one module comes from (`path` relative to `src/js/`, as `resolve` returns it).
    public static func sourceURL(_ path: String, base: URL = baseURL) -> URL {
        base.appending(path: path)
    }

    /// The scriptlets are wanted while a list in use is uBO's own (only
    /// those lists may call the trusted ones, and only they need them).
    public static func needed(by lists: [PlannedFilterList]) -> Bool {
        lists.contains(where: \.isTrusted)
    }
}

/// uBO's scriptlet modules as text: which files to fetch, and the one
/// classic script JavaScriptCore can run (macOS's public JavaScriptCore has
/// no module loader).
nonisolated public enum ScriptletModules {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case badSpecifier(String, in: String)
        case tooManyModules(Int)
        case unsupportedExport(String, in: String)
        case cycle(String)
        case missingModule(String)
        case script(String)
        case noScriptlets

        public var description: String {
            switch self {
            case let .badSpecifier(spec, file): "\(file): import '\(spec)' is not a relative .js path inside src/js"
            case let .tooManyModules(count): "more than \(count) modules"
            case let .unsupportedExport(line, file): "\(file): unsupported export: \(line)"
            case let .cycle(file): "import cycle through \(file)"
            case let .missingModule(file): "module not fetched: \(file)"
            case let .script(message): "JavaScript: \(message)"
            case .noScriptlets: "no scriptlets in builtinScriptlets"
            }
        }
    }

    /// One `import` statement: the module it names and the bindings it takes
    /// (`local` ← `imported`); a side-effect import has none.
    public struct Import: Equatable, Sendable {
        public var specifier: String
        public var bindings: [(imported: String, local: String)]

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.specifier == rhs.specifier && lhs.bindings.map(\.imported) == rhs.bindings.map(\.imported)
                && lhs.bindings.map(\.local) == rhs.bindings.map(\.local)
        }
    }

    // MARK: Fetch rules

    /// `specifier` as seen from module `path` (both relative to `src/js/`):
    /// only relative `.js` paths that stay inside `src/js/`, so a changed
    /// module cannot make the app fetch anything else.
    public static func resolve(_ specifier: String, from path: String) -> String? {
        guard specifier.hasPrefix("./") || specifier.hasPrefix("../"), specifier.hasSuffix(".js"),
              !specifier.contains("?"), !specifier.contains("#"), !specifier.contains("\\") else { return nil }
        var parts = path.split(separator: "/").dropLast().map(String.init)
        for part in specifier.split(separator: "/", omittingEmptySubsequences: false) {
            switch part {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            case "": return nil
            default: parts.append(String(part))
            }
        }
        return parts.joined(separator: "/")
    }

    /// Every module `entry` needs, fetched level by level through `fetch`
    /// (a path relative to `src/js/` → its text).
    public static func collect(entry: String = UBlockScriptlets.entry, limit: Int = UBlockScriptlets.maximumModules,
                               fetch: @escaping @Sendable (String) async throws -> String) async throws -> [String: String] {
        var modules: [String: String] = [:]
        var level = [entry]
        while !level.isEmpty {
            guard modules.count + level.count <= limit else { throw Failure.tooManyModules(limit) }
            let texts = try await withThrowingTaskGroup(of: (String, String).self) { group in
                for path in level { group.addTask { (path, try await fetch(path)) } }
                var texts: [(String, String)] = []
                for try await result in group { texts.append(result) }
                return texts
            }
            var next: Set<String> = []
            for (path, text) in texts {
                modules[path] = text
                for item in try imports(in: text, path: path) {
                    guard let resolved = resolve(item.specifier, from: path) else {
                        throw Failure.badSpecifier(item.specifier, in: path)
                    }
                    if modules[resolved] == nil, !level.contains(resolved) { next.insert(resolved) }
                }
            }
            level = next.sorted()
        }
        return modules
    }

    // MARK: Module syntax (the subset uBO's resources use)

    /// The top-level `import` statements of a module (they start a line).
    public static func imports(in text: String, path: String = "") throws -> [Import] {
        try statements(in: text, path: path).compactMap { statement in
            guard case let .import(item) = statement.kind else { return nil }
            return item
        }
    }

    private struct Statement {
        enum Kind {
            case `import`(Import)
            /// `export` dropped from a declaration: the names it declares.
            case declaration([String])
            /// `export { a, b as c };`: exported name ← local name.
            case list([(exported: String, local: String)])
        }

        var lines: Range<Int>
        var kind: Kind
        /// The statement's text without `export ` (declarations only).
        var replacement: String?
    }

    private static let identifier = #"[A-Za-z_$][A-Za-z0-9_$]*"#

    private static func statements(in text: String, path: String = "") throws -> [Statement] {
        let lines = text.components(separatedBy: "\n")
        var result: [Statement] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("import ") || line.hasPrefix("import{") {
                // Up to the line that ends the statement (`… from '…';` or `import '…';`).
                var end = index
                var joined = line
                while !joined.contains(";"), end + 1 < lines.count {
                    end += 1
                    joined += " " + lines[end]
                }
                guard let item = parseImport(joined) else { throw Failure.badSpecifier(joined, in: path) }
                result.append(Statement(lines: index..<(end + 1), kind: .import(item)))
                index = end + 1
                continue
            }
            if line.hasPrefix("export ") {
                let rest = String(line.dropFirst("export ".count))
                if rest.hasPrefix("{") {
                    var end = index
                    var joined = rest
                    while !joined.contains("}"), end + 1 < lines.count {
                        end += 1
                        joined += " " + lines[end]
                    }
                    guard !joined.contains(" from "), let open = joined.firstIndex(of: "{"),
                          let close = joined.firstIndex(of: "}") else { throw Failure.unsupportedExport(line, in: path) }
                    let names = parseBindings(String(joined[joined.index(after: open)..<close]))
                        .map { (exported: $0.local, local: $0.imported) }
                    result.append(Statement(lines: index..<(end + 1), kind: .list(names)))
                    index = end + 1
                    continue
                }
                guard let name = declaredName(rest) else { throw Failure.unsupportedExport(line, in: path) }
                result.append(Statement(lines: index..<(index + 1), kind: .declaration([name]), replacement: rest))
            }
            index += 1
        }
        return result
    }

    private static func parseImport(_ statement: String) -> Import? {
        let text = statement.trimmingCharacters(in: .whitespaces)
        guard let quote = text.firstIndex(where: { $0 == "'" || $0 == "\"" }) else { return nil }
        let after = text[text.index(after: quote)...]
        guard let closing = after.firstIndex(of: text[quote]) else { return nil }
        let specifier = String(after[..<closing])
        let clause = text[text.index(text.startIndex, offsetBy: "import".count)..<quote].trimmingCharacters(in: .whitespaces)
        if clause.isEmpty { return Import(specifier: specifier, bindings: []) }  // import './x.js';
        guard clause.hasSuffix("from"), let open = clause.firstIndex(of: "{"), let close = clause.firstIndex(of: "}"),
              clause[..<open].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }  // no default or namespace imports
        return Import(specifier: specifier, bindings: parseBindings(String(clause[clause.index(after: open)..<close])))
    }

    /// `a, b as c,` → [(a, a), (b, c)]
    private static func parseBindings(_ list: String) -> [(imported: String, local: String)] {
        list.split(separator: ",").compactMap { item in
            let words = item.split(whereSeparator: \.isWhitespace).map(String.init)
            switch words.count {
            case 1: return (words[0], words[0])
            case 3 where words[1] == "as": return (words[0], words[2])
            default: return nil
            }
        }
    }

    private static func declaredName(_ declaration: String) -> String? {
        let pattern = #"^(?:async\s+)?(?:function\s*\*?|class|const|let|var)\s+("# + identifier + ")"
        guard let match = declaration.firstMatch(of: try! Regex(pattern)),
              let name = match.output[1].substring else { return nil }
        return String(name)
    }

    // MARK: Linking

    /// One classic script that defines `__roomModules[path]` for every module,
    /// dependencies first. Only top-level `import`/`export` lines change, so
    /// each function's text (what uBO's `fn.toString()` gives) is untouched.
    public static func link(_ modules: [String: String], entry: String = UBlockScriptlets.entry) throws -> String {
        var parsed: [String: [Statement]] = [:]
        for (path, text) in modules { parsed[path] = try statements(in: text, path: path) }
        var order: [String] = []
        var state: [String: Bool] = [:]  // false: visiting, true: done
        func visit(_ path: String) throws {
            if state[path] == true { return }
            if state[path] == false { throw Failure.cycle(path) }
            guard let items = parsed[path] else { throw Failure.missingModule(path) }
            state[path] = false
            for case let .import(item) in items.map(\.kind) {
                guard let resolved = resolve(item.specifier, from: path) else { throw Failure.badSpecifier(item.specifier, in: path) }
                try visit(resolved)
            }
            state[path] = true
            order.append(path)
        }
        try visit(entry)

        var script = "var __roomModules = Object.create(null);\n"
        for path in order {
            let text = modules[path]!
            var lines = text.components(separatedBy: "\n")
            var head: [String] = []
            var exports: [(exported: String, local: String)] = []
            for statement in parsed[path]! {
                switch statement.kind {
                case let .import(item):
                    let resolved = resolve(item.specifier, from: path)!
                    if !item.bindings.isEmpty {
                        let names = item.bindings.map { $0.imported == $0.local ? $0.local : "\($0.imported): \($0.local)" }
                        head.append("const { \(names.joined(separator: ", ")) } = __roomModules[\(quoted(resolved))];")
                    }
                    for line in statement.lines { lines[line] = "" }
                case let .declaration(names):
                    exports += names.map { ($0, $0) }
                    lines[statement.lines.lowerBound] = statement.replacement!
                case let .list(names):
                    exports += names
                    for line in statement.lines { lines[line] = "" }
                }
            }
            let getters = exports.map { "get \($0.exported)() { return \($0.local); }" }
            script += "__roomModules[\(quoted(path))] = (function () {\n'use strict';\n"
            script += head.joined(separator: "\n") + "\n"
            script += lines.joined(separator: "\n")
            script += "\nreturn { \(getters.joined(separator: ", ")) };\n})();\n"
        }
        return script
    }

    private static func quoted(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Evaluating

    /// uBO's `builtinScriptlets` from the linked script, read in a bare
    /// JavaScriptCore context (no DOM, network or files).
    public static func scriptlets(fromLinked script: String, entry: String = UBlockScriptlets.entry) throws -> [UBlockScriptlet] {
        guard let context = JSContext() else { throw Failure.script("no context") }
        var failure: String?
        context.exceptionHandler = { _, exception in
            failure = failure ?? exception?.toString() ?? "exception"
        }
        context.evaluateScript(script)
        if let failure { throw Failure.script(failure) }
        let read = """
        JSON.stringify(__roomModules[\(quoted(entry))].builtinScriptlets.map(s => ({
            name: s.name, aliases: s.aliases || [], dependencies: s.dependencies || [],
            requiresTrust: !!s.requiresTrust, world: s.world || 'MAIN', source: String(s.fn),
        })))
        """
        let json = context.evaluateScript(read)?.toString() ?? ""
        if let failure { throw Failure.script(failure) }
        let scriptlets = try JSONDecoder().decode([UBlockScriptlet].self, from: Data(json.utf8))
        guard !scriptlets.isEmpty else { throw Failure.noScriptlets }
        return scriptlets
    }
}

/// One entry of uBO's `builtinScriptlets`.
nonisolated public struct UBlockScriptlet: Codable, Hashable, Sendable {
    public var name: String
    public var aliases: [String]
    public var dependencies: [String]
    public var requiresTrust: Bool
    /// uBO's MV3 build runs some in the isolated world; Room runs all in the main world, as Brave does.
    public var world: String
    /// The function's text.
    public var source: String

    public init(name: String, aliases: [String] = [], dependencies: [String] = [], requiresTrust: Bool = false,
                world: String = "MAIN", source: String) {
        self.name = name
        self.aliases = aliases
        self.dependencies = dependencies
        self.requiresTrust = requiresTrust
        self.world = world
        self.source = source
    }
}

/// One entry of adblock-rust's resources JSON (`adblock::resources::Resource`).
nonisolated public struct AdblockResource: Codable, Hashable, Sendable {
    public struct Kind: Codable, Hashable, Sendable {
        public var mime: String
    }

    public var name: String
    public var aliases: [String]
    public var kind: Kind
    /// Base64.
    public var content: String
    public var dependencies: [String]?
    public var permission: Int?

    public init(name: String, aliases: [String] = [], mime: String, content: String,
                dependencies: [String]? = nil, permission: Int? = nil) {
        self.name = name
        self.aliases = aliases
        kind = Kind(mime: mime)
        self.content = content
        self.dependencies = dependencies
        self.permission = permission
    }
}

nonisolated public enum ScriptletResources {
    /// adblock-rust resources for uBO's scriptlets: `name.js` ones are
    /// injectable (`application/javascript`, called with the rule's
    /// arguments), `name.fn` helpers are dependencies only (`fn/javascript`);
    /// `requiresTrust` ones need the trusted lists' permission bit.
    public static func resources(from scriptlets: [UBlockScriptlet]) -> [AdblockResource] {
        scriptlets.compactMap { scriptlet in
            guard !scriptlet.name.isEmpty, !scriptlet.source.isEmpty else { return nil }
            return AdblockResource(
                name: scriptlet.name, aliases: scriptlet.aliases,
                mime: scriptlet.name.hasSuffix(".fn") ? "fn/javascript" : "application/javascript",
                content: Data(scriptlet.source.utf8).base64EncodedString(),
                dependencies: scriptlet.dependencies.isEmpty ? nil : scriptlet.dependencies,
                permission: scriptlet.requiresTrust ? UBlockScriptlets.trustedPermission : nil)
        }
    }

    /// Dependencies no scriptlet provides (a changed uBO layout; the
    /// scriptlets that need them fail to inject, the rest work).
    public static func missingDependencies(_ resources: [AdblockResource]) -> [String] {
        let names = Set(resources.map(\.name))
        return Array(Set(resources.flatMap { $0.dependencies ?? [] }).subtracting(names)).sorted()
    }

    /// The engine's resources: Room's own first (its redirect bodies keep
    /// their names), then `added`. adblock-rust refuses a resource whose name
    /// or alias is taken, so an added one whose name is taken is dropped, and
    /// a taken alias is dropped from it.
    public static func merge(room: [AdblockResource], added: [AdblockResource]) -> [AdblockResource] {
        var taken = Set(room.flatMap { [$0.name] + $0.aliases })
        var merged = room
        for var resource in added where !taken.contains(resource.name) {
            taken.insert(resource.name)
            resource.aliases = resource.aliases.filter { taken.insert($0).inserted }
            merged.append(resource)
        }
        return merged
    }
}
