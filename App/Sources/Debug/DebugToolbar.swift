import AppKit
import Engine
import SwiftUI

/// Chapter 1 throwaway toolbar in the sidebar placeholder: address field,
/// navigation, hidden pages, DevTools and the overlay spikes.
struct DebugToolbar: View {
    @Bindable var session: DebugSession
    let overlays: OverlaySpike
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search or enter address", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($addressFocused)
                .onSubmit { session.open(address) }
                .onChange(of: session.addressFocusRequest) { addressFocused = true }
                .onChange(of: session.current?.url, initial: true) { _, url in
                    if !addressFocused { address = url?.absoluteString ?? "" }
                }

            HStack(spacing: 4) {
                button("chevron.left", "Back") { session.current?.goBack() }
                    .disabled(session.current?.canGoBack != true)
                button("chevron.right", "Forward") { session.current?.goForward() }
                    .disabled(session.current?.canGoForward != true)
                if session.current?.isLoading == true {
                    button("xmark", "Stop") { session.current?.stop() }
                } else {
                    button("arrow.clockwise", "Reload") { session.current?.reload() }
                }
                Spacer()
                button("plus", "New page") { session.newPage(DebugSession.url(from: "duckduckgo.com")) }
                button("eye.slash", "New hidden page") {
                    session.newPage(DebugSession.url(from: "en.wikipedia.org"), hidden: true, select: false)
                }
                button("hammer", "DevTools") { session.host.toggleDevTools() }
            }

            if let current = session.current, current.isLoading {
                ProgressView(value: current.loadProgress).controlSize(.small)
            }

            HStack(spacing: 4) {
                Button("Overlay") { overlays.toggleGlassOverlay() }
                Button("Hover reveal") { overlays.isHoverRevealEnabled.toggle() }
                    .foregroundStyle(overlays.isHoverRevealEnabled ? Color.accentColor : Color.primary)
            }
            .controlSize(.small)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(session.pages.enumerated()), id: \.offset) { index, page in
                        PageRow(page: page, selected: index == session.currentIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { session.select(index) }
                    }
                }
            }

            if let status = session.statusText {
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

private struct PageRow: View {
    let page: any WebContents
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let favicon = page.favicon {
                Image(nsImage: favicon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "globe").frame(width: 16, height: 16)
            }
            Text(page.title ?? page.url?.host() ?? "New page").lineLimit(1)
            Spacer()
            if page.isAudible { Image(systemName: "speaker.wave.2.fill").font(.caption) }
            if page.state != .alive { Text(String(describing: page.state)).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(selected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
