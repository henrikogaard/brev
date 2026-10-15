# ADR-0088: Show sign-in codes and links on screen as they arrive

- **Status:** Accepted
- **Date:** 2026-10-11
- **Accepted:** 2026-10-15
- **Deciders:** Henrik
- **Relates to:** ADR-0006 (telemetry and privacy), ADR-0058 (string
  catalogs), ADR-0074 (source-owned conversations), ADR-0075 (macOS
  background mail presence), ADR-0076 (settings backup), ADR-0083 (widgets)
- **Issue:** #239

## Context

People who sign in to a website by email wait for a one-time code or a
magic link, then switch to the mail window to find it. Issue #239 asks for
a small floating panel that shows the code (Copy) or the link (Open) the
moment the message arrives.

The feature reads message content and acts on it, so it carries more risk
than a normal notification. It must not surface a spoofed message, silently
read mail before the user consents, or expose a code outside the user's
awareness. Henrik accepted the revised design on 2026-10-15 with
"design look good - continue", following the request for explicit design
acceptance. This accepts the decisions below, including aligned DMARC-pass-only
authentication. It does not establish provider evidence, ship the feature,
authorize merging the PR, or close issue #239.

What the codebase gives us today (checked 2026-10-11):

- New mail is `MailEvent.messagesAdded(folderID:messageIDs:)` from
  `subscribeToChanges()`. It is consumed only in `BrevMailRootView`
  (`handleBackendEvent`), next to `NewMailNotificationPolicy`. IMAP seeds the
  known-ID set on the first listing of a folder and emits for later unknown
  IDs, so a deeper page load can in principle report old mail as added. No
  message-age or delivery-provenance check exists.
- `MessageHeader` carries a `snippet` only. The body and the raw
  `Authentication-Results` value are on `MessageBody` and need
  `backend.body(for:)`, which fetches on a cache miss. The existing IMAP body
  path may persist fetched content in the ordinary mail cache (ADR-0029).
- `MessageHeaderAnalyzer` parses DMARC *failure* only. There is no pass
  parsing, and raw SPF/DKIM results are deliberately not surfaced today. The
  raw `MessageBody.authenticationResults` value is untrusted; the existing
  first-value extraction has no receiving-service provenance.
- `MessageSecurityWarningPolicy` already detects a link whose visible text
  and real destination host disagree.
- There is no `NSPanel` anywhere. `BrevToast` and `BrevInlineStatus` give the
  panel content. Per-account settings have one pattern:
  `NotificationSettings.AccountOverride`.
- ADR-0075 runs the fetch schedule from the root view and a background
  coordinator. Whether the `.messagesAdded` consumer survives a closed main
  window is not yet verified.

## Decision

1. **Scope.** macOS first: a floating panel. iOS follows as a separate slice
   but iOS notifications are deferred to a separate privacy design and
   acceptance. OS notification persistence and lock-screen disclosure conflict
   with the memory-only panel promise. This ADR does not authorize OTP or link
   contents in notifications.
2. **Detection is local and deterministic.** A pure `SignInCodeDetector` in
   BrevMail takes plain-text body content and returns at most one candidate:
   a code (4-8 digits, or short alphanumerics, near sign-in wording in English
   and Norwegian) or one prominent sign-in link. It rejects tracking and
   unsubscribe links, order numbers, prices, phone numbers and dates. No AI
   and no remote service. The feature performs no detection, body read or panel
   presentation before the corresponding per-account opt-in, including when a
   body is already cached.
3. **Only fresh, recent, primary mail.** A message must arrive through
   `.messagesAdded` after the account's first-listing baseline, have
   receiving-provider delivery/backfill provenance that establishes it as a
   fresh delivery rather than a cache backfill or reconciliation, have its own
   date within 10 minutes, and belong to an Inbox-class folder. Spam, Trash,
   Archive, Sent and Drafts never qualify. A recent timestamp alone is not
   proof of fresh delivery: if the provider cannot establish delivery versus
   backfill provenance, fail closed. The 10-minute check supplements that
   provenance; it does not solve backfill by itself.
