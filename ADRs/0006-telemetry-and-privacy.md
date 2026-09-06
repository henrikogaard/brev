# ADR-0006: Telemetry, privacy, and GDPR compliance

- **Status:** Accepted
- **Date:** 2026-05-26
- **Deciders:** Henrik

## Context

Brev's positioning depends on a credible privacy promise. Stating "we
respect your privacy" without specifics is marketing. The decision is
how to make the promise verifiable and how to handle the genuine
third-party data flows the app needs.

Brev ships without analytics or automatic crash reporting. Matomo, Sentry,
Firebase Analytics, Mixpanel, and Amplitude are absent and mechanically banned.

GDPR-wise, Brev's posture is:

- **Controller:** Henrik (sole controller, no DPO required at this
  scale).
- **Processor relationships:** the user's selected mail provider (mail
  data), optionally Gravatar/Automattic (avatar hashes if user opts
  in), optionally sender domains (favicon fetches if user opts in),
  optionally the user's chosen AI endpoint (provider-hosted AI or BYOK).
- **Data Brev itself collects from users:** zero.

## Decision

### Zero telemetry, verifiable

Brev contains no analytics SDK, no crash reporter, no usage
beacons, no opt-in telemetry. Not "off by default" — not present.

- `Matomo`, `Sentry`, `FirebaseAnalytics`, `Mixpanel`, `Amplitude`,
  and similar libraries are banned by SwiftLint rule (ADR-0005).
- Brev no longer ships previous backend or provider package mirrors;
  provider integrations live in Brev-owned packages.
- `scripts/test-telemetry-artifacts.sh` verifies `Tuist/Package.resolved`,
  generated Xcode projects/workspace files, and the latest or explicitly
  supplied `BrevIOS.app` / `Brev.app` contain no `sentry-cocoa`,
  `Sentry-Dynamic`, `matomo-sdk-ios`, or `MatomoTracker` artifacts.
- The beta gate uses `scripts/privacy-audit.sh`, settings-default
  tests, and smoke checks to verify optional external calls stay off by
  default. A runtime socket-deny harness can strengthen this later, but
  ADR-0006 must not claim a harness exists before it is implemented.

Errors are logged to a local file at `~/Library/Logs/Brev/brev.log`
(macOS) or the app's container logs (iOS). Users can attach the log
file when reporting bugs via GitHub Issues. The log file is never
transmitted automatically.

For mail accounts, Brev may persist local mailbox-cache snapshots
(folders, headers, and previously fetched bodies/attachments) under
Application Support to support offline restore and fast relaunch. This
cache is local-only, excluded from telemetry (none exists), and contains
no OAuth secrets, passwords, app passwords, or API keys. The cache can
be cleared from Settings without signing out.

Gmail compose staging stores unsent drafts and attachment bytes in the local
account database, separately from evictable message content. Cache clearing and
sync snapshots preserve this staging; send/discard cleanup and account removal
delete it. The staging tables belong to the canonical account with cascading
deletion, and draft-operation session guards reject stale writes after removal.
No credentials are added to staging and no new external service is involved.

Explicit Gmail Send Later submission persists frozen MIME and delivery intent
in account-owned SQLite rows. Automatic delivery uses existing Gmail send calls
only for submitted schedules while the process can run. Interrupted/uncertain
attempts are held for review, not reissued on restart. Clearing an account removes
the queue; no helper, hosted relay, or new endpoint is introduced.

### Network calls Brev makes, by category

The following external network calls exist or are planned for the v1
release channel. Each is either core to the product after account
sign-in, platform distribution infrastructure, or off by default
(privacy-sensitive features).

