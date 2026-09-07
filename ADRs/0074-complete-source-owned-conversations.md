# ADR-0074: Complete source-owned conversations

- **Status:** Accepted
- **Date:** 2026-09-07
- **Deciders:** Henrik
- **Amends:** ADR-0020 and ADR-0052
- **Tracking:** #28, acceptance area 3

## Context

The reader derives membership from loaded headers in the current folder. That
omits Sent/Archive members and older unloaded replies. ADR-0052 deliberately
limits resolution to one folder and identifies a cross-folder index as a separate
decision. The existing search pagination fixes do not change that boundary.

Brev needs complete conversations without coupling the reader to provider models,
scanning message bodies, merging unrelated subjects, or widening action targets.
Profiles continue to control visible mailboxes; conversation discovery must never
cross the selected account/mailbox source.

## Decision

1. Add an optional provider-neutral conversation extension owned by `BrevBackend`.
   It accepts a source-owned anchor locator and exposes cached snapshots plus
   cancellable related-header loading. Snapshots carry members, actual folder
   locators, selected anchor identity, coverage, excluded/unavailable folders and
   a continuation only when the provider supports resumption. Views see plain
   Swift values and capabilities, never Gmail DTOs or storage objects. Cached
   lookup is gated by the offline-capable `.cachedConversations` extended flag;
   it does not authorize remote discovery.
2. Build the cached conversation from all indexed folders in the owning mailbox,
   including Inbox, Sent and Archive. Keep provider identity and folder membership
   in the provider's existing local store, rather than adding another database or
   package. IMAP indexes parsed Message-ID/In-Reply-To/References relationships;
   Gmail indexes native thread ID and many-to-many label membership. Add versioned
   metadata migrations and rebuild from existing headers where possible.
3. Gmail's remote path uses `users.threads.get` in metadata format, selecting only
   the headers needed for display and reply linkage. It must not use full bodies
   or attachment endpoints merely to discover members. Deduplicate Gmail label
   memberships by account-wide message ID and retain the selected membership for
   folder context and actions. Enforce existing response-size/auth/retry bounds.
4. IMAP uses bounded UID SEARCH HEADER queries over known reply identifiers and
   fetches matching ENVELOPE/FLAGS/UID plus `BODY.PEEK[HEADER.FIELDS (REFERENCES)]`.
   Expand the discovered graph until its identifier frontier is exhausted across
   eligible folders. HEADER search is a candidate search: parse returned IDs and
   verify exact relationships locally before including a member. Do not use
   subject-only matching or arbitrary body/full-folder downloads as fallback.
5. Missing parents, cycles, ambiguous IDs, duplicate physical copies and legacy
   records with absent References are explicit cases. Distinct IMAP UID locators
   must not disappear merely because Message-ID or subject is equal. Ambiguous
   identifiers must not silently merge unrelated mail. Thread-root changes when
   an older ancestor is found must not change the selected anchor message.
6. Cached lookup adds no network request. Initially, remote discovery requires
   the reader's explicit **Load related mail** action. Its consent can also enable
   automatic related-header lookup on future conversation opens for that account;
   that preference defaults off and is reversible in Mailbox View settings. The
   consent explains that all eligible folders in this mailbox may be searched,
   including folders not currently synced. This does not enable background-wide
   scans, cross-profile/account lookup, body prefetch, or automatic mark-as-read.
7. Search all accessible, selectable folders in the owning mailbox; exclude Spam
   and Trash by default, with explicit inclusion available. Report exclusions and
   access failures. Respect offline mode and current source retirement. Ordinary
   sync remains governed by folder-sync preferences; explicit related lookup is
   separate from silently enabling sync on another folder.
8. Keep the selected message/body visible while cached and remote members arrive.
   Show compact cached/loading/partial/complete-for-scope feedback, Retry and an
   optional Continue action. A budget/size limit or failed folder never produces
   a complete flag. Finite request batches and concurrency are bounded; defaults
   are measured against representative accounts before claiming performance.
9. Preserve list navigation independently of reader-member selection. Selecting a
   Sent reply while viewing Inbox must open that reply and retain its actual
   source/folder/UIDVALIDITY context. Existing actions resolve the selected member's
   locator, not the sidebar's folder, and do not silently expand to every newly
   discovered conversation member. Explicit whole-conversation actions are a
   separate command/acceptance concern.
10. Give each lookup one owner and request generation. Cancellation, a new anchor,
    profile/account switch, folder generation change, or account removal rejects
    stale callbacks and local writes. Drain local metadata commits before purge;
    do not wait indefinitely for remote requests or permit old replies to refill
    a replacement account. Persist metadata only through provider-owned stores.

