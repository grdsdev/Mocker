//
//  MockingURLProtocol.swift
//  Rabbit
//
//  Created by Antoine van der Lee on 04/05/2017.
//  Copyright © 2017 WeTransfer. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The protocol which can be used to send Mocked data back. Use the `Mocker` to register `Mock` data
open class MockingURLProtocol: URLProtocol {

    private enum LifecycleState {
        case pending
        case finished
        case cancelled
    }

    enum Error: Swift.Error, LocalizedError, CustomDebugStringConvertible {
        case missingMockedData(url: String)
        case explicitMockFailure(url: String)

        var errorDescription: String? {
            return debugDescription
        }

        var debugDescription: String {
            switch self {
            case .missingMockedData(let url):
                return "Missing mock for URL: \(url)"
            case .explicitMockFailure(url: let url):
                return "Induced error for URL: \(url)"
            }
        }
    }

    private var responseWorkItem: DispatchWorkItem?
    private let lifecycleLock = NSLock()
    private var lifecycleState: LifecycleState = .pending
    private var observedRequest: MockedRequest?
    private weak var selectedRegistry: MockRegistry?

    /// Returns Mocked data based on the mocks register in the `Mocker`. Will end up in an error when no Mock data is found for the request.
    override public func startLoading() {
        lifecycleLock.lock()
        lifecycleState = .pending
        lifecycleLock.unlock()

        guard
            let decision = Mocker.decision(for: request),
            let mock = Optional(decision.mock),
            let requestURL = request.url,
            let response = HTTPURLResponse(url: requestURL, statusCode: mock.statusCode, httpVersion: decision.httpVersion.rawValue, headerFields: mock.headers),
            let data = mock.data(for: request)
        else {
            guard claimFinished() else { return }
            print("\n\n 🚨 No mocked data found for url \(String(describing: request.url?.absoluteString)) method \(String(describing: request.httpMethod)). Did you forget to use `register()`? 🚨 \n\n")
            client?.urlProtocol(self, didFailWithError: Error.missingMockedData(url: String(describing: request.url?.absoluteString)))
            return
        }


        let registry = Mocker.registry(for: request)
        let bodyData = request.httpBodyStreamData() ?? request.httpBody
        let snapshot = registry?.snapshot(for: request, pattern: decision.pattern, id: UUID(), bodyData: bodyData)
        selectedRegistry = registry
        observedRequest = snapshot
        if let snapshot { registry?.record(.started(snapshot)) }

        if let onRequestHandler = mock.compatibilityOnRequestHandler {
            onRequestHandler.handleRequest(request, body: bodyData)
        }
        mock.onRequestExpectation?.fulfill()

        guard let delay = mock.delay else {
            guard claimFinished() else { return }
            finishRequest(for: mock, data: data, response: response)
            return
        }

        let workItem = DispatchWorkItem(block: { [weak self] in
            guard let self = self else { return }
            guard self.claimFinished() else { return }
            self.finishRequest(for: mock, data: data, response: response)
        })

        lifecycleLock.lock()
        guard lifecycleState == .pending else {
            lifecycleLock.unlock()
            return
        }
        responseWorkItem = workItem
        lifecycleLock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func finishRequest(for mock: Mock, data: Data, response: HTTPURLResponse) {
        let outcome: MockedRequestOutcome
        if let redirectLocation = data.redirectLocation {
            let redirected = URLRequest(url: redirectLocation)
            let scoped = Mocker.registry(for: request)?.scopedRequest(from: redirected) ?? redirected
            self.client?.urlProtocol(self, wasRedirectedTo: scoped, redirectResponse: response)
            outcome = .redirected(to: redirectLocation)
        } else if let requestError = mock.requestError {
            self.client?.urlProtocol(self, didFailWithError: requestError)
            outcome = .failed(description: String(describing: requestError))
        } else {
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: mock.cacheStoragePolicy)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
            outcome = .response(statusCode: mock.statusCode)
        }

        if let observedRequest { selectedRegistry?.record(.completed(observedRequest, outcome: outcome)) }
        mock.compatibilityCompletion?()
        mock.onCompletedExpectation?.fulfill()
    }

    override public func stopLoading() {
        lifecycleLock.lock()
        guard lifecycleState == .pending else {
            lifecycleLock.unlock()
            return
        }
        lifecycleState = .cancelled
        let workItem = responseWorkItem
        let observedRequest = self.observedRequest
        let registry = selectedRegistry
        lifecycleLock.unlock()
        workItem?.cancel()
        if let observedRequest { registry?.record(.completed(observedRequest, outcome: .cancelled)) }
    }

    private func claimFinished() -> Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard lifecycleState == .pending else { return false }
        lifecycleState = .finished
        responseWorkItem = nil
        return true
    }

    /// Simply sends back the passed request. Implementation is needed for a valid inheritance of URLProtocol.
    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    /// Overrides needed to define a valid inheritance of URLProtocol.
    override public class func canInit(with request: URLRequest) -> Bool {
        return Mocker.shouldHandle(request)
    }
}

private extension Data {
    /// Returns the redirect location from the raw HTTP response if exists.
    var redirectLocation: URL? {
        let locationComponent = String(data: self, encoding: String.Encoding.utf8)?.components(separatedBy: "\n").first(where: { (value) -> Bool in
            return value.contains("Location:")
        })

        guard let redirectLocationString = locationComponent?.components(separatedBy: "Location:").last, let redirectLocation = URL(string: redirectLocationString.trimmingCharacters(in: NSCharacterSet.whitespaces)) else {
            return nil
        }
        return redirectLocation
    }
}
