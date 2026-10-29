# ADR-0090: Quarantine unverified legacy mail until server confirmation

- **Status:** Accepted
- **Date:** 2026-10-29
- **Deciders:** Henrik

## Context

ADR-0087 imports missing legacy headers into SQLite. Before its durable
import marker existed, an interrupted JSON flush could leave a deleted
header in the legacy file. Conversely, a failed index write could leave a
real newer message only in that file. The persisted cursor is overwritten
by page fetches and UIDVALIDITY describes a mailbox generation, not visited
coverage. Neither establishes whether a missing row was deleted.

Henrik approved retaining ambiguous records for recovery while hiding them
from normal consumers until server confirmation, accepting offline gaps.
This decision supersedes only ADR-0087's missing-legacy-row import policy
and extends ADR-0006's local data lifecycle. Existing completed imports
cannot be retroactively classified; this policy applies before the marker.

## Decision

1. Schema v10 follows v8's import marker and v9's attachment index without
   renumbering either. A separate account/folder/message quarantine retains
   missing legacy header payloads and their generation. Its writes and the
   existing import marker commit together. Only after success is the old
   JSON file removed; failure retains it for retry.
2. Quarantined payloads never enter normal headers, search, conversation
   links or page windows. Existing indexed rows remain authoritative and
   are not overwritten by legacy flags, dates or references. Legacy page
   membership, cursor and modification sequence are not imported. Existing
   indexed/server metadata is preserved. Malformed legacy window membership
   cannot block later recovery of a real server header.
3. Only explicit server page writes may confirm headers. Generic local
   upserts, date repair, flag changes and UIDVALIDITY/cursors alone cannot
   promote a pending record. Confirmation installs the server header, never
   the retained legacy payload, including after generation changes or when
   the legacy generation is unknown.
4. Recovery uses existing authorized first-page refresh, older pagination
   and explicit index rebuild. A pending folder cannot take the unchanged
   CONDSTORE early return. There is no independent recovery network task,
   new endpoint or consent change. Older records may remain hidden until
   the user reaches them or rebuilds the index.
5. Cached content has separate provenance. Pending recovery blocks direct
   parsed-body, raw-source and index-body reads, including offline fallback.
   Header confirmation alone does not unlock old source/body files. A fresh
   server source is persisted atomically with its source confirmation; a
   failed write remains suppressed. Fresh structured-body requests may
   return their result without confirming an old raw source. Standalone
   cache entries unrelated to quarantine keep their existing behavior.
6. Recovery data is local cache, not a backup: it stays until explicit cache
   clearing/account removal or targeted deletion. Generation invalidation
   must not expose retained content under reused UIDs. Clear Cache discards
   recovery data as well as normal headers and content; folder import
   markers survive folder clearing so leftover JSON cannot replay. Account
   removal removes all account metadata and files. No automatic expiry,
   export, recovery UI or new storage counter is introduced.

## Rationale

- Importing all missing rows preserves offline data but resurrects old
  deletions; discarding them loses recoverable records. Quarantine retains
  data without claiming it is current mail.
- Cursor-prefix filtering and UIDVALIDITY heuristics mistake incomplete
  provenance for authority. New tombstones cannot reconstruct old history.
- Reusing ordinary fetches avoids a second synchronization lifecycle and
  respects the existing network gates.
- Separate content provenance avoids exposing stale bodies after a header
  or UID is confirmed without fetching its current content.

## Consequences

### Accepted

- Temporary offline gaps are deliberate. Recovery is bounded by the pages
  actually fetched; unchanged CONDSTORE is not evidence about pending UIDs.
- Retained bytes consume local disk space until cleanup. The original JSON
  is deleted only after durable archival; quarantine inherits SQLite's
  encryption-at-rest posture from ADR-0082.
- SQLite and in-memory behavior must match; migration rollback, restart,
  consumer exclusion and cleanup are regression-tested.

### Risks

- Previously completed imports have no reliable provenance and are not
  repaired by this migration. No claim is made to reconstruct all historic
  deletions or to validate native cache migration without runtime QA.
- An old source file may survive a failed cleanup. Durable read suppression
  must remain authoritative, not the file's existence or a generic write.
- The paired storage cutover's native/performance acceptance gates remain.

## References

- Supersedes the missing-row import policy in [ADR-0087](0087-imap-header-pages-from-sqlite.md).
- [ADR-0006](0006-telemetry-and-privacy.md): privacy and local data lifecycle.
- ADR-0028: provider invariants; ADR-0030: sync engine.
- ADR-0082: encryption at rest; PRIVACY.md: cache retention and erasure.
