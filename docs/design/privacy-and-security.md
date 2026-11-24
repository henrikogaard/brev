# Privacy & Security

> Consolidates former ADRs `0006`, `0021`, `0036`, `0055`, `0082`, and `0088`.
> User-facing counterpart: [PRIVACY.md](../../PRIVACY.md).

## Hard Invariants

1. **Zero telemetry, mechanically enforced.** Brev contains no analytics SDK, no crash reporter, no usage beacons, and no opt-in telemetry. Imports of `Matomo`, `Sentry`, `FirebaseAnalytics`, `Mixpanel`, and `Amplitude` are banned by SwiftLint and verified against built artifacts by `scripts/test-telemetry-artifacts.sh` and `scripts/privacy-audit.sh`.
2. **No Brev-operated mail proxy or cloud server.** Brev connects directly from the user's device to the user's chosen mail, DAV, or AI endpoints. Ogard Labs (`privacy@brevmail.eu`) stores no user mailbox data, credentials, or analytics.
3. **Keychain-only secrets.** IMAP/SMTP passwords, app passwords, OAuth tokens, and BYOK AI API keys live exclusively in the macOS or iOS Keychain—never in `UserDefaults`, logs, crash reports, or portable backups.
4. **No silent third-party leaks.** Tracking pixels are stripped before rendering, the sandboxed `WKWebView` reader disables JavaScript, and every new external network call must be documented both in the ledger below and in [PRIVACY.md](../../PRIVACY.md).
5. **Demo mode isolation.** Demo/mock sessions (`BREV_USE_MOCK=1`) never access system Contacts, system Calendar, or real Keychain/DAV credentials.

## Balanced Privacy Posture (Updated from Legacy ADRs)

Zero telemetry and zero Brev-operated proxy servers remain non-negotiable. However, rather than burying every benign convenience behind eight disconnected Settings toggles:

- **Onboarding choices:** First-run setup may present clear, plain-language opt-in choices for conveniences such as sender avatars, iCloud preference sync, background mail presence, and on-device AI.
- **Trusted-sender remote images:** Remote HTML assets remain blocked by default for unknown senders (with tracking pixels stripped), while supporting a practical trust tier for explicitly allowed senders/domains and optionally Contacts / replied-to senders.
- **Sign-in code trust on generic IMAP:** See Sign-In Code Detection below—generic IMAP accounts are no longer permanently disqualified when standard authentication headers or explicit user opt-in are used.

## External Network Calls Ledger

Every external network call Brev makes is either core to an account the user added, platform update infrastructure, or gated by explicit user opt-in:

