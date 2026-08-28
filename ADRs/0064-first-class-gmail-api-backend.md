# ADR-0064: First-class Gmail API backend

- **Status:** Accepted
- **Date:** 2026-08-25
- **Deciders:** Henrik
- **Amends:** ADR-0028, ADR-0057, ADR-0063

## Context

Brev currently supports Gmail and Google Workspace through the standards-first
IMAP/SMTP backend. Google OAuth produces an XOAUTH2 credential, Gmail folders
are exposed through IMAP Special-Use, and `X-GM-LABELS` provides basic label
display and mutation.

That path is a sound compatibility fallback, but it cannot provide a fully
Gmail-native model:

- IMAP UIDs are scoped to one folder, while Gmail message IDs are stable across
  the whole account.
- Gmail labels are many-to-many projections, not folders containing independent
  message copies.
- Gmail thread IDs differ from Brev's RFC 5322 reply-chain inference.
- Gmail search syntax, history cursors, label colors and visibility, drafts,
  send-as identities, and provider quota/policy errors do not map cleanly onto
  the IMAP session implementation.
- The existing `BrevSyncEngine` schema is keyed by folder, UIDVALIDITY, UIDNEXT,
  and HIGHESTMODSEQ. Gmail API synchronization is keyed by account-wide message
  IDs, label IDs, thread IDs, and `historyId`. Reusing the IMAP schema directly
  would duplicate messages across labels and make delta reconciliation
  incorrect.

ADR-0028 intentionally deferred provider APIs until the standards backend was
usable. That condition is now satisfied. ADR-0057 added the smallest useful
Gmail label seam over IMAP and explicitly deferred Gmail account-wide identity,
threading, search, label management, and label-only delta sync.

The request is now to make Gmail and Google Workspace feel native while
preserving generic IMAP/SMTP support for every other provider.

This decision is also constrained by Google's current platform rules:

- Gmail API traffic goes to `gmail.googleapis.com` and is a new external
  network dependency under ADR-0006.
- Gmail API installed-app clients must use the existing platform-specific
  public OAuth clients and PKCE from ADR-0063.
- Gmail scopes are sensitive or restricted. `https://mail.google.com/` is
  required for immediate permanent deletion and IMAP/SMTP XOAUTH2; narrower
  Gmail API scopes cannot perform that operation.
- External Testing projects have test-user and token-lifetime limits.
- Gmail `watch` requires Cloud Pub/Sub and a server or pull subscriber. Google
  recommends poll-based synchronization for user-owned installed devices.
- Gmail Workspace delegated-mailbox administration requires service-account
  domain-wide delegation and is not available to an ordinary native OAuth
  client.

## Decision

### 1. Add a dedicated `BrevGmail` package

Brev will add `packages/BrevGmail` as a peer of `BrevBackend` and
`BrevSyncEngine`.

`BrevGmail` will contain:

- `GmailAPIBackend`, a `MailBackend` adapter;
- an injected `GmailAPITransport` that owns Gmail REST request/response
  semantics;
- a Gmail credential provider using the existing Keychain token store and
  single-flight refresh behavior;
- a Gmail-specific canonical SQLite store;
- a full-sync and `historyId` reconciliation module;
- provider extension adapters for labels, send-as identities, signatures,
  sync health, offline mutations, and scheduled send where supported.

`BrevBackend` remains the provider-neutral interface package and must not import
`BrevGmail`. `BrevMail` and app views continue to depend only on `MailBackend`,
capabilities, provider-neutral domain models, and extension interfaces.

The account lifecycle is wired through provider-neutral app-factory closures:
`BrevGmail` persists non-secret `GoogleOAuthAccountConfiguration` metadata in
UserDefaults, keeps OAuth tokens in the existing Keychain-backed `TokenStore`,
and uses the existing single-flight `OAuthTokenRefresher` for Gmail REST
access. Native provisioning writes token and metadata transactionally and
restores both when initial backend connection fails. Restore and removal are
selected by the persisted `gmail-api` backend identifier; all other accounts
continue through the IMAP/SMTP connector. Removing a native Gmail account
clears metadata, Keychain credentials, canonical SQLite records, and cached
content together. The macOS and iOS targets construct the standard connector
and inject these closures without exposing `BrevGmail` to views.

### 2. Keep IMAP/SMTP as an explicit fallback

New Google sign-ins will create a Gmail API account when the Gmail API
authorization and profile checks succeed. Generic IMAP/SMTP remains available
as an explicit fallback for:

- accounts blocked by Workspace administrator policy;
- environments where the Gmail API is unavailable but IMAP access is allowed;
- existing Gmail accounts already configured as IMAP/SMTP;
- manual app-password setups.

