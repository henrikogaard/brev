# Account lifecycle — QA pass (issue #2, 2026-09-26)

Credential-free evidence plus the live-pass attempt against the disposable
generic-IMAP (mailo.com) and Gmail QA accounts. Repo-scoped secrets
(`BREV_LIVE_MAIL_*`, `BREV_GOOGLE_OAUTH_*`, `BREV_QA_GOOGLE_*`) were
provisioned on 2026-09-26; values are never recorded here.

## Automated local smoke

| Script | Result | Notes |
|--------|--------|-------|
| `scripts/imap-smtp-local-smoke.sh` | pass | `imap-smtp-local-smoke: OK` — local IMAP/SMTP fixture round-trip |
| `scripts/check-imap-oauth-setup.sh` | pass | `preflight: IMAP OAuth configuration ready (2 provider(s))` |

## Missing Google client configuration guidance

Not reproducible in this build: the test/mock build already carries both Google
OAuth client IDs — `check-imap-oauth-setup.sh` reports
`preflight: IMAP OAuth configuration ready (2 provider(s))` (macOS + iOS client
IDs configured). The "missing client configuration" guidance copy could not be
screenshotted because Add Account → Google is fully wired here; exercise on a
build without client IDs, or confirm copy in the live pass if it differs.

## Generic IMAP capability exposure

A generic IMAP/SMTP account exposes a reduced capability set vs the Google
provider, and the UI hides the affordances behind capability checks rather than
backend-type checks (ADR-0001 rule 3). Notable gates a plain IMAP account fails:

- `.labels` — label/smart-view surfaces and label moves are suppressed
  (`MessageListView.swift` L978/L2901, `MailMoveUndoRegistration.swift` L155,
  `FolderSidebarPresentation.swift` L290 combined with `.providerAPI` /
  `.serverSideThreading`).
- `.serverSideSearch` — search execution degrades to `.cacheOnly`; the
  Server execution chip is not offered (`UnifiedInboxSearch.swift` L28,
  `MessageListSearchDebouncePolicy.swift` L205/L209).
- `.blockSender` — Block-sender action omitted from menus
  (`MessageListView.swift` L949, `MessageDetailView.swift` L770,
  `ThreadConversationView.swift` L380).
- `.junkAPI` — junk reporting adjusts (`MessageCommandPresentation.swift` L408).
- `.aliases` / `.serverSignatures` — composer hides alias picker and signature
  management (`ComposeView.swift` L1568/L3575/L3619).
- `.serverRules` / `.manageSieve` — Settings → Rules features hidden
  (`RulesSection.swift` L166/L635).
- `.smtpOAuth` — OAuth-specific reply/auth paths disabled
  (`BrevMailRootView.swift` L5577/L7021).
- `.folderCreate` / `.folderRename` / `.folderDelete` / `.folderFlush` —
  sidebar folder-management actions gated individually
  (`FolderSidebarPresentation.swift` L461–472).

## Live IMAP/SMTP (generic provider — mailo.com disposable)

### Round 2 — `fix/imap-smtp-provider-compat` (D5/D6 fixed, 2026-09-26)

`imap-smtp-live-smoke.sh` (secrets via env only):

| Stage | Result |
|-------|--------|
| connect :993, folder list (9), connector restore, IDLE wiring | pass |
| headers / body / attachment fetch, server search | pass |
| folder create/rename/delete, flush, message mutations | pass |
| SMTP `--validate-smtp-setup` | pass — AUTH LOGIN exchange accepted |
| SMTP `--send-test-message` + compose lifecycle | **pass — `imap-smtp-live-smoke: OK`** (real message submitted; Drafts save/send/discard pass) |
| multi-word TEXT / non-ASCII server-side search | fail — provider charset/TEXT-search gap (observation O4, not caused by the fix) |
| `--exercise-idle-event` | timeout — provider emits no same-account APPEND notifications; script marks this provider-optional |