| Call | Data sent | When | Default | User control |
| --- | --- | --- | --- | --- |
| IMAP/SMTP account autodiscovery | Email domain for DNS SRV probes; full email address only for provider-local HTTPS autoconfig requests | During user-initiated account setup | Off until the user starts account setup | Account setup/manual entry |
| IMAP mail access | Account credentials, mailbox commands, folder/message identifiers, search queries, message/attachment fetch requests, raw RFC 822 source fetches (cache-first; on miss only, for View Source / Show Headers / Save As), server-side message copies (`UID COPY`, originals left in place), and pre-send draft updates (`APPEND`) when sending an opted-in existing remote draft with a no-reply reminder | During signed-in mail use after the user adds an account; pre-send draft update runs only on explicit Send with a no-reply reminder enabled | On after account add | Account add/remove; no-reply reminder opt-in plus explicit Send for the pre-send draft save |
| SMTP submission | Account credentials plus the draft headers, body, and attachments being sent | When the user sends mail | On after account add | Account add/remove |
| Gmail API mail access | Google OAuth access token; account-wide Gmail message, thread, label, draft, attachment, and history identifiers; Gmail search queries; requested message metadata, bodies, raw source, attachments, label mutations, drafts, and outgoing MIME payloads | Through `gmail.googleapis.com` after the user explicitly adds a Google account using the native Gmail provider; full and delta sync continue while that account remains configured. Opening a Draft from the Drafts folder also reads `drafts.list` to find its draft ID. Sending an opted-in existing remote draft first updates that draft through the existing authenticated Gmail save call so its canonical RFC Message-ID matches the no-reply reminder | Off until Google account add | Account add/remove; explicit IMAP/SMTP fallback; no-reply reminder opt-in plus explicit Send for the pre-send save |
| Keep Offline body prefetch | Existing IMAP account credentials or Gmail OAuth token plus mailbox/message identifiers and a message-body fetch request to the configured provider, when needed by the backend | Only when the user turns Keep Offline on in a message list, Unified Inbox, reader or conversation menu; cache-first and best-effort | **Off** | Explicit per-message Keep Offline toggle |
| ManageSieve server-side filter sync | Account credentials plus a generated Brev-owned Sieve script derived from local rules | Only after the user enters a ManageSieve endpoint during account setup and later chooses to sync local rules from Settings | **Off** | Account setup / Settings → Rules |
| Sparkle update check | Appcast request metadata such as app version, release ring, IP address, and user agent; the appcast and release notes are fetched from `henrikogaard.github.io` and the DMG from `github.com` / `objects.githubusercontent.com` | Once per launch in configured direct-download macOS releases of either ring (Stable or Nightly) | On for direct-download macOS only | Settings → Updates |
| Manual GitHub release check | GitHub API request metadata such as IP address, user agent, and requested Brev release repository | Only when the user chooses the manual GitHub release check in Settings → Updates | **Off** | Settings → Updates |
| Remote HTML assets in messages | Remote image, font, stylesheet, and tracking-pixel requests from message HTML | When the user loads once, allows a sender/domain, or enables always-load remote images | **Off** | Message banner / Settings → Reading |
| List-Unsubscribe action | Standard unsubscribe HTTPS URL request metadata (including RFC 8058 `List-Unsubscribe=One-Click` POST or browser page open), or an unsubscribe email draft addressed to the list provider | Only after the message advertises `List-Unsubscribe` and the user confirms the exact destination and method | **Off** | Message unsubscribe banner / Subscriptions view |
| Related-mail header discovery | Reply identifiers (Message-ID, In-Reply-To, References) from the selected conversation. IMAP: bounded `UID SEARCH HEADER` queries plus metadata fetches across eligible folders. Gmail: metadata-only `users.threads.get` / minimal `users.messages.get` | Only when the user chooses "Load related mail" in the reader, or on conversation open when the per-account preference is enabled | **Off** | Reader action / Settings → Folder Sync |
| Gravatar avatar lookup | SHA-256 hash of sender email address plus normal HTTPS request metadata | Background sync, if enabled | **Off** | Settings → Privacy |
| BIMI DNS lookup | Sender domain DNS query and logo SVG request metadata | Background sync, if enabled | **Off** | Settings → Privacy |
| Domain favicon fetch | Sender-domain icon request metadata | Background sync, if enabled | **Off** | Settings → Privacy |
| AI Writer via selected provider | User-selected draft/message text and prompt context | On AI Writer use, after consent | **Off** | Settings → AI |
| Manual thread summaries via selected AI backend | User-selected loaded thread content and summary prompt context | On Summarize Thread use, after AI consent | **Off** | Settings → AI / thread action |
| Mailbox chat Q&A via selected AI backend | User-selected question plus a bounded cache-only set of matching message headers/snippets | On Assistant / Mail Context chat send, after AI consent | **Off** | Settings → AI / Assistant |
| BYOK/local AI endpoint (v2) | User-selected draft/message text, prompt context, and configured-provider authentication where applicable | On AI Writer use, once configured | **Off** | Settings → AI |
| Microsoft OAuth token exchange | Authorization code, PKCE verifier, and client ID exchanged with `login.microsoftonline.com`; refresh-token exchanges thereafter | During user-initiated Outlook account setup and on token refresh | Off until the user adds an Outlook account | Account add/remove |
| Google OAuth token exchange | Authorization code, PKCE verifier, and client ID exchanged with `oauth2.googleapis.com`; refresh-token exchanges thereafter | During user-initiated Google account setup, Google PIM feature enablement, Google Drive attachment opt-in, and token refresh | Off until the user adds a Google account, enables a Google PIM feature, or uses a Drive action | Account add/remove; Settings → Calendar & Contacts; Drive opt-in prompt |
| Google OpenID UserInfo verification | Short-lived Google access token in a bearer header to read verified email and stable subject | Immediately after user-initiated Google authorization-code exchange | Off until Google account add or PIM enablement | Account add/remove |
| CardDAV / CalDAV / Google PIM discovery, sync, and write | Account/source credentials or OAuth tokens with `PROPFIND`/`REPORT`/`PUT`/`DELETE` (DAV) or Google Calendar/People/Tasks API calls | Only when a PIM source is connected and sync/editing is enabled | **Off** | Settings → Calendar & Contacts |
| Google Picker & Drive attachment calls | Account OAuth token, Picker API key/app ID, and `drive.file` metadata/download/export/upload calls | Only after the user invokes a Drive attach/save action and grants `drive.file` | **Off** | Drive attach/save action; revoke Google grant |
| iCloud Key-Value preference sync | Allowlisted local preferences only (snoozes/done markers, VIPs, inbox category overrides, pinned messages, blocked senders, follow-up reminders, signatures, templates, smart mailboxes, compose and sidebar preferences); never mail, credentials, or consent flags | While preference sync is enabled, on local/remote change | **Off** | Settings → Privacy |