Brev will not silently switch an existing `imap-smtp:<email>` account to the
API backend. Migration is an explicit, reversible flow: connect and complete
the Gmail API initial sync, preserve local settings, then retire the old IMAP
cache only after success.

### 3. Use Google account identity, not email, as the durable key

The Gmail API account ID will be `gmail-api:<google-subject>`, using the stable
Google OIDC subject returned by the verified token-bound identity response.
Email and hosted-domain metadata remain account attributes, not durable keys.

The OAuth result and account configuration will persist:

- verified Google subject;
- current email and optional hosted domain;
- granted scope set;
- OAuth client platform;
- provider mode (`gmail-api` or `imap-smtp` fallback).

### 4. Make Gmail message identity account-wide

The Gmail store will use the following canonical relationships:

- `messages(accountID, gmailMessageID, gmailThreadID, metadata, raw/body cache)`;
- `labels(accountID, gmailLabelID, name, type, visibility, color, counts)`;
- `message_labels(accountID, gmailMessageID, gmailLabelID)`;
- `account_state(accountID, email, historyID, lastFullSyncAt, lastDeltaSyncAt)`;
- provider-specific draft and pending-mutation mappings.

`MessageHeader.id` maps to the Gmail message ID. `MessageHeader.threadID` maps
to the Gmail thread ID. `Folder` values are projections of Gmail labels and
system roles. Unified Inbox and search deduplicate by account plus Gmail
message ID, not by folder membership.

The IMAP folder/UID cache is not reused for Gmail API state.

### 5. Synchronize with full sync plus `historyId`

Initial synchronization will:

1. load the Gmail profile and label catalog;
2. page message IDs, bounded by the user's retention and initial-sync policy;
3. fetch message metadata/body in batches no larger than 50 requests;
4. write canonical messages and label relationships transactionally;
5. persist the newest `historyId` only after the transaction commits.

Incremental synchronization will use `users.history.list` in chronological
order. An expired or invalid history cursor (HTTP 404) triggers an atomic full
reconciliation. Foreground activation, background-refresh opportunities, and
manual refresh use the same reconciler.

Gmail Pub/Sub `watch` is deferred until Brev has an explicit server or pull
subscriber architecture. Brev will not claim account-wide push from the native
client alone.

### 6. Expose Gmail behavior through capabilities

`GmailAPIBackend` will advertise only capabilities it can satisfy, including:

- `.providerAPI`;
- `.oauthAuth`;
- `.serverSideSearch`;
- `.serverSideThreading`;
- `.labels`;
- `.historyDeltaSync`;
- provider sync health;
- folder/label lifecycle capabilities as each slice ships;
- send-as and server-signature extended capabilities when loaded.

Provider-specific details are exposed through provider-neutral extension
interfaces. Views must not type-check `GmailAPIBackend`.

A label-catalog extension will expose label IDs, display names, system/user
type, hierarchy, visibility, colors, counts, and allowed mutations. Existing
`MessageLabelManaging` remains the message-label mutation interface.

### 7. Deliver Gmail-native semantics

The Gmail backend will map:

- Inbox, Starred, Important, Sent, Drafts, All Mail, Spam, and Trash to their
  native Gmail roles and names;
- archive to removal of the `INBOX` label;
- move to an add/remove label operation with an explicit destination;
- trash/restore to Gmail trash/untrash endpoints;
- permanent delete only when the granted scopes include
  `https://mail.google.com/`;
- unread/starred/important to Gmail system-label mutations;
- Gmail search text and structured predicates to the Gmail `q` language;
- drafts and send to Gmail API MIME/base64url operations;
- existing send-as identities and per-alias signatures to capability-driven
  compose choices.

System labels cannot be renamed or deleted. Unsupported Workspace admin
operations remain hidden or read-only with policy explanations.

### 8. Preserve offline and ambiguous-operation safety

The provider-neutral offline mutation kinds may be reused only where their
semantics are unambiguous. Gmail replay uses Gmail message and label IDs,
idempotent label modifications, typed policy/rate-limit errors, and surfaced
conflicts.

Send and draft operations preserve the existing uncertain-delivery rule: a
network failure after submission is not automatically retried unless the
provider response proves delivery did not occur.

### 9. Keep OAuth scope state explicit

The initial testing implementation may use the already configured
`https://mail.google.com/` grant because full Gmail semantics include immediate
permanent deletion and because the same test project supports the IMAP fallback.

The backend must persist and inspect the scopes actually granted. Permanent
delete and any settings surface are gated on granted scopes rather than assumed
from the requested set.

Before production verification, Brev will make an explicit release decision:

- retain `https://mail.google.com/` and justify immediate permanent deletion;
  or
