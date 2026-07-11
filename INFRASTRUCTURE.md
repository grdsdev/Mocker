# Infrastructure dispositions

| Item | Disposition | Reason |
|---|---|---|
| `.github/workflows/ci.yml` | Replaced | Swift 6 macOS/Linux, product, concurrency, and Apple compile jobs |
| `.github/workflows/stale.yml` | Maintained | Updated to `actions/stale@v9` |
| `.gitmodules` and WeTransfer CI submodule | Archived | Retained for release-history investigation; not used by required CI |
| `fastlane/` | Archived | Retained pending confirmation that no release automation consumes it |
| CocoaPods/Carthage metadata and docs | Maintained | Distribution support requires a separate owner decision |
| `.swiftpm/xcode` workspace data | Removed | No committed workspace data exists |
| `.github/CODEOWNERS` | Maintained | Current repository ownership file |
| Library evolution/binary releases | Not supported | The package makes source-package compatibility claims only |
| Windows | Not supported | No viable URLProtocol interception CI coverage |
