import Foundation

/// Sends a suggestion request (the network in the app, a fake in tests).
public protocol SuggestTransport: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

/// URLSession without cookies, cache or credentials: a suggestion request
/// carries the typed text and nothing else.
public struct URLSessionSuggestTransport: SuggestTransport {
    private let session: URLSession

    /// `proxy` ("host:port", DEBUG checks only) routes requests through an HTTP proxy.
    public init(proxy: String? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 3
        if let proxy, let colon = proxy.lastIndex(of: ":"), let port = Int(proxy[proxy.index(after: colon)...]) {
            let host = String(proxy[..<colon])
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: true, kCFNetworkProxiesHTTPProxy: host, kCFNetworkProxiesHTTPPort: port,
                "HTTPSEnable": true, "HTTPSProxy": host, "HTTPSPort": port,
            ]
        }
        session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
}

/// Search suggestions from the default engine (ROADMAP 2.4 task 6): one
/// request per pause in typing. Nothing is sent while `isEnabled` says no
/// (the Settings switch, read at every step so turning it off holds at
/// once), nothing before the debounce has passed without another keystroke,
/// and each keystroke cancels the request in flight. Typed text that is
/// surely a URL is never sent (it is a page, not a query).
@MainActor
public final class SuggestClient {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    /// At most this many suggestions are shown (`macos-ui-stack.md` §5.2).
    public static let limit = 5

    private let transport: any SuggestTransport
    private let sleep: Sleep
    public var debounce: Duration
    /// The off switch (CLAUDE.md): checked before the debounce, after it and when the answer arrives.
    public var isEnabled: () -> Bool = { true }
    private var task: Task<Void, Never>?
    private var generation = 0

    /// `sleep`: the debounce wait (tests pass one they release by hand).
    public init(transport: any SuggestTransport, debounce: Duration, sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.debounce = debounce
        self.sleep = sleep
    }

    /// Asks for suggestions for `query` after the debounce; `deliver` runs on
    /// the main actor with at most `limit` suggestions, unless a newer
    /// request, `cancel()` or the off switch came first.
    public func request(_ query: String, engine: SearchEngine, deliver: @escaping @MainActor ([String]) -> Void) {
        cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled(), Self.shouldSend(text), let url = engine.suggestURL(for: text) else { return }
        let current = generation
        let sleep = sleep, transport = transport, debounce = debounce
        task = Task { [weak self] in
            do { try await sleep(debounce) } catch { return }
            guard let self, self.isCurrent(current) else { return }
            var request = URLRequest(url: url)
            request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data: Data
            do { data = try await transport.data(for: request) } catch { return }
            guard self.isCurrent(current) else { return }
            deliver(Array(Self.parse(data, query: text).prefix(Self.limit)))
        }
    }

    /// Drops the pending or in-flight request (a keystroke, the palette closing, the switch turned off).
    public func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func isCurrent(_ requestGeneration: Int) -> Bool {
        !Task.isCancelled && generation == requestGeneration && isEnabled()
    }

    /// Queries only: not empty, not surely a URL.
    static func shouldSend(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if case .url(_, confident: true) = URLFixup.classify(text) { return false }
        return true
    }

    /// OpenSearch suggestions (`["q", ["s1", "s2"]]`, Google, DuckDuckGo with
    /// `type=list`, Kagi); DuckDuckGo's object list (`[{"phrase": …}]`) too.
    /// The typed text itself is not a suggestion.
    static func parse(_ data: Data, query: String) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var suggestions: [String] = []
        if let array = json as? [Any], array.count >= 2, let list = array[1] as? [Any] {
            suggestions = list.compactMap { $0 as? String }
        } else if let objects = json as? [[String: Any]] {
            suggestions = objects.compactMap { $0["phrase"] as? String }
        }
        let typed = query.lowercased()
        var seen = Set<String>()
        return suggestions.filter { !$0.isEmpty && $0.lowercased() != typed && seen.insert($0.lowercased()).inserted }
    }

    /// Suggestions as matches (spec §C search group): a search for each, or
    /// the page when a suggestion is surely a URL; the engine's order is kept
    /// inside `Relevance.suggest`.
    public static func matches(for suggestions: [String], engine: SearchEngine) -> [OmniboxMatch] {
        suggestions.enumerated().map { index, suggestion in
            let fraction = 1 - Double(index) / Double(max(1, limit))
            let relevance = Relevance.scaled(fraction, in: Relevance.suggest)
            if case .url(let url, confident: true) = URLFixup.classify(suggestion) {
                return OmniboxMatch(id: "suggest:\(suggestion)", provider: .suggest, relevance: relevance, action: .navigate(url: url),
                                    title: suggestion, icon: .url)
            }
            return OmniboxMatch(id: "suggest:\(suggestion)", provider: .suggest, relevance: relevance,
                                action: .search(query: suggestion, url: engine.searchURL(for: suggestion)), title: suggestion, icon: .search)
        }
    }
}
