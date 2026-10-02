import AppKit
import Engine
import FakeEngine
import Testing

@Suite("Delegate dispatch")
struct DelegateDispatchTests {
    // MARK: Navigation policy

    @Test func addressBarLoadAsksForPolicy() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let navigation = RecordingNavigationDelegate()
        page.navigationDelegate = navigation
        page.load(url("https://typed.example"), transition: .typed, fromAddressBar: true)
        let action = try #require(navigation.actions.first)
        #expect(action.url == url("https://typed.example"))
        #expect(action.kind == .other)
        #expect(action.transition == .typed)
        #expect(action.disposition == .currentTab)
        #expect(action.isUserGesture)
    }

    @Test func ignoreCancelsNavigation() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let navigation = RecordingNavigationDelegate()
        navigation.decide = { _ in .ignore }
        page.navigationDelegate = navigation
        page.load(url("https://blocked.example"))
        #expect(page.url == nil)
        #expect(navigation.actions.count == 1)
    }

    @Test func backForwardAndReloadAreReportedWithTheirKind() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let navigation = RecordingNavigationDelegate()
        page.navigationDelegate = navigation
        page.load(url("https://a.example"))
        page.load(url("https://b.example"))
        page.goBack()
        page.reload()
        #expect(navigation.actions.map(\.kind) == [.other, .other, .backForward, .reload])
        #expect(navigation.actions[2].url == url("https://a.example"))
    }

    @Test func linkClickCarriesReferrerAndGesture() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://from.example"))
        let navigation = RecordingNavigationDelegate()
        page.navigationDelegate = navigation
        page.simulateLinkClick(to: url("https://to.example"))
        let action = try #require(navigation.actions.first)
        #expect(action.kind == .linkActivated)
        #expect(action.referrer == url("https://from.example"))
        #expect(action.isUserGesture)
        #expect(page.url == url("https://to.example"))
    }

    @Test func policyCanRedirectALinkToANewTab() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://pinned.example"))
        let navigation = RecordingNavigationDelegate()
        navigation.decide = { $0.url.host() == "pinned.example" ? .currentTab : .newForegroundTab }
        let ui = RecordingUIDelegate()
        page.navigationDelegate = navigation
        page.uiDelegate = ui

        page.simulateLinkClick(to: url("https://elsewhere.example"))

        #expect(page.url == url("https://pinned.example"))
        #expect(ui.calls == [.didCreate(targetURL: url("https://elsewhere.example"), disposition: .newForegroundTab)])
        let created = try #require(ui.createdContents.first)
        #expect(created.url == url("https://elsewhere.example"))
        #expect(profile.openWebContents.count == 2)
    }

    @Test func backgroundTabStartsHidden() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui
        page.simulateLinkClick(to: url("https://bg.example"), disposition: .newBackgroundTab)
        let created = try #require(ui.createdContents.first as? FakeWebContents)
        #expect(created.configuration.initiallyHidden)
    }

    @Test func newContentsWithoutUIDelegateAreClosed() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.simulateWindowOpen(url("https://popup.example"), disposition: .newPopup)
        #expect(profile.openWebContents.count == 1)
    }

    @Test func saveToDiskStartsADownload() throws {
        let (_, profile) = try makeProfile()
        let downloads = RecordingDownloadsDelegate()
        profile.downloadsDelegate = downloads
        let page = profile.makeWebContents()
        let navigation = RecordingNavigationDelegate()
        navigation.decide = { _ in .saveToDisk }
        page.navigationDelegate = navigation
        page.simulateLinkClick(to: url("https://files.example/archive.zip"))
        #expect(downloads.began.first?.suggestedFilename == "archive.zip")
        #expect(page.url == nil)
    }

    // MARK: JavaScript dialogs

    @Test func javaScriptDialogsReachTheDelegate() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://dialogs.example:8443/page"))
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui

        await page.simulateAlert("Hello")
        ui.confirmAnswer = true
        #expect(await page.simulateConfirm("Sure?"))
        ui.promptAnswer = "Room"
        #expect(await page.simulatePrompt("Name?", defaultText: "x") == "Room")
        page.simulateDialogsDismissed()

        #expect(ui.calls.filter { if case .security = $0 { false } else { true } } == [
            .alert("Hello", origin: url("https://dialogs.example:8443")),
            .confirm("Sure?"),
            .prompt("Name?", defaultText: "x"),
            .dialogsDismissed,
        ])
    }

    @Test func dialogsWithoutDelegateUseDefaults() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        await page.simulateAlert("ignored")
        #expect(await page.simulateConfirm("?") == false)
        #expect(await page.simulatePrompt("?") == nil)
        #expect(await page.simulatePermissionRequest([.camera]) == .dismissed)
        #expect(await page.simulateAuthChallenge() == nil)
        #expect(await page.simulateCertificateError() == false)
        #expect(await page.simulateFileChooser(FileChooserRequest(mode: .open)) == nil)
        #expect(await page.simulateContextMenu(ContextMenuElement(location: .zero), items: []) == nil)
    }

    @Test func beforeUnloadCanKeepThePageOpen() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://form.example"))
        page.hasBeforeUnloadHandler = true
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui

        ui.beforeUnloadAnswer = false
        page.close()
        #expect(page.state == .alive)

        ui.beforeUnloadAnswer = true
        page.close()
        #expect(page.state == .closed)
        #expect(ui.calls == [.beforeUnload(isReload: false), .beforeUnload(isReload: false), .didClose])
        #expect(profile.openWebContents.isEmpty)
    }

    @Test func beforeUnloadOnReload() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://form.example"))
        page.hasBeforeUnloadHandler = true
        let ui = RecordingUIDelegate()
        ui.beforeUnloadAnswer = false
        page.uiDelegate = ui
        page.loadsSynchronously = false
        page.reload()
        #expect(!page.isLoading)
        #expect(ui.calls == [.beforeUnload(isReload: true)])
    }

    @Test func windowCloseFromScriptSkipsBeforeUnload() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.hasBeforeUnloadHandler = true
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui
        page.simulateWindowClose()
        #expect(ui.calls == [.didClose])
    }

    // MARK: Permissions, auth, certificates, files

    @Test func permissionRequestCarriesKindsAndOrigin() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://meet.example/room/1"))
        let ui = RecordingUIDelegate()
        ui.permissionAnswer = .grantedOnce
        page.uiDelegate = ui

        let response = await page.simulatePermissionRequest([.camera, .microphone], quietReason: .crowdDeny)
        page.simulatePermissionPromptDismissed()

        #expect(response == .grantedOnce)
        let origin = url("https://meet.example")
        #expect(ui.calls == [
            .permission([PermissionRequest(kind: .camera, origin: origin), PermissionRequest(kind: .microphone, origin: origin)], quietReason: .crowdDeny),
            .permissionDismissed,
        ])
    }

    @Test func authCertificateAndFileChooser() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://intranet.example/x"))
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui

        let credential = await page.simulateAuthChallenge(realm: "Staff", scheme: "Digest")
        #expect(credential?.user == "u")
        ui.proceedPastCertificateError = true
        #expect(await page.simulateCertificateError(code: -201, description: "ERR_CERT_DATE_INVALID"))
        let request = FileChooserRequest(mode: .openMultiple, acceptTypes: ["image/*"])
        #expect(await page.simulateFileChooser(request) == [URL(filePath: "/tmp/a.txt")])

        #expect(ui.calls == [
            .auth(AuthChallenge(origin: url("https://intranet.example"), realm: "Staff", scheme: "Digest")),
            .certificate(CertificateError(url: url("https://intranet.example/x"), code: -201, description: "ERR_CERT_DATE_INVALID", isOverridable: true)),
            .fileChooser(request),
        ])
    }

    // MARK: Context menu

    @Test func delegatePresentedContextMenuReturnsTheChoice() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let ui = RecordingUIDelegate()
        ui.contextMenuChoice = 50100
        page.uiDelegate = ui
        let element = ContextMenuElement(location: NSPoint(x: 5, y: 7), linkURL: url("https://link.example"))
        let items = [
            MenuItem(id: 50100, title: "Open Link in New Tab"),
            .separator(),
            MenuItem(id: 50101, title: "Copy Link"),
        ]
        #expect(await page.simulateContextMenu(element, items: items) == 50100)
        #expect(ui.calls == [.contextMenu(element)])
    }

    @Test func contextMenuLeftToTheEngine() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui
        #expect(await page.simulateContextMenu(ContextMenuElement(location: .zero), items: [MenuItem(id: 1, title: "Back")]) == nil)
        #expect(ui.calls.count == 1)
    }

    // MARK: Keyboard

    @Test func reservedKeysNeverReachThePage() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let ui = RecordingUIDelegate()
        ui.reservedKeyCodes = [17] // kVK_ANSI_T
        page.uiDelegate = ui
        #expect(page.simulateKeyDown(keyDown("t", keyCode: 17), pageHandles: true) == .reserved)
        #expect(ui.calls == [.reservedKey(17)])
    }

    @Test func consumedAndUnhandledKeys() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui
        #expect(page.simulateKeyDown(keyDown("c", keyCode: 8), pageHandles: true) == .consumedByPage)
        #expect(page.simulateKeyDown(keyDown("y", keyCode: 16), pageHandles: false) == .unhandled)
        ui.handlesUnhandledKeys = true
        #expect(page.simulateKeyDown(keyDown("y", keyCode: 16), pageHandles: false) == .handledByDelegate)
        #expect(ui.calls == [
            .consumedKey(KeyEventInfo(keyCode: 8, modifiers: .command, phase: .keyDown)),
            .unhandledKey(16),
            .unhandledKey(16),
        ])
    }

    // MARK: Page state notifications

    @Test func audioMuteStatusFullscreenSecurityAndCrash() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents(WebContentsConfiguration(initiallyMuted: true))
        let ui = RecordingUIDelegate()
        page.uiDelegate = ui
        #expect(page.isMuted)

        page.load(url("http://plain.example"))
        page.simulateAudio(true)
        page.simulateAudio(true)
        page.isMuted = false
        page.isMuted = false
        page.simulateStatusText("https://hover.example")
        page.simulateStatusText(nil)
        page.simulateFullscreenRequest(enter: true)
        page.simulateFullscreenRequest(enter: false)
        page.simulateCrash()

        #expect(ui.calls == [
            .security(SecurityState(level: .insecure)),
            .audible(true),
            .muted(false),
            .statusText("https://hover.example"),
            .statusText(nil),
            .enterFullscreen(origin: url("http://plain.example")),
            .exitFullscreen,
            .processGone(.crashed),
        ])
        #expect(!page.isAudible)
    }

    @Test func colorsAreObservableState() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents(WebContentsConfiguration(transparentBackground: true))
        #expect(page.rootBackgroundColor == nil)
        page.simulateColors(theme: .systemRed, rootBackground: .black)
        #expect(page.themeColor == .systemRed)
        #expect(page.rootBackgroundColor == .black)
    }
}
