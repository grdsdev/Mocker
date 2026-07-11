import Foundation
import Mocker

/// Errors produced while asynchronously waiting for registry events.
public enum MockRegistryWaitError: Error, Sendable, Equatable {
    /// No matching event arrived before the timeout.
    case timedOut
}

private final class WaitState: @unchecked Sendable {
    let lock = NSLock()
    var continuation: CheckedContinuation<MockRegistryEvent, Error>?
    var observation: MockRegistryObservation?
    var isFinished = false

    func finish(with result: Result<MockRegistryEvent, Error>) {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        let observation = self.observation
        self.observation = nil
        lock.unlock()
        observation?.cancel()
        continuation?.resume(with: result)
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
public extension MockRegistry {
    /// Waits for the first matching event emitted after this call.
    ///
    /// Cancellation stops observation and throws `CancellationError`.
    func nextEvent(matching pattern: RequestPattern, timeout: Duration) async throws -> MockRegistryEvent {
        try await waitForEvent(matching: pattern, timeout: timeout) { _ in true }
    }

    /// Waits for the first matching completion emitted after this call.
    func nextCompletedRequest(matching pattern: RequestPattern, timeout: Duration) async throws -> (request: MockedRequest, outcome: MockedRequestOutcome) {
        let event = try await waitForEvent(matching: pattern, timeout: timeout) {
            if case .completed = $0 { return true }
            return false
        }
        guard case .completed(let request, let outcome) = event else { preconditionFailure("Completion filter returned a start event") }
        return (request, outcome)
    }

    private func waitForEvent(matching pattern: RequestPattern, timeout: Duration, accepting predicate: @escaping @Sendable (MockRegistryEvent) -> Bool) async throws -> MockRegistryEvent {
        let state = WaitState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.lock.lock()
                guard !state.isFinished else {
                    state.lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                state.continuation = continuation
                state.observation = observeEvents(matching: pattern) { event in
                    if predicate(event) { state.finish(with: .success(event)) }
                }
                state.lock.unlock()
                let components = timeout.components
                let seconds = max(0, components.seconds)
                let nanos = UInt64(seconds) * 1_000_000_000 + UInt64(max(0, components.attoseconds / 1_000_000_000))
                Task {
                    try? await Task<Never, Never>.sleep(nanoseconds: nanos)
                    state.finish(with: .failure(MockRegistryWaitError.timedOut))
                }
            }
        } onCancel: {
            state.finish(with: .failure(CancellationError()))
        }
    }
}
