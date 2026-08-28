# ADR-0044: Read-only cached-attachment enumeration seam

- **Status:** Accepted
- **Date:** 2026-06-26
- **Deciders:** Henrik
- **Amends:** ADR-0041

## Context

ADR-0041 separated attachment search from ordinary message search and shipped the
UI half in the related feature request: an All Attachments surface, saved search folders, the
`AttachmentSearchRecord` presentation model, and a read-only
`AttachmentSearchRecordProviding` seam in `BrevMail`. That seam is currently fed by
an empty stub provider, so the surface renders its empty state. ADR-0041
deliberately deferred the real data source, noting the surface should exist
"without adding a backend method or new network behavior before there is a real
local attachment index," and that the enumerator "gets its own ADR if it qualifies
as a protected-path change."

Populating the surface requires enumerating attachments from messages Brev has
already cached, across folders and accounts, and mapping them to
`AttachmentSearchRecord`s that route back to the owning message. Two hard
constraints apply:

- **Zero unexpected network (ADR-0006, ADR-0041).** Discovery must read only what
  is already cached. It must not connect, fetch bodies, or download attachment
  bytes. Degraded/offline states are surfaced, not silently resolved.
- **View-layer boundary (ADR-0028).** Views consume backend-neutral domain values
  through capability seams; they must not import a concrete sync/store subsystem
  or Realm types.

The relevant code facts (verified 2026-06-26):

- `MailBackend` (in `BrevBackend`) is the per-account/source capability seam the
  mail UI already holds as `[any MailBackend]`. It exposes paired single-account
  and `sourceID`-scoped methods (`body(for:)` / `body(for:sourceID:)`, etc.).
- `BrevBackend` sits **below** `BrevSyncEngine` (the dependency is
  `BrevSyncEngine -> BrevBackend`), so `BrevBackend` cannot import the sync engine.
  Instead, `IMAPSMTPBackend` reads caches through injected `BrevBackend` protocols:
  `IMAPMailboxHeaderCache.snapshot(accountID:folderID:)` returns cached
  `[MessageHeader]`, and `IMAPMessageSourceCache.source(accountID:messageID:)`
  returns the cached raw RFC822 (`IMAPMessageSource.rawMessage`). Both are
  connection-free.
- The internal `IMAPMessageBodyParser.parse(messageID:rawMessage:) -> MessageBody`
  is pure and already used by `body(for:)` and an existing attachment-presence
  check. `MessageBody.attachments` yields the attachment list.

## Decision

Add a **read-only, cache-only attachment enumeration seam** to `MailBackend`,
mirroring the existing single-account / multi-source pairing:

```swift
/// Returns attachment-bearing messages already present in Brev's local cache
/// for the given folders. Read-only: it must not connect, fetch, or download.
/// Folders or messages that are not cached are simply omitted.
func cachedAttachmentMessages(in folders: [Folder]) async -> [CachedAttachmentMessage]
func cachedAttachmentMessages(in folders: [Folder], sourceID: MailSourceID) async -> [CachedAttachmentMessage]
```

1. `CachedAttachmentMessage` is a new `BrevBackend` value type carrying the
   existing domain values needed to build a record and route back: `folder:
   Folder`, `header: MessageHeader`, and `body: MessageBody` (whose `attachments`
   are already parsed). No new identity types are introduced.
2. `IMAPSMTPBackend` implements it by, for each folder: reading
   `headerCache.snapshot` for the cached headers, then for each header reading
   `sourceCache.source` and parsing it with `IMAPMessageBodyParser`. Messages
   whose raw source is not cached are skipped. No `requireConnected()`, no
   fetch/download operations are invoked.
3. `MailBackend` provides a **default implementation returning `[]`**, so backends
   without a local attachment cache (the `MockBackend`, the quarantined the provider
   backend) opt out without bespoke code. The default-empty return makes the
   surface degrade safely; a capability flag is optional sugar on top.
