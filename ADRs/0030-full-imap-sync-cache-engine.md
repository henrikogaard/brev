# ADR-0030: Full IMAP sync and cache engine

- **Status:** Proposed
- **Date:** 2026-06-07
- **Deciders:** Henrik

## Context

### What the current cache can and cannot do

ADR-0029 landed a first-tier IMAP cache: successful first-page header
listings are written to an account/folder-scoped `IMAPMailboxHeaderCache`
(JSON in `UserDefaults`), visited older page-token windows are merged into
the same cache, and the last known next-page token is persisted so the
"load more" affordance survives app relaunch. Fetched message sources are
cached in a flat file store (`IMAPMessageSourceCache`) with a per-account
byte budget. A cached folder snapshot (`IMAPFolderSnapshotCache`) keeps
the folder tree available after a transient offline launch.

The current model has deliberate gaps documented in ADR-0029's risk table:

- **No folder-wide reconciliation.** Only the first page (newest ~50
  messages) and pages the user has actually scrolled to are in cache.
  Unvisited messages in large mailboxes are invisible to cache-only search
  and to the notification path when a message is not in any loaded page.
- **No delta sync.** Each first-page refresh is a blind `UID FETCH` of the
  50 newest UIDs. The backend does not record HIGHESTMODSEQ from the `SELECT`
  response and cannot ask the server "what changed since modseq X?". This
  means every background refresh refetches headers the app already has,
  burning bandwidth on large Inboxes.
- **UIDVALIDITY is checked** on first-page load (ADR-0029) and cache is
  cleared on change, but that check only fires when the user visits the
  folder. An externally renamed or deleted folder can cause stale UIDs to
  sit in cache across launches.
- **No full-text index.** Local search covers only cached (visited)
  headers. Attachments require source fetch. Full-text body search across
  the whole mailbox is not possible without a complete local copy.

### Why this matters

- **Offline use**: a user who loses connectivity mid-session can only read
  messages they previously loaded. Inbox plus up to a handful of visited
  older windows.
- **Search accuracy**: cache-only search (`SearchQuery(execution: .cacheOnly)`)
  misses any message the user has not explicitly scrolled past. This is
  material for mailboxes with thousands of messages.
- **Notification reliability**: the first-page refresh path catches new
  arrivals when the app is in foreground, but background refresh bounded to
  `maximumBackgroundRefreshFolderCount = 12` folders and only the first page
  can miss messages in deeply nested folders.
- **Draft/Sent sync**: ADR-0029 explicitly defers folder-wide Drafts
  reconciliation for listing and editing drafts created on another device.

### What CONDSTORE/QRESYNC provide

RFC 7162 (IMAP CONDSTORE and QRESYNC) adds two capabilities that directly
address the delta-sync gap:

- **CONDSTORE** (`CAPABILITY CONDSTORE` or server advertising it in the
  `ENABLED` response): each message gains a `MODSEQ` attribute; the folder
  exposes `HIGHESTMODSEQ` in `SELECT` and `STATUS` responses. A client can
  ask `UID FETCH 1:* (FLAGS) (CHANGEDSINCE <modseq>)` and receive only the
  messages that changed since it last synced, rather than re-fetching all
  headers. This is the core efficiency primitive.
- **QRESYNC** (depends on CONDSTORE + ENABLE): a client can supply the last
  seen UIDVALIDITY, HIGHESTMODSEQ, and a set of cached UIDs in the `SELECT`
  command; the server immediately returns expunged UIDs and flag changes,
  letting the client reconcile in one round trip.

Without CONDSTORE the only safe approach is a full `UID SEARCH 1:*` to
obtain the current UID set, diff it against cached UIDs to find additions
and deletions, then `UID FETCH` just the new UIDs. This is correct but
O(n) in folder size for the comparison step and requires sending a
potentially large UID set to the server.

