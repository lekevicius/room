import Foundation
import Testing
@testable import Import

/// 4.3b: the other browser's extensions through their Web Store pages, one
/// at a time (the planner's decision for task 6).
@Suite("Import: extensions through their store pages")
struct StorePageSequenceTests {
    static let a = String(repeating: "a", count: 32)
    static let b = String(repeating: "b", count: 32)
    static let c = String(repeating: "c", count: 32)

    @Test("One page at a time: the next opens when the current installs or its page closes")
    func oneAtATime() {
        var sequence = StorePageSequence(ids: [Self.a, Self.b, Self.c, Self.a])
        #expect(sequence.start(installedInProfile: []) == .open(id: Self.a, url: URL(string: "https://chromewebstore.google.com/detail/\(Self.a)")!))
        // Another extension changing does not move it on.
        #expect(sequence.extensionsChanged(installedInProfile: ["zzz"]) == nil)
        #expect(sequence.current == Self.a && sequence.pending == [Self.b, Self.c])
        #expect(sequence.extensionsChanged(installedInProfile: [Self.a]) == .open(id: Self.b, url: sequence.pageURL(for: Self.b)!))
        #expect(sequence.pageClosed() == .open(id: Self.c, url: sequence.pageURL(for: Self.c)!))
        #expect(sequence.extensionsChanged(installedInProfile: [Self.a, Self.c]) == .finished)
        #expect(sequence.isFinished)
        #expect(sequence.opened == [Self.a, Self.b, Self.c] && sequence.installed == [Self.a, Self.c] && sequence.closedWithoutInstall == [Self.b])
        #expect(sequence.pageClosed() == nil)
    }

    @Test("Already installed and invalid ids open no page; a pending one installed meanwhile leaves the queue")
    func skips() {
        var sequence = StorePageSequence(ids: [Self.a, "not-an-id", Self.b, Self.c], pageTemplate: "http://127.0.0.1:8770/store?id={id}")
        #expect(sequence.start(installedInProfile: [Self.a]) == .open(id: Self.b, url: URL(string: "http://127.0.0.1:8770/store?id=\(Self.b)")!))
        #expect(sequence.alreadyInstalled == [Self.a] && sequence.invalid == ["not-an-id"])
        #expect(sequence.extensionsChanged(installedInProfile: [Self.a, Self.c]) == nil)
        #expect(sequence.pending.isEmpty && sequence.installed == [Self.c])
        #expect(sequence.pageClosed() == .finished)
        #expect(StorePageSequence.isExtensionID(Self.a) && !StorePageSequence.isExtensionID(String(repeating: "z", count: 32)))
    }

    @Test("Cancel leaves the rest unopened")
    func cancel() {
        var sequence = StorePageSequence(ids: [Self.a, Self.b])
        _ = sequence.start(installedInProfile: [])
        sequence.cancel()
        #expect(sequence.isFinished && sequence.opened == [Self.a] && sequence.pageClosed() == nil)
    }
}
