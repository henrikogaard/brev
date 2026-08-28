# Gmail API native provider specification

- **Status:** Approved for implementation
- **Date:** 2026-08-25
- **Target:** macOS 14+ and iOS/iPadOS 17+
- **Architecture:** ADR-0064
- **Related QA:** the related feature request provider onboarding matrix

## Problem Statement

Brev can authenticate Gmail and Google Workspace accounts through Google OAuth
and use IMAP/SMTP with basic Gmail labels. The account still behaves like a
generic IMAP mailbox: messages can duplicate across labels, conversations do
not use Gmail thread IDs, search lacks Gmail syntax, label metadata is partial,
and sync observes one IMAP folder rather than the account-wide Gmail history.

Gmail and Workspace users expect the app to preserve Gmail's identity,
conversation, label, archive, search, draft, send-as, policy, and synchronization
semantics without weakening the generic IMAP experience for other providers.

## Solution

Add a dedicated `BrevGmail` package whose `GmailAPIBackend` implements the
existing `MailBackend` interface. It uses Gmail API account-wide message IDs,
thread IDs, label IDs, Gmail search, drafts/send, and history synchronization.
It persists Gmail state in a canonical Gmail-specific store and presents
provider behavior through capabilities and provider-neutral extension
interfaces.

New Google sign-ins use Gmail API when authorization, profile, and initial sync
succeed. Existing Gmail-over-IMAP accounts remain unchanged until the user
chooses an explicit migration or re-adds the account. IMAP/SMTP remains the
fallback and the primary backend for non-Google providers.

## User Stories

1. As a Gmail user, I want to sign in with Google once, so that Brev connects
   without an app password.
2. As a Workspace user, I want my custom-domain Google account recognized as
   Google Workspace, so that I do not see generic IMAP branding.
3. As a user, I want the consent screen to explain the actual Gmail access Brev
   requests, so that I can make an informed choice.
4. As a user, I want a direct reauthentication action when Google revokes or
   expires access, so that I am not left with a passive sync error.
5. As a user, I want Inbox, Starred, Important, Sent, Drafts, All Mail, Spam,
   Trash, and my labels named like Gmail, so that the sidebar is familiar.
6. As a user, I want All Mail visible by default for Gmail accounts, so that I
   can reach archived messages without changing generic folder preferences.
7. As a user, I want nested user labels, visibility, and colors preserved, so
   that my existing Gmail organization appears in Brev.
8. As a user, I want system labels protected from invalid rename/delete actions,
   so that Brev never offers operations Gmail will reject.
9. As a user, I want to create, rename, recolor, show/hide, and delete user
   labels, so that label management is complete.
10. As a user, I want one message to appear as one message even when it has many
    labels, so that Inbox, All Mail, search, and Unified Inbox do not duplicate
    it.
11. As a user, I want Gmail conversations grouped by Gmail thread ID, so that
    threads match Gmail web and mobile.
12. As a user, I want label changes reflected everywhere immediately, so that
    counts, chips, search, and notifications stay consistent.
13. As a user, I want archive to remove Inbox without deleting the message, so
    that Brev behaves like Gmail.
14. As a user, I want Trash and Restore actions to use Gmail's native semantics,
    so that recovery matches Gmail.
15. As a user, I want permanent deletion available only when my granted scopes
    allow it, so that Brev does not pretend an operation succeeded.
16. As a user, I want Mark important/not important, Star/unstar, Spam/not spam,
    and read/unread to work on individual messages and selections.
17. As a user, I want bulk label actions in the normal message list and Unified
    Inbox, so that Gmail organization is not limited to a context submenu.
18. As a user, I want Gmail operators such as `from:`, `to:`, `cc:`, `subject:`,
    `label:`, `in:anywhere`, `is:important`, `is:starred`, `has:attachment`,
    `after:`, and `before:` to work in search.
19. As a user, I want Brev to explain recognized Gmail search operators, so that
    I understand whether search ran on Gmail or locally.
20. As a user, I want search results deduplicated by Gmail message ID, so that
    labels do not multiply results.
