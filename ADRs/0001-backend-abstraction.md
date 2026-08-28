# ADR-0001: MailBackend domain boundary

- **Status:** Accepted
- **Date:** 2026-08-28
- **Deciders:** Henrik

## Context

Brev supports a native Gmail adapter and a standards-based IMAP/SMTP adapter.
Both must feed one SwiftUI application without leaking provider data-transfer
objects, persistence types, or authentication details into views.

## Decision

1. Every mail adapter conforms to `MailBackend`.
2. `BrevBackend` owns plain Swift domain models for accounts, folders,
   messages, drafts, search, mutations, and events.
3. Views consume `MailBackend` and capability flags. They never type-check a
   concrete adapter.
4. Provider packages translate their protocol or API responses into Brev
   domain models before returning data.
5. Realm and cache implementation types stay behind the backend boundary.
6. Optional provider features use explicit capabilities and extension
   protocols rather than widening the base interface for one adapter.

## Rationale

The boundary keeps the UI stable while each adapter implements its native
authentication, sync, labels, search, and mutation behavior. Capability-driven
presentation lets Brev explain differences without scattering provider checks
through the app.

## Consequences

- `GmailAPIBackend` and `IMAPSMTPBackend` share one application contract.
- New adapters must translate into Brev domain models and declare capabilities.
- Tests can exercise UI and orchestration against backend fakes without loading
  a provider SDK or Realm object.

## References

- ADR-0028: Mail provider architecture and invariants
- ADR-0029: IMAP/SMTP backend foundation
- ADR-0064: First-class Gmail API backend
