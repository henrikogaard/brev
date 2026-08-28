# ADR-0032: Server-side filters with ManageSieve

- **Status:** Proposed
- **Date:** 2026-06-09
- **Deciders:** Henrik

## Context

The related feature request asks Brev to evaluate server-side filters alongside local
rules. Local rules already exist and are useful, but they only run when
Brev is open on the current device. Users expect server-side filters to
apply across devices and while the app is fully quit.

Brev already has early backend-neutral rule models (`ServerRule`,
`ServerRuleCondition`, `ServerRuleAction`) and capability flags such as
`manageSieve`, `sieveVacation`, and `serverRules`. There is also
quarantined provider API code for the provider filters. That is enough to
shape a standards-first path, but not enough to safely edit server
scripts.

ManageSieve introduces new network behavior. Per ADR-0006 and
ADR-0028, Brev must not add background probes or third-party calls
without an explicit opt-in and privacy disclosure.

## Decision

1. **ManageSieve is an optional backend extension.**
   It does not become a required `MailBackend` method. Backends expose
   it through capability flags and an extension service. Views and
   settings surfaces gate UI on capabilities, never on concrete backend
   types.

2. **Discovery is user-initiated.**
   Brev does not automatically probe ManageSieve during startup, account
   restore, or mailbox refresh. The first connection attempt happens
   when the user opens server-side filter settings for an account and
   chooses to check server-side filter support. Account setup may offer
   an explicit checkbox or button later, but it must remain opt-in.

3. **The first network target is the user's mail provider only.**
   ManageSieve connects to the configured provider host or a
   user-confirmed SRV/autoconfig result for the account domain. It does
   not contact third-party rule services. `PRIVACY.md` and ADR-0006 must
   document the opt-in probe before implementation ships.

4. **Existing server scripts are preserved.**
   Brev lists existing scripts and active state when the server allows
   it, but it does not rewrite unknown scripts in order to translate
   them into Brev's simplified rule model. Unknown scripts are shown as
   read-only or opened in a raw script editor only after explicit user
   action.

5. **Brev-owned rules are written to a Brev-owned script.**
   The first writable slice manages a dedicated script, for example
   `brev-rules`. Brev may activate that script only after presenting the
   impact to the user. If the server supports only one active script,
   Brev must not deactivate an existing user script without explicit
   confirmation and a recoverable backup path.

6. **Rule translation starts with a conservative subset.**
   The first supported mapping is limited to conditions and actions Brev
   can round-trip safely: sender contains, recipient contains, subject
   contains, has attachment where supported, move to folder, archive,
   mark read/unread, flag, delete, and forward only with explicit
   destructive confirmation. Unsupported Sieve extensions keep rules
   read-only.

7. **Local rules remain the fallback.**
   Providers without ManageSieve or provider rule APIs keep using local
   rules. Brev may offer to duplicate compatible local rules into a
   server-side script after support is confirmed, but migration is never
   automatic.

8. **Validation is server-backed and fail-closed.**
   Brev relies on the ManageSieve server's script validation through
   upload/activation semantics. Failed validation leaves the existing
   active script untouched and reports the server error in plain user
   copy.

## Rationale

**Provider APIs only were rejected.** Provider APIs can be richer, but
the standards-first IMAP/SMTP roadmap needs a portable filter path for
providers such as Fastmail and self-hosted mail servers.

**Automatic background discovery was rejected.** It would create network
traffic outside a user action and conflict with Brev's zero-network-by-
default posture for optional features.

**Full local-rule-to-Sieve translation was rejected for the first
slice.** Sieve extensions vary widely. A small round-trippable subset is
safer than generating scripts that appear valid but behave differently
on different servers.

**Overwriting the active script was rejected.** Many users already have
server scripts created by webmail or another client. Brev should not
take ownership of those scripts just because it can connect.

**A raw script editor as the only UI was rejected.** It is powerful but
not friendly enough for the product. A raw editor can exist as an
advanced affordance, while normal users get a structured rule editor for
the safe subset.

## Consequences

### Accepted

- The related feature request implementation must include a privacy update because it
  adds an opt-in network call to the user's provider.
