import AppKit
import Chrome
import Engine
import Model
import Store
import Tabs

/// Settings ▸ Spaces' profiles (ROADMAP 4.4 task 7; spec §B): rename (only
/// the label: the engine keeps the profile under its id, B-22) and delete
/// (its spaces' entries to the Archive, its pages closed, then the engine
/// deletes its data). The Default profile (the first) stays.
extension AppDelegate {
    /// What a deletion would take, for the confirmation.
    struct ProfileDeletionCounts: Equatable {
        var spaces: Int
        var entries: Int
    }

    func profileDeletionCounts(_ id: UUID) -> ProfileDeletionCounts {
        guard let sidebar = store?.sidebar else { return ProfileDeletionCounts(spaces: 0, entries: 0) }
        let spaces = Set(sidebar.spaces.filter { $0.profileID == id }.map(\.id))
        let entries = sidebar.entries.values.count { $0.kind != .folder && ($0.profileID == id || $0.spaceID.map(spaces.contains) == true) }
        return ProfileDeletionCounts(spaces: spaces.count, entries: entries)
    }

    /// Renames the profile; the error's message when refused.
    @discardableResult
    func renameProfile(_ id: UUID, to name: String) -> String? {
        guard let store else { return "No state" }
        do {
            let given = try store.sidebar.renameProfile(id, to: name)
            extensions?.rename(profile: id, to: given)
            return nil
        } catch .emptyName {
            return "A profile needs a name."
        } catch {
            return "\(error)"
        }
    }

    /// A new profile with no space yet (Settings ▸ Spaces' New Profile…;
    /// the space form's popup offers it, as the sidebar's New Profile… does).
    @discardableResult
    func newProfile(named name: String) -> Model.Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let store, !trimmed.isEmpty else { return nil }
        return store.sidebar.createProfile(name: trimmed)
    }

    /// The confirmation (a sheet on `window`), then the deletion and its toast.
    func confirmDeleteProfile(_ id: UUID, over window: NSWindow?) {
        guard let store, let profile = store.sidebar.profiles.first(where: { $0.id == id }) else { return }
        let counts = profileDeletionCounts(id)
        let alert = NSAlert()
        alert.messageText = "Delete the profile “\(profile.name)”?"
        let spaces = counts.spaces == 1 ? "Its space" : "Its \(counts.spaces) spaces"
        let entries = counts.entries == 1 ? "1 tab" : "\(counts.entries) tabs"
        alert.informativeText = (counts.spaces == 0 ? "It has no space. " : "\(spaces) and \(entries) (pinned, Today and Essentials) go to the Archive (⇧⌘L). ")
            + "Its cookies, history, passwords, permissions and site data are deleted from this Mac. This cannot be undone."
        alert.addButton(withTitle: "Delete Profile")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let proceed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                guard let self else { return }
                let outcome = await self.deleteProfile(id)
                self.toastCenter?.show(Toast(id: "profile-deleted", symbol: .profile, message: outcome.message(name: profile.name)))
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: proceed) } else { proceed(alert.runModal()) }
    }

    enum ProfileDeletionOutcome: Equatable {
        case deleted
        /// The model row went; the engine's data could not be removed now.
        case dataLeft(String)
        case refused(String)

        func message(name: String) -> String {
            switch self {
            case .deleted: "Deleted the profile “\(name)” and its data"
            case .dataLeft(let why): "Deleted the profile “\(name)”; its data remains: \(why)"
            case .refused(let why): "“\(name)” was not deleted: \(why)"
            }
        }
    }

    /// Deletes without asking (the confirmation is the caller's): every page
    /// of the profile closes, the store archives and removes its spaces and
    /// the profile, its settings go, then the engine deletes its data. An
    /// engine profile not loaded this session is loaded to be deleted (its
    /// directory is from an earlier one).
    func deleteProfile(_ id: UUID) async -> ProfileDeletionOutcome {
        guard let store, !windows.all.isEmpty else { return .refused("no state") }
        guard let model = store.sidebar.profiles.first(where: { $0.id == id }) else { return .refused("no such profile") }
        guard model.id != store.sidebar.profiles.first?.id else { return .refused("the Default profile stays") }
        let spaces = Set(store.sidebar.spaces.filter { $0.profileID == id }.map(\.id))
        guard store.sidebar.spaces.contains(where: { !spaces.contains($0.id) }) else {
            return .refused("every space uses it; give one space another profile first")
        }
        // In every window (4.8a: a page lives in the window that shows it).
        for entry in store.sidebar.entries.values where entry.profileID == id || entry.spaceID.map(spaces.contains) == true {
            for session in windows.all { session.tabs?.unload(entry.id) }
        }
        do {
            try store.sidebar.deleteProfile(id)
        } catch {
            return .refused("\(error)")
        }
        store.settings.update { $0.searchEngineByProfile[id.uuidString] = nil }
        extensions?.remove(profile: id)
        var engineProfile = forgetEngineProfile(id)
        if engineProfile == nil {
            engineProfile = try? await engine.createProfile(name: TabController.engineProfileName(for: model))
        }
        guard let engineProfile else { return .dataLeft("the engine could not open it") }
        engineProfile.downloadsDelegate = nil
        // Pages close asynchronously (beforeunload, the engine's own teardown): wait for them, at most 5 s.
        for _ in 0..<50 {
            do {
                try await engine.deleteProfile(engineProfile)
                NSLog("Room: profile %@ deleted with its engine data", id.uuidString)
                return .deleted
            } catch EngineError.profileInUse {
                try? await Task.sleep(for: .milliseconds(100))
            } catch {
                NSLog("Room: profile %@ deleted; the engine's data remains: %@", id.uuidString, "\(error)")
                return .dataLeft("\(error)")
            }
        }
        return .dataLeft("a page of it would not close")
    }
}

