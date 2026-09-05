# ADR-0012: Settings surface — `BrevSettings` package, v1 sections

- **Status:** Accepted
- **Date:** 2026-05-27
- **Deciders:** Henrik

## Context

ADR-0011 placed composite mail UI in `BrevMail` but explicitly
noted "settings panels" as one of its contents. As Settings starts
to take shape — account management (ADR-0066), appearance
(themes per ADR-0002), signature, notifications, privacy
(ADR-0006) — packing all of it inside `BrevMail` blurs the
package's cohesion: `BrevMail` is "the inbox surface", Settings is
"everything else".

Two options:

1. **Keep Settings in `BrevMail`.** Less ceremony. Works today.
   But every Settings section drags new dependencies into
   `BrevMail`: account list needs `AccountStore`, signature needs
   HTML editor primitives, notifications needs platform
   notification APIs, AI Writer settings need `BrevAI` (ADR-0008).
   `BrevMail`'s public surface widens fast.
2. **New `BrevSettings` package.** Small now, grows cleanly.
   Mirrors the layering established by ADR-0011: composition
   packages sit above primitives, and Settings is a different
   composition surface than the mail inbox.

## Decision

Create `packages/BrevSettings/` with:

- `SettingsView` — top-level entry. On macOS it's mounted in the
  `Settings { … }` scene. On iOS it's pushed from a sidebar gear
  button.
- Section views (v1):
  - `AccountsSection` — list of `BrevAccount`s from
    `AccountStore`, "Add account" / sign-out, "Set as default".
  - `AppearanceSection` — theme picker (uses
    `BrevTheme.brevBuiltIns` + custom themes when ADR-0002's JSON
    loader lands), app icon choice, and window material preferences.
  - `MailboxViewSection` — reading renderer preferences, remote
    content behavior, conversation/date grouping, sender image
    visibility and sources, preview-line count, list density, message
    font, and text size.
  - `SignatureSection` — per-account signature, plain text v1,
    HTML editor in a follow-up.
  - `ComposeSection` — local compose defaults for reply behavior,
    formatting, attachments, recipient warnings, and undo-send delay;
    hidden from the v1 sidebar until the send pipeline can honor those
    defaults.
  - `AboutSection` — version, build, license (MIT), links to
    PRIVACY.md and the provider project.
- `SettingsNavigationState` — `@Observable` to track the selected
  section on macOS (sidebar / detail layout) and to drive
  programmatic navigation on iOS. Selection changes go through an
  explicit `select(_:)` method that clamps to
  `SettingsSectionAvailability`, so feature-flagged or roadmap-only
  sections can exist in the enum without being shown in the v1 sidebar
  and without recursive SwiftUI/Observation setters.

Deferred to follow-up ADRs:

- Notifications section (needs ADR on iOS notification design).
- Privacy section (toggles for any opt-in network calls; depends
  on ADR-0006's table being filled in).
- AI Writer section (waits on ADR-0008 implementation).
- Sync / advanced (waits on ADR-0066 macOS backend).

### Dependency direction

```
                BrevBackend ─┐
                              │
   BrevThemes ── BrevDesign ──┼──> BrevMail ─────> apps/{iOS,macOS}
                              │           ↑
                              ├──> BrevSettings ─┘
                              │           ↑
                              └──> (later: BrevAI, BrevCalendar)
```

- `BrevSettings` depends on `BrevBackend`, `BrevDesign`,
  `BrevThemes`.
- `BrevMail` and `BrevSettings` are siblings: neither depends on
  the other. Cross-navigation lives in the app target.
- Nothing depends on `BrevSettings` except the two apps.

### View-side rules

Inherits the same posture as `BrevMail` (ADR-0011):

- All colors via `theme.*`.
- No `import RealmSwift`.
- No backend type-checks; capability flags only (e.g.
  `backend.capabilities.contains(.multiAccount)` to gate "Add
  account").
- Reads account state through `AccountStore` (ADR-0066), never
  through a backend-specific singleton.

## Rationale

- **Cohesion.** `BrevMail` stays "the inbox surface".
  `BrevSettings` is "everything that configures the app". When the
  next contributor opens the repo, the package names answer the
  "where would I find X?" question.
- **Optional dependency growth.** Settings eventually depends on
  `BrevAI` (writer config), `BrevCalendar` (default calendar),
  `BrevAvatars` (avatar style). Concentrating those in
  `BrevSettings` keeps `BrevMail`'s graph small.
- **Independent snapshot suites.** `BrevSettings`'s panels can
  snapshot independently of inbox views, halving the matrix size
  per package.
- **Platform-specific entry stays in the app target.** macOS's
  `Settings { … }` scene and iOS's gear-button push are different
  enough that letting each app target define its own entry is
  cheaper than another platform shim inside the package.

## Consequences

- New SPM package `packages/BrevSettings/`.
- Both `apps/iOS/Project.swift` and `apps/macOS/Project.swift`
  add `.package(path: "../../packages/BrevSettings")` and link
  the runtime product.
- `apps/macOS/Sources/BrevApp.swift` gains a `Settings { … }`
  scene mounting `SettingsView`.
- `apps/iOS/Sources/BrevApp.swift` (or `BrevMailRootView`'s
  sidebar) gains a gear button that pushes / presents
  `SettingsView`.
- Full Settings lives only in `BrevSettings`. The legacy
  `BrevMail.SettingsView` sheet was deleted; gear / account
  settings always open the app-owned Settings surface via
  `onOpenSettings`.
- `BrevMail` may import `BrevSettings` for shared preference
  types and presentation helpers. The in-mail theme picker
  (ADR-0011) stays put for now — it's a quick toolbar action,
  distinct from the full appearance panel.
- A future ADR may consolidate the in-toolbar theme picker into
  `BrevSettings`’s `AppearanceSection` once a “favorites” /
  recents UI for themes exists; not blocking on that.
- The list-density preference keeps its three-mode contract
  (`compact` / `comfortable` / `spacious`), but as of the
  2026-08-16 iOS polish, `compact` must visibly tighten every
  mailbox surface on both platforms — message rows and avatars,
  the iOS search band, and the touch sidebar rows, which had
  been ignoring the preference. Touch floors still bind: sidebar
  rows keep a 30pt minimum and the profile picker its 44pt
  target, per the accessibility posture in ADR-0025.

## Alternatives considered

- **Keep Settings inside `BrevMail`.** Rejected per Context: the
  dependency graph grows untenable.
- **Per-feature settings packages** (`BrevAccountSettings`,
  `BrevAppearanceSettings`, …). Rejected: too granular for v1.
  Revisit if `BrevSettings` outgrows ~30 source files.
- **Settings inside each platform app.** Rejected: forces
  duplication of every panel between iOS and macOS, against
  ADR-0011's stated reason for `BrevMail`.

## References

- ADR-0001 — Backend abstraction
- ADR-0002 — Theme system
- ADR-0006 — Telemetry, privacy, and GDPR
- ADR-0008 — AI Writer architecture
- ADR-0028 — Roadmap and invariants
- ADR-0011 — BrevMail package
- ADR-0066 — retired provider adapter adapter

### 2026-09-05 Settings workspace consistency

Settings receives explicit mailbox identities and cached folder collections from
Mail. Source changes refresh scoped pages; a visible mailbox selector makes any
manual Settings choice explicit. Folder retention overrides use SourceFolderID;
legacy folder-only values remain as fallback until overridden for that source.
No provider endpoints, opt-ins, or account defaults change through navigation.

Mail and Settings share opaque selection roles in BrevDesign. Settings search
indexes control labels and scrolls to the matching control. Folder Sync uses
compact hierarchical rows with labeled retention and visibility controls.


### 2026-09-05 navigation groups

Accounts and Appearance share the App group. Advanced is a normal labeled
section, with the same row alignment and header style as every other group;
capability availability still controls which destinations are present. Removing
the special disclosure group also makes the keyboard order match visible rows.
