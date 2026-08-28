# ADR-0052: Client-side IMAP threading

- **Status:** Accepted
- **Date:** 2026-08-12
- **Deciders:** Henrik

## Context

`MessageHeader.threadID` names the conversation a message belongs to. The
message list groups rows by it (ADR-0020), the reading pane builds
`ThreadConversationView` from it, and the unified inbox groups by it per
source (ADR-0017).

For a standards IMAP account none of that ever engaged. `IMAPSMTPBackend` set
`threadID` to the message's own `Message-ID`, so every message was a
conversation of one, and the threading UI was additionally gated on
`.serverSideThreading` — a capability only `ProviderHTTPBackend` and
`MockBackend` advertise. Threading therefore worked in mock builds and against
one provider, and silently did nothing on the accounts Brev is actually built
for (ADR-0028).

Plain IMAP has no thread identity. RFC 5322 reply links are what a mail client
has to work with, and `THREAD` (RFC 5256) is an optional extension many servers
do not implement, so a server-side answer cannot be relied on.

## Decision

1. **Threading is derived locally, from reply links.** `MessageHeader` gains
   `messageID` (this message's own `Message-ID`) and `inReplyTo` (RFC 5322
   `In-Reply-To`). `MessageThreadResolver` joins messages that reference each
   other with union-find and rewrites `threadID` to name the conversation.

2. **No extra network cost.** `In-Reply-To` and `Message-ID` are both fields of
   the IMAP `ENVELOPE`, which every message listing already fetches. Parsing
   `envelope[8]` costs nothing on the wire.

3. **Absent parents still group their replies.** A referenced message that is
   not in the fetched set — sent from another client, filed in another folder —
   becomes a node in the graph anyway, so two replies to it land in one
   conversation instead of splitting. Conversations are named after the oldest
   message actually present, never after an absent one.

4. **`threadID` stops being a Message-ID.** It is now an ancestor's Message-ID
   for every message except a thread's first. Outgoing replies must not
   reference it: `MessageHeader.rfcMessageID` reads the new `messageID` field,
   falling back to the old `threadID` reading only for headers cached before
   this ADR.

5. **Resolution runs once, on the way out of the backend.** Every listing path
   — live FETCH, header cache, search index, offline fallback — funnels through
   one private `messages(in:pageToken:recordsActiveFolder:)`, which resolves
   against the union of the page and the folder's cached headers. A reply that
   arrives on page 2 therefore joins the message it answers on page 1.
   Resolution is pure and idempotent: it reads `messageID`/`inReplyTo` and
   never its own output, so applying it to already-resolved headers is a no-op.

6. **A capability, not a type check.** `IMAPSMTPBackend` advertises
   `.clientSideThreading` (a `BackendExtendedCapabilities` flag — the 32-bit
   `BackendCapabilities` set is fully allocated). Threading UI branches on
   `MailBackend.groupsMessagesIntoThreads`, which is true for either flag, so a
   server-threaded provider and a standards IMAP account behave identically and
   ADR-0028 invariant 2 still holds.

## Rationale

Union-find over reply links, rather than the fuller JWZ algorithm: JWZ's extra
machinery is mostly its subject-based fallback, which merges unrelated mail
that happens to share a subject line ("Re: lunch"). A false merge hides a
message inside someone else's conversation, which is worse than a thread that
splits.

`References` is deliberately not read in this ADR. It would need an extra
`BODY.PEEK[HEADER.FIELDS (REFERENCES)]` on every listing, and it only adds
coverage where `In-Reply-To` chains have gaps that the absent-parent node does
not already bridge. If real mailboxes show split threads, adding it is a
contained follow-up: one more listing field, one more union per message.

Threading per folder, not per account, matches what the list shows and what
ADR-0020 already does client-side for `ThreadConversationView`. A thread whose
other half lives in Sent stays split; joining them means a cross-folder index,
which is its own decision.

Alternatives considered:

- **Server `THREAD` (RFC 5256).** Not universally implemented, returns a
  server-defined grouping Brev cannot reproduce offline, and would still need
  the local path as a fallback — two behaviours to keep identical.
- **Grouping in the view layer.** Would leave `threadID` meaningless in the
  domain model and duplicate the logic in every list that groups.
- **Persisting resolved thread ids.** Rejected as premature: resolution is a
  linear pass over headers already in memory, and a persisted id would need
  invalidation whenever the cache gains an older ancestor.

## Consequences

### Accepted

- Thread grouping, inline expansion, and `ThreadConversationView` work on every
  IMAP account, identically to a server-threaded provider.
- `MessageHeader` gains two optional fields. Both are `decodeIfPresent`, so
  header caches written before this ADR decode unchanged and simply thread as
  they did before until refreshed.
- Conversation ids can change as more of a thread loads: page 2 can reveal an
  older ancestor and rename the conversation. Grouping stays correct; only the
  opaque id moves.

### Risks

- **Servers that omit `Message-ID`.** Those messages get a private node key and
  can never merge into a thread — the same single-message behaviour as before.
- **Chains gapped in both directions.** A reply whose parent is absent *and*
  which shares no `In-Reply-To` with a sibling stays on its own until
  `References` is read.
- **Cost on large folders.** Resolution is O(n·α) over the folder's cached
  headers per page. Measured against the existing sort and filter passes this
  is noise, but a folder with tens of thousands of cached headers should be
  watched.

## References

- ADR-0001: Backend abstraction and capabilities
- ADR-0028: Roadmap and invariants (invariant 2, capability-driven UI)
- ADR-0017: Multi-source mail workspace
- ADR-0020: Thread conversation view
- ADR-0028: Standards-first IMAP/SMTP roadmap
- ADR-0029: IMAP/SMTP backend foundation
- `packages/BrevBackend/Sources/BrevBackend/MessageThreadResolver.swift`
