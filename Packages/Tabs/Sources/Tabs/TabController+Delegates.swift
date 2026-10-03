import AppKit
import Engine
import Model

// MARK: - Navigation delegate

extension TabController: NavigationDelegate {
    /// Navigations proceed as the page asked: links from permanent entries
    /// navigate in place this phase (Peek is 2.7); new-tab dispositions come
    /// back through `didCreate`.
    public func webContents(_ webContents: any WebContents, decidePolicyFor action: NavigationAction) -> Disposition {
        action.disposition
    }

    /// Every committed main-frame navigation of an entry's page is a history
    /// visit (ROADMAP 2.4 task 4); the title follows when the page reports it.
    public func webContents(_ webContents: any WebContents, didCommitNavigation url: URL, transition: PageTransition) {
        guard let id = entryID(for: webContents), let page = pages[id] else { return }
        // Tagged with the profile the page lives in (history follows the profile, ROADMAP 2.5).
        store.history.recordVisit(url: url.absoluteString, title: nil, transition: HistoryTransition(transition), profile: page.profileID)
        // The title is written again after this visit (same-document commits keep the page's title).
        pages[id]?.historyTitle = nil
        if let page = pages[id] { refreshHistoryTitle(page) }
    }
}

extension HistoryTransition {
    init(_ transition: PageTransition) {
        switch transition {
        case .link: self = .link
        case .typed: self = .typed
        case .bookmark: self = .bookmark
        case .generated: self = .generated
        case .keyword: self = .keyword
        case .formSubmit: self = .formSubmit
        case .reload: self = .reload
        case .other: self = .other
        }
    }
}

// MARK: - UI delegate