- remove immediate permanent deletion and request the narrower
  `gmail.modify`/send scope profile.

No client secret is bundled. Platform-specific public clients and callback
validation remain governed by ADR-0063.

### 10. Extend privacy and diagnostics before shipping

ADR-0006 and `PRIVACY.md` will list Gmail API traffic, data categories,
retention, local cache behavior, account removal, and scope use. Gmail API
calls occur only after the user explicitly adds a Google account.

Errors are typed and user-safe:

- 401 / `invalid_grant` requests reauthentication;
- Workspace `domainPolicy` and admin enforcement become policy-disabled UI;
- 403/429 quota errors use bounded retry/backoff and sync-health disclosure;
- 5xx errors use exponential backoff with jitter;
- no token, message content, query, or raw provider body is logged.

## Rationale

### Chosen: dedicated Gmail backend and store

This keeps the provider-neutral `MailBackend` seam deep: views learn no new
provider type, while Gmail's message identity, labels, history, drafts, and
error model remain local to one implementation. It gives Gmail callers high
leverage without spreading Gmail branches across the app.

### Rejected: inject Gmail REST operations into `IMAPSMTPBackend`

This produces one shallow dual-protocol backend with incompatible message IDs,
sync cursors, cache keys, mutation semantics, and failure modes. Gmail details
would leak into generic IMAP behavior and make both providers harder to test.

### Rejected: reuse `BrevSyncEngine` unchanged

Its store is intentionally IMAP-oriented. Folder-scoped UIDs and UIDVALIDITY
cannot represent Gmail account-wide messages and many-to-many labels without
duplication. A future provider-neutral search-index seam may be shared, but the
canonical Gmail store remains Gmail-specific.

### Rejected: Gmail API sidecar over an IMAP primary backend

A sidecar can improve search or labels quickly, but it creates two authorities
for message state and delivery. The requested outcome is a native Gmail
provider, not a partially overlaid IMAP account.

### Deferred: direct Gmail Pub/Sub push

Gmail `watch` publishes to Cloud Pub/Sub and requires a server or pull
subscriber plus daily renewal and missed-notification recovery. Poll-based
history sync is the supported installed-device baseline and fits Brev's current
local-only architecture.

## Consequences

### Accepted

- A new top-level package and backend increase the package graph.
- Gmail has a separate canonical cache and migration path from IMAP.
- Gmail consumer and Workspace accounts gain native identity, threading,
  labels, search, drafts, send-as, and history semantics.
- Generic providers continue using the IMAP/SMTP backend unchanged.
- Existing UI receives new capability-driven label/search/account states but no
  concrete Gmail type.
- The implementation is delivered as vertical slices, each independently
  testable and revertible.
- The Google Cloud External/Testing project remains the live QA environment.

### Risks

- Gmail API restricted-scope verification and annual security assessment can
  delay public release. Mitigation: document scope use early and make permanent
  deletion scope-gated.
- Large initial syncs can hit per-user quota and bandwidth limits. Mitigation:
  bounded concurrency, batches no larger than 50, retention-aware sync, jittered
  retry, and visible sync health.
- History notifications can be delayed or cursors can expire. Mitigation:
  periodic polling and full-resync recovery.
- Migration could duplicate accounts or lose local preferences. Mitigation:
  explicit transactional migration with rollback and stable account aliases.
- Gmail and Workspace policies vary by tenant. Mitigation: typed policy states,
  consumer + Workspace QA, and no promise of delegated mailbox administration
  without domain-wide delegation.
- A second cache implementation creates maintenance cost. Mitigation: keep its
  interface small, share only provider-neutral MIME/search utilities, and test
  through `MailBackend` contracts.

## References

- ADR-0001: Backend abstraction for multi-provider support
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Standards-first IMAP/SMTP roadmap
- ADR-0029: IMAP/SMTP backend foundation
- ADR-0030: Full IMAP sync and cache engine
- ADR-0052: Client-side IMAP threading
- ADR-0057: Gmail labels over IMAP
- ADR-0067: Native OAuth public-client secret posture
- ADR-0063: Platform-specific Google native OAuth clients
- [Gmail API REST reference](https://developers.google.com/workspace/gmail/api/reference/rest)
- [Synchronize clients with Gmail](https://developers.google.com/workspace/gmail/api/guides/sync)
- [Gmail API push notifications](https://developers.google.com/workspace/gmail/api/guides/push)
- [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Gmail API errors](https://developers.google.com/workspace/gmail/api/guides/handle-errors)
- [Gmail API quotas](https://developers.google.com/workspace/gmail/api/reference/quota)
- [Google OAuth app verification FAQ](https://support.google.com/cloud/answer/13463817)
