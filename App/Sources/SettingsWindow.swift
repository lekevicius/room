import AppKit
import Chrome
import Omnibox
import Store
import SwiftUI

/// Settings (⌘,): a SwiftUI leaf in its own window (PLAN §4 UI framework).
/// Phase 2.4b brings only the Search section the suggest client needs (the
/// default engine and the suggestions switch, CLAUDE.md); Settings v0 (2.8)
/// adds the rest and 4.4 the full window.
final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private struct SettingsView: View {
    let settings: SettingsStore

    /// The download folder (spec §F, ROADMAP 2.6 task 1); `nil` in Settings is ~/Downloads.
    private var folder: URL {
        DownloadRules.folder(setting: settings.settings.downloadDirectory,
                             downloads: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }

    private var folderName: String {
        FileManager.default.displayName(atPath: folder.path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        settings.update { $0.downloadDirectory = url.standardizedFileURL == downloads.standardizedFileURL ? nil : url.path }
    }

    var body: some View {
        Form {
            Section("Search") {
                Picker("Search engine", selection: Binding(
                    get: { settings.settings.searchEngine },
                    set: { id in settings.update { $0.searchEngine = id } })) {
                    ForEach(SearchEngine.all) { engine in Text(engine.name).tag(engine.id) }
                }
                Toggle(isOn: Binding(
                    get: { settings.settings.searchSuggestions },
                    set: { on in settings.update { $0.searchSuggestions = on } })) {
                    Text("Show search suggestions")
                    Text("Sends what you type in the palette to the search engine. Off: nothing leaves Room while you type.")
                }
            }
            Section("Links") {
                Toggle(isOn: Binding(
                    get: { settings.settings.peekOffSiteLinks },
                    set: { on in settings.update { $0.peekOffSiteLinks = on } })) {
                    Text("Open links to other sites from pinned tabs in Peek")
                    Text("Sign-in pages, form posts and redirects still open in the tab.")
                }
            }
            Section("Downloads") {
                LabeledContent("Save downloads to") {
                    HStack {
                        Text(folderName).foregroundStyle(.secondary)
                        Button("Change…") { chooseFolder() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
