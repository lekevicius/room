// room-record: Room's window as a clip, and the pointer beside it.
//
//   room-record --out build/showcase/clips/palette [--script Website/capture/scenes/palette.json]
//               [--app Room | --pid 1234] [--duration 8] [--tail 0.8] [--codec hevc|h264]
//   room-record --probe     prints the pointer's position in Room's window points, to write scripts by pointing
//
// Writes <out>.mov (the window alone at the display's scale, no system cursor, 60 fps) and
// <out>.cursor.json ({ width, height, events: [[t, x, y, kind], …] } in window points, top-left
// origin, t in seconds from the first frame; kind m(ove) d(own) u(p) s(croll)).
// With --script it plays the choreography (Website/capture/scenes/README.md) and stops after it;
// without, it records until --duration or Return.
//
// Permissions (System Settings ▸ Privacy & Security): Screen & System Audio Recording for the
// terminal that runs it; Accessibility too when it plays a script (posting events).
import AppKit
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

// MARK: Arguments

struct Options {
    var out = "build/showcase/clips/clip"
    var script: String?
    var app = "Room"
    var pid: pid_t?
    var duration: Double = 10
    var tail: Double = 0.8
    var codec = "hevc"
    var probe = false

    init(_ args: [String]) {
        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--out": out = it.next() ?? out
            case "--script": script = it.next()
            case "--app": app = it.next() ?? app
            case "--pid": pid = it.next().flatMap { pid_t($0) }
            case "--duration": duration = it.next().flatMap(Double.init) ?? duration
            case "--tail": tail = it.next().flatMap(Double.init) ?? tail
            case "--codec": codec = it.next() ?? codec
            case "--probe": probe = true
            default: fail("unknown argument \(a)")
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("room-record: \(message)\n".utf8))
    exit(1)
}

// MARK: Choreography

/// One step of a scene script. Points are window points from the top-left corner.
struct Step: Decodable {
    var wait: Double?
    var move: [Double]?
    var drag: [Double]?
    var click: Bool?
    var down: Bool?
    var up: Bool?
    var key: String?
    var type: String?
    var scroll: [Double]?
    var duration: Double?
    var interval: Double?
    /// Curvature of a move, as a fraction of its length (0 is a straight line).
    var arc: Double?
    /// Held during a click or drag: "shift", "cmd+opt", …
    var modifiers: String?
}

struct Script: Decodable {
    var steps: [Step]
    /// Where the pointer rests before the first frame.
    var start: [Double]?
}

/// Posts real events, as a person's hand would make them.
@MainActor
final class Hand {
    let origin: CGPoint
    private(set) var position: CGPoint
    private var buttonDown = false
    private let source = CGEventSource(stateID: .hidSystemState)

    init(windowOrigin: CGPoint, start: CGPoint) {
        origin = windowOrigin
        position = start
        warp(to: start)
    }

