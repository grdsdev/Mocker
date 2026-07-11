import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A URL loading protocol that serves responses selected by a `MockRegistry`.
open class MockingURLProtocol: URLProtocol {
    private enum LifecycleState { case pending, finished, cancelled }
    private var responseWorkItem: DispatchWorkItem?
    private let lifecycleLock = NSLock()
    private var lifecycleState: LifecycleState = .pending
    private var observedRequest: MockedRequest?
    private weak var selectedRegistry: MockRegistry?
    private var selectedHTTPVersion: Mocker.HTTPVersion?

    /// Starts loading and emits one start plus one terminal registry event for selected requests.
    override public func startLoading() {
        guard let decision = Mocker.decision(for: request),
              let method = Mock.HTTPMethod(rawValue: request.httpMethod ?? "GET"),
              let result = decision.mock.responses[method],
              let registry = Mocker.registry(for: request),
              let snapshot = registry.snapshot(for: request, pattern: decision.pattern, id: UUID(), bodyResult: request.bodyDataForObservation())
        else { failMissingMock(); return }

        selectedRegistry = registry; observedRequest = snapshot
        selectedHTTPVersion = decision.httpVersion
        registry.record(.started(snapshot))

        if case .response(let response) = result, let delay = response.delay {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.claimFinished() else { return }
                self.finish(result)
            }
            lifecycleLock.lock(); responseWorkItem = workItem; lifecycleLock.unlock()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay.nanoseconds, execute: workItem)
        } else if claimFinished() {
            finish(result)
        }
    }

    private func finish(_ result: MockResponseResult) {
        guard let requestURL = request.url else { return }
        let outcome: MockedRequestOutcome
        switch result {
        case .response(let configured):
            guard let response = HTTPURLResponse(url: requestURL, statusCode: configured.statusCode, httpVersion: selectedHTTPVersion?.rawValue, headerFields: configured.headers) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: configured.cachePolicy)
            client?.urlProtocol(self, didLoad: configured.body)
            client?.urlProtocolDidFinishLoading(self)
            outcome = .response(statusCode: configured.statusCode)
        case .redirect(let destination, let statusCode, let headers):
            guard let response = HTTPURLResponse(url: requestURL, statusCode: statusCode, httpVersion: selectedHTTPVersion?.rawValue, headerFields: headers) else { return }
            let redirected = URLRequest(url: destination)
            let scoped = selectedRegistry?.scopedRequest(from: redirected) ?? redirected
            client?.urlProtocol(self, wasRedirectedTo: scoped, redirectResponse: response)
            outcome = .redirected(to: destination)
        case .failure(let failure):
            client?.urlProtocol(self, didFailWithError: failure.error)
            outcome = .failed(description: failure.description)
        }
        if let observedRequest { selectedRegistry?.record(.completed(observedRequest, outcome: outcome)) }
    }

    /// Cancels loading and records cancellation exactly once.
    override public func stopLoading() {
        lifecycleLock.lock()
        guard lifecycleState == .pending else { lifecycleLock.unlock(); return }
        lifecycleState = .cancelled
        let workItem = responseWorkItem, snapshot = observedRequest, registry = selectedRegistry
        lifecycleLock.unlock()
        workItem?.cancel()
        if let snapshot { registry?.record(.completed(snapshot, outcome: .cancelled)) }
    }

    private func failMissingMock() {
        guard claimFinished() else { return }
        let description = "Missing mock for URL: \(String(describing: request.url))"
        client?.urlProtocol(self, didFailWithError: NSError(domain: "Mocker", code: 1, userInfo: [NSLocalizedDescriptionKey: description]))
    }

    private func claimFinished() -> Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard lifecycleState == .pending else { return false }
        lifecycleState = .finished; responseWorkItem = nil; return true
    }

    /// Returns the request unchanged, including invisible registry routing properties.
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    /// Returns whether the request's selected registry should intercept it.
    override public class func canInit(with request: URLRequest) -> Bool { Mocker.shouldHandle(request) }
}

private extension Duration {
    var nanoseconds: DispatchTimeInterval {
        let parts = components
        let value = max(0, parts.seconds) * 1_000_000_000 + max(0, parts.attoseconds / 1_000_000_000)
        return .nanoseconds(value > Int64(Int.max) ? Int.max : Int(value))
    }
}