// MARK: - Settings' services, Clear browsing data

extension AppDelegate {
    func profileServices() -> ProfileServices {
        ProfileServices(
            rename: { [weak self] id, name in
                guard let self else { return "No state" }
                return renameProfile(id, to: name)
            },
            create: { [weak self] name in self?.newProfile(named: name) },
            delete: { [weak self] id in self?.confirmDeleteProfile(id, over: self?.settingsWindow?.window) },
            counts: { [weak self] id in self?.profileDeletionCounts(id) ?? ProfileDeletionCounts(spaces: 0, entries: 0) },
            routingRules: { [weak self] space in
                guard let self else { return }
                let hasRules = store?.sidebar.routingRules.contains { $0.targetSpaceID == space } ?? false
                showRoutingRules(newRule: hasRules ? nil : (host: "", space: space), over: settingsWindow?.window)
            },
            engineProfile: { [weak self] id in
                guard let self, let model = store?.sidebar.profiles.first(where: { $0.id == id }) else { return nil }
                return await engineProfile(for: model)
            },
            clearBrowsingData: { [weak self] profile, kinds, period in
                await self?.clearBrowsingData(profile: profile, kinds: kinds, since: period) ?? ""
            },
            openPage: { [weak self] url in
                self?.tabs?.openNewTab(url: url.absoluteString, transition: .link)
                self?.windowController?.window?.makeKeyAndOrderFront(nil)
            })
    }

    /// Clear browsing data for one profile or all (4.4b): the engine clears,
    /// the downloads list follows, and a toast says what went.
    @discardableResult
    func clearBrowsingData(profile id: UUID?, kinds: BrowsingDataKinds, since period: BrowsingDataPeriod) async -> String {
        guard let store else { return "" }
        let models = store.sidebar.profiles.filter { id == nil || $0.id == id }
        let start = period.start(before: Date())
        for model in models {
            guard let engineProfile = await engineProfile(for: model) else { continue }
            await engineProfile.clearBrowsingData(kinds, since: period)
            if kinds.contains(.downloads) { downloads?.list.clearFinished(of: engineProfile, since: start) }
        }
        let what = ClearBrowsingDataSheet.kindRows.filter { kinds.contains($0.kind) }.map(\.short)
        let list = what.count > 1 ? what.dropLast().joined(separator: ", ") + " and " + what.last! : what.first ?? "nothing"
        let range = period == .allTime ? "of all time" : "from the " + ClearBrowsingDataSheet.periodTitle(period).lowercased()
        let whose = models.count == 1 && store.sidebar.profiles.count > 1 ? " in “\(models[0].name)”" : ""
        let line = "Cleared \(list) \(range)\(whose)"
        toastCenter?.show(Toast(id: "browsing-data-cleared", symbol: .success, message: line))
        NSLog("Room: %@", line)
        return line
    }
}
