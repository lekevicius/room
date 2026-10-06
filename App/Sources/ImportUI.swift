import AppKit
import Chrome
import Design
import Engine
import Import
import Model
import Store
import SwiftUI

// MARK: - The import sheet (ROADMAP 4.3a task 3)

extension AppDelegate {
    /// The palette's "Import from another browser…": a sheet over the
    /// browser window. Nothing is read until a source is picked and nothing
    /// is written before Import.
    @objc func showImportSheet(_ sender: Any?) {
        guard let store else { return }
        if let sheet = importSheet {
            sheet.makeKeyAndOrderFront(nil)
            return
        }
        guard let window = windowController?.window else { return }
        var sources = ImportSources.detectInstalls(home: Self.importHome)
        #if DEBUG
        // `-RoomImportSource <directory>`: each source in it listed first, as a detected install (spikes, the tour).
        if let path = UserDefaults.standard.string(forKey: "RoomImportSource") {
            sources = ImportSources.sources(inDirectory: URL(fileURLWithPath: path, isDirectory: true)) + sources
        }
        #endif
        let model = ImportSheetModel(store: store, sources: sources)
        model.engineProfile = { [weak self] profile in await self?.engineProfile(for: profile) }
        model.announce = { [weak self] message in
            self?.toastCenter?.show(Toast(id: "imported", symbol: .importData, message: message))
        }
        model.openStorePages = { [weak self] ids, space in
            (self?.openExtensionStorePages(ids, space: space)?.sequence).map { $0.opened.count + $0.pending.count } ?? 0
        }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ImportSheetMetrics.width, height: ImportSheetMetrics.height),
                             styleMask: [.titled], backing: .buffered, defer: true)
        let content = ImportSheet(model: model, onChooseFile: { [weak self] in self?.chooseImportFile() },
                                  onChoosePasswords: { [weak self] in self?.choosePasswordsFile() },
                                  onClose: { [weak self] in self?.closeImportSheet() })
        sheet.contentViewController = NSHostingController(rootView: content)
        importSheet = sheet
        importModel = model
        window.makeKeyAndOrderFront(nil)
        window.beginSheet(sheet)
    }

    func closeImportSheet() {
        guard let sheet = importSheet else { return }
        importModel?.cancel()
        importSheet = nil
        importModel = nil
        sheet.sheetParent?.endSheet(sheet)
    }

    /// Where the browsers' folders are looked for: the user's home, or DEBUG
    /// `-RoomImportHome <dir>` (a fake home holding fixtures at the real
    /// relative paths: the tour's detection of Safari, Arc, Firefox and
    /// Chrome; 4.3b task 9).
    static var importHome: URL {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "RoomImportHome") { return URL(fileURLWithPath: path, isDirectory: true) }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// "Choose CSV…" in the Passwords box: the file another browser exported.
    private func choosePasswordsFile() {
        guard let sheet = importSheet, let model = importModel else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "Choose the passwords file you exported from your other browser (a .csv)."
        panel.prompt = "Choose"
        panel.beginSheetModal(for: sheet) { response in
            guard response == .OK, let url = panel.url else { return }
            model.choosePasswords(url)
        }
    }

    /// "Choose a File or Folder…": an open panel over the sheet. A folder
    /// chosen here is readable even where Room has no Full Disk Access
    /// (Safari's `~/Library/Safari`), because the panel grants it.
    private func chooseImportFile() {
        guard let sheet = importSheet, let model = importModel else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose a browser's folder (Safari: ~/Library/Safari), a profile folder, or an exported bookmarks file (.html)."
        panel.prompt = "Choose"
        // Safari's folder when macOS kept Room out of it: the panel opens there, and choosing it grants access.
        if let source = model.selectedSource, model.scan?.needsFileAccess == true { panel.directoryURL = source.location }
        panel.beginSheetModal(for: sheet) { response in
            guard response == .OK, let url = panel.url else { return }
            model.addChosen(url)
        }
    }
}

/// The sheet's fixed lines.
enum ImportSheetText {
    /// 4.3b task 7: cookies are not imported (another browser's keychain key encrypts them).
    static let cookies = "Cookies and site data are not imported; sign in again on the sites you use."
}

