# ADR-0011: BrevMail package — composite mail UI lives outside apps

- **Status:** Accepted
- **Date:** 2026-05-27
- **Deciders:** Henrik

## Context

ADR-0004 lays out the build / directory structure. The Brev-owned
SPM packages it sanctions are:

- `BrevDesign` — design primitives (tokens + atom components like
  `BrevButton`, `BrevListRow`)
- `BrevThemes` — `BrevTheme`, `BrevColor`, `\.brevTheme` env
- `BrevAvatars` — sender avatar resolution (ADR-0003)
- `BrevCalendar` — calendar invitation handling (ADR-0007)
- `BrevAI` — AI Writer (ADR-0008)
- `BrevBackend` — `MailBackend` protocol + `MockBackend` (ADR-0001)

What ADR-0004 does **not** specify is where composite, mail-shaped
views live: the folder sidebar, message list, message reading pane,
compose sheet, thread view. These compose multiple BrevDesign atoms,
consume a `MailBackend`, and are shared by both `apps/macOS` and
`apps/iOS` (with platform-conditional modifiers for native chrome,
per ADR-0028 invariant 4).

Three placements were live:

1. **In `apps/*` directly.** Fastest. Forces structural duplication
   between macOS and iOS — every shared view has to be copy-pasted
   or hoisted into an internal shared folder that doesn't survive
   the SPM module boundary.
2. **Inside `BrevDesign`.** Wrong: `BrevDesign` is the primitives
   layer. Putting `MessageListView` next to `BrevButton` makes the
   "open `BrevDesign` to find a token / atom" promise fuzzier and
   forces `BrevDesign` to depend on `BrevBackend`, `BrevAvatars`,
   `BrevCalendar`, eventually `BrevAI`. That's a one-way street to
   a monolith.
3. **A new `BrevMail` package.** Depends on the other Brev packages,
   not depended on by them. Apps become thin shells: scene setup,
   window chrome, theme injection, navigation root.

Option 3 mirrors the layering Brev already commits to elsewhere:
`BrevBackend` is a leaf, `BrevThemes` is a leaf, `BrevDesign`
depends on `BrevThemes` only. `BrevMail` sits one level above and
composes them — the same shape, one rung up.

Per ADR-0005, adding a new top-level package triggers the ADR
gate; that's the trigger for this document.

## Decision

Create a new SPM package at `packages/BrevMail/` containing all
composite, mail-shaped views: folder sidebar, message list, reading
pane, thread view, compose sheet, search results, and settings
panels. Apps under `apps/macOS` and `apps/iOS` become thin scene
shells that:

1. Construct or obtain a `MailBackend` (mock for previews; real
   backend per platform).
2. Inject the active `BrevTheme` via `.brevTheme(_:)`.
3. Mount the top-level `BrevMailRootView` from `BrevMail`.
4. Provide any platform-specific menu bar, status item, dock,
   or shortcut-receiver wiring that genuinely cannot be expressed
   in cross-platform SwiftUI.

### Dependency direction

```
                BrevBackend ─┐
                              │
   BrevThemes ── BrevDesign ──┼──> BrevMail ──> apps/{macOS,iOS}
                              │
                BrevAvatars ──┤
                BrevCalendar ─┤
                BrevAI ───────┘
```

- `BrevMail` depends on `BrevBackend`, `BrevDesign`, `BrevThemes`,
  and (eventually) `BrevAvatars`, `BrevCalendar`, `BrevAI`.
- Nothing depends on `BrevMail` except the two apps.
- `BrevDesign` MUST NOT depend on `BrevMail`. Lint-enforced via
  the existing `prefer_brev_namespace_in_views` posture — there's
  no specific rule yet because the apps are the only legitimate
  importers and ADR-0005 already prohibits new view-side imports
  outside the sanctioned set.

### Package contents (initial)

- `BrevMailRootView` — platform-adaptive container.
  - macOS: `NavigationSplitView` (sidebar / list / detail).
  - iOS: `NavigationStack` with push-based detail.
- `FolderSidebar` — list of folders driven by
  `MailBackend.folders(for:)`. Selection state held in
  `MailNavigationState`.
- `MessageListView` — `LazyVStack` of `BrevListRow` per message
  header from `MailBackend.messages(in:pageToken:)`.
- `MessageDetailView` — header card + body from
  `MailBackend.body(for:)`. Placeholder rendering only at first;
  HTML rendering lands separately.
