import XCTest
import Mocker

/// Selects the lifecycle event that fulfills a registry-backed expectation.
public enum ObservedRequestEvent: Sendable {
    /// Fulfill when a matching request starts.
    case started
    /// Fulfill when a matching request completes.
    case completed
}

private final class ObservationHolder: @unchecked Sendable {
    let lock = NSLock()
    var count = 0
    private var observation: MockRegistryObservation?
    private var isFulfilled = false

    func install(_ observation: MockRegistryObservation) {
        lock.lock()
        if isFulfilled { lock.unlock(); observation.cancel(); return }
        self.observation = observation
        lock.unlock()
    }

    func recordFulfillment(expectedCount: Int) {
        lock.lock(); count += 1
        if count == expectedCount { isFulfilled = true; observation = nil }
        lock.unlock()
    }
}

public extension XCTestCase {
    /// Creates an expectation fulfilled by future matching registry events.
    func expectation(in registry: MockRegistry, for pattern: RequestPattern, event: ObservedRequestEvent = .started, expectedFulfillmentCount: Int = 1) -> XCTestExpectation {
        let expectation = expectation(description: "Observe \(event) for \(pattern)")
        expectation.expectedFulfillmentCount = expectedFulfillmentCount
        let holder = ObservationHolder()
        let observation = registry.observeEvents(matching: pattern) { observed in
            let matches: Bool
            switch (event, observed) {
            case (.started, .started), (.completed, .completed): matches = true
            default: matches = false
            }
            guard matches else { return }
            expectation.fulfill()
            holder.recordFulfillment(expectedCount: expectedFulfillmentCount)
        }
        holder.install(observation)
        return expectation
    }
}
