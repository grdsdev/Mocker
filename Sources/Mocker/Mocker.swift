//
//  Mocker.swift
//  Rabbit
//
//  Created by Antoine van der Lee on 04/05/2017.
//  Copyright © 2017 WeTransfer. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Can be used for registering Mocked data, returned by the `MockingURLProtocol`.
public struct Mocker {
    private struct IgnoredRule: Equatable, Sendable {
        let urlToIgnore: URL
        let matchType: URLMatchType

        /// Checks if the passed URL should be ignored.
        ///
        /// - Parameter url: The URL to check for.
        /// - Returns: `true` if it should be ignored, `false` if the URL doesn't correspond to ignored rules.
        func shouldIgnore(_ url: URL) -> Bool {
            url.matches(urlToIgnore, matchType: matchType)
        }
    }

    public enum HTTPVersion: String, Sendable {
        case http1_0 = "HTTP/1.0"
        case http1_1 = "HTTP/1.1"
        case http2_0 = "HTTP/2.0"
    }

    /// The way Mocker handles unregistered urls
    public enum Mode: Sendable {
        /// The default mode: only URLs registered with the `ignore(_ url: URL)` method are ignored for mocking.
        ///
        /// - Registered mocked URL: Mocked.
        /// - Registered ignored URL: Ignored by Mocker, default process is applied as if the Mocker doesn't exist.
        /// - Any other URL: Raises an error.
        case optout

        /// Only registered mocked URLs are mocked, all others pass through.
        ///
        /// - Registered mocked URL: Mocked.
        /// - Any other URL: Ignored by Mocker, default process is applied as if the Mocker doesn't exist.
        case optin
    }

    /// The mode defines how unknown URLs are handled. Defaults to `optout` which means requests without a mock will fail.
    private final class Storage: @unchecked Sendable {
        struct State {
            var mocks: [Mock] = []
            var ignoredRules: [IgnoredRule] = []
            var mode: Mode = .optout
            var httpVersion: HTTPVersion = .http1_1
        }

        private let lock = NSLock()
        private var state = State()

        func withState<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
            lock.lock()
            defer { lock.unlock() }
            return try body(&state)
        }
    }

    private static let storage: Storage = {
        _ = URLProtocol.registerClass(MockingURLProtocol.self)
        return Storage()
    }()

    public static var mode: Mode {
        get { storage.withState { $0.mode } }
        set { storage.withState { $0.mode = newValue } }
    }

    public static var httpVersion: HTTPVersion {
        get { storage.withState { $0.httpVersion } }
        set { storage.withState { $0.httpVersion = newValue } }
    }

    /// Register new Mocked data. If a mock for the same URL and HTTPMethod exists, it will be overwritten.
    ///
    /// - Parameter mock: The Mock to be registered for future requests.
    public static func register(_ mock: Mock) {
        storage.withState {
            $0.mocks.removeAll(where: { $0 == mock })
            $0.mocks.append(mock)
        }
    }

    /// Register an URL to ignore for mocking. This will let the URL work as if the Mocker doesn't exist.
    ///
    /// - Parameter url: The URL to ignore.
    /// - Parameter ignoreQuery: If `true`, checking the URL will ignore the query and match only for the scheme, host and path. Defaults to `false`.
    @available(*, deprecated, renamed: "ignore(_:matchType:)")
    public static func ignore(_ url: URL, ignoreQuery: Bool) {
        storage.withState {
            let rule = IgnoredRule(urlToIgnore: url, matchType: ignoreQuery ? .ignoreQuery : .full)
            $0.ignoredRules.append(rule)
        }
    }

    /// Register an URL to ignore for mocking. This will let the URL work as if the Mocker doesn't exist.
    ///
    /// - Parameter url: The URL to ignore.
    /// - Parameter matchType: The approach that will be used to determine whether URLs match the provided URL. Defaults to `full`.
    public static func ignore(_ url: URL, matchType: URLMatchType = .full) {
        storage.withState {
            let rule = IgnoredRule(urlToIgnore: url, matchType: matchType)
            $0.ignoredRules.append(rule)
        }
    }

    /// Checks if the passed URL should be handled by the Mocker. If the URL is registered to be ignored, it will not handle the URL.
    ///
    /// - Parameter url: The URL to check for.
    /// - Returns: `true` if it should be mocked, `false` if the URL is registered as ignored.
    public static func shouldHandle(_ request: URLRequest) -> Bool {
        storage.withState { state in
            switch state.mode {
            case .optout:
                guard let url = request.url else { return false }
                return !state.ignoredRules.contains(where: { $0.shouldIgnore(url) })
            case .optin:
                return findMock(for: request, in: state.mocks) != nil
            }
        }
    }

    /// Removes all registered mocks. Use this method in your tearDown function to make sure a Mock is not used in any other test.
    public static func removeAll() {
        storage.withState {
            $0.mocks.removeAll()
            $0.ignoredRules.removeAll()
        }
    }

    /// Retrieve a Mock for the given request. Matches on `request.url` and `request.httpMethod`.
    ///
    /// - Parameter request: The request to search for a mock.
    /// - Returns: A mock if found, `nil` if there's no mocked data registered for the given request.
    static func mock(for request: URLRequest) -> Mock? {
        storage.withState { findMock(for: request, in: $0.mocks) }
    }

    private static func findMock(for request: URLRequest, in mocks: [Mock]) -> Mock? {
        if let specificMock = mocks.first(where: { $0 == request && $0.fileExtensions == nil }) {
            return specificMock
        }
        return mocks.first(where: { $0 == request })
    }
}
