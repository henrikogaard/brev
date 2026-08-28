# ADR-0042: Enterprise and admin policy scope

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Amends:** ADR-0040
- **Amended by:** ADR-0043

## Context

Outlook and eM Client are strong in managed work environments because they
surface Exchange/Microsoft 365 concepts such as shared mailboxes, delegation,
Send As, Send on Behalf, retention/compliance policy, sensitivity labels,
server rules, forwarding, and admin-disabled controls.

Brev should be credible for work accounts without becoming an admin console and
without weakening the privacy posture recorded in ADR-0006. The existing
`BackendCapabilities` surface already gates shared mailbox access, server rules,
aliases, signatures, forwarding, and provider APIs. The related feature request needs the missing
enterprise pieces to be explicit: which controls are in scope, which are
non-goals, how admin policy restrictions appear in UI, and what privacy
documentation future provider policy calls require.

## Decision

Brev accepts these enterprise controls as mail-client scope when a provider
backend exposes them behind capabilities:

| Control | Scope |
| --- | --- |
| Shared/delegated mailbox access | In scope. Users can browse and act on mailboxes they are allowed to access. |
| Shared/delegated mailbox management | In scope as provider-backed future work where the current user has permission. |
| Send As / Send on Behalf | In scope as capability-gated compose identity behavior. |
| Server rules, forwarding, automatic replies, aliases, signatures | In scope where provider APIs or standards extensions support them. Generic IMAP/SMTP keeps local fallback behavior. |
| Retention policy metadata | In scope as read-only visibility first. Provider retention editing requires a later explicit provider design. |
| Local cache retention interaction | In scope. Provider retention policy never silently changes Brev's local cache retention; Brev explains the distinction. |
| Sensitivity labels / information protection metadata | In scope as provider-backed metadata and compose/read presentation, gated by tenant policy. |
| Admin-disabled controls | In scope as presentation state. They must appear as policy-disabled/read-only, not as generic errors. |

These are non-goals:

- Tenant administration, user provisioning, license management, audit log
  browsing, eDiscovery, legal hold management, DLP rule authoring, or compliance
  center workflows.
- Hosted Brev services that proxy enterprise mailbox data or keep generic IMAP
  sessions open on the user's behalf.
- Provider-specific UI branches that check for a concrete Exchange backend type.

The capability model now has a richer availability context:

- `BackendCapabilities` remains the transport/mail feature gate used by existing
  code.
- `BackendExtendedCapabilities` records enterprise/provider operations such as
  shared mailbox management, Send As, Send on Behalf, retention policy
  visibility/management, and sensitivity labels.
- `BackendPolicyRestrictions` records tenant/admin restrictions separately from
  capabilities.
- `BackendFeatureAvailabilityContext` combines those inputs so UI can present
  supported, read-only, local-only, unavailable, or policy-disabled states
  without concrete backend checks.

## Rationale

Enterprise mail features are not all the same. A backend may support an operation
while the tenant disables it for the signed-in user, or it may expose policy
metadata read-only without allowing edits. Capability and policy state need to be
modeled separately so Brev can be honest without treating expected admin policy
as a failure.

Keeping tenant administration out of scope preserves the mail-client boundary.
Brev should help the user understand and act within the policies attached to
their mailbox, not administer the organization.

## Consequences

- UI surfaces can show "Policy" or "Read only" states for enterprise controls.
- Future provider-native backends can expose Send As, Send on Behalf, retention,
  and sensitivity-label support without view-layer backend type checks.
- Generic IMAP/SMTP accounts continue to fall back to local-only behavior where
  no provider policy API exists.
- Future provider policy metadata fetches must update ADR-0006 and `PRIVACY.md`
  with hosts, OAuth scopes, data sent, data cached, and user controls before
  shipping.
- Full retention editing, sensitivity-label mutation, and shared mailbox
  permission management still require provider-specific implementation and tests.

## References

- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0028: Standards-first IMAP/SMTP roadmap
- ADR-0040: Native Exchange and Microsoft 365 scope
- The related feature request: Enterprise/admin controls