/// The sheet's size (chosen; looks are Chapter 5's).
enum ImportSheetMetrics {
    static let width: CGFloat = 580
    static let height: CGFloat = 760
}

/// The sheet's state (a SwiftUI leaf's model): the sources, the one picked
/// and its profile, the readers' counts (read off the main thread when a
/// source is picked), the options, the plan's preview (mapped off the main
/// thread whenever an option changes), then the import itself: the sidebar
/// in one `SidebarStore.applyImport` (one transaction) and the history in
/// batches into the target profile's `ProfileHistory.importEntries`.
@MainActor @Observable
final class ImportSheetModel {
    enum Phase: Equatable {
        /// Nothing picked yet.
        case choosing
        case reading
        /// Read; the options and the preview show.
        case ready
        case importing
        case done(String)
    }

    @ObservationIgnored let store: RoomStore
    private(set) var sources: [ImportSource]
    private(set) var selectedSourceID: String?
    private(set) var profiles: [ImportProfileChoice] = []
    var selectedProfile: String? { didSet { if oldValue != selectedProfile { rescan() } } }
    private(set) var scan: ImportScan?
    private(set) var phase: Phase = .choosing
    private(set) var progress: ImportProgress?
    /// Why the chosen file is not a source, or a source could not be read at all.
    private(set) var message: String?

    var importBookmarks = true { didSet { replan() } }
    var importHistory = true { didSet { replan() } }
    var importSidebar = true { didSet { replan() } }
    var layout: ImportOptions.Layout = .oneSpace { didSet { replan() } }
    var barIntoEssentials = false { didSet { replan() } }
    /// `nil`: a new space named after the source.
    var targetSpace: UUID? { didSet { replan() } }
    var targetProfile: UUID { didSet { replan() } }
    private(set) var plan: ImportPlan?
    /// What the last import wrote (the toast's counts; the tour compares them with the preview).
    private(set) var applied: ImportApplied?
    private(set) var historyResult: HistoryImportResult?

    // Passwords (4.3b): a CSV the other browser exported, through the engine's importer.
    private(set) var passwordsFile: URL?
    /// Data rows in the chosen file (its lines past the header), or why it cannot be used.
    private(set) var passwordsLine: String?
    @ObservationIgnored private var passwordsCSV: String?
    /// On once a file is chosen.
    var importPasswords = false
    /// Asked once for the whole file (spec 4.3b task 5).
    var passwordConflicts: PasswordImportConflictPolicy = .skip
    private(set) var passwordsResult: PasswordImportResult?

    // Extensions (4.3b): the other browser's Web Store extensions, opened one at a time on their store pages.
    /// Off until ticked: it opens pages (each extension under it is chosen by default).
    var importExtensions = false
    var chosenExtensions: Set<String> = []
    private(set) var storePagesOpened = 0
    /// Opens the store pages in a space (nil: the active one); how many will open.
    @ObservationIgnored var openStorePages: (([String], UUID?) -> Int)?

    /// The engine profile of a Room profile, made if needed (the app's).
    @ObservationIgnored var engineProfile: ((Model.Profile) async -> (any Engine.Profile)?)?
    @ObservationIgnored var announce: ((String) -> Void)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var work: Task<Void, Never>?
    #if DEBUG
    /// Seconds of the last read and the last mapping (spike-results).
    @ObservationIgnored private(set) var debugReadSeconds: Double = 0
    @ObservationIgnored private(set) var debugPlanSeconds: Double = 0
    /// The last import's sidebar write (apply and flush) and its history batches (B-84).
    @ObservationIgnored private(set) var debugApplySeconds: Double = 0
    @ObservationIgnored private(set) var debugHistorySeconds: Double = 0
    @ObservationIgnored private(set) var debugHistoryBatches = 0
    #endif

    init(store: RoomStore, sources: [ImportSource]) {
        self.store = store
        self.sources = sources
        targetProfile = store.sidebar.profiles.first?.id ?? UUID()
    }

    var selectedSource: ImportSource? { sources.first { $0.id == selectedSourceID } }

    var newSpaceName: String { selectedSource.map { $0.kind == .bookmarksFile ? "Bookmarks" : $0.kind.displayName } ?? "Imported" }

    // MARK: Picking