21. As a user, I want drafts created and updated through Gmail, so that drafts
    appear consistently across Gmail clients.
22. As a user, I want Gmail sends to use the correct thread and reply headers,
    so that sent replies remain in the expected conversation.
23. As a user, I want existing Gmail send-as aliases in the From picker, so that
    I can use identities already configured in Gmail.
24. As a user, I want the correct per-alias signature selected, so that compose
    matches Gmail settings.
25. As a user, I want attachment previews and downloads to use Gmail attachment
    IDs and the local cache, so that large messages remain responsive.
26. As a user, I want cache-first startup and offline reading for downloaded
    messages, so that Gmail remains useful without a connection.
27. As a user, I want offline label/read/archive/trash changes queued and safely
    replayed, so that reconnect does not lose intent.
28. As a user, I want ambiguous sends surfaced rather than automatically retried,
    so that Gmail does not receive duplicate mail.
29. As a user, I want account-wide incremental sync, so that changes from Gmail
    web and other devices appear without scanning every label.
30. As a user, I want an expired Gmail history cursor to recover through a full
    reconciliation without losing local pending work.
31. As a user, I want sync health to show rate limiting, administrator policy,
    reauthentication, full-resync, and pending mutation states distinctly.
32. As a Workspace user, I want administrator-blocked scopes explained clearly,
    so that I know when to contact my administrator or use IMAP fallback.
33. As a Workspace user, I want existing send-as aliases supported, while
    delegated mailbox administration remains honestly unavailable without an
    admin/server integration.
34. As a user, I want notifications grouped and routed by Gmail thread/message
    identity, so that tapping a notification opens the exact conversation.
35. As a user, I want Gmail-specific behavior only on Gmail-capable accounts,
    so that Fastmail, Outlook, and generic IMAP accounts keep their current UI.
36. As an existing Gmail-over-IMAP user, I want migration to be explicit and
    reversible, so that trying Gmail API cannot destroy my current setup.
37. As a privacy-conscious user, I want Gmail API traffic and local retention
    documented, so that I understand what leaves the device and what stays.
38. As a tester, I want a live consumer Gmail and Workspace matrix on macOS and
    iOS, so that implementation evidence is separate from provider acceptance.

## Implementation Decisions

### Modules and seams

- Add the `BrevGmail` package.
- Keep `MailBackend` as the only mail interface used by views.
- Implement `GmailAPIBackend` as the adapter at that seam.
- Inject a `GmailAPITransport` into the backend. The transport owns URLSession,
  HTTP construction, JSON decoding, provider error parsing, and response-size
  bounds. It accepts a credential provider rather than raw credentials from
  callers.
- Keep transport models internal to `BrevGmail`. Map them to BrevBackend domain
  values before crossing the package interface.
- Add a Gmail connector/factory injected into `AppSessionFactory`; do not make
  `BrevMail` construct provider networking directly.
- Add provider-neutral extension interfaces only where existing interfaces are
  insufficient: label catalog/lifecycle and provider search presentation.
- Reuse existing `MessageLabelManaging`, sync-health, scheduled-send, outbox,
  cached-header, send-as, and signature interfaces where their contracts fit.

### Account and authorization

- Extend the verified Google OAuth result with stable subject, optional hosted
  domain, and granted scopes.
- Persist a Gmail API account configuration separate from IMAP configuration.
- Use `gmail-api:<subject>` as the stable account ID.
- Use the existing platform public clients, system browser, state validation,
  PKCE, token-bound UserInfo verification, Keychain token store, and
  single-flight refresh.
- Persist granted scopes and capability-gate operations from the granted set.
- Testing uses the configured `mail.google.com` grant. Permanent delete remains
  disabled when that grant is absent.
- Before production verification, record the explicit decision between broad
  full-delete access and a narrower `gmail.modify` profile.
- Workspace administrator policy failures are typed, non-retryable states with
  IMAP fallback guidance.

### Gmail store and identity

