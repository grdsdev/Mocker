import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Mocker

final class URLMatchingTests: XCTestCase {
    func testIgnoreQueryPreservesOriginPortAndEncodedPath() {
        let base = URL(string: "https://example.com/resource?a=1")!
        XCTAssertTrue(base.matches(URL(string: "https://example.com/resource?b=2"), matchType: .ignoreQuery))
        XCTAssertFalse(base.matches(URL(string: "https://example.com:8443/resource"), matchType: .ignoreQuery))
        XCTAssertFalse(URL(string: "https://example.com/a%2Fb")!.matches(URL(string: "https://example.com/a/b"), matchType: .ignoreQuery))
    }

    func testPrefixUsesOriginAndPathSegmentBoundariesAndIgnoresQuery() {
        let prefix = URL(string: "https://example.com/private?ignored=true")!
        XCTAssertTrue(URL(string: "https://example.com/private")!.matches(prefix, matchType: .prefix))
        XCTAssertTrue(URL(string: "https://example.com/private/profile?q=1")!.matches(prefix, matchType: .prefix))
        XCTAssertFalse(URL(string: "https://example.com/privateer")!.matches(prefix, matchType: .prefix))
        XCTAssertFalse(URL(string: "https://example.com.evil/private")!.matches(prefix, matchType: .prefix))
        XCTAssertFalse(URL(string: "https://example.com:8443/private")!.matches(prefix, matchType: .prefix))
    }

    func testExtensionMatchingIsCaseInsensitiveAndPreservesInternalDots() {
        let png = Mock(fileExtensions: ".png", statusCode: 200, data: [.get: Data()])
        XCTAssertTrue(png == URLRequest(url: URL(string: "https://example.com/image.PNG")!))

        let archive = Mock(fileExtensions: "tar.gz", statusCode: 200, data: [.get: Data()])
        XCTAssertEqual(archive.fileExtensions, ["tar.gz"])
        XCTAssertFalse(archive == URLRequest(url: URL(string: "https://example.com/archive.targz")!))
    }
}

final class RegistryConcurrencyTests: XCTestCase {
    override func tearDown() {
        Mocker.removeAll()
        Mocker.mode = .optout
        Mocker.httpVersion = .http1_1
        super.tearDown()
    }

    func testRegisterAndIgnoreAreImmediatelyVisible() {
        let url = URL(string: "https://example.com/immediate")!
        let request = URLRequest(url: url)
        Mock(url: url, statusCode: 200, data: [.get: Data()]).register()
        XCTAssertNotNil(Mocker.mock(for: request))

        Mocker.ignore(url)
        XCTAssertFalse(MockingURLProtocol.canInit(with: request))
    }

    func testConcurrentConfigurationAndRegistryAccess() {
        let queue = DispatchQueue(label: "phase1.registry.stress", attributes: .concurrent)
        let group = DispatchGroup()
        for index in 0..<200 {
            group.enter()
            queue.async {
                let url = URL(string: "https://example.com/\(index)")!
                let request = URLRequest(url: url)
                Mocker.mode = index.isMultiple(of: 2) ? .optin : .optout
                Mocker.httpVersion = index.isMultiple(of: 2) ? .http2_0 : .http1_1
                Mock(url: url, statusCode: 200, data: [.get: Data()]).register()
                _ = Mocker.shouldHandle(request)
                _ = Mocker.mock(for: request)
                if index.isMultiple(of: 10) { Mocker.removeAll() }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
    }
}

final class MockDeterminismTests: XCTestCase {
    func testAnonymousMultiMethodMocksHaveStableRequest() {
        let forward: [Mock.HTTPMethod: Data] = [.post: Data(), .get: Data()]
        let reverse = Dictionary(uniqueKeysWithValues: forward.reversed())
        let first = Mock(contentType: .json, statusCode: 200, data: forward)
        let second = Mock(contentType: .json, statusCode: 200, data: reverse)
        XCTAssertEqual(first.request.url, second.request.url)
        XCTAssertEqual(first.request.httpMethod, second.request.httpMethod)
        XCTAssertEqual(first.request.httpMethod, "GET")
    }
}

final class ResponseURLTests: XCTestCase {
    override func tearDown() {
        Mocker.removeAll()
        super.tearDown()
    }

    func testIgnoreQueryResponseUsesInterceptedRequestURL() {
        let expected = URL(string: "https://example.com/value?actual=2")!
        Mock(url: URL(string: "https://example.com/value?registered=1")!, ignoreQuery: true,
             statusCode: 200, data: [.get: Data()]).register()
        let expectation = expectation(description: "response")
        URLSession.shared.dataTask(with: expected) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual(response?.url, expected)
            expectation.fulfill()
        }.resume()
        wait(for: [expectation], timeout: 5)
    }

    func testExtensionResponseUsesInterceptedRequestURL() {
        let expected = URL(string: "https://cdn.example.com/image.PNG?size=2")!
        Mock(fileExtensions: "png", statusCode: 200, data: [.get: Data()]).register()
        let expectation = expectation(description: "response")
        URLSession.shared.dataTask(with: expected) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual(response?.url, expected)
            expectation.fulfill()
        }.resume()
        wait(for: [expectation], timeout: 5)
    }
}

