# Security posture

Brev treats all message content and all server responses as **untrusted
input**: an email body, header, attachment, or IMAP/SMTP/ManageSieve response
may be attacker-controlled. This document records the defenses that enforce that
stance and where they live, so changes near them get the scrutiny they need.

This is a living record of audited properties, not a vulnerability-disclosure
policy. It reflects an audit of the surfaces below; it is not a guarantee of
absence of bugs.

## Rendering untrusted message HTML

`packages/BrevMail/Sources/BrevMail/HTMLBodyWebView.swift`

- **Scripting disabled** — `prefs.allowsContentJavaScript = false`.
- **Remote subresources blocked, fail-closed** — a `WKContentRuleList` blocks
  every `^https?://` subresource. When the blocker can't be compiled and the
  user hasn't allowed remote content, `HTMLBodyLoadPlan.resolve` renders a
  "remote content blocked" placeholder instead of the original HTML, so trackers
  can't leak (`HTMLBodyLoadPlan`).
- **Navigation is locked down** — only the initial `loadHTMLString` and explicit
  user link taps are permitted; auto-redirects and form submissions are
  cancelled.
- **Dangerous link schemes are dropped** — `MessageLinkSchemePolicy` rejects
  `javascript:`, `vbscript:`, `data:`, `file:`, `blob:`, `about:`, `jar:`,
  `view-source:`, and schemeless links before any link reaches the OS opener.
  Enforced at the single `HTMLBodyWebView` chokepoint so every render path is
  covered.
- **Inline CID images are sanitized** — `MessageInlineCIDRenderPolicy` inlines
  `cid:` parts as `data:` URIs whose MIME type is constrained to `image/*` with
  a safe character set (falling back to `image/png`), so the MIME type can't
  break out of the attribute.

## Confidentiality of outgoing mail (E2EE)

`packages/BrevBackend/Sources/BrevBackend/IMAPSMTPBackend.swift`, ADR-0021

- **Fail-closed** — a message the user asked to sign/encrypt is never silently
  downgraded to plaintext. `preparedOutboundData` throws when the crypto engine
  is missing or key resolution fails, before any SMTP submit, and the *prepared*
  (encrypted) bytes — not the plaintext — are what gets submitted and saved as
  the Sent copy.
- **Not retried as plaintext** — `shouldQueueOfflineMutation` returns `false` for
  the outbound-crypto error types, so a failed secured send surfaces immediately
  rather than sitting in the offline queue.

## Injection and traversal

- **No SQL injection** — the sync store uses parameterized prepared statements
  (`?` + `sqlite3_bind_*`) for all server-supplied data; writes are wrapped in
  `BEGIN IMMEDIATE`/`COMMIT`/`ROLLBACK`, and `PRAGMA user_version` migrations
  refuse to open a newer-than-known schema
  (`packages/BrevSyncEngine/.../SQLiteSyncStore.swift`).
- **No path traversal in attachment names** — staged attachments are keyed by a
  hex-encoded id (`IMAPDraftStagingStore.fileKey`); download save names go through
  `MessageAttachmentDownloadFilenamePolicy.safeFilename`, which replaces `/`, `:`,
  `\`, and control characters and rejects `.`/`..`.

## Account autodiscovery

`packages/BrevBackend/Sources/BrevBackend/MozillaAutoconfig.swift`,
`MailAutodiscovery.swift`, ADR-0028

- **HTTPS-only probes**, and discovered servers with a `plain` (no-TLS) socket
  type are **rejected** so discovery never downgrades credential transport.
- **XXE-safe** — the autoconfig `XMLParser` leaves external-entity resolution at
  its safe default (off).
- Discovered settings are **user-confirmed** before saving (a "Test connection"
  step), per ADR-0028.

## Gmail REST transport and account cleanup

`packages/BrevGmail/Sources/BrevGmail/GmailAPITransport.swift`

- Gmail URL path components use strict RFC 3986 encoding, so provider IDs cannot
  inject path separators, queries, fragments, or percent escapes.
- Only idempotent requests retry, with a bounded exponential backoff and the
  provider's `Retry-After` delay when present. Draft writes and sends never
  retry after explicit post-dispatch evidence; their local state remains
  available for reconciliation.
- OAuth refresh failures preserve the distinction between revoked credentials
  (reauthentication) and transient endpoint failures (retryable). Provider
  errors are mapped to the neutral backend authentication state before they
  reach session restore.
- Gmail account removal deletes canonical SQLite records and cached content
  before clearing credentials. A cleanup failure leaves metadata and tokens in
  place so the user can retry; pending-mutation cleanup failures are surfaced
  rather than swallowed.

## Denial-of-service bounds on untrusted streams

`packages/BrevBackend/Sources/BrevBackend/IMAPSessionClient.swift`,
`MailTransportLimits.swift`

- **Literal byte counts are capped** (`IMAPSessionClient.maxLiteralByteCount`,
  512 MiB) so an absurd `{N}` can't drive an unbounded read.
- **Protocol line length is capped** (`MailTransportLimits.maxLineByteCount`,
  8 MiB) on the IMAP and ManageSieve transports so a terminator-less stream
  can't grow the read buffer without bound.
- **SMTP reply collection is bounded** (`MailTransportLimits`): a single
  multiline reply may contain at most 128 lines and 64 KiB of UTF-8 text,
  preventing a server from making capability or command-response parsing
  retain unbounded continuation data.

## Privacy / telemetry

No telemetry or crash-reporting libraries are linked; outbound network surfaces
are opt-in and enumerated in `PRIVACY.md` and ADR-0006, and enforced by
`scripts/privacy-audit.sh`.

## Reporting a problem

There is no published security contact yet. Until one exists, report suspected
vulnerabilities to the maintainer privately rather than in a public issue.
