import XCTest
import Mocker
import MockerXCTest
import MockerTesting

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class Phase5Tests: XCTestCase {
    func testValidatedMockResponseConfigurationAndDelivery() throws {
        let url = URL(string: "https://example.com/new-api")!
        let pattern = try RequestPattern(url: url, methods: [.post])
        let response = try MockResponse(statusCode: 201, contentType: .json, headers: ["X-Test": "yes"], body: Data("ok".utf8))
        let mock = try Mock(matching: pattern, responses: [.post: .response(response)])
        let registry = try MockRegistry(mode: .optIn, bodyCapturePolicy: .complete)
        registry.register(mock)
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = Data("{\"value\":1}".utf8)
        let result = try perform(request, in: registry)
        XCTAssertEqual(result.data, Data("ok".utf8))
        XCTAssertEqual(result.response.statusCode, 201)
        XCTAssertEqual(result.response.value(forHTTPHeaderField: "Content-Type"), HTTPContentType.json.rawValue)
    }

    func testInvalidConfigurationReturnsTypedErrors() throws {
        XCTAssertThrowsError(try MockResponse(statusCode: 99)) { XCTAssertEqual($0 as? MockConfigurationError, .invalidStatusCode(99)) }
        let pattern = try RequestPattern(url: URL(string: "https://example.com")!, methods: [.get])
        XCTAssertThrowsError(try Mock(matching: pattern, responses: [:])) { XCTAssertEqual($0 as? MockConfigurationError, .noResponses) }
        XCTAssertThrowsError(try Mock(matching: pattern, responses: [.post: .response(try MockResponse(statusCode: 200))])) {
            XCTAssertEqual($0 as? MockConfigurationError, .methodHasNoResponse(.get))
        }
        XCTAssertThrowsError(try MockRegistry(historyCapacity: -1)) { XCTAssertEqual($0 as? MockConfigurationError, .invalidHistoryCapacity(-1)) }
        XCTAssertThrowsError(try MockRegistry(bodyCapturePolicy: .upToBytes(-1))) { XCTAssertEqual($0 as? MockConfigurationError, .invalidBodyCaptureLimit(-1)) }
    }

    func testRedirectFailureAndHTTPVersionNames() throws {
        let redirectURL = URL(string: "https://example.com/destination")!
        let redirectPattern = try RequestPattern(url: URL(string: "https://example.com/redirect")!, methods: [.get])
        let registry = try MockRegistry(mode: .optIn, httpVersion: .http2)
        registry.register(try Mock(matching: redirectPattern, responses: [.get: .redirect(to: redirectURL, statusCode: 302, headers: [:])]))
        XCTAssertEqual(registry.httpVersion, .http2)
        let failure = MockFailure(domain: "tests", code: 42, description: "expected")
        let failurePattern = try RequestPattern(url: URL(string: "https://example.com/failure")!, methods: [.get])
        registry.register(try Mock(matching: failurePattern, responses: [.get: .failure(failure)]))
        XCTAssertThrowsError(try perform(URLRequest(url: failurePatternURL), in: registry))
    }

    func testObservedRequestDecodesBodyWithExplicitErrors() throws {
        struct Payload: Codable, Sendable, Equatable { let value: Int }
        let url = URL(string: "https://example.com/body")!
        let pattern = try RequestPattern(url: url, methods: [.post])
        let request = MockedRequest(id: UUID(), url: url, method: .post, headers: [:], body: Data("{\"value\":2}".utf8), isBodyTruncated: false, pattern: pattern)
        XCTAssertEqual(try request.decodeBody(as: Payload.self), Payload(value: 2))
        let absent = MockedRequest(id: UUID(), url: url, method: .post, headers: [:], body: nil, isBodyTruncated: false, pattern: pattern)
        XCTAssertThrowsError(try absent.decodeBody(as: Payload.self)) { XCTAssertEqual($0 as? RequestBodyError, .absent) }
    }

    func testPatternNormalizationReplacementAndSpecificPrecedence() throws {
        let registry = try MockRegistry(mode: .optIn)
        let exactURL = URL(string: "HTTPS://Example.COM:443/images/item.PNG?size=1")!
        let exact = try RequestPattern(url: exactURL, methods: [.get])
        XCTAssertEqual(exact, try RequestPattern(url: URL(string: "https://example.com/images/item.PNG?size=1")!, methods: [.get]))
        let extensions = try RequestPattern(fileExtensions: ["png", ".JPG"], methods: [.get])
        registry.register(try Mock(matching: extensions, responses: [.get: .response(try MockResponse(statusCode: 203, body: Data("extension".utf8)))]))
        registry.register(try Mock(matching: exact, responses: [.get: .response(try MockResponse(statusCode: 200, body: Data("old".utf8)))]))
        registry.register(try Mock(matching: exact, responses: [.get: .response(try MockResponse(statusCode: 201, body: Data("exact".utf8)))]))
        let result = try perform(URLRequest(url: exactURL), in: registry)
        XCTAssertEqual(result.response.statusCode, 201)
        XCTAssertEqual(result.data, Data("exact".utf8))
    }

    func testObservationHistoryAndBodyTruncationRemainFrameworkNeutral() throws {
        let registry = try MockRegistry(mode: .optIn, historyCapacity: 1, bodyCapturePolicy: .upToBytes(2))
        let url = URL(string: "https://example.com/history")!
        let pattern = try RequestPattern(url: url, methods: [.post])
        registry.register(try Mock(matching: pattern, responses: [.post: .response(try MockResponse(statusCode: 204))]))
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = Data("body".utf8)
        _ = try perform(request, in: registry)
        XCTAssertEqual(registry.events.count, 2)
        guard case .started(let observed) = registry.events.first else { return XCTFail("missing start") }
        XCTAssertEqual(observed.body, Data("bo".utf8)); XCTAssertTrue(observed.isBodyTruncated)
        XCTAssertThrowsError(try observed.decodeBody(as: String.self)) { XCTAssertEqual($0 as? RequestBodyError, .truncated) }
        registry.removeAll()
        XCTAssertEqual(registry.events.count, 2)
        registry.removeAllEvents(); XCTAssertTrue(registry.events.isEmpty)
    }

    func testDelayedCancellationRecordsOneTerminalCancellation() throws {
        let registry = try MockRegistry(mode: .optIn)
        let url = URL(string: "https://example.com/cancelled")!
        let pattern = try RequestPattern(url: url, methods: [.get])
        let response = try MockResponse(statusCode: 200, delay: .seconds(1))
        registry.register(try Mock(matching: pattern, responses: [.get: .response(response)]))
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockingURLProtocol.self]
        let task = URLSession(configuration: configuration).dataTask(with: registry.scopedRequest(from: URLRequest(url: url)))
        task.resume()
        let deadline = Date().addingTimeInterval(1)
        while registry.events.isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        task.cancel(); task.cancel()
        while registry.events.count < 2 && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        let terminal = registry.events.compactMap { event -> MockedRequestOutcome? in
            if case .completed(_, let outcome) = event { return outcome }; return nil
        }
        XCTAssertEqual(terminal, [.cancelled])
    }

    func testXCTestAdapterObservesCompletionWithoutMutatingMock() throws {
        let registry = try MockRegistry(mode: .optIn)
        let url = URL(string: "https://example.com/xctest-adapter")!
        let pattern = try RequestPattern(url: url, methods: [.get])
        registry.register(try Mock(matching: pattern, responses: [.get: .response(try MockResponse(statusCode: 200))]))
        let completed = expectation(in: registry, for: pattern, event: .completed)
        _ = try perform(URLRequest(url: url), in: registry)
        wait(for: [completed], timeout: 1)
    }

    func testAsyncAdapterTimesOutAndPreservesCancellation() async throws {
        let registry = try MockRegistry()
        let pattern = try RequestPattern(url: URL(string: "https://example.com/async-adapter")!, methods: [.get])
        do { _ = try await registry.nextEvent(matching: pattern, timeout: .milliseconds(1)); XCTFail("expected timeout") }
        catch { XCTAssertEqual(error as? MockRegistryWaitError, .timedOut) }
        let waiter = Task { try await registry.nextEvent(matching: pattern, timeout: .seconds(10)) }
        waiter.cancel()
        do { _ = try await waiter.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCoreSourcesContainNoTestingFrameworkReferences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Mocker")
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "swift" }) {
            let text = try String(contentsOf: file)
            XCTAssertFalse(text.contains("import XCTest")); XCTAssertFalse(text.contains("XCTestExpectation")); XCTAssertFalse(text.contains("import Testing"))
        }
    }

    private var failurePatternURL: URL { URL(string: "https://example.com/failure")! }

    private func perform(_ request: URLRequest, in registry: MockRegistry) throws -> (data: Data, response: HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockingURLProtocol.self]
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var result: Result<(Data, HTTPURLResponse), Error>? }
        let box = Box()
        URLSession(configuration: configuration).dataTask(with: registry.scopedRequest(from: request)) { data, response, error in
            if let error { box.result = .failure(error) }
            else { box.result = .success((data ?? Data(), response as! HTTPURLResponse)) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return try XCTUnwrap(box.result).get()
    }
}
