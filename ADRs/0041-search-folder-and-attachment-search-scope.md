# ADR-0041: Search folders and attachment search scope

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Amends:** ADR-0034
- **Amended by:** ADR-0060

## Context

Brev's IMAP/SMTP hardening in ADR-0034 made ordinary message search more
correct: users can search the current folder or all folders, non-ASCII search
terms use IMAP literals, and transient server failures fall back to local cache
filtering.

That still leaves a parity gap against mature desktop clients such as eM Client:
saved search folders, an All Attachments surface, and eventual search within
attached documents are different user jobs. Treating all of them as one message
search box would blur persistence, routing, and privacy expectations.

The relevant invariants are unchanged:

- Views must consume backend-neutral domain values and source identifiers, not
  concrete provider types or Realm objects.
- Search and attachment discovery must not create unexpected external network
  calls.
- Cross-account results must carry enough source/folder/message context to route
  back to the correct message, especially from Unified Inbox style surfaces.

## Decision

Brev separates the search family into three concepts:

1. **Ordinary message search** remains the mailbox search bar. It can execute
   against server search or cache fallback according to the current backend and
   scope.
2. **Saved search folders** are durable `SmartMailbox` records. They now carry a
   `kind` discriminator so message-header predicates and attachment smart views
   can persist side by side without executing through the wrong engine.
3. **Attachment search** is a source-aware presentation model built from cached
   message and attachment metadata. Rows carry `MailSourceID`, folder id,
   message id, and attachment id so an All Attachments view can open the correct
   message and attachment across account, folder, and Unified Inbox boundaries.

Attachment search is metadata-first. It may show cached and downloadable
attachments, but it must surface degraded/offline states instead of silently
fetching bodies or indexing attachment contents. Downloading bytes or expanding a
local document-content index must be caused by an explicit user action or by a
separate, disclosed cache/sync setting.

## Rationale

Saved search folders need stable persistence and edit/delete semantics; ordinary
message search needs transient execution state; attachment search needs
attachment-specific routing and degraded-state copy. One generic search model
would make each path either under-specified or too easy to misuse.

The `SmartMailbox.kind` discriminator keeps legacy saved queries decoding as
message searches while making future attachment smart views explicit. Keeping
attachment rows as presentation records also gives the UI the All Attachments
surface it needs without adding a backend method or new network behavior before
there is a real local attachment index.

## Consequences

- Legacy smart mailbox payloads without `kind` decode as `.messageSearch`.
- Message smart mailbox execution ignores `.attachmentSearch` records; attachment
  smart views require attachment/body metadata instead of `MessageHeader` alone.
- Attachment rows must carry source, folder, message, and attachment identity.
- Attachment search can filter by query, file type, sender, and folder using
  available metadata.
- Missing cached bodies or missing local content indexes appear as degraded
  states in results. They are not hidden and do not trigger automatic downloads.
- Search within attached document contents remains future work for a local-only
  indexer and needs its own tests before any UI claims that capability.

## Implementation status (2026-06-26, the related feature request)

The UI half of this decision has shipped in `BrevMail`:

- An **All Attachments** smart view (`AllAttachmentsView`) with query/file-type
  filtering, theme-tokened rows, degraded-state badges, and an empty state.
- **Saved search folders** in the sidebar (create/edit/delete) backed by
  `SmartMailboxSettings`, plus the `SavedSearchEditor` presentation and sheet.
- The source-aware presentation model (`AttachmentSearchRecord` +
  `AttachmentSearchPresentation`) carrying source/folder/message/attachment
  identity, and a read-only `AttachmentSearchRecordProviding` seam with a pure,
  unit-tested cache→record mapper (`CachedAttachmentSearchRecordProvider`).
- Root wiring that routes the surface and opens a result back to its message.