4. In `BrevMail`, the existing `CachedAttachmentEnumerating` adapter (introduced in
   #259) is implemented to wrap `[any MailBackend]`, call the new method for the
   visible folders/sources, and map each `CachedAttachmentMessage` into
   `AttachmentSearchRecord`s (filtering inline parts, attaching
   `MailSourceID`/folder name). `BrevMailRootView` swaps the stub provider for this
   real provider.

The enumeration stays **metadata-first**: it reports what is cached and omits the
rest; it never causes a download or builds a document-content index. Those remain
explicit, separately disclosed actions per ADR-0041.

## Rationale

**Why a method on `MailBackend` rather than injecting the store into the view.**
The view already depends on `[any MailBackend]` and on backend-neutral domain
values. Handing it a `BrevSyncEngine` store or SQLite handle would breach
ADR-0028's invariant that views don't see concrete subsystems or Realm types, and
it would duplicate the account/source plumbing `MailBackend` already encapsulates.
Keeping discovery behind the existing capability seam is the smallest change
consistent with the architecture.

**Why read injected `BrevBackend` caches rather than `BrevSyncEngine`.** The related feature request
originally assumed the implementation would delegate to
`SyncEngineProtocol.cachedHeaders/cachedBody`. That is not possible without
inverting the package layering: `BrevBackend` is below `BrevSyncEngine`. The
injected `IMAPMailboxHeaderCache` / `IMAPMessageSourceCache` protocols are the
layer-correct cache accessors, and they are exactly what the concrete sync-engine
store already implements from above. This reuses the same caches `body(for:)`
reads, with no new dependency edge.

**Why return parsed `MessageBody` rather than raw data.** Parsing is the only way
to know which attachments a message has, and the pure `IMAPMessageBodyParser`
already exists in `BrevBackend`. Returning `MessageBody` lets `BrevMail` reuse its
tested record-mapping (`CachedAttachmentSearchRecordProvider`) instead of
re-parsing MIME in the view layer.

**Why not reuse `body(for:)`.** `body(for:)` calls `requireConnected()` and will
fetch on a cache miss. That violates the zero-network requirement. The new seam is
explicitly cache-only and never connects.

**Alternatives rejected:**

- *Inject a sync/store service into `BrevMailRootView`* — breaks the view
  boundary; wrong layer.
- *Define a separate `AttachmentCacheReading` protocol parallel to `MailBackend`* —
  duplicates per-account/source wiring and capability gating that `MailBackend`
  already owns, for no benefit.
- *Move `CachedAttachmentSource`/`CachedAttachmentEnumerating` down into
  `BrevBackend`* — unnecessary; the backend returns existing domain types and
  `BrevMail` keeps its presentation adapter, preserving the clean split between
  domain and presentation records.
- *Precompute an attachment index table in the sync engine* — larger change, new
  persisted schema, and premature; revisit only if enumeration cost proves too
  high in practice.

## Consequences

### Accepted

- A new protected-path change to `packages/BrevBackend/Sources` (the `MailBackend`
  protocol) and a new value type, plus the `BrevMail` adapter and one-line root
  rewire.
- The surface lists attachments **only from messages whose raw source is cached**.
  A message with a cached header but no cached source contributes nothing, because
  attachments cannot be known without the body. There is therefore no "attachment
  exists but bytes need downloading" row in v1; that degraded state requires the
  sync engine to cache MIME BODYSTRUCTURE independently of full bodies, which is
  out of scope here. This narrows — but does not contradict — ADR-0041's
  degraded-state vision.
- Results reflect whatever `OfflineRetentionPolicy` (ADR-0034) currently retains;
  pruning a body removes its attachments from the surface, which is the honest
  behavior.
- The `BrevMail` mapping layer is unit-testable with a fake `MailBackend`/cache;
  the existing `CachedAttachmentSearchRecordProviderTests` already covers record
  mapping.

### Risks

- **Enumeration cost.** Reading and MIME-parsing every cached source across all
  visible folders is O(messages) and can be heavy for large local caches.
  Mitigation: run off the main actor, bound/iterate by folder and page, and
  consider memoizing parsed attachment metadata later if profiling shows a
  problem. We are betting current cache sizes make a straight scan acceptable for
  v1.
- **Headless-unverifiable populate path.** The cache read + parse pipeline depends
  on real cached data; only the mapping is unit-testable without a live mailbox.
  Mitigation: supervised QA against a real or disposable IMAP account, consistent
  with the QA posture of #263.
- **Capability drift.** If a future backend gains a cache but forgets to override
  the default-empty method, its attachments silently won't appear. Mitigation:
  document the override requirement on the protocol method and cover it in the
  backend's tests.

## References

- ADR-0006: Privacy posture and zero-network-by-default
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0029: IMAP/SMTP backend foundation
- ADR-0030: Full IMAP sync and cache engine
- ADR-0034: Offline retention, search, and notification hardening
- ADR-0041: Search folders and attachment search scope (amended)
- The related feature request: Attachment and search-folder power tools (UI shipped)
- The related feature request: Cache-backed attachment enumerator (this ADR)
- Code: `packages/BrevBackend/Sources/BrevBackend/MailBackend.swift`,
  `IMAPSMTPBackend.swift`, `IMAPMessageSourceCache.swift`,
  `IMAPMailboxHeaderCache.swift`, `IMAPMessageBodyParser.swift`;
  `packages/BrevMail/Sources/BrevMail/CachedAttachmentSearchRecordProvider.swift`
