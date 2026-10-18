import Foundation
import Integration
import Model
import Testing

/// Modules in the shape of uBO's `src/js/resources/` (Room's own text, not
/// uBO's): a registry, a helper, a scriptlet that needs it, one that needs
/// trust, a module outside `resources/`, and the collecting entry.
nonisolated private let modules: [String: String] = [
    "resources/base.js": """
    export const registeredScriptlets = [];

    export const registerScriptlet = (fn, details) => {
        details.fn = fn;
        fn.details = details;
        if ( Array.isArray(details.dependencies) ) {
            details.dependencies = details.dependencies.map(d => typeof d === 'function' ? d.details.name : d);
        }
        registeredScriptlets.push(details);
    };
    """,
    "resources/helper.js": """
    import { registerScriptlet } from './base.js';
    import { Counter as __Counter__ } from '../counter.js';

    export function setFlagFn(name, value) {
        window[name] = value;
    }
    registerScriptlet(setFlagFn, {
        name: 'set-flag.fn',
    });

    export const Counter = __Counter__;
    registerScriptlet(Counter, { name: 'counter.fn' });
    """,
    "counter.js": """
    export class Counter {
        constructor() { this.n = 0; }
    }
    """,
    "resources/flag.js": """
    import {
        registerScriptlet,
    } from './base.js';
    import { setFlagFn } from './helper.js';

    function setFlag(name = '', value = '') {
        setFlagFn(name, value === 'true');
    }
    registerScriptlet(setFlag, {
        name: 'set-flag.js',
        aliases: [ 'sf.js' ],
        dependencies: [ setFlagFn ],
    });

    function trustedSetFlag(name = '', value = '') {
        setFlagFn(name, value);
    }
    registerScriptlet(trustedSetFlag, {
        name: 'trusted-set-flag.js',
        requiresTrust: true,
        world: 'ISOLATED',
        dependencies: [ 'set-flag.fn' ],
    });
    """,
    "resources/scriptlets.js": """
    import './flag.js';

    import { registeredScriptlets } from './base.js';

    export const builtinScriptlets = registeredScriptlets;
    """,
]

@Suite("uBlock Origin scriptlets: what is fetched (B-30)")
struct UBlockScriptletFetchTests {
    @Test("Modules come from uBO's src/js at the pinned tag")
    func pinned() {
        #expect(UBlockScriptlets.sourceURL("resources/base.js").absoluteString
            == "https://raw.githubusercontent.com/gorhill/uBlock/\(UBlockScriptlets.tag)/src/js/resources/base.js")
    }

    @Test("Only relative .js imports inside src/js are followed")
    func resolve() {
        #expect(ScriptletModules.resolve("./base.js", from: "resources/scriptlets.js") == "resources/base.js")
        #expect(ScriptletModules.resolve("../jsonpath.js", from: "resources/shared.js") == "jsonpath.js")
        #expect(ScriptletModules.resolve("../../secrets.js", from: "resources/shared.js") == nil)
        #expect(ScriptletModules.resolve("https://example.com/x.js", from: "resources/base.js") == nil)
        #expect(ScriptletModules.resolve("lodash", from: "resources/base.js") == nil)
        #expect(ScriptletModules.resolve("./x.json", from: "resources/base.js") == nil)
        #expect(ScriptletModules.resolve(".//x.js", from: "resources/base.js") == nil)
    }

    @Test("Every module the entry needs is fetched once, single- and multi-line imports alike")
    func collect() async throws {
        let log = FetchLog()
        let fetched = try await ScriptletModules.collect { path in
            await log.add(path)
            guard let text = modules[path] else { throw URLError(.fileDoesNotExist) }
            return text
        }
        #expect(Set(fetched.keys) == Set(modules.keys))
        let paths = await log.paths
        #expect(paths.count == modules.count && Set(paths).count == paths.count)
    }

    @Test("An import that leaves src/js, or too many modules, stops the fetch")
    func refused() async {
        let bad = modules.merging(["resources/flag.js": "import { x } from '../../../etc/x.js';\n"]) { $1 }
        await #expect(throws: ScriptletModules.Failure.self) {
            try await ScriptletModules.collect { bad[$0] ?? "" }
        }
        await #expect(throws: ScriptletModules.Failure.tooManyModules(3)) {
            try await ScriptletModules.collect(limit: 3) { modules[$0] ?? "" }
        }
    }

    @Test("uBO's own lists are trusted and bring the scriptlets; others do not")
    func trust() {
        #expect(FilterListCatalog.all.filter(\.isTrusted).map(\.id).allSatisfy { $0.hasPrefix("ublock-") })
        #expect(FilterListCatalog.info("ublock-unbreak")?.isTrusted == true)
        #expect(FilterListCatalog.info("easylist")?.isTrusted == false)
        let bundle = URL(filePath: "/App/Resources/ContentBlocking")
        var settings = ContentBlockingSettings()
        settings.customLists = [CustomFilterList(url: URL(string: "https://lists.example/mine.txt")!)]
        let custom = settings.customLists[0].id.uuidString
        let without = ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle,
                                               downloads: [custom: URL(filePath: "/Lists/mine.txt")])
        #expect(!UBlockScriptlets.needed(by: without.lists) && without.lists.allSatisfy { !$0.isTrusted })
        settings.setList("ublock-unbreak", enabled: true)
        // Turned on but not downloaded yet: nothing to inject into, nothing wanted.
        #expect(!UBlockScriptlets.needed(by: ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle, downloads: [:]).lists))
        let with = ContentBlockingPlan.make(settings: settings, bundleDirectory: bundle,
                                            downloads: ["ublock-unbreak": URL(filePath: "/Lists/ublock-unbreak.txt")])
        #expect(UBlockScriptlets.needed(by: with.lists))
        #expect(with.lists.filter(\.isTrusted).map(\.id) == ["ublock-unbreak"])
    }
}

