import Foundation

/// Errors thrown by engine API calls.
nonisolated public enum EngineError: Error, Sendable, Equatable {
    /// The engine does not implement this member (e.g. no engine at all).
    /// The string names the member.
    case notSupported(String)
    /// Called before `initialize` or outside the main loop.
    case notRunning
    /// The web contents or profile was closed.
    case closed
    /// A profile name that cannot be used as a directory name.
    case invalidProfileName(String)
    /// Script evaluation threw; the payload is the exception message.
    case javaScriptException(String)
    /// The engine reported a failure it did not classify further.
    case failed(String)
}