    private func global(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x, y: origin.y + p.y) }

    private func post(_ type: CGEventType, at p: CGPoint, flags: CGEventFlags = []) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: global(p), mouseButton: .left) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    func warp(to p: CGPoint) {
        CGWarpMouseCursorPosition(global(p))
        position = p
        post(.mouseMoved, at: p)
    }

    /// Eased travel along a gentle arc, sampled at 120 Hz: hands do not move in straight lines.
    func move(to target: CGPoint, duration: Double, arc: Double) async {
        let from = position
        let dx = target.x - from.x, dy = target.y - from.y
        let length = max(1, hypot(dx, dy))
        let bend = CGPoint(x: -dy / length * length * arc, y: dx / length * length * arc)
        let control = CGPoint(x: from.x + dx / 2 + bend.x, y: from.y + dy / 2 + bend.y)
        let frames = max(1, Int(duration * 120))
        for i in 1...frames {
            let s = Double(i) / Double(frames)
            let t = s * s * s * (s * (s * 6 - 15) + 10) // smootherstep
            let u = 1 - t
            let p = CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * target.x,
                            y: u * u * from.y + 2 * u * t * control.y + t * t * target.y)
            position = p
            post(buttonDown ? .leftMouseDragged : .mouseMoved, at: p, flags: held)
            try? await Task.sleep(for: .seconds(duration / Double(frames)))
        }
    }

    var held: CGEventFlags = []

    func press() { buttonDown = true; post(.leftMouseDown, at: position, flags: held) }
    func release() { buttonDown = false; post(.leftMouseUp, at: position, flags: held) }

    static func flags(_ names: String?) -> CGEventFlags {
        var flags: CGEventFlags = []
        for p in (names ?? "").lowercased().split(separator: "+") {
            switch p {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: fail("unknown modifier \(p)")
            }
        }
        return flags
    }

    func scroll(by delta: CGPoint, duration: Double) async {
        let frames = max(1, Int(duration * 60))
        var done = CGPoint.zero
        for i in 1...frames {
            let s = Double(i) / Double(frames)
            let t = 1 - pow(1 - s, 3)
            let target = CGPoint(x: delta.x * t, y: delta.y * t)
            let step = CGPoint(x: (target.x - done.x).rounded(), y: (target.y - done.y).rounded())
            done.x += step.x; done.y += step.y
            if let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                               wheel1: Int32(-step.y), wheel2: Int32(-step.x), wheel3: 0) {
                e.location = global(position)
                e.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .seconds(duration / Double(frames)))
        }
    }

    func key(_ combo: String) {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        var flags: CGEventFlags = []
        for p in parts.dropLast() {
            switch p {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: fail("unknown modifier \(p)")
            }
        }
        guard let name = parts.last, let code = Keys.code(name) else { fail("unknown key \(combo)") }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    func type(_ text: String, interval: Double) async {
        for ch in text {
            let s = String(ch)
            if let code = Keys.code(s.lowercased()) {
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
                    if ch.isUppercase { e?.flags = .maskShift }
                    e?.post(tap: .cghidEventTap)
                }
            } else {
                // Anything without a US key position goes in as text.
                let utf16 = Array(s.utf16)
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                    e?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    e?.post(tap: .cghidEventTap)
                }
            }
            // A little human unevenness between keys.
            try? await Task.sleep(for: .seconds(interval * Double.random(in: 0.7...1.35)))
        }
    }
}

enum Keys {
    static let table: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "`": 50, " ": 49, "space": 49, "return": 36, "enter": 36, "tab": 48, "delete": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    static func code(_ name: String) -> CGKeyCode? { table[name] }
}

// MARK: Pointer log

@MainActor
final class PointerLog {
    var events: [[Any]] = []
    var start: Date?
    let frame: CGRect
    private var monitor: Any?

    init(frame: CGRect) { self.frame = frame }

    /// Global coordinates (Cocoa, bottom-left) → window points (top-left).
    private func local(_ p: NSPoint) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x - frame.minX, y: (height - p.y) - frame.minY)
    }

    func begin() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .scrollWheel]) { [weak self] event in
            let location = NSEvent.mouseLocation
            let type = event.type
            MainActor.assumeIsolated { self?.record(type, at: location) }
        }
        record(.mouseMoved, at: NSEvent.mouseLocation)
    }

    func record(_ type: NSEvent.EventType, at location: NSPoint) {
        guard let start else { return }
        let kind: String
        switch type {
        case .leftMouseDown: kind = "d"
        case .leftMouseUp: kind = "u"
        case .scrollWheel: kind = "s"
        default: kind = "m"
        }
        let p = local(location)
        let t = Date().timeIntervalSince(start)
        events.append([round(t * 1000) / 1000, round(p.x * 10) / 10, round(p.y * 10) / 10, kind])
    }

    func end() { if let monitor { NSEvent.removeMonitor(monitor) } }

    func write(to url: URL) throws {
        let json: [String: Any] = ["width": frame.width, "height": frame.height, "events": events]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }
}

// MARK: Recording

final class RecordingDelegate: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    let started: @Sendable () -> Void
    let finished: @Sendable (Error?) -> Void
    init(started: @escaping @Sendable () -> Void, finished: @escaping @Sendable (Error?) -> Void) {
        self.started = started
        self.finished = finished
    }
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { started() }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finished(nil) }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) { finished(error) }
}

