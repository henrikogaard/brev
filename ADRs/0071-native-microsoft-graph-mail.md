# ADR-0071: Native Microsoft Graph mail and shared mailboxes

- **Status:** Proposed
- **Date:** 2026-09-05
- **Deciders:** Henrik
- **Amends on acceptance:** ADR-0040, ADR-0066
- **Tracking:** #28

## Context

The existing Microsoft compatibility path uses OAuth over IMAP/SMTP and cannot
serve tenants that disable those protocols. Work-account parity needs native
mail, permission-aware shared sources, and send-as behavior behind Brev's
existing provider-neutral interface.

## Decision

1. Add a `BrevMicrosoft` provider package implementing `MailBackend` using
   Microsoft Graph v1.0. The package depends inward on BrevBackend domain types.
2. Use the system-browser native OAuth authorization-code/PKCE flow. Store
   tokens only in Keychain. Normal mail setup requests delegated user mail
   permissions; adding shared mail requests the additional delegated shared-mail
   scopes only after the user explicitly selects that feature.
3. Model the signed-in identity as the account and each primary/shared mailbox
   as a `MailSourceID`. Shared sources are added explicitly; do not request broad
   directory-read or tenant-wide application permissions merely to discover them.
4. Implement folder/message pagination, MIME/body/attachment access, search,
   drafts/send, delta reconciliation, offline caching and recoverable mutations.
   Preserve Graph's move/immutable-ID semantics in mutation receipts and Undo.
5. Check provider permissions for shared-folder access and send-as/send-on-behalf.
   OAuth scopes do not grant mailbox permissions by themselves. Surface consent,
   tenant policy, revoked permission, throttling and reauthentication distinctly.
6. Reuse the mail UI and capability model. A shared mailbox appears as another
   collapsible source inside the selected profile, with its own folder tree.
7. Use delegated access for the initial implementation. Shared-folder webhook
   subscriptions require different permissions; foreground/local background
   reconciliation must not imply remote push or silently escalate to application
   permissions.
8. Keep on-premises EWS/MAPI outside this implementation. The first supported
   target is Microsoft 365/Exchange Online and compatible Microsoft accounts.
9. Record exact hosts, data, OAuth scopes, defaults, and consent points in
   PRIVACY.md and ADR-0006 before introducing provider calls. App registration,
   tenant consent, credentials, live shared-mailbox QA, and release remain
   separate external gates.

## Alternatives

IMAP-only support leaves the identified workplace gap. EWS-first would make
legacy compatibility dictate the architecture. Tenant-wide application access
is inappropriate for an ordinary personal desktop/mobile client.

## Consequences

A new adapter, authentication option, cache/replay coverage, and contract tests
are required. Rate limits, continuation links, delta resets, shared-mailbox
permissions, and ambiguous send outcomes need dedicated fixtures and live QA.
The API is independently implemented; Brev views never import Graph DTOs.
Approving the design does not grant account consent or tenant permissions.

## References

- [ADR-0040](0040-native-exchange-microsoft365-scope.md)
- [ADR-0066](0066-current-provider-scope.md)
- [Graph mail API](https://learn.microsoft.com/en-us/graph/api/resources/mail-api-overview?view=graph-rest-1.0)
- [Shared/delegated mail](https://learn.microsoft.com/en-us/graph/outlook-share-messages-folders)
- [Permission reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
