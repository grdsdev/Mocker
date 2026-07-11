import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RequestDecision {
    let mock: Mock
    let httpVersion: Mocker.HTTPVersion
}

/// An isolated, synchronously accessed collection of mocks and request-handling configuration.
public final class MockRegistry: @unchecked Sendable {
    private struct Entry { let pattern: RequestPattern; var mock: Mock }
    private struct State {
        var entries: [Entry] = []
        var ignored: Set<RequestPattern> = []
        var mode: Mocker.Mode
        var httpVersion: Mocker.HTTPVersion
    }
    private final class WeakBox { weak var value: MockRegistry?; init(_ value: MockRegistry) { self.value = value } }
    private final class Directory: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: WeakBox] = [:]
    }

    private static let propertyKey = "dev.grds.mocker.registry.v2.8E392B64"
    private static let directory = Directory()

    private let identifier = UUID().uuidString
    private let lock = NSLock()
    private var state: State

    /// Creates an independent registry.
    public init(mode: Mocker.Mode = .optout, httpVersion: Mocker.HTTPVersion = .http1_1) {
        state = State(mode: mode, httpVersion: httpVersion)
        _ = URLProtocol.registerClass(MockingURLProtocol.self)
    }

    /// Controls how requests without a registered mock are handled.
    public var mode: Mocker.Mode { get { withState { $0.mode } } set { withState { $0.mode = newValue } } }
    /// Controls the HTTP version used when constructing responses.
    public var httpVersion: Mocker.HTTPVersion { get { withState { $0.httpVersion } } set { withState { $0.httpVersion = newValue } } }

    /// Registers a mock using the matching fields from the mock.
    public func register(_ mock: Mock) { register(mock, matching: mock.requestPattern) }

    /// Registers a mock with an explicit pattern, replacing an equal pattern without changing its position.
    public func register(_ mock: Mock, matching pattern: RequestPattern) {
        precondition(pattern.constrainedMethods == mock.responseMethods, "Pattern methods must equal the mock response methods")
        withState { state in
            if let index = state.entries.firstIndex(where: { $0.pattern == pattern }) { state.entries[index].mock = mock }
            else { state.entries.append(Entry(pattern: pattern, mock: mock)) }
        }
    }

    /// Adds an idempotent ignored request pattern.
    public func ignore(_ pattern: RequestPattern) { withState { _ = $0.ignored.insert(pattern) } }

    /// Removes all mocks and ignored patterns without changing mode or HTTP version.
    public func removeAll() { withState { $0.entries.removeAll(); $0.ignored.removeAll() } }

    /// Returns a publicly identical request copy routed to this registry.
    public func scopedRequest(from request: URLRequest) -> URLRequest {
        Self.directory.lock.lock()
        Self.directory.entries = Self.directory.entries.filter { $0.value.value != nil }
        Self.directory.entries[identifier] = WeakBox(self)
        Self.directory.lock.unlock()
        let mutable = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(identifier, forKey: Self.propertyKey, in: mutable)
        return mutable as URLRequest
    }

    func shouldHandle(_ request: URLRequest) -> Bool {
        withState { state in
            switch state.mode {
            case .optout: return !state.ignored.contains(where: { $0.matches(request) })
            case .optin: return Self.find(request, in: state.entries) != nil
            }
        }
    }

    func decision(for request: URLRequest) -> RequestDecision? {
        withState { state in Self.find(request, in: state.entries).map { RequestDecision(mock: $0, httpVersion: state.httpVersion) } }
    }

    static func registry(for request: URLRequest) -> MockRegistry? {
        guard let identifier = tag(in: request) else { return nil }
        directory.lock.lock(); defer { directory.lock.unlock() }
        return directory.entries[identifier]?.value
    }

    static func hasTag(_ request: URLRequest) -> Bool { tag(in: request) != nil }
    private static func tag(in request: URLRequest) -> String? { URLProtocol.property(forKey: propertyKey, in: request) as? String }

    private static func find(_ request: URLRequest, in entries: [Entry]) -> Mock? {
        entries.reversed().first(where: { !$0.pattern.isExtension && $0.pattern.matches(request) })?.mock
            ?? entries.reversed().first(where: { $0.pattern.isExtension && $0.pattern.matches(request) })?.mock
    }

    private func withState<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock(); defer { lock.unlock() }; return try body(&state)
    }
}
