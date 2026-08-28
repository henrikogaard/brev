# ADR-0034: Offline retention enforcement, sync-progress events, search correctness, and new-mail notifications

- **Status:** Accepted
- **Date:** 2026-06-14
- **Deciders:** Henrik
- **Amended by:** ADR-0041

## Context

Five user-reported gaps in the shipping IMAP/SMTP client needed
addressing together because four of them touch the `MailBackend`
protocol seam and must preserve the ADR-0028 invariants (views talk to
protocols, capability-driven UI, no concrete-type branching):

1. **Offline retention did nothing.** `OfflineRetentionPolicy` existed
   with four windows but had *no consumer* — choosing "30 days" never
   evicted anything. Users also wanted more windows.
2. **Cached-data size was under-reported.** The Storage panel measured
   only `Brev/Cache/<key>` and omitted the draft staging store.
3. **No download/sync progress.** Only indeterminate spinners existed;
   a multi-folder refresh gave no "x of N" feedback.
4. **Server search felt broken.** Two real causes: search was scoped to
   the single viewed folder with no all-folders option, and non-ASCII
   terms (e.g. Norwegian "Møte") were sent as quoted 8-bit strings,
   which strict servers reject under `CHARSET UTF-8`.
5. **New-mail notifications never fired** even though the Test button
   worked. The notification center's cached authorization status was
   captured once at setup and went stale if the user granted permission
   later; the notification body was also empty.

## Decision

1. **Retention is enforced through a new no-op-default `MailBackend`
   method.** `applyRetention(folderID:retentionDays:keepsBodies:)` takes
   plain `Int?`/`Bool` (never the `BrevSettings` enum) so `BrevBackend`
   keeps zero dependency on `BrevSettings`. The IMAP backend computes the
   age cutoff from header-cache dates (bodies carry no date) and evicts
   matching bodies via a new batch `IMAPMessageSourceCache.removeSources`.
   Headers are always preserved. `OfflineRetentionPolicy` gains
   7/14-day, 6-month, and 1-year windows plus `retentionDays`/`keepsBodies`
   mappings; the original four raw values are unchanged for migration.
   The mail view enforces the policy once per session (after first
   workspace load) and again on a `.brevMailboxSyncSettingsDidChange`
   notification posted by every retention settings surface.

2. **Storage size totals the whole account footprint.**
   `MailboxStorageInfo.totalAccountSize` sums the file caches and the
   draft staging directory (same hex-key derivation).

3. **Sync progress is a new coarse `MailEvent` case.**
   `MailEvent.syncProgress(completed:total:)` is emitted by the IMAP
   refresh loop and rendered as a determinate bar, scoped to the visible
   account via the existing `from: backend` consumer parameter — no new
   per-event source identifier.

4. **Search gains an all-folders scope and RFC 3501-correct literals.**
   A "This folder / All mailboxes" toggle passes `folderID == nil` to the
   backend (which already enumerates all folders) while keeping the
   request's anchor folder for the staleness guard. Non-ASCII SEARCH
   terms are transmitted as synchronizing literals (`{n}` + continuation
   + raw UTF-8 octets) under `CHARSET UTF-8`, reusing the proven APPEND
   literal handshake. ASCII searches are byte-identical to before.
   Transient `.notConnected`/`.network` errors fall back to local
   filtering instead of surfacing a scary error.

5. **New-mail notifications re-check authorization and carry content.**
   `BrevLocalNotificationCenter` re-reads the system authorization status
   before dropping a notification when its cached value is not authorized,
   so permission granted after setup takes effect. The notification body
   is populated from the cached header via the existing
   `CachedMessageHeaderProviding` extension service. The settings toggle
   is relabelled "Enable notifications" and its copy corrected: live
   new-mail alerts work while Brev runs, with or without provider push.

## Rationale

Reducing the retention policy to `Int?`/`Bool` at the `BrevMail` layer is
the only way to enforce it without inverting the `BrevBackend → BrevSettings`
dependency direction. Driving body eviction from header dates is forced by
the cache shape (`IMAPMessageSource` has no date). Folder-granular progress
is the achievable determinate signal without threading byte callbacks
through the IMAP transport. Literals are the standards-correct fix for the
search bug; quoting 8-bit bytes only happened to work on lenient servers.

## Consequences