Consistent with the Rationale above ("without adding a backend method ... before
there is a real local attachment index"), the content pane is wired with an empty
stub provider for now, so the surface renders its empty state. The real cache
enumerator — which requires a new **read-only** `MailBackend` cache-read seam and
supervised live QA — is deferred to the related feature request and remains metadata-first (no
automatic downloads, no content indexing) per this ADR. That seam, when designed,
gets its own ADR if it qualifies as a protected-path change.

## Implementation status (2026-06-28): mail UI layer for the cached seams

The view layer that realizes this decision and its sibling backend seams has
shipped in `BrevMail`/`BrevSettings`, preserving the ADR-0028 invariants (views
talk to protocols, capability-driven UI, no concrete-type branching):

- **All Attachments** now populates from the read-only cached-attachment
  enumerator behind `AttachmentSearchRecordProviding` (the live provider from
  #264), replacing the empty stub — still metadata-first, no downloads.
- **Search refinements:** `MessageListSearchDebouncePolicy` and
  `UnifiedInboxSearch` debounce/scope handling, plus the local-cache fallback
  surfacing, building on ADR-0034 decision 4.
- **Mail storage management (#257):** a `MailStorageSection` settings panel and
  `MailboxStorageInfo` surface disk usage and cache controls, extending
  ADR-0034 decision 2 (storage sizing) into a management view. A redacted
  snapshot helper (`scripts/mail-storage-redacted-snapshot.sh`) supports
  supervised QA without exposing message content.
- **Retention UI:** `MailRetentionSweepPlan` renders the ADR-0034 retention
  policy as a user-visible sweep plan.
- **Context-menu honesty (#262):** `MessageEMLExport` and the copy / raw-source
  menu actions surface the ADR-0045 seam; unbacked actions stay hidden.

Verified: `BrevMail` 1150 tests pass, `BrevSettings` 278 tests pass.

## References

- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0028: Standards-first IMAP/SMTP roadmap
- ADR-0034: Offline retention, search, and notification hardening
- ADR-0044: Read-only cached-attachment enumeration seam
- ADR-0045: Message copy and raw-source seam
- Issues #257 (storage), #259 (attachment/search-folder power tools), #262 (context-menu honesty)


## Implementation update (2026-09-05): local Smart View conditions

Saved message views now store an optional condition group with all/any
matching. Legacy predicates still decode and migrate into editable conditions,
including false booleans and folder scope. Supported conditions use existing
header metadata and source IDs; mailbox/folder choices never use display names
as identity. The read-only `MailBackend.cachedMessageHeaders(in:sourceID:)`
seam returns complete cached header candidates without connecting, fetching,
or applying ordinary search result limits. Backends without an implementation
report unsupported enumeration. No external network behavior is added.

Saved message views enumerate source-scoped cached headers for each cached
folder in the active profile. IMAP includes the local index and header cache
without its ordinary 50-result search cap. Gmail reads actual label memberships
from the local store instead of testing only a primary folder. Sent and Trash inclusion is explicit
for new views. Duplicate message IDs from label memberships produce one row,
preferentially retaining a membership that satisfies the saved condition. The
row retains all cached membership IDs so all/any and negative folder rules
remain accurate. Sent/Trash exclusions also inspect reserved system labels.
Attachment views retain their separate metadata query path.

Mail and Settings share the same editor and visibility/order panel. Built-in
and custom definitions retain their positions when hidden. Users can hide the
entire sidebar section and restore it from Settings.

## Implementation update (2026-09-06): complete IMAP search collection

Explicit ordinary IMAP search uses the existing page-returning provider operation
for every folder in scope, in 50-header requests. It no longer truncates the final
result collection to 50. Legacy nonpaged ordinary adapters keep their 200-candidate
request bound and fail visibly when that limit is reached, since they cannot
prove completion without a cursor. The production connector supplies the paged
operation. The pre-existing legacy attachment path remains unchanged.
Empty intermediate pages still follow their continuation; repeated cursors fail
visibly, duplicate source-qualified IDs collapse, and cancellation after the
final network response prevents publication. Ordinary search does not fetch MIME
sources. Attachment predicates retain ADR-0060's explicit source-inspection path.

A cache hit does not establish complete server coverage. Online cache-then-server
search therefore consults the server even when cached matches exist. Cache-only
search stays local and returns the full cached match collection; existing cache
fallback when server search cannot begin remains intact. Failures after a server
page or folder has already been searched report incomplete search instead of
silently returning cached results. Richer coverage reporting for the initial
unavailable-server fallback still needs the progressive-result contract.

The array-returning search contract still collects all pages before presenting
its final response. Progressive presentation, result pagination in the UI, richer
cache-coverage reporting, and bounded document-content indexing remain issue #28
work. This correction does not establish their completion or change the metadata-
first All Attachments behavior.