- Add a Gmail-specific SQLite store with account-wide message and thread IDs,
  label metadata, message-label joins, history cursor, draft mappings, cached
  bodies/raw source/attachment metadata, and pending provider operations.
- Do not copy IMAP UIDVALIDITY/UIDNEXT/HIGHESTMODSEQ semantics.
- Commit message/label changes and history cursor in one transaction.
- Use account plus Gmail message ID as the dedupe key across label projections.
- Map Gmail label IDs to `Folder.ID`; system-label roles are stable, while user
  label names can change without changing identity.
- Preserve the current local search-index interface only as a derived index;
  the Gmail store remains canonical.

### Full and delta sync

- Full sync loads profile, labels, message IDs, then bounded message batches.
- Respect the user's retention/body download policy during initial sync.
- Limit Gmail multipart batches to 50 operations even though Google permits
  100.
- Use bounded per-account concurrency and provider quota accounting.
- Delta sync uses `history.list` from the committed cursor and processes message
  add/delete and label add/remove events in chronological order.
- HTTP 404 for an expired history cursor schedules one full reconciliation.
- Foreground, background refresh, manual retry, and periodic recovery share the
  same sync module.
- Pub/Sub `watch` and a Brev relay are out of the initial implementation.

### Messages, threads, and attachments

- List calls retrieve Gmail IDs/thread IDs; detail calls retrieve metadata,
  MIME structure, body, and raw source as required.
- `MessageHeader.threadID` is the Gmail thread ID and advertises
  `.serverSideThreading`.
- Attachments map Gmail message/attachment IDs to stable Brev attachment IDs.
- Cache-first body/raw/attachment reads preserve the current privacy and offline
  behavior.
- Gmail thread operations apply label mutations to threads only when the user
  explicitly selected the whole conversation; message operations remain
  message-scoped.

### Labels and sidebar

- Load Gmail system/user label type, hierarchy, visibility, color, message/thread
  counts, and unread counts.
- System labels are immutable. User labels support lifecycle operations allowed
  by Gmail.
- Gmail accounts default to showing All Mail and use Gmail names Starred and
  Important; generic providers keep current wording/preferences.
- Label chips and menus share one label-catalog presentation module.
- Add/remove labels, archive, read, star, important, spam, trash, and restore use
  optimistic UI with rollback on failure.

### Search

- Gmail server-side search maps `SearchQuery` predicates and raw text to Gmail
  `q` while preserving a provider-neutral search interface.
- A provider search-description extension tells UI which syntax/operators are
  available without exposing a Gmail backend type.
- Search results dedupe by Gmail message ID and can include Spam/Trash only when
  the query or scope requests them.
- Cache/local fallback remains available while offline and is disclosed as
  local results.

### Drafts, send, aliases, and signatures

- Gmail API create/update/delete/send owns Gmail drafts for API accounts.
- MIME output remains Brev-owned and base64url-encoded for Gmail.
- Threaded replies set Gmail thread ID plus RFC 2822 reply headers and matching
  subject.
- Existing send-as identities are listed and exposed through current extended
  capabilities; alias creation/delegation management is not promised.
- Per-alias Gmail signatures are mapped into the compose signature context.
- A lost response after send remains an unknown-delivery conflict, never an
  automatic retry.

### Offline mutation behavior

- Reuse provider-neutral pending mutation intents, but resolve folder/label IDs
  through the Gmail store.
- Batch idempotent label changes where safe; do not batch dependent operations.
- Persist optimistic mutations and rollback metadata atomically.
- Permanent deletion is never silently substituted for Trash.
- Provider policy, not-found, revoked auth, quota, and unknown-delivery states
  map to distinct conflicts.

### Workspace support

- Detect and display verified hosted-domain metadata when available.
- Support the signed-in user's own mailbox and existing send-as aliases.
- Represent `domainPolicy`, admin enforcement, disabled Gmail service, and
  restricted-scope blocks as policy-disabled states.
- Do not offer delegated/shared mailbox administration without a future
  service-account/domain-wide-delegation ADR.
- Consumer and Workspace accounts share the same backend and differ through
  discovered capabilities/policies.

