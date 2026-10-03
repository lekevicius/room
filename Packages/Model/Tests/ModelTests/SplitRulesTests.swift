import Foundation
import Testing
@testable import Model

@Suite("Split rules (spec §D)")
struct SplitRulesTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test("Equal sizes: one per pane side by side or stacked; the grid keeps columns then rows")
    func equalRatios() {
        let third: Double = 1.0 / 3
        #expect(SplitRules.equalRatios(layout: .hbox, count: 3) == [third, third, third])
        #expect(SplitRules.equalRatios(layout: .vbox, count: 2) == [0.5, 0.5])
        #expect(SplitRules.equalRatios(layout: .grid, count: 2) == [0.5, 0.5])
        #expect(SplitRules.equalRatios(layout: .grid, count: 4) == [0.5, 0.5, 0.5, 0.5])
    }

    @Test("Persisted sizes are kept only when they fit the layout")
    func normalizedRatios() {
        #expect(SplitRules.normalizedRatios([0.3, 0.7], layout: .hbox, count: 2) == [0.3, 0.7])
        #expect(SplitRules.normalizedRatios([0.3, 0.7], layout: .hbox, count: 3).count == 3)
        #expect(SplitRules.normalizedRatios([0.3, 0.3], layout: .vbox, count: 2) == [0.5, 0.5])
        #expect(SplitRules.normalizedRatios([0.3, 0.7, 0.6, 0.4], layout: .grid, count: 4) == [0.3, 0.7, 0.6, 0.4])
        #expect(SplitRules.normalizedRatios([0, 1], layout: .hbox, count: 2) == [0.5, 0.5])
    }

    @Test("At most four panes")
    func maxPanes() {
        #expect(SplitRules.canAdd(toCount: 3))
        #expect(!SplitRules.canAdd(toCount: 4))
    }

    @Test("The group row sits with a permanent member if there is one, else with the first pane")
    func anchor() {
        let space = UUID(), profile = UUID()
        let today = Entry(id: a, kind: .today, spaceID: space, profileID: profile)
        let pinned = Entry(id: b, kind: .pinned, spaceID: space, profileID: profile)
        let other = Entry(id: c, kind: .today, spaceID: space, profileID: profile)
        #expect(SplitRules.anchor(of: [today, pinned]) == b)
        #expect(SplitRules.anchor(of: [other, today]) == c)
    }

    @Test("Focus: the next pane after one leaves (the previous for the last); ⌃⇧] / ⌃⇧[ wrap; ⌃⇧N picks pane N")
    func focus() {
        let order = [a, b, c]
        #expect(SplitRules.focusAfterLeaving(b, order: order) == c)
        #expect(SplitRules.focusAfterLeaving(c, order: order) == b)
        #expect(SplitRules.focusAfterLeaving(a, order: [a]) == nil)
        #expect(SplitRules.adjacentPane(to: c, offset: 1, order: order) == a)
        #expect(SplitRules.adjacentPane(to: a, offset: -1, order: order) == c)
        #expect(SplitRules.pane(number: 2, order: order) == b)
        #expect(SplitRules.pane(number: 4, order: order) == nil)
    }

    @Test("⌘W on a pane: a Today tab closes, a permanent entry gets §A.3 without the switch and leaves; the next pane takes the focus")
    func paneClose() {
        let space = UUID(), profile = UUID()
        let today = Entry(id: a, kind: .today, spaceID: space, profileID: profile)
        let pinned = Entry(id: b, kind: .pinned, spaceID: space, profileID: profile)
        let closeToday = SplitRules.paneClose(today, behavior: .resetUnloadSwitch, order: [a, b])
        #expect(closeToday == SplitRules.PaneClose(steps: [.unload, .remove], leavesGroup: false, focus: b))
        let closePinned = SplitRules.paneClose(pinned, behavior: .resetUnloadSwitch, order: [a, b, c])
        #expect(closePinned == SplitRules.PaneClose(steps: [.unload, .reset], leavesGroup: true, focus: c))
    }

    @Test("Drops: leading edges insert before the pane; two panes follow the drop's axis, a crossing drop makes a grid")
    func drops() {
        #expect(SplitRules.insertionIndex(target: 1, edge: .left) == 1)
        #expect(SplitRules.insertionIndex(target: 1, edge: .bottom) == 2)
        #expect(SplitRules.layout(afterDropOn: .top, current: nil, count: 2) == .vbox)
        #expect(SplitRules.layout(afterDropOn: .right, current: .hbox, count: 3) == .hbox)
        #expect(SplitRules.layout(afterDropOn: .bottom, current: .hbox, count: 3) == .grid)
    }

    @Test("A pane moved by its grip takes its size along (not in the grid)")
    func moveRatios() {
        #expect(SplitRules.ratiosAfterMove([0.2, 0.3, 0.5], layout: .hbox, from: 0, to: 2) == [0.3, 0.5, 0.2])
        #expect(SplitRules.ratiosAfterMove([0.4, 0.6, 0.5, 0.5], layout: .grid, from: 0, to: 2) == [0.4, 0.6, 0.5, 0.5])
    }
}
