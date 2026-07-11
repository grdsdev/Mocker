# Major-version migration guide

This release intentionally removes the prior compatibility surface. The last
Swift 5-compatible and pre-cleanup checkpoints are documented in
[SWIFT_6_MIGRATION.md](SWIFT_6_MIGRATION.md).

| Previous API | Replacement | Behavioral note |
|---|---|---|
| `Mode.optin` / `.optout` | `.optIn` / `.optOut` | Swift word-boundary casing |
| `HTTPVersion.http2_0` | `.http2` | HTTP/1.0 and HTTP/1.1 remain distinct |
| `Mock.DataType` | `HTTPContentType` | Stores the actual header value |
| URL/request/extension `Mock` initializers | `RequestPattern` + `MockResponse` + `Mock.init(matching:responses:)` | Construction throws typed errors |
| `ignoreQuery: true` | `RequestPattern(url:matchType: .ignoreQuery)` | Matching identity is explicit |
| `requestError` | `MockResponseResult.failure(MockFailure)` | Failure values are stable and sendable |
| Redirect text in response data | `MockResponseResult.redirect` | Redirect intent is explicit |
| `completion`, `onRequest`, `onRequestHandler` | `MockRegistry.events` or `observeEvents` | Observation is registry-scoped |
| `expectationForRequestingMock` / completing helper | Import `MockerXCTest`; use `expectation(in:for:event:)` | No mock mutation |
| Optional callback body decoding | `MockedRequest.decodeBody(as:)` | Absence, truncation, and decoding failure are distinct |
| `Mock: Equatable` | `RequestPattern: Equatable` | Pattern identity controls replacement |

## Construction

Before:

```swift
Mock(url: endpoint, contentType: .json, statusCode: 201, data: [.post: payload]).register()
```

After:

```swift
let pattern = try RequestPattern(url: endpoint, methods: [.post])
let response = try MockResponse(statusCode: 201, contentType: .json, body: payload)
let mock = try Mock(matching: pattern, responses: [.post: .response(response)])
registry.register(mock)
```

For extension matching, create `try RequestPattern(fileExtensions:methods:)`.
Invalid empty extensions, empty methods, status codes, response maps, body-capture
limits, and history capacities now produce `MockConfigurationError` where callers
can recover.

## Testing frameworks

The core target imports neither XCTest nor Swift Testing. Add `MockerXCTest` or
`MockerTesting` as an explicit product dependency. XCTest expectations and async
waits observe future events; synchronous history queries inspect existing events.

## Shared and isolated registries

`Mocker` remains convenient for serialized tests, but its state is process-wide.
Create a `MockRegistry`, register definitions on it, and pass a
`scopedRequest(from:)` copy for tests that execute concurrently.