    /// Picks a source: its profiles from `Local State` (read now, not before), then a scan.
    func pick(_ id: String?) {
        guard id != selectedSourceID else { return }
        work?.cancel()
        selectedSourceID = id
        scan = nil
        plan = nil
        message = nil
        applied = nil
        guard let source = selectedSource else {
            profiles = []
            phase = .choosing
            return
        }
        guard source.isReadable else {
            profiles = []
            phase = .choosing
            message = source.note
            return
        }
        profiles = ImportSources.profiles(of: source)
        let preferred = profiles.first { $0.directory == "Default" } ?? profiles.first
        if selectedProfile != preferred?.directory {
            selectedProfile = preferred?.directory  // rescans
        } else {
            rescan()
        }
    }

    /// A file or folder from the open panel, listed and picked.
    func addChosen(_ url: URL) {
        guard let source = ImportSources.identify(url) else {
            message = "Room cannot import from \(url.lastPathComponent): choose a browser's folder, a profile folder or a bookmarks .html file."
            return
        }
        if !sources.contains(where: { $0.id == source.id }) { sources.insert(source, at: 0) }
        selectedSourceID = nil
        pick(source.id)
    }

    private func rescan() {
        guard let source = selectedSource, source.isReadable else { return }
        let profile = profiles.first { $0.directory == selectedProfile }
        work?.cancel()
        generation += 1
        let generation = generation
        phase = .reading
        progress = ImportProgress(fraction: 0, step: "Reading…")
        scan = nil
        plan = nil
        let weak = MainActorWeak(self)
        work = Task.detached(priority: .userInitiated) {
            let start = ContinuousClock.now
            let scan = ImportScanner.scan(source, profile: profile) { progress in
                Task { @MainActor in
                    guard let model = weak.value, model.generation == generation else { return }
                    model.progress = progress
                }
            }
            let seconds = (ContinuousClock.now - start) / .seconds(1)
            await MainActor.run {
                guard let model = weak.value, model.generation == generation, !Task.isCancelled else { return }
                model.scanned(scan, seconds: seconds)
            }
        }
    }

    private func scanned(_ scan: ImportScan, seconds: Double) {
        self.scan = scan
        #if DEBUG
        debugReadSeconds = seconds
        #endif
        chosenExtensions = Set(webStoreExtensions.map(\.id))
        if scan.needsFileAccess {
            message = "macOS keeps Room out of \(scan.source.name)'s files. Click Choose a File or Folder… and choose its folder "
                + "(\(scan.source.location.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))): choosing it there lets Room read it."
        } else if scan.isEmpty {
            message = "Nothing to import was found there."
        }
        phase = .ready
        progress = nil
        replan()
    }

    // MARK: Planning (off the main thread)

    var options: ImportOptions {
        var options = ImportOptions(targetSpace: targetSpace.map { .existing($0) } ?? .new(name: newSpaceName), targetProfile: targetProfile)
        options.bookmarks = importBookmarks
        options.history = importHistory
        options.sidebar = importSidebar
        options.layout = layout
        options.barIntoEssentials = barIntoEssentials
        return options
    }

    private func replan() {
        guard let scan, phase == .ready else { return }
        generation += 1
        let generation = generation
        let options = options
        let target = ImportTarget(state: store.currentState())
        let weak = MainActorWeak(self)
        work = Task.detached(priority: .userInitiated) {
            let start = ContinuousClock.now
            let plan = ImportPlanner.plan(scan, options: options, target: target)
            let seconds = (ContinuousClock.now - start) / .seconds(1)
            await MainActor.run {
                guard let model = weak.value, model.generation == generation else { return }
                model.plan = plan
                #if DEBUG
                model.debugPlanSeconds = seconds
                #endif
            }
        }
    }

    /// Waits for the current read or mapping (spikes).
    func settle() async { await work?.value }

    var canImport: Bool {
        switch phase {
        case .ready: plan.map { !$0.preview.isEmpty } == true || wantsPasswords || wantsExtensions
        // Passwords need no source: a CSV alone imports.
        case .choosing: wantsPasswords
        default: false
        }
    }

    var wantsPasswords: Bool { importPasswords && passwordsCSV != nil }
    var wantsExtensions: Bool { importExtensions && !chosenExtensions.isEmpty && scan?.extensions?.value != nil }

