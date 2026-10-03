import Foundation

/// Spike-only loopback CDP transport. No RoomCore API or external dependency.
/// One command at a time; unsolicited events are recorded while waiting.
@MainActor
final class HostCDP {
    private let socket: URLSessionWebSocketTask
    private var nextID = 0
    private(set) var events: [[String: Any]] = []

    init(url: URL) {
        socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
    }

    func close() { socket.cancel(with: .goingAway, reason: nil) }

    static func connect(port: Int, pageURL: String) async throws -> HostCDP {
        let endpoint = URL(string: "http://127.0.0.1:\(port)/json/list")!
        for _ in 0..<100 {
            if let (data, _) = try? await URLSession.shared.data(from: endpoint),
               let targets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let target = targets.first(where: { ($0["type"] as? String) == "page" && ($0["url"] as? String) == pageURL }),
               let address = target["webSocketDebuggerUrl"] as? String,
               let url = URL(string: address) {
                return HostCDP(url: url)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure("no CDP target for \(pageURL)")
    }

    @discardableResult
    func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
        let timeout = Task { @MainActor in
            try await Task.sleep(for: .seconds(20))
            self.close()
        }
        defer { timeout.cancel() }
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        while true {
            let message = try await socket.receive()
            let bytes: Data
            switch message {
            case .data(let data): bytes = data
            case .string(let string): bytes = Data(string.utf8)
            @unknown default: throw Failure("unknown WebSocket message")
            }
            guard let response = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw Failure("non-object CDP response")
            }
            if response["id"] as? Int == id {
                if let error = response["error"] { throw Failure("\(method): \(error)") }
                return response["result"] as? [String: Any] ?? [:]
            }
            if let event = response["method"] as? String {
                events.append(response)
                HostSpike.record("cdp-event", event)
                if event == "Page.javascriptDialogOpening" {
                    // Dismiss through Chrome's own dialog callback. Do not let
                    // an unattended prompt leave Runtime.evaluate hanging.
                    nextID += 1
                    let dismiss = try JSONSerialization.data(withJSONObject: [
                        "id": nextID, "method": "Page.handleJavaScriptDialog",
                        "params": ["accept": false],
                    ])
                    try await socket.send(.string(String(decoding: dismiss, as: UTF8.self)))
                }
            }
        }
    }

    @discardableResult
    func evaluate(_ expression: String, userGesture: Bool = false) async throws -> Any {
        let response = try await call("Runtime.evaluate", [
            "expression": expression, "returnByValue": true,
            "awaitPromise": true, "userGesture": userGesture,
        ])
        if let error = response["exceptionDetails"] { throw Failure("JavaScript: \(error)") }
        return (response["result"] as? [String: Any])?["value"] ?? "undefined"
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
