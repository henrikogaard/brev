# ADR-0043: Provider-backed workflow state

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik
- **Amends:** ADR-0042

## Context

Brev has strong local workflow features: local inbox categories, snooze, Done,
follow-up reminders, rules, signatures, aliases, profiles, and folder aliases.
Users coming from Outlook or eM Client often expect some of this state to follow
them across devices when the provider supports it.

The related feature request asks Brev to audit that local-only state and define how provider
backed variants can be added without losing the generic IMAP/SMTP fallback or
turning the UI into backend-specific branches.

## Decision

Brev treats workflow state as a per-surface sync decision. Settings and UI can
present each surface as:

- **Local**: state is stored by Brev only, scoped to account/source where
  applicable, and removed when that account/source is removed.
- **Provider**: state is backed by a provider capability or extension service
  and can sync across devices through the provider.
- **Unsupported**: no local or provider-safe behavior exists for that surface on
  this account.

The initial workflow matrix is:

| Surface | Generic IMAP/SMTP fallback | Provider-backed path |
| --- | --- | --- |
| Categories / labels | Local categories and overrides | Provider labels/categories when `.labels` exists |
| Snooze | Local snooze smart view | Provider snooze when `.snooze` exists |
| Follow-up reminders | Local reminders | Future provider task/reminder service, not assumed today |
| Signatures | Local signatures | Server signatures when `.serverSignatures` exists |
| Aliases | Local sender identity behavior | Server aliases when `.aliases` exists |
| Shared mailbox workflow state | Unsupported without shared mailbox capability | Provider shared mailbox management when `.sharedMailboxes` and `.sharedMailboxManagement` exist |

Provider-backed workflow state must use capability gates and extension services.
Views must not check for concrete backend types. Generic IMAP/SMTP accounts keep
local fallback behavior even when provider-backed modes are unavailable.

Conflict policy is explicit:

- When provider-backed state is available, provider state is authoritative after
  sync. Brev may keep local review metadata to explain or resolve conflicts, but
  it must not silently overwrite provider state from stale local state.
- Local-only state remains authoritative for generic accounts and is removed when
  the relevant account/source is removed.
- Unsupported surfaces do not create placeholder local state that looks synced.

## Rationale

Different workflow surfaces have different provider semantics. Labels can often
round-trip; reminders may need a task service; signatures and aliases may be
read-only or provider-managed; shared mailbox state has permission and delegation
rules. A single "sync everything" toggle would hide those differences and create
privacy surprises.

The matrix lets UI explain what will sync before the user relies on it, while
keeping Brev useful for standards-only accounts.

## Consequences

- `WorkflowStateSyncPresentation` resolves Local, Provider, and Unsupported rows
  from `BackendFeatureAvailabilityContext`.
- Organization sync settings now expose account cleanup so account removal clears
  account-scoped local sync choices.
- Future provider round trips need extension-service APIs, mockable tests, and
  privacy documentation for concrete hosts/scopes before shipping.
- Existing local workflow state remains the fallback for generic IMAP/SMTP.

## References

- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0028: Standards-first IMAP/SMTP roadmap
- ADR-0042: Enterprise and admin policy scope
- The related feature request: Provider-backed workflow state
