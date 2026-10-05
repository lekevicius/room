#if DEBUG
import AppKit
import Engine

/// Phase 3.2b's quit checks on the real app:
///
/// - `quitstay` (`scripts/run-spike.sh quitstay --remote-debugging-port=<p>
///   -RoomSpikeCDPPort <p>`): ten pages, the selected one `dialogs.html` with
///   beforeunload armed; ⌘Q's path (`NSApp.terminate`) → the engine's close
///   path → the page's beforeunload dialog, answered "stay" over the DevTools
///   protocol (`Page.handleJavaScriptDialog`) → the quit is cancelled with
///   every page and entry as it was. The spike then ends; the runner's own
///   quit raises the dialog again and a background task answers "leave", so
///   the app quits through the same path (its log shows the order: quit
///   requested, final state written, quit proceeds).
/// - `quitflags`: what the next launch reads about the previous exit (the
///   store's `uncleanExit` and every engine profile's `lastExitWasClean`).
extension SpikeRunner.Context {
    func quitStay() async {
        let port = UserDefaults.standard.integer(forKey: "RoomSpikeCDPPort")
        guard port > 0, let app = AppDelegate.current else {
            SpikeRunner.record("error", "quitstay: needs --remote-debugging-port=<p> -RoomSpikeCDPPort <p>")
            return
        }
        for site in Self.typicalSites.prefix(9) {
            session.newPage(URL(string: site)!, hidden: true, select: false)
        }
        let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent()
            .appending(path: "phase-2.6/dialogs.html")
        guard let dialogs = await open(fixture) else {
            SpikeRunner.record("error", "quitstay: dialogs.html did not open")
            return
        }
        let start = Date()
        while session.pages.contains(where: { $0.isLoading }), Date().timeIntervalSince(start) < 60 {
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Chrome asks beforeunload only after a user gesture: a real click arms it.
        await click(dialogs, "#arm")
        let armed = await waitUntil(5) { dialogs.title == "Dialogs (armed)" }
        let pagesBefore = session.pages
        let entriesBefore = session.store.today(space: session.sidebar.activeSpaceID).map(\.id)
        SpikeRunner.record("pages", "\(pagesBefore.count) loaded, \(entriesBefore.count) entries, armed=\(armed)")

        let cdp: SpikeCDP
        do {
            cdp = try await SpikeCDP.connect(port: port, pageURL: dialogs.url?.absoluteString ?? "")
            try await cdp.call("Page.enable")
        } catch {
            SpikeRunner.record("error", "quitstay: CDP: \(error)")
            return
        }

        // ⌘Q's path: RoomCrApplication asks AppDelegate.applicationShouldTerminate.
        let quitStart = ContinuousClock.now
        NSApp.terminate(nil)
        SpikeRunner.record("terminating_after_quit", app.engine.isTerminating)
        let opening = try? await cdp.waitForEvent("Page.javascriptDialogOpening", timeout: 15)
        let dialogType = (opening?["params"] as? [String: Any])?["type"] as? String ?? "none"
        SpikeRunner.record("dialog", "\(dialogType) after \(String(format: "%.0f", ms(since: quitStart)))ms")
        guard opening != nil else {
            SpikeRunner.record("error", "quitstay: no beforeunload dialog")
            return
        }
        let stayStart = ContinuousClock.now
        _ = try? await cdp.call("Page.handleJavaScriptDialog", ["accept": false])
        let cancelled = await waitUntil(5) { !app.engine.isTerminating }
        try? await Task.sleep(for: .seconds(1))
        let pagesAfter = session.pages
        let alive = pagesAfter.filter { $0.state != .closed }.count
        let entriesAfter = session.store.today(space: session.sidebar.activeSpaceID).map(\.id)
        SpikeRunner.record("stay", "cancelled=\(cancelled) after \(String(format: "%.0f", ms(since: stayStart)))ms terminating=\(app.engine.isTerminating) "
            + "pages \(pagesBefore.count)→\(pagesAfter.count) alive=\(alive) same pages=\(zip(pagesBefore, pagesAfter).allSatisfy { $0 === $1 }) "
            + "entries \(entriesBefore.count)→\(entriesAfter.count) same=\(entriesBefore == entriesAfter) window=\(window.isVisible)")
        SpikeRunner.record("stay_reply", "quitInProgress cleared, app running pid \(ProcessInfo.processInfo.processIdentifier)")

        // The runner's quit (after `end`) raises the dialog again: answer "leave".
        Task { @MainActor in
            let again = try? await cdp.waitForEvent("Page.javascriptDialogOpening", timeout: 30)
            SpikeRunner.record("leave", again == nil ? "no second dialog" : "dialog again; answering leave")
            _ = try? await cdp.call("Page.handleJavaScriptDialog", ["accept": true])
        }
    }

    func quitFlags() async {
        guard let app = AppDelegate.current else { return }
        SpikeRunner.record("previous_exit", app.previousExitSummary ?? "unknown")
    }
}

/// Spike-only loopback DevTools protocol client over the Debug build's
/// remote-debugging port (the embryo host's `HostCDP`, plus event waits).
@MainActor
final class SpikeCDP {
    private let socket: URLSessionWebSocketTask
    private var nextID = 0
    private var events: [[String: Any]] = []

    private init(url: URL) {
        socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
    }

    static func connect(port: Int, pageURL: String) async throws -> SpikeCDP {
        let endpoint = URL(string: "http://127.0.0.1:\(port)/json/list")!
        for _ in 0..<100 {
            if let (data, _) = try? await URLSession.shared.data(from: endpoint),
               let targets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let target = targets.first(where: { ($0["type"] as? String) == "page" && ($0["url"] as? String) == pageURL }),
               let address = target["webSocketDebuggerUrl"] as? String, let url = URL(string: address) {
                return SpikeCDP(url: url)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure("no DevTools target for \(pageURL)")
    }

    @discardableResult
    func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        while true {
            let response = try await receive()
            if response["id"] as? Int == id {
                if let error = response["error"] { throw Failure("\(method): \(error)") }
                return response["result"] as? [String: Any] ?? [:]
            }
            if response["method"] != nil { events.append(response) }
        }
    }

    /// The next (or an already received) event named `method`.
    func waitForEvent(_ method: String, timeout: Double) async throws -> [String: Any] {
        if let index = events.firstIndex(where: { $0["method"] as? String == method }) {
            return events.remove(at: index)
        }
        let socket = socket
        let timer = Task {
            try await Task.sleep(for: .seconds(timeout))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { timer.cancel() }
        while true {
            let message = try await receive()
            if message["method"] as? String == method { return message }
            if message["method"] != nil { events.append(message) }
        }
    }

    private func receive() async throws -> [String: Any] {
        let message = try await socket.receive()
        let bytes: Data
        switch message {
        case .data(let data): bytes = data
        case .string(let string): bytes = Data(string.utf8)
        @unknown default: throw Failure("unknown WebSocket message")
        }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw Failure("non-object DevTools message")
        }
        return object
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
#endif
