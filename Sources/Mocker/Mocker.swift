import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The process-wide compatibility adapter for registering mocked responses.
public struct Mocker {
    /// HTTP protocol versions available for mocked responses.
    public enum HTTPVersion: String, Sendable {
        /// HTTP/1.0.
        case http1_0 = "HTTP/1.0"
        /// HTTP/1.1.
        case http1_1 = "HTTP/1.1"
        /// HTTP/2.
        case http2 = "HTTP/2.0"
    }
    /// The way unknown requests are handled.
    public enum Mode: Sendable {
        /// Intercept every request except those explicitly ignored.
        case optOut
        /// Intercept only requests having a matching mock.
        case optIn
    }

    static let sharedRegistry: MockRegistry = {
        do { return try MockRegistry() }
        catch { preconditionFailure("Default registry configuration must remain valid: \(error)") }
    }()
    /// The shared registry's handling mode.
    public static var mode: Mode { get { sharedRegistry.mode } set { sharedRegistry.mode = newValue } }
    /// The shared registry's mocked response HTTP version.
    public static var httpVersion: HTTPVersion { get { sharedRegistry.httpVersion } set { sharedRegistry.httpVersion = newValue } }
    /// Registers a mock in the shared registry.
    public static func register(_ mock: Mock) { sharedRegistry.register(mock) }
    /// Ignores a request pattern in the shared registry.
    public static func ignore(_ pattern: RequestPattern) { sharedRegistry.ignore(pattern) }
    /// Returns whether the request should be intercepted by its selected registry.
    public static func shouldHandle(_ request: URLRequest) -> Bool { registry(for: request)?.shouldHandle(request) ?? MockRegistry.hasTag(request) }
    /// Removes mocks and ignored patterns from the shared registry.
    public static func removeAll() { sharedRegistry.removeAll() }
    static func decision(for request: URLRequest) -> RequestDecision? { registry(for: request)?.decision(for: request) }
    static func mock(for request: URLRequest) -> Mock? { decision(for: request)?.mock }
    static func registry(for request: URLRequest) -> MockRegistry? { MockRegistry.hasTag(request) ? MockRegistry.registry(for: request) : sharedRegistry }
}
