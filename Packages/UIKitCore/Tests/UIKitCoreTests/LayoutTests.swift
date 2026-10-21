import AppKit
import Testing
import Design
@testable import UIKitCore

@Suite("Window layout")
struct WindowLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)

    @Test("Open sidebar: card butts against it, inset on the other three sides")
    func open() throws {
        let layout = WindowLayout.compute(bounds: bounds, sidebarWidth: 240, isSidebarOpen: true)
        #expect(layout.sidebar == CGRect(x: 0, y: 0, width: 240, height: 800))
        let inset = CardMetrics.inset
        #expect(layout.card == CGRect(x: 240, y: inset, width: 1280 - 240 - inset, height: 800 - 2 * inset))
        let splitter = try #require(layout.splitter)
        #expect(splitter.width == SidebarMetrics.splitterHitWidth)
        #expect(splitter.minX < 240 && splitter.maxX > 240)
    }

    @Test("Closed sidebar: card inset on all four sides, no splitter")
    func closed() {
        let layout = WindowLayout.compute(bounds: bounds, sidebarWidth: 240, isSidebarOpen: false)
        let inset = CardMetrics.inset
        #expect(layout.sidebar.width == 0)
        #expect(layout.splitter == nil)
        #expect(layout.card == bounds.insetBy(dx: inset, dy: inset))
    }

    @Test("The sidebar gives way so the card keeps its minimum width")
    func narrowWindow() {
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 400)
        let layout = WindowLayout.compute(bounds: narrow, sidebarWidth: 500, isSidebarOpen: true)
        #expect(layout.sidebar.width == 600 - WindowLayout.minimumCardWidth)
        #expect(layout.card.width >= WindowLayout.minimumCardWidth - CardMetrics.inset)
        let tiny = WindowLayout.compute(bounds: CGRect(x: 0, y: 0, width: 400, height: 400), sidebarWidth: 500, isSidebarOpen: true)
        #expect(tiny.sidebar.width == SidebarMetrics.minWidth)
    }

    @Test("The splitter's drag proposes the pointer's distance from the window's left edge plus the grab offset")
    func proposedWidth() {
        #expect(WindowLayout.proposedWidth(pointerX: 300, bounds: bounds, grabOffset: 2) == 302)
    }

    @Test("The revealed overlay floats 10 pt from the top, leading and bottom edges at the sidebar's width (spec §E)")
    func overlayFrame() {
        let frame = WindowLayout.overlayFrame(bounds: bounds, sidebarWidth: 280)
        #expect(frame == CGRect(x: 10, y: 10, width: 280, height: 780))
        // A narrow window keeps the card's minimum beside it, as the docked sidebar does.
        let narrow = WindowLayout.overlayFrame(bounds: CGRect(x: 0, y: 0, width: 600, height: 400), sidebarWidth: 500)
        #expect(narrow.width == 600 - RevealMetrics.overlayInset - WindowLayout.minimumCardWidth)
    }

    @Test("Splitter outcomes: clamp to 180–500, snap closed under 120",
          arguments: [(600.0, SidebarResize.open(width: 500)), (320.4, .open(width: 320)), (150, .open(width: 180)),
                      (120, .open(width: 180)), (119.9, .closed), (20, .closed), (-40, .closed)])
    func resize(proposed: CGFloat, expected: SidebarResize) {
        #expect(SidebarResize.outcome(forProposedWidth: proposed) == expected)
    }
}

@Suite("Window controller", .serialized, .tags(.window), .localOnly)
struct RoomWindowControllerTests {
    private func makeController() -> RoomWindowController {
        let controller = RoomWindowController(contentSize: NSSize(width: 1000, height: 640))
        controller.spaceTitle = "Personal"
        controller.window?.orderFrontRegardless()
        controller.window?.layoutIfNeeded()
        return controller
    }