extension TabController: WebContentsUIDelegate {
    public func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?,
                            disposition: Disposition) {
        guard let opener = entryID(for: webContents) else {
            newContents.close()
            return
        }
        adoptOpenedPage(newContents, url: targetURL, openedBy: opener, select: disposition != .newBackgroundTab)
    }

    public func webContentsDidClose(_ webContents: any WebContents) {
        // Its prompts are answered (the presentation forgets the page).
        pageUIDelegate?.webContentsDidClose(webContents)
        if closing.removeValue(forKey: ObjectIdentifier(webContents)) != nil { return }
        guard let id = entryID(for: webContents) else { return }
        // Quitting: the entry stays as it is, unloaded (it restores at the next launch).
        if engine?.isTerminating == true {
            pages.removeValue(forKey: id)?.generation += 1
            return
        }
        // The page closed itself (`window.close()`): close its entry as ⌘W would.
        if let sidebar { sidebar.close(id) }
        if pages[id]?.contents === webContents { unload(id) }
    }

    public func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool,
                            completion: @escaping (Bool) -> Void) {
        let key = ObjectIdentifier(webContents)
        let answer: (Bool) -> Void = { [weak self] leave in
            if !leave, let self, let closed = closing.removeValue(forKey: key) {
                // After the close command has finished with the entry (it may remove it).
                Task { @MainActor in self.stay(closed.contents, entry: closed.entry) }
            }
            completion(leave)
        }
        guard let pageUIDelegate else { return answer(true) }
        pageUIDelegate.webContents(webContents, runBeforeUnloadDialogForReload: isReload, completion: answer)
    }

    /// The user kept a page that was being closed: it goes back to its entry,
    /// or, if the entry is gone, into a new Today tab; either way selected.
    private func stay(_ contents: any WebContents, entry: UUID) {
        guard let sidebar else { return }
        if store.sidebar.entry(entry) != nil, pages[entry] == nil {
            adopt(contents, entry: entry)
            sidebar.select(entry)
        } else if let tab = try? store.sidebar.addEntry(.today, url: contents.url?.absoluteString, title: contents.title,
                                                        space: sidebar.activeSpaceID, at: 0) {
            adopt(contents, entry: tab.id)
            sidebar.select(tab.id)
        }
    }

    // Everything below is presentation, forwarded to `pageUIDelegate` (the app's prompts, menus and file choosers, Phase 2.6).

    public func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?) {
        pageUIDelegate?.webContentsDidRequestEnterFullscreen(webContents, origin: origin)
    }

    public func webContentsDidRequestExitFullscreen(_ webContents: any WebContents) {
        pageUIDelegate?.webContentsDidRequestExitFullscreen(webContents)
    }

    public func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {
        guard webContents === current else { return }
        pageUIDelegate?.webContents(webContents, didChangeStatusText: text)
    }

    public func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        pageUIDelegate?.webContents(webContents, willShowContextMenu: menu, for: element) ?? false
    }

    public func webContents(_ webContents: any WebContents, runJavaScriptAlert message: String, origin: URL?,
                            completion: @escaping () -> Void) {
        guard let pageUIDelegate else { return completion() }
        pageUIDelegate.webContents(webContents, runJavaScriptAlert: message, origin: origin, completion: completion)
    }

    public func webContents(_ webContents: any WebContents, runJavaScriptConfirm message: String, origin: URL?,
                            completion: @escaping (Bool) -> Void) {
        guard let pageUIDelegate else { return completion(false) }
        pageUIDelegate.webContents(webContents, runJavaScriptConfirm: message, origin: origin, completion: completion)
    }

    public func webContents(_ webContents: any WebContents, runJavaScriptPrompt message: String, defaultText: String, origin: URL?,
                            completion: @escaping (String?) -> Void) {
        guard let pageUIDelegate else { return completion(nil) }
        pageUIDelegate.webContents(webContents, runJavaScriptPrompt: message, defaultText: defaultText, origin: origin,
                                   completion: completion)
    }

    public func webContentsDidDismissJavaScriptDialogs(_ webContents: any WebContents) {
        pageUIDelegate?.webContentsDidDismissJavaScriptDialogs(webContents)
    }

    public func webContents(_ webContents: any WebContents, willAskForPermission requests: [PermissionRequest],
                            quietReason: PermissionQuietReason?, completion: @escaping (PermissionResponse) -> Void) {
        guard let pageUIDelegate else { return completion(.dismissed) }
        pageUIDelegate.webContents(webContents, willAskForPermission: requests, quietReason: quietReason, completion: completion)
    }

    public func webContentsDidDismissPermissionPrompt(_ webContents: any WebContents) {
        pageUIDelegate?.webContentsDidDismissPermissionPrompt(webContents)
    }

    public func webContents(_ webContents: any WebContents, didReceiveAuthChallenge challenge: AuthChallenge,
                            completion: @escaping (URLCredential?) -> Void) {
        guard let pageUIDelegate else { return completion(nil) }
        pageUIDelegate.webContents(webContents, didReceiveAuthChallenge: challenge, completion: completion)
    }

    /// The interstitial shows the host as the row's title; Go Back on a page
    /// with nothing to go back to leaves Room's empty card state, never
    /// Chromium's "Privacy error" page (B-25, decided 2026-10-03).
    public func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError,
                            completion: @escaping (Bool) -> Void) {
        guard let pageUIDelegate else { return completion(false) }
        let host = error.url.host() ?? error.url.absoluteString
        if let id = entryID(for: webContents), let page = pages[id] {
            page.interstitialHost = host
            if let entry = store.sidebar.entry(id), entry.liveTitle != host {
                try? store.sidebar.setLivePage(id, url: entry.liveURL ?? error.url.absoluteString, title: host)
            }
        }
        pageUIDelegate.webContents(webContents, didFailCertificateCheck: error) { [weak self, weak webContents] proceed in
            // Read before the presenter goes back (it does only when it can).
            let leavesNothing = !proceed && webContents?.canGoBack == false
            completion(proceed)
            guard let self, let webContents, let id = self.entryID(for: webContents) else { return }
            self.pages[id]?.interstitialHost = nil
            guard leavesNothing else { return }
            // After the engine has finished with the cancelled navigation.
            Task { @MainActor in self.abandonBlockedPage(webContents, entry: id, url: error.url, host: host) }
        }
    }

    /// B-25: the page goes, the entry stays (its row shows the host) and the
    /// card shows the empty state while it is selected.
    private func abandonBlockedPage(_ webContents: any WebContents, entry id: UUID, url: URL, host: String) {
        guard pages[id]?.contents === webContents else { return }
        unload(id)
        try? store.sidebar.setLivePage(id, url: url.absoluteString, title: host)
        sidebar?.pageStateDidChange([id])
    }

    public func webContents(_ webContents: any WebContents, runFileChooser request: FileChooserRequest,
                            completion: @escaping ([URL]?) -> Void) {
        guard let pageUIDelegate else { return completion(nil) }
        pageUIDelegate.webContents(webContents, runFileChooser: request, completion: completion)
    }

    public func webContents(_ webContents: any WebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        pageUIDelegate?.webContents(webContents, isReservedKeyEvent: event) ?? false
    }

    public func webContents(_ webContents: any WebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        if let pageUIDelegate { return pageUIDelegate.webContents(webContents, handleUnhandledKeyEvent: event) }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    public func webContents(_ webContents: any WebContents, didConsumeKey key: KeyEventInfo) {
        pageUIDelegate?.webContents(webContents, didConsumeKey: key)
    }

    public func webContents(_ webContents: any WebContents, didChangeSecurityState state: SecurityState) {
        pageUIDelegate?.webContents(webContents, didChangeSecurityState: state)
    }

    public func webContents(_ webContents: any WebContents, processGone status: TerminationStatus) {
        pageUIDelegate?.webContents(webContents, processGone: status)
    }
}
