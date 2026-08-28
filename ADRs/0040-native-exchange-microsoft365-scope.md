# ADR-0040: Native Exchange and Microsoft 365 scope

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Amends:** ADR-0028
- **Amended by:** ADR-0042

## Context

ADR-0028 made Brev standards-first for launch: IMAP receive/sync,
SMTP submission, password/app-password setup, and OAuth-over-IMAP where
provider profiles support it. That keeps Brev broadly useful without
making provider-specific APIs a launch dependency.

The related feature request reopens the Exchange deferral. Outlook, Apple Mail, and eM
Client can connect to Microsoft 365 or Exchange mailboxes even when the
tenant disables IMAP. Brev's current Outlook/Microsoft support is not
native Exchange support: it uses Microsoft OAuth to request IMAP and
SMTP access against `outlook.office365.com` and `smtp.office365.com`.
That path still fails for tenants that disable or restrict IMAP.

## Decision

Native Exchange and Microsoft 365 support is accepted as future scope,
but it remains outside the standards-first launch backend.

1. **Microsoft Graph mail is the primary native Microsoft 365 path.**
   A future provider-specific backend may use Graph mail, folder,
   attachment, search, delta/history sync, shared mailbox, and rules
   APIs behind `MailBackend`.

2. **EWS is a compatibility lane, not the first native path.** EWS may
   be evaluated for on-premises and hybrid Exchange accounts after the
   Graph-backed Microsoft 365 path is designed. It should not block
   Graph work, and Brev should not pretend EWS covers modern Microsoft
   365 tenants as the preferred API.

3. **Exchange Autodiscover is in scope for native Exchange setup.**
   ADR-0028's IMAP/SMTP autodiscovery remains the launch path. A native
   Exchange setup slice may add Exchange Autodiscover, but it must
   disclose what account identifiers leave the device before probing.

4. **Direct MAPI implementation is out of scope.** Brev will not build
   or previous package a direct MAPI transport unless a future ADR explicitly
   reverses this decision.

5. **Current Microsoft sign-in remains OAuth-over-IMAP/SMTP.** The
   account setup UI must describe that limitation clearly and tell users
   with IMAP-disabled Microsoft 365 tenants that native Exchange support
   is future work.

6. **Provider-native work must stay capability-driven.** Views must
   branch on backend capabilities such as provider API, shared mailboxes,
   server rules, delta sync, and aliases rather than checking for a
   concrete Exchange backend type.

7. **No new Microsoft network call is introduced by this ADR.** Before a
   Graph, EWS, or Exchange Autodiscover implementation ships, ADR-0006
   and `PRIVACY.md` must be updated with the exact hosts, scopes, data
   sent, defaults, and user controls.

## Rationale

Staying IMAP-only would keep the launch backend simple, but it would
make Brev unusable for a common business-mail configuration. Accepting
native Exchange as future scope keeps Brev credible for work accounts
without derailing the current standards-first implementation.

Graph is the right first Microsoft 365 target because it is the modern
Microsoft API surface and maps to capabilities Brev already tracks:
provider APIs, server-side search, shared mailboxes, aliases, rules,
and delta sync. EWS remains valuable for legacy Exchange deployments,
but it should be sequenced after Graph so the compatibility layer does
not define the whole Microsoft architecture.

## Consequences

- The related feature request is resolved as "future scope accepted, launch deferral
  preserved."
- The account setup screen now distinguishes Microsoft OAuth-over-IMAP
  from future native Exchange support.
- Future Graph/EWS work requires its own design and privacy update
  before implementation, including token scopes, tenant/admin consent
  behavior, shared mailbox semantics, retention/compliance boundaries,
  and local cache implications.
- ADR-0028 remains the authority for launch sequencing: IMAP/SMTP is
  first; provider-native Microsoft APIs follow later behind
  `MailBackend`.

## References

- ADR-0001: Backend abstraction for multi-provider
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0028: Standards-first IMAP/SMTP roadmap
- The related feature request: Exchange / Microsoft 365 support