- `MailBackend` gains one optional method and `MailEvent` one case; every
  exhaustive `switch` over `MailEvent` was updated, and non-IMAP backends
  inherit safe no-op/never-emit defaults.
- All-folders search is sequential per folder and capped at 50 results per
  folder; this is acceptable for v1 and left as a future refinement.
- A server answering `BAD [BADCHARSET]` to `CHARSET UTF-8` still fails the
  server search and falls back to cache; an automatic retry without
  `CHARSET` is a possible later improvement.
- Package suites cover the new behaviour: the non-ASCII literal wire
  format, retention eviction (age window, headers-only, keep-all), the
  `retentionDays` mapping, and storage sizing.

## Amendment (2026-06-28): multi-account scoping, local search index, sync-store expansion

Implementation follow-ups landed on top of the accepted decision, preserving
every invariant above (views talk to protocols, capability-driven UI, no
concrete-type branching, no new external network calls per ADR-0006):

- **Source-scoped retention.** `applyRetention` gains a `sourceID`-explicit
  overload so retention enforces per account/mailbox in multi-account
  workspaces. The original signature is retained and forwards through
  `selectSourceIfNeeded`; `BrevBackend` still takes only `Int?`/`Bool` and
  keeps zero dependency on `BrevSettings`.
- **Local search index.** `MailLocalSearchIndex` and the `rebuildSearchIndex`
  backend hook add a cache-backed local index so search resolves from local
  content when the server path is unavailable or slow, extending decision 4's
  correctness work (the related feature request). The index covers only already-cached
  headers/bodies and reuses the existing IMAP sync path for any full-message
  download — no new endpoint or external service. `LocalSearchIndexMetrics`
  reports Brev-owned record counts only and never exposes subjects, addresses,
  folder names, query text, or message content.
- **Source-scoped read seam.** `copy`/`rawSource` gain `sourceID`-explicit
  protocol variants (governed by ADR-0045) alongside the retention overload,
  so every source-scoped operation shares one shape. Backends without the
  capability still throw `.notSupported` via the protocol-extension default.
- **Sync-store expansion.** `SQLiteSyncStore` / `SyncStoreProtocol` grow the
  storage and query surface backing the index and retention.

Covered by the BrevBackend (865 tests) and BrevSyncEngine (71 tests) package
suites.

## Amendment (2026-06-28): per-message "keep offline" pins (#268)

Retention is folder/age-based, but users want to protect individual messages
(e.g. receipts) from eviction. A per-message **keep-offline pin** now exempts
specific bodies from the sweep, preserving decision 1's invariants:

- `MessageOfflineRetentionOverrideStore` (BrevMail, local UserDefaults) records
  pinned messages keyed by `account|mailbox|messageID` — collision-safe across
  the Unified Inbox's multiple sources. Local-only; cross-device sync is deferred
  to the provider-workflow-state work (#261).
- `applyRetention` gains a `keepingMessageIDs` parameter. An empty set is
  byte-identical to the prior behaviour (no regression); a non-empty set never
  evicts those bodies, in both the age-window and headers-only paths; the
  wholesale folder purge excludes the pinned IDs (and reclaims orphan bodies
  whose header is gone) so a pin can't be swept. It stays a plain
  `Set<MessageHeader.ID>` at the seam, so `BrevBackend` keeps no
  `BrevSettings`/`BrevMail` dependency. The no-source variant is a new protocol
  requirement with a forwarding default, so non-IMAP backends are unaffected.
- The retention sweep passes the source's pinned IDs; the "Keep Offline" context
  menu action toggles the pin and makes a best-effort body fetch (errors
  swallowed) so a cached copy is more likely to exist. The pin is what
  guarantees the body survives the sweep; un-pinning only clears the pin and does
  not actively evict the cached body.

Verified by the `applyRetention` exemption tests (BrevBackend) and the
`MessageOfflineRetentionOverrideStore` / context-menu tests (BrevMail).

## References

- ADR-0028 (invariants), ADR-0028 (standards-first roadmap),
  ADR-0029 (IMAP/SMTP backend), ADR-0030 (sync/cache engine),
  ADR-0041 (search folders/attachment scope), ADR-0045 (copy/raw-source seam).
- RFC 3501 §6.4.4 (SEARCH, CHARSET, literals).
