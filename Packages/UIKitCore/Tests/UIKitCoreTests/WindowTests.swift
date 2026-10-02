import AppKit
import Testing
import Design
@testable import UIKitCore

@MainActor
func makeShownWindow(size: NSSize = NSSize(width: 900, height: 600)) -> RoomWindow {
    let window = RoomWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size))
    window.contentView = NSView()
    window.orderFrontRegardless()
    window.layoutIfNeeded()
    window.displayIfNeeded()
    return window
}

@MainActor
func buttonFrames(_ window: NSWindow) -> [CGRect] {
    [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0)?.frame }
}

@Suite("RoomWindow", .serialized)
struct RoomWindowTests {
    @Test("Window style matches the Dia shell")
    func style() {
        let window = RoomWindow()
        defer { window.close() }
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.tabbingMode == .disallowed)
        #expect(!NSWindow.allowsAutomaticWindowTabbing)
        #expect(!window.isMovableByWindowBackground)
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.appearance == nil)
    }
}

@Suite("Traffic lights", .serialized)
struct TrafficLightTests {
    @Test("Buttons are measured from the content view's top-left corner")
    func measured() throws {
        let window = makeShownWindow()
        defer { window.close() }
        let rect = try #require(TrafficLightLayout.measure(window).buttonsRect)
        // Tahoe: 14pt buttons at a 23pt pitch → 60pt wide; earlier systems 12/20 → 52.
        #expect(rect.minX > 0 && rect.minY > 0)
        #expect((12...16).contains(rect.height))
        #expect((50...64).contains(rect.width))
        #expect(rect.maxY < 40)
    }

    @Test("Geometry is stable across title, appearance and resize changes")
    func stable() throws {
        let window = makeShownWindow()
        defer { window.close() }
        let layout = TrafficLightLayout(window: window)
        let initial = layout.geometry
        #expect(initial.buttonsRect != nil)

        window.title = "A much longer title that AppKit would normally draw"
        window.layoutIfNeeded()
        layout.update()
        #expect(layout.geometry == initial)

        window.appearance = NSAppearance(named: .darkAqua)
        window.layoutIfNeeded()
        layout.update()
        #expect(layout.geometry == initial)

        window.setContentSize(NSSize(width: 1200, height: 760))
        window.layoutIfNeeded()
        layout.update()
        #expect(layout.geometry == initial)

        window.appearance = nil
        window.setContentSize(NSSize(width: 640, height: 420))
        window.layoutIfNeeded()
        layout.update()
        #expect(layout.geometry == initial)
    }

    @Test("Measuring never moves the buttons")
    func neverRepositions() {
        let window = makeShownWindow()
        defer { window.close() }
        let before = buttonFrames(window)
        let layout = TrafficLightLayout(window: window)
        for _ in 0..<3 { layout.update() }
        #expect(buttonFrames(window) == before)
    }

    @Test("Hidden buttons report a change and drop out of the union")
    func hiddenButton() throws {
        let window = makeShownWindow()
        defer { window.close() }
        let layout = TrafficLightLayout(window: window)
        var reported: [TrafficLightGeometry] = []
        layout.onChange = { reported.append($0) }
        let full = try #require(layout.geometry.buttonsRect)
        window.standardWindowButton(.zoomButton)?.isHidden = true
        layout.update()
        let partial = try #require(layout.geometry.buttonsRect)
        #expect(partial.maxX < full.maxX)
        #expect(reported.count == 1)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
        layout.update()
        #expect(layout.geometry == .none)
    }

    @Test("Header placement derives from the buttons, or the edge inset without them")
    func headerPlacement() {
        let geometry = TrafficLightGeometry(buttonsRect: CGRect(x: 18, y: 20, width: 60, height: 14))
        #expect(geometry.leadingX(gap: 12, edgeInset: 16) == 90)
        #expect(geometry.centerY(fallback: 26) == 27)
        #expect(TrafficLightGeometry.none.leadingX(gap: 12, edgeInset: 16) == 16)
        #expect(TrafficLightGeometry.none.centerY(fallback: 26) == 26)
    }
}

