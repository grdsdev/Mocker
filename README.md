# Mocker

Mocker intercepts `URLSession` requests with deterministic, registry-scoped mock
responses. Version-next requires Swift 6 and the deployment versions listed in
[SWIFT_6_MIGRATION.md](SWIFT_6_MIGRATION.md).

## Usage

```swift
import Mocker

let endpoint = URL(string: "https://example.com/items")!
let pattern = try RequestPattern(url: endpoint, methods: [.post])
let response = try MockResponse(
    statusCode: 201,
    contentType: .json,
    body: payload
)
let mock = try Mock(
    matching: pattern,
    responses: [.post: .response(response)]
)

let registry = try MockRegistry(mode: .optIn)
registry.register(mock)

let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [MockingURLProtocol.self]
let session = URLSession(configuration: configuration)
let request = registry.scopedRequest(from: URLRequest(url: endpoint))
```

Use `.redirect(to:statusCode:headers:)` or `.failure(_:)` response results for
non-body outcomes. Exact, ignore-query, prefix, and extension matching are modeled
by `RequestPattern`.

## Observation and testing

Each registry owns bounded request history and framework-neutral observation.
Import `MockerXCTest` for registry-backed expectations:

```swift
let completed = expectation(
    in: registry,
    for: pattern,
    event: .completed
)
```

Import `MockerTesting` to await inspectable events:

```swift
let result = try await registry.nextCompletedRequest(
    matching: pattern,
    timeout: .seconds(1)
)
#expect(result.outcome == .response(statusCode: 201))
```

Request body capture is disabled by default. Enable it through
`MockRegistry(bodyCapturePolicy:)`; captured complete bodies can be decoded with
`MockedRequest.decodeBody(as:)` and explicit `RequestBodyError` failures.

The static `Mocker` namespace remains a convenience shared registry for serialized
tests. Prefer isolated `MockRegistry` instances for parallel tests.

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for the major-version source changes.
