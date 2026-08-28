# ADR-0045: Message copy and raw-source backend seams for context-menu actions

- **Status:** Accepted
- **Date:** 2026-06-27
- **Deciders:** Henrik
- **Amends:** ADR-0001

## Context

The related feature request grew the macOS right-click menu into an eM Client-style surface.
The related feature request is the honesty pass over it: every visible action must either work
end-to-end, be hidden until its backing feature exists, or be disabled only when
a real capability/context is missing. The audit (verified against the checked-out
code on 2026-06-27) found three groups:

- **Wired** actions (read/unread, flag, reply, archive, delete, junk, print,
  export PDF, properties, etc.) — fine.
- **Enabled but mis-routed** — Unified-Inbox `Move…` drops the per-item
  `sourceID` (the sheet reads `navigation.selectedSourceID`, which is `nil` for
  unified/smart views), and `Snooze…` / `Mark as Done` never receive a persisted
  root `LocalMessageWorkflowState`. Both are **view-layer** bugs; they need no new
  backend surface and are fixed as part of #262 but are not governed by this ADR.
- **Placeholders** declared in `MessageCommandPresentation` and shown as disabled
  no-ops: `Copy to Folder…`, `Save As…`, `Create Meeting from Message`,
  `Create Rule from Message…`, `Add Note…`, `Download for Offline`, `Show Headers`,
  `View Source`.

Four placeholders are v1-worthy but need data the backend does not yet expose:

- **Copy to Folder…** needs a server-side message *copy* (originals left in place).
- **View Source**, **Save As… (.eml export)**, and **Show Headers** all need the
  message's **raw RFC822 source**.

The relevant code facts (verified 2026-06-27):

- `MailBackend` (in `BrevBackend`) is the per-account/source capability seam the
  mail UI holds as `[any MailBackend]`. It exposes paired single-account and
  `sourceID`-scoped mutations/reads — `move(messageIDs:to:)` /
  `move(messageIDs:to:sourceID:)`, `body(for:)` / `body(for:sourceID:)` — but has
  **no `copy`** and **no raw-source accessor**.
- `MessageBody` (`Models.swift`) carries `html` / `plainText` / `attachments` /
  parsed headers but **no raw RFC822** field. The body is parsed *from* the raw
  source by the pure `IMAPMessageBodyParser`.
- Raw source is already cached: `IMAPMessageSource.rawMessage: String`,
  `IMAPMessageSourceCache.source(accountID:messageID:) -> IMAPMessageSource?`
  (connection-free), and `IMAPSMTPBackend.cachedMessageSource(messageID:)` already
  exists. This is the same cache #263/#264 populate and `body(for:)` reads.
- `BackendCapabilities` is a `UInt32` `OptionSet` and is **fully allocated**:
  every bit `1 << 0` … `1 << 31` is in use (the last is `.blockSender`). The file
  itself directs additional flags to a separate set
  (`BackendExtendedCapabilities`, BackendCapabilities.swift lines 143–145), which
  has room but, until now, **no runtime accessor on `MailBackend`** — the
  protocol only vends `var capabilities: BackendCapabilities`.

Two hard constraints apply:

- **Capability-driven UI (ADR-0028 invariant 2, AGENTS.md Rule 4).** The view must
  gate these actions on advertised capabilities, never on a concrete backend type.
- **Zero-network-by-default (ADR-0006).** Reading a message's raw source must be
  cache-first; any fetch must be a user-initiated read over the *existing* IMAP
  session, not a new background call or a new external destination.

## Decision

Add a small, capability-gated **copy** mutation and **raw-source** read to
`MailBackend`, plus the overflow capability accessor needed to gate them.

### 1. Extended-capability accessor

Add to the `MailBackend` protocol, with a default of `[]`:

```swift
/// Capability flags that overflow the 32-bit `capabilities` set.
/// Defaults to empty; backends override to advertise extended features.
var extendedCapabilities: BackendExtendedCapabilities { get }
```

```swift
public extension MailBackend {
    var extendedCapabilities: BackendExtendedCapabilities { [] }
}
```

This is the runtime accessor the overflow set was designed for; it also gives the
already-declared `.serverAliases` / `.serverSignatures` extended flags a real home.

### 2. Two extended capability flags

