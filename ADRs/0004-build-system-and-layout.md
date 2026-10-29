# ADR-0004: Build system and project layout

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

Brev uses Tuist for project generation and SPM dependency management.
`Workspace.swift` declares the top-level workspace. App target manifests
live under `apps/*/Project.swift`; Swift packages live under
`packages/*/Package.swift`.
`Tuist/Package.swift` declares SPM dependencies. `mise` pins Tuist,
SwiftLint, SwiftFormat, Periphery, and other tool versions.

The legacy implementation must decide:

1. Inherit provider's build system or replace it.
2. How to structure two app targets (macOS, iOS) plus packages.
3. Tooling: linter, formatter, test framework, snapshot tests.

ADR-0028 establishes that we previous package only `previous backend/API/`, `Cache/`,
`Models/`, and selective `Utils/`. We discard the UI targets.
The build system must accommodate this asymmetry: retired sync engine
+ fresh app shells.

Henrik has no prior Mac app experience. Most coding will go through
AI agents (Claude Code, Codex CLI). Tooling choice should optimize for
agent fluency and well-documented standard paths.

## Decision

### Inherit Tuist

Use Tuist as the project-generation tool because:

- Cherry-picking provider `previous backend` commits requires our build to
  understand provider's Tuist target declarations.
- Tuist solves the `.xcodeproj` merge-conflict problem that plain
  Xcode projects suffer in multi-target repos.
- AI agents are competent with Tuist; well-documented; not exotic.

Version pinned via `.mise.toml`. Same pin as provider initially, bumped
when we need it.

### Repository layout

```
brev/
├── .github/
│   └── workflows/                  # CI: lint, format, tests, build, periphery
├── .mise.toml                      # Tuist, SwiftLint, SwiftFormat versions
├── .swiftlint.yml                  # Custom rules (see ADR-0005)
├── .swiftformat                    # Adapted from provider
├── ADRs/                           # Architecture decisions
├── apps/
│   ├── macOS/                      # Brev for macOS
│   │   ├── Sources/                # App entry, scenes, view layer
│   │   ├── Resources/              # Assets, Info.plist, entitlements
│   │   └── Project.swift           # Tuist target
│   ├── iOS/                        # Brev for iPhone/iPad
│   │   ├── Sources/
│   │   ├── Resources/
│   │   ├── ShareExtension/         # Share extension target
│   │   ├── NotificationServiceExtension/
│   │   └── Project.swift
│   └── iOSTests/                   # BrevIOSTests app unit test bundle
├── packages/
│   ├── previous backend/                   # retired: API, Cache, Models, selected Utils
│   │   ├── Sources/                # Modified previous package (Matomo/Sentry stripped)
│   │   ├── PATCHES.md              # Audit log of our modifications
│   │   └── Package.swift           # SPM
│   ├── BrevDesign/                 # NEW: design system, components, icons
│   │   ├── Sources/
│   │   └── Package.swift
│   ├── BrevThemes/                 # NEW: theme engine + bundled themes
│   ├── BrevAvatars/                # NEW: avatar resolution cascade
│   ├── BrevCalendar/               # NEW: ICS handling shell for v1, parser for v2
│   ├── BrevAI/                     # NEW: AIBackend protocol, provider-hosted AIBackend
│   └── BrevTesting/                # Shared test helpers, snapshot fixtures
├── themes/                         # JSON theme files (built-in)
├── docs/
│   ├── architecture.md             # High-level system view, links to ADRs
│   ├── brand.md                    # Visual identity spec
│   ├── provider-sync.md            # How provider review/cherry-pick works
│   └── contributing.md
├── prompts/                        # Agent prompt templates
│   ├── provider-review.md          # Weekly provider review prompt
│   ├── new-view.md                 # Prompt for adding a new view
│   ├── new-theme.md                # Prompt for adding a built-in theme
│   └── new-adr.md                  # Prompt for drafting an ADR
├── scripts/
│   ├── previous package-provider.sh          # Initial previous backend previous package + future updates
│   ├── strip-telemetry.sh          # Remove Matomo/Sentry on each previous package
│   ├── lint.sh                     # Run all linters
│   └── format.sh                   # Run all formatters
├── Tuist/
│   ├── Package.swift               # SPM dependencies (Alamofire, RealmSwift, etc.)
│   └── ProjectDescriptionHelpers/  # Shared Tuist build constants
├── Workspace.swift                 # Top-level workspace tying everything together
├── AGENTS.md                       # Agent contract (see file for details)
├── CLAUDE.md                       # Claude-specific guidance, links to AGENTS.md
├── llms.txt                        # Bootstrap for LLM agents
├── README.md
├── PRIVACY.md
├── LICENSE                         # MIT
├── NOTICE                          # Attribution to provider + bundled themes
├── THIRD_PARTY_LICENSES.md         # MIT theme licenses, etc.
└── CHANGELOG.md
```