4. **Trusted authentication gate, fail closed.** Raw
   `MessageBody.authenticationResults` and raw `Authentication-Results`
   headers are untrusted input; neither the topmost result nor an `authserv-id`
   alone establishes provenance. The existing first-value extraction has no
   provenance and cannot be used as a trust boundary. Before an account can
   qualify, its provider adapter must establish and document a receiving-
   service trust boundary: map a trusted `authserv-id` to the configured,
   authenticated provider and verify how sender-supplied forged authentication
   results are handled or removed. Preserve ordered duplicate headers or obtain
   authoritative provider metadata when needed to prove that boundary. Do not
   infer trust from the `From` field, header position, a user-entered allowlist,
   or TLS alone.

   Only a provider-neutral trusted authentication assessment may cross the
   backend domain seam, exposed through a capability or equivalent contract;
   views must not type-check provider implementations. Generic IMAP accounts
   without an established trust boundary are unavailable and fail closed.
   Gmail support also requires evidence and is not assumed. For this
   initial version, eligibility requires a trusted DMARC pass aligned to
   the actual `From` domain; there is no DKIM-only fallback in the first
   version. Missing, malformed, ambiguous, or conflicting trusted results
   fail closed. Authentication is an
   anti-spoofing signal, not proof that a link or destination site is safe.
5. **Body fetch policy.** Only after the explicit opt-in, delivery-provenance,
   recency and folder gates pass, and the account advertises an established
   trusted-authentication capability, may the feature call `body(for:)` over
   the account's existing endpoint. Do not fetch for unsupported accounts.
   Check consent and eligibility before starting the asynchronous body read
   and recheck both before displaying any result. Disabling either opt-in or
   removing the account cancels pending work and dismisses its panel; stale
   asynchronous completions must not display content. There is no new endpoint
   or third party.
6. **Links.** Only https links. The panel shows the real destination host
  before opening. A link whose visible text and target host disagree (the
  existing mismatch policy) gets no one-click open. Opening uses the default
  browser. Authentication does not establish link safety.
7. **Derived state only is memory-only.** A detected candidate and panel state
   live only in memory while the panel is visible. They are never logged,
   persisted, synced, put in a notification `userInfo`, written to a widget
   snapshot, or included in diagnostics or QA artifacts. The implementation
   must audit the existing body-fetch/cache path for disk-cache side effects;
   this decision does not claim that `body(for:)` is non-persisting and does
   not erase the ordinary mail cache. If the requirement is that original
   OTP-bearing emails are never persisted, that requires a separate storage
   policy and decision; it is not implied here.
8. **Clipboard.** Copy writes with `org.nspasteboard.ConcealedType`. An
   optional "clear after N seconds" clears only if the pasteboard change count
   is unchanged since Brev wrote it.
9. **Panel.** A non-activating `NSPanel` at the bottom centre of the active
   screen, above other windows, that never takes keyboard focus. Click, the
   close control and a timeout dismiss it; the default timeout is 60 seconds.
   Escape is supported only while Brev is the active app, using app-local key
   handling while the panel is visible. When a browser or another app is
   active, dismissal is by click, close or timeout only: no global key monitor,
   Accessibility/Input Monitoring request, or stolen key focus. A newer code
   from the same sender replaces the older one. Content uses `BrevToast`
   (BrevDesign is not edited). Implementation verification must show that
   presenting the panel does not change the focused app and that Escape in a
   background app is not consumed; this has not been runtime-tested in this
   documentation PR.
10. **Closed window.** The arrival hook moves out of the view into an
    `AppSession`-owned controller so it works while the main window is closed,
    for as long as Brev is running and syncing. If the verification below shows
    the subscription already survives, only the new consumer moves. Verifying
    this subscription lifetime is an implementation gate; no runtime result
    is claimed here.
11. **Settings and consent.** A `SignInCodeSettings` model modelled on
    `NotificationSettings.AccountOverride`, with independent codes and links
    opt-ins, both default off per account and device. The in-context opt-in
    explains that eligible messages may cause additional message-body fetches
    and that sensitive codes may appear over other apps. Adding or signing in
    to an account is not feature consent. Consent is device-local and excluded
    from account backup and iCloud key-value sync (ADR-0076). The post-use
    default is to leave the message unchanged; the panel timeout defaults to
    60 seconds.
12. **Privacy documentation.** When body-reading implementation begins,
    update `PRIVACY.md` and ADR-0006 to describe the opt-in-gated use of the
    existing account endpoint and the additional body fetch. The accepted
    design and isolated detector do not claim the feature has shipped or
    update user-facing privacy documentation as though it had.

## Rationale

- **Detector over a notification trick.** macOS Notification Center would
  retain notification content and may expose it on the lock screen. A panel
  we own keeps derived candidate state in memory only; it does not make the
  original mail body's ordinary cache non-persistent.