```swift
/// The backend can copy messages into a folder, leaving the originals in place.
public static let messageCopy = BackendExtendedCapabilities(rawValue: 1 << 9)

/// The backend can return a message's raw RFC822 source.
public static let rawMessageSource = BackendExtendedCapabilities(rawValue: 1 << 10)
```

### 3. Paired `MailBackend` methods, default-throwing

Each gets a default protocol-extension implementation that throws
`MailBackendError.notSupported(capabilities)`, matching `listAliases` /
`downloadAttachment`:

```swift
/// Copy messages into a folder, leaving the originals in place. Mirrors `move`.
/// Capability-gated by `BackendExtendedCapabilities.messageCopy`.
func copy(messageIDs: [String], to folder: Folder) async throws
func copy(messageIDs: [String], to folder: Folder, sourceID: MailSourceID) async throws

/// The message's raw RFC822 source. Cache-first: returns the cached source when
/// present, otherwise fetches it over the existing connection and caches it —
/// the same posture as `body(for:)`. Capability-gated by `.rawMessageSource`.
func rawSource(for messageID: String) async throws -> String
func rawSource(for messageID: String, sourceID: MailSourceID) async throws -> String
```

### 4. `IMAPSMTPBackend` implementation

- Advertises `.messageCopy` and `.rawMessageSource` in `extendedCapabilities`.
- `copy` issues IMAP `COPY` with the **same offline-mutation-queue replay parity**
  and `sourceID` routing as `move`.
- `rawSource` returns `cachedMessageSource(messageID:)?.rawMessage` when cached,
  otherwise fetches `BODY[]` over the existing IMAP session, caches it, and returns
  it. No `requireConnected()`-free path is bypassed beyond what `body(for:)`
  already does on a cache miss.

### 5. `BrevMail` wiring (view layer — listed for completeness, not new ADR surface)

- `MessageCommandPresentation` gains an `extendedCapabilities` parameter and gates
  `canCopyToFolder` on `.messageCopy` and `canViewSource` / `canSaveAs` /
  `canShowHeaders` on `.rawMessageSource`. When a flag is absent the action is
  **hidden**, not shown disabled (per #262's honesty rule; disabled is reserved
  for "supported but not in this context").
- **Copy to Folder** reuses the existing `MoveToSheet` chooser in a copy mode and
  calls `copy(...)`, threading the item's `sourceID`.
- **View Source** and **Show Headers** present read-only sheets built from
  `rawSource(...)` (Show Headers = the leading header block; View Source = the full
  source). **Save As…** writes `rawSource(...)` to a user-chosen `.eml` via
  `NSSavePanel`, mirroring the existing Print / Export-PDF panel path. Like Print
  and Export-PDF, Save As is offered in the focused single-folder list and the
  reader, not in the Unified-Inbox aggregate; the read-only inspectors (View
  Source / Show Headers) and Copy to Folder are offered in both.
- **Create Rule from Message…**, **Create Meeting**, **Download for Offline**,
  and **Add Note** are now implemented under #268. Add Note is local-only: it
  writes a source-scoped note into `LocalMessageWorkflowStateStorage` and never
  mutates provider state or adds a network call.
- The two routing bugs are fixed here but governed by #262, not this ADR: thread
  `sourceID` through the `.moveTo` sheet payload; pass a persisted root
  `LocalMessageWorkflowState` into both list views and map the Snoozed/Done smart
  views to `.snoozed` / `.done`.

## Rationale

**Why methods on `MailBackend` (Rule 4).** The view already depends on
`[any MailBackend]` and branches on capabilities. A `copy` / `rawSource` method
behind that seam is smaller and architecture-correct versus injecting a sync store
or type-checking the backend.

**Why `copy` mirrors `move`.** IMAP `COPY` is the same class of mutation as `MOVE`
(which is `COPY`+`EXPUNGE`). Reusing the `move` shape — paired `sourceID` variant,
offline-queue replay — keeps mutation handling uniform.

**Why raw-source is cache-first, and why fetch-on-miss is not a *new* network call
under ADR-0006 / Rule 7.** `rawSource` reads the same cache `body(for:)` reads and,
on a miss, fetches `BODY[]` over the **same IMAP session and server** the reader
already uses — no new external destination or service, and user-initiated rather
than background. Opening a message already triggers exactly this fetch. We still
record the copy mutation and the raw-source fetch in ADR-0006's operation table and
note them in `PRIVACY.md`, because they are user-triggered message-content
operations and the table should stay complete.

