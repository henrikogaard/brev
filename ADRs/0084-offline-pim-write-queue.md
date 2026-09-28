# ADR-0084: Offline PIM writes queue and replay on reconnect

- **Status:** Proposed
- **Date:** 2026-09-28
- **Deciders:** Henrik
- **Related:** ADR-0072 (partially supersedes its sync rule 6 — see
  "Supersession" below), ADR-0006, PRs #119/#120 (precondition
  re-resolution the replay path reuses)

## Context

The offline audit (`docs/qa/offline-audit-2026-09-28.md`) found that
mail mutations are durable offline — `OfflineMutationQueue` persists
flag/move/delete/send intents and replays them on reconnect — but PIM
writes are not. `PIMEventWriteService` (and its contact/task siblings)
issue CalDAV/CardDAV PUT/DELETE immediately; with no network the write
fails and the edit is lost unless the user keeps the editor open and
retries by hand.

Two properties already in the codebase make a queue tractable:

- **Precondition re-resolution.** Since #119/#120 the write services
  re-resolve the live href/etag at write time instead of replaying the
  draft's frozen `If-Match`. A queued write replayed later uses the
  same path, so a stale precondition cannot wedge the queue the way it
  wedged interactive saves (412-forever, matrix 2.5).
- **A proven queue + conflict surface.** `OfflineMutationQueue`
  (durable, deduped, per-account) plus `OutboxView` and
  `ConflictReviewSheet` are the shipped pattern for pending mail work.
  PIM follows the same shape rather than inventing a second mechanism.

The options:

- **Durable PIM write queue.** Persist intent (create/update/delete +
  full payload + source), apply the edit to the local cache immediately
  with a pending marker, replay on reconnect, surface conflicts via the
  existing conflict-review flow.
- **Reject edits while offline.** Cheapest: when
  `NetworkReachabilityMonitor` reports offline, PIM editors disable Save
  with copy like "Changes require a connection". Honest but loses work
  and puts Brev behind every daily-driver client.
- **Queue only updates/deletes, not creates.** Avoids the server-
  assigned-href problem for new items, but "I added an event on the
  train and it vanished" is the worst form of the bug.

## Decision

1. **PIM writes queue durably, like mail.** A per-source FIFO queue in
   the BrevCalendar store records the intent — `create(payload)`,
   `update(localID, payload)`, `delete(localID)` — not HTTP details.
   The editor always succeeds locally; the network write is the queue's
   job, not the editor's.

2. **Edits apply to the local cache immediately, marked pending.** The
   cache record carries a `pendingSync` flag; list/detail UI shows a
   subtle pending indicator (same visual language as the Outbox row
   states). If the app quits before replay, the pending edit is still
   visible on next launch — the queue and the cache marker are written
   in one transaction.

3. **Replay reuses the write services.** On
   `NetworkReachabilityMonitor` connectivity and at the start of each
   PIM sync pass, the queue drains oldest-first through the existing
   `PIM*WriteService` calls, so precondition re-resolution,
   serialization, and error classification all stay in one place. A
   replayed update whose remote record moved still lands on the live
   href; a genuine conflict (server-side change sync hasn't seen)
   surfaces through the conflict-review surface, same as an interactive
   save.

4. **Dedup and collapse.** A second update to an item with a pending
   update replaces it (the queue stores latest intent, not history). A
   delete of a pending create removes both without touching the server.
   A delete of a pending update keeps the delete. Ordering is preserved
   per item.

5. **Creates reconcile, provider-specifically.** The queued create
   payload carries a Brev-generated `UID`/`PRODID`-safe identifier. For
   CalDAV/CardDAV sources the UID is authoritative: if sync observes
   the UID first (another client pushed it, or our own create landed
   but its response was lost), the pending create adopts the remote
   href instead of duplicating. Google People/Tasks assigns resource
   names server-side and the writers never transmit a client-supplied
   id, so a UID match is impossible there; those creates reconcile by
   content fingerprint instead — a canonical hash of the contact's
   name + primary email, or the task's title + due date — compared
   against newly-observed remote items. A pending create that survives
   one full sync pass without a fingerprint match is **excluded from
   automatic replay** and surfaced in the conflict-review surface as
   "possibly created on the server — confirm before retrying"; it is
   never replayed silently, since a blind retry is exactly how
   duplicates are born.

6. **User visibility matches mail.** Queued PIM writes appear in the
   same Outbox/pending surface as mail mutations (or a directly
   equivalent PIM section if grouping requires it) with retry/discard.
   Failure copy distinguishes "queued — will sync when online" from a
   real conflict needing a decision.

7. **No new network calls.** Replay uses the existing DAV write
   endpoints; the ADR-0006 network table is unchanged. `PRIVACY.md`
   gains a line noting PIM edits are persisted locally until synced.

## Consequences

- Editors stop caring about connectivity: Save always succeeds locally,
  and the offline path becomes an ordering problem instead of a data-
  loss problem.
- The queue must understand item identity pre-server-href (local IDs
  for creates), which is why the queue stores intent + payload rather
  than serialized DAV operations.
- Replaying a create after the server already knows the UID is a
  reconciliation case, not an error — covered by decision 5.
- Conflict UX stays consistent: replayed writes land in the same
  conflict-review flow as interactive ones.

## Supersession

ADR-0072's sync rule 6 required a connection for all remote mutations
("no automatic durable mutation replay queue is promised"). This ADR
supersedes that clause for first-phase (CalDAV/CardDAV/Google) PIM
sources: offline writes now queue durably and replay through the same
write services. The rule's other half — ambiguous network outcomes
must be reconciled before retry — is retained and made
provider-specific by decision 5, so the two ADRs describe one
contract: replay is durable, but never blind.
