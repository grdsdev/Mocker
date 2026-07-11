import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Errors produced while reading or decoding an observed request body.
public enum RequestBodyError: Error, Sendable, Equatable {
    /// The request has no captured body.
    case absent
    /// Reading the body stream failed.
    case streamReadFailed
    /// The stream ended without reaching its end state.
    case incompleteStream
    /// The configured capture limit truncated the body.
    case truncated
    /// Decoding failed with a stable diagnostic.
    case decodingFailed(description: String)
}

public extension MockedRequest {
    /// Decodes the captured complete body as JSON.
    /// - Throws: `RequestBodyError` when the body is absent, truncated, or malformed.
    func decodeBody<Value: Decodable & Sendable>(as type: Value.Type) throws -> Value {
        if let bodyError { throw bodyError }
        guard let body else { throw RequestBodyError.absent }
        guard !isBodyTruncated else { throw RequestBodyError.truncated }
        do { return try JSONDecoder().decode(type, from: body) }
        catch { throw RequestBodyError.decodingFailed(description: String(describing: error)) }
    }
}

extension URLRequest {
    func bodyDataForObservation() -> Result<Data?, RequestBodyError> {
        guard let stream = httpBodyStream else { return .success(httpBody) }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 { data.append(contentsOf: buffer.prefix(count)) }
            else if count == 0 { return stream.streamStatus == .atEnd ? .success(data) : .failure(.incompleteStream) }
            else { return .failure(.streamReadFailed) }
        }
    }
}
