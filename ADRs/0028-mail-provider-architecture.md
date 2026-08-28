# ADR-0028: Mail provider architecture and invariants

- **Status:** Accepted
- **Date:** 2026-08-28
- **Deciders:** Henrik

## Context

Brev supports Gmail and standards-based mail accounts on macOS and iOS. The
product needs one UI and one domain model while still allowing each provider
adapter to implement its native sync, labels, search, and authentication.

## Decision

1. `MailBackend` is the provider boundary. The current adapters are
   `GmailAPIBackend` and `IMAPSMTPBackend`.
2. Generic account setup uses standards discovery and manual IMAP/SMTP
   configuration. Gmail and Google Workspace use the Gmail API by default.
3. Views consume plain Brev domain models and capabilities. They do not import
   provider DTOs, Realm objects, or concrete backend types.
4. Provider differences appear through capability flags and extension
   protocols. A view must not branch on a backend's concrete type.
5. `BrevBackend` owns domain contracts. Provider packages depend inward on
   those contracts. UI packages do not become provider dependencies.
6. Body rendering and compose preparation remain provider-neutral seams.
7. External network behavior follows ADR-0006. New calls require explicit
   user intent, privacy documentation, and focused tests.
8. Native Microsoft Graph, Microsoft 365, Outlook, and Exchange support is
   future scope under ADR-0040.

## Rationale

One deep provider interface keeps account-specific protocol behavior inside
the adapter while the app presents a consistent mailbox. Capabilities let the
UI explain real differences without pretending that every backend supports the
same features.

## Consequences

- Gmail labels and history sync stay inside `BrevGmail`.
- Other providers connect through IMAP/SMTP without provider-specific UI code.
- Realm remains an implementation detail behind plain Swift models.
- A future provider adapter must implement `MailBackend` and expose behavior
  through the existing capability model.

## References

- ADR-0001: Backend abstraction
- ADR-0006: Telemetry and privacy
- ADR-0029: IMAP/SMTP backend foundation
- ADR-0030: Full IMAP sync and cache engine
- ADR-0040: Native Exchange and Microsoft 365 scope
- ADR-0064: First-class Gmail API backend
