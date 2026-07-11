# Swift 6 migration

Mocker now requires Swift 6.0 and Xcode 16 or newer. The supported deployment
minimums are macOS 13, iOS 16, tvOS 16, and watchOS 9. Linux is tested with the
official Swift 6.0 container. Windows support, library evolution, and binary
compatibility are not claimed.

| Component | Minimum Swift | Platforms | Notes |
|---|---:|---|---|
| `Mocker` | 6.0 | Declared Apple platforms and Linux | Framework-neutral core |
| `MockerXCTest` | 6.0 | XCTest-supported declared platforms and Linux | Registry expectations |
| `MockerTesting` | 6.0 | Testing-supported declared platforms and Linux | Async observation waits |

This tools-version increase prevents older SwiftPM versions from loading the
package. The last Swift 5-compatible commit is `ea16253`. Callback closures that
cross concurrency domains must satisfy Swift 6 sendability checking; prefer
registry events and immutable `MockedRequest` snapshots in new code.

The existing CocoaPods, Carthage-related documentation, Fastlane files, and CI
submodule are retained pending a distribution-channel decision. They are not
treated as supported Swift 6 installation paths by this package matrix.
