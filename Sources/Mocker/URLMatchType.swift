//
//  URLMatchType.swift
//  Mocker
//
//  Created by Brent Whitman on 2024-04-18.
//

import Foundation

/// How to check if one URL matches another.
public enum URLMatchType: Sendable {
    /// Matches the full URL, including the query
    case full
    /// Matches the URL excluding the query
    case ignoreQuery
    /// Matches if the URL begins with the prefix
    case prefix
}

extension URL {
    /// Returns the URL string after removing only its query and fragment.
    var baseString: String? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.fragment = nil
        return components.string
    }
    
    /// Checks if  this URL matches the passed URL using the provided match type.
    ///
    /// - Parameter url: The URL to check for a match.
    /// - Parameter matchType: The approach that will be used to determine whether this URL match the provided URL. Defaults to `full`.
    /// - Returns: `true` if the URL matches based on the match type; `false` otherwise.
    func matches(_ otherURL: URL?, matchType: URLMatchType = .full) -> Bool {
        guard let otherURL else { return false }
        
        switch matchType {
        case .full:
            return absoluteString == otherURL.absoluteString
        case .ignoreQuery:
            return baseString == otherURL.baseString
        case .prefix:
            guard
                let candidate = URLComponents(url: self, resolvingAgainstBaseURL: false),
                let prefix = URLComponents(url: otherURL, resolvingAgainstBaseURL: false),
                candidate.scheme?.lowercased() == prefix.scheme?.lowercased(),
                candidate.host?.lowercased() == prefix.host?.lowercased(),
                candidate.user == prefix.user,
                candidate.password == prefix.password,
                effectivePort(of: candidate) == effectivePort(of: prefix)
            else { return false }

            let prefixPath = normalizedPath(prefix.percentEncodedPath)
            let candidatePath = normalizedPath(candidate.percentEncodedPath)
            return candidatePath == prefixPath || candidatePath.hasPrefix(prefixPath + "/")
        }
    }

    private func effectivePort(of components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private func normalizedPath(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
