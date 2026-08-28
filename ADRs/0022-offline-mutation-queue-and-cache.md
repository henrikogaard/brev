# ADR-0022: Offline mutation queue and local cache evolution

- **Status:** Accepted
- **Date:** 2026-06-01
- **Deciders:** Henrik

## Context

The related feature request requires that mailbox mutations (mark read, flag, move,
delete, junk, send) survive loss of connectivity: they must be
persisted, replayed when the network returns, and surface conflicts in
a recoverable way. Today every `MailBackend` mutation is a direct
`async throws` call — if it fails because the device is offline, the
change is simply lost.

Two constraints shape the design:

- **ADR-0028 invariant 1:** views never import backend/the provider
  types. The queue must therefore expose a provider-agnostic mutation
  model, not Realm objects or `MailApiFetcher` payloads.
- **ADR-0028 invariant 5:** Realm types never reach views. The queue's
  persistence must not leak storage types either.

The retired `previous backend` already uses Realm for the message cache. The
question of whether Realm should also back the *mutation* queue, or
whether a lighter store suffices, must be answered without prematurely
committing the whole app to a new storage engine.

## Decision

Introduce a backend-agnostic **offline mutation queue** in
`BrevBackend`, independent of any concrete storage engine:

1. **`PendingMutation`** — a `Codable`, `Sendable` value type that
   captures one intended change as a provider-neutral `Kind` enum
   (`setRead`, `setFlagged`, `setFlagColor`, `move`, `delete`,
   `setJunk`, `send`) plus the affected message IDs, a stable
   `dedupKey`, a `createdAt` timestamp, and an `attempt` count.

2. **`OfflineMutationQueue`** — a protocol for enqueue / load / update /
   remove, plus a `UserDefaultsMutationQueue` reference implementation.
   The reference store is deliberately small (JSON in `UserDefaults`):
   the queue holds *pending intentions*, which are low-volume and short
   lived, not the message cache. Send intentions store only a staged-draft
   identifier; the full draft (headers, recipients, body, and attachments)
   remains in the existing `IMAPDraftStagingStore`. Legacy queued send records
   are copied into that staging store by the IMAP backend before replay and
   then rewritten as staged references, so plaintext draft content is removed
   from `UserDefaults` without silently dropping queued mail.

3. **`MutationConflict`** — a value type describing a server-side
   conflict (e.g. a message was deleted provider before a queued flag
   replayed), with enough context for the UI to show and resolve it.

4. **`OfflineMutationProcessor`** — an actor that drains the queue
   against any `MailBackend`, applying retry-with-backoff, duplicate
   suppression (later mutations on the same `dedupKey` collapse onto the
   newest), conflict detection, and permanent-failure handling.

**Cache storage choice is explicitly deferred.** The message cache stays
on the existing `previous backend`/Realm model. This ADR records that the
mutation queue does *not* require a new storage engine, and that a
follow-up ADR is only needed if IMAP caching needs outgrow the current
model (per the issue's third acceptance criterion). The queue's
`UserDefaults` backing is replaceable behind the `OfflineMutationQueue`
protocol, so swapping it for a SQLite/Realm store later is a localized
change with no view impact.

## Rationale

- A value-typed, `Codable` mutation model satisfies invariants 1 and 5:
  views and the queue speak in IDs and enum cases, never Realm or
  the provider types.
- `UserDefaults` JSON is the right size for *pending* mutations — a
  handful of small records — and avoids dragging the whole app onto a
  new database before there is evidence the cache needs one.
- Putting retry/backoff/dedup/conflict logic in an actor keeps the
  policy testable in isolation with a fake backend, which directly
  serves the issue's "tests cover retry, cancellation, duplicate
  suppression, and permanent failure" requirement.
- Hiding the store behind a protocol means the storage decision can be
  revisited (with its own ADR) without touching call sites.

## Consequences

- New public surface in `BrevBackend`: `PendingMutation`,
  `OfflineMutationQueue`, `UserDefaultsMutationQueue`,
  `MutationConflict`, `OfflineMutationProcessor`,
  `MutationProcessingResult`.
- Mutation call sites can enqueue instead of failing when offline;
  wiring the app's mutation paths through the queue is a follow-up
  integration step (the queue and processor land first, with tests).
- We accept that `UserDefaults` is not transactional; the processor
  tolerates duplicate replay by making mutations idempotent at the
  `dedupKey` level.
- Risk: a long-offline device could accumulate stale mutations whose
  targets no longer exist. The processor treats `notFound` as a
  surfaced conflict rather than a silent drop, keeping it recoverable.

## References

- The related feature request — Offline queue and local cache evolution
- ADR-0001 — `MailBackend` protocol
- ADR-0028 — roadmap and invariants (invariants 1 and 5)
- `packages/BrevBackend/Sources/BrevBackend/OfflineMutationQueue.swift`