CONDSTORE is widely implemented: Gmail (with `X-GM-EXT-1`), Fastmail,
Outlook/Exchange 2013+, iCloud (2020+), Dovecot 2.0+, Cyrus 2.4+. A
minority of hosted providers and very old self-hosted servers do not
advertise it. The design must work on both.

RFC 3501 §6.3.1 (SELECT) establishes that every `SELECT` response carries
`UIDVALIDITY` and `UIDNEXT`. UIDVALIDITY must be compared before trusting
any cached UID; a change means the entire per-folder cache is invalid.
UIDNEXT lets the client know the smallest UID a new message will receive
and can short-circuit the diff step if nothing changed above the cached
UIDNEXT.

RFC 4731 (IMAP ESEARCH) is available on most CONDSTORE-capable servers. It
returns search results in a compact `MIN MAX ALL COUNT` or explicit UID-set
form rather than as individual untagged `SEARCH` responses. The sync engine
should prefer `UID ESEARCH` over `UID SEARCH` when the server advertises
`ESEARCH`, primarily to reduce parse overhead for large UID sets.

## Decision

### 1. Persistent store

The folder-wide header index must survive app relaunch, hold metadata for
tens of thousands of messages per folder, and support set-membership queries
(which UIDs are cached?) efficiently. The options:

- **UserDefaults JSON** (current first-page cache): adequate for O(50) rows;
  fails at O(10 000) due to slow encode/decode and memory pressure.
- **CoreData**: sufficient, but brings a heavy managed-object-context
  concurrency model that conflicts with Brev's actor-based backend design.
  The N+1 fetch and fault patterns are error-prone in async/await code.
- **Realm**: explicitly excluded. Realm is coupled to the
  `previous backend package/` retired sync engine which depends on provider API
  internals. Pulling Realm into a generic standards-first package would
  reintroduce the coupling ADR-0028 is meant to remove.
- **SQLite via a thin wrapper**: relational, fast for set queries
  (`UID IN (...)`, sorted range scans), well-understood schema migration,
  no object-graph impedance mismatch. SQLite is available on every Apple
  platform without additional dependencies. A thin wrapper keeps the package
  dependency surface minimal and hides the concrete library choice behind a
  `SyncStoreProtocol` seam.

**Decision: SQLite via a thin wrapper.** `BrevSyncEngine` will depend on
an in-process SQLite store accessed through a wrapper protocol
(`SyncStoreProtocol`) so it can be replaced or backed by an in-memory store
in tests. The schema is described below; the concrete implementation is
deferred to the implementation slice of this ADR.

#### Schema (v1)

```sql
CREATE TABLE accounts (
    id          TEXT PRIMARY KEY,       -- BrevAccount.ID
    created_at  INTEGER NOT NULL        -- Unix timestamp
);

CREATE TABLE folder_sync_state (
    account_id          TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    folder_id           TEXT NOT NULL,  -- Folder.ID (IMAP path)
    uid_validity        INTEGER,        -- last seen UIDVALIDITY
    highest_mod_seq     INTEGER,        -- last confirmed HIGHESTMODSEQ (0 = unknown)
    uid_next            INTEGER,        -- last seen UIDNEXT
    last_sync_date      INTEGER,        -- Unix timestamp of last successful sync
    sync_tier           INTEGER NOT NULL DEFAULT 0,  -- 0 = condstore, 1 = uid_scan
    PRIMARY KEY (account_id, folder_id)
);

CREATE TABLE message_headers (
    account_id  TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    folder_id   TEXT NOT NULL,
    uid         INTEGER NOT NULL,
    message_id  TEXT NOT NULL,          -- MessageHeader.ID ("folder:uid")
    flags       INTEGER NOT NULL DEFAULT 0,  -- bitmask: seen, flagged, answered, draft, junk
    envelope    BLOB NOT NULL,          -- JSON-encoded envelope (sender, subject, date, recipients)
    size_bytes  INTEGER,
    is_dirty    INTEGER NOT NULL DEFAULT 0,  -- 1 = queued mutation pending; skip during sync
    PRIMARY KEY (account_id, folder_id, uid)
);
CREATE INDEX msg_message_id ON message_headers (account_id, message_id);
CREATE INDEX msg_date ON message_headers (account_id, folder_id, envelope);

CREATE TABLE message_bodies (
    account_id  TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    message_id  TEXT NOT NULL,          -- MessageHeader.ID
    raw_source  BLOB NOT NULL,          -- UTF-8 raw RFC 5322 message source
    fetched_at  INTEGER NOT NULL,       -- Unix timestamp
    size_bytes  INTEGER NOT NULL,
    PRIMARY KEY (account_id, message_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
);
```