    /// The Web Store extensions of the scan (unpacked ones are in its skipped list, with their reason).
    var webStoreExtensions: [ImportedExtension] { scan?.extensions?.value?.extensions.filter(\.fromWebStore) ?? [] }

    /// The passwords' profile: the chosen space's, else "Into profile".
    var passwordsProfile: UUID { targetSpace.flatMap { store.sidebar.space($0)?.profileID } ?? targetProfile }

    // MARK: Passwords

    /// A CSV chosen in the Passwords box: read now (Chrome's importer takes at most 1000 KB), its rows counted.
    func choosePasswords(_ url: URL) {
        passwordsFile = url
        passwordsResult = nil
        guard let data = try? Data(contentsOf: url) else {
            passwordsCSV = nil
            passwordsLine = "\(url.lastPathComponent) could not be read."
            return
        }
        guard let text = String(data: data, encoding: .utf8) else {
            passwordsCSV = nil
            passwordsLine = "\(url.lastPathComponent) is not UTF-8 text."
            return
        }
        passwordsCSV = text
        let rows = max(0, text.split(whereSeparator: \.isNewline).count - 1)
        passwordsLine = "\(url.lastPathComponent): \(rows) \(rows == 1 ? "row" : "rows")"
        importPasswords = true
    }

    // MARK: Import

    /// Writes the plan: the sidebar in one change (one transaction, flushed
    /// now), then the history in batches with progress, then the toast.
    func performImport() async {
        guard canImport else { return }
        let plan = plan ?? ImportPlan.empty
        let sourceName = selectedSource?.name ?? passwordsFile?.lastPathComponent ?? "a file"
        phase = .importing
        work?.cancel()
        progress = ImportProgress(fraction: 0, step: "Adding to the sidebar…")
        var applied = ImportApplied()
        #if DEBUG
        let applyStart = ContinuousClock.now
        #endif
        if !plan.batch.isEmpty, selectedSource != nil {
            do {
                applied = try store.sidebar.applyImport(plan.batch)
                store.flush()
                #if DEBUG
                debugApplySeconds = (ContinuousClock.now - applyStart) / .seconds(1)
                #endif
            } catch {
                NSLog("Room: import refused: \(error)")
                message = "The sidebar changed while the preview was made; nothing was imported. Pick the source again."
                phase = .ready
                progress = nil
                return
            }
        }
        self.applied = applied
        var history = HistoryImportResult()
        if let profileID = plan.historyProfile, let model = store.sidebar.profiles.first(where: { $0.id == profileID }), !plan.history.isEmpty {
            if let engine = await engineProfile?(model), let profileHistory = engine.history {
                #if DEBUG
                let historyStart = ContinuousClock.now
                defer {
                    debugHistorySeconds = (ContinuousClock.now - historyStart) / .seconds(1)
                    debugHistoryBatches = plan.history.count
                }
                #endif
                for (index, batch) in plan.history.enumerated() {
                    progress = ImportProgress(fraction: Double(index) / Double(plan.history.count),
                                              step: "Adding history (\(index * ImportPlanner.historyBatchSize) of \(plan.preview.historyURLs))…")
                    history = history + (await profileHistory.importEntries(batch))
                }
            } else {
                message = "History was not imported: the engine has no history for \(model.name)."
            }
        }
        historyResult = history
        // Passwords through the engine's importer (Chrome's PasswordImporter on RoomCore).
        var passwords: PasswordImportResult?
        if wantsPasswords, let csv = passwordsCSV, let model = store.sidebar.profiles.first(where: { $0.id == passwordsProfile }) {
            progress = ImportProgress(fraction: 1, step: "Adding passwords…")
            if let engine = await engineProfile?(model) {
                passwords = await engine.importPasswords(csv: csv, conflicts: passwordConflicts)
            } else {
                passwords = PasswordImportResult(status: .unavailable)
            }
            passwordsResult = passwords
            if let passwords, passwords.status != .success { message = Self.passwordsFailure(passwords.status) }
        }
        // Extensions: their store pages, one at a time, in the space the bookmarks went to (or the active one).
        storePagesOpened = 0
        if wantsExtensions {
            let ids = webStoreExtensions.map(\.id).filter(chosenExtensions.contains)
            storePagesOpened = openStorePages?(ids, targetSpace ?? applied.spaces.first) ?? 0
        }
        progress = nil
        let summary = Self.summary(source: sourceName, applied: applied, history: history, passwords: passwords, storePages: storePagesOpened)
        phase = .done(summary)
        announce?(summary)
    }

