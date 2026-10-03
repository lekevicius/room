import AppKit
import Omnibox
import Store
import SwiftUI

/// Settings (⌘,): a SwiftUI leaf in its own window (PLAN §4 UI framework).
/// Phase 2.4b brings only the Search section the suggest client needs (the
/// default engine and the suggestions switch, CLAUDE.md); Settings v0 (2.8)
/// adds the rest and 4.4 the full window.
final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 160), styleMask: [.titled, .closable],
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
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