## Rationale and alternatives

- **Keep the loaded-folder filter:** preserves current simplicity but cannot meet
  the user's cross-folder or unloaded-reply requirements.
- **Scan every folder/body on each click:** too expensive and violates the
  metadata-first and explicit-network boundaries. Use indexed edges and targeted
  provider requests instead.
- **Match subjects:** joins unrelated conversations and can hide mail. Reply
  identifiers/native thread IDs are the authoritative membership signals.
- **Require IMAP THREAD:** not portable across standards servers and cannot be
  the sole offline model. It may become an optional optimization later.
- **Automatically fetch without consent:** conflicts with the current explicit
  opt-in rule. A per-account consent supports normal automatic conversation
  behavior after a clear choice, while cached views remain immediately usable.
- **Reuse message-list navigation storage for every related message:** would
  inject Sent/Archive members into Inbox state and risk applying actions to the
  wrong folder. Keep conversation snapshots and list windows distinct.

## Consequences and delivery gates

Henrik accepted this ADR in the implementation thread on 2026-09-07. This
authorizes the architectural direction, not merge,
release, broader OAuth grants, or live mail mutations. Before adding the remote paths, record the new
related-header requests/consent in ADR-0006 and PRIVACY.md.

Implementation proceeds through provider-neutral snapshot/locator tests, cached
membership/index migrations, Gmail metadata loading, IMAP targeted discovery,
reader/selection/action integration, then native and real-account acceptance.

Required verification includes:

- Inbox/Sent/Archive chains, absent parents, References-only links, cycles and
  older replies beyond all loaded list pages; no subject-only merging.
- Same IDs across accounts, duplicate Gmail labels, ambiguous/reused RFC IDs,
  duplicate IMAP copies and UIDVALIDITY changes; no wrong-source action.
- Selected reply and body remain visible through graph expansion and root changes.
- Every requested folder is accounted for; skipped/failed folders and request
  budgets remain partial, with no silent finite-result cap.
- Cache-first/offline behavior, consent off/on/revocation, source switching,
  cancellation and account purge/re-add during a delayed response.
- No BODY[]/full Gmail message/attachment downloads or Seen mutations for discovery.
- Native light/dark, accessibility and compact layout checks; measured first-paint,
  selection latency, total discovery time, memory and network requests on large
  IMAP and Gmail accounts. CI/unit tests do not substitute for live acceptance.

## Risks and limits

IMAP discovery can be expensive on servers without efficient header search;
missing or corrupt reply headers can make global completeness unknowable. Return
partial/unsupported coverage and preserve the original message instead of
silently guessing. Cache eviction must remove/reconcile index edges. Provider
thread semantics can differ from RFC linkage; the common UI reports membership
and coverage without pretending both algorithms are identical.

## References

- [ADR-0020](0020-thread-conversation-view.md): loaded-folder reader boundary
- [ADR-0052](0052-client-side-imap-threading.md): local reply-link resolution
- [ADR-0028](0028-mail-provider-architecture.md): source/provider invariants
- [ADR-0041](0041-search-folder-and-attachment-search-scope.md): search scope
- [Gmail threads.get](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/get): metadata format and header selection
- [RFC 9051](https://www.rfc-editor.org/rfc/rfc9051.html): UID SEARCH HEADER and selective PEEK fetching
- Current integration points: `BrevMailRootView.threadHeadersForSelection`,
  `ThreadMessageDerivation`, `MessageThreadResolver`, `MailLocalSearchIndex`,
  `IMAPSMTPBackend`, `GmailAPIBackend` and their provider-owned stores.


## Implementation progress — 2026-09-08

The SyncEngine v5 migration adds a reply-identifier table in the existing SQLite
cache. Header upserts maintain it atomically; foreign-key cascades cover expunge,
folder invalidation and account clearing. Migration backfills Message-ID and
In-Reply-To from v4 header records one row at a time, preserving original-byte
provenance. Backfill uses the existing `rfcMessageID` legacy fallback; statement
preparation is shared across each batch/migration. Malformed linkage does not
prevent the original header being cached; control/NUL characters cannot enter
identifier bindings.

The local index walks matching identifiers only. A per-identifier candidate cap
and a total traversal budget produce `partial`, never complete coverage. Known
folder generations are checked against cached UIDVALIDITY; missing generations
remain unknown and are not evidence authorizing a remote UID action. No network
calls or automatic header enrichment are introduced by this step. Persisted
References ingestion, provider extension wiring and reader/actions remain pending.
