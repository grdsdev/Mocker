import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An immutable description of the requests matched by a registry entry.
public struct RequestPattern: Hashable, Sendable {
    private enum Kind: Hashable, Sendable {
        case full(String)
        case ignoreQuery(String)
        case prefix(origin: String, path: String)
        case fileExtensions(Set<String>)
    }

    private let kind: Kind
    private let methods: Set<Mock.HTTPMethod>?

    /// Creates a URL pattern. Empty paths are normalized to `/`; relative and file URLs retain their structured components.
    /// - Parameters:
    ///   - url: The absolute HTTP or HTTPS URL that defines the pattern.
    ///   - methods: The accepted methods, or `nil` to accept any method.
    ///   - matchType: The URL matching behavior.
    public init(url: URL, methods: Set<Mock.HTTPMethod>? = nil, matchType: URLMatchType = .full) {
        Self.validate(methods)
        let components = Self.components(for: url)
        self.methods = methods
        switch matchType {
        case .full:
            kind = .full(Self.canonicalURL(components, includeQueryAndFragment: true))
        case .ignoreQuery:
            kind = .ignoreQuery(Self.canonicalURL(components, includeQueryAndFragment: false))
        case .prefix:
            kind = .prefix(origin: Self.origin(components), path: Self.prefixPath(components.percentEncodedPath))
        }
    }

    /// Creates a case-insensitive file-extension pattern.
    /// - Parameters:
    ///   - fileExtensions: Extensions to accept; one leading dot is ignored.
    ///   - methods: The accepted methods, or `nil` to accept any method.
    public init(fileExtensions: Set<String>, methods: Set<Mock.HTTPMethod>? = nil) {
        Self.validate(methods)
        let normalized = Set(fileExtensions.map { value in
            (value.hasPrefix(".") ? String(value.dropFirst()) : value).lowercased()
        })
        precondition(!normalized.isEmpty && !normalized.contains(""), "At least one non-empty file extension is required")
        kind = .fileExtensions(normalized)
        self.methods = methods
    }

    /// Returns whether the complete request belongs to this pattern.
    public func matches(_ request: URLRequest) -> Bool {
        let method = Mock.HTTPMethod(rawValue: request.httpMethod ?? Mock.HTTPMethod.get.rawValue)
        if let methods, method.map({ methods.contains($0) }) != true { return false }
        guard let url = request.url else { return false }
        switch kind {
        case .full(let identity):
            return Self.identity(for: url, includeQueryAndFragment: true) == identity
        case .ignoreQuery(let identity):
            return Self.identity(for: url, includeQueryAndFragment: false) == identity
        case .prefix(let origin, let path):
            guard let components = Self.optionalComponents(for: url), Self.origin(components) == origin else { return false }
            let candidate = Self.prefixPath(components.percentEncodedPath)
            return candidate == path || (path == "/" ? candidate.hasPrefix("/") : candidate.hasPrefix(path + "/"))
        case .fileExtensions(let extensions):
            return extensions.contains(url.pathExtension.lowercased())
        }
    }

    var constrainedMethods: Set<Mock.HTTPMethod>? { methods }
    var isExtension: Bool { if case .fileExtensions = kind { return true }; return false }

    private static func validate(_ methods: Set<Mock.HTTPMethod>?) {
        if let methods { precondition(!methods.isEmpty, "At least one HTTP method is required") }
    }

    private static func components(for url: URL) -> URLComponents {
        guard let result = optionalComponents(for: url) else {
            preconditionFailure("The URL cannot be represented by URLComponents")
        }
        return result
    }

    private static func optionalComponents(for url: URL) -> URLComponents? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.percentEncodedPath.isEmpty { components.percentEncodedPath = "/" }
        return components
    }

    private static func identity(for url: URL, includeQueryAndFragment: Bool) -> String? {
        optionalComponents(for: url).map { canonicalURL($0, includeQueryAndFragment: includeQueryAndFragment) }
    }

    private static func canonicalURL(_ input: URLComponents, includeQueryAndFragment: Bool) -> String {
        var components = input
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) { components.port = nil }
        if !includeQueryAndFragment { components.percentEncodedQuery = nil; components.percentEncodedFragment = nil }
        return components.string!
    }

    private static func origin(_ input: URLComponents) -> String {
        var components = input
        components.percentEncodedPath = ""
        components.percentEncodedQuery = nil
        components.percentEncodedFragment = nil
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) { components.port = nil }
        return components.string!
    }

    private static func prefixPath(_ input: String) -> String {
        let path = input.isEmpty ? "/" : input
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