    static func summary(source: String, applied: ImportApplied, history: HistoryImportResult, passwords: PasswordImportResult? = nil,
                        storePages: Int = 0) -> String {
        var parts: [String] = []
        func add(_ count: Int, _ one: String, _ many: String) { if count > 0 { parts.append("\(count) \(count == 1 ? one : many)") } }
        add(applied.spaces.count, "space", "spaces")
        add(applied.pinned, "pinned tab", "pinned tabs")
        add(applied.folders, "folder", "folders")
        add(applied.essentials, "essential", "essentials")
        add(applied.today, "Today tab", "Today tabs")
        add(history.urls, "history page", "history pages")
        if let passwords, passwords.status == .success {
            add(passwords.imported, "password", "passwords")
            let kept = passwords.conflicts - passwords.replaced
            if kept > 0 { parts.append("\(kept) saved \(kept == 1 ? "password" : "passwords") kept") }
            if passwords.skipped > 0 { parts.append("\(passwords.skipped) password \(passwords.skipped == 1 ? "row" : "rows") skipped") }
        }
        if storePages > 0 { parts.append("\(storePages) extension \(storePages == 1 ? "page" : "pages") to open, one at a time") }
        return parts.isEmpty ? "Nothing new to import from \(source)" : "Imported from \(source): " + parts.joined(separator: ", ")
    }

    static func passwordsFailure(_ status: PasswordImportResult.Status) -> String {
        switch status {
        case .badFormat: "Passwords were not imported: the file has no header Room recognises (name, url, username, password)."
        case .tooLarge: "Passwords were not imported: the file is over 1000 KB."
        case .tooMany: "Passwords were not imported: the file has more rows than one import takes."
        case .busy: "Passwords were not imported: another import is still running."
        case .unavailable: "Passwords were not imported: this profile has no password store."
        default: "Passwords were not imported: the file could not be read."
        }
    }

    /// The Passwords box's result line.
    var passwordsResultLine: String? {
        guard let result = passwordsResult else { return nil }
        guard result.status == .success else { return Self.passwordsFailure(result.status) }
        var line = "\(result.imported) imported"
        if result.conflicts > 0 {
            line += result.replaced > 0 ? ", \(result.replaced) saved replaced" : ", \(result.conflicts) saved kept"
        }
        if result.skipped > 0 { line += ", \(result.skipped) skipped" }
        return line
    }

    func cancel() {
        work?.cancel()
        work = nil
        generation += 1
    }

    // MARK: Counts for the rows

    func countLine(_ result: Result<ImportedBookmarks, ImportError>?) -> String? {
        switch result {
        case .success(let value): "\(value.links) bookmarks in \(value.folders) folders"
        case .failure(let error): error.message
        case nil: nil
        }
    }

    func historyLine() -> String? {
        switch scan?.history {
        case .success(let value): "\(value.urls.count) pages, \(value.visits) visits"
        case .failure(let error): error.message
        case nil: nil
        }
    }

    func sidebarLine() -> String? {
        switch scan?.sidebar {
        case .success(let value):
            "\(value.spaces.count) spaces, \(value.profiles.count) profiles, \(value.essentialsCount) essentials, "
                + "\(value.pinnedLinks) pinned in \(value.folders) folders, \(value.todayTabs) Today tabs"
        case .failure(let error): error.message
        case nil: nil
        }
    }

    func extensionsLine() -> String? {
        switch scan?.extensions {
        case .success(let value): "\(value.extensions.count) found"
        case .failure(let error): error.message
        case nil: nil
        }
    }

