# ADR-0087: Serve IMAP header pages from SQLite and retire whole-folder JSON

- **Status:** Accepted
- **Date:** 2026-10-09
- **Updated:** 2026-10-10 (accepted by Henrik)
- **Deciders:** Henrik
- **Amends:** ADR-0029 (header cache semantics), ADR-0030 (migration path),
  ADR-0082 §3 (Layer A/B coverage)
- **Related:** ADR-0034 (retention), ADR-0041 (cache-only search), ADR-0044
  (cached attachment enumeration), ADR-0050 (cache-first restore), ADR-0052
  (client-side threading), ADR-0057 (Gmail labels over IMAP)

## Context

IMAP folders keep two local copies of their headers:

1. `FileBackedIMAPMailboxHeaderCache` stores one JSON file per folder under
   `Application Support/Brev/Cache/<account>/headers/<folder>.json`. Each file
   holds every visited header plus paging metadata: `uidValidity`,
   `highestModSeq`, `nextPageToken`, `firstPageHeaderIDs`, and
   `pageHeaderIDsByToken`.
2. The per-account SQLite store (`BrevSyncEngine`, `SQLiteSyncStore`,
   `sync-cache/<account>.sqlite`) has a `message_headers` table with the
   full `MessageHeader` as `header_json`, keyed by `(account, folder, uid)`
   and indexed by `(account, folder, date_ts DESC)`. `cacheHeaders` already
   writes every header here first, so SQLite is a superset of the JSON
   headers. It has none of the paging metadata.

Page-1 cache hits already read 50 rows from SQLite. The JSON file is still
decoded in full on the first open of a folder after launch, in three places:
the next-page token (`cachedLocalIndexPage`), thread resolution
(`threadedHeaders` reads every cached header), and the background
first-page refresh (UIDVALIDITY check, removal diff, `cacheHeaders`). Every
change (a flag flip, a CONDSTORE delta, a label edit) re-encodes and
atomically rewrites the whole folder file after a 750 ms debounce. Nine
other paths scan the full in-memory header array.