    @Test("Dragging the splitter resizes, clamps, snaps closed and posts once")
    func splitterDrag() async throws {
        let controller = makeController()
        defer { controller.close() }
        let splitter = controller.rootView.splitterView
        nonisolated(unsafe) var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: RoomWindowController.sidebarDidSnapClosedNotification, object: controller, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        splitter.onDrag?(320)
        #expect(controller.sidebarWidth == 320 && controller.isSidebarOpen)
        splitter.onDrag?(900)
        #expect(controller.sidebarWidth == SidebarMetrics.maxWidth)
        splitter.onEnd?()
        #expect(posts == 0)

        splitter.onDrag?(150)
        #expect(controller.sidebarWidth == SidebarMetrics.minWidth)
        splitter.onDrag?(60)
        #expect(!controller.isSidebarOpen)
        // Hidden, the sidebar view waits in the hidden overlay (5.1b: a reveal no longer moves it there).
        #expect(controller.sidebarView.isHiddenOrHasHiddenAncestor)
        #expect(controller.rootView.splitterView.isHidden)
        splitter.onEnd?()
        #expect(posts == 1)
        // Reopening restores the width the drag started from.
        controller.toggleSidebarVisibility(nil)
        #expect(controller.isSidebarOpen)
        #expect(controller.sidebarWidth == SidebarMetrics.maxWidth)
    }

    /// The Room Browser design (`beea283`, 2026-10-07) gave the band beside
    /// the traffic lights to the top bar (toggle, extensions, navigation);
    /// the space title, shown while no address field is set, moved to the
    /// address row under it (B-123: this test still checked the old header).
    @Test("The space title sits in the address row under the top bar, at the rows' content inset")
    func headerPlacement() throws {
        let controller = makeController()
        defer { controller.close() }
        controller.rootView.layoutSubtreeIfNeeded()
        let sidebar = controller.sidebarView
        let lights = try #require(sidebar.trafficLights.buttonsRect)
        let bar = TopBarLayout(width: sidebar.bounds.width, trafficLights: sidebar.trafficLights)
        let title = sidebar.titleFrame
        #expect(title.minY >= lights.maxY)
        #expect(title.minY >= bar.bottom)
        #expect(abs(title.minX - (SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset)) <= 0.5)
        let rowTop = bar.bottom + SidebarMetrics.addressRowGap
        #expect(abs(title.midY - (rowTop + SidebarMetrics.addressFieldHeight / 2)) <= 1)
        #expect(title.width >= ceil(sidebar.titleField.attributedStringValue.size().width))
    }

    @Test("Clicks in the titlebar band over the card reach the card, not the titlebar")
    func titlebarHitTesting() throws {
        let controller = makeController()
        defer { controller.close() }
        let window = try #require(controller.window)
        let frameView = try #require(window.contentView?.superview)
        let card = controller.rootView.currentLayout.card
        // 12pt below the card's top edge, well inside the 52pt toolbar band.
        let inRoot = NSPoint(x: card.midX, y: card.minY + 12)
        let inFrame = frameView.convert(inRoot, from: controller.rootView)
        let hit = try #require(frameView.hitTest(inFrame))
        #expect(hit.isDescendant(of: controller.cardView))
    }

    @Test("Clicks on the sidebar background move the window")
    func sidebarDrags() {
        let controller = makeController()
        defer { controller.close() }
        let point = NSPoint(x: 100, y: 300)
        let hit = controller.rootView.hitTest(point)
        #expect(hit === controller.sidebarView.contentView || hit === controller.sidebarView)
        #expect(controller.sidebarView.mouseDownCanMoveWindow)
    }

    @Test("Inactive windows dim and desaturate the sidebar content")
    func inactiveDimming() {
        let controller = makeController()
        defer { controller.close() }
        controller.activityOverride = false
        #expect(controller.materialView.state == .inactive)
        #expect(!controller.sidebarView.isWindowActive)
        #expect(controller.sidebarView.contentView.contentFilters.count == 1)
        controller.activityOverride = true
        #expect(controller.materialView.state == .active)
        #expect(controller.sidebarView.contentView.contentFilters.isEmpty)
        controller.activityOverride = nil
        #expect(controller.materialView.state == .followsWindowActiveState)
    }
}
