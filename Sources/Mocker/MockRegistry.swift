import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RequestDecision {
    let mock: Mock
    let pattern: RequestPattern
    let httpVersion: Mocker.HTTPVersion
}

/// An isolated, synchronously accessed collection of mocks and request-handling configuration.
///
/// The unchecked sendability is protected by the single `NSLock` guarding all mutable state.
public final class MockRegistry: @unchecked Sendable {
    private struct Entry { let pattern: RequestPattern; var mock: Mock }
    private struct State {
        var entries: [Entry] = []
        var ignored: Set<RequestPattern> = []
        var mode: Mocker.Mode
        var httpVersion: Mocker.HTTPVersion
        var events: [MockRegistryEvent] = []
        var observers: [UUID: MockRegistryObservation.Slot] = [:]
    }
    private final class WeakBox { weak var value: MockRegistry?; init(_ value: MockRegistry) { self.value = value } }
    private final class Directory: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: WeakBox] = [:]
    }

    private static let propertyKey = "dev.grds.mocker.registry.v2.8E392B64"
    private static let directory = Directory()

    private let identifier = UUID().uuidString
    private let historyCapacity: Int
    private let bodyCapturePolicy: RequestBodyCapturePolicy
    private let lock = NSLock()
    private var state: State

    /// Creates an independent registry.
    public init(mode: Mocker.Mode = .optOut, httpVersion: Mocker.HTTPVersion = .http1_1, historyCapacity: Int = 100, bodyCapturePolicy: RequestBodyCapturePolicy = .none) throws {
        guard historyCapacity >= 0 else { throw MockConfigurationError.invalidHistoryCapacity(historyCapacity) }
        if case .upToBytes(let limit) = bodyCapturePolicy, limit < 0 { throw MockConfigurationError.invalidBodyCaptureLimit(limit) }
        self.historyCapacity = historyCapacity
        self.bodyCapturePolicy = bodyCapturePolicy
        state = State(mode: mode, httpVersion: httpVersion)
        _ = URLProtocol.registerClass(MockingURLProtocol.self)
    }

    /// Controls how requests without a registered mock are handled.
    public var mode: Mocker.Mode { get { withState { $0.mode } } set { withState { $0.mode = newValue } } }
    /// Controls the HTTP version used when constructing responses.
    public var httpVersion: Mocker.HTTPVersion { get { withState { $0.httpVersion } } set { withState { $0.httpVersion = newValue } } }

    /// Registers a mock using the matching fields from the mock.
    public func register(_ mock: Mock) {
        let pattern = mock.pattern
        withState { state in
            if let index = state.entries.firstIndex(where: { $0.pattern == pattern }) { state.entries[index].mock = mock }
            else { state.entries.append(Entry(pattern: pattern, mock: mock)) }
        }
    }

    /// Adds an idempotent ignored request pattern.
    public func ignore(_ pattern: RequestPattern) { withState { _ = $0.ignored.insert(pattern) } }

    /// Removes all mocks and ignored patterns without changing mode or HTTP version.
    public func removeAll() { withState { $0.entries.removeAll(); $0.ignored.removeAll() } }

    /// A deterministic copy of recorded events. This operation is `O(n)`.
    public var events: [MockRegistryEvent] { withState { $0.events } }

    /// Returns recorded events selected by a pattern. This operation is `O(n)`.
    public func events(matching pattern: RequestPattern) -> [MockRegistryEvent] {
        withState { $0.events.filter { pattern.matches($0.request.urlRequest) } }
    }

    /// Removes all recorded events without changing mocks or configuration.
    public func removeAllEvents() { withState { $0.events.removeAll() } }

    /// Observes future events immediately on the thread that records them.
    public func observeEvents(matching pattern: RequestPattern? = nil, using observer: @escaping @Sendable (MockRegistryEvent) -> Void) -> MockRegistryObservation {
        let id = UUID(), slot = MockRegistryObservation.Slot(pattern: pattern, observer: observer)
        withState { $0.observers[id] = slot }
        return MockRegistryObservation(slot: slot) { [weak self] in self?.withState { $0.observers[id] = nil } }
    }

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
            case .optOut: return !state.ignored.contains(where: { $0.matches(request) })
            case .optIn: return Self.find(request, in: state.entries) != nil
            }
        }
    }

    func decision(for request: URLRequest) -> RequestDecision? {
        withState { state in Self.findEntry(request, in: state.entries).map { RequestDecision(mock: $0.mock, pattern: $0.pattern, httpVersion: state.httpVersion) } }
    }

    func snapshot(for request: URLRequest, pattern: RequestPattern, id: UUID, bodyResult: Result<Data?, RequestBodyError>) -> MockedRequest? {
        guard let url = request.url, let method = Mock.HTTPMethod(rawValue: request.httpMethod ?? "GET") else { return nil }
        let source: Data?
        let bodyError: RequestBodyError?
        switch bodyResult { case .success(let data): source = data; bodyError = nil; case .failure(let error): source = nil; bodyError = error }
        let capture: (Data?, Bool)
        switch bodyCapturePolicy {
        case .none: capture = (nil, false)
        case .complete: capture = (source, false)
        case .upToBytes(let limit):
            capture = source.map { (Data($0.prefix(limit)), $0.count > limit) } ?? (nil, false)
        }
        return MockedRequest(id: id, url: url, method: method, headers: request.allHTTPHeaderFields ?? [:], body: capture.0, isBodyTruncated: capture.1, bodyError: bodyError, pattern: pattern)
    }

    func record(_ event: MockRegistryEvent) {
        let observers: [MockRegistryObservation.Slot] = withState { state in
            if historyCapacity > 0 {
                state.events.append(event)
                while Set(state.events.map(\.request.id)).count > historyCapacity {
                    let completedIDs = Set(state.events.compactMap { event -> UUID? in
                        if case .completed(let request, _) = event { return request.id }
                        return nil
                    })
                    guard let oldestCompleteID = state.events.first(where: { completedIDs.contains($0.request.id) })?.request.id else { break }
                    state.events.removeAll { $0.request.id == oldestCompleteID }
                }
            }
            return state.observers.values.filter { slot in
                slot.pattern.map { $0.matches(event.request.urlRequest) } ?? true
            }
        }
        observers.forEach { $0.invoke(event) }
    }

    static func registry(for request: URLRequest) -> MockRegistry? {
        guard let identifier = tag(in: request) else { return nil }
        directory.lock.lock(); defer { directory.lock.unlock() }
        return directory.entries[identifier]?.value
    }

    static func hasTag(_ request: URLRequest) -> Bool { tag(in: request) != nil }
    private static func tag(in request: URLRequest) -> String? { URLProtocol.property(forKey: propertyKey, in: request) as? String }

    private static func find(_ request: URLRequest, in entries: [Entry]) -> Mock? {
        findEntry(request, in: entries)?.mock
    }

    private static func findEntry(_ request: URLRequest, in entries: [Entry]) -> Entry? {
        entries.reversed().first(where: { !$0.pattern.isExtension && $0.pattern.matches(request) })
            ?? entries.reversed().first(where: { $0.pattern.isExtension && $0.pattern.matches(request) })
    }

    private func withState<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        lock.lock(); defer { lock.unlock() }; return try body(&state)
    }
}

private extension MockedRequest {
    var urlRequest: URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method.rawValue; return request
    }
}