@MainActor
func run(_ options: Options) async {
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    } catch {
        fail("no screen content (Screen Recording permission?): \(error.localizedDescription)")
    }
    let candidates = content.windows.filter { window in
        guard window.windowLayer == 0, let app = window.owningApplication else { return false }
        if let pid = options.pid { return app.processID == pid }
        return app.applicationName == options.app
    }
    guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
        fail("no on-screen window of \(options.pid.map { "pid \($0)" } ?? options.app)")
    }
    let frame = window.frame
    if options.probe {
        print("Room's window: \(Int(frame.width))×\(Int(frame.height)) pt. Point at things; Control-C to stop.")
        let height = NSScreen.screens.first?.frame.height ?? 0
        var last = CGPoint(x: -1, y: -1)
        while true {
            let m = NSEvent.mouseLocation
            let p = CGPoint(x: (m.x - frame.minX).rounded(), y: (height - m.y - frame.minY).rounded())
            if p != last { print("[\(Int(p.x)), \(Int(p.y))]"); last = p }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
    let scale = NSScreen.screens.first { $0.frame.intersects(frame) }?.backingScaleFactor ?? 2

    let config = SCStreamConfiguration()
    config.width = Int(frame.width * scale)
    config.height = Int(frame.height * scale)
    config.showsCursor = false
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.captureResolution = .best
    config.queueDepth = 8
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let stream = SCStream(filter: filter, configuration: config, delegate: nil)

    let base = URL(fileURLWithPath: options.out)
    try? FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
    let movie = base.appendingPathExtension("mov")
    try? FileManager.default.removeItem(at: movie)
    let outputConfig = SCRecordingOutputConfiguration()
    outputConfig.outputURL = movie
    outputConfig.outputFileType = .mov
    outputConfig.videoCodecType = options.codec == "h264" ? .h264 : .hevc

    let log = PointerLog(frame: frame)
    let script: Script? = options.script.map { path in
        guard let data = FileManager.default.contents(atPath: path) else { fail("no script at \(path)") }
        do { return try JSONDecoder().decode(Script.self, from: data) } catch { fail("script \(path): \(error)") }
    }
    let hand = script.map { Hand(windowOrigin: frame.origin, start: CGPoint(x: $0.start?[0] ?? frame.width / 2, y: $0.start?[1] ?? frame.height / 2)) }

    let startedSignal = AsyncStream<Void>.makeStream()
    let finishedSignal = AsyncStream<Error?>.makeStream()
    let delegate = RecordingDelegate(started: { startedSignal.continuation.yield() },
                                     finished: { finishedSignal.continuation.yield($0) })
    let output = SCRecordingOutput(configuration: outputConfig, delegate: delegate)
    do {
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
    } catch {
        fail("could not start capture: \(error.localizedDescription)")
    }
    for await _ in startedSignal.stream { break }
    log.start = Date()
    log.begin()
    print("recording \(Int(frame.width))×\(Int(frame.height)) pt at \(scale)× → \(movie.path)")

    if let script, let hand {
        for step in script.steps {
            if let wait = step.wait { try? await Task.sleep(for: .seconds(wait)) }
            hand.held = Hand.flags(step.modifiers)
            if step.down == true { hand.press() }
            if let to = step.move { await hand.move(to: CGPoint(x: to[0], y: to[1]), duration: step.duration ?? 0.7, arc: step.arc ?? 0.08) }
            if let to = step.drag {
                hand.press()
                try? await Task.sleep(for: .milliseconds(120))
                await hand.move(to: CGPoint(x: to[0], y: to[1]), duration: step.duration ?? 0.8, arc: step.arc ?? 0.04)
                try? await Task.sleep(for: .milliseconds(100))
                hand.release()
            }
            if step.click == true {
                hand.press()
                try? await Task.sleep(for: .milliseconds(90))
                hand.release()
            }
            if step.up == true { hand.release() }
            if let combo = step.key { hand.key(combo) }
            if let text = step.type { await hand.type(text, interval: step.interval ?? 0.085) }
            if let d = step.scroll { await hand.scroll(by: CGPoint(x: d[0], y: d[1]), duration: step.duration ?? 0.8) }
        }
        try? await Task.sleep(for: .seconds(options.tail))
    } else {
        print("press Return to stop (or wait \(options.duration) s)")
        let stop = AsyncStream<Void>.makeStream()
        FileHandle.standardInput.readabilityHandler = { handle in
            _ = handle.availableData
            stop.continuation.yield()
        }
        let timer = Task { try? await Task.sleep(for: .seconds(options.duration)); stop.continuation.yield() }
        for await _ in stop.stream { break }
        timer.cancel()
        FileHandle.standardInput.readabilityHandler = nil
    }

    log.end()
    do {
        try await stream.stopCapture()
    } catch {
        fail("could not stop capture: \(error.localizedDescription)")
    }
    for await error in finishedSignal.stream {
        if let error { fail("recording failed: \(error.localizedDescription)") }
        break
    }
    let cursor = base.appendingPathExtension("cursor.json")
    do { try log.write(to: cursor) } catch { fail("could not write \(cursor.path)") }
    print("wrote \(movie.path) and \(cursor.lastPathComponent) (\(log.events.count) pointer events)")
}

let options = Options(CommandLine.arguments)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    await run(options)
    exit(0)
}
app.run()
