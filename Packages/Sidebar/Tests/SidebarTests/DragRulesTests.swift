import CoreGraphics
import Foundation
import Model
import Store
import Testing
@testable import Sidebar

@Suite("Drop targets (spec §A.6, §A.9)")
struct DropRulesTests {
    let space = UUID()
    let folder = UUID(), inside = UUID(), pinned = UUID(), tab = UUID()

    /// # Space / Folder (open) / · Inside / Pinned / --- / Tab / + New Tab
    var rows: [DropRules.Row] {
        [
            .spaceTitle,
            .entry(id: folder, kind: .folder, container: .pinned(space: space, folder: nil), index: 0, depth: 0, showsChildren: true),
            .entry(id: inside, kind: .pinned, container: .pinned(space: space, folder: folder), index: 0, depth: 1, showsChildren: false),
            .entry(id: pinned, kind: .pinned, container: .pinned(space: space, folder: nil), index: 1, depth: 0, showsChildren: false),
            .separator,
            .entry(id: tab, kind: .today, container: .today(space: space), index: 0, depth: 0, showsChildren: false),
            .newTab,
        ]
    }

    func target(_ row: Int?, _ fraction: CGFloat, held: Bool = false, single: Bool = true, dragged: EntryKind? = nil) -> DropRules.Target {
        DropRules.target(rows: rows, row: row, fraction: fraction, held: held, space: space, single: single, draggedKind: dragged)
    }

    @Test("Edges reorder before or after the row, in the row's own list")
    func edges() {
        #expect(target(3, 0.1) == .insert(.pinned(space: space, folder: nil), index: 1, line: .init(boundary: 3, depth: 0)))
        #expect(target(3, 0.9) == .insert(.pinned(space: space, folder: nil), index: 2, line: .init(boundary: 4, depth: 0)))
        #expect(target(2, 0.9) == .insert(.pinned(space: space, folder: folder), index: 1, line: .init(boundary: 3, depth: 1)))
        // Below an open folder: its first child.
        #expect(target(1, 0.9) == .insert(.pinned(space: space, folder: folder), index: 0, line: .init(boundary: 2, depth: 1)))
    }

    @Test("The middle 60% goes onto the row only after the hold; until then it splits at half height")
    func hold() {
        #expect(target(1, 0.5, held: true) == .intoFolder(folder, row: 1))
        #expect(target(1, 0.3) == .insert(.pinned(space: space, folder: nil), index: 0, line: .init(boundary: 1, depth: 0)))
        #expect(target(1, 0.15, held: true).container != nil, "the edge zone never drops into the folder")
        #expect(target(3, 0.5, held: true) == .newFolder(with: pinned, row: 3))
        #expect(target(3, 0.5, held: true, single: false).container != nil, "a group drag makes no folder")
        #expect(target(5, 0.5, held: true) == .join(with: tab, row: 5), "Today rows never make folders")
    }

    @Test("A folder dropped onto a folder goes into it after the hold (B-117); onto a tab it makes no folder or split")
    func folderOntoFolder() {
        // A folder drag is never `single` (only one non-folder entry makes a folder or a split).
        #expect(target(1, 0.5, held: true, single: false) == .intoFolder(folder, row: 1))
        #expect(target(1, 0.5, held: false, single: false).container != nil, "before the hold it reorders")
        #expect(target(3, 0.5, held: true, single: false).container != nil)
        #expect(target(5, 0.5, held: true, single: false).container != nil)
    }

    @Test("Join (spec §D): a single entry held on a tab's centre splits with it; a pinned entry onto a pinned one still makes a folder (§A.6)")
    func join() {
        #expect(target(5, 0.5, held: true, dragged: .pinned) == .join(with: tab, row: 5))
        #expect(target(3, 0.5, held: true, dragged: .today) == .join(with: pinned, row: 3))
        #expect(target(3, 0.5, held: true, dragged: .pinned) == .newFolder(with: pinned, row: 3))
        #expect(target(5, 0.5, held: false).container != nil, "no join before the 500 ms rest")
        #expect(target(5, 0.15, held: true).container != nil, "the edge zones reorder")
        #expect(target(5, 0.5, held: true, single: false).container != nil, "a group drag joins nothing")
        #expect(DropRules.holdDelay == 0.5)
    }

    @Test("Section boundaries: under the space title, either side of the separator, New Tab and the empty area")
    func boundaries() {
        #expect(target(0, 0.5) == .insert(.pinned(space: space, folder: nil), index: 0, line: .init(boundary: 1, depth: 0)))
        #expect(target(4, 0.2) == .insert(.pinned(space: space, folder: nil), index: .max, line: .init(boundary: 4, depth: 0)))
        #expect(target(4, 0.8) == .insert(.today(space: space), index: 0, line: .init(boundary: 5, depth: 0)))
        #expect(target(6, 0.5) == .insert(.today(space: space), index: .max, line: .init(boundary: 6, depth: 0)))
        #expect(target(nil, 0) == .insert(.today(space: space), index: .max, line: .init(boundary: 7, depth: 0)))
    }

    @Test("Essentials grid: before the nearest tile left of its centre, else after it")
    func grid() {
        let frames = EssentialsLayout.frames(count: 5, width: 228)
        #expect(DropRules.gridIndex(frames: frames, point: CGPoint(x: 2, y: 10)) == 0)
        #expect(DropRules.gridIndex(frames: frames, point: CGPoint(x: frames[1].midX + 1, y: 10)) == 2)
        #expect(DropRules.gridIndex(frames: frames, point: CGPoint(x: 227, y: frames[4].midY)) == 5)
        #expect(DropRules.gridIndex(frames: [], point: .zero) == 0)
    }
}

@Suite("Multi-select (spec §A.9)")
struct MultiSelectionTests {
    let order = (0..<5).map { _ in UUID() }

    @Test("⌘-click toggles, starting from the selected entry when it is in the same section")
    func toggle() {
        var selection = MultiSelection()
        selection.toggle(order[3], section: .today, order: order, primary: order[1])
        #expect(selection.ids == [order[1], order[3]])
        selection.toggle(order[0], section: .today, order: order, primary: order[1])
        #expect(selection.ids == [order[0], order[1], order[3]], "kept in sidebar order")
        selection.toggle(order[1], section: .today, order: order, primary: order[1])
        #expect(selection.ids == [order[0], order[3]])
        // Another section starts over: one section only.
        let pinned = UUID()
        selection.toggle(pinned, section: .pinned, order: [pinned], primary: order[1])
        #expect(selection.ids == [pinned] && selection.section == .pinned)
    }

    @Test("⇧-click selects the range from the anchor within the section")
    func extend() {
        var selection = MultiSelection()
        selection.extend(to: order[3], section: .today, order: order, primary: order[1])
        #expect(selection.ids == Array(order[1...3]))
        selection.toggle(order[4], section: .today, order: order, primary: order[1])
        selection.extend(to: order[2], section: .today, order: order, primary: order[1])
        #expect(selection.ids == Array(order[2...4]), "the range runs from the last ⌘-clicked entry")
        selection.extend(to: UUID(), section: .pinned, order: [], primary: nil)
        #expect(selection.ids.count == 1 && selection.section == .pinned)
        selection.retain([])
        #expect(selection.isEmpty && selection.section == nil)
    }
}