The `message_bodies` table is separate from `message_headers` to avoid
loading raw source during listing queries. Body storage respects the same
per-account byte budget already enforced by `FileIMAPMessageSourceCache`,
pruning the oldest rows when the budget is exceeded.

### 2. Sync protocol

#### Tier 1 — CONDSTORE-capable providers

1. Open the folder with `SELECT <mailbox> (CONDSTORE)`.
2. Read `UIDVALIDITY` from the `SELECT` response. If it differs from
   `folder_sync_state.uid_validity`, clear all `message_headers` rows for
   this folder and reset `highest_mod_seq` to 0.
3. Read `HIGHESTMODSEQ` from the `SELECT` response.
4. If `HIGHESTMODSEQ` equals the stored value, the folder is fully synced;
   skip to step 8.
5. Issue `UID FETCH 1:* (FLAGS ENVELOPE) (CHANGEDSINCE <stored_highestmodseq>)`.
   This returns only messages added or flag-changed since the last sync.
6. Insert or update returned messages in `message_headers`.
7. Issue `UID SEARCH 1:<uid_next - 1>` (or `UID ESEARCH` if available) to
   detect expunged UIDs: any UID in `message_headers` for this folder not
   returned by the search has been deleted. Remove those rows.
8. Update `folder_sync_state` with the new `UIDVALIDITY`, `HIGHESTMODSEQ`,
   `UIDNEXT`, and `last_sync_date`.
9. Emit `messagesAdded`, `messagesUpdated`, and `messagesRemoved` events
   for any differences relative to the prior cache.

Note: step 7 requires a UID-set comparison even in CONDSTORE tier. An
alternative is to rely on untagged `EXPUNGE` responses during an open
session. The sync engine uses `EXPUNGE`-response handling when a long-lived
IDLE session is active; for short background sync activations the UID
search is the safe fallback.

#### Tier 2 — UID-scan (no CONDSTORE)

1. Open the folder with plain `SELECT <mailbox>`.
2. Read `UIDVALIDITY`. Clear cache on change (same as Tier 1).
3. Issue `UID SEARCH 1:*` (or `UID ESEARCH ALL` if available) to get the
   current full UID set.
4. Compute the set difference:
   - UIDs in server result but not in `message_headers` → new messages.
   - UIDs in `message_headers` but not in server result → deleted.
5. Fetch headers for new UIDs: `UID FETCH <new-uid-set> (FLAGS ENVELOPE)`.
   Batch in groups of 200 UIDs to avoid sending a single enormous command.
6. Update flags for all returned messages (server result includes FLAGS in
   the same fetch).
7. Delete rows for removed UIDs.
8. Update `folder_sync_state.last_sync_date` and `uid_next`. Store
   `highest_mod_seq = 0` (not known).

Tier detection: after a successful `SELECT ... (CONDSTORE)`, the server
confirms CONDSTORE support via `[HIGHESTMODSEQ n]` in the response or the
OK tagged response. If the tagged response does not include a HIGHESTMODSEQ
annotation the server does not support CONDSTORE; the sync engine
permanently records `sync_tier = 1` (uid_scan) for that folder/account
combination.

#### Tier upgrade/downgrade