- **Explicit account opt-in over default-on detection.** The feature can cause
  additional body reads and display sensitive codes over other apps. Separate
  defaults-off choices let a person enable only codes or only links on
  accounts where they want the behavior.
- **Provider-established authentication over raw-header parsing.** An
  attacker can add misleading `Authentication-Results` fields. Only a
  provider adapter that demonstrates the receiving-service boundary can make
  a trusted assessment; absence of evidence means no feature for that account.
  A trusted DMARC pass aligned to the actual From domain is the accepted
  initial policy; a DKIM-only fallback is not permitted.
- **Body fetch over snippet-only.** Snippets are short, so many codes sit
  beyond them. Fetches are bounded by explicit consent, provider trust,
  delivery provenance, recency and folder gates, with consent rechecked before
  display.
- **Rejected:** AI extraction (content would leave the device or add a model
  dependency); showing every code regardless of authentication; one global
  setting only (people have accounts they do not want scanned); persisting
  recent codes for a history view (it conflicts with decision 7).

## Consequences

### Accepted scope

- A new macOS window type, a new controller owned by `AppSession`, and one
  extra body fetch per qualifying, opted-in message on accounts with an
  established trust capability.
- Accounts without delivery provenance or trusted authentication evidence
  never show a panel; unsupported generic IMAP and unproven Gmail accounts
  fail closed.
- Message flags and folders remain unchanged by default after Copy or Open.
- iOS notifications remain out of scope until a separate privacy design is
  accepted.
- `PRIVACY.md` and ADR-0006 need implementation-time updates before shipping.

### Risks

- Provider authentication provenance may not be available or provable for a
  given adapter. Mitigation: enable only accounts whose adapter establishes
  and documents the boundary; require evidence for Gmail and keep unsupported
  generic IMAP unavailable.
- Forged, duplicate, malformed or conflicting authentication headers may be
  mistaken for provider results. Mitigation: preserve order or use
  authoritative provider metadata, verify forged-result handling, and test
  synthetic adversarial fixtures with fail-closed outcomes.
- A recent message date may belong to a backfilled message. Mitigation:
  require provider delivery/backfill provenance in addition to the 10-minute
  window; otherwise fail closed.
- The existing `body(for:)` path may persist original message content in the
  ordinary mail cache. Mitigation: audit that behavior before implementation
  claims and keep derived candidate state separate; a zero-persistence
  requirement for source emails needs a separate storage-policy decision.
- Consent can change or an account can be removed while a body read is in
  flight. Mitigation: cancel pending work and recheck consent and eligibility
  before reading and before display.
- A non-activating panel may interfere with other apps' keyboard or focus
  behavior. Mitigation: use only app-local Escape handling and verify focus
  remains unchanged and background Escape is not consumed.
- The `.messagesAdded` consumer may stop with the window closed. Mitigation:
  verify the subscription lifetime first; move the hook only if needed.
- Re-listing can report old mail as new when delivery provenance is missing.
  Mitigation: do not use message age as a substitute for provenance.
- Parser edge cases across providers. Mitigation: synthetic fixtures for
  forged first headers, forged matching `authserv-id`, duplicates and
  conflicting results, absent trust boundaries, and a genuine aligned DMARC
  pass; fail closed by default.
- Multi-account bursts could flood the screen. Mitigation: one panel at a
  time, newest replaces older for the same sender, a small queue cap.

## Remaining implementation evidence gates

The accepted design recorded 2026-10-15 resolves the defaults and
consent scope: separate codes and links opt-ins, both off per account/device;
leave messages unchanged by default; and a 60-second default timeout. It also
requires trusted-provider authentication rather than trusting raw headers,
with a DMARC-only aligned-pass policy and no DKIM-only fallback.

Before provider-dependent implementation proceeds:

- Each enabled provider must supply evidence for its receiving-service trust
  boundary and forged-result handling. Gmail support is not presumed; generic
  IMAP without evidence remains unavailable.
- Eligibility must prove provider delivery/backfill provenance, or fail
  closed. The ten-minute timestamp filter alone is insufficient.
- Implementation must verify subscription lifetime, cancellation and consent
  rechecks, ordinary body-cache side effects, and focused-app behavior. Escape
  must work only while Brev is active; background-app Escape must not be
  consumed. No runtime verification is claimed by this ADR-only PR.