| Call | Data sent | When | Default | User control |
|---|---|---|---|---|
| IMAP/SMTP account autodiscovery | Email domain for DNS SRV probes; full email address only for provider-local HTTPS autoconfig requests | During user-initiated account setup | Off until the user starts account setup | Account setup/manual entry |
| IMAP mail access | Account credentials, mailbox commands, folder/message identifiers, search queries, message/attachment fetch requests, raw RFC 822 source fetches (cache-first; on miss only, for View Source / Show Headers / Save As), and server-side message copies (`UID COPY`, originals left in place) | During signed-in mail use after the user adds an account | On after account add | Account add/remove |
| SMTP submission | Account credentials plus the draft headers, body, and attachments being sent | When the user sends mail | On after account add | Account add/remove |
| Gmail API mail access | Google OAuth access token; account-wide Gmail message, thread, label, draft, attachment, and history identifiers; Gmail search queries; requested message metadata, bodies, raw source, attachments, label mutations, drafts, and outgoing MIME payloads | Through `gmail.googleapis.com` after the user explicitly adds a Google account using the native Gmail provider; full and delta sync continue while that account remains configured | Off until Google account add | Account add/remove; explicit IMAP/SMTP fallback |
| ManageSieve server-side filter sync | Account credentials plus a generated Brev-owned Sieve script derived from local rules | Only after the user enters a ManageSieve endpoint during account setup and later chooses to sync local rules from Settings | **Off** | Account setup / Settings → Rules |
| Sparkle update check | Appcast request metadata such as app version, update channel, IP address, and user agent | Once per launch in configured direct-download macOS releases | On for direct-download macOS only | Settings → Updates |
| Manual GitHub release check | GitHub API request metadata such as IP address, user agent, and requested Brev release repository | Only when the user chooses the manual GitHub release check in Settings → Updates | **Off** | Settings → Updates |
| Remote HTML assets in messages | Remote image, font, stylesheet, and tracking-pixel requests from message HTML | When the user loads once, allows a sender/domain, or enables always-load remote images | **Off** | Message banner / Settings → Reading |
| List-Unsubscribe action | Standard unsubscribe HTTPS URL request metadata, or an unsubscribe email draft addressed to the list provider | Only after the message advertises `List-Unsubscribe` and the user confirms the action | **Off** | Message unsubscribe banner |
| Gravatar avatar lookup | SHA-256 hash of sender email address plus normal HTTPS request metadata | Background sync, if enabled | **Off** | Settings → Privacy |
| BIMI DNS lookup | Sender domain DNS query and logo SVG request metadata | Background sync, if enabled | **Off** | Settings → Privacy |
| Domain favicon fetch | Sender-domain icon request metadata | Background sync, if enabled | **Off** | Settings → Privacy |
| AI Writer via selected provider | User-selected draft/message text and prompt context | On AI Writer use, after consent | **Off** | Settings → AI |
| Manual thread summaries via selected AI backend | User-selected loaded thread content and summary prompt context | On Summarize Thread use, after AI consent | **Off** | Settings → AI / thread action |
| Mailbox chat Q&A via selected AI backend | User-selected sender-scoped question plus a bounded cache-only set of matching message headers/snippets (max 12 messages / 48 KiB in v1) | On Mail Context chat send, after AI consent | **Off** | Settings → AI / Mail Context chat |
| BYOK/local AI endpoint (v2) | User-selected draft/message text, prompt context, and configured-provider authentication where applicable | On AI Writer use, once configured | **Off** | Settings → AI |
| Microsoft OAuth token exchange | Authorization code, PKCE verifier, and client ID exchanged with `login.microsoftonline.com`; refresh-token exchanges thereafter | During user-initiated Outlook account setup and on token refresh | Off until the user adds an Outlook account | Account add/remove |
| Google OAuth token exchange | Authorization code, PKCE verifier, and client ID exchanged with `oauth2.googleapis.com`; refresh-token exchanges thereafter | During user-initiated Google account setup and on token refresh | Off until the user adds a Google account | Account add/remove |
| Google OpenID UserInfo verification | The short-lived Google access token in a bearer header; the response is used only to read the verified email and stable subject | Immediately after a user-initiated Google authorization-code exchange | Off until the user adds a Google account | Account add/remove |
| CardDAV contacts sync | OAuth bearer token or configured credentials plus a CardDAV `REPORT` query to the provider principal URL | After the user adds/restores an OAuth account with a built-in CardDAV profile, or when the user triggers sync for a configured CardDAV server | Off until account add/restore or contacts setup | Account add/remove; contacts setup |
| CalDAV invite write | Account credentials plus the event/response payload `PUT` to the user-configured CalDAV collection | Only when the user accepts a calendar invite and a CalDAV target is configured | **Off** | Calendar invite action |
| iCloud Key-Value preference sync | Allowlisted local preferences only (snoozes/done markers, VIPs, inbox category overrides, pinned messages, blocked senders, follow-up reminders, signatures, templates, smart mailboxes, compose and sidebar preferences; see ADR-0056); never mail, credentials, or consent flags | While the user has enabled preference sync, on local change and on remote change | **Off** | Settings → Privacy |

Optional privacy-sensitive external calls (remote HTML assets, server-side
filter sync, avatars, iCloud preference sync, and AI)
require explicit opt-in via Settings or an in-context user action. A
first-run welcome screen walks the user through each, with
plain-language explanations of what each shares.

### AI Writer transparency

Every AI action shows a small persistent label in the UI:

- "Sent to: provider-hosted AI" — provider-specific option when available
- "Sent to: api.openai.com" — neutral badge with provider name
- "Sent to: localhost (Ollama)" — local endpoint badge

When BYOK/local providers are configured, the destination label shows the
configured endpoint host (including `localhost` for local servers), and
provider metadata stays local on device.

This makes per-action data flow obvious. The user always knows where
their message content goes when they invoke AI, including compose
actions, thread summaries, and mailbox chat answers.

