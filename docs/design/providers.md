# Mail Providers & Authentication

> Consolidates former ADRs `0032`, `0040`, `0063`, `0064`, `0065`, `0067`, `0079`, and `0081`.

## Provider Strategy

Brev is standards-first and multi-provider behind one `MailBackend` contract:

| Provider | Package | Auth | Status |
| --- | --- | --- | --- |
| **Generic IMAP / SMTP** | `BrevBackend` + `BrevSyncEngine` | Password / app password, XOAUTH2 (Google/Microsoft), STARTTLS / implicit TLS, RFC 6186 SRV & provider autoconfig | **Shipped** |
| **Google / Gmail (Native API)** | `BrevGmail` | Platform-specific Google OAuth 2.0 + PKCE (macOS Desktop loopback / iOS reversed client ID) + OpenID UserInfo | **Shipped** |
| **Microsoft 365 / Outlook** | `BrevBackend` (OAuth-over-IMAP now) → future `BrevMicrosoftGraph` | Microsoft OAuth 2.0 + PKCE (`login.microsoftonline.com`) | **IMAP/SMTP OAuth shipped; native Graph planned** |
| **JMAP (Fastmail, Stalwart, Cyrus)** | `BrevJMAP` | Bearer / API token or OAuth 2.0 + RFC 8620 §2 session discovery (`/.well-known/jmap` or explicit HTTPS session URL) | **Shipped** |

## Native Gmail Adapter (`BrevGmail`)

- Uses Gmail's REST API (`gmail.googleapis.com`) for native message/thread IDs, multi-label semantics, `history.list` incremental sync, native server search (`gmail-q`), drafts, and send-as identities.
- Maps system labels (`INBOX`, `SENT`, `DRAFT`, `TRASH`, `SPAM`, `STARRED`, `SNOOZED`) and user labels onto `Folder` + provider-label operations while preserving multi-label membership (including archived unlabeled messages mapped to synthetic `ALL_MAIL`).
- Users may still explicitly fall back to IMAP/SMTP for Gmail accounts if desired.

## Platform-Specific Google OAuth

- **macOS (`Desktop app` client):** Uses an ephemeral random-port loopback HTTP listener (`127.0.0.1`) with PKCE and `state` verification, plus `ASWebAuthenticationSession` / system browser handoff. Client credentials are injected at build time via Xcode build settings (never hardcoded secrets in git).
- **iOS (`iOS` native client):** Uses Google's reversed client ID custom URL scheme callback with PKCE and `state` verification.
- **Incremental scopes:** Mail sign-in requests minimal mail + OpenID identity scopes first; Google Calendar, Contacts, Tasks, and Drive (`drive.file`) request incremental consent only when the user enables those features.

## Server-Side Filters (ManageSieve — Shipped, Opt-In)

- Optional RFC 5804 ManageSieve support discovered via SRV during setup or configured manually in Settings → Rules for capable accounts.
- Compiles Brev local rules into a dedicated Brev-managed Sieve script only when the user explicitly chooses to sync rules, preserving existing non-Brev scripts untouched.

## Native JMAP Adapter (`BrevJMAP` — Shipped)

- Targets Fastmail (`https://api.fastmail.com/jmap/session`), Stalwart, Cyrus, and any standards-compliant JMAP server (RFC 8620 / RFC 8621).
- **Strict HTTPS session discovery & auth:** Discovers the RFC 8620 §2 Session resource via `/.well-known/jmap` (for bare domains/hosts) or an explicit HTTPS session URL. Rejects non-HTTPS URLs, embedded URL credentials, and insecure redirects, and strips `Authorization` / `Cookie` headers on cross-origin redirects. API / Bearer tokens live strictly in the system Keychain (`TokenStore`), never in `UserDefaults`, `.brevbackup`, or iCloud preference sync.
- **Batched JSON API & full RFC 8621 mail surface:** Single-round-trip batched `Email/query` + `Email/get` (`#resultRef` back-references) for message listing and structured server search (`FilterCondition`), `Mailbox/get` + `Mailbox/set` (role mapping, unread/total counts, folder CRUD/flush), `Email/get` body/attachment/header parsing + RFC 8620 §6.2 percent-encoded `downloadUrl` attachment & raw RFC 5322 downloads, `Email/set` mutations (read, flag, Apple `$MailFlagBit0..2` flag colors, move, copy, trash/destroy), `Blob/upload` + `Email/set` drafts, and single-batch `Identity/get` + `Email/set` + `EmailSubmission/set` outbound sending.
- **Delta sync & EventSource SSE:** Maintains JMAP `Mailbox` and `Email` state tokens for incremental `Mailbox/changes` + `Email/changes` sync (falling back cleanly to full refresh on `cannotCalculateChanges`), integrates with `MailboxBackgroundRefreshing` / `CachedMessageHeaderProviding` for `PushWakeCoordinator`, and drives `subscribeToChanges()` via RFC 8620 §7.3 `EventSource` SSE (`StateChange`) with clean cancellation and bounded exponential backoff.
- **WebPush-to-device delivery bridge:** Native iOS/macOS apps do not expose a browser WebPush service worker endpoint directly, so JMAP WebPush (`PushSubscription/set` with RFC 8291 P-256 keys, exposed directly on `JMAPBackend` via `JMAPWebPushSubscriptionSpec`) registers a user-owned HTTPS WebPush delivery receiver URL distinct from the JMAP API endpoint. That user-owned bridge receives encrypted RFC 8620 §7.2.2 `PushVerification` challenges and RFC 8620 §7.1 `StateChange` objects from the JMAP server and forwards opaque wakes (carrying only device-local opaque account tokens, never mail bodies or credentials) to Brev via APNs or local delivery, where `PushWakeCoordinator` handles both `PushVerification` challenges and `StateChange` wakes.
  - **Operator token-mapping notes:** Brev never transmits raw email addresses or internal `imap-smtp:` / `gmail-api:` / `jmap:` account IDs in push registration or wake payloads. When forwarding an RFC 8620 `StateChange` (`{"@type": "StateChange", "changed": {"<providerAccountId>": {"Email": "..."}}}`), the operator's WebPush bridge maps each provider JMAP account ID in `changed` to the corresponding device-local opaque token (`acct-<uuid>`) registered for that device before delivering the wake to Brev; any unmapped or non-opted-in key is ignored by `PushWakeCoordinator`. For RFC 8620 §7.2.2 `PushVerification` challenges (`{"@type": "PushVerification", "pushSubscriptionId": "...", "verificationCode": "..."}`), the bridge forwards the JSON challenge untouched and `AppSession`'s `PushWakeCoordinator` automatically submits the matching `PushSubscription/set` `update` to activate the pending subscription.

## Future Provider Designs

### Native Microsoft Graph (`BrevMicrosoftGraph`)

- Targets Microsoft 365 / Exchange tenants where IMAP/SMTP basic or OAuth access is disabled.
- Will implement `MailBackend` over Graph REST APIs (`graph.microsoft.com`) with delta tokens, native folders/categories, shared mailboxes, and incremental OAuth scopes.
- Enterprise admin/MDM compliance policies remain non-goals unless explicitly scoped later.