- Any future iOS notification needs its own accepted privacy design before
  notification contents are authorized.

## Provider readiness audit (2026-10-15)

Read-only audit of the current adapters at `64bf2d9`. No live account, raw
private message, or sign-in code was used. These findings identify missing
evidence; they do not establish that a provider can never support this feature.

| Gate | Observed implementation | Result |
| --- | --- | --- |
| IMAP authentication provenance | `IMAPMessageBodyParser.parse` and `structuredBody` take the first matching header through `MIMEHeader.value(named:)`. `MessageBody.authenticationResults` is a raw string with no receiving-service provenance. | Not established. A matching `authserv-id` or apparent pass cannot qualify an account. |
| Gmail authentication provenance | `GmailAPIBackend.body(from:)` uses `headerMap`, which keeps only the first value for each lowercased header name. The documented Message API exposes MIME headers, not a separate trusted DMARC assessment. | Not established. Preserve evidence before interpreting results; API authentication does not authenticate each header's author. |
| IMAP fresh delivery | `IMAPSMTPBackendState.recordListedMessageIDs` seeds a set and emits previously unseen IDs on subsequent listings. The event carries no delivery/backfill origin. | A later page of old mail can be indistinguishable from arrival. Do not use this event alone. |
| Gmail fresh delivery | `GmailAPIBackend.reconcile` calls `emitDiff` after either incremental sync or the `fullSyncRequired` fallback. The diff emits IDs missing from the earlier store snapshot. | Store additions are not proof of fresh delivery; the full-sync fallback loses that distinction. |
| Gmail timestamps | The Message API documents `internalDate` as receipt time for normal SMTP mail, but allows API-migrated mail to use the message's Date header. | Neither `internalDate` nor a recent header timestamp proves delivery origin by itself. |
| IMAP body storage | `IMAPSMTPBackend.messageBody` writes fetched/parsed bodies through `bodyCache.setBody`; `FileIMAPMessageBodyCache` encodes `MessageBody` as JSON and writes it to disk. | The existing fetch path can persist source message content. Memory-only claims apply to derived candidates, not email bodies. |
| Gmail body storage | `GmailAPIBackend.body(for:)` stores fetched full messages and calls `readCache.storeBody`; `SQLiteGmailAccountStore.storeBody` writes `body_json` into `gmail_bodies`. | Source content can persist in ordinary mail storage. No non-persisting body-read guarantee. |
| Closed-window delivery | `BrevMailRootView.mailRootLoadingContent` starts a SwiftUI task which reaches `subscribeToChanges`. | Ownership is verified in source; whether the consumer survives closing the window is not runtime-verified. |

**Current outcome:** neither adapter has demonstrated all required provider
gates. Do not add a capability flag asserting support, connect a detector to
`.messagesAdded`, or expose an enabled setting on the strength of this audit.
The audit does not change ordinary message rendering, fetching, or caching.

To unblock the first provider-dependent implementation slice:

1. Identify a receiving service with documented authentication-header
   sanitization or authoritative authentication metadata, tied to the
   configured authenticated account. RFC 8601 describes the required trust
   boundary; it is not evidence that a particular service implements it.
2. In an isolated test mailbox, verify how sender-supplied first headers,
   matching `authserv-id` values, duplicates, conflicting results and missing
   results are handled. Use only synthetic messages. Record sanitized
   provenance evidence, never real sign-in content. Local parser fixtures
   alone cannot establish the server's behavior.
3. Establish delivery origin through that provider's sync path, including
   import, backfill, reconnect and history-expiry/full-sync cases. If origin
   cannot be established, keep the account unsupported.
4. Only then implement the provider-neutral assessment and eligible-event
   contract with fail-closed fixtures. Preserve ordered header evidence where
   needed; retaining more headers alone must not grant trust.

The sources reviewed below do not establish Gmail's forged-header removal
contract or an authoritative per-message delivery-origin field. This remains
an evidence blocker, not an assumption to encode in a provider adapter.

## Implementation slices

### Isolated detector status (2026-10-15)

The provider-independent part of slice 3 is implemented in BrevMail as internal
`SignInCodeDetector` and `SignInCandidate` types, exercised only by synthetic
Swift Testing fixtures. This work can precede provider evidence because no
production caller, body access, eligibility assessment, capability, setting,
panel or notification is added. Both adapters remain unsupported for live
presentation; all evidence gates above are unchanged.

