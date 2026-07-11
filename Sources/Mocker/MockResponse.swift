import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Content-Type HTTP header value.
public struct HTTPContentType: RawRepresentable, Hashable, Sendable {
    /// The complete header value.
    public let rawValue: String
    /// Creates a content type from its complete header value.
    public init(rawValue: String) { self.rawValue = rawValue }
    /// JSON encoded as UTF-8.
    public static let json = Self(rawValue: "application/json; charset=utf-8")
    /// HTML encoded as UTF-8.
    public static let html = Self(rawValue: "text/html; charset=utf-8")
    /// A PNG image.
    public static let png = Self(rawValue: "image/png")
    /// A PDF document.
    public static let pdf = Self(rawValue: "application/pdf")
    /// An MP4 video.
    public static let mp4 = Self(rawValue: "video/mp4")
    /// A ZIP archive.
    public static let zip = Self(rawValue: "application/zip")
}

/// A normal mocked HTTP response.
public struct MockResponse: Sendable {
    /// The response status code.
    public let statusCode: Int
    /// The response headers, including an optional content type.
    public let headers: [String: String]
    /// The response body.
    public let body: Data
    /// An optional delivery delay.
    public let delay: Duration?
    /// The URL loading cache policy.
    public let cachePolicy: URLCache.StoragePolicy

    /// Creates a validated HTTP response.
    /// - Throws: `MockConfigurationError.invalidStatusCode` outside `100...599`.
    public init(statusCode: Int, contentType: HTTPContentType? = nil, headers: [String: String] = [:], body: Data = Data(), delay: Duration? = nil, cachePolicy: URLCache.StoragePolicy = .notAllowed) throws {
        guard (100...599).contains(statusCode) else { throw MockConfigurationError.invalidStatusCode(statusCode) }
        var headers = headers
        if let contentType { headers["Content-Type"] = contentType.rawValue }
        self.statusCode = statusCode; self.headers = headers; self.body = body; self.delay = delay; self.cachePolicy = cachePolicy
    }
}

/// A stable, sendable failure delivered to URL loading as an `NSError`.
public struct MockFailure: Error, Sendable, Equatable {
    /// The failure domain.
    public let domain: String
    /// The failure code.
    public let code: Int
    /// A human-readable description.
    public let description: String
    /// Creates a stable mocked failure.
    public init(domain: String, code: Int, description: String) { self.domain = domain; self.code = code; self.description = description }
    var error: NSError { NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: description]) }
}

/// A method-specific mocked terminal result.
public enum MockResponseResult: Sendable {
    /// Delivers a normal response.
    case response(MockResponse)
    /// Delivers a redirect.
    case redirect(to: URL, statusCode: Int, headers: [String: String])
    /// Delivers a stable failure.
    case failure(MockFailure)
}
