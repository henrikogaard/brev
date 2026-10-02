# ADR-0085: Desktop starts in Compact list density

- **Status:** Accepted
- **Date:** 2026-10-02
- **Deciders:** Henrik
- **Related:** ADR-0004 (layout), ADR-0002 (theme), PR for the 2026-10-01
  visual review (item 12)

## Context

`MailboxListDensity` offers Compact, Comfortable, and Spacious, and the user's
choice is stored under `MailboxViewPreferenceKey.listDensity`. Every call site
that reads the preference used `MailboxListDensity.comfortable.rawValue` as its
`@AppStorage` default, on both platforms.

The 2026-10-01 visual review measured the consequence on the desktop: a
1400-point-tall window showed noticeably fewer messages than it could, because
rows carried three text lines at phone-like spacing while the window sat mostly
empty below the list. Comfortable is a reasonable starting point on a phone
screen; on a desktop window it wastes the space the platform provides.

Two constraints narrowed the options:

- Changing the default for **both** platforms would make the phone denser than
  the platform's own spacing conventions, which the merged navigation work
  (PR #162) deliberately aligned to iOS.
- Introducing a **desktop-only preference key** would strand values already
  stored under the shared key and would need a second control in Settings.

## Decision

1. `MailboxListDensity.platformDefault` is the density a platform starts with:
   `.compact` on macOS, `.comfortable` on iOS.
2. The `@AppStorage` defaults at the density call sites use
   `platformDefault.rawValue` instead of a hard-coded `comfortable`.
3. The stored preference keeps winning. Nothing is migrated, and anyone who has
   already chosen a density sees exactly what they chose.
4. `MailboxListDensityTests` pins the platform default so a future edit cannot
   silently flip it back.

## Rationale

The density setting exists to trade air for visible rows, and the desktop window
is where that trade pays off. Making the platform default express the platform's
starting point keeps one preference, one key, and one Settings control, while
letting each platform begin where it reads best.

## Consequences

- A desktop install with no saved density opens denser than before; the Settings
  control still offers all three values and switching back to Comfortable is one
  click.
- Row-level sizing (avatars, vertical padding, chrome) already derives from the
  density, so no view needed a separate desktop variant.
- Snapshot suites that render the list at a default density now capture the
  Compact rendering on macOS; those suites are deferred in CI and will need a
  baseline re-record on a macOS 26 host.

## References

- `packages/BrevDesign/Sources/BrevDesign/Preferences/MailboxViewPreferences.swift`
- `packages/BrevDesign/Tests/BrevDesignTests/MailboxListDensityTests.swift`
- `docs/qa/` entries for the 2026-10-01 visual review

## Delivery note

PR #180 landed the enum and its tests, but the twelve `@AppStorage` call-site
edits were left in an uncommitted working tree and never reached `main`. This
ADR's acceptance is recorded together with the follow-up that wires those call
sites, restoring the behavior the decision describes.