    var previewLine: String {
        guard let preview = plan?.preview else { return "" }
        var parts: [String] = []
        func add(_ count: Int, _ label: String) { if count > 0 { parts.append("\(count) \(label)") } }
        add(preview.newProfiles, preview.newProfiles == 1 ? "new profile" : "new profiles")
        add(preview.spaces, preview.spaces == 1 ? "new space" : "new spaces")
        add(preview.folders, preview.folders == 1 ? "folder" : "folders")
        add(preview.pinned, "pinned")
        add(preview.essentials, preview.essentials == 1 ? "essential" : "essentials")
        add(preview.today, "Today tabs")
        add(preview.historyURLs, "history pages")
        if wantsExtensions {
            let pages = webStoreExtensions.count { chosenExtensions.contains($0.id) }
            parts.append("\(pages) extension store \(pages == 1 ? "page" : "pages") (one at a time)")
        }
        if wantsPasswords { parts.append("the passwords file") }
        return parts.isEmpty ? "Nothing new to import." : "Will add " + parts.joined(separator: ", ") + "."
    }

    var previewNotes: String {
        guard let preview = plan?.preview else { return "" }
        var parts: [String] = []
        if preview.duplicates > 0 { parts.append("\(preview.duplicates) duplicates skipped") }
        if preview.foldersFlattened > 0 { parts.append("\(preview.foldersFlattened) folders deeper than \(FolderRules.maxDepth) levels flattened") }
        if preview.essentialsOverflow > 0 { parts.append("\(preview.essentialsOverflow) past the Essentials cap (\(EntryRules.essentialsCap)) pinned instead") }
        if !preview.skipped.isEmpty { parts.append("\(preview.skipped.count) items skipped") }
        return parts.joined(separator: "; ")
    }
}