Once a folder is recorded as Tier 2, the engine re-attempts
`SELECT ... (CONDSTORE)` on the next sync cycle (after at minimum one week
or account re-setup). If CONDSTORE becomes available it upgrades to Tier 1
and resets `highest_mod_seq` to 0 for a full reconciling sync.

### 3. Scope and priority

The sync engine processes one folder at a time per account. Folder priority
during a sync activation:

1. **Inbox** — always first.
2. **Recently visited folders** — folders the user opened in the current or
   previous app session, ordered by last-access timestamp.
3. **Sent, Drafts, Junk** — system folders in that order.
4. **All remaining folders** — alphabetical, depth-first. Capped to a
   configurable `maximumFoldersPerActivation` (default 12 total including
   the priority slots above) per background activation.

Full deep-tree sync (all folders, no cap) is deferred to a low-priority
background task only when the device is plugged in and on Wi-Fi, subject to
platform background-refresh quotas.

### 4. UIDVALIDITY handling

`folder_sync_state.uid_validity` is compared at the start of every sync
cycle and at every `SELECT` response, including during IDLE re-connection.
On change:

1. Delete all `message_headers` rows for the folder.
2. Reset `highest_mod_seq` to 0 and `sync_tier` to 0 (re-probe CONDSTORE).
3. Emit `messagesRemoved` for all previously cached UIDs.
4. Begin a fresh full-folder sync from step 1 of the appropriate tier.

The existing `IMAPMailboxHeaderCache` already checks UIDVALIDITY on
first-page load (ADR-0029). Migration: when `BrevSyncEngine` is present,
`IMAPSMTPBackend` delegates UIDVALIDITY tracking to the engine's
`FolderSyncState`; the old `uidValidity` field in
`IMAPMailboxHeaderCacheSnapshot` becomes a read-only mirror populated from
the engine's state.

### 5. Background sync integration

The existing `MailboxBackgroundRefreshing` extension service (ADR-0029)
fires on foreground activation, network recovery, and scheduled background
fetch. `SyncScheduler` plugs into this seam:

```
BackgroundRefreshService.refresh(folders:)
    → SyncScheduler.next()          -- returns highest-priority unsync'd folder
    → SyncEngineProtocol.syncFolder(_:using:)
    → updates FolderSyncState
    → emits MailEvent stream entries
```

The number of folders processed per activation is bounded by
`SyncScheduler.maximumFoldersPerActivation`. The scheduler respects
platform background-time limits by returning `nil` from `next()` when the
cap is reached.

### 6. Integration with the offline mutation queue

The offline mutation queue (`OfflineMutationQueue`, ADR-0022) marks target
message UIDs as "dirty" by setting `message_headers.is_dirty = 1`. The sync
engine skips dirty rows during flag reconciliation and does not overwrite
their flags from a stale server response. When the mutation processor
successfully replays a queued mutation it clears the `is_dirty` flag so the
next sync cycle re-reads server state for that UID.

Invariant: the sync engine **never** flushes the mutation queue. It reads
`is_dirty` but does not call `OfflineMutationQueue.remove(id:)`. The
`OfflineMutationProcessor` (ADR-0022) owns all dequeue logic.

Race avoidance: if a sync cycle begins while a mutation is in-flight, the
sync engine skips the dirty UID for that cycle. If the mutation completes
after the sync cycle concludes, the next cycle will refresh the correct
server state.

### 7. MailBackend boundary

Views continue to call `MailBackend.messages(in:pageToken:)` and receive
`[MessageHeader]` value types. The sync engine is an implementation detail
of `IMAPSMTPBackend`:

```
views → MailBackend.messages(in:pageToken:)
             ↓
    IMAPSMTPBackend.messages(in:pageToken:)
             ↓
    if syncEngine != nil && pageToken == nil:
        read from BrevSyncEngine local store
    else:
        existing IMAP fetch path
```

