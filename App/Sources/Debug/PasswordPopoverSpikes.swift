#if DEBUG
import AppKit
import Chrome
import Engine
import UIKitCore

/// Phase 5.8a spike `passwordpopover` (`scripts/password-popover-check.sh`):
/// the host's password popover, fired through the page's UI delegate (the
/// tab controller, then the window's page delegate) with the members RoomCore
/// will call once the `//room` adapter lands, on the 3.7a sign-in fixture
/// (`http://127.0.0.1:8776/phase-3.7/login.html`, scripts/test-servers.sh).
/// Return saves (the confirmation toast), Esc answers Not Now, Never for
/// This Site, the update offer (no Never), Manage Passwords (a tab with
/// `chrome://password-manager`), the popover with the sidebar hidden (the
/// card's corner), a withdrawn offer, the engine's own saved confirmation.
/// `-RoomSpikeCaptureDirectory` keeps in-process captures named
/// `phase-5.8a-<name>-<appearance>.png`; `-RoomSpikeAppearance dark`.
@MainActor private final class OfferAnswers {
    var responses: [PasswordOfferResponse] = []
}

extension SpikeRunner.Context {
    private var passwordAppearance: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }
    private static let passwordFixture = URL(string: "http://127.0.0.1:8776/phase-3.7/login.html")!

    func passwordPopoverChecks() async {
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        NSApp.appearance = NSAppearance(named: passwordAppearance == "dark" ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1200, height: 780))
        window.center()
        controller.sidebarWidth = 280
        controller.isSidebarOpen = true
        controller.activityOverride = true
        await activate()
        SpikeRunner.record("conditions", "load=\(SpikeRunner.loadAverage()) appearance=\(passwordAppearance) app=\(Bundle.main.bundlePath)")
        guard let page = await open(Self.passwordFixture) else { return SpikeRunner.record("error", "no page for the fixture") }
        SpikeRunner.record("fixture", "url=\(page.url?.absoluteString ?? "nil") title=\(page.title ?? "nil")")
        let origin = URL(string: "http://127.0.0.1:8776")!
        let save = PasswordOffer(kind: .save, origin: origin, username: "ada@example.com", maskedPassword: PasswordOffer.mask(length: 9))
        let update = PasswordOffer(kind: .update, origin: origin, username: "ada@example.com", maskedPassword: PasswordOffer.mask(length: 11))

        // Return saves; the confirmation toast offers Manage.
        let answers = OfferAnswers()
        var line = await passwordOffer(save, on: page, answers: answers, capture: "password-save")
        let (returnKey, _) = passwordKey(36, "\r")
        _ = await waitUntil(3) { answers.responses.count == 1 }
        let toast = passwordToasts?.currentToast
        line += " Return(\(returnKey))=\(answers.responses.last.map { "\($0)" } ?? "none") popover closed=\(presenter?.passwordOfferView == nil)"
            + " toast=\"\(toast?.message ?? "none")\" action=\(toast?.action?.title ?? "none")"
        SpikeRunner.record("password_save_return", line)
        try? await Task.sleep(for: .milliseconds(400))
        passwordCapture("password-saved-toast")
        if let id = toast?.id { passwordToasts?.dismiss(id: id) }

        // Esc: Not Now, no toast.
        line = await passwordOffer(save, on: page, answers: answers, capture: nil)
        let (escKey, _) = passwordKey(53, "\u{1b}")
        _ = await waitUntil(3) { answers.responses.count == 2 }
        line += " Esc(\(escKey))=\(answers.responses.last.map { "\($0)" } ?? "none") popover closed=\(presenter?.passwordOfferView == nil)"
            + " toast=\(passwordToasts?.currentToast?.id ?? "none")"
        SpikeRunner.record("password_save_escape", line)

        // Never for This Site.
        line = await passwordOffer(save, on: page, answers: answers, capture: nil)
        let never = button(identifier: "password-offer-never", in: presenter?.passwordOfferView)
        never?.performClick(nil)
        _ = await waitUntil(3) { answers.responses.count == 3 }
        line += " never button=\(never != nil) answer=\(answers.responses.last.map { "\($0)" } ?? "none")"
        SpikeRunner.record("password_never", line)

        // The update offer: Update is the default, no Never.
        line = await passwordOffer(update, on: page, answers: answers, capture: "password-update")
        let updateButton = button(identifier: "password-offer-save", in: presenter?.passwordOfferView)
        line += " primary=\"\(updateButton?.title ?? "none")\" default=\(updateButton?.keyEquivalent == "\r")"
            + " never offered=\(button(identifier: "password-offer-never", in: presenter?.passwordOfferView) != nil)"
        updateButton?.performClick(nil)
        _ = await waitUntil(3) { answers.responses.count == 4 }
        line += " answer=\(answers.responses.last.map { "\($0)" } ?? "none") toast=\"\(passwordToasts?.currentToast?.message ?? "none")\""
        SpikeRunner.record("password_update", line)
        if let id = passwordToasts?.currentToast?.id { passwordToasts?.dismiss(id: id) }

        // Manage Passwords: Not Now and Chrome's manager as a tab, selected.
        line = await passwordOffer(save, on: page, answers: answers, capture: nil)
        let before = session.tabs.currentEntryID
        button(identifier: "password-offer-manage", in: presenter?.passwordOfferView)?.performClick(nil)
        _ = await waitUntil(3) { answers.responses.count == 5 }
        _ = await waitUntil(8) { self.session.tabs.current?.url?.scheme == "chrome" }
        let manager = session.tabs.current
        line += " answer=\(answers.responses.last.map { "\($0)" } ?? "none") new tab=\(session.tabs.currentEntryID != before)"
            + " url=\(manager?.url?.absoluteString ?? "nil") title=\(manager?.title ?? "nil")"
        SpikeRunner.record("password_manage", line)
        try? await Task.sleep(for: .milliseconds(800))
        passwordCapture("password-manager-tab")

        // Back to the fixture; the sidebar hidden: the card's top-left corner.
        if let entry = session.tabs.entryID(for: page) { session.sidebar.select(entry) }
        _ = await waitUntil(3) { self.session.tabs.current === page }
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(600))
        line = await passwordOffer(save, on: page, answers: answers, capture: "password-save-sidebar-hidden")
        _ = passwordKey(53, "\u{1b}")
        _ = await waitUntil(3) { answers.responses.count == 6 }
        SpikeRunner.record("password_sidebar_hidden", line + " Esc=\(answers.responses.last.map { "\($0)" } ?? "none")")
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(400))

        // The engine withdraws the offer: the popover goes, no answer.
        line = await passwordOffer(save, on: page, answers: answers, capture: nil)
        page.uiDelegate?.webContentsDidWithdrawPasswordOffer(page)
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("password_withdrawn", line + " popover closed=\(presenter?.passwordOfferView == nil) answers=\(answers.responses.count) (6 expected)")

        // The engine's own saved confirmation (a generated password).
        let confirmed = page.uiDelegate?.webContents(page, didSavePassword: save) ?? false
        SpikeRunner.record("password_automatic_save", "host confirmed=\(confirmed) toast=\"\(passwordToasts?.currentToast?.message ?? "none")\"")
        if let id = passwordToasts?.currentToast?.id { passwordToasts?.dismiss(id: id) }
        SpikeRunner.record("password_answers", answers.responses.map { "\($0)" }.joined(separator: ","))
    }

    private var passwordToasts: ToastCenter? { AppDelegate.current?.windows.session(for: window)?.toasts }

    /// Fires `offer` through the page's UI delegate and waits for the popover;
    /// the line says whether the host presented it, where it points and who has the keyboard.
    private func passwordOffer(_ offer: PasswordOffer, on page: any WebContents, answers: OfferAnswers, capture: String?) async -> String {
        let respond: (PasswordOfferResponse) -> Void = { answers.responses.append($0) }
        let presented = switch offer.kind {
        case .save: page.uiDelegate?.webContents(page, willOfferPasswordSave: offer, completion: respond) ?? false
        case .update: page.uiDelegate?.webContents(page, willOfferPasswordUpdate: offer, completion: respond) ?? false
        }
        let shown = await waitUntil(3) { self.presenter?.passwordOfferView?.window?.isVisible == true }
        try? await Task.sleep(for: .milliseconds(350))
        var line = "kind=\(offer.kind) presented=\(presented) popover=\(shown)"
        if let popover = presenter?.passwordOfferView?.window {
            line += " popover frame=\(NSStringFromRect(popover.frame)) key=\(popover.isKeyWindow)"
            if controller.isSidebarOpen, let buttonWindow = session.sidebar.addressField.siteButtonView.window {
                let button = session.sidebar.addressField.siteButtonView
                let site = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                line += " site button=\(NSStringFromRect(site)) arrow tip into the button=\(Int(popover.frame.maxY - site.minY)) pt"
                    + " overlaps x=\(popover.frame.minX < site.maxX && popover.frame.maxX > site.minX)"
            } else {
                let card = controller.rootView.currentLayout.card
                let corner = window.convertToScreen(controller.rootView.convert(card, to: nil))
                line += " card=\(NSStringFromRect(corner)) inside the card x=\(popover.frame.minX >= corner.minX && popover.frame.maxX <= corner.maxX)"
            }
            let title = presenter?.passwordOfferView.flatMap { Self.label("password-offer-title", in: $0) }
            line += " title=\"\(title ?? "nil")\""
        }
        if let capture { passwordCapture(capture) }
        return line
    }

    /// Sends a key to the popover's window (Return 36, Esc 53); says where it went.
    private func passwordKey(_ keyCode: UInt16, _ characters: String) -> (String, Bool) {
        guard let popover = presenter?.passwordOfferView?.window else { return ("no popover", false) }
        if popover.isKeyWindow {
            PageDriver.key(popover, characters: characters, keyCode: keyCode)
            return ("key window", true)
        }
        // Key status lost to another app's window (5.4b's Room on screen): straight to the popover.
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: popover.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) {
                popover.sendEvent(event)
            }
        }
        return ("popover window, not key", false)
    }

    private static func label(_ identifier: String, in root: NSView) -> String? {
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField { return field.stringValue }
            queue += view.subviews
        }
        return nil
    }

    /// The window with the popover over it, as the window server draws them, for the review sheet.
    private func passwordCapture(_ name: String) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        window.displayIfNeeded()
        let others = [presenter?.passwordOfferView?.window].compactMap { $0 } + (window.childWindows ?? []).filter { $0.isVisible }
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.8a-\(name)-\(passwordAppearance).png")
        guard let image = others.isEmpty ? WindowSnapshot.capture(window) : WindowSnapshot.capture(window, with: others),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { return SpikeRunner.record("capture_\(name)", "failed") }
        SpikeRunner.record("capture_\(name)", "\(url.lastPathComponent) \(image.width)x\(image.height) px")
    }
}
#endif
