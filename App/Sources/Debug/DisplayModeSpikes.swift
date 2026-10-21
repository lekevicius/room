#if DEBUG
import AppKit
import Design
import Model
import UIKitCore

/// 5.3b: the matrix's columns for the review sheet of Phase 5.3 (`-RoomMatrixColumns modes|sizes`,
/// `scripts/visual-matrix.sh`): the four display modes (normal, Increase Contrast, Reduce
/// Transparency, Differentiate Without Colour, through `DisplayOptions.source`, never the system's
/// settings) or the three sidebar text sizes (through the setting), each light and dark in an
/// active window. With the sizes, every capture of the sidebar's rows and the palette also reads
/// the text frames back against their rows (`clip_…` lines: a tool, not a test).
extension SpikeRunner.Context {
    struct MatrixColumn {
        let name: String
        /// For the record's keys ("large-dark").
        let key: String
        let apply: () async -> Void
        /// The states are set up again after this column is applied (a text size: the palette
        /// measures its panel as it opens).
        var setupPerColumn = false
        /// Reads the surface back after each capture (the text sizes' clipping check).
        var readBack: ((String) -> String)?
        /// The tokens the columns change, printed on the sheet.
        var notes: [String] = []
    }

    func matrixColumns() -> [MatrixColumn] {
        let appearance = { (dark: Bool) in
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for session in AppDelegate.current?.windows.all ?? [] { session.controller.activityOverride = true }
            self.matrixActive = true
        }
        switch UserDefaults.standard.string(forKey: "RoomMatrixColumns") {
        case "modes":
            let modes: [(String, String, DisplayOptions)] = [
                ("normal", "normal", .standard),
                ("Increase Contrast", "ic", DisplayOptions(increaseContrast: true)),
                ("Reduce Transparency", "rt", DisplayOptions(reduceTransparency: true)),
                ("Differentiate Without Colour", "dwc", DisplayOptions(differentiateWithoutColor: true)),
            ]
            let notes = [
                String(format: "Increase Contrast: hairlines Palette.hairlineHighContrast (label %.0f%% light / %.0f%% dark; normal: separatorColor, the card's CardBorder 7–8%%); "
                       + "secondary text Palette.sidebarSecondaryLabel %.0f%% / %.0f%% (normal %.0f%% / %.0f%%).",
                       Palette.hairlineHighContrastAlpha.light * 100, Palette.hairlineHighContrastAlpha.dark * 100,
                       Palette.sidebarSecondaryHighContrastAlpha.light * 100, Palette.sidebarSecondaryHighContrastAlpha.dark * 100,
                       Palette.sidebarSecondaryAlpha.light * 100, Palette.sidebarSecondaryAlpha.dark * 100),
                String(format: "Reduce Transparency: Materials.solidFill (windowBackgroundColor) in place of the window's material and the overlays' glass (palette, find, zoom, dialogs, "
                       + "⌃Tab, the revealed sidebar, toasts, the status pill, a pane's header). Differentiate Without Colour: the changed dot %.0f pt with a %.1f pt ring "
                       + "(Palette.changedMarkOutline; normal %.0f pt), the audible and muted glyphs in a circle (speaker.wave.2.circle.fill, speaker.slash.circle.fill). "
                       + "Set in-process (DisplayOptions.source), never System Settings: AppKit's own colours do not change here.",
                       ChangedMark.style(DisplayOptions(differentiateWithoutColor: true)).size, ChangedMark.style(DisplayOptions(differentiateWithoutColor: true)).outline,
                       SidebarMetrics.changedDotSize),
            ]
            return modes.flatMap { mode in
                [false, true].map { dark in
                    MatrixColumn(name: "\(mode.0), \(dark ? "dark" : "light")", key: "\(mode.1)-\(dark ? "dark" : "light")", apply: {
                        appearance(dark)
                        DisplayOptions.source = .fixed(mode.2)
                    }, notes: notes)
                }
            }
        case "sizes":
            let notes = TextScale.Size.allCases.map { size in
                String(format: "%@: Typography.sidebarRow %.1f, sidebarSecondary %.1f, sidebarSpaceTitle %.1f, paletteRow %.1f, paletteField %.1f pt; "
                       + "SidebarMetrics.rowHeight %.0f, spaceTitleRowHeight %.0f, separatorRowHeight %.0f, PaletteMetrics.rowHeight %.0f pt (TextScale ×%.3f).",
                       size.rawValue, TextScale.fontSize(14, size), TextScale.fontSize(11, size), TextScale.fontSize(13, size), TextScale.fontSize(13, size),
                       TextScale.fontSize(18, size), TextScale.length(36, size), TextScale.length(36, size), TextScale.length(24, size),
                       TextScale.length(36, size), TextScale.factor(size))
            }
            return TextScale.Size.allCases.flatMap { size in
                [false, true].map { dark in
                    MatrixColumn(name: "\(size.rawValue), \(dark ? "dark" : "light")", key: "\(size.rawValue)-\(dark ? "dark" : "light")", apply: {
                        appearance(dark)
                        await self.setSidebarTextSize(size)
                    }, setupPerColumn: true, readBack: { surface in self.clippingReport(surface) }, notes: notes)
                }
            }
        default:
            return Self.matrixVariants.map { variant in
                MatrixColumn(name: variant.name, key: variant.dark ? "dark" : "light", apply: {
                    NSApp.appearance = NSAppearance(named: variant.dark ? .darkAqua : .aqua)
                    for session in AppDelegate.current?.windows.all ?? [] { session.controller.activityOverride = variant.active }
                    self.matrixActive = variant.active
                })
            }
        }
    }