- Backend work should add a standards-first ManageSieve client and a
  backend extension service, then reuse the existing server-rule domain
  model where it can round-trip safely.
- Settings UI should distinguish local-only rules from server-side
  rules and explain that server-side rules run even when Brev is closed.
- Tests must cover capability gating, no automatic discovery on restore,
  safe listing, unknown-script preservation, Brev-owned script writes,
  activation failure preserving prior active state, and local-rule
  fallback.

### Risks

- ManageSieve authentication mechanisms vary by provider and may need
  app-password, OAuth SASL, or provider-specific configuration.
- Folder names in Sieve `fileinto` scripts may not match IMAP display
  names without careful UTF-7 and hierarchy handling.
- Servers differ in supported extensions, especially vacation, variables,
  body tests, relational tests, and spam-test extensions.
- A single-active-script server can make the user experience harder when
  existing non-Brev scripts are already active.

## Implementation status (2026-06-28): setup-time SRV discovery

The ManageSieve backend (client, `ManageSieveRuleSyncing` extension service,
`.manageSieve` capability), the settings sync UI, and the account-setup
ManageSieve fields had already landed. The remaining gap (the related feature request) was that
autodiscovery never populated the endpoint, so users had to type it by hand.

`MailAccountAutodiscovery` now includes the RFC 5804 `_sieve._tcp` record in the
existing setup-time SRV batch (`MailServiceSRVRecordSet.sieve`,
`MailSRVDiscovery.manageSieveSettings`). When a domain advertises it, the
discovered endpoint pre-fills the (opt-in) ManageSieve fields in the setup sheet
for the user to review before completing setup.

This stays within decisions 2 and 3:

- It is a **domain-only DNS SRV lookup** in the same privacy class as the
  existing `_imap`/`_submission` setup probes — no email address transmitted,
  and **no connection to the ManageSieve server**. The first actual ManageSieve
  connection still happens only when the user opens server-side filter settings.
- The discovered endpoint is a **user-confirmed SRV result** (decision 3); the
  user reviews and completes setup before it is stored. `PRIVACY.md` is updated
  to disclose the `_sieve._tcp` probe.

ManageSieve has no implicit-TLS SRV variant, so the discovered endpoint is
recorded as STARTTLS. The endpoint is stored as a `MailServerSettings` with the
`.imap` kind placeholder, matching the existing `IMAPAccountConfiguration.manageSieve`
convention (the kind is unused on the sieve transport). Built-in provider
profiles still do not seed ManageSieve endpoints — that remains follow-up work.

Verified by the `MailSRVDiscovery` suite (`BrevBackend`, 868 tests pass).

## Implementation status (2026-06-28): Create Rule from Message (#268)

The message context menu's "Create Rule from Message…" action (previously hidden
as a no-op per the #262 honesty pass) is now wired. It creates a **local** rule,
consistent with decision 7 (local rules remain the fallback; migration to a
server script is never automatic):

- `MessageRuleDraftBuilder.draft(for:)` seeds a `LocalRuleEditorDraft` with a
  `senderContains(<sender>)` condition and a safe, non-destructive default action
  (mark read); the rule is named after the sender. The user reviews and edits it
  (e.g. switching to move-to-folder) in the existing `LocalRuleEditorSheet`
  before saving.
- On save the rule is appended to `LocalRulesSettings` (local, UserDefaults).
  Syncing it to a ManageSieve server stays the separate, existing opt-in in
  Settings → Rules — no rule is pushed to a server by this action.

Wired in both the regular and Unified Inbox message lists; the reader's detail
context menu is unchanged. Verified by `MessageRuleDraftBuilder` tests and the
updated `MessageCommandPresentation` matrix (`BrevMail`).

## References

- ADR-0001: Backend abstraction for multi-provider
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0028: Standards-first IMAP/SMTP roadmap
- The related feature request: Evaluate server-side filters (Sieve) alongside local rules
- RFC 5228: Sieve Email Filtering Language
- RFC 5804: ManageSieve protocol
- RFC 5230: Sieve Vacation extension
