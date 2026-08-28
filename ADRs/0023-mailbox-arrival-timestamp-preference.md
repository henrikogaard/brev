# ADR-0023: Mailbox arrival timestamp preference

- **Status:** Accepted
- **Date:** 2026-06-03
- **Deciders:** Henrik

## Context

Brev's mailbox list currently shows relative received dates such as
"2 hr ago". That is compact, but it hides the exact arrival time, which
users sometimes need when scanning recent mail or matching a message to
another event. The mailbox list already has shared view preferences in
`MailboxViewSettings`, backed by `MailboxViewPreferenceKey` in
`BrevDesign`, and surfaced through `BrevSettings`.

This touches a public `BrevDesign` preference key, so ADR-0005 requires
an ADR update. The decision must also preserve ADR-0028's shared,
platform-aware settings model.

## Decision

Add a shared mailbox view preference named `showAbsoluteArrivalTime`,
stored under `MailboxViewPreferenceKey.showAbsoluteArrivalTime`.

When the preference is off, mailbox rows continue to show relative
arrival labels. When it is on:

- Messages received today show the localized time only.
- Messages received on a different day in the same year show date plus
  time.
- Messages received in a different year show date, year, and time.

The preference defaults to off and is included in settings
export/import. Imports from older settings exports that do not include
the field default to off.

## Rationale

The alternatives were:

- Always replace relative labels with absolute labels. Rejected because
  relative labels are compact and useful for the default mailbox scan.
- Show both relative and absolute labels in every row. Rejected because
  the list timestamp column is narrow, especially on iPhone and compact
  macOS layouts.
- Make this a platform-only setting. Rejected because ADR-0028 and
  ADR-0012 establish shared settings models with platform-specific
  presentation.

A shared, default-off display preference keeps the existing behavior
while allowing users who care about exact arrival time to opt in.

## Consequences

### Accepted

- `BrevDesign` gains one public mailbox preference key.
- `MailboxViewSettings` and the settings transfer payload gain one
  boolean field.
- Message-list rows need a small presentation helper to keep relative
  and absolute timestamp formatting testable.

### Risks

- Date-plus-time labels are longer than relative labels and may be
  truncated in narrow layouts. The setting is opt-in, and labels remain
  compact by omitting the date for today's messages and the year for
  same-year messages.
- Locale-aware date formatting can produce different punctuation or
  ordering across systems. Tests pin the presentation helper with a
  deterministic locale and time zone while production uses the user's
  locale.

## References

- ADR-0002: Theme system architecture
- ADR-0005: Enforcement, automation, and provider sync
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0012: Settings surface — `BrevSettings` package, v1 sections
- `packages/BrevDesign/Sources/BrevDesign/Preferences/MailboxViewPreferences.swift`
- `packages/BrevSettings/Sources/BrevSettings/MailboxViewSettings.swift`
- `packages/BrevMail/Sources/BrevMail/MessageListDatePresentation.swift`