- `MailNavigationState` — `@Observable` (iOS 17 / macOS 14) holder
  for selected folder, selected message, search query, presented
  sheet.
- `ThemePickerView` — settings panel that mutates
  `\.brevTheme` at scene scope. Proves the env injection works.
- Snapshot tests under `Tests/BrevMailTests/` for the message-list
  row across the three built-in themes.

### View-side rules (inherited from ADR-0028)

- All colors via `theme.*` — enforced by `no_literal_colors_in_views`.
- No `import RealmSwift` — `BrevMail` programs against
  `BrevBackend`'s plain Swift DTOs.
- No `if backend is X` — capability checks via
  `backend.capabilities.contains(.X)`.
- Platform-conditional modifiers (`#if os(macOS)`) inside shared
  views are fine; duplicating whole views per platform is not.
- Split-view panes own full-height themed backgrounds. Sidebar,
  message-list, and reading-pane columns must not expose platform
  default scroll or split-view backgrounds when content is short,
  empty, or transparent window chrome is enabled.

## Rationale

- **Mirrors the layering Brev already committed to.** `BrevMail`
  is to `BrevDesign` what `BrevDesign` is to `BrevThemes`. Each
  ring adds composition, none of them reach down past their direct
  dependency.
- **Apps stay thin.** The macOS app and the iOS app should differ
  in _chrome_ (menu bar, status item, dock, keyboard handling)
  and in _backend wiring_, not in mail UI structure. Putting the
  mail UI in a shared package mechanically prevents drift.
- **Snapshot coverage scales.** A single snapshot suite renders
  `BrevMail` views across themes; we don't double-cover the same
  views in two app targets.
- **Backend agnosticism stays honest.** `BrevMail` depends on
  `BrevBackend` (protocol) and nothing else from the backend
  side. The macOS app's eventual backend implementation (ADR-0066
  TBD) drops into the same surface as `previous backend`'s iOS binding —
  `BrevMail` cannot tell the difference.
- **Cherry-pick legibility is unaffected.** `BrevMail` is fresh
  Brev code; `previous backend` stays a clean previous package.

## Consequences

- A new package directory under `packages/BrevMail/` with the
  standard layout (`Sources/`, `Tests/`, `Package.swift`,
  `defaultLocalization: "en"`, iOS 17 / macOS 14).
- Both `apps/iOS/Project.swift` and `apps/macOS/Project.swift`
  add `.package(path: "../../packages/BrevMail")` and link
  `BrevMail`.
- Placeholder `Text("Brev")` in both `BrevApp.swift` files is
  replaced by `BrevMailRootView()` wired to a `MockBackend` and
  the default theme.
- A follow-up ADR may carve `BrevMail` further (e.g., split
  Compose into `BrevCompose`) if the package outgrows reasonable
  cohesion. Default is to keep it one package until friction
  forces a split.
- The `adr-required` CI gate (ADR-0005) will accept `BrevMail`
  source changes once this ADR is Accepted; until then, the
  `adr-not-required` label or this ADR PR must accompany BrevMail
  source changes.
- Lint excludes are unchanged: `BrevMail` is held to the same
  rules as `BrevDesign` (`no_literal_colors_in_views`,
  `no_realm_in_views`, `no_backend_type_checks`, etc.).

## Alternatives considered

- **Composite views in `apps/*`** (option 1 above). Rejected:
  forces duplication or an ad-hoc shared folder; degrades the
  promise that apps are thin scenes.
- **Composite views in `BrevDesign`** (option 2 above). Rejected:
  collapses the primitives / compositions distinction and forces
  `BrevDesign` to depend on the backend.
- **Two parallel packages, `BrevMailCommon` + `BrevMailMacOS` /
  `BrevMailIOS`.** Rejected for now: premature. SwiftUI's
  platform conditionals are expressive enough; revisit only if a
  view turns out to be impossible to share.
- **Folding `BrevMail` into the eventual macOS backend package.**
  Rejected: would couple presentation to platform-specific backend
  code, the opposite of ADR-0001's intent.

## References

- ADR-0001 — Backend abstraction
- ADR-0002 — Theme system
- ADR-0004 — Build system and project layout
- ADR-0005 — Enforcement and protected paths
- ADR-0028 — Roadmap and invariants
- ADR-0066 — previous backend is iOS-only