The sync engine populates the store in the background. The view layer sees
the same `MessageHeader` value type regardless of whether the data came from
a live IMAP fetch or the local index.

The `BrevSyncEngine` package is a peer of `BrevBackend` in the package
graph. It imports `BrevBackend` (for `MessageHeader`, `Folder`,
`BrevAccount`, `MailEvent`). `BrevBackend` does not import `BrevSyncEngine`.
`IMAPSMTPBackend` accepts an optional `syncEngine: (any SyncEngineProtocol)?`
at construction time; when `nil` the existing first-page cache behaviour is
unchanged.

## Rationale

### SQLite over alternatives

**vs. CoreData**: CoreData's managed-object-context model requires careful
thread affinity and pinning. Brev's backend layer is actor-isolated; mixing
an `NSManagedObjectContext` with Swift concurrency's actor model reliably
produces subtle threading violations. CoreData also brings a larger framework
surface for a simple indexed store.

**vs. Realm**: Realm is already present via the retired `previous backend` sync
engine (ADR-0066), but that path is the provider-coupled. Introducing Realm
as a direct dependency of `BrevSyncEngine` would re-entangle the
standards-first backend with a proprietary dependency, violating ADR-0028's
explicit goal.

**vs. flat files / UserDefaults**: The existing `FileIMAPMessageSourceCache`
and `UserDefaultsIMAPMailboxHeaderCache` are adequate for hundreds of
records. At 10 000+ messages per folder they become impractical: JSON
encode/decode of 10 000 `MessageHeader` values on every read is slow, and
file-per-message incurs excessive filesystem metadata overhead.

**vs. GRDB directly as a declared dependency**: GRDB (MIT) is permissible to
statically link into a MIT binary. However, declaring it as a direct
dependency couples the package's external API surface to GRDB's versioning
cadence. The `SyncStoreProtocol` seam keeps the concrete library choice
internal and replaceable without a public API change.

### CONDSTORE-first with UID-scan fallback

A pure UID-scan implementation is correct on every server but burns
bandwidth proportional to folder size on every sync. For a 30 000 message
Inbox the UID-scan approach requires sending a `UID SEARCH 1:*` response
containing 30 000 integers — roughly 200 KB of protocol traffic — just to
confirm nothing changed. CONDSTORE reduces this to a single `HIGHESTMODSEQ`
integer comparison and a `CHANGEDSINCE` fetch that returns zero messages when
the mailbox is idle.

The fallback to Tier 2 for non-CONDSTORE providers is unavoidable; omitting
it would exclude iCloud Mail prior to 2020 and various corporate Exchange
installations. The Tier 2 implementation is bounded by the same
`maximumFoldersPerActivation` cap and batch size limits, so it does not
degrade performance unboundedly on large mailboxes.

### New package vs. new target in BrevBackend

Adding the sync engine as a separate `BrevSyncEngine` package (rather than
a new target inside `BrevBackend`) enforces the dependency direction at the
compiler level: `BrevBackend` cannot accidentally import `BrevSyncEngine`.
This makes it structurally impossible for the view-facing protocol
(`MailBackend`) to grow a sync-engine dependency. `IMAPSMTPBackend` lives
in `BrevBackend` and holds a protocol reference (`any SyncEngineProtocol`),
keeping coupling nominal rather than structural.

## Consequences

### New package

`packages/BrevSyncEngine/` contains:

- **`SyncEngineProtocol`** — the public interface `IMAPSMTPBackend` holds.
  Methods: `syncFolder(_:using:)`, `cachedHeaders(for:pageToken:)`,
  `cachedBody(for:)`, `invalidate(folder:reason:)`.
- **`FolderSyncState`** — value type carrying `folderID`, `uidValidity`,
  `highestModSeq`, `cachedUIDRange`, `lastSyncDate`, `syncTier`
  (`.condstore` / `.uidScan`).
- **`SyncScheduler`** — holds a priority queue of folders; `next()` returns
  the highest-priority unsync'd folder up to the configured cap.
