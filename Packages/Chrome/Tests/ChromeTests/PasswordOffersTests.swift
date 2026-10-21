import AppKit
import Engine
import FakeEngine
import Testing
@testable import Chrome

/// The password popover's rules (ROADMAP 5.8 task 2) on FakeEngine pages
/// whose UI delegate is `PageChrome`; `a` (127.0.0.1:8772) is in the card.
@MainActor
@Suite("The password save and update popover (5.8a, FakeEngine)")
struct PasswordOfferTests {
    final class Fixture {
        let engine = FakeApplication()
        let chrome = PageChrome()
        let profile: FakeProfile
        let a: FakeWebContents
        let b: FakeWebContents
        var toasts: [Toast] = []
        var managerOpened = 0

        init() throws {
            try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
            profile = try engine.profile(named: "Default")
            a = profile.makeWebContents()
            b = profile.makeWebContents()
            for page in [a, b] { page.uiDelegate = chrome }
            a.load(URL(string: "http://127.0.0.1:8772/login.html")!)
            b.load(URL(string: "http://localhost:8772/login.html")!)
            chrome.prompts.setCurrentPage(a)
            chrome.showNotice = { [unowned self] in self.toasts.append($0) }
            chrome.openPasswordManager = { [unowned self] in self.managerOpened += 1 }
        }

        var prompts: PagePrompts { chrome.prompts }

        func settle() async {
            for _ in 0..<10 { await Task.yield() }
        }

        /// Submits on `page`, waits for the popover's offer, answers it with `response`.
        func submit(_ page: FakeWebContents, _ username: String, _ password: String,
                    answer response: PasswordOfferResponse) async throws -> FakeWebContents.PasswordSubmitOutcome {
            let submit = Task { await page.simulatePasswordSubmit(username: username, password: password) }
            await settle()
            let offer = try #require(prompts.visiblePasswordOffer)
            prompts.respondToPasswordOffer(response, to: offer.id)
            return await submit.value
        }
    }

    @Test("Return and Enter save, Esc and a click elsewhere answer Not Now, Manage closes without saving; other keys answer nothing")
    func keys() {
        #expect(PasswordOfferRules.response(forKeyCode: 36) == .save)
        #expect(PasswordOfferRules.response(forKeyCode: 76) == .save)
        #expect(PasswordOfferRules.response(forKeyCode: 53) == .notNow)
        #expect(PasswordOfferRules.response(forKeyCode: 49) == nil)
        #expect(PasswordOfferRules.closeResponse == .notNow)
        #expect(PasswordOfferRules.manageResponse == .notNow)
    }