### Privacy, security, and operations

- Update ADR-0006 and `PRIVACY.md` before the first Gmail API request ships.
- Document `gmail.googleapis.com`, requested data, local cache, account removal,
  and granted scope behavior.
- Never log tokens, raw messages, provider response bodies, search text, or
  Gmail IDs that can identify user mail.
- Bound response bodies and attachment downloads using existing transport-limit
  conventions.
- Retry only documented transient errors with jittered exponential backoff.
- Surface quota/admin/reauth states through sync health.

### Delivery slices

1. **Foundation:** accepted ADR, package graph, transport, credential provider,
   account config, app factory seam, and OAuth profile/granted-scope persistence.
2. **Read-only native Gmail:** labels, folders, message list/detail/raw source,
   attachments, thread IDs, search, and consumer/Workspace account branding.
3. **Mutations and compose:** label lifecycle, read/star/important/archive/trash,
   drafts, send, send-as identities/signatures, offline replay.
4. **Canonical cache and history sync:** SQLite store, cache-first startup,
   history cursor, 404 recovery, retention, sync health.
5. **Native UX polish and migration:** sidebar/labels/colors, Unified Inbox,
   notification routing, reauth/admin states, explicit IMAP migration and
   rollback.
6. **Live acceptance:** consumer Gmail + Workspace macOS/iOS matrix and OAuth
   verification artifacts.

## Testing Decisions

- The highest test seam is the `MailBackend` contract: the same contract suite
  runs against Mock, IMAP/SMTP, and Gmail API adapters for shared behavior.
- `GmailAPITransport` has fixture-based tests for URL construction, auth headers,
  pagination, JSON/MIME decoding, error redaction, quota classification, and
  response limits.
- OAuth tests prove stable subject/hosted domain/granted scope persistence,
  refresh single-flight, granular denial, reauth, and no secret logging.
- Store tests use temporary SQLite files and verify schema migration,
  account-wide dedupe, label joins, transaction rollback, history cursor
  atomicity, and cache survival across restart.
- Full-sync tests verify pagination, bounded batching, retention policy, and
  duplicate label projections.
- Delta-sync tests verify chronological history, add/delete/label changes,
  repeated events, missing messages, expired cursor 404, and one full-resync
  recovery.
- Mutation tests exercise optimistic state, rollback, offline replay, batch
  limits, permanent-delete scope gating, and unknown-send outcomes.
- Gmail native UI tests use existing sidebar/list/detail/compose/Unified Inbox
  snapshot seams on macOS and iOS.
- Workspace tests cover consumer account, custom-domain account, admin blocked,
  Gmail disabled, alias available, alias read-only, and delegated mailbox
  unavailable states.
- Notification tests verify Gmail thread/message routing and dedupe.
- Live tests remain redacted and supervised; no disposable credentials are
  committed.

## Out of Scope

- Gmail Pub/Sub push or a Brev server relay in the initial implementation.
- Google Workspace domain-wide delegation, delegated-mailbox administration,
  or admin impersonation.
- Google People API contacts.
- Gmail category-tab reproduction beyond labels returned by the account.
- Creating or verifying send-as aliases; only existing aliases are listed.
- Automatic migration of existing Gmail IMAP accounts.
- Public OAuth verification submission, security-assessment procurement, and
  production publishing; the implementation will prepare their evidence.
- Replacing IMAP/SMTP for non-Google providers.

## Further Notes

- The Google Cloud project `brev-gmail-oauth-testing` contains separate macOS
  Desktop and iOS OAuth clients, Gmail API enablement, External/Testing
  audience, and the required OIDC/email/full Gmail testing scopes.
- Testing grants using restricted Gmail scope can expire after seven days; live
  QA must include expiry and reauthorization.
- The current implementation has already hardened Google OAuth identity through
  token-bound UserInfo verification. Gmail API work must build on that current
  branch behavior rather than older review snapshots.
- The related feature request remains the live provider-onboarding matrix; this feature needs a
  separate implementation issue or explicit issue-282 scope amendment before
  tracker updates.
