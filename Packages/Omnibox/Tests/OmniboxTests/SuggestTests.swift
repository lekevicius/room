import Foundation
import Synchronization
import Testing
@testable import Omnibox

/// Records requests; answers at once or, when gated, when the test opens the gate.
final class FakeTransport: SuggestTransport, Sendable {
    private struct State {
        var requests: [URL] = []
        var cancelled = 0
        var gated = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    let response: Data

    init(response: String = #"["swift", ["swift", "swift ui", "swiftui tutorial", "swift.org", "swift playgrounds", "swift package", "swiftlint"]]"#) {
        self.response = Data(response.utf8)
    }

    var requests: [URL] { state.withLock { $0.requests } }
    var cancelled: Int { state.withLock { $0.cancelled } }
    var inFlight: Int { state.withLock { $0.waiting.count } }

    func gate() { state.withLock { $0.gated = true } }

    func open() {
        let waiting = state.withLock { state in
            state.gated = false
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }

    func data(for request: URLRequest) async throws -> Data {
        let gated = state.withLock { state in
            state.requests.append(request.url!)
            return state.gated
        }
        if gated {
            await withCheckedContinuation { continuation in state.withLock { $0.waiting.append(continuation) } }
        }
        if Task.isCancelled {
            state.withLock { $0.cancelled += 1 }
            throw CancellationError()
        }
        return response
    }
}

/// The debounce as a wait the test ends by hand (no wall-clock in unit tests).
final class ManualSleep: Sendable {
    private let waiting = Mutex<[CheckedContinuation<Void, Never>]>([])

    var count: Int { waiting.withLock { $0.count } }

    var sleep: SuggestClient.Sleep {
        { [self] _ in await withCheckedContinuation { continuation in waiting.withLock { $0.append(continuation) } } }
    }

    func release() {
        let all = waiting.withLock { list in
            defer { list = [] }
            return list
        }
        all.forEach { $0.resume() }
    }
}

/// Lets queued main-actor tasks and the transport run (bounded; no clock).
@MainActor
private func settle(until condition: () -> Bool = { false }) async {
    for _ in 0..<500 {
        if condition() { return }
        await Task.yield()
    }
}

@MainActor
@Suite("Search suggest client (ROADMAP 2.4 task 6)")
struct SuggestClientTests {
    @Test("Nothing is sent before the debounce passes; then one request, for the last query, capped at five")
    func debounce() async {
        let transport = FakeTransport(), sleep = ManualSleep()
        let client = SuggestClient(transport: transport, debounce: .milliseconds(120), sleep: sleep.sleep)
        var delivered: [[String]] = []
        for query in ["s", "sw", "swi", "swift"] {
            client.request(query, engine: .google) { delivered.append($0) }
        }
        await settle { sleep.count == 4 }
        #expect(transport.requests.isEmpty)
        sleep.release()
        await settle { !delivered.isEmpty }
        #expect(transport.requests.map(\.absoluteString) == ["https://suggestqueries.google.com/complete/search?client=firefox&q=swift"])
        #expect(delivered == [["swift ui", "swiftui tutorial", "swift.org", "swift playgrounds", "swift package"]])
    }

    @Test("With the switch off nothing is sent; turning it off drops a waiting request and an answer in flight")
    func offSwitch() async {
        let transport = FakeTransport(), sleep = ManualSleep()
        let client = SuggestClient(transport: transport, debounce: .milliseconds(120), sleep: sleep.sleep)
        var enabled = false
        client.isEnabled = { enabled }
        var delivered = 0
        client.request("swift", engine: .google) { _ in delivered += 1 }
        await settle()
        #expect(sleep.count == 0)

        enabled = true
        client.request("swift", engine: .google) { _ in delivered += 1 }
        await settle { sleep.count == 1 }
        enabled = false
        sleep.release()
        await settle()
        #expect(transport.requests.isEmpty)

        enabled = true
        transport.gate()
        client.request("swift", engine: .google) { _ in delivered += 1 }
        await settle { sleep.count == 1 }
        sleep.release()
        await settle { transport.inFlight == 1 }
        enabled = false
        transport.open()
        await settle()
        #expect(transport.requests.count == 1)
        #expect(delivered == 0)
    }

    @Test("A keystroke cancels the request in flight; only the newer answer is delivered")
    func cancelsInFlight() async {
        let transport = FakeTransport(), sleep = ManualSleep()
        let client = SuggestClient(transport: transport, debounce: .milliseconds(120), sleep: sleep.sleep)
        var delivered: [String] = []
        transport.gate()
        client.request("swi", engine: .duckDuckGo) { _ in delivered.append("swi") }
        await settle { sleep.count == 1 }
        sleep.release()
        await settle { transport.inFlight == 1 }
        client.request("swift", engine: .duckDuckGo) { _ in delivered.append("swift") }
        await settle { sleep.count == 1 }
        sleep.release()
        await settle { transport.inFlight == 2 }
        transport.open()
        await settle { !delivered.isEmpty && transport.cancelled == 1 }
        #expect(transport.cancelled == 1)
        #expect(delivered == ["swift"])
        #expect(transport.requests.last?.absoluteString == "https://duckduckgo.com/ac/?q=swift&type=list")
    }

    @Test("Empty text and text that is surely a URL are never sent")
    func notQueries() async {
        let transport = FakeTransport(), sleep = ManualSleep()
        let client = SuggestClient(transport: transport, debounce: .milliseconds(120), sleep: sleep.sleep)
        for text in ["", "  ", "github.com/apple", "https://example.com", "localhost:3000"] {
            client.request(text, engine: .google) { _ in }
        }
        await settle()
        #expect(sleep.count == 0)
        #expect(transport.requests.isEmpty)
    }

    @Test("Both answer formats parse; a URL suggestion opens the page; the engine's order is kept")
    func parsing() {
        #expect(SuggestClient.parse(Data(#"[{"phrase":"kagi search"},{"phrase":"kagi"}]"#.utf8), query: "kagi") == ["kagi search"])
        #expect(SuggestClient.parse(Data("not json".utf8), query: "x").isEmpty)
        let matches = SuggestClient.matches(for: ["swift ui", "swift.org"], engine: .google)
        #expect(matches[0].action == .search(query: "swift ui", url: "https://www.google.com/search?q=swift%20ui"))
        #expect(matches[1].action == .navigate(url: "https://swift.org"))
        #expect(matches[0].relevance > matches[1].relevance)
        #expect(matches.allSatisfy { Relevance.suggest.contains($0.relevance) && $0.group == .search })
    }
}
