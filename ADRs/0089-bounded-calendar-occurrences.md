# ADR-0089: Bounded calendar occurrence projection

- **Status:** Accepted
- **Date:** 2026-10-15
- **Deciders:** Henrik Øgård
- **Tracking:** [#11](https://github.com/henrikogaard/brev/issues/11),
  parent [#3](https://github.com/henrikogaard/brev/issues/3);
  evidence in [PR #245](https://github.com/henrikogaard/brev/pull/245)
- **Acceptance:** Henrik approved the bounded design on 2026-10-15 and requested
  an ADR-only draft PR. This records design acceptance, not implementation,
  merge authorization or live-provider acceptance.

ADR-0088 is reserved by the sign-in design in
[PR #241](https://github.com/henrikogaard/brev/pull/241).

## Context

The isolated iOS/stub v7 run loaded two daily COUNT5 masters starting
October 16. October 16 displayed the masters, but October 18 displayed no
occurrences. Later-occurrence future edit/delete was not attempted.

Source inspection explains the missing projection path:

- `CalendarBrowsingModel.visibleEvents` filters raw cached `PIMEvent` records.
- Agenda buckets use those records' stored start dates.
- Day/week/month layouts test the same raw start/end intervals.
- Selection resolves a cached record ID, not a series occurrence.
- `ICSParser.RecurrenceRule` explicitly exists for descriptive summaries,
  not expansion. Its parser drops unknown RRULE parts and strips ordinal
  BYDAY prefixes. It cannot safely become an occurrence-generation input.
- Google sync requests masters and exceptions, not expanded instances.

The accepted ADR-0072 already calls for source-owned, timezone-aware recurrence
and capability-gated scopes. Implementing the missing read model needs an
explicit completeness and selection contract; adding days to the summary
rule would produce plausible but incorrect dates for more complex calendars.

## Decision

### 1. Preserve authoritative records; project a separate read model

Keep provider/cache record IDs, raw payloads, versions and series identities
unchanged. Add a provider-neutral occurrence value in BrevCalendar, consumed
by the shared agenda, day, week, month and detail surfaces.

An occurrence carries the source/collection/master record identity, original
occurrence boundary, and displayed start/end. Its view identity must be stable
and distinct from a provider record ID. Never send a projected record directly
to a writer or persist generated occurrences as authoritative provider items.

Existing exact-record deep links retain their current meaning. A projected
row may select an occurrence internally; do not silently change the existing
copy-link contract into an undocumented occurrence URL format.

### 2. Start with a strict, explicitly supported recurrence subset

Support the editor's ordinary rules first:

- DAILY, WEEKLY, MONTHLY and YEARLY, with positive INTERVAL.
- COUNT or inclusive UNTIL, never both.
- Plain nonordinal BYDAY for WEEKLY only, with defined week-start semantics.
- Timed dates with an established timezone or UTC basis, and date-only ranges.

Use a lossless validation descriptor populated at the adapter boundary, separate
from the existing descriptive `RecurrenceRule`. Validate the complete recurrence
set before marking it projectable. Unknown, duplicate, malformed or unsupported
parts must not be discarded while generating dates.

Initially, RDATE, EXDATE, exception components, ordinal BYDAY, other BY-parts,
unresolvable/custom timezone semantics, and recurrence ranges outside this
subset must produce an explicit unsupported/incomplete result for the series.
Do not generate its master pattern alongside exceptions or resurrect cancelled
instances. Full exception handling remains required follow-up work, not an
implied capability or waived acceptance criterion.

Optional/versioned descriptor data must decode old caches safely. Legacy records
without sufficient lossless metadata remain browsable as raw records with a
localized limitation; never infer completeness from the old summary model.
Existing explicit sync can populate metadata for active sources. Do not trigger
a sync, recreate a disconnected source, or rewrite frozen caches on view load.

### 3. Bound work and make incomplete coverage visible

Projection is pure local computation over a requested half-open date interval.
Grid intervals follow their visible dates. Agenda uses an explicitly displayed,
navigable bounded interval rather than expanding an infinite series.

Initial limits: at most 366 days per request and 10,000 candidate evaluations
per series/request. Limits are defensive; reaching a limit returns incomplete
coverage, never a normal-looking silently truncated success. Other healthy
series must still render. Avoid running expansion repeatedly for each grid cell.

Preserve wall-clock recurrence in the event timezone across daylight-saving
changes; do not approximate a day as 86,400 seconds. Invalid monthly/yearly
dates and nonexistent local times follow RFC 5545 skip semantics and do not
consume COUNT. Use the first occurrence of ambiguous local times. Date-only
values remain dates, including exclusive end dates, not UTC midnight instants
that drift across display zones. Test these rules before claiming support.

### 4. Separate selection from mutation

Selecting a later row retains both the authoritative master and the original
occurrence boundary. Changing the draft's displayed start must not change
which original occurrence was selected.

Do not enable new projected-row mutation merely because display now works.
Future-scope mutation requires a separately verified path that:

- Splits at the original selected boundary, not the edited DTSTART.
- Preserves the earlier master's fields and identity.
- Preserves the remaining COUNT or UNTIL bound rather than creating extra dates.
- Uses the original master for whole-series operations.
- Deletes the whole series when future-delete starts at its first occurrence.
- Preserves version/conflict checks and source/collection capability checks.
- Reports partial multi-write failure without silently losing future events or
  automatically repeating a create with an ambiguous outcome.

Unsupported series/scopes remain read-only with a localized explanation.
Single-instance mutation remains deferred. No new network API, credential scope,
provider fallback, background fetch or system-calendar permission is introduced.

## Alternatives

| Alternative | Why not the initial choice |
| --- | --- |
| Expand the existing summary rule in the view | Loses constraints and exceptions; can silently invent occurrences and target the wrong write |
| Ask each provider for instances while browsing | Breaks cache-only/offline browsing and does not fix retained disconnected caches |
| Implement full RFC recurrence immediately | Much broader parser, exception and provider-write work than the proven defect |
| Adopt a recurrence dependency immediately | Requires dependency/license/security and conformance review before selecting one |

## Consequences and acceptance

The accepted design introduces a public domain/read-model contract and bounded
UI coverage. This ADR-only publication contains no implementation and does not
claim the recurrence defect fixed. Implementation remains a subsequent step.

Implementation should be staged: lossless eligibility and bounded projection;
shared occurrence-aware browsing/selection; then verified future-scope writes.
These are layers of one fix, not independent branches changing the same models.

Minimum evidence includes COUNT5 day/agenda/grid consistency, first/third
selection identity, unsupported-rule rejection, timezone/date-only boundaries,
and defensive limits. Then use new disposable series for actual third-occurrence
edit and delete, checking both earlier and remaining dates after sync.

Do not mutate v7 recurrence masters or retained caches, Charlie, or earlier
evidence. Keep future reports separately versioned. Synthetic/stub evidence
does not replace live-provider, native macOS, physical-device, accessibility or
maintainer acceptance. No issue closure follows from this design acceptance.

## Implementation status (2026-10-16)

The read-model slice is implemented:

- `PIMEvent` carries `recurrenceDescriptor` (lossless RRULE/RDATE/EXDATE
  capture plus the DTSTART basis) and `seriesMasterItemKey`; old cached
  JSON without the keys still decodes.
- CalDAV and Google sync populate the descriptor. Google cancelled
  recurring instances persist as marker records (never rendered as
  generated rows) instead of master tombstones.
- `PIMRecurrenceValidator` admits only the supported subset; every
  rejection carries a specific `PIMRecurrenceUnsupportedReason`.
- `PIMOccurrenceProjector` generates bounded, timezone-aware,
  DST-safe occurrences inside the displayed interval, with stable row
  IDs, per-series completeness, and defensive bounds (366-day window,
  10,000 candidates per series).
- `CalendarBrowsingModel` projects once per load/navigation; agenda,
  day, week, and month render `PIMEventOccurrence` rows, and selection
  is occurrence-aware while retaining the authoritative master. The
  agenda is a navigable 30-day window.
- Later occurrences (`occurrenceIndex > 0`) are read-only with a
  localized explanation; incomplete series keep raw rows plus a
  localized coverage note. Deep links and copy-link stay authoritative.

### Read-side exceptions (2026-10-17)

Live evidence v8 showed that one EXDATE collapsed a whole series to its
master date. The read model now merges exceptions instead of refusing them:

- The descriptor keeps every EXDATE body verbatim (`exdates`, with `TZID`
  and `VALUE=DATE` parameters). The validator parses them under the series
  basis: `Z` instants or a resolvable `TZID` for timed series, `VALUE=DATE`
  days for date-only series. Any other form is `malformedExDate`. A cache
  written before bodies were captured (`hasExDate` without `exdates`) stays
  `exdatePresent`, never guessed.
- Excluded and overridden slots consume COUNT but produce no row (RFC 5545
  §3.8.5.1). A moved instance renders as its own raw row; a cancelled Google
  marker renders nothing.
- An exception inside the displayed interval whose original start the
  pattern never generates fails the series closed (`exceptions`) with the
  raw master row and the coverage note. Exceptions outside the interval are
  not checked, so coverage stays bounded.
- RDATE remains unsupported.

Known limit: if the master's own first instance is excluded or overridden,
no row has `occurrenceIndex == 0`, so whole-series Edit/Delete is only
reachable from the moved instance's raw row until §4 writes land.

Still pending: future-scope writes against projected occurrences, RDATE,
and per-occurrence actions.

## References

- [ADR-0072](0072-provider-neutral-calendar-contact-authoring.md): R6 and scope gating.
- [ADR-0028](0028-mail-provider-architecture.md): provider/domain/view boundaries.
- [ADR-0006](0006-telemetry-and-privacy.md): local-first privacy and explicit network intent.
- [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545), sections 3.3.5 and 3.3.10.
- https://github.com/henrikogaard/brev/pull/245
- https://github.com/henrikogaard/brev/issues/11
- https://github.com/henrikogaard/brev/issues/3