**Why return `String`.** The cache already stores raw RFC822 as
`IMAPMessageSource.rawMessage: String`, and that string is the parser's input.
Returning it directly avoids a re-encoding round-trip and matches existing storage.
The consequence — byte fidelity for non-UTF-8/binary parts is bounded by the cache's
`String` storage — is acceptable for viewing, copying, and `.eml` export of
standards mail and is listed as a risk.

**Why add `extendedCapabilities` now.** The core 32-bit set is full; this is the
*designed* overflow path (per BackendCapabilities.swift's own note). Adding the
accessor with a `[]` default is the minimal way to gate the new actions
capability-style without breaking any conformer, and it repairs the currently
dangling extended-flag documentation.

**Alternatives rejected:**

- *Cram into `BackendCapabilities`* — impossible; all 32 bits are allocated.
- *Add a raw-RFC822 field to `MessageBody`* — bloats the body model used
  everywhere by the reader, and the body is parsed *from* the raw source
  (circular). The raw source is a distinct, on-demand accessor.
- *Inject the sync store / SQLite into the view to read raw source* — breaks
  ADR-0028's view-layer boundary.
- *Show the actions unconditionally* — violates #262's honesty goal and Rule 4 on
  any non-IMAP backend.
- *A new parallel capability accessor instead of `BackendExtendedCapabilities`* —
  duplicates the designated overflow set for no benefit.

## Consequences

### Accepted

- New protected-path surface in `packages/BrevBackend/Sources`: one protocol
  property, four methods (two pairs), two extended flags, plus `IMAPSMTPBackend`
  implementations — and the `BrevMail` wiring + sheets and the two bug fixes.
- `Copy to Folder` and the raw-source actions appear only on backends that
  advertise the flags. The `MockBackend` and the quarantined the provider backend
  opt out via the default `[]` / default-throw, so their menus hide the actions.
- `Save As… (.eml)`, `View Source`, and `Show Headers` reflect the *raw cached or
  freshly fetched* source — honest about exactly what Brev holds.
- Adds entries to ADR-0006's operation table and `PRIVACY.md`: a user-initiated
  copy mutation, and a raw-source fetch-on-miss equivalent to the existing body
  fetch.

### Risks

- **Fetch-on-miss latency/size** for very large messages. Mitigation: run off the
  main actor and reuse the existing body-fetch path; the common case is a cache hit.
- **String fidelity** for non-UTF-8 / binary parts in `.eml` export. Mitigation:
  the cache already standardizes source as `String`; revisit with a `Data` path only
  if a concrete fidelity bug appears.
- **Capability drift.** A future backend that can copy or vend raw source must
  remember to advertise the flags or the actions silently hide. Mitigation: document
  the requirement on the methods and cover it in backend tests.
- **New `extendedCapabilities` accessor.** Conformers that don't override it get
  `[]` (intended); only `IMAPSMTPBackend` overrides for now.

## References

- ADR-0001: Backend abstraction for future multi-provider support (amended)
- ADR-0006: Telemetry, privacy, and GDPR compliance (zero-network-by-default)
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0029: IMAP/SMTP backend foundation
- ADR-0030: Full IMAP sync and cache engine (raw-source cache)
- ADR-0034: Offline retention, sync-progress, search, notification hardening
- ADR-0041 / ADR-0044: Attachment search and cached-source reuse
- The related feature request: eM Client-style right-click menu depth
- The related feature request: Wire or remove placeholder message context-menu actions (this ADR)
- The related feature request: Full-message download and indexing (raw-source overlap)
- Code: `packages/BrevBackend/Sources/BrevBackend/MailBackend.swift`,
  `BackendCapabilities.swift`, `IMAPSMTPBackend.swift`,
  `IMAPMessageSourceCache.swift`, `IMAPMessageBodyParser.swift`;
  `packages/BrevMail/Sources/BrevMail/MessageCommandPresentation.swift`,
  `MessageListView.swift`, `UnifiedInboxListView.swift`, `BrevMailRootView.swift`,
  `MoveToSheet.swift`
