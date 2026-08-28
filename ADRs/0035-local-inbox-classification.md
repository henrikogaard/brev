# ADR-0035: Local inbox classification and category tabs

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Henrik

## Context

Outlook, Apple Mail, and eM Client all make high-volume inboxes easier
to scan with Focused Inbox, categories, or inbox tabs. Brev had quick
filters and local workflow state, but no first-class inbox
classification surface. The related feature request asks for category tabs, manual
recategorization, explainable local rules, Unified Inbox behavior that
preserves source identity, settings to disable the feature, and tests.

This touches ADR-0028 invariants: the view layer must stay
backend-agnostic, provider semantics must be capability-driven, and AI
must never run automatically. It also touches ADR-0006 because an inbox
classifier could easily become a hidden network or telemetry feature if
designed carelessly.

## Decision

1. **Classification is local and opt-in for v1.** The default mode is
   `off`. Users can enable `categories` in Mailbox View settings. No
   provider calls, remote AI calls, telemetry, or remote categorization
   are performed.

2. **Categories are provider-neutral UI concepts.** Brev uses `All`,
   `Primary`, `Transactions`, `Updates`, `Promotions`, and `Other`.
   These names intentionally do not claim parity with Microsoft,
   Gmail, Apple, or IMAP keywords.

3. **The first classifier is deterministic and explainable.** It uses
   local header/snippet/sender keywords and returns a reason such as a
   matched keyword, direct-message fallback, or manual override. It does
   not inspect message bodies, attachments, remote content, or contacts.

4. **Manual overrides are local and source-scoped.** Overrides are stored
   by `SourceMessageID` (`accountID`, `mailboxID`, `messageID`) so Unified
   Inbox can handle identical message ids from different accounts without
   collisions.

5. **Provider-backed categories are future capability work.** If Brev
   later syncs categories, Focused Inbox state, or server labels, that
   must be exposed through backend capabilities and provider-neutral
   domain models rather than concrete backend checks in views.

## Consequences

- Category tabs appear only when the feature is enabled and only for
  inbox-like surfaces: normal Inbox folders and Unified Inbox.
- Manual recategorization is available from message row context menus.
- Classification settings and overrides are local user preferences and
  may not sync across devices until the related feature request or a later provider-backed
  workflow-state design is implemented.
- The heuristic classifier is intentionally conservative and may require
  user overrides for ambiguous senders.

## References

- ADR-0006 (telemetry and privacy)
- ADR-0028 (roadmap and invariants)
- The related feature request (inbox classification and category tabs)
- The related feature request (provider-backed workflow state)
