import Foundation

/// A weak reference that may travel through a `@Sendable` closure (such as
/// `withObservationTracking`'s `onChange`, which fires on any thread) and is
/// only dereferenced back on the main actor. Capturing `self` directly there
/// is a "sending 'self'" error under Swift 6 region isolation (Xcode 26.6).
struct MainActorWeak<Object: AnyObject>: @unchecked Sendable {
    private weak var object: Object?

    init(_ object: Object) { self.object = object }

    @MainActor var value: Object? { object }
}
