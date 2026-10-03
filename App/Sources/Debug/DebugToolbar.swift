import AppKit
import Engine
import SwiftUI
import Tabs

/// Chapter 1 throwaway, in the Debug ▸ Show Debug Toolbar panel until the
/// palette (Phase 2.4): an address field and navigation for the selected
/// tab, DevTools, and the overlay spikes. The flat page list it had is gone
/// (Phase 2.3): pages are the sidebar's entries.
struct DebugToolbar: View {
    let tabs: TabController
    let pageHost: PageHost
    let pageDelegate: PageUIDelegate
    let overlays: OverlaySpike
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search or enter address", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($addressFocused)
                .onSubmit {
                    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    tabs.navigateSelected(to: URLPrompt.url(from: trimmed))
                }
                .onChange(of: tabs.current?.url, initial: true) { _, url in
                    if !addressFocused { address = url?.absoluteString ?? "" }
                }

            HStack(spacing: 4) {
                button("chevron.left", "Back") { tabs.current?.goBack() }
                    .disabled(tabs.current?.canGoBack != true)
                button("chevron.right", "Forward") { tabs.current?.goForward() }
                    .disabled(tabs.current?.canGoForward != true)
                if tabs.current?.isLoading == true {
                    button("xmark", "Stop") { tabs.current?.stop() }
                } else {
                    button("arrow.clockwise", "Reload") { tabs.current?.reload() }
                }
                Spacer()
                button("hammer", "DevTools") { pageHost.toggleDevTools() }
            }

            if let current = tabs.current, current.isLoading {
                ProgressView(value: current.loadProgress).controlSize(.small)
            }

            HStack(spacing: 4) {
                Button("Overlay") { overlays.toggleGlassOverlay() }
                Button("Hover reveal") { overlays.isHoverRevealEnabled.toggle() }
                    .foregroundStyle(overlays.isHoverRevealEnabled ? Color.accentColor : Color.primary)
            }
            .controlSize(.small)
            if overlays.isHoverRevealEnabled || overlays.isGlassOverlayShown || overlays.overlayClickCount > 0 {
                Text("over page \(overlays.movesOverPage) · reveals \(overlays.revealCount) · overlay hover \(overlays.overlayHoverCount) click \(overlays.overlayClickCount)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("overlay-counters")
            }

            Spacer(minLength: 0)

            if let status = pageDelegate.statusText {
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 22, height: 22) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
    }
}
