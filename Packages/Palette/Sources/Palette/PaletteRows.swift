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

    /// An unused slot's content.
    static let empty = PaletteRow(id: "", icon: .symbol(.search), title: "", startsGroup: false)
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
    /// One per possible row (`OmniboxResult.limit`).
    static let slots = 8

    var body: some View {
        // Fixed slots, identified by position and always laid out at full
        // height: a keystroke changes the rows' content, not SwiftUI's
        // geometry (2.4b profile: SwiftUI rebuilt and re-measured every row on
        // each keystroke). Unused slots are transparent; the panel clips the
        // list to the rows in use.
        VStack(spacing: 0) {
            ForEach(0..<Self.slots, id: \.self) { index in
                let row = index < model.rows.count ? model.rows[index] : nil
                PaletteRowView(row: row ?? .empty, highlighted: model.highlighted == index) { model.onDelete?(index) }
                    .padding(.top, row?.startsGroup == true ? PaletteMetrics.groupGap : 0)
                    .opacity(row == nil ? 0 : 1)
                    .allowsHitTesting(row != nil)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active = phase { model.pointerMoved(over: index) }
                    }
                    .onTapGesture { model.onClick?(index, NSEvent.modifierFlags) }
            }
            Spacer(minLength: 0)
        }
        .padding(PaletteMetrics.listPadding)
        .transaction { $0.animation = nil }
    }
}

/// Fonts and colours made once: building `Font(NSFont)` and `Color(nsColor:)`
/// in every row body made SwiftUI resolve them again on each keystroke.
/// The colours stay dynamic (`NSColor`s resolve when drawn).
private enum Style {
    static let row = Font(Typography.row)
    static let secondary = Font(Typography.secondary)
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let chip = Color(nsColor: Palette.sidebarHover)
    static let highlight = Color(nsColor: Palette.sidebarMultiSelection)
}

private struct PaletteRowView: View {
    let row: PaletteRow
    let highlighted: Bool
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: SidebarMetrics.faviconTitleGap + 2) {
            icon.frame(width: PaletteMetrics.iconSize, height: PaletteMetrics.iconSize)
            // Title and detail in one text: one resolve and one measure per row
            // (separate texts with layout priorities were most of a keystroke's
            // SwiftUI time, 2.4b profile). The detail is cut first.
            label
                .font(Style.row)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let space = row.spaceName {
                Text(space)
                    .font(Style.secondary)
                    .foregroundStyle(Style.secondaryLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Style.chip))
                    .lineLimit(1)
            }
            if highlighted, let hint = row.hint {
                Text(hint)
                    .font(Style.secondary)
                    .foregroundStyle(Style.secondaryLabel)
                    .lineLimit(1)
            }
            if row.isDeletable {
                // Spec §C: hover shows an × on the right (also on the highlighted row, for ⇧Delete's target).
                Image(systemName: Symbol.closeTab.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Style.secondaryLabel)
                    .frame(width: PaletteMetrics.deleteButtonSize, height: PaletteMetrics.deleteButtonSize)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: delete)
                    .accessibilityLabel("Remove from History")
                    .accessibilityAddTraits(.isButton)
                    .opacity(highlighted || hovering ? 1 : 0)
            }
        }
        .onHover { hovering = $0 }
        .padding(.horizontal, SidebarMetrics.rowContentInset)
        .frame(height: PaletteMetrics.rowHeight)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Style.highlight)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private var label: Text {
        let title = Text(row.title).foregroundStyle(Style.label)
        guard let detail = row.detail else { return title }
        return Text("\(title)  \(Text(detail).foregroundStyle(Style.secondaryLabel))")
    }

    @ViewBuilder private var icon: some View {
        switch row.icon {
        case .favicon(let image, let domain, let dimmed):
            FaviconRepresentable(image: image, domain: domain, dimmed: dimmed)
        case .symbol(let symbol):
            Image(systemName: symbol.name)
                .font(.system(size: 13))
                .foregroundStyle(Style.secondaryLabel)
        case .systemName(let name):
            Image(systemName: name)
                .font(.system(size: 13))
                .foregroundStyle(Style.secondaryLabel)
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