The deliberately conservative grammar accepts explicit English/Norwegian
sign-in-code wording with 4–8 ASCII digits or 4–8 ASCII alphanumerics containing
at least one digit, preserving the original code spelling. It rejects multiple
code-like values, mixed code/link candidates, common order/price/phone/date
contexts, and delimited numeric fragments. False negatives are preferred to
guessing. Grouped codes, letter-only codes and generic “code” wording are not
recognized in this slice.

Link detection accepts a single explicit plain-text HTTPS destination with
nearby sign-in wording, preserving its exact spelling and exposing its host.
Every displayed domain outside the destination must match that host exactly
(even parent/subdomain differences are rejected). HTML, Markdown, credentials,
ports, IP literals, internationalized hosts, malformed escapes, ambiguous
terminal punctuation and recognizable tracking/redirect/unsubscribe patterns
are rejected. Arbitrary server-side redirect/tracking behavior cannot be
determined locally: this is not a destination-safety verdict. Callers must never
flatten HTML into this input and thereby discard visible/target evidence.

Inputs are bounded to 64 KiB and 128 numeric tokens. Candidate values have no
serialization conformance, caches, logs, storage or sync integration; default
description/debug/reflection surfaces are redacted. These safeguards do not
prevent a future caller from misusing an extracted associated value: the
integration-time lifecycle audit in slice 5 is still required. No user-visible
strings or network/storage behavior change in this slice.

### Isolated consent model status (2026-10-15)

The model-only part of slice 4 is implemented as `SignInCodeSettings` in
BrevSettings. Explicit stable-account-ID records hold independent code/link
booleans, both off for missing accounts, with no global inherited enable.
Persistence requires injected local `UserDefaults`; malformed records or
key/account-ID mismatches fail closed. Explicit removal deletes the persisted
account record, and removing the last record removes the storage key. Initial
behavior is fixed: leave the source message unchanged and a 60-second timeout.

Synthetic tests exercise account isolation, independent opt-ins, local-only
persistence, malformed data, deletion, and exclusion from backup export/import
in both restore modes and the cloud allowlist. The model is not included in
`SettingsBackupPayload` or `PreferenceSyncAllowlist`, and no settings-store or
account-lifecycle caller is added. Consent is not provider eligibility. No
detector invocation, candidate persistence, body read, network call, UI, panel,
notification or AppSession wiring is added; both providers remain unsupported.
The consent explanation and integration-time privacy updates remain unshipped.

### Remaining integration slices

1. Verify provider delivery/backfill provenance and authentication trust
   boundaries before enabling any account. Preserve ordered duplicate headers
   or obtain authoritative provider metadata as needed; add synthetic
   fixtures for forged first headers, forged matching `authserv-id`, duplicate
   and conflicting results, absent boundaries and genuine aligned DMARC pass.
   Unsupported providers remain unavailable.
2. Implement opt-in-gated eligibility and body access: per-account/device
   codes and links both default off; require freshness provenance, timestamp,
   folder and trusted-provider capability before `body(for:)`; recheck consent
   before asynchronous reads and display; cancel on disable or account removal.
3. Add the local deterministic detector and English/Norwegian false-positive
   fixtures. Detection must not run before opt-in, even for cached bodies.
4. Wire the isolated `SignInCodeSettings` model and add the in-context consent
   explanation. Keep consent out of backup/iCloud, default post-use behavior to leave messages
   unchanged, and set the panel timeout default to 60 seconds. Update
   `PRIVACY.md` and ADR-0006 as part of implementation, before shipping.
5. Audit existing body-cache persistence and test that derived candidate and
   panel state is never logged or persisted. Verify subscription lifetime
   with the main window closed before moving the hook, and verify focused-app
   behavior, app-active Escape, and unconsumed Escape in other apps.
6. Defer iOS notifications until a separate privacy design is accepted.

## References

- Issue #239.
- `BrevBackend/Models.swift` (`MailEvent`, `MessageBody`),
  `BrevMail/BrevMailRootView.swift` (`handleBackendEvent`),
  `MessageHeaderAnalyzer`, `MessageSecurityWarningPolicy`,
  `BrevSettings/NotificationSettings.swift`.
- RFC 8601 (Authentication-Results), RFC 7489 (DMARC).
- [RFC 8601 trust boundary and header handling](https://www.rfc-editor.org/rfc/rfc8601.html).
- [Gmail Message resource, headers and internalDate](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages).
- [Gmail history records and full-sync fallback](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list).
