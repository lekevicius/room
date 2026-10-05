import Engine
import FakeEngine
import Foundation
import Testing
@testable import Tabs

@Suite("Sites (eTLD+1, spec §A.4), through the engine's site(of:)")
struct SiteRulesTests {
    let engine = FakeApplication()

    @Test("Registrable domains by the Public Suffix List, private section included",
          arguments: [("www.example.com", "example.com"), ("a.b.example.co.uk", "example.co.uk"), ("example.co.uk", "example.co.uk"),
                      ("room.github.io", "room.github.io"), ("docs.room.github.io", "room.github.io"), ("www.ck", "www.ck"),
                      ("a.b.ck", "a.b.ck"), ("localhost", "localhost"), ("127.0.0.1", "127.0.0.1"), ("Developer.Apple.COM.", "apple.com")])
    func site(host: String, expected: String) {
        #expect(engine.site(of: URL(string: "https://\(host)/")!) == expected)
    }

    @Test("Same site: subdomains of one registrable domain; not across public suffixes or IPs")
    func sameSite() {
        #expect(engine.isSameSite(URL(string: "https://mail.google.com/x")!, URL(string: "https://www.google.com")!))
        #expect(!engine.isSameSite(URL(string: "https://a.github.io")!, URL(string: "https://b.github.io")!))
        #expect(!engine.isSameSite(URL(string: "http://127.0.0.1:8770/")!, URL(string: "http://localhost:8770/")!))
        #expect(!engine.isSameSite(URL(string: "about:blank")!, URL(string: "about:blank")!))
    }
}

@Suite("Peek's off-site rule (spec §A.4, §I.6)")
struct PeekRulesTests {
    let home = URL(string: "https://news.example.com/today")!
    let article = URL(string: "https://www.other.org/story")!
    let engine = FakeApplication()

    func link(_ url: URL, disposition: Disposition = .currentTab, gesture: Bool = true, redirect: Bool = false,
              clientRedirect: Bool = false, kind: NavigationAction.Kind = .linkActivated,
              transition: PageTransition? = nil) -> NavigationAction {
        NavigationAction(url: url, kind: kind, transition: transition ?? (kind == .formSubmitted ? .formSubmit : .link),
                         disposition: disposition, isUserGesture: gesture, isRedirect: redirect, isClientRedirect: clientRedirect)
    }

    /// The page's script setting `window.location`: not a link (B-33).
    func script(_ url: URL) -> NavigationAction { link(url, kind: .other) }

    func pinned(since: TimeInterval? = 0.1) -> PeekRules.Context {
        PeekRules.Context(isPermanentEntry: true, currentURL: home, secondsSinceUserInput: since)
    }

    func decide(_ action: NavigationAction, _ context: PeekRules.Context) -> PeekDecision {
        PeekRules.decision(for: action, context: context) { engine.isSameSite($0, $1) }
    }

    @Test("A click on a link to another site from a permanent entry opens in Peek, however recent the input")
    func offSiteClick() {
        #expect(decide(link(article), pinned()) == .peek)
        #expect(decide(link(article), pinned(since: nil)) == .peek)
    }

    @Test("Same site, Today tabs and the setting off navigate in place")
    func inPlace() {
        #expect(decide(link(URL(string: "https://www.example.com/sports")!), pinned()) == .asRequested)
        let today = PeekRules.Context(isPermanentEntry: false, currentURL: home)
        #expect(decide(link(article), today) == .asRequested)
        var off = pinned()
        off.isEnabled = false
        #expect(decide(link(article), off) == .asRequested)
    }

    @Test("Form posts, redirect chains, client redirects, typed loads and clicks without a gesture stay in place")
    func exemptions() {
        #expect(decide(link(article, kind: .formSubmitted), pinned()) == .asRequested)
        #expect(decide(link(article, redirect: true), pinned()) == .asRequested)
        #expect(decide(link(article, clientRedirect: true), pinned(since: 5)) == .asRequested)
        #expect(decide(link(article, gesture: false), pinned()) == .asRequested)
        #expect(decide(link(article, kind: .other, transition: .typed), pinned(since: 5)) == .asRequested)
        #expect(decide(link(URL(string: "mailto:a@b.c")!), pinned()) == .asRequested)
    }

    @Test("OAuth requests and identity providers' sign-in pages stay in place")
    func loginFlows() {
        let oauth = URL(string: "https://accounts.provider.com/o/oauth2/auth?client_id=x&redirect_uri=https%3A%2F%2Fnews.example.com%2Fcb&response_type=code")!
        #expect(decide(link(oauth), pinned()) == .asRequested)
        #expect(decide(link(URL(string: "https://login.provider.com/signin?continue=x")!), pinned()) == .asRequested)
        #expect(!PeekRules.isLoginFlow(article))
    }

    @Test("window.location set within 2 s of a gesture navigates in place; later it peeks (a script is never a link click, B-33)")
    func scriptAfterGesture() {
        #expect(decide(script(article), pinned(since: 0.3)) == .asRequested)
        #expect(decide(script(article), pinned(since: 1.9)) == .asRequested)
        #expect(decide(script(article), pinned(since: nil)) == .asRequested)
        #expect(decide(script(article), pinned(since: 2.5)) == .peek)
    }

    @Test("⇧-click opens Peek from any page")
    func shiftClick() {
        let today = PeekRules.Context(isPermanentEntry: false, currentURL: home)
        #expect(decide(link(article, disposition: .newWindow), today) == .peek)
        #expect(decide(link(article, disposition: .newBackgroundTab), pinned()) == .asRequested)
        #expect(decide(link(article, disposition: .newWindow, kind: .other), today) == .asRequested)
    }
}
