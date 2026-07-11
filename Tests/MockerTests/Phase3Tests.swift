import XCTest
@testable import Mocker
import MockerXCTest
import MockerTesting

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class Phase3Tests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var current: Int { lock.lock(); defer { lock.unlock() }; return value }
    }
    func testSuccessRecordsOrderedStartAndCompletion() {
        let registry = MockRegistry(mode: .optin, historyCapacity: 10, bodyCapturePolicy: .complete)
        let url = URL(string: "https://example.com/events")!
        registry.register(Mock(url: url, statusCode: 201, data: [.post: Data()]))
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = Data("body".utf8)
        perform(request, in: registry)
        guard case .started(let started) = registry.events.first,
              case .completed(let completed, let outcome) = registry.events.last else { return XCTFail("missing event pair") }
        XCTAssertEqual(started.id, completed.id)
        XCTAssertEqual(started.body, Data("body".utf8))
        XCTAssertEqual(outcome, .response(statusCode: 201))
    }

    func testHistoryIsBoundedByCompleteRequestPairsAndResetIsIndependent() {
        let registry = MockRegistry(mode: .optin, historyCapacity: 1)
        let first = URL(string: "https://example.com/1")!, second = URL(string: "https://example.com/2")!
        registry.register(Mock(url: first, statusCode: 200, data: [.get: Data()]))
        registry.register(Mock(url: second, statusCode: 200, data: [.get: Data()]))
        perform(URLRequest(url: first), in: registry); perform(URLRequest(url: second), in: registry)
        XCTAssertEqual(registry.events.count, 2)
        XCTAssertEqual(registry.events(matching: RequestPattern(url: second, methods: [.get])).count, 2)
        registry.removeAll()
        XCTAssertEqual(registry.events.count, 2)
        registry.removeAllEvents()
        XCTAssertTrue(registry.events.isEmpty)
        XCTAssertFalse(registry.shouldHandle(URLRequest(url: second)))
    }

    func testBoundedHistoryNeverKeepsCompletionWithoutItsStart() {
        let registry = MockRegistry(historyCapacity: 1)
        let first = MockedRequest(id: UUID(), url: URL(string: "https://example.com/first")!, method: .get, headers: [:], body: nil, isBodyTruncated: false, pattern: RequestPattern(url: URL(string: "https://example.com/first")!, methods: [.get]))
        let second = MockedRequest(id: UUID(), url: URL(string: "https://example.com/second")!, method: .get, headers: [:], body: nil, isBodyTruncated: false, pattern: RequestPattern(url: URL(string: "https://example.com/second")!, methods: [.get]))
        registry.record(.started(first)); registry.record(.started(second)); registry.record(.completed(first, outcome: .response(statusCode: 200)))
        XCTAssertFalse(registry.events.contains { $0.request.id == first.id })
        registry.record(.completed(second, outcome: .response(statusCode: 200)))
        XCTAssertEqual(registry.events.map(\.request.id), [second.id, second.id])
    }

    func testObservationCanReenterAndCancellationStopsLaterCallbacks() {
        let registry = MockRegistry(mode: .optin)
        let url = URL(string: "https://example.com/observe")!
        let pattern = RequestPattern(url: url, methods: [.get])
        registry.register(Mock(url: url, statusCode: 200, data: [.get: Data()]))
        let count = Counter()
        let observation = registry.observeEvents(matching: pattern) { _ in
            _ = registry.events
            count.increment()
        }
        perform(URLRequest(url: url), in: registry)
        observation.cancel()
        perform(URLRequest(url: url), in: registry)
        XCTAssertEqual(count.current, 2)
    }

    func testXCTestAdapterObservesCompletion() {
        let registry = MockRegistry(mode: .optin)
        let url = URL(string: "https://example.com/xctest")!
        let pattern = RequestPattern(url: url, methods: [.get])
        registry.register(Mock(url: url, statusCode: 204, data: [.get: Data()]))
        let completed = expectation(in: registry, for: pattern, event: .completed)
        perform(URLRequest(url: url), in: registry)
        wait(for: [completed], timeout: 1)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    func testTestingAdapterReturnsFutureCompletion() async throws {
        let registry = MockRegistry(mode: .optin)
        let url = URL(string: "https://example.com/async")!
        let pattern = RequestPattern(url: url, methods: [.get])
        registry.register(Mock(url: url, statusCode: 202, data: [.get: Data()]))
        let waiter = Task { try await registry.nextCompletedRequest(matching: pattern, timeout: .seconds(1)) }
        await Task.yield()
        perform(URLRequest(url: url), in: registry)
        let result = try await waiter.value
        XCTAssertEqual(result.outcome, .response(statusCode: 202))
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    func testTestingAdapterHandlesImmediateCancellation() async {
        let registry = MockRegistry()
        let pattern = RequestPattern(url: URL(string: "https://example.com/cancel")!, methods: [.get])
        let waiter = Task { try await registry.nextEvent(matching: pattern, timeout: .seconds(10)) }
        waiter.cancel()
        do { _ = try await waiter.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func perform(_ request: URLRequest, in registry: MockRegistry) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockingURLProtocol.self]
        let done = expectation(description: "request")
        URLSession(configuration: configuration).dataTask(with: registry.scopedRequest(from: request)) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 2)
    }
}
