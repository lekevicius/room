import Foundation
import Model

/// The write side of the stores: every mutation calls `scheduleWrite()`; the
/// first one in a quiet period starts a 300 ms timer, later ones coalesce
/// into it, and when it fires the whole state goes to the `StateWriter` as
/// one transaction with the next generation number. Writes are therefore at
/// most 300 ms behind and at most ~3 per second under continuous mutation.
/// `flushAndWait` writes synchronously (quit, window close).
public final class Persistence {
    public let writer: StateWriter
    /// Generation of the last state handed to the writer.
    public private(set) var generation: Int64
    public var debounce: Duration
    /// Unwritten mutations exist.
    public private(set) var isDirty = false
    public private(set) var lastError: (any Error)?
    /// Called after each successful asynchronous commit (tests, diagnostics).
    public var onCommit: ((Int64) -> Void)?

    private var pending: Task<Void, Never>?
    private let stateProvider: () -> RoomState

    init(writer: StateWriter, generation: Int64, debounce: Duration = .milliseconds(300),
         stateProvider: @escaping () -> RoomState) {
        self.writer = writer
        self.generation = generation
        self.debounce = debounce
        self.stateProvider = stateProvider
    }

    public func scheduleWrite() {
        isDirty = true
        guard pending == nil else { return }
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Hands the current state to the writer now (asynchronously).
    public func flush() {
        pending?.cancel()
        pending = nil
        guard isDirty else { return }
        isDirty = false
        generation += 1
        let written = generation
        writer.write(stateProvider(), generation: written) { [weak self] result in
            Task { @MainActor in self?.finished(written, result) }
        }
    }

    /// Writes the current state and waits; with `cleanExit` also clears the
    /// running flag (the next launch is then not "unclean").
    public func flushAndWait(cleanExit: Bool = false) throws {
        pending?.cancel()
        pending = nil
        if isDirty {
            isDirty = false
            generation += 1
        }
        // Not dirty: rewriting the same generation is a no-op except for
        // the clean-exit flag.
        try writer.writeAndWait(stateProvider(), generation: generation, cleanExit: cleanExit)
    }

    private func finished(_ generation: Int64, _ result: Result<WriteOutcome, any Error>) {
        switch result {
        case .success(.committed):
            onCommit?(generation)
        case .success(.stale):
            break
        case .failure(let error):
            // Keep the state dirty so the next mutation retries the whole diff.
            lastError = error
            isDirty = true
        }
    }
}
