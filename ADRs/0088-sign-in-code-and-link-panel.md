# ADR-0088: Show sign-in codes and links on screen as they arrive

- **Status:** Proposed
- **Date:** 2026-10-11
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
than a normal notification: a spoofed message must never be surfaced, and a
code must never end up in a log, a store, a sync payload or a diagnostics
file. What the codebase gives us today (checked 2026-10-11):

- New mail is `MailEvent.messagesAdded(folderID:messageIDs:)` from
  `subscribeToChanges()`. It is consumed only in `BrevMailRootView`
  (`handleBackendEvent`), next to `NewMailNotificationPolicy`. IMAP seeds the
  known-ID set on the first listing of a folder and emits for later unknown
  IDs, so a deeper page load can in principle report old mail as added. No
  message-age check exists.
- `MessageHeader` carries a `snippet` only. The body and the raw
  `Authentication-Results` header are on `MessageBody` and need
  `backend.body(for:)`, which fetches on a cache miss.
- `MessageHeaderAnalyzer` parses DMARC *failure* only. There is no pass
  parsing, and raw SPF/DKIM results are deliberately not surfaced today.
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
   (a time-sensitive local notification, issue follow-up). Nothing here
   changes the phone UI.
2. **Detection is local and deterministic.** A pure `SignInCodeDetector` in
   BrevMail takes plain-text body content and returns at most one candidate:
   a code (4-8 digits, or short alphanumerics, near sign-in wording in English
   and Norwegian) or one prominent sign-in link. It rejects tracking and
   unsubscribe links, order numbers, prices, phone numbers and dates. No AI
   and no remote service.
3. **Only genuinely new, recent, primary mail.** A message qualifies only if
   it arrives through `.messagesAdded` after the account's first listing, its
   own date is within 10 minutes, and its folder is Inbox-class. Spam, Trash,
   Archive, Sent and Drafts never qualify. The age check is the backfill
   guard the event lacks.
4. **Authentication gate, fail closed.** A new pure parser reads the topmost
   `Authentication-Results` header only. A message qualifies on `dmarc=pass`,
   or on `dkim=pass` with a signing domain aligned to the From domain. A
   missing header, an `fail`/`softfail`/`none` result, or a mismatch means it
   is never surfaced. Gmail and IMAP differences are handled in the parser's
   fixtures.
5. **Body fetch policy.** The body is read from the cache when present. On a
   miss, one `body(for:)` fetch over the account's existing connection is made,
   and only for messages that already passed decision 3. No new endpoint, no
   third party.
6. **Links.** Only https links. The panel shows the real destination host
   before opening. A link whose visible text and target host disagree (the
   existing mismatch policy) gets no one-click open. Opening uses the default
   browser.
7. **Nothing is kept.** The candidate lives in memory while the panel is
   visible. It is never logged, persisted, synced, put in a notification
   `userInfo`, written to the Realm store or a widget snapshot, or included
   in diagnostics or QA artifacts. A test enforces the logging and persistence
   rule.
8. **Clipboard.** Copy writes with `org.nspasteboard.ConcealedType`. An
   optional "clear after N seconds" clears only if the pasteboard change count
   is unchanged since Brev wrote it.
9. **Panel.** A non-activating `NSPanel` at the bottom centre of the active
   screen, above other windows, that never takes keyboard focus. It dismisses
   on click, Escape, the close control or a timeout (default 60 s). A newer
   code from the same sender replaces the older one. Content uses `BrevToast`
   (BrevDesign is not edited).
10. **Closed window.** The arrival hook moves out of the view into an
    `AppSession`-owned controller so it works while the main window is closed,
    for as long as Brev is running and syncing. If the verification below shows
    the subscription already survives, only the new consumer moves.
11. **Settings.** A `SignInCodeSettings` model modelled on
    `NotificationSettings.AccountOverride`, with a section in BrevSettings:
    codes on/off, links on/off (both default on, per account), post-use action
    (leave, mark read, archive; default leave), panel timeout, clipboard
    clearing. The settings are device-local and excluded from settings backup
    and iCloud key-value sync (ADR-0076).
12. **Privacy docs.** `PRIVACY.md` gains a short note: local processing, no
    network beyond the existing mail fetch, in-memory only. ADR-0006's
    network-call table gets a row for the body fetch.

## Rationale

- **Detector over a notification trick.** macOS Notification Center would
  keep a copy of the code in its history and cannot be controlled by Brev. A
  panel we own holds it in memory only.
- **Authentication gate over trusting all mail.** A phishing message that
  asks the person to "copy this code" or "open this link" is the main abuse.
  Requiring a pass result, and showing the real host, keeps the feature from
  making that attack easier. The cost is that mail from providers that do not
  add `Authentication-Results` is skipped.
- **Body fetch over snippet-only.** Snippets are short, so many codes sit
  beyond them, and the authentication result is not in the header. The fetch
  is bounded by recency and folder gates.
- **Rejected:** AI extraction (content would leave the device or add a model
  dependency); showing every code regardless of authentication; one global
  setting only (people have accounts they do not want scanned); persisting
  recent codes for a history view (it conflicts with decision 7).

## Consequences

### Accepted

- A new macOS window type, a new controller owned by `AppSession`, and one
  extra body fetch per qualifying new message.
- Mail from senders without a passing `Authentication-Results` header never
  shows a panel.
- The panel is Mac only until the iOS slice ships.

### Risks

- The `.messagesAdded` consumer may stop with the window closed. Mitigation:
  verify first (below); move the hook only if needed.
- Re-listing could report old mail as new. Mitigation: the 10-minute age gate
  on the message's own date.
- Parser edge cases across Gmail and IMAP servers. Mitigation: fixture tests
  from real header shapes, with fail-closed defaults.
- Multi-account bursts could flood the screen. Mitigation: one panel at a
  time, newest replaces older for the same sender, a small queue cap.

## Open questions for Henrik

1. Default on (as the issue says) or off until the person enables it? A default
   of "on" means every new inbox message gets a body fetch.
2. Default post-use action (leave unchanged) and panel timeout (60 s).
3. Is `dkim=pass` with alignment enough when DMARC is absent, or require DMARC?

## Implementation slices

1. `SignInCodeDetector` with English and Norwegian fixtures and false-positive
   tests. No UI.
2. `AuthenticationResultsParser` and the eligibility policy (recency, folder,
   authentication), with tests.
3. `SignInCodeSettings` and the Settings section, `PRIVACY.md`, ADR-0006 row.
4. macOS panel and the `AppSession` hook, with the no-logging/no-persistence
   test. First step: verify the subscription lifetime with the window closed.
5. iOS notification follow-up.

## References

- Issue #239.
- `BrevBackend/Models.swift` (`MailEvent`, `MessageBody`),
  `BrevMail/BrevMailRootView.swift` (`handleBackendEvent`),
  `MessageHeaderAnalyzer`, `MessageSecurityWarningPolicy`,
  `BrevSettings/NotificationSettings.swift`.
- RFC 8601 (Authentication-Results), RFC 7489 (DMARC).