    @Test("Save stores the password, confirms it with a toast whose Manage opens the password manager; the offer shows a mask")
    func saveConfirms() async throws {
        let f = try Fixture()
        let submit = Task { await f.a.simulatePasswordSubmit(username: "ada", password: "hunter2") }
        await f.settle()
        let offer = try #require(f.prompts.visiblePasswordOffer)
        #expect(offer.offer.kind == .save)
        #expect(offer.offer.origin == URL(string: "http://127.0.0.1:8772"))
        #expect(offer.offer.username == "ada")
        #expect(offer.offer.maskedPassword == "•••••••")
        #expect(PasswordOfferRules.title(offer.offer) == "Save password for “127.0.0.1”?")
        f.prompts.respondToPasswordOffer(try #require(PasswordOfferRules.response(forKeyCode: 36)))
        #expect(await submit.value == .answered(.save, .save))
        #expect(f.profile.savedPasswords == [.init(site: "http://127.0.0.1:8772", username: "ada", password: "hunter2")])
        let toast = try #require(f.toasts.last)
        #expect(toast.id == PasswordOfferRules.confirmationToastID)
        #expect(toast.message == "Password saved for 127.0.0.1")
        toast.action?.handler()
        #expect(f.managerOpened == 1)
        #expect(PasswordOfferRules.managerURL.absoluteString == "chrome://password-manager")
    }

    @Test("Never for this site is recorded per origin: that origin offers no more, another still does")
    func neverPerOrigin() async throws {
        let f = try Fixture()
        #expect(try await f.submit(f.a, "ada", "hunter2", answer: .never) == .answered(.save, .never))
        #expect(f.profile.neverSavePasswordSites == ["http://127.0.0.1:8772"])
        #expect(f.profile.savedPasswords.isEmpty)
        #expect(f.toasts.isEmpty)
        // The same origin again, another username: nothing reaches the popover.
        #expect(await f.a.simulatePasswordSubmit(username: "grace", password: "s3cret") == .neverForSite)
        #expect(f.prompts.visiblePasswordOffer == nil)
        // The other origin still asks.
        f.prompts.setCurrentPage(f.b)
        #expect(try await f.submit(f.b, "ada", "hunter2", answer: .save) == .answered(.save, .save))
        #expect(f.profile.savedPasswords.map(\.site) == ["http://localhost:8772"])
    }

    @Test("Not Now records nothing: the next submit offers again")
    func notNowAsksAgain() async throws {
        let f = try Fixture()
        #expect(try await f.submit(f.a, "ada", "hunter2", answer: .notNow) == .answered(.save, .notNow))
        #expect(f.profile.neverSavePasswordSites.isEmpty && f.profile.savedPasswords.isEmpty && f.toasts.isEmpty)
        #expect(try await f.submit(f.a, "ada", "hunter2", answer: .save) == .answered(.save, .save))
    }

    @Test("A changed password is an update: Update replaces it; an update offers no Never (answered so, it is Not Now)")
    func update() async throws {
        let f = try Fixture()
        f.profile.savedPasswords = [.init(site: "http://127.0.0.1:8772", username: "ada", password: "old")]
        #expect(!PasswordOfferRules.offersNever(.update) && PasswordOfferRules.offersNever(.save))
        #expect(try await f.submit(f.a, "ada", "newer", answer: .never) == .answered(.update, .notNow))
        #expect(f.profile.neverSavePasswordSites.isEmpty)
        #expect(try await f.submit(f.a, "ada", "newer", answer: .save) == .answered(.update, .save))
        #expect(f.profile.savedPasswords.first?.password == "newer")
        #expect(f.toasts.last?.message == "Password updated for 127.0.0.1")
        // The same password again: nothing to offer.
        #expect(await f.a.simulatePasswordSubmit(username: "ada", password: "newer") == .alreadySaved)
    }

    @Test("A background page's offer waits for the card; a withdrawn offer goes unanswered; a closed page's is Not Now")
    func waitsWithdrawnClosed() async throws {
        let f = try Fixture()
        let background = Task { await f.b.simulatePasswordSubmit(username: "ada", password: "pw") }
        await f.settle()
        #expect(f.prompts.visiblePasswordOffer == nil)
        f.prompts.setCurrentPage(f.b)
        #expect(f.prompts.visiblePasswordOffer?.offer.origin == URL(string: "http://localhost:8772"))
        f.b.simulatePasswordOfferWithdrawn()
        #expect(f.prompts.visiblePasswordOffer == nil)
        #expect(await background.value == .withdrawn)

        f.prompts.setCurrentPage(f.a)
        let closing = Task { await f.a.simulatePasswordSubmit(username: "ada", password: "pw") }
        await f.settle()
        f.prompts.pageClosed(f.a)
        #expect(await closing.value == .answered(.save, .notNow))
    }

    @Test("A generated password the engine saved itself gets the same confirmation, and the engine shows none")
    func automaticSave() throws {
        let f = try Fixture()
        #expect(f.a.simulateAutomaticPasswordSave(username: "ada", password: "Xy7-generated"))
        #expect(f.toasts.last?.message == "Password saved for 127.0.0.1")
    }
}
