# ADR-0054: Mailbox arrival timestamp format and default

- **Status:** Proposed
- **Date:** 2026-08-12
- **Deciders:** Henrik
- **Amends:** ADR-0023

## Context

ADR-0023 added the `showAbsoluteArrivalTime` mailbox preference, defaulted
it off, and pinned three label tiers:

- today: localized time only;
- another day in the same year: date plus time;
- another year: date, year, and time.

Its Risks section anticipated that "date-plus-time labels are longer than
relative labels and may be truncated in narrow layouts."

A macOS HIG review of the current build confirmed that risk, and found a
second problem ADR-0023 did not consider. Both labels are too long for the
280-point minimum message-list column:

- With the preference **off** (the default), relative labels such as
  "48 min ago" wrapped onto two lines, because the row's timestamp had no
  line limit. That layout defect is fixed independently in the row itself
  and is not what this ADR is about.
- With the preference **on**, the widest label ("Jun 15, 2025, 12:00 PM")
  cannot coexist with a readable sender at the minimum column width. The
  row now gives the sender a 96-point floor and truncates the timestamp
  past that point, so the timestamp loses its tail exactly when it carries
  the most information.

Apple Mail avoids this by never showing a full date-plus-time string in
the list. It shows time for today, a weekday name within the last week,
and a date beyond that — dropping the time component entirely once the
message is not from today.

## Decision

**Proposed, pending Henrik's approval.** Amend ADR-0023's format and
default:

1. Replace the three tiers with four, and drop the time component from
   every tier except today:
   - today: localized time only (unchanged);
   - yesterday: the localized "Yesterday" string;
   - within the last seven days: the weekday name;
   - older: date, with year only when it differs from the current year.
2. Change the `showAbsoluteArrivalTime` default from off to on.

Both changes are user-visible and the preference key is public
`BrevDesign` API, which is why this needs an ADR rather than a code
change.

## Rationale

The tiers above are strictly shorter than ADR-0023's at every age, which
removes the truncation instead of mitigating it. "Yesterday" and a weekday
name are also easier to read at a glance than "Jun 11, 8:30 PM", and they
carry the recency information that matters when scanning a mailbox.

ADR-0023 explicitly rejected "always replace relative labels with absolute
labels," on the grounds that relative labels are compact and useful for
the default scan. That reasoning held for its own format, where the
absolute alternative was materially longer. It does not hold for the
format above, which is shorter than the relative labels it replaces
("Yesterday" versus "1 day ago", "09:05" versus "3 hr ago"). The tradeoff
that justified defaulting off no longer exists.

Alternatives considered:

- **Keep ADR-0023 as-is.** Rejected. It leaves a truncated timestamp in
  the one configuration where users opted in specifically to read exact
  arrival times.
- **Change the format but keep the preference off by default.** Viable and
  strictly safer. It fixes the opted-in case without changing default
  behavior, at the cost of leaving relative labels — which no Apple mail
  client uses — as what most users see. Worth taking if Henrik wants the
  smaller change.
- **Shorten only at narrow widths.** Rejected: width-dependent date
  formats make rows change meaning as the user resizes the window.

## Consequences

### Accepted

- `MessageListDatePresentation` gains a weekday tier and drops the time
  component from non-today tiers. Its tests need new cases per tier.
- The `showAbsoluteArrivalTime` default flips, which changes what existing
  users see on upgrade without them changing a setting.
- Settings export/import keeps the field; imports that omit it now default
  to on, matching the new default.

### Risks

- Users who preferred relative labels must opt out. Mitigated by the
  preference already existing and remaining in Settings.
- Weekday names are locale-dependent and longer in some locales
  ("Wednesday", "onsdag", "Mittwoch"). The row's sender floor and
  single-line timestamp handle the overflow, and the widest weekday is
  still shorter than ADR-0023's date-plus-time.

## References

- ADR-0005: Enforcement, automation, and provider sync
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0023: Mailbox arrival timestamp preference
- `packages/BrevMail/Sources/BrevMail/MessageListDatePresentation.swift`
- `packages/BrevDesign/Sources/BrevDesign/Preferences/MailboxViewPreferences.swift`
