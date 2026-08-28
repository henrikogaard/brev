# ADR-0031: UI Extension Plugin API

- **Status:** Accepted
- **Date:** 2026-06-08
- **Deciders:** Henrik

## Context

Brev has 13 SPM packages, each a build-time dependency. Some are
naturally "plugin-like" (BrevAI, BrevCalendar, BrevAvatars) but there
is no formal plugin abstraction — each one requires bespoke integration
into the app chrome.

As Brev grows, third-party developers (and first-party feature teams)
should be able to contribute UI surfaces — compose toolbar buttons,
message context menu actions, settings panels, and sidebar panels —
without editing Brev's core view files. This requires a lightweight,
type-safe plugin API.

Constraints:

1. **No dynamic loading.** iOS does not allow dlopen/dlsym; macOS
   allows it only with fragile Swift ABI guarantees. All plugins must
   be linked at build time via SPM.
2. **Theme must pass through.** Plugin views rendered inside Brev's
   hierarchy must receive `@Environment(\.brevTheme)` automatically.
   Plugins must not hardcode colors.
3. **No Realm/previous backend types cross the boundary.** Per ADR-0028
   invariants 1 and 5, plugin views only see plain value types.
4. **MIT compatibility.** Plugin packages are distributed under the
   same license or a compatible one (MIT+).
5. **Third-party authors do not need the full Brev codebase.** The
   plugin package must be a small, self-contained dependency with no
   internal Brev dependencies beyond Foundation and SwiftUI.

## Decision

### New `BrevPlugins` package

A new SPM package at `packages/BrevPlugins/` publishes three things:

1. **`BrevUIExtension` protocol** — the identity of a plugin.
2. **`UIExtensionContribution` enum + config structs** — typed
   declarations of where and how a plugin's UI appears.
3. **`BrevPluginRegistry` actor** — the point where plugins register
   themselves and the app discovers them.

The package has zero Brev-internal dependencies: only `SwiftUI` and
`Foundation`. Third-party authors add `BrevPlugins` to their SPM
package and export types conforming to `BrevUIExtension`.

### `BrevUIExtension` protocol

```swift
public protocol BrevUIExtension: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    var author: String { get }
    var contributions: [UIExtensionContribution] { get }
}
```

### Contribution types

Four extension points in v1:

- **`composeToolbar(ComposeToolbarConfig)`** — a button in the compose
  window's toolbar. Receives `ComposeContext` (draft metadata, account).
- **`messageContextMenu(MessageContextMenuConfig)`** — an action in the
  message list or message detail context menu. Receives
  `MessageContext` (selected message IDs, folder, source).
- **`settingsPanel(SettingsPanelConfig)`** — a section in Brev's
  Preferences window. Receives no context; managed as a standalone
  SwiftUI view.
- **`sidebarPanel(SidebarPanelConfig)`** — an item in the sidebar's
  "Extensions" group. Receives `SidebarContext` (account, selected
  folders, navigation callback).

All config structs carry: `id`, `displayName`, `sfSymbolName`, and a
`content` builder that returns `AnyView`. The builder receives a typed
context object (plain value type) so the plugin can react to what the
user is doing.

### Registry and discovery

Plugins call `BrevPluginRegistry.register(_:)` at an initialization
point defined by the host app. The host app reads
`BrevPluginRegistry.allExtensions` once at startup and wires each
plugin's contributions into the appropriate chrome locations.

The registry is an `actor` so thread-safe access is guaranteed even
if plugins are registered from different contexts.

### Integration into the app

Each app target (macOS, iOS) or chrome owner (BrevMail, BrevSettings)
reads plugin contributions and renders them:

- **Compose toolbar:** `BrevMail/ComposeView.swift` iterates
  `composeToolbar` contributions and renders buttons alongside the
  built-in send/attach/format bar.
- **Message context menu:** The row context menu builders in
  `BrevMail/MessageListView.swift` and
  `BrevMail/UnifiedInboxListView.swift` iterate
  `messageContextMenu` contributions and append menu items after the
  inventory-backed built-in actions.
- **Settings:** `BrevSettings/SettingsView.swift` iterates
  `settingsPanel` contributions and renders them as
  `NavigationLink`s in the Extensions section.
- **Sidebar:** A dynamic "Extensions" section in the sidebar
  renders `sidebarPanel` contributions with expandable/selectable
  rows.

All plugin views are wrapped in a `PluginHost` modifier that injects
the current `BrevTheme` environment value so plugins always render
in the user's chosen theme.

## Rationale

**Why four contribution types, not one generic "view injection".**
Each extension point has different needs: compose buttons receive a
draft, context menus receive message IDs, settings panels are
standalone. Typed configs are self-documenting and let the host app
enforce correct usage without runtime checks.

**Why a registry actor instead of SPM auto-discovery.** Swift does not
have a stable mechanism for discovering protocol conformances across
module boundaries at runtime. An explicit registration call is the
pragmatic trade-off: it works today, is testable, and costs one line
per plugin.

**Why `AnyView` instead of `some View` in config structs.** The
contributions array is heterogeneous (different plugin views have
different concrete types). `AnyView` is the natural SwiftUI solution
here; the type erasure is confined to the config layer, not the plugin
implementation.

**Why BrevPlugins has no internal Brev dependencies.** Third-party
authors should not need to check out the entire Brev monorepo to write
a plugin. A standalone package with only Foundation + SwiftUI is the
lowest possible adoption barrier.

**Why not `BackendExtensionService`.** The existing extension service
pattern is for backend-specific features (auto-reply, rules). Plugin
UI extensions are orthogonal: they can (but need not) be tied to a
backend, and they contribute *views*, not *backend methods*.

## Consequences

### Accepted

- BrevPlugins package is created and versioned alongside the main repo.
- Existing plugin-like packages (BrevAI, BrevCalendar) are NOT migrated
  to the plugin API in this ADR; that is future work and may not happen
  if the tight coupling is acceptable.
- The four contribution types are v1 only; more can be added later
  (e.g., `composeSidebar`, `messageDetailToolbar`).
- Plugins are build-time only; there is no runtime plugin gallery or
  installation flow in v1.
- A reference/example plugin package living in a `Plugins/` directory
  at the repo root demonstrates the API.

### Risks

- **Low plugin adoption.** If the API is too cumbersome or the four
  extension points are too limited, third parties may not write
  plugins. Mitigation: make the protocol minimal, provide a working
  example plugin, and document clearly.
- **Theme divergence.** Plugin authors might use literal colors despite
  the environment-provided theme. Mitigation: the ADR-0005 enforcement
  rule (`no_literal_colors_in_views`) does not cover plugin packages;
  the PluginHost wrapper should document the expectation. A future
  SwiftLint rule could be extended.
- **Registry initialisation order.** If the app tries to read
  contributions before plugins register, the list is empty. Mitigation:
  the app controls the init sequence; registration happens before the
  first chrome render.

## References

- ADR-0002: Theme system architecture
- ADR-0028: Roadmap to v2 and architectural invariants (invariants 1, 2, 5)
- ADR-0005: Enforcement, automation, and provider sync (protected paths)
- ADR-0066: v2 provider roadmap and provider extensions (superseded)
- BrevAI package (`packages/BrevAI/`) — existing plugin-like pattern
- BrevCalendar package (`packages/BrevCalendar/`) — existing plugin-like pattern
- Swift Package Manager documentation
