import AppKit
import Engine
import FakeEngine
import Testing
@testable import Chrome

/// Two FakeEngine pages whose UI delegate is `PageChrome`; `a` is in the card.
@MainActor
final class PromptsFixture {
    let engine = FakeApplication()
    let chrome = PageChrome()
    let a: FakeWebContents
    let b: FakeWebContents

    init() throws {
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let profile = try engine.profile(named: "Default")
        a = profile.makeWebContents()
        b = profile.makeWebContents()
        for page in [a, b] { page.uiDelegate = chrome }
        a.load(URL(string: "https://a.example/page")!)
        a.load(URL(string: "https://a.example/next")!)
        b.load(URL(string: "https://b.example/")!)
        chrome.prompts.setCurrentPage(a)
    }

    var prompts: PagePrompts { chrome.prompts }

    /// Lets the simulated engine calls (started in tasks) reach the delegate.
    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// Lets work queued on the main queue run.
@MainActor
func waitForMainQueue() async {
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
}

@MainActor
@Suite("The page's dialogs (ROADMAP 2.6 task 2, FakeEngine)")
struct PageDialogTests {
    @Test("Return answers the primary button, Esc the safe one: alert OK, confirm true/false, prompt text/nil")
    func returnAndEscape() async throws {
        let f = try PromptsFixture()
        let confirmYes = Task { await f.a.simulateConfirm("Sure?") }
        await f.settle()
        let dialog = try #require(f.prompts.visibleDialog)
        f.prompts.respond(PromptRules.returnResponse(for: dialog.dialog, text: nil))
        #expect(await confirmYes.value == true)

        let confirmNo = Task { await f.a.simulateConfirm("Sure?") }
        await f.settle()
        f.prompts.respond(PromptRules.escapeResponse(for: try #require(f.prompts.visibleDialog).dialog))
        #expect(await confirmNo.value == false)

        let prompt = Task { await f.a.simulatePrompt("Name?", defaultText: "Ada") }
        await f.settle()
        f.prompts.respond(PromptRules.returnResponse(for: try #require(f.prompts.visibleDialog).dialog, text: "Grace"))
        #expect(await prompt.value == "Grace")

        let cancelled = Task { await f.a.simulatePrompt("Name?") }
        await f.settle()
        f.prompts.respond(PromptRules.escapeResponse(for: try #require(f.prompts.visibleDialog).dialog))
        #expect(await cancelled.value == nil)

        // An alert has one answer; Esc acknowledges it.
        #expect(PromptRules.escapeResponse(for: .alert(message: "", origin: nil)) == .accept(text: nil))
        let alert = Task { await f.a.simulateAlert("Hi") }
        await f.settle()
        f.prompts.respond(PromptRules.escapeResponse(for: try #require(f.prompts.visibleDialog).dialog))
        await alert.value
        #expect(f.prompts.visibleDialog == nil)
    }

    @Test("A dialog from a page not in the card waits for it; the page in the card is not blocked by it")
    func waitsForItsPage() async throws {
        let f = try PromptsFixture()
        var attention: [ObjectIdentifier] = []
        f.prompts.onPageNeedsAttention = { attention.append($0) }
        let alert = Task { await f.b.simulateAlert("From b") }
        await f.settle()
        #expect(f.prompts.visibleDialog == nil)
        #expect(f.prompts.hasPending(ObjectIdentifier(f.b)))
        #expect(attention == [ObjectIdentifier(f.b)])
        f.prompts.setCurrentPage(f.b)
        #expect(f.prompts.visibleDialog?.dialog == .alert(message: "From b", origin: URL(string: "https://b.example")))
        f.prompts.respond(.accept(text: nil))
        await alert.value
        #expect(!f.prompts.hasPending(ObjectIdentifier(f.b)))
    }

    @Test("beforeunload shows at once, whatever the card shows; Stay answers false")
    func beforeUnloadAtOnce() async throws {
        let f = try PromptsFixture()
        var leave: Bool?
        f.chrome.webContents(f.b, runBeforeUnloadDialogForReload: false) { leave = $0 }
        let shown = try #require(f.prompts.visibleDialog)
        #expect(shown.page == ObjectIdentifier(f.b))
        f.prompts.respond(PromptRules.escapeResponse(for: shown.dialog))
        #expect(leave == false)
    }

    @Test("The engine closing JavaScript dialogs drops them unanswered; auth and certificate stay")
    func engineDismissal() async throws {
        let f = try PromptsFixture()
        var answered = 0
        f.chrome.webContents(f.a, runJavaScriptAlert: "x", origin: nil) { answered += 1 }
        f.chrome.webContents(f.a, didReceiveAuthChallenge: AuthChallenge(origin: URL(string: "https://a.example")!, scheme: "Basic")) { _ in
            answered += 1
        }
        f.a.simulateDialogsDismissed()
        #expect(answered == 0)
        #expect(f.prompts.visibleDialog.map { if case .auth = $0.dialog { true } else { false } } == true)
    }

    @Test("From the page's second alert, confirm or prompt on, the dialog offers suppression; checked, the page's dialogs are answered unseen until it loads again (B-116)")
    func suppressionUntilReload() async throws {
        let f = try PromptsFixture()
        var alerts = 0
        f.chrome.webContents(f.a, runJavaScriptAlert: "1", origin: nil) { alerts += 1 }
        #expect(f.prompts.visibleDialog?.offersSuppression == false, "the first dialog does not offer it")
        f.prompts.respond(.accept(text: nil))
        f.chrome.webContents(f.a, runJavaScriptAlert: "2", origin: nil) { alerts += 1 }
        let second = try #require(f.prompts.visibleDialog)
        #expect(second.offersSuppression)
        // A third waits behind the second; checking the box answers both.
        var confirms: [Bool] = []
        f.chrome.webContents(f.a, runJavaScriptConfirm: "3", origin: nil) { confirms.append($0) }
        f.prompts.respond(.accept(text: nil), to: second.id, suppressingFurther: true)
        #expect(alerts == 2 && confirms == [false])
        #expect(f.prompts.visibleDialog == nil)
        // Later ones never show: an alert is acknowledged, a confirm and a prompt cancelled.
        var prompts: [String?] = []
        f.chrome.webContents(f.a, runJavaScriptAlert: "4", origin: nil) { alerts += 1 }
        f.chrome.webContents(f.a, runJavaScriptConfirm: "5", origin: nil) { confirms.append($0) }
        f.chrome.webContents(f.a, runJavaScriptPrompt: "6", defaultText: "x", origin: nil) { prompts.append($0) }
        #expect(alerts == 2, "answered on the next turn, not inside the engine's call")
        await waitForMainQueue()
        #expect(alerts == 3 && confirms == [false, false] && prompts == [nil])
        #expect(f.prompts.visibleDialog == nil && f.prompts.suppressedCount == 4)
        // Another page is not affected; beforeunload is never suppressed.
        f.prompts.setCurrentPage(f.b)
        f.chrome.webContents(f.b, runJavaScriptAlert: "b", origin: nil) {}
        #expect(f.prompts.visibleDialog?.offersSuppression == false)
        f.prompts.respond(.accept(text: nil))
        f.prompts.setCurrentPage(f.a)
        f.chrome.webContents(f.a, runBeforeUnloadDialogForReload: true) { _ in }
        #expect(f.prompts.visibleDialog.map { if case .beforeUnload = $0.dialog { true } else { false } } == true)
        f.prompts.respond(.cancel)
        // The page reloads: its dialogs show again, the count from one.
        f.a.reload()
        await f.settle()
        #expect(!f.prompts.suppressedPages.contains(ObjectIdentifier(f.a)))
        f.chrome.webContents(f.a, runJavaScriptAlert: "7", origin: nil) { alerts += 1 }
        #expect(f.prompts.visibleDialog?.offersSuppression == false)
        f.prompts.respond(.accept(text: nil))
        #expect(alerts == 4)
    }

    @Test("A closed page's prompts are answered once, with the safe answer")
    func closedPageAnswersOnce() async throws {
        let f = try PromptsFixture()
        var confirms: [Bool] = [], credentials: [URLCredential?] = [], permissions: [PermissionResponse] = []
        f.chrome.webContents(f.a, runJavaScriptConfirm: "x", origin: nil) { confirms.append($0) }
        f.chrome.webContents(f.a, didReceiveAuthChallenge: AuthChallenge(origin: URL(string: "https://a.example")!, scheme: "Basic")) {
            credentials.append($0)
        }
        f.chrome.webContents(f.a, willAskForPermission: [PermissionRequest(kind: .geolocation, origin: URL(string: "https://a.example")!)],
                             quietReason: nil) { permissions.append($0) }
        f.chrome.webContentsDidClose(f.a)
        f.chrome.webContentsDidClose(f.a)
        #expect(confirms == [false])
        #expect(credentials.count == 1 && credentials[0] == nil)
        #expect(permissions == [.dismissed])
        #expect(f.prompts.visibleDialog == nil)
    }

    @Test("HTTP auth: Sign In answers the credential for the session, Cancel answers nil")
    func auth() async throws {
        let f = try PromptsFixture()
        let signIn = Task { await f.a.simulateAuthChallenge(realm: "Staff") }
        await f.settle()
        f.prompts.respond(.signIn(user: "ada", password: "lovelace"))
        let credential = try #require(await signIn.value)
        #expect(credential.user == "ada" && credential.password == "lovelace" && credential.persistence == .forSession)
        let cancel = Task { await f.a.simulateAuthChallenge() }
        await f.settle()
        f.prompts.respond(.cancel)
        #expect(await cancel.value == nil)
    }

    @Test("A certificate error proceeds only when it can be bypassed; Go Back answers false and goes back")
    func certificate() async throws {
        let f = try PromptsFixture()
        let hard = Task { await f.a.simulateCertificateError(isOverridable: false) }
        await f.settle()
        #expect(!PromptRules.allowsProceed(try #require(f.prompts.visibleDialog).dialog))
        f.prompts.respond(.proceed)
        #expect(f.prompts.visibleDialog != nil, "proceeding is refused and the interstitial stays")
        #expect(f.a.canGoBack)
        f.prompts.respond(.cancel)
        #expect(await hard.value == false)
        #expect(f.a.url == URL(string: "https://a.example/page"))

        let soft = Task { await f.a.simulateCertificateError(isOverridable: true) }
        await f.settle()
        f.prompts.respond(.proceed)
        #expect(await soft.value == true)
    }
}

@MainActor
@Suite("Permission prompts (ROADMAP 2.6 task 2, FakeEngine)")
struct PermissionPromptTests {
    @Test("Allow, Allow This Time, Don't Allow and closing answer granted, grantedOnce, denied, dismissed")
    func answers() async throws {
        let f = try PromptsFixture()
        for response in [PermissionResponse.granted, .grantedOnce, .denied, .dismissed] {
            let asked = Task { await f.a.simulatePermissionRequest([.camera, .microphone]) }
            await f.settle()
            #expect(f.prompts.visiblePermission?.requests.map(\.kind) == [.camera, .microphone])
            f.prompts.respondToPermission(response)
            #expect(await asked.value == response)
        }
    }

    @Test("A prompt waits for its page and for the page's dialog; the engine withdrawing it drops it unanswered")
    func waitsAndWithdraws() async throws {
        let f = try PromptsFixture()
        var answers: [PermissionResponse] = []
        f.chrome.webContents(f.b, willAskForPermission: [PermissionRequest(kind: .notifications, origin: URL(string: "https://b.example")!)],
                             quietReason: nil) { answers.append($0) }
        #expect(f.prompts.visiblePermission == nil)
        f.prompts.setCurrentPage(f.b)
        #expect(f.prompts.visiblePermission != nil)
        // A dialog on the page comes first.
        f.chrome.webContents(f.b, runJavaScriptAlert: "x", origin: nil) {}
        #expect(f.prompts.visiblePermission == nil)
        f.prompts.respond(.accept(text: nil))
        #expect(f.prompts.visiblePermission != nil)
        f.b.simulatePermissionPromptDismissed()
        #expect(f.prompts.visiblePermission == nil)
        #expect(answers.isEmpty)
    }

    @Test("Allow This Time is offered for camera, microphone and location only")
    func oneTimeGrant() {
        let origin = URL(string: "https://a.example")!
        #expect(PromptRules.offersOneTimeGrant([.init(kind: .camera, origin: origin), .init(kind: .microphone, origin: origin)]))
        #expect(PromptRules.offersOneTimeGrant([.init(kind: .geolocation, origin: origin)]))
        #expect(!PromptRules.offersOneTimeGrant([.init(kind: .notifications, origin: origin)]))
    }
}

@MainActor
@Suite("Links to other applications (3.4b, FakeEngine)")
struct ExternalAppTests {
    @Test("The first link of a scheme asks; after Open the scheme opens without asking; a refusal asks again")
    func confirmOncePerScheme() async throws {
        let f = try PromptsFixture()
        let mail = URL(string: "mailto:someone@example.com")!

        // Refused: blocked, and the next link of that scheme asks again.
        let refused = Task { await f.a.simulateExternalURL(mail) }
        await f.settle()
        guard case .externalApp(let request)? = f.prompts.visibleDialog?.dialog else {
            Issue.record("no confirmation")
            return
        }
        #expect(request.scheme == "mailto")
        f.prompts.respond(.cancel)
        #expect(await refused.value == false)

        let opened = Task { await f.a.simulateExternalURL(mail) }
        await f.settle()
        #expect(f.prompts.visibleDialog != nil)
        f.prompts.respond(.accept(text: nil))
        #expect(await opened.value == true)

        // The same scheme again, from another page too: no question.
        #expect(await f.a.simulateExternalURL(URL(string: "mailto:other@example.com")!) == true)
        #expect(await f.b.simulateExternalURL(mail) == true)
        #expect(f.prompts.visibleDialog == nil)

        // Another scheme asks.
        let other = Task { await f.a.simulateExternalURL(URL(string: "roomtest://x")!, applicationName: "Room Test") }
        await f.settle()
        #expect(f.prompts.visibleDialog != nil)
        f.prompts.respond(.cancel)
        #expect(await other.value == false)
        #expect(f.a.openedExternalURLs.count == 2)
    }
}
