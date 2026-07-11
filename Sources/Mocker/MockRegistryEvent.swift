import Foundation

/// Controls how request bodies are copied into observation snapshots.
public enum RequestBodyCapturePolicy: Sendable {
    /// Does not capture request bodies.
    case none
    /// Captures at most the specified number of leading bytes.
    case upToBytes(Int)
    /// Captures the complete in-memory request body.
    case complete
}

/// An immutable request snapshot emitted by a mock registry.
public struct MockedRequest: Sendable, Equatable {
    /// The identifier correlating the start and completion events.
    public let id: UUID
    /// The intercepted URL.
    public let url: URL
    /// The effective HTTP method.
    public let method: Mock.HTTPMethod
    /// A copy of the request headers.
    public let headers: [String: String]
    /// The captured body, when enabled and available.
    public let body: Data?
    /// Whether `body` is only a prefix of the request body.
    public let isBodyTruncated: Bool
    /// A body read failure captured before observation, when one occurred.
    public let bodyError: RequestBodyError?
    /// The pattern that selected the response.
    public let pattern: RequestPattern

    /// Creates an immutable request snapshot.
    public init(id: UUID, url: URL, method: Mock.HTTPMethod, headers: [String: String], body: Data?, isBodyTruncated: Bool, bodyError: RequestBodyError? = nil, pattern: RequestPattern) {
        self.id = id; self.url = url; self.method = method; self.headers = headers; self.body = body; self.isBodyTruncated = isBodyTruncated; self.bodyError = bodyError; self.pattern = pattern
    }
}

/// The terminal outcome of a selected mocked request.
public enum MockedRequestOutcome: Sendable, Equatable {
    /// A normal HTTP response.
    case response(statusCode: Int)
    /// A mocked redirect.
    case redirected(to: URL)
    /// A mocked failure, represented by its stable description.
    case failed(description: String)
    /// Cancellation before response delivery.
    case cancelled
}

/// A lifecycle event recorded by a mock registry.
public enum MockRegistryEvent: Sendable, Equatable {
    /// A selected request is about to begin URL loading.
    case started(MockedRequest)
    /// A selected request reached one terminal outcome.
    case completed(MockedRequest, outcome: MockedRequestOutcome)

    /// The event's request snapshot.
    public var request: MockedRequest {
        switch self { case .started(let request), .completed(let request, _): return request }
    }
}

/// A cancellable registry-event subscription.
///
/// The unchecked sendability is protected by the slot's lock.
public final class MockRegistryObservation: @unchecked Sendable {
    final class Slot: @unchecked Sendable {
        private let condition = NSCondition()
        private var acceptsCallbacks = true
        let pattern: RequestPattern?
        let observer: @Sendable (MockRegistryEvent) -> Void

        init(pattern: RequestPattern?, observer: @escaping @Sendable (MockRegistryEvent) -> Void) {
            self.pattern = pattern; self.observer = observer
        }

        func invoke(_ event: MockRegistryEvent) {
            condition.lock()
            guard acceptsCallbacks else { condition.unlock(); return }
            condition.unlock()
            observer(event)
        }

        func cancel() {
            condition.lock(); acceptsCallbacks = false; condition.unlock()
        }
    }

    private let slot: Slot
    private let onCancel: @Sendable () -> Void
    init(slot: Slot, onCancel: @escaping @Sendable () -> Void) { self.slot = slot; self.onCancel = onCancel }

    /// Synchronously prevents new observer callbacks from beginning.
    public func cancel() { slot.cancel(); onCancel() }
    deinit { cancel() }
}