@Suite("uBlock Origin scriptlets: into adblock-rust resources (B-30)")
struct UBlockScriptletConversionTests {
    @Test("The linked modules evaluate to the registry, with each function's text untouched")
    func evaluate() throws {
        let scriptlets = try ScriptletModules.scriptlets(fromLinked: try ScriptletModules.link(modules))
        #expect(scriptlets.map(\.name) == ["set-flag.fn", "counter.fn", "set-flag.js", "trusted-set-flag.js"])
        let flag = try #require(scriptlets.first { $0.name == "set-flag.js" })
        #expect(flag.aliases == ["sf.js"] && flag.dependencies == ["set-flag.fn"] && !flag.requiresTrust)
        #expect(flag.source == """
        function setFlag(name = '', value = '') {
            setFlagFn(name, value === 'true');
        }
        """)
        #expect(scriptlets.first { $0.name == "counter.fn" }?.source.hasPrefix("class Counter {") == true)
        let trusted = try #require(scriptlets.first { $0.name == "trusted-set-flag.js" })
        #expect(trusted.requiresTrust && trusted.world == "ISOLATED")
    }

    @Test("A cycle, a missing module or a throwing module is an error, not an empty set")
    func failures() {
        var cyclic = modules
        cyclic["resources/base.js"] = "import './scriptlets.js';\nexport const registeredScriptlets = [];\n"
        #expect(throws: ScriptletModules.Failure.cycle("resources/scriptlets.js")) { try ScriptletModules.link(cyclic) }
        var missing = modules
        missing["resources/helper.js"] = nil
        #expect(throws: ScriptletModules.Failure.missingModule("resources/helper.js")) { try ScriptletModules.link(missing) }
        var throwing = modules
        throwing["resources/flag.js"] = "throw new Error('changed layout');\n"
        #expect(throws: ScriptletModules.Failure.self) {
            try ScriptletModules.scriptlets(fromLinked: try ScriptletModules.link(throwing))
        }
    }

    @Test("Scriptlets are injectable, helpers are dependencies only, trusted ones carry the trusted bit")
    func resources() throws {
        let resources = ScriptletResources.resources(from: [
            UBlockScriptlet(name: "set-flag.js", aliases: ["sf.js"], dependencies: ["set-flag.fn"], source: "function a() {}"),
            UBlockScriptlet(name: "set-flag.fn", source: "function setFlagFn() {}"),
            UBlockScriptlet(name: "trusted-set-flag.js", requiresTrust: true, source: "function b() {}"),
            UBlockScriptlet(name: "", source: "function c() {}"),
        ])
        #expect(resources.map(\.name) == ["set-flag.js", "set-flag.fn", "trusted-set-flag.js"])
        #expect(resources.map(\.kind.mime) == ["application/javascript", "fn/javascript", "application/javascript"])
        #expect(resources.map(\.permission) == [nil, nil, UBlockScriptlets.trustedPermission])
        #expect(Data(base64Encoded: resources[0].content) == Data("function a() {}".utf8))
        #expect(ScriptletResources.missingDependencies(resources).isEmpty)
        #expect(ScriptletResources.missingDependencies([resources[0]]) == ["set-flag.fn"])
        // adblock-rust's JSON: no empty dependencies, no default permission.
        let json = String(decoding: try JSONEncoder().encode(resources[1]), as: UTF8.self)
        #expect(!json.contains("dependencies") && !json.contains("permission") && json.contains(#""kind":{"mime":"fn\/javascript"}"#))
    }

    @Test("Room's redirect bodies keep their names; a taken name drops the scriptlet, a taken alias drops the alias")
    func merge() {
        let room = [AdblockResource(name: "noop.js", aliases: ["noopjs", "blank-js"], mime: "application/javascript", content: "")]
        let added = [
            AdblockResource(name: "noop.js", mime: "application/javascript", content: "dWJv"),
            AdblockResource(name: "set-flag.js", aliases: ["blank-js", "sf.js"], mime: "application/javascript", content: ""),
            AdblockResource(name: "other.js", aliases: ["sf.js"], mime: "application/javascript", content: ""),
        ]
        let merged = ScriptletResources.merge(room: room, added: added)
        #expect(merged.map(\.name) == ["noop.js", "set-flag.js", "other.js"])
        #expect(merged[0].content == "" && merged[1].aliases == ["sf.js"] && merged[2].aliases.isEmpty)
    }
}

private actor FetchLog {
    var paths: [String] = []
    func add(_ path: String) { paths.append(path) }
}

/// An index in the shape of uBO's `src/js/redirect-resources.js` (Room's own text).
nonisolated private let redirectIndex = """
/* A licence header. */

export default new Map([
    [ '1x1.gif', {
        alias: '1x1-transparent.gif',
        data: 'blob',
    } ],
    [ 'tagmanager_gtm.js', {
        alias: [
            'tagmanager.example/gtm.js',
            'gtm-stub',
        ],
        data: 'text',
    } ],
    [ 'stub-dai.js', {
        requiresTrust: true,
    } ],
    [ 'click-to-load.html', {
        params: [ 'url' ],
    } ],
    [ 'empty', {
        data: 'text',
    } ],
]);
"""

@Suite("uBlock Origin redirect bodies (B-30)")
struct UBlockRedirectTests {
    @Test("The index gives names and aliases; bodies that need URL parameters are left out")
    func index() throws {
        let entries = try UBlockRedirects.entries(fromIndex: redirectIndex)
        #expect(entries.map(\.name) == ["1x1.gif", "tagmanager_gtm.js", "stub-dai.js", "empty"])
        #expect(entries[1].aliases == ["tagmanager.example/gtm.js", "gtm-stub"] && entries[0].aliases == ["1x1-transparent.gif"])
        #expect(entries[2].requiresTrust && !entries[1].requiresTrust)
    }

    @Test("Bodies come from web_accessible_resources at the pinned tag, by plain file names only")
    func fetchRules() {
        #expect(UBlockRedirects.sourceURL("noop.js").absoluteString
            == "https://raw.githubusercontent.com/gorhill/uBlock/\(UBlockScriptlets.tag)/src/web_accessible_resources/noop.js")
        #expect(UBlockRedirects.sourceURL(UBlockRedirects.index, base: UBlockScriptlets.baseURL) == UBlockScriptlets.sourceURL("redirect-resources.js"))
        #expect(UBlockRedirects.isSafeName("noop-0.1s.mp3") && UBlockRedirects.isSafeName("empty"))
        for name in ["../js/x.js", "a/b.js", ".hidden", "", "x.js?y", "https:x"] {
            #expect(!UBlockRedirects.isSafeName(name), "\(name)")
        }
        #expect(throws: UBlockRedirects.Failure.unsafeName("../x.js")) {
            try UBlockRedirects.entries(fromIndex: "export default new Map([ [ '../x.js', {} ] ]);")
        }
        #expect(throws: UBlockRedirects.Failure.notAnIndex) {
            try UBlockRedirects.entries(fromIndex: "import x from './x.js';\nexport default new Map([]);")
        }
    }

    @Test("MIME types as adblock-rust reads them; a failed body is left out; a trusted body carries the bit")
    func resources() async throws {
        #expect(UBlockRedirects.mime(for: "noop-1s.mp4") == "video/mp4")
        #expect(UBlockRedirects.mime(for: "noop-vast4.xml") == "text/xml")
        #expect(UBlockRedirects.mime(for: "empty") == "text/plain")
        #expect(UBlockRedirects.mime(for: "x.webm") == "application/octet-stream")
        let entries = try UBlockRedirects.entries(fromIndex: redirectIndex)
        let bodies = await UBlockRedirects.bodies(for: entries) { name in
            guard name != "1x1.gif" else { throw URLError(.fileDoesNotExist) }
            return Data(name.utf8)
        }
        let resources = UBlockRedirects.resources(entries, bodies: bodies)
        #expect(resources.map(\.name) == ["tagmanager_gtm.js", "stub-dai.js", "empty"])
        #expect(resources.map(\.permission) == [nil, UBlockScriptlets.trustedPermission, nil])
        #expect(Data(base64Encoded: resources[0].content) == Data("tagmanager_gtm.js".utf8))
    }
}
