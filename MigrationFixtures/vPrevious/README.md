# Previous-major source fixtures

These snippets document source that compiled against the maintenance branch:

```swift
Mocker.mode = .optin
Mock(url: endpoint, ignoreQuery: true, contentType: .json,
     statusCode: 201, data: [.post: payload]).register()
mock.completion = { completion.fulfill() }
expectationForRequestingMock(&mock)
```

They intentionally do not compile against the new major version. See the paired
next-major fixture and `MIGRATION_GUIDE.md`.