- **`SyncStoreProtocol`** (implementation slice) — the SQLite wrapper seam;
  an `InMemorySyncStore` is provided for tests.

### Changes to IMAPSMTPBackend

`IMAPSMTPBackend.init` gains an optional parameter:

```swift
syncEngine: (any SyncEngineProtocol)? = nil
```

When `syncEngine != nil`:
- `messages(in:pageToken:)` for `pageToken == nil` reads from
  `syncEngine.cachedHeaders(for:pageToken:)` instead of making an IMAP
  network call. Subsequent pages still use the existing `listMessages`
  operation with UID page tokens.
- `connect()` schedules an initial sync pass via `SyncScheduler`.
- `backgroundRefresh(folders:)` routes through `SyncScheduler.next()`
  before falling back to the existing first-page refresh.

When `syncEngine == nil` the existing behaviour is fully preserved.

### Migration path from the current first-page cache

1. Ship `BrevSyncEngine` with the `SyncEngineProtocol` and `FolderSyncState`
   stubs (this ADR's implementation task).
2. Implement the SQLite store (`SyncStoreProtocol`) and the Tier 1 and Tier 2
   sync loops in a follow-up slice.
3. Wire `IMAPAccountConnector.standard` to instantiate `BrevSyncEngine` and
   inject it into `IMAPSMTPBackend`. At this point the first-page cache
   (`IMAPMailboxHeaderCache`) becomes a secondary fallback only.
4. Once the sync engine has been in production for two releases, evaluate
   whether `IMAPMailboxHeaderCache` can be removed entirely or kept as a
   lightweight warm-start index.

The two caches can coexist during the transition: `IMAPSMTPBackend` checks
the sync engine first; on miss it falls back to the existing header cache.
This ensures no regression in offline availability during rollout.

### Risks

- **CONDSTORE coverage gaps**: a small number of providers advertise
  CONDSTORE but return incorrect HIGHESTMODSEQ values (known issue in some
  Exchange versions). Mitigation: add a provider-quirks table; if a sync
  cycle using CONDSTORE yields inconsistencies, fall back to Tier 2 for
  that folder/session.
- **SQLite contention**: if the sync engine and mutation processor access
  the store concurrently, WAL mode must be enabled. Mitigation: enable
  `PRAGMA journal_mode=WAL` on open; all writes go through the same actor.
- **Schema migration**: adding columns requires `ALTER TABLE`. Mitigation:
  embed a schema version in the store and run migration SQL on open; the
  `SyncStoreProtocol` exposes a `currentSchemaVersion` so tests can assert
  migration correctness.
- **Memory pressure from large UID sets**: on a folder with 100 000
  messages the in-memory UID diff (Tier 2) requires holding two sets of
  integers simultaneously. Mitigation: use a SQLite `EXCEPT` query to
  compute the diff inside the database rather than in Swift heap; only the
  result set (new/deleted UIDs) materialises in memory.

## References

- ADR-0001: Backend abstraction for multi-provider
- ADR-0022: Offline mutation queue and local cache evolution
- ADR-0029: IMAP/SMTP backend foundation
- RFC 7162: IMAP Extensions: Quick Flag Changes Resynchronization (CONDSTORE)
  and Quick Mailbox Resynchronization (QRESYNC)
- RFC 3501 §6.3.1: Internet Message Access Protocol — SELECT command and
  response codes (UIDVALIDITY, UIDNEXT)
- RFC 4731: IMAP4 Extension to SEARCH Command for Controlling What Kind
  of Information Is Returned (ESEARCH)
- `packages/BrevBackend/Sources/BrevBackend/IMAPMailboxHeaderCache.swift`
- `packages/BrevBackend/Sources/BrevBackend/IMAPSMTPBackend.swift`
- `packages/BrevBackend/Sources/BrevBackend/OfflineMutationQueue.swift`
