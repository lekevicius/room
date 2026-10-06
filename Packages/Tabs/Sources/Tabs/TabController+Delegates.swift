import AppKit
import Engine
import Model

// MARK: - Navigation delegate

extension TabController: NavigationDelegate {
    /// Navigations proceed as the page asked, but for Peek (spec §A.4): an
    /// off-site click from a permanent entry, or a ⇧-click, is cancelled
    /// and opens in Peek over the page. A Peek's own page navigates in place.
    /// New-tab dispositions come back through `didCreate`.
    public func webContents(_ webContents: any WebContents, decidePolicyFor action: NavigationAction) -> Disposition {
        guard peekDecision(for: action, in: webContents) == .peek, let opener = entryID(for: webContents) else { return action.disposition }
        // After the engine has finished with the cancelled navigation.
        Task { @MainActor in self.openPeek(action.url, over: opener) }
        return .ignore
    }

    /// The page's back/forward list changed: its entry keeps the new one
    /// (written with the store's next debounced transaction, 2.1), so a
    /// relaunch or a crash finds it (3.7b). Peek pages keep none.
    public func webContentsDidChangeNavigationState(_ webContents: any WebContents) {
        guard let id = entryID(for: webContents) else { return }
        saveNavigationState(of: webContents, entry: id)
    }
}

// MARK: - UI delegate

extension TabController: WebContentsUIDelegate {
    public func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?,
                            disposition: Disposition) {
        // A Peek's popups open under the entry the Peek is over (never routed: Peek is untouched by routing, 4.2).
        let fromEntry = entryID(for: webContents)
        guard let opener = fromEntry ?? peekOpener(of: webContents) else {
            newContents.close()
            return
        }
        adoptOpenedPage(newContents, url: targetURL, openedBy: opener, select: disposition != .newBackgroundTab, routable: fromEntry != nil)
    }

    public func webContentsDidClose(_ webContents: any WebContents) {
        // Its prompts are answered (the presentation forgets the page).
        pageUIDelegate?.webContentsDidClose(webContents)
        if closing.removeValue(forKey: ObjectIdentifier(webContents)) != nil {
            pageClosers.removeValue(forKey: ObjectIdentifier(webContents))?(true)
            return
        }
        if closingPeeks.remove(ObjectIdentifier(webContents)) != nil { return }
        // A Peek's page closed itself (`window.close()`): the Peek goes.
        if let opener = peekOpener(of: webContents) {
            peeks.removeValue(forKey: opener)
            if opener == currentEntryID { updatePeek(animated: true) }
            return
        }
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
                // ⌘W's entry stays (its removal waited for the page to close).
                pageClosers.removeValue(forKey: key)?(false)
                // After the close command has finished with the entry.
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
        // B-35 (4.2): only the card's page can take the window, so the shown Peek's page first
        // becomes a Today tab under its entry (Open as Tab's path, spec §I.6) and the card's page;
        // the request then goes on and is granted like any card page's.
        if let opener = peekOpener(of: webContents), opener == currentEntryID { expandShownPeek() }
        pageUIDelegate?.webContentsDidRequestEnterFullscreen(webContents, origin: origin)
    }

    public func webContentsDidRequestExitFullscreen(_ webContents: any WebContents) {
        pageUIDelegate?.webContentsDidRequestExitFullscreen(webContents)
    }

    public func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {
        page(for: webContents)?.hoveredLink = text.flatMap(URL.init(string:))
        guard webContents === focusedPage else { return }
        pageUIDelegate?.webContents(webContents, didChangeStatusText: text)
    }

    /// Chromium's focus-the-location-bar command (3.5): the window's field, for the page it shows only.
    public func webContentsDidRequestFocusOnLocationBar(_ webContents: any WebContents) {
        guard webContents === focusedPage else { return }
        pageUIDelegate?.webContentsDidRequestFocusOnLocationBar(webContents)
    }

    /// Where the engine's bubbles point (RoomCore's Views bubbles, 3.7a): the window's answer.
    public func bubbleAnchorRect(for webContents: any WebContents) -> CGRect? {
        pageUIDelegate?.bubbleAnchorRect(for: webContents)
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
        // Esc the page in Peek did not use closes the Peek (spec §I.6).
        if event.type == .keyDown, event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           webContents === peekContents {
            return closeShownPeek()
        }
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

    // MARK: The renderer, other applications, notices, capture (3.4b)

    public func webContentsDidBecomeUnresponsive(_ webContents: any WebContents,
                                                 completion: @escaping (UnresponsiveRendererAction) -> Void) {
        guard let pageUIDelegate else { return completion(.wait) }
        pageUIDelegate.webContentsDidBecomeUnresponsive(webContents, completion: completion)
    }

    public func webContentsDidBecomeResponsive(_ webContents: any WebContents) {
        pageUIDelegate?.webContentsDidBecomeResponsive(webContents)
    }

    public func webContents(_ webContents: any WebContents, shouldOpenExternalURL request: ExternalURLRequest,
                            completion: @escaping (Bool) -> Void) {
        guard let pageUIDelegate else { return completion(false) }
        pageUIDelegate.webContents(webContents, shouldOpenExternalURL: request, completion: completion)
    }

    public func webContents(_ webContents: any WebContents, didAddInfoBar infoBar: InfoBar) {
        pageUIDelegate?.webContents(webContents, didAddInfoBar: infoBar)
    }

    public func webContents(_ webContents: any WebContents, didRemoveInfoBar infoBar: InfoBar) {
        pageUIDelegate?.webContents(webContents, didRemoveInfoBar: infoBar)
    }

    /// The row's capture indicator follows `captureState` through `track`.
    public func webContents(_ webContents: any WebContents, didChangeCaptureState state: CaptureState) {
        pageUIDelegate?.webContents(webContents, didChangeCaptureState: state)
    }

    /// The footer's media row is 4.6's: the session is logged once per change.
    func logMediaSession(_ page: Page, _ session: MediaSessionInfo?, entry: UUID) {
        guard page.loggedMediaSession != session else { return }
        page.loggedMediaSession = session
        if let session {
            NSLog("Room: media session \"%@\" by \"%@\" on \"%@\" (%@) art=%@ entry %@", session.title, session.artist, session.album,
                  "\(session.playbackState)", session.artworkURL?.absoluteString ?? "none", entry.uuidString)
        } else {
            NSLog("Room: media session ended, entry %@", entry.uuidString)
        }
    }
}
