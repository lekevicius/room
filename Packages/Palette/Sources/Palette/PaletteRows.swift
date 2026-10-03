import AppKit
import Design
import Observation
import Sidebar
import SwiftUI

/// One row as drawn.
struct PaletteRow: Identifiable, Equatable {
    enum Icon: Equatable {
        /// A favicon, or the letter tile for `domain` without one (spec §I.2).
        case favicon(NSImage?, domain: String, dimmed: Bool)
        case symbol(Symbol)
        /// A command's SF Symbol by name.
        case systemName(String)
    }

    var id: String
    var icon: Icon
    var title: String
    var detail: String?
    /// "Switch to Tab" on entries.
    var hint: String?
    /// Another space's name (spec §C chip).
    var spaceName: String?
    /// The first row of a group after the first: a small gap above it.
    var startsGroup: Bool
    /// A history row: an × removes it (spec §C).
    var isDeletable = false
}

/// The rows and the highlight; the controller writes it, the SwiftUI list reads it.
@Observable
final class PaletteRowsModel {
    var rows: [PaletteRow] = []
    var highlighted: Int?
    @ObservationIgnored var onHover: ((Int) -> Void)?
    @ObservationIgnored var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    @ObservationIgnored var onDelete: ((Int) -> Void)?
    /// The pointer only highlights a row when it moved: rows changing under a
    /// still pointer must not take the highlight from the keyboard's top hit.
    @ObservationIgnored var lastPointer: NSPoint?

    func pointerMoved(over index: Int) {
        let location = NSEvent.mouseLocation
        defer { lastPointer = location }
        guard let lastPointer, lastPointer != location else { return }
        onHover?(index)
    }
}

/// The result list (SwiftUI leaf in an `NSHostingView`, PLAN §4 UI framework).
/// Colours are dynamic `NSColor`s, resolved when drawn: the overlay is reused
/// across opens, and SwiftUI's `.primary` kept the light appearance after a
/// switch to dark while it was out of the window (2.4a capture).
struct PaletteRowsView: View {
    let model: PaletteRowsModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                PaletteRowView(row: row, highlighted: model.highlighted == index) { model.onDelete?(index) }
                    .padding(.top, row.startsGroup ? PaletteMetrics.groupGap : 0)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active = phase { model.pointerMoved(over: index) }
                    }
                    .onTapGesture { model.onClick?(index, NSEvent.modifierFlags) }
            }
            Spacer(minLength: 0)
        }
        .padding(PaletteMetrics.listPadding)
    }
}

private struct PaletteRowView: View {
    let row: PaletteRow
    let highlighted: Bool
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: SidebarMetrics.faviconTitleGap + 2) {
            icon.frame(width: PaletteMetrics.iconSize, height: PaletteMetrics.iconSize)
            Text(row.title)
                .font(Font(Typography.row))
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let detail = row.detail {
                Text(detail)
                    .font(Font(Typography.row))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let space = row.spaceName {
                Text(space)
                    .font(Font(Typography.secondary))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: Palette.sidebarHover)))
                    .lineLimit(1)
            }
            if let hint = row.hint {
                Text(hint)
                    .font(Font(Typography.secondary))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .opacity(highlighted ? 1 : 0)
            }
            if row.isDeletable {
                // Spec §C: hover shows an × on the right (also on the highlighted row, for ⇧Delete's target).
                Button(action: delete) {
                    Image(systemName: Symbol.closeTab.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: PaletteMetrics.deleteButtonSize, height: PaletteMetrics.deleteButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from History")
                .accessibilityLabel("Remove from History")
                .opacity(highlighted || hovering ? 1 : 0)
            }
        }
        .onHover { hovering = $0 }
        .padding(.horizontal, SidebarMetrics.rowContentInset)
        .frame(height: PaletteMetrics.rowHeight)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Color(nsColor: Palette.sidebarMultiSelection))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    @ViewBuilder private var icon: some View {
        switch row.icon {
        case .favicon(let image, let domain, let dimmed):
            FaviconRepresentable(image: image, domain: domain, dimmed: dimmed)
        case .symbol(let symbol):
            Image(systemName: symbol.name)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        case .systemName(let name):
            Image(systemName: name)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }
}

/// The sidebar's favicon view (letter tiles, dimming) in a SwiftUI row.
private struct FaviconRepresentable: NSViewRepresentable {
    let image: NSImage?
    let domain: String
    let dimmed: Bool

    func makeNSView(context: Context) -> FaviconView {
        FaviconView(frame: NSRect(x: 0, y: 0, width: PaletteMetrics.iconSize, height: PaletteMetrics.iconSize))
    }

    func updateNSView(_ view: FaviconView, context: Context) {
        view.image = image
        view.letterSource = domain
        view.isUnloaded = dimmed
    }
}