### Shared design system across platforms

`BrevDesign` is a single SwiftUI package consumed by both `apps/macOS`
and `apps/iOS`. Platform-specific behavior uses SwiftUI conditional
modifiers:

```swift
public struct BrevButton: View {
    public var body: some View {
        Label(...)
            .modifier(PlatformButtonStyle())
    }
}

struct PlatformButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.buttonStyle(MacBrevButtonStyle())
        #else
        content.buttonStyle(IOSBrevButtonStyle())
        #endif
    }
}
```

Components live once. `#if os(macOS)` / `#if os(iOS)` branches handle
platform differences. Avoid duplicating components per platform; if a
component needs to be fundamentally different (e.g. Mac sidebar vs.
iPhone bottom tab bar), they get separate names (`SidebarView` vs.
`TabBarView`), not platform-conditional implementations of the same
name.

### Application icon asset catalogs

App icon masters live under `assets/app-icons/source/`. The glass family uses
six SVG files: Frost, Smoke and Obsidian, each with a full and a compact drawing.
`scripts/generate-app-icon-variants.swift` renders them with `rsvg-convert`
(librsvg, required only when regenerating assets). Each raster size is drawn
from the SVG directly. Logical sizes up to 64 points use the compact drawing,
including Retina exports. The 128 px macOS representation also uses compact
artwork for 48–64 pt Retina Dock slots. No second inset or rounded-tile mask is applied.

Smoke is the primary icon and Obsidian is the distinct Nightly icon. Both
platforms use the asset catalogs. The old Icon Composer resource is no longer
compiled, so it cannot override Smoke or add a white background. All macOS Dock variants, including Smoke, use bundled multi-resolution ICNS
files; Settings and login branding
use vector PDF image sets. iOS icon PNGs are composited over a matching neutral
background and encoded without alpha.

`AppIconVariant` retains the existing preference IDs and asset-name mapping:
`envelope-light` is Frost, `envelope-dark-metal` is Smoke, and `envelope-carbon`
is Obsidian. Existing settings backups and saved selections remain readable.
The iOS manifest and Info.plist list Frost and Obsidian as alternates; Smoke
maps to the primary icon. Icon-family changes update these surfaces together.

### Extension target API boundaries

The iOS app extensions (`BrevShareExtension`, `BrevNotificationContent`)
compile with `APPLICATION_EXTENSION_API_ONLY = YES` so APIs the SDK marks
unavailable to extensions (for example `UIApplication.shared`) fail the
build instead of surviving until App Store validation. Extension code that
must reach app-only APIs does so through extension-safe surfaces only
(e.g. the responder chain for `UIApplication.open`, which carries no
extension restriction).

### iOS app unit test target

`BrevIOSTests` (`apps/iOSTests/`) is the app shell's unit test bundle. It
depends on the `BrevIOS` app target for `@testable` access; Tuist hosts the
bundle in the app (`TEST_HOST`), so tests can also assert against the app's
Info.plist. An app extension cannot be linked by a test bundle, so pure
share-extension logic that needs coverage (currently `ShareHandoffURL.swift`)
is compiled into the test target alongside `apps/iOSTests/**`. The `BrevIOS`
scheme's test action runs the bundle via `xcodebuild test`.

### Main macOS window chrome

The main macOS scene keeps its native title-bar window style and logical
application title, but removes the visible title toolbar item. This leaves the
traffic-light controls, toolbar actions, window identity, and accessibility
semantics intact while reclaiming horizontal toolbar space for mail actions.
SwiftUI's native title-toolbar removal is used on macOS 15 and newer; the
macOS 14 deployment target uses a narrow `NSViewRepresentable` bridge that sets
only `NSWindow.titleVisibility`.
Dedicated utility windows such as Settings and Keyboard Shortcuts retain their
visible descriptive titles.

### Tooling stack

