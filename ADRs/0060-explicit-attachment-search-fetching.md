# ADR-0060: Explicit user-triggered attachment search fetching

- **Status:** Accepted
- **Date:** 2026-08-24
- **Deciders:** Henrik
- **Amends:** ADR-0041

## Context

ADR-0041 established attachment search as metadata-first and prohibited
silent body downloads. ADR-0044 subsequently made the All Attachments
surface real by enumerating bodies that are already in the local cache.
That leaves ordinary message search with a `hasAttachments` predicate
unable to find older matching messages when only the first server page is
considered.

The IMAP backend now follows bounded server result pages and inspects each
candidate for attachment metadata. This may fetch message content (and the
raw MIME source can contain attachment bytes), so treating it like a
cache-only enumeration would be misleading. The behavior must remain
user-triggered and visible while preserving Brev's no-background-fetch
posture.

## Decision

1. A paginated attachment search may fetch server candidates and their
   message sources only after the user has explicitly entered or selected a
   message search containing the attachment predicate. Cache-only searches
   continue to inspect local data only.
2. The message-list UI discloses that attachment search checks message
   contents page by page and that no background fetch is running. The
   disclosure remains visible for the duration of the active fetch and is
   paired with an indeterminate progress indicator. The backend does not
   expose a trustworthy total page count, so the UI must not invent one.
3. Cancellation, a changed query, folder switch, or account switch makes
   the in-flight request stale; its response must not be applied. A new
   explicit search may start a new fetch and disclosure.
4. The All Attachments smart view and its `MailBackend` cache enumeration
   seam remain cache-only. Opening that view must not initiate this fetch.
   A future control that deliberately expands that view beyond the cache
   requires its own user-facing action and progress treatment.

## Rationale

This keeps the useful pagination fix without hiding a potentially expensive
network and MIME-source operation. A search containing “with attachments”
is a direct user request, unlike sync, refresh, cache enumeration, or idle
work, so it is the narrowest acceptable opt-in.

An indeterminate indicator is more honest than a guessed “page N of M”
counter: the server cursor only tells us whether another page exists, and
the number of candidates that need source inspection is not known up front.
Keeping the disclosure in the message-list search seam also avoids adding a
backend-specific type or a second fetching path to the All Attachments UI.

Alternatives rejected:

- **Fetch attachment candidates during cache enumeration or sync** — would
  violate the existing zero-background-fetch and cache-only contracts.
- **Fetch only the first server page** — silently misses older attachments,
  which was the correctness bug addressed by the pagination change.
- **Add a new All Attachments “load more” backend API now** — expands the
  product surface and would duplicate the already available explicit message
  search path without a settled UX for scope, cancellation, and totals.
- **Show a determinate page counter** — the server does not provide a stable
  total, so this would communicate false precision.

## Consequences

### Accepted

- Users can search beyond the first IMAP result page for messages with
  attachments, with visible disclosure and progress while the operation runs.
- A user-triggered search may perform network and raw-source work; the
  operation remains bounded per page and cancellation-aware.
- Cache-first All Attachments behavior remains predictable and offline-safe.
- The policy is covered by focused presentation tests and the existing IMAP
  pagination tests.

### Risks

- A broad attachment search can still inspect many message sources and may
  take time or transfer substantial data. The disclosure, indeterminate
  progress, bounded pages, and user-controlled search scope make that cost
  visible and attributable.
- Search text changes currently trigger the existing debounced search flow,
  so “explicit” means the user entered or selected the predicate; no extra
  submit button is required for this established search interaction.

## References

- ADR-0041: Search folders and attachment search scope
- ADR-0044: Read-only cached-attachment enumeration seam
- ADR-0006: Telemetry, privacy, and GDPR compliance
- `packages/BrevBackend/Sources/BrevBackend/IMAPSMTPBackend.swift`
- `packages/BrevMail/Sources/BrevMail/MessageListView.swift`
- `packages/BrevMail/Tests/BrevMailTests/MessageListSearchDebouncePolicyTests.swift`