Measured and extrapolated cost (docs/qa/performance-baseline-2026-09.md,
local cache sizes on the maintainer's Mac):

| Fact | Value |
|---|---|
| JSON size per header | 0.5–0.8 KB, so 10k ≈ 5–8 MB, 100k ≈ 50–80 MB |
| Whole-folder rewrite at 10k headers | ≈ 75 ms (debug), per flush |
| 10k cache-hit listing, cold thread resolution | 35 ms (debug) |
| Cold folder open to interactive list | **not measured** |
| SQLite page read at 10k/50k/100k | **not measured** |

ADR-0030 planned for the JSON cache to become a fallback once the SQLite
engine shipped and to be re-evaluated after two releases. SQLite has
shipped. Henrik asked for faster folder switching on 2026-10-09.

## Decision

1. **SQLite is the IMAP header store.** When an account has a
   `localSearchIndex`, header pages, lookups, mutations, and the paging
   metadata live in that account's SQLite database. The JSON snapshot file
   is no longer read or written for such accounts.

2. **Paging metadata moves next to the rows.** Schema v7 adds:
   - `folder_sync_state.next_page_token TEXT` (the server UID cursor).
     IMAP starts writing the existing `uid_validity` and
     `highest_mod_seq` columns, which it never wrote before.
   - `imap_page_windows(account_id, folder_id, page_key TEXT, uid INTEGER,
     PRIMARY KEY(account_id, folder_id, page_key, uid))`. `page_key` is
     `first` for the first-page window or the server token for an older
     page. This replaces `firstPageHeaderIDs` and `pageHeaderIDsByToken`
     with the same meaning: a first-page refresh replaces the `first`
     window and keeps older visited windows; a revisited page that loses
     UIDs emits `messagesRemoved`.

   Header rows and window rows for one page are written in the same
   transaction.

3. **No consumer scans a whole folder on the main path.** Each full-array
   consumer becomes a query:

   | Consumer | Becomes |
   |---|---|
   | `cachedMessageHeader` | Primary-key or `message_id` lookup |
   | Cache-only search | Existing FTS (`message_search`) |
   | `retentionHeaders` | `date_ts` range query |
   | Attachment enumeration | New engine query returning only attachment-bearing (or cached-body) rows; today's path pages every header through `allIndexedHeaders` and filters in memory |
   | Removal diffs | `imap_page_windows` set difference |
   | Date repair | Query for `date_ts` ≤ 0 rows |
   | `threadedHeaders` | Thread keys for the page's members from `conversation_links`, not the whole folder |
   | Flag, label, remove, CONDSTORE | Row updates (the existing flag fast path) |

   Thread resolution stays client-side per ADR-0052. Only its input
   narrows from "every cached header" to "headers linked to this page".

   Attachment enumeration (ADR-0044) is the one consumer whose current
   SQLite path is itself a whole-folder scan: `allIndexedHeaders` pages
   every row into memory and the caller keeps the ones with attachments.
   It gets a selective query instead, with whatever column or index the
   header table needs to answer it without reading the other rows.

4. **No-index fallback is memory only.** When `localSearchIndex` is nil
   (SQLite failed to open, replacement-account validation, tests), the
   backend uses `InMemoryIMAPMailboxHeaderCache`. `FileBackedIMAPMailbox
   HeaderCache` is removed after migration. A failed SQLite open is
   already logged; this ADR does not add UI for it.

5. **Lazy per-folder migration.** On the first open of a folder after
   upgrade, if its JSON file exists: import the metadata and any headers
   missing from SQLite in one transaction, then delete the file. A folder
   never opened again is cleaned up with the account directory on the
   next "Clear cache" or account removal. Persisted `.snapshot(offset)`
   page tokens fall back to a fresh first page.

6. **Storage UI reads SQLite.** `MailboxStorageInfo` and
   `MailStorageSection` stop decoding JSON files. They use per-folder
   counts and sizes from the engine (`metrics(for:)`). Clear cache and
   account removal clear SQLite rows (`clearFolder`, `clearAccount`).

7. **Measure first, then cut over.** Before any behaviour change, add
   `PerformanceBaselineTests` cases for cold JSON decode and cold SQLite
   page read at 10k and 50k headers, and a live-run measurement of cold
   folder open (docs/qa/performance-live-run.md). The cutover ships only
   if it meets the targets below.

### Targets

| Measure | Target |
|---|---|
| Cold folder open, first 50 rows from cache, 50k folder | ≤ 200 ms (`cached_inbox_query_ms` warn budget) |
| Flag update persist, 10k folder | ≤ 5 ms, no whole-folder write |
| Idle memory with a 10k mailbox | No higher than today |
| Full-folder decodes on cold open | Zero |

### Rollout

1. Baseline tests and live measurement (no behaviour change).
2. Schema v7 and dual-write of metadata and windows.
3. Read paths switch to SQLite; JSON is read only for migration.
4. Remove `FileBackedIMAPMailboxHeaderCache` and the storage-UI JSON reader.

Each step is its own PR with tests.

## Rationale

- **Rows instead of files.** A flag flip should touch one row, not
  rewrite 5–80 MB. SQLite already holds the rows with the right index, so
  this removes a second copy rather than adding a store.
- **Alternative: keep JSON, decode off the shared actor and merge
  incrementally.** That moves the cold decode off the critical path but
  keeps the per-flush whole-file rewrite and the doubled storage.
  Rejected as a stopgap that the next mailbox-size step would outgrow.
- **Alternative: one JSON file per page.** Smaller rewrites, but it
  re-implements indexing, ordering and removal detection that SQLite
  already does. Rejected.
- **Alternative: make SQLite mandatory and fail the account without it.**
  Simpler code, but an SQLite open failure would make an account
  unusable. The memory-only fallback keeps mail working without a local
  index, at the cost of no offline cache. Rejected.
- **Windows table instead of a per-row page column.** A header can belong
  to the first window and an older visited window across refreshes. A
  join table keeps that many-to-many without rewriting header rows.

## Consequences

### Accepted

- One copy of IMAP headers on disk instead of two.
- Header rows inherit future SQLCipher protection (ADR-0082 Layer B). §3
  no longer lists `FileBackedIMAP*` header caches as staying at Layer A.
- Ordering moves from string `id DESC` to `uid DESC` as the tie-breaker
  within the same second. `date_ts` is whole seconds. Messages with an
  identical timestamp may swap order once after upgrade.
- About 176 `IMAPSMTPBackendTests` references to the in-memory cache stay
  valid. The file-backed suite and the storage-UI tests are rewritten.

### Risks

- **Downgrade.** An older build sees schema v7 and refuses to open the
  database (`unknownSchemaVersion`), losing offline cache and search
  until it is reinstalled forward. Sparkle never offers downgrades;
  manual downgrades are unsupported. Mitigation: the store could treat a
  newer schema as "wipe and resync"; decide in step 2.
- **Write contention.** Header reads share the account's lock with FTS
  and attachment indexing. A page read could wait behind a sync burst.
  Mitigation: measure in step 1. If page reads miss the budget, add a
  read-only WAL connection for page queries.
- **Write amplification.** `upsertHeaders` also maintains FTS and
  `conversation_links`. Flag-only changes use the existing fast path;
  other mutations must too.
- **`is_dirty` rows are skipped by upserts.** Nothing sets `is_dirty` from
  the backend today. This ADR keeps it unused; the offline mutation queue
  (ADR-0022) must define it before using it.
- **Thread resolution regressions.** Narrowing the input could miss links
  that only the whole-folder scan found. Mitigation: a parity test that
  resolves the same fixture folder both ways before step 3 ships.

## References

- ADR-0029: IMAP/SMTP backend foundation (header cache semantics)
- ADR-0030: Full IMAP sync and cache engine (migration path)
- ADR-0082: Encryption at rest (§3 Layer A/B coverage)
- `packages/BrevBackend/Sources/BrevBackend/FileBackedIMAPMailboxHeaderCache.swift`
- `packages/BrevBackend/Sources/BrevBackend/IMAPSMTPBackend.swift`
  (`threadedHeaders`, `cacheHeaders`, `cachedLocalIndexPage`)
- `packages/BrevSyncEngine/Sources/BrevSyncEngine/SQLiteSyncStore.swift`
  (`message_headers`, `folder_sync_state`, schema migrations)
- `docs/qa/performance-baseline-2026-09.md`, `docs/qa/performance-budgets.md`