- **Project generation:** Tuist (pinned via `.mise.toml`)
- **Dependency management:** SPM (via Tuist's Package.swift)
- **Lint:** SwiftLint with `.swiftlint.yml` custom rules (ADR-0005)
- **Format:** SwiftFormat with config adapted from provider
- **Dead code detection:** Periphery (inherited from provider config)
- **Test framework:** Swift Testing (Xcode 16+, modern syntax)
- **SwiftUI view tests:** ViewInspector
- **Snapshot tests:** swift-snapshot-testing (Point-Free)
- **UI tests:** XCUITest for full-app flows
- **Commit style:** Conventional Commits (inherited from provider)
- **Tool version manager:** Mise

### CI

GitHub Actions. Workflows:

- **`lint.yml`** — SwiftLint, SwiftFormat check, Periphery dead code,
  no-telemetry custom check (ADR-0005), no-literal-colors custom check
  (ADR-0005).
- **`test.yml`** — Unit tests on both platforms.
- **`snapshot.yml`** — Snapshot tests for every component × every
  theme (light + dark).
- **`build.yml`** — Verify both apps build for release configurations.
- **`adr-required.yml`** — Block PRs touching protected paths without
  an accompanying ADR (ADR-0005).
- **`provider-review.yml`** — Weekly scheduled run that produces an
  provider change report (ADR-0005).
- **`selection-profile.yml`** — Synthetic navigation workload in an
  optimized SwiftPM test bundle. Build tests with `swift build -c release
  --build-tests -Xswiftc -enable-testing` to support `@testable` imports, then
  execute with `swift test -c release --skip-build`.
  The actual workload registers a unique per-run Darwin notification, drains
  its initial changed state, then atomically publishes its PID in the private
  output directory. The harness waits up to 30 seconds for this announcement;
  it does not discover a target by executable name. Both sides bound tracer
  startup at 120 seconds. The workload starts its measured loop only after
  xctrace's supported `--notify-tracing-started` signal, acknowledging that
  signal in a separate file. The 75-second recording budget covers the
  25-second measured loop independently of startup time.
  Harness failures preserve their exit status and print
  build/test/tracer logs; credential-free shell self-tests cover this contract.
  Build, workload and tracing commands run with an allowlisted environment
  (`HOME`, `PATH`, `TMPDIR`, optional `DEVELOPER_DIR`, the workload opt-in,
  private handshake directory and unique notification name).
  Announced workload processes are eligible only when a bounded parent-PID walk
  reaches this invocation's SwiftPM test PID; ownership is rechecked directly
  before tracer attachment. An early runner or unrelated matching process is
  never selected. Background test/tracer jobs own separate process groups;
  cleanup also snapshots their descendants because SwiftPM helpers create
  separate groups. It terminates owned descendants/groups and reaps leaders
  on success, failure or interruption, escalating after a bounded grace period.
  Each run requires a new owner-only output directory so failure reporting
  cannot reuse old logs. Trace exports may include process environments;
  inspect only allowlisted aggregate fields, never print or upload raw exports.
  Raw traces remain private and are not SwiftUI frame or app-memory evidence.

No Xcode Cloud (provider uses both; we use only GitHub Actions to
keep CI in one place and observable).

## Rationale

**Why Tuist.** Matches provider, which is the dominating concern.
Anything else would make cherry-picking provider `previous backend` work
significantly harder. Tuist is also genuinely good at multi-target
monorepos.

**Why shared `BrevDesign` across platforms.** ADR-0028 chose to
rewrite both view layers in v1. Shared `BrevDesign` is the asset
making this cheaper than two sequential rewrites. The shared package
also keeps visual consistency between Mac and iOS tight by
construction — same components, same tokens, fewer drift opportunities.

**Why Swift Testing over XCTest.** Cleaner syntax, better diagnostics,
AI agents handle it well. Apple's direction of travel.

**Why snapshot tests as a CI gate.** Theme × component combinatorics
are too large to test manually (12 themes × ~50 components = 600
permutations, light + dark = 1200). Snapshot tests catch regressions
automatically. Mac and iOS share components so snapshots cover both.

**Why Mise as the version manager.** Inherited from provider. Pins
Tuist, SwiftLint, SwiftFormat etc. to known-good versions so AI
agents working in the repo don't accidentally bump tooling and break
the build.

## Consequences

### Accepted

- Learning curve for Henrik: Tuist, Swift Testing, snapshot testing,
  SwiftLint custom rules. All standard and well-documented; not exotic.
- One-time setup cost: previous package `previous backend`, configure Tuist top-level,
  set up SPM packages, write `.swiftlint.yml` custom rules. ~1 week.
- AI agents have a clear, conventional Mac iOS app structure to
  reason about. Less surface to confuse them on.

### Risks

- **Tuist version drift from provider.** When provider bumps Tuist
  significantly, we either bump too or carry the divergence. We bump.
- **SPM packages depending on platform-conditional code.** Care
  needed in `BrevDesign` to avoid leaking `#if os(...)` into public
  APIs.
- **Snapshot test maintenance.** Every intentional visual change
  requires snapshot regeneration. Document the regeneration command
  clearly in `scripts/`.

## References

- ADR-0028: initial project rationale (previous package structure)
- ADR-0005: Enforcement (SwiftLint custom rules, CI gates)
- Tuist docs: https://docs.tuist.io/
- Swift Testing: https://developer.apple.com/documentation/testing
- Point-Free swift-snapshot-testing: https://github.com/pointfreeco/swift-snapshot-testing
- Mise: https://mise.jdx.dev/
