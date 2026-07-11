import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A validated mapping from one request pattern to method-specific outcomes.
public struct Mock: Sendable {
    /// HTTP request methods supported by mock definitions.
    public enum HTTPMethod: String, Hashable, Sendable {
        /// OPTIONS.
        case options = "OPTIONS"
        /// GET.
        case get = "GET"
        /// HEAD.
        case head = "HEAD"
        /// POST.
        case post = "POST"
        /// PUT.
        case put = "PUT"
        /// PATCH.
        case patch = "PATCH"
        /// DELETE.
        case delete = "DELETE"
        /// TRACE.
        case trace = "TRACE"
        /// CONNECT.
        case connect = "CONNECT"
    }

    /// The request identity matched by this definition.
    public let pattern: RequestPattern
    /// The terminal outcome configured for each matched method.
    public let responses: [HTTPMethod: MockResponseResult]

    /// Creates a validated mock definition.
    /// - Throws: `MockConfigurationError` when responses are empty or do not exactly match the pattern methods.
    public init(matching pattern: RequestPattern, responses: [HTTPMethod: MockResponseResult]) throws {
        guard !responses.isEmpty else { throw MockConfigurationError.noResponses }
        guard let methods = pattern.constrainedMethods else { throw MockConfigurationError.unconstrainedMockPattern }
        for method in methods where responses[method] == nil { throw MockConfigurationError.methodHasNoResponse(method) }
        if let extra = responses.keys.first(where: { !methods.contains($0) }) { throw MockConfigurationError.patternDoesNotMatchResponse(extra) }
        for result in responses.values {
            if case .redirect(_, let statusCode, _) = result, !(100...599).contains(statusCode) { throw MockConfigurationError.invalidStatusCode(statusCode) }
        }
        self.pattern = pattern
        self.responses = responses
    }
}

/// Errors produced while validating registry and response configuration.
public enum MockConfigurationError: Error, Sendable, Equatable {
    /// A mock has no method responses.
    case noResponses
    /// A pattern has an explicit empty method set.
    case noMethods
    /// An extension pattern has no usable extensions.
    case noFileExtensions
    /// A URL cannot be represented structurally.
    case unsupportedURL(String)
    /// A mock pattern accepts any method and therefore cannot map finite responses exactly.
    case unconstrainedMockPattern
    /// A pattern method has no response.
    case methodHasNoResponse(Mock.HTTPMethod)
    /// A response exists for a method excluded by the pattern.
    case patternDoesNotMatchResponse(Mock.HTTPMethod)
    /// A status code is outside `100...599`.
    case invalidStatusCode(Int)
    /// A body capture limit is negative.
    case invalidBodyCaptureLimit(Int)
    /// A history capacity is negative.
    case invalidHistoryCapacity(Int)
}
