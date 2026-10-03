import Engine
import Foundation
import Testing
@testable import Tabs

@Suite("Sites (eTLD+1, spec §A.4)")
struct SiteRulesTests {
    @Test("Registrable domains by the Public Suffix List, private section included",
          arguments: [("www.example.com", "example.com"), ("a.b.example.co.uk", "example.co.uk"), ("example.co.uk", "example.co.uk"),
                      ("room.github.io", "room.github.io"), ("docs.room.github.io", "room.github.io"), ("www.ck", "www.ck"),
                      ("a.b.ck", "a.b.ck"), ("localhost", "localhost"), ("127.0.0.1", "127.0.0.1"), ("Developer.Apple.COM.", "apple.com")])
    func site(host: String, expected: String) {
        #expect(SiteRules.site(ofHost: host) == expected)
    }

    @Test("Same site: subdomains of one registrable domain; not across public suffixes or IPs")
    func sameSite() {
        #expect(SiteRules.isSameSite(URL(string: "https://mail.google.com/x")!, URL(string: "https://www.google.com")!))
        #expect(!SiteRules.isSameSite(URL(string: "https://a.github.io")!, URL(string: "https://b.github.io")!))
        #expect(!SiteRules.isSameSite(URL(string: "http://127.0.0.1:8770/")!, URL(string: "http://localhost:8770/")!))
        #expect(!SiteRules.isSameSite(URL(string: "about:blank")!, URL(string: "about:blank")!))
    }
}

@Suite("Peek's off-site rule (spec §A.4, §I.6)")
struct PeekRulesTests {
    let home = URL(string: "https://news.example.com/today")!
    let article = URL(string: "https://www.other.org/story")!

    func link(_ url: URL, disposition: Disposition = .currentTab, gesture: Bool = true, redirect: Bool = false,
              clientRedirect: Bool = false, kind: NavigationAction.Kind = .linkActivated) -> NavigationAction {
        NavigationAction(url: url, kind: kind, transition: kind == .formSubmitted ? .formSubmit : .link, disposition: disposition,
                         isUserGesture: gesture, isRedirect: redirect, isClientRedirect: clientRedirect)
    }

    func pinned(hovered: URL?, since: TimeInterval? = 0.1) -> PeekRules.Context {
        PeekRules.Context(isPermanentEntry: true, currentURL: home, hoveredLink: hovered, secondsSinceUserInput: since)
    }

    @Test("A click on a link to another site from a permanent entry opens in Peek")
    func offSiteClick() {
        #expect(PeekRules.decision(for: link(article), context: pinned(hovered: article)) == .peek)
        // The fragment and a trailing slash do not make it another link.
        #expect(PeekRules.decision(for: link(URL(string: "https://www.other.org/story/")!), context: pinned(hovered: URL(string: "https://www.other.org/story#top")!)) == .peek)
    }

    @Test("Same site, Today tabs and the setting off navigate in place")
    func inPlace() {
        let sameSite = URL(string: "https://www.example.com/sports")!
        #expect(PeekRules.decision(for: link(sameSite), context: pinned(hovered: sameSite)) == .asRequested)
        let today = PeekRules.Context(isPermanentEntry: false, currentURL: home, hoveredLink: article)
        #expect(PeekRules.decision(for: link(article), context: today) == .asRequested)
        var off = pinned(hovered: article)
        off.isEnabled = false
        #expect(PeekRules.decision(for: link(article), context: off) == .asRequested)
    }

    @Test("Form posts, redirect chains, client redirects, typed and script navigations without a gesture stay in place")
    func exemptions() {
        #expect(PeekRules.decision(for: link(article, kind: .formSubmitted), context: pinned(hovered: nil)) == .asRequested)
        #expect(PeekRules.decision(for: link(article, redirect: true), context: pinned(hovered: article)) == .asRequested)
        #expect(PeekRules.decision(for: link(article, clientRedirect: true), context: pinned(hovered: nil)) == .asRequested)
        #expect(PeekRules.decision(for: link(article, gesture: false), context: pinned(hovered: article)) == .asRequested)
        #expect(PeekRules.decision(for: link(article, kind: .other), context: pinned(hovered: article)) == .asRequested)
        #expect(PeekRules.decision(for: link(URL(string: "mailto:a@b.c")!), context: pinned(hovered: nil)) == .asRequested)
    }

    @Test("OAuth requests and identity providers' sign-in pages stay in place")
    func loginFlows() {
        let oauth = URL(string: "https://accounts.provider.com/o/oauth2/auth?client_id=x&redirect_uri=https%3A%2F%2Fnews.example.com%2Fcb&response_type=code")!
        #expect(PeekRules.decision(for: link(oauth), context: pinned(hovered: oauth)) == .asRequested)
        let signIn = URL(string: "https://login.provider.com/signin?continue=x")!
        #expect(PeekRules.decision(for: link(signIn), context: pinned(hovered: signIn)) == .asRequested)
        #expect(!PeekRules.isLoginFlow(article))
    }

    @Test("window.location set within 2 s of a gesture navigates in place; later it peeks")
    func scriptAfterGesture() {
        #expect(PeekRules.decision(for: link(article), context: pinned(hovered: nil, since: 0.3)) == .asRequested)
        #expect(PeekRules.decision(for: link(article), context: pinned(hovered: URL(string: "https://elsewhere.net")!, since: 1.9)) == .asRequested)
        #expect(PeekRules.decision(for: link(article), context: pinned(hovered: nil, since: nil)) == .asRequested)
        #expect(PeekRules.decision(for: link(article), context: pinned(hovered: nil, since: 2.5)) == .peek)
    }

    @Test("⇧-click opens Peek from any page")
    func shiftClick() {
        let today = PeekRules.Context(isPermanentEntry: false, currentURL: home, hoveredLink: article)
        #expect(PeekRules.decision(for: link(article, disposition: .newWindow), context: today) == .peek)
        #expect(PeekRules.decision(for: link(article, disposition: .newBackgroundTab), context: pinned(hovered: article)) == .asRequested)
    }
}
