#if DEBUG
import AppKit
import Engine

/// The spikes' engine-neutral way to drive a page (B-44, ROADMAP 3.1a 5a):
/// script and captures through the `WebContents` members, input as real
/// `NSEvent`s delivered to the engine's native view. Every failure is an
/// `error:` line in the spike output (the grand tour's checks fail on it),
/// never a silent return. On RoomCore `executeJavaScript` and
/// `captureViewport` arrive in 3.3b; until then those paths fail loudly.
enum PageDriver {
    // MARK: Script and capture

    /// The script's JSON result, or `nil` after recording why it failed.
    static func evaluate(_ page: any WebContents, _ script: String, _ purpose: String) async -> String? {
        do {
            return try await page.executeJavaScript(script)
        } catch {
            SpikeRunner.record("error", "\(purpose): executeJavaScript failed (\(error))")
            return nil
        }
    }

    /// Evaluates `script` right after a real click near the viewport's
    /// top-left corner, so the page has transient user activation (media
    /// `play()`, `AudioContext.resume()`, `showPicker()`).
    static func evaluateWithGesture(_ page: any WebContents, _ script: String, _ purpose: String) async -> String? {
        guard click(page, at: CGPoint(x: 4, y: 4), purpose) else { return nil }
        try? await Task.sleep(for: .milliseconds(50))
        return await evaluate(page, script, purpose)
    }

    /// The viewport, or `nil` after recording why it failed.
    static func capture(_ page: any WebContents, _ purpose: String) async -> NSImage? {
        do {
            return try await page.captureViewport()
        } catch {
            SpikeRunner.record("error", "\(purpose): captureViewport failed (\(error))")
            return nil
        }
    }

    /// The centre of the element `selector` matches, in the page's CSS
    /// pixels (the viewport's top-left origin), or `nil` after recording why.
    static func center(of selector: String, in page: any WebContents, fromRight: Double? = nil, _ purpose: String) async -> CGPoint? {
        let x = fromRight.map { "r.right - \($0)" } ?? "r.x + r.width / 2"
        let script = "(() => { const e = document.querySelector('\(selector)'); if (!e) return null; "
            + "const r = e.getBoundingClientRect(); return [\(x), r.y + r.height / 2] })()"
        guard let json = await evaluate(page, script, purpose) else { return nil }
        guard let point = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Double], point.count == 2 else {
            SpikeRunner.record("error", "\(purpose): no element \(selector) (\(json))")
            return nil
        }
        return CGPoint(x: point[0], y: point[1])
    }

    // MARK: Input

    /// A click at `point` (page CSS pixels at zoom 1 = the native view's
    /// points from its top-left), as mouse-down and mouse-up events the
    /// window delivers to whatever view is there.
    @discardableResult
    static func click(_ page: any WebContents, at point: CGPoint, button: NSEvent.EventType = .leftMouseDown,
                      modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1, _ purpose: String) -> Bool {
        guard let (window, location) = windowLocation(page, point, purpose) else { return false }
        let up: NSEvent.EventType = switch button {
        case .rightMouseDown: .rightMouseUp
        case .otherMouseDown: .otherMouseUp
        default: .leftMouseUp
        }
        // A window that is not key takes the first mouse-down for activation;
        // while another application holds the screen (a system dialog), the
        // window never becomes key, so the press goes to the page's view itself.
        let target = window.isKeyWindow ? nil : window.contentView?.hitTest(window.contentView!.convert(location, from: nil))
        for type in [button, up] {
            guard let event = mouseEvent(type, location, window, modifiers, clickCount) else {
                SpikeRunner.record("error", "\(purpose): could not make a \(type) event")
                return false
            }
            if let target {
                switch type {
                case .leftMouseDown: target.mouseDown(with: event)
                case .leftMouseUp: target.mouseUp(with: event)
                case .rightMouseDown: target.rightMouseDown(with: event)
                case .rightMouseUp: target.rightMouseUp(with: event)
                default: window.sendEvent(event)
                }
            } else {
                window.sendEvent(event)
            }
        }
        return true
    }

    /// The pointer moved to `point`: a mouse-moved event straight to the view
    /// under it (AppKit routes synthetic mouse-moved events only to a first
    /// responder that asked for them, which is not how a pointer reaches a page).
    @discardableResult
    static func hover(_ page: any WebContents, at point: CGPoint, modifiers: NSEvent.ModifierFlags = [], _ purpose: String) -> Bool {
        guard let (window, location) = windowLocation(page, point, purpose) else { return false }
        guard let event = mouseEvent(.mouseMoved, location, window, modifiers, 0),
              let target = window.contentView?.hitTest(window.contentView!.convert(location, from: nil)) else {
            SpikeRunner.record("error", "\(purpose): nothing under \(point) to move the pointer over")
            return false
        }
        target.mouseMoved(with: event)
        return true
    }

    /// Clicks the centre of `selector`'s element.
    @discardableResult
    static func click(_ page: any WebContents, _ selector: String, fromRight: Double? = nil, button: NSEvent.EventType = .leftMouseDown,
                      modifiers: NSEvent.ModifierFlags = [], _ purpose: String) async -> Bool {
        guard let point = await center(of: selector, in: page, fromRight: fromRight, purpose) else { return false }
        return click(page, at: point, button: button, modifiers: modifiers, purpose)
    }

    /// Moves the pointer over `selector`'s element.
    @discardableResult
    static func hover(_ page: any WebContents, _ selector: String, _ purpose: String) async -> Bool {
        guard let point = await center(of: selector, in: page, purpose) else { return false }
        return hover(page, at: point, purpose)
    }

    /// A key press (down and up) through the application, the way a typed key arrives.
    static func key(_ window: NSWindow, characters: String, charactersIgnoringModifiers: String? = nil, keyCode: UInt16,
                    modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters, isARepeat: false, keyCode: keyCode)
            if let event { NSApp.sendEvent(event) }
        }
    }

    // MARK: Helpers

    private static func windowLocation(_ page: any WebContents, _ point: CGPoint, _ purpose: String) -> (NSWindow, CGPoint)? {
        let view = page.nativeView
        guard let window = view.window else {
            SpikeRunner.record("error", "\(purpose): the page is not in a window")
            return nil
        }
        // The page's origin is its view's top-left corner, whether or not the view is flipped.
        let local = view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y)
        return (window, view.convert(local, to: nil))
    }

    private static func mouseEvent(_ type: NSEvent.EventType, _ location: CGPoint, _ window: NSWindow,
                                   _ modifiers: NSEvent.ModifierFlags, _ clickCount: Int) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount,
            pressure: type == .mouseMoved ? 0 : 1)
    }
}
#endif
