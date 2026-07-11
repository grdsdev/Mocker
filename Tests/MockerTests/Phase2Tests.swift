import XCTest
@testable import Mocker

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class Phase2Tests: XCTestCase {
    func testRequestPatternNormalizesURLIdentityAndMethods() {
        let first = RequestPattern(url: URL(string: "HTTPS://Example.COM:443/a%2Fb?x=1")!, methods: [.get])
        let second = RequestPattern(url: URL(string: "https://example.com/a%2Fb?x=1")!, methods: [.get])
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, RequestPattern(url: URL(string: "https://example.com/a/b?x=1")!, methods: [.get]))
        XCTAssertNotEqual(first, RequestPattern(url: URL(string: "https://example.com/a%2Fb?x=2")!, methods: [.get]))
    }

    func testIgnoreQueryPrefixAndExtensionSemantics() {
        XCTAssertEqual(
            RequestPattern(url: URL(string: "https://example.com/a?q=1#one")!, matchType: .ignoreQuery),
            RequestPattern(url: URL(string: "https://EXAMPLE.com:443/a?q=2#two")!, matchType: .ignoreQuery)
        )
        let prefix = RequestPattern(url: URL(string: "https://example.com/private/")!, matchType: .prefix)
        XCTAssertTrue(prefix.matches(URLRequest(url: URL(string: "https://example.com/private/child?q=1")!)))
        XCTAssertFalse(prefix.matches(URLRequest(url: URL(string: "https://example.com/privateer")!)))
        XCTAssertEqual(
            RequestPattern(fileExtensions: ["png", ".JPG"]),
            RequestPattern(fileExtensions: ["jpg", ".PNG", "png"])
        )
    }

    func testMissingMethodMatchesGETAndPatternReplacementUsesIdentity() {
        let url = URL(string: "https://example.com/item")!
        let registry = MockRegistry(mode: .optin)
        registry.register(Mock(url: url, statusCode: 201, data: [.get: Data("first".utf8)]))
        registry.register(Mock(url: url, statusCode: 202, data: [.get: Data("second".utf8)]))
        let request = URLRequest(url: url)
        XCTAssertTrue(registry.shouldHandle(request))
        XCTAssertEqual(registry.decision(for: request)?.mock.statusCode, 202)
    }

    func testRegistriesKeepConfigurationAndMocksIsolated() {
        let url = URL(string: "https://example.com/isolation")!
        let first = MockRegistry(mode: .optin, httpVersion: .http1_0)
        let second = MockRegistry(mode: .optin, httpVersion: .http2_0)
        first.register(Mock(url: url, statusCode: 201, data: [.get: Data()]))
        second.register(Mock(url: url, statusCode: 202, data: [.get: Data()]))
        let request = URLRequest(url: url)
        XCTAssertEqual(first.decision(for: request)?.mock.statusCode, 201)
        XCTAssertEqual(first.decision(for: request)?.httpVersion, .http1_0)
        XCTAssertEqual(second.decision(for: request)?.mock.statusCode, 202)
        first.removeAll()
        XCTAssertFalse(first.shouldHandle(request))
        XCTAssertTrue(second.shouldHandle(request))
    }

    func testScopedRequestIsACopyWithInvisiblePersistentRouting() {
        let registry = MockRegistry(mode: .optin)
        let original = URLRequest(url: URL(string: "https://example.com/scoped")!)
        let scoped = registry.scopedRequest(from: original)
        XCTAssertNil(MockRegistry.registry(for: original))
        XCTAssertTrue(MockRegistry.registry(for: scoped) === registry)
        XCTAssertEqual(scoped.url, original.url)
        XCTAssertEqual(scoped.allHTTPHeaderFields, original.allHTTPHeaderFields)
        XCTAssertTrue(MockRegistry.registry(for: scoped as NSURLRequest as URLRequest) === registry)
        XCTAssertEqual(MockingURLProtocol.canonicalRequest(for: scoped).url, original.url)
    }

    func testScopedRoutingSurvivesURLSessionAndKeepsConcurrentRegistriesIsolated() {
        let url = URL(string: "https://example.com/session-scope")!
        let first = MockRegistry(mode: .optin)
        let second = MockRegistry(mode: .optin)
        first.register(Mock(url: url, statusCode: 200, data: [.get: Data("first".utf8)]))
        second.register(Mock(url: url, statusCode: 200, data: [.get: Data("second".utf8)]))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let done = expectation(description: "both isolated requests")
        done.expectedFulfillmentCount = 2
        session.dataTask(with: first.scopedRequest(from: URLRequest(url: url))) { data, _, error in
            XCTAssertNil(error); XCTAssertEqual(data, Data("first".utf8)); done.fulfill()
        }.resume()
        session.dataTask(with: second.scopedRequest(from: URLRequest(url: url))) { data, _, error in
            XCTAssertNil(error); XCTAssertEqual(data, Data("second".utf8)); done.fulfill()
        }.resume()
        wait(for: [done], timeout: 2)
    }
}