macOS live test app (built from the fix branch): autodiscovery resolved
provider settings ("Mailo"), password entered, **Test connection →
"IMAP and SMTP connection test succeeded"**, Add account completed and
the inbox loaded. Refresh showed new mail; a compose-window self-send
("QA app send test") arrived in the inbox ~30 s later. A transient
"IMAP transport session changed while reading" banner appeared once;
Retry reconnected and cleared it — that doubles as the reconnect leg.
Settings → Accounts → Remove → "No accounts signed in"; `security
dump-keychain` shows zero brev/mailo entries (no credential residue, no
stale rows). Capability gating on the live account matches the
hidden-affordance list above (no label/rules/block-sender affordances
shown).

iOS live leg — **pass with signed build** (round 3): building BrevIOS
with `DEVELOPMENT_TEAM=45AD7E7G5G -allowProvisioningUpdates` (ad-hoc
"Sign to Run Locally" is NOT sufficient — the unsigned
`CODE_SIGNING_ALLOWED=NO` build gets `-34018` from securityd on every
keychain write; with the team-signed build the same writes succeed).
Full lifecycle on iPhone 17 sim: autodiscovery → Test connection →
Add account → inbox loads (5 messages) → compose self-send arrived in
inbox ~40 s → terminate+relaunch restores account and mailbox
(reconnect leg) → Settings → Accounts → Remove → "No accounts signed
in". One UI quirk observed while typing the recipient: the To field
committed a partial "He" chip mid-keystroke and autocompleted the rest;
pasting the address worked. Unsigned-build keychain failure kept as
observation O6 — environment limitation, not an app defect.

Observation (D7 noted earlier): the "Reconnect your mailbox" title is
`session.signInError != nil`, not a persisted account — misleading copy
after a failed add, no zombie state.

### Round 1 — before the fix (blocked, kept for history)

| Stage | Result | Notes |
|-------|--------|-------|
| connect/list/restore/IDLE | pass | |
| SELECT INBOX | fail | unconditional `(CONDSTORE)` modifier — **D5**, fixed above |
| SMTP validation/send | fail | only AUTH LOGIN advertised — **D6**, fixed above |
| macOS manual add | partial | error surfaced; sheet stayed open (correct); D7 copy issue recorded |

## O4 triage — server-side TEXT search on mailo.com (diagnosis, no fix)

Client encoding is RFC-correct: `IMAPSessionClient.searchTokens` splits
`SearchQuery.text` on whitespace into `TEXT "live" TEXT "search"` atoms
(AND semantics, quoted strings for ASCII), and `executeSearch` adds
`CHARSET UTF-8` + synchronizing literals only when a value carries
non-ASCII octets. The failing smoke guards search `TEXT` for body
content ("live search", "søk røyk") — mailo's `TEXT` indexing appears to
cover only envelope headers (subject/subject-key searches succeed
identically), i.e. a provider body-indexing limitation, not a wire bug.
Fix candidate if pursued: verify against Dovecot before changing the
client.

## Live Gmail rows

**Still blocked — device verification, not 2SV.** Henrik disabled 2-Step
Verification; password entry now proceeds to a "Verify it's you" screen
offering only: verification code by SMS to the recovery phone (•••55), a
voice call to it, "use another phone or computer to finish signing in",
or "confirm your recovery phone number". All require the phone or an
already-signed-in device — none can be completed from this environment.
Evidence: `docs/qa/live-pass-2026-09-26/google-verify-redacted.png`.
The OAuth sheet itself (ASWebAuthenticationSession → accounts.google.com)
launches correctly and the client ID is honored. Needs Henrik to either
approve the sign-in on a trusted device or provide a fully password-only
account.

iOS onboarding shows only "Add mail account" — no "Continue with
Google" row — **resolved (O5, 2026-09-26):** the iOS OAuth client ID is
NOT baked by `tuist generate` (the checked-in pbxproj keeps empty
`BREV_GOOGLE_OAUTH_*` values by design). `script/build_and_run.sh`
injects them as xcodebuild build-setting overrides; a plain `xcodebuild`
without those overrides produces a build with no Google row. Verified
on iPhone 17 sim iOS 27.0: building with the client-ID override yields
the "Continue with Google" row (Info.plist carries the 72-char ID); the
same build without it shows the missing-config guidance added in #116.
Stale builds must be regenerated/rebuilt via `script/build_and_run.sh`
(or equivalent overrides) — see the blueprint's `ios-oauth` knowledge
entry.
