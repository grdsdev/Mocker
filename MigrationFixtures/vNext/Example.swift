import Foundation
import Mocker

func makeRegistry(endpoint: URL, payload: Data) throws -> MockRegistry {
    let pattern = try RequestPattern(url: endpoint, methods: [.post])
    let response = try MockResponse(statusCode: 201, contentType: .json, body: payload)
    let mock = try Mock(matching: pattern, responses: [.post: .response(response)])
    let registry = try MockRegistry(mode: .optIn)
    registry.register(mock)
    return registry
}