@Suite("Window activity", .serialized)
struct WindowActivityTests {
    @Test("Override forces the state and reports changes once")
    func override() {
        let window = makeShownWindow()
        defer { window.close() }
        let activity = WindowActivity(window: window)
        let initiallyActive = activity.isActive
        var changes: [Bool] = []
        activity.onChange = { changes.append($0) }
        activity.override = true
        activity.override = true
        activity.override = false
        #expect(changes == (initiallyActive ? [false] : [true, false]))
        #expect(!activity.isActive)
    }
}

@Suite("Window material", .serialized)
struct WindowMaterialTests {
    private func colors(_ view: WindowMaterialView) -> [NSColor] {
        (view.tintView.gradientLayer.colors as? [CGColor] ?? []).compactMap { NSColor(cgColor: $0) }
    }

    @Test("Behind-window sidebar material that follows the window state")
    func material() {
        let view = WindowMaterialView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        #expect(view.material == .sidebar)
        #expect(view.blendingMode == .behindWindow)
        #expect(view.state == .followsWindowActiveState)
        #expect(!view.mouseDownCanMoveWindow)
    }

    @Test("No tint by default; a tint is a top-to-bottom gradient within 10–25%")
    func tint() throws {
        let view = WindowMaterialView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        #expect(colors(view).allSatisfy { $0.alphaComponent == 0 })
        view.setTintColor(.systemPurple, animated: false)
        let tinted = colors(view)
        #expect(tinted.count == 2)
        #expect(tinted[0].alphaComponent > tinted[1].alphaComponent)
        for color in tinted {
            #expect(Materials.tintOpacityRange.contains(color.alphaComponent))
        }
    }

    @Test("Animated tint changes add a colors animation")
    func animatedTint() {
        let view = WindowMaterialView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.setTintColor(.systemTeal, animated: true)
        #expect(view.tintView.gradientLayer.animation(forKey: "colors") != nil)
    }

    @Test("Inactive windows get a fainter tint")
    func inactiveTint() throws {
        let view = WindowMaterialView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.setTintColor(.systemOrange, animated: false)
        let active = try #require(colors(view).first).alphaComponent
        view.isWindowActive = false
        view.tintView.updateLayer()
        let inactive = try #require(colors(view).first).alphaComponent
        #expect(inactive < active)
    }
}

@Suite("Window state callbacks (persisted by the store)", .serialized)
struct WindowStateCallbackTests {
    @Test("Toggle and splitter drags report width and visibility; programmatic sets do not")
    func sidebarState() {
        let controller = RoomWindowController()
        defer { controller.close() }
        var reports: [(CGFloat, Bool)] = []
        controller.onSidebarStateChange = { reports.append(($0, $1)) }
        controller.sidebarWidth = 300
        controller.isSidebarOpen = true
        #expect(reports.isEmpty)
        controller.toggleSidebar(nil)
        #expect(reports.count == 1 && reports[0] == (300, false))
        controller.toggleSidebar(nil)
        controller.rootView.splitterView.onDrag?(350)
        controller.rootView.splitterView.onEnd?()
        #expect(reports.last.map { $0 == (350, true) } == true)
        // Dragged under the snap threshold: closed, and the pre-drag width kept.
        controller.rootView.splitterView.onDrag?(60)
        controller.rootView.splitterView.onEnd?()
        #expect(reports.last.map { $0 == (350, false) } == true)
    }

    @Test("A saved frame is restored only if it is on a screen")
    func restoreFrame() throws {
        let controller = RoomWindowController()
        defer { controller.close() }
        let screen = try #require(NSScreen.main).visibleFrame
        let onScreen = NSRect(x: screen.minX + 20, y: screen.minY + 20, width: 1000, height: 700)
        #expect(controller.restoreFrame(onScreen))
        #expect(controller.window?.frame == onScreen)
        #expect(!controller.restoreFrame(NSRect(x: -100_000, y: -100_000, width: 1000, height: 700)))
        #expect(controller.window?.frame == onScreen)
    }
}
