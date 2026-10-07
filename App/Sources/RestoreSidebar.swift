import AppKit
import Chrome
import Engine
import Model
import Store
import SwiftUI

/// Help ▸ Restore Sidebar… (spec §H, ROADMAP 4.1b task 6): a sheet listing
/// the rolling backups (`BackupScheduler`) with their dates and counts. A
/// restore unloads every page, backs the current state up first (a
/// `-before-restore` backup), replaces the spaces, entries, splits, the
/// windows' spaces and selections and the Archive from the chosen backup in
/// one write (`RoomStore.restoreSidebar`), and rebuilds the window's sidebar
/// and card from the store, as at launch.
extension AppDelegate {
    @objc func showRestoreSidebar(_ sender: Any?) {
        guard let store, let window = windowController?.window, restoreSheet == nil else { return }
        ensureWindow()
        let backups = store.backups
        let infos = backups.list().compactMap { try? backups.info($0) }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400), styleMask: [.titled], backing: .buffered,
                             defer: true)
        let content = RestoreSidebarList(backups: infos, onCancel: { [weak self] in self?.closeRestoreSheet() },
                                         onRestore: { [weak self] info in
                                             self?.closeRestoreSheet()
                                             self?.restoreSidebar(from: info.file)
                                         })
        sheet.contentViewController = NSHostingController(rootView: content)
        restoreSheet = sheet
        window.beginSheet(sheet)
    }

    private func closeRestoreSheet() {
        guard let sheet = restoreSheet else { return }
        restoreSheet = nil
        sheet.sheetParent?.endSheet(sheet)
    }

    /// The restore itself (the sheet's Restore; DEBUG spikes call it).
    @discardableResult
    func restoreSidebar(from file: BackupFile) -> Bool {
        guard let store, let active = activeWindow, let tabs = active.tabs, let sidebar = active.sidebar, let backupScheduler else { return false }
        hideLibrary()
        // Every page in every window goes; their back/forward lists land in the state being backed up.
        for session in windows.all {
            guard let pages = session.tabs else { continue }
            for id in pages.loadedEntryIDs { pages.unload(id) }
            pages.deactivate()
        }
        store.flush()
        let backup: RoomState
        do {
            try backupScheduler.takeNow(label: RoomBackups.beforeRestoreLabel)
            backup = try store.backups.loadState(file).state
        } catch {
            NSLog("Room: Restore Sidebar failed before anything changed: \(error)")
            let alert = NSAlert()
            alert.messageText = "The sidebar could not be restored"
            alert.informativeText = "\(error.localizedDescription)\nNothing was changed."
            alert.runModal()
            tabs.showSelection()
            return false
        }
        // The backup's windows map onto the open ones, the active first (4.8a).
        let open = [active.id] + windows.all.map(\.id).filter { $0 != active.id }
        store.restoreSidebar(from: backup, window: sidebar.windowID, open: open)
        // The sidebars rebuilt themselves on the store's change; the active window's card shows its
        // restored selection, as at launch; the others load theirs when they are next key.
        for session in windows.all where session !== active { session.selectionShown = false }
        showSelection(of: active)
        let date = file.date.formatted(date: .abbreviated, time: .shortened)
        toastCenter?.show(Toast(id: "sidebar-restored", symbol: .restore, message: "Sidebar restored from \(date)"))
        NSLog("Room: sidebar restored from %@ (%ld spaces, %ld entries, %ld archived)", file.url.lastPathComponent,
              backup.spaces.count, backup.entries.count, backup.archive.count)
        return true
    }
}

/// The sheet's list (a SwiftUI leaf, AGENTS.md).
struct RestoreSidebarList: View {
    let backups: [BackupInfo]
    let onCancel: () -> Void
    let onRestore: (BackupInfo) -> Void
    @State private var selection: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore Sidebar").font(.headline)
            Text("Spaces, tabs and the Archive come back as they were in the backup. The sidebar as it is now is backed up first.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if backups.isEmpty {
                Text("No backups yet. Room takes one at launch and every 30 minutes while the sidebar changes.")
                    .font(.callout).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(backups, id: \.file.url, selection: $selection) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.file.date.formatted(date: .abbreviated, time: .standard))
                            Text("\(info.entries) entries · \(info.spaces) spaces · \(info.archived) archived")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if info.file.label == RoomBackups.beforeRestoreLabel {
                            Text("before restore").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Restore") {
                    if let info = backups.first(where: { $0.file.url == selection }) { onRestore(info) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding(20)
        .frame(width: 460, height: 400)
    }
}