*Note:* Optional macOS background mail changes only the cadence of already-configured mail connections and adds no new endpoint. On-device Apple Intelligence (`FoundationModels`) makes zero network calls. Local MCP agent access (`brev-mcp`) binds only a user-private `0600` Unix domain socket with same-UID `getpeereid` checks on both ends and zero TCP/UDP ports.

## Local Store Encryption at Rest

- **Layer A (OS file protection — shipped):** `SQLiteSyncStore`, `SQLiteGmailAccountStore`, header/body/source caches, local mail folders, and staging files open standard SQLite/file stores under `~/Library/Application Support/Brev`. On iOS, `BrevStoreProtection` applies `FileProtectionType.completeUntilFirstUserAuthentication` to the store root and its contents; on macOS, `BrevStoreProtection` is a no-op and at-rest confidentiality relies on FileVault and the user's sandboxed home container (explicit `0600`/`0700` POSIX modes are enforced on specific sensitive surfaces such as the local MCP socket and audit log).
- **Layer B (application-level encryption — planned):** Application-level encryption of local SQLite databases and cached payloads using device-scoped Keychain keys (`eu.brevmail.brev` / `eu.brevmail.brev.ios`, never shared across platforms or exported in backups) is planned future work and is not yet implemented in `SQLiteSyncStore` or `SQLiteGmailAccountStore`.
- **Logs:** Local errors write to `~/Library/Logs/Brev/brev.log` (macOS) or the app container (iOS) with secrets, tokens, message bodies, and sign-in codes strictly redacted; logs are never transmitted automatically.

## S/MIME Security

- `BrevCrypto` encapsulates all cryptographic operations so views and mail adapters never see low-level CMS/Security types.
- **Inbound verification & decryption:** Supported on both macOS and iOS with clear signature/encryption badges in the reader.
- **Outbound signing & encryption:** Supported on macOS via Apple's CMS encoder; fails closed rather than silently downgrading to plaintext when requested security cannot be satisfied.
- **iOS outbound S/MIME (relaxed from former ADR-0036):** Rather than treating iOS outbound S/MIME as a permanent non-goal, iOS remains fail-closed *until* a standards-compliant RFC 8551 CMS encoder (e.g. SwiftCrypto / BoringSSL-backed) is integrated, at which point both platforms share full S/MIME parity.
- OpenPGP is retired (`scripts/test-openpgp-retired.sh`).

## Sign-In Code & Link Detection

- Device-local, per-account opt-in (`SignInCodeSettings`, off by default, excluded from backups and iCloud sync).
- Extracted one-time codes and HTTPS sign-in links stay **memory-only** (never logged or persisted), copy to clipboard as concealed/expiring entries (`org.nspasteboard.ConcealedType` on macOS; `.localOnly` with 60-second expiry on iOS), and post **lock-screen-safe** generic local notifications on iOS (zero raw codes or links in `UNNotificationContent`, biometric-gated Copy action, foreground host-confirming Open Link action).
- **Generic IMAP support (relaxed from former ADR-0088):** Previously restricted strictly to providers advertising a verified `.trustedSignInAssessment` flag (excluding all generic IMAP servers). Going forward, generic IMAP accounts may qualify when incoming messages carry passing standard `Authentication-Results` (`SPF=pass`, `DKIM=pass`, `DMARC=pass` with aligned domain) or when the user explicitly opts in per account with a clear trust explanation.

## Local MCP Agent Access Security

- Transport is strictly a user-private `0600` `AF_UNIX` socket scoped per app bundle identity (Stable, Nightly, Test) with `getpeereid` same-UID verification on **both** the server and the bundled `brev-mcp` stdio helper. Zero TCP or UDP ports.
- Master switch and per-account grants default to off, stay device-local, and are excluded from backups and iCloud sync.
- Read tools are cache-only, exclude Trash/Spam, and redact sign-in codes/links; write tools require per-call in-app approval with a 60-second fail-closed timeout; `send_message`, `delete_message`, and settings/credential mutations are permanently excluded.
- Bounded 1,000-entry backup-excluded local audit log (`agent-access-audit.json`) never records bodies, snippets, credentials, or unresolved caller-supplied IDs.

## GDPR & Crash Reporting

- **Controller:** Ogard Labs (`privacy@brevmail.eu`). Right to erasure is uninstalling the app; mail stays on the user's provider.
- **Crash logs:** No third-party crash SDK. Diagnostics come only from Apple's opt-in App Store Connect crash aggregation or logs a user deliberately attaches to a GitHub issue.
