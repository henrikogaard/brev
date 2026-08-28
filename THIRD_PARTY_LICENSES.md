# Third-party licenses

Brev is licensed under the MIT License. Dependencies retain their own licenses.
Exact resolved revisions are recorded in `Package.resolved` files.

## Runtime dependency

| Dependency | Version | License | Use |
|---|---:|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.6 | MIT, with bundled BSD-licensed components documented in Sparkle's `LICENSE` | Direct-download macOS updates |

Binary distributions must reproduce Sparkle's complete upstream license and
its bundled component notices. Swift Package Manager retains that license in
the resolved package source.

## Test-only dependencies

| Dependency | License |
|---|---|
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | MIT |
| [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump) | MIT |
| [swift-issue-reporting](https://github.com/pointfreeco/swift-issue-reporting) | MIT |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | Apache-2.0 |
| [xctest-dynamic-overlay](https://github.com/pointfreeco/xctest-dynamic-overlay) | MIT |

These packages are used by tests and development tooling and are not intended
to be shipped as app runtime features.

## Built-in theme palettes

Built-in theme palette names may reference editor or community palette names
for compatibility and user recognition. Those names and marks belong to their
respective owners.