/// The sheet (a SwiftUI leaf in an `NSHostingController`; its rows update
/// when a read or a mapping ends, not per keystroke).
struct ImportSheet: View {
    @Bindable var model: ImportSheetModel
    let onChooseFile: () -> Void
    let onChoosePasswords: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Another Browser").font(.headline)
            sourceList
            if !model.profiles.isEmpty {
                Picker("From profile", selection: $model.selectedProfile) {
                    ForEach(model.profiles) { Text($0.name).tag(Optional($0.directory)) }
                }
                .fixedSize()
                .disabled(model.phase == .importing)
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let progress = model.progress {
                ProgressView(value: progress.fraction) { Text(progress.step).font(.callout) }
            }
            if model.scan != nil, model.phase != .reading {
                whatToImport
                placement
                preview
            }
            passwordsBox
            // 4.3b task 7: one line.
            Text(ImportSheetText.cookies)
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                if case .done(let summary) = model.phase {
                    Text(summary).font(.callout).lineLimit(2)
                }
                Spacer()
                if case .done = model.phase {
                    Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", action: onClose).keyboardShortcut(.cancelAction).disabled(model.phase == .importing)
                    Button("Import") { Task { await model.performImport() } }
                        .keyboardShortcut(.defaultAction).disabled(!model.canImport)
                }
            }
        }
        .padding(20)
        .frame(width: ImportSheetMetrics.width, height: ImportSheetMetrics.height)
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(selection: Binding(get: { model.selectedSourceID }, set: { model.pick($0) })) {
                ForEach(model.sources) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                        if let note = source.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    }
                    .tag(Optional(source.id))
                }
            }
            .frame(height: 130)
            .disabled(model.phase == .importing)
            HStack {
                Button("Choose a File or Folder…", action: onChooseFile).disabled(model.phase == .importing)
                Spacer()
                if model.sources.isEmpty { Text("No other browser found.").font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var whatToImport: some View {
        GroupBox("Import") {
            VStack(alignment: .leading, spacing: 4) {
                if let line = model.countLine(model.scan?.bookmarks) {
                    row("Bookmarks", line, isOn: $model.importBookmarks, available: model.scan?.bookmarks?.value != nil)
                }
                if let line = model.sidebarLine() {
                    row("Arc sidebar", line, isOn: $model.importSidebar, available: model.scan?.sidebar?.value != nil)
                }
                if let line = model.historyLine() {
                    row("History", line, isOn: $model.importHistory, available: model.scan?.history?.value != nil)
                }
                if let line = model.extensionsLine() {
                    row("Extensions", line + (model.webStoreExtensions.isEmpty ? "" : "; their Web Store pages open one at a time"),
                        isOn: $model.importExtensions, available: !model.webStoreExtensions.isEmpty)
                    extensionsList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    /// The Web Store extensions with a checkbox each; unpacked ones with their reason.
    @ViewBuilder private var extensionsList: some View {
        let skipped = model.scan?.extensions?.value?.skipped ?? []
        if model.importExtensions, !model.webStoreExtensions.isEmpty || !skipped.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.webStoreExtensions, id: \.id) { item in
                    Toggle(isOn: Binding(get: { model.chosenExtensions.contains(item.id) }, set: { on in
                        if on { model.chosenExtensions.insert(item.id) } else { model.chosenExtensions.remove(item.id) }
                    })) {
                        Text(item.enabled ? item.name : "\(item.name) (disabled there)").font(.callout)
                    }
                    .toggleStyle(.checkbox)
                }
                ForEach(Array(skipped.enumerated()), id: \.offset) { _, item in
                    Text("\(item.item): \(item.reason)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.leading, 20)
            .disabled(model.phase == .importing)
        }
    }

    /// Passwords (4.3b): a CSV exported from the other browser, imported by the engine (Chrome's importer).
    private var passwordsBox: some View {
        GroupBox("Passwords") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Toggle("Passwords", isOn: $model.importPasswords).toggleStyle(.checkbox).disabled(model.passwordsFile == nil)
                    Text(model.passwordsLine ?? "Export them from your other browser as a CSV file (Chrome: Password Manager ▸ Settings ▸ "
                         + "Export; Safari: File ▸ Export ▸ Passwords), then choose it.")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("Choose CSV…", action: onChoosePasswords)
                }
                if model.passwordsFile != nil {
                    Picker("When a site already has a saved password", selection: $model.passwordConflicts) {
                        Text("Keep the saved one").tag(PasswordImportConflictPolicy.skip)
                        Text("Replace it").tag(PasswordImportConflictPolicy.replace)
                    }
                    .fixedSize()
                }
                if let line = model.passwordsResultLine { Text(line).font(.callout) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
            .disabled(model.phase == .importing)
        }
    }

    private func row(_ title: String, _ detail: String, isOn: Binding<Bool>, available: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(title, isOn: isOn).toggleStyle(.checkbox).disabled(!available || model.phase == .importing)
            Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    @ViewBuilder private var placement: some View {
        GroupBox("Where") {
            VStack(alignment: .leading, spacing: 6) {
                if model.scan?.bookmarks?.value != nil {
                    Picker("Bookmarks", selection: $model.layout) {
                        Text("Into one space").tag(ImportOptions.Layout.oneSpace)
                        Text("One space per folder").tag(ImportOptions.Layout.spacePerFolder)
                    }
                    .pickerStyle(.segmented).fixedSize()
                    Toggle("Bookmarks bar into Essentials (up to \(EntryRules.essentialsCap))", isOn: $model.barIntoEssentials)
                        .toggleStyle(.checkbox)
                }
                HStack {
                    // The space is the bookmarks'; the profile is a new space's and the history's.
                    if model.scan?.bookmarks?.value != nil {
                        Picker("Space", selection: $model.targetSpace) {
                            Text("New space named \u{201C}\(model.newSpaceName)\u{201D}").tag(UUID?.none)
                            ForEach(model.store.sidebar.spaces, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .fixedSize()
                    }
                    if model.targetSpace == nil, model.scan?.bookmarks?.value != nil || model.scan?.history?.value != nil {
                        Picker("Into profile", selection: $model.targetProfile) {
                            ForEach(model.store.sidebar.profiles, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .fixedSize()
                    }
                }
                if model.scan?.sidebar?.value != nil {
                    Text("Arc's spaces become new spaces, each in a profile named as in Arc (made when Room has none by that name).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
            .disabled(model.phase == .importing)
        }
    }

    @ViewBuilder private var preview: some View {
        if model.plan != nil, model.phase == .ready {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.previewLine).font(.callout)
                if !model.previewNotes.isEmpty {
                    Text(model.previewNotes).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let skipped = model.plan?.preview.skipped, !skipped.isEmpty {
                    DisclosureGroup("Skipped") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(skipped.enumerated()), id: \.offset) { _, item in
                                    Text("\(item.item): \(item.reason)").font(.caption).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 80)
                    }
                    .font(.caption)
                }
            }
        }
    }
}
