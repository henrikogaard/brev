# ADR-0066: Current provider scope

- **Status:** Accepted
- **Date:** 2026-08-28
- **Deciders:** Henrik
- **Amends:** ADR-0028, ADR-0040, ADR-0046, ADR-0059, ADR-0064

## Context

Brev needs a precise statement of which account types are first-class in the
public baseline and which integrations remain future work.

## Decision

1. Gmail and Google Workspace use `GmailAPIBackend` as the native path.
2. Other compatible providers use `IMAPSMTPBackend` through standards-based
   discovery or manual configuration.
3. CalDAV and CardDAV discovery use provider-neutral RFC well-known endpoints.
4. Provider identity does not grant hidden UI behavior. Capabilities determine
   which actions and status messages appear.
5. Microsoft OAuth over IMAP/SMTP is a compatibility path, not native Outlook
   or Exchange support.
6. Native Microsoft Graph, Microsoft 365, Outlook, shared-mailbox, and Exchange
   behavior remains future scope.

## Rationale

A small, explicit provider set makes setup copy, capability handling, testing,
and support expectations honest. Generic standards accounts stay generic;
Gmail-native behavior stays in `BrevGmail`; future Microsoft behavior has a
clear adapter boundary.

## Consequences

- Public support claims cover Gmail API and secure IMAP/SMTP.
- Any compatible IMAP/SMTP server may connect without becoming a named native
  provider.
- Future Microsoft work must satisfy `MailBackend` and the capability-driven UI
  rules in ADR-0028.

## References

- ADR-0001: Backend abstraction
- ADR-0028: Mail provider architecture and invariants
- ADR-0040: Native Exchange and Microsoft 365 scope
- ADR-0046: Capability-driven AI and calendar discovery
- ADR-0059: Malformed domain-derived DAV endpoint handling
- ADR-0064: First-class Gmail API backend
