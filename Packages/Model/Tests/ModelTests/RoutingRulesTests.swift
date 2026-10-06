import Foundation
import Testing
@testable import Model

@Suite("Rule: space routing matching (§B)")
struct RoutingMatchTests {
    let work = UUID(), home = UUID()

    @Test("contains matches anywhere in the full URL, ignoring case")
    func contains() {
        let rule = RoutingRule(match: .contains, pattern: "GitHub.com/room", targetSpaceID: work)
        #expect(RoutingRules.firstMatch([rule], url: "https://github.com/Room/issues") == rule)
        #expect(RoutingRules.firstMatch([rule], url: "https://gist.github.com/x?q=github.com/room") == rule, "the query counts too")
        #expect(RoutingRules.firstMatch([rule], url: "https://gitlab.com/room") == nil)
    }

    @Test("equals compares the host exactly, ignoring case and www. on either side",
          arguments: [
              ("example.com", "https://example.com/a", true),
              ("example.com", "https://WWW.Example.com/", true),
              ("www.example.com", "http://example.com:8080/x", true),
              ("https://example.com/whatever", "https://example.com/", true),
              ("example.com/", "https://example.com/", true),
              ("example.com", "https://docs.example.com/", false),
              ("example.com", "https://example.com.evil.org/", false),
              ("docs.example.com", "https://example.com/docs.example.com", false),
          ])
    func equals(_ pattern: String, _ url: String, _ matches: Bool) {
        let rule = RoutingRule(match: .equals, pattern: pattern, targetSpaceID: work)
        #expect((RoutingRules.firstMatch([rule], url: url) != nil) == matches)
    }

    @Test("regex runs over the full URL")
    func regex() {
        let rule = RoutingRule(match: .regex, pattern: #"^https://[a-z]+\.atlassian\.net/browse/[A-Z]+-\d+"#, targetSpaceID: work)
        #expect(RoutingRules.firstMatch([rule], url: "https://room.atlassian.net/browse/RM-42") == rule)
        #expect(RoutingRules.firstMatch([rule], url: "http://room.atlassian.net/browse/RM-42") == nil)
    }

    @Test("The first enabled match in position order wins; disabled rules are skipped")
    func order() {
        let late = RoutingRule(match: .contains, pattern: "example", targetSpaceID: home, position: 2)
        let early = RoutingRule(match: .equals, pattern: "example.com", targetSpaceID: work, position: 1)
        let off = RoutingRule(match: .contains, pattern: "example", targetSpaceID: home, position: 0, enabled: false)
        #expect(RoutingRules.firstMatch([late, early, off], url: "https://example.com/") == early)
        #expect(RoutingRules.firstMatch([late, early, off], url: "https://example.org/") == late)
        #expect(RoutingRules.firstMatch([off], url: "https://example.com/") == nil)
    }

    @Test("An invalid regex is refused at entry with a message, and never matches if one is stored")
    func invalidRegex() throws {
        let error = try #require(RoutingRules.validate(.regex, pattern: "([a-z"))
        guard case .invalidRegex = error else { Issue.record("expected invalidRegex, got \(error)"); return }
        #expect(error.message.hasPrefix("Not a valid regular expression"))
        #expect(RoutingRules.validate(.regex, pattern: #"^https://a\.example/"#) == nil)
        // The same text is a fine `contains` pattern.
        #expect(RoutingRules.validate(.contains, pattern: "([a-z") == nil)
        #expect(RoutingRules.validate(.equals, pattern: "  ") == .empty)
        let broken = RoutingRule(match: .regex, pattern: "([a-z", targetSpaceID: work, position: 0)
        let next = RoutingRule(match: .contains, pattern: "a", targetSpaceID: home, position: 1)
        #expect(RoutingRules.firstMatch([broken, next], url: "https://a.example/") == next)
    }
}

@Suite("Rule: where a link opens (§B)")
struct RoutingDecisionTests {
    let work = UUID(), home = UUID(), play = UUID()
    let rules: [RoutingRule]
    var spaces: Set<UUID> { [work, home, play] }

    init() {
        rules = [RoutingRule(match: .contains, pattern: "github", targetSpaceID: work, position: 0),
                 RoutingRule(match: .equals, pattern: "youtube.com", targetSpaceID: play, position: 1)]
    }

    @Test("External: a matching rule names the space")
    func externalRule() {
        let decision = RoutingRules.route("https://github.com/x", from: .external, rules: rules, settings: Settings(),
                                          spaces: spaces, mostRecentSpace: home)
        #expect(decision == .init(space: work, reason: .rule(rules[0].id), moved: false))
    }

    @Test("External, no rule: the most recent space by default, else the chosen one while it exists")
    func externalDefault() {
        var settings = Settings()
        #expect(RoutingRules.route("https://example.com/", from: .external, rules: rules, settings: settings, spaces: spaces,
                                   mostRecentSpace: home) == .init(space: home, reason: .mostRecentSpace, moved: false))
        settings.externalLinksSpaceID = play
        #expect(RoutingRules.route("https://example.com/", from: .external, rules: rules, settings: settings, spaces: spaces,
                                   mostRecentSpace: home) == .init(space: play, reason: .chosenDefault, moved: false))
        settings.externalLinksSpaceID = UUID()
        #expect(RoutingRules.route("https://example.com/", from: .external, rules: rules, settings: settings, spaces: spaces,
                                   mostRecentSpace: home)?.reason == .mostRecentSpace, "a deleted chosen space counts as none")
        #expect(RoutingRules.route("https://example.com/", from: .external, rules: [], settings: Settings(), spaces: spaces,
                                   mostRecentSpace: nil) == nil)
    }

    @Test("A rule whose space is gone is skipped")
    func ruleForMissingSpace() {
        let decision = RoutingRules.route("https://github.com/x", from: .external, rules: rules, settings: Settings(),
                                          spaces: [home, play], mostRecentSpace: home)
        #expect(decision?.reason == .mostRecentSpace)
    }

    @Test("From a page: off by default, the link stays in its space")
    func pageOff() {
        let decision = RoutingRules.route("https://github.com/x", from: .page(space: home), rules: rules, settings: Settings(),
                                          spaces: spaces, mostRecentSpace: home)
        #expect(decision == .init(space: home, reason: .sourceSpace, moved: false))
    }

    @Test("From a page with routing on: a rule for another space moves it; a rule for its own space or no rule keeps it")
    func pageOn() {
        var settings = Settings()
        settings.routeLinksBetweenSpaces = true
        #expect(RoutingRules.route("https://github.com/x", from: .page(space: home), rules: rules, settings: settings,
                                   spaces: spaces, mostRecentSpace: home) == .init(space: work, reason: .rule(rules[0].id), moved: true))
        #expect(RoutingRules.route("https://github.com/x", from: .page(space: work), rules: rules, settings: settings,
                                   spaces: spaces, mostRecentSpace: home) == .init(space: work, reason: .sourceSpace, moved: false))
        #expect(RoutingRules.route("https://example.com/", from: .page(space: home), rules: rules, settings: settings,
                                   spaces: spaces, mostRecentSpace: play) == .init(space: home, reason: .sourceSpace, moved: false),
                "no rule: the external default does not apply to page links")
    }
}