### GDPR compliance specifics

- **`PRIVACY.md`** lives at repo root and is published at
  `brevmail.eu/privacy`. Plain language, structured by "what data
  leaves your device and where."
- **Contact:** `privacy@brevmail.eu` for data subject rights
  requests.
- **Right to erasure:** Brev stores no user data server-side, so
  erasure means uninstalling the app. The mail data lives with the
  user's selected mail provider, subject to their privacy policy.
  Documented in PRIVACY.md.
- **Data portability:** Mail stays with the selected provider and can be
  accessed through its supported standard or native interfaces. Settings export/import
  via JSON in v1.1 (not v1).
- **Cookies / tracking:** None. The sandboxed message renderer does not enable
  JavaScript or load remote content without user approval.
- **Children:** Brev does not target users under 16. No age
  verification at sign-up because Brev doesn't have its own sign-up —
  users authenticate with their mail provider.

### Crash reporting (or lack thereof)

No automatic crash reporting. If Brev crashes:

1. macOS or iOS generates a system crash log (visible in Console.app
   or Settings → Privacy → Analytics).
2. User can opt to send the Apple crash log to Apple, who shares it
   with Brev via App Store Connect (this is App Store standard
   behavior; opt-in by the user via Apple, not by us).
3. Or the user can attach the local Brev log to a GitHub Issue
   manually.

We see crash data only via App Store Connect (aggregated) or via
deliberate user submission. Never via direct phone-home.

### Secrets handling

- Account credentials (IMAP/SMTP passwords or app passwords, OAuth
  tokens where a provider flow exists, future BYOK API keys) live in
  macOS Keychain or iOS Keychain. Never in `UserDefaults`, never in log
  files, never in crash reports.
- Provider diagnostics may log coarse account identifiers and credential
  presence flags, but never access-token, refresh-token, password, app-password,
  or API-key values or fragments.
- Keychain entries scoped to `eu.brevmail.brev` and `eu.brevmail.
  brev.ios` respectively. Never shared between platforms (per-device
  re-authentication).
- BYOK provider metadata (endpoint/model/provider name) is stored in local
  app settings storage; only API keys are secret-backed.
- Local providers such as Ollama do not require an API key by default.

## Rationale

**Why zero telemetry, not opt-in telemetry.** Opt-in telemetry sounds
respectful but creates an asymmetry: the developer wants the data,
the user has to actively refuse. Even with informed opt-in, building
the telemetry pipeline is a maintenance cost. For a solo project of
this size, the value of telemetry is low and the maintenance/privacy
cost is real. Better to commit to zero and treat user feedback
through deliberate channels (GitHub Issues, the user's own mail to
support).

**Why eager opt-in for avatar lookups instead of opt-out.** Per
ADR-0003, defaults-off prevents avatar lookups unless the user chooses
them. A user who never opens the welcome panel never makes avatar, AI,
push, or remote-HTML network calls beyond account sign-in/mail sync
itself; direct-download macOS builds remain the distribution-specific
exception for signed Sparkle appcast checks.

**Why per-action AI provider transparency.** AI Writer sends actual
message content (potentially sensitive) to a third party. The user
should never forget this. A persistent UI label is the cheapest
mechanism that makes the data flow visible at the moment it
matters.

**Why local-only logs.** Useful for debugging without becoming a
phone-home channel. Users in trouble can attach logs deliberately.

## Consequences

### Accepted

- No analytics means no usage data to inform product decisions. We
  rely on Henrik's own usage, deliberate user feedback, and GitHub
  Issues. Acceptable for project size.
- No crash reporting means harder bug diagnosis. Mitigation: detailed
  local logs, clear bug-report template that asks for the log file,
  App Store Connect's aggregated crash data for App Store releases.
- "Defaults-off" for avatars means new users see initials-only.
  Documented as a deliberate trade-off in ADR-0003.

### Risks

- **Crash log surface still leaks some data via Apple's pipeline.**
  Apple's standard crash reporting (which the user can opt out of in
  system settings) sends stack traces and basic device info to Apple
  and onward to developers via App Store Connect. This is outside
  Brev's control. Documented in PRIVACY.md.
- **App Store distribution involves Apple's data collection.** Users
  installing via App Store get whatever telemetry Apple collects on
  installations and updates. Out of our control. Documented.
- **GitHub Issues are public.** A user submitting bug reports may
  inadvertently include sensitive information from their email. We
  add a note to the bug template recommending log redaction.

## References

- ADR-0028: Mail provider architecture and invariants
- ADR-0003: Avatar resolution (defaults-off for external lookups)
- ADR-0005: Enforcement (mechanical rules backing this ADR)
- ADR-0008: AI Writer (provider transparency)
- PRIVACY.md (user-facing version)
- GDPR text: https://gdpr-info.eu/