final class RequestBodyStreamTests: XCTestCase {
    private struct Payload: Codable, Equatable { let value: String }

    func testBodyLargerThanBufferAndPartialReadsAreComplete() {
        let expected = Payload(value: String(repeating: "value", count: 40))
        let encoded = try! JSONEncoder().encode(expected)
        var request = URLRequest(url: URL(string: "https://example.com/body")!)
        request.httpBodyStream = ChunkedInputStream(data: encoded, chunkSize: 3)
        let expectation = expectation(description: "body")
        let handler = OnRequestHandler(httpBodyType: Payload.self) { _, body in
            XCTAssertEqual(body, expected)
            expectation.fulfill()
        }
        handler.handleRequest(request)
        wait(for: [expectation], timeout: 1)
    }

    func testFailedStreamReturnsNilWithoutCrashing() {
        var request = URLRequest(url: URL(string: "https://example.com/body")!)
        request.httpBodyStream = FailingInputStream()
        let expectation = expectation(description: "body")
        let handler = OnRequestHandler(httpBodyType: Payload.self) { _, body in
            XCTAssertNil(body)
            expectation.fulfill()
        }
        handler.handleRequest(request)
        wait(for: [expectation], timeout: 1)
    }
}

final class URLProtocolLifecycleTests: XCTestCase {
    override func tearDown() {
        Mocker.removeAll()
        super.tearDown()
    }

    func testCancelledDelayedMockDoesNotCallCompletion() {
        let completion = expectation(description: "mock completion")
        completion.isInverted = true
        var mock = Mock(contentType: nil, statusCode: 200, data: [.get: Data()])
        mock.delay = .milliseconds(100)
        mock.completion = { completion.fulfill() }
        mock.register()

        let task = URLSession.shared.dataTask(with: mock.request)
        task.resume()
        task.cancel()
        wait(for: [completion], timeout: 0.3)
    }
}

private final class ChunkedInputStream: InputStream {
    private let bytes: [UInt8]
    private let chunkSize: Int
    private var offset = 0
    private var status: Stream.Status = .notOpen

    init(data: Data, chunkSize: Int) {
        bytes = Array(data)
        self.chunkSize = chunkSize
        super.init(data: Data())
    }

    override var streamStatus: Stream.Status { status }
    override func open() { status = .open }
    override func close() { status = .closed }
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard offset < bytes.count else {
            status = .atEnd
            return 0
        }
        let count = min(chunkSize, len, bytes.count - offset)
        for index in 0..<count { buffer[index] = bytes[offset + index] }
        offset += count
        return count
    }
}

private final class FailingInputStream: InputStream {
    private var status: Stream.Status = .notOpen

    init() { super.init(data: Data()) }
    override var streamStatus: Stream.Status { status }
    override func open() { status = .open }
    override func close() { status = .closed }
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        status = .error
        return -1
    }
}
