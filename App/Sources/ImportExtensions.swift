import AppKit
import Chrome
import Import
import Model
import Store

// MARK: - The other browser's extensions through their store pages (ROADMAP 4.3b task 6)

/// Opens the chosen extensions' Chrome Web Store pages one at a time as
/// Today tabs of a space (the planner's decision: no install-by-id engine
/// member). The user adds each one in the store and answers Room's consent
/// sheet (3.6a); the next page opens when the space's profile reports the
/// install (`extensionsDidChange`, seen through `ExtensionsCenter`) or the
/// page's tab is closed. The order and the bookkeeping are
/// `StorePageSequence` (Import, unit-tested); this class only opens pages
/// and watches.
@MainActor
final class ExtensionStorePages {
    private(set) var sequence: StorePageSequence
    let space: UUID
    let profile: UUID
    /// The Today tab of the page open now.
    private(set) var currentEntry: UUID?
    /// Every step, for the import spike's log.
    var onStep: ((StorePageSequence, UUID?) -> Void)?
    var onFinished: ((StorePageSequence) -> Void)?

    private let open: (URL, UUID) -> UUID?
    private let installedIDs: () -> Set<String>
    private let entryExists: (UUID) -> Bool

    init(ids: [String], space: UUID, profile: UUID, pageTemplate: String, open: @escaping (URL, UUID) -> UUID?,
         installedIDs: @escaping () -> Set<String>, entryExists: @escaping (UUID) -> Bool) {
        sequence = StorePageSequence(ids: ids, pageTemplate: pageTemplate)
        self.space = space
        self.profile = profile
        self.open = open
        self.installedIDs = installedIDs
        self.entryExists = entryExists
    }

    func start() {
        apply(sequence.start(installedInProfile: installedIDs()))
        watch()
    }

    func cancel() {
        sequence.cancel()
        currentEntry = nil
    }

    private func apply(_ step: StorePageSequence.Step) {
        switch step {
        case .open(_, let url):
            currentEntry = open(url, space)
            onStep?(sequence, currentEntry)
            // A tab that could not be made counts as closed: the next one opens.
            if currentEntry == nil, let next = sequence.pageClosed() { apply(next) }
        case .finished:
            currentEntry = nil
            onStep?(sequence, nil)
            onFinished?(sequence)
        }
    }

    /// Re-armed after every change while pages are left.
    private func watch() {
        guard !sequence.isFinished else { return }
        let entry = currentEntry
        withObservationTracking {
            _ = installedIDs()
            if let entry { _ = entryExists(entry) }
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in weakSelf.value?.changed() }
        }
    }

    private func changed() {
        guard !sequence.isFinished else { return }
        if let step = sequence.extensionsChanged(installedInProfile: installedIDs()) {
            apply(step)
        } else if let entry = currentEntry, !entryExists(entry), let step = sequence.pageClosed() {
            apply(step)
        }
        watch()
    }

    /// The toast's line once the sequence ends.
    static func summary(_ sequence: StorePageSequence) -> String {
        var parts = ["\(sequence.installed.count) added"]
        if !sequence.closedWithoutInstall.isEmpty { parts.append("\(sequence.closedWithoutInstall.count) not added") }
        if !sequence.alreadyInstalled.isEmpty { parts.append("\(sequence.alreadyInstalled.count) already here") }
        return "Extensions from the Web Store: " + parts.joined(separator: ", ")
    }
}

extension AppDelegate {
    /// The store pages' address: the Chrome Web Store's, or DEBUG
    /// `-RoomWebStorePage <template with {id}>` (the tour's local page: no
    /// request leaves the machine).
    static var webStorePageTemplate: String {
        #if DEBUG
        if let template = UserDefaults.standard.string(forKey: "RoomWebStorePage") { return template }
        #endif
        return StorePageSequence.defaultPageTemplate
    }

    /// Starts the store pages for `ids` in `space` (nil: the active space);
    /// a running sequence is cancelled first. How many pages will open (ids
    /// already installed in the space's profile and invalid ones open none).
    @discardableResult
    func openExtensionStorePages(_ ids: [String], space: UUID?) -> ExtensionStorePages? {
        guard let store, let tabs, !ids.isEmpty,
              let spaceID = space ?? sidebar?.activeSpaceID, let target = store.sidebar.space(spaceID) else { return nil }
        extensionStorePages?.cancel()
        let profile = target.profileID
        let pages = ExtensionStorePages(
            ids: ids, space: spaceID, profile: profile, pageTemplate: Self.webStorePageTemplate,
            open: { [weak tabs] url, space in tabs?.openNewTab(url: url.absoluteString, inSpace: space, transition: .link) },
            installedIDs: { [weak self] in Set(self?.extensions?.section(profile: profile)?.installed.map(\.id) ?? []) },
            entryExists: { [weak store] id in store?.sidebar.entry(id) != nil })
        pages.onFinished = { [weak self] sequence in
            guard !sequence.opened.isEmpty || !sequence.alreadyInstalled.isEmpty else { return }
            self?.toastCenter?.show(Toast(id: "imported-extensions", symbol: .importData, message: ExtensionStorePages.summary(sequence)))
            if self?.extensionStorePages?.sequence == sequence { self?.extensionStorePages = nil }
        }
        extensionStorePages = pages
        pages.start()
        return pages
    }
}