    /// Back to the design's tokens after a surface's columns.
    func resetMatrixColumns() async {
        switch UserDefaults.standard.string(forKey: "RoomMatrixColumns") {
        case "modes": DisplayOptions.source = .fixed(.standard)
        case "sizes": await setSidebarTextSize(.medium)
        default: break
        }
    }

    /// Settings ▸ Appearance ▸ Sidebar text, through the setting (the app applies it to `TextScale`).
    func setSidebarTextSize(_ size: TextScale.Size) async {
        guard let value = SidebarTextSize(rawValue: size.rawValue) else { return }
        sidebar.store.settings.update { $0.sidebarTextSize = value }
        _ = await waitUntil(3) { TextScale.size == size }
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// The text frames of the sidebar's rows or the palette read back against their rows: a label is
    /// clipped when its text is taller than its frame or its frame leaves its row.
    func clippingReport(_ surface: String) -> String {
        let root: NSView?
        switch surface {
        case "rows": root = sidebar.debugOutline
        case "palette": root = AppDelegate.current?.activeWindow?.palette?.debugPanel
        default: root = nil
        }
        guard let root else { return "no view" }
        var checked = 0, clipped: [String] = [], margin = CGFloat.greatestFiniteMagnitude, rowHeights = Set<CGFloat>()
        func walk(_ view: NSView) {
            for subview in view.subviews where !subview.isHidden {
                if let field = subview as? NSTextField, !field.stringValue.isEmpty, field.frame.width > 0 {
                    checked += 1
                    let row = field.superview?.bounds ?? .zero
                    let text = ceil(field.cell?.cellSize.height ?? 0)
                    let inside = min(field.frame.minY - row.minY, row.maxY - field.frame.maxY)
                    margin = min(margin, inside, field.frame.height - text)
                    if text > field.frame.height + 0.5 || inside < -0.5 {
                        clipped.append(String(format: "\"%@\" text %.0f in %.0f, frame %@ in row %.0f",
                                              String(field.stringValue.prefix(24)), text, field.frame.height, NSStringFromRect(field.frame), row.height))
                    }
                    if field.superview is NSTableCellView || String(describing: Swift.type(of: field.superview!)).contains("PaletteRow") {
                        rowHeights.insert(row.height)
                    }
                }
                walk(subview)
            }
        }
        walk(root)
        return String(format: "size=%@ labels=%d clipped=%d worst_margin=%.1f row_heights=%@%@", TextScale.size.rawValue, checked, clipped.count,
                      margin == .greatestFiniteMagnitude ? 0 : margin, rowHeights.sorted().map { String(format: "%.0f", $0) }.joined(separator: ","),
                      clipped.isEmpty ? "" : " " + clipped.joined(separator: "; "))
    }
}
#endif
