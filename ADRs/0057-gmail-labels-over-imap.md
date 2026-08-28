# ADR-0057: Gmail labels over IMAP (X-GM-EXT-1)

- **Status:** Proposed
- **Date:** 2026-08-15
- **Deciders:** Henrik
- **Amends:** ADR-0022, ADR-0029, ADR-0030

## Context

Gmail OAuth is a headline sign-in path (ADR-0028), but Brev treated
Gmail as a folder-only IMAP server. Gmail exposes labels through the
`X-GM-EXT-1` IMAP extension: `X-GM-LABELS` is a FETCH attribute and a
`STORE` target, system labels are backslash atoms (`\Inbox`, `\Sent`,
`\Important`, `\Starred`), and every user label also appears as a
mailbox whose path is the label name.

`BackendCapabilities.labels` already existed (ADR-0001, ADR-0019) but
was advertised only by `MockBackend`. Nothing in `IMAPSessionClient`
parsed the server's CAPABILITY list; extensions were probed by trying a
command and degrading on failure. That does not work for a FETCH
attribute: a non-Gmail server rejects the whole `FETCH` when
`X-GM-LABELS` is present, so it must be sent strictly behind a
capability check.

## Decision

1. **Passive capability detection.** `IMAPSessionClient` records
   `IMAPServerCapabilities` from lines it already reads: the greeting
   `* OK [CAPABILITY …]`, the tagged `OK [CAPABILITY …]` on `LOGIN` /
   `AUTHENTICATE`, and any untagged `* CAPABILITY` returned by the
   STARTTLS pre-check. No extra round trip is issued; scripted-transport
   tests stay byte-identical. Gmail (and Dovecot-family servers) send
   the response code on the authentication `OK` (RFC 3501 §7.1).
2. **Fetch.** When the server advertised `X-GM-EXT-1`, the listing
   FETCH attribute set becomes `FLAGS ENVELOPE X-GM-LABELS BODY.PEEK[…]`.
   `IMAPMessageListing.labels` carries the parsed list (quoted strings
   unescaped, modified UTF-7 decoded, system labels keep their
   backslash). `IMAPMessageListingPage.supportsGmailLabels` tells the
   backend what the server said.
3. **Advertise `.labels` dynamically.** `IMAPSMTPBackend.capabilities`
   is now computed: the construction-time set plus `.labels` once a
   listing reported `X-GM-EXT-1`. The detection is persisted as
   `IMAPFolderCacheSnapshot.supportsGmailLabels` (additive,
   `decodeIfPresent`) so cache-first startup (ADR-0050) advertises it
   before the first live listing.
4. **Domain model and store.** `MessageHeader.labels: [String]` is
   additive: decoded with `decodeIfPresent ?? []`, encoded only when
   non-empty so pre-existing header-cache JSON and the SQLite
   `header_json` blob (ADR-0030) stay byte-identical. The sync-store
   schema version does not change; a legacy row round-trips with an
   empty label list.
5. **Mutation seam.** Label writes go through a new
   `MessageLabelManaging` extension service
   (`extensionService(MessageLabelManaging.self)`), not a new
   `MailBackend` requirement. `IMAPSMTPBackend` offers it only when a
   `setMessageLabels` operation was injected; the operation renders
   `UID STORE <set> ±X-GM-LABELS (…)`. Failures that would queue a
   flag change also queue `PendingMutation.Kind.setLabels` (ADR-0022)
   for replay.
6. **UI.** Rows and the reader show user labels as theme-coloured
   chips; system labels are hidden because folders and flags already
   express them. A "Labels" context-menu submenu, gated on
   `.labels` and the extension service, toggles candidate labels
   derived from the custom (non-`[Gmail]`) folder list.

## Rationale

- Passive detection is the smallest change that keeps every existing
  scripted IMAP test valid and adds zero network cost.
- An extension service keeps the already-large `MailBackend` protocol
  stable and lets `MockBackend`/other providers opt in later without a
  protocol-wide default.
- Encoding `labels` only when present avoids a cache/store migration
  for the overwhelmingly common non-Gmail account.

## Consequences

- Gmail users see labels and can add/remove them from the message
  context menu; the change survives offline via the mutation queue.
- Servers that do not include `[CAPABILITY …]` in the authentication
  `OK` and do not send it in the greeting are not detected. Gmail
  does; an explicit fallback `CAPABILITY` command is a follow-up if a
  Gmail-compatible relay ever needs it.
- Not in this slice: `[Gmail]/All Mail` folder mapping, label-driven
  virtual folders, `X-GM-THRID`/`X-GM-MSGID`, CONDSTORE delta-sync of
  label-only changes (only `FLAGS` are refreshed today), a label
  management/creation UI, and toolbar / menu-bar label commands.
- `WorkflowStateSyncPresentation` treats `.labels` as "categories are
  provider-backed"; that mapping predates this ADR and now applies to
  Gmail accounts too. Revisit with the workflow-state work (ADR-0043).

## References

- ADR-0001 capability matrix; ADR-0028 invariant 2
- ADR-0019 flag colors (why labels and flags stay distinct)
- ADR-0022 offline mutation queue
- ADR-0029 / ADR-0030 IMAP backend and sync store
- Gmail IMAP extensions: `developers.google.com/gmail/imap/imap-extensions`
