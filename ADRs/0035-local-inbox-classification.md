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
- Issue #295 (Inbox split into People and Updates, with a Subscriptions view)

## Amendment (2026-11-22): Two-way People/Updates split, sender overrides, and Updates bundling

Issue #295 extends local inbox classification with a calm two-way split
(`People`, `Updates`, `All`) alongside the existing five-category mode and off
mode, plus sender bundling in `Updates` and a `Subscriptions` view.

1. **Two-way People/Updates mode.** `InboxClassificationMode` adds
   `.peopleAndUpdates` alongside `.off` and `.categories` in `BrevDesign`, and
   adds `InboxSplitTab` (`.people`, `.updates`, `.all`). Opening an Inbox in
   People & Updates mode defaults to **People** with pill tabs showing live
   counts (`People N · Updates M · All`). Existing `.off` and `.categories`
   preferences continue to decode and behave unchanged.
2. **Deterministic local signals.** `PeopleUpdatesClassifier` stays 100% local
   with no AI or external network calls. Signals are evaluated in priority
   order:
   - Explicit sender override (always wins).
   - `List-Unsubscribe` header or `Precedence: bulk`/`list`/`junk` -> `Updates`.
   - Automated sender address patterns (`no-reply`, `noreply`,
     `notifications@`, `newsletter@`, `updates@`, `receipts@`, `billing@`,
     `mailer-daemon`) -> `Updates`.
   - Known replied-to sender (the user has sent mail to that address in locally
     cached Sent headers) -> `People`.
   - Known transactional/receipt/newsletter/notification subject or snippet
     patterns -> `Updates`.
   - Direct sender fallback -> `People`.
3. **Sender-level overrides.** `InboxSenderCategoryOverrideStore` persists
   per-sender (`from.email.lowercased()`) People/Updates assignments locally so
   moving any sender to People or Updates remembers across all messages from
   that sender.
4. **Sender bundling in Updates.** Multiple Updates messages from the same
   normalized sender collapse into one bundle row showing sender name, message
   count, unread count, and remaining count (`"Linear 2 · 2 new · 1 more from
   Linear"`) with a disclosure chevron to expand individual rows. Archiving a
   bundle archives all of its messages through the existing undoable move queue
   so a single `⌘Z` restores the entire bundle.
5. **Subscriptions view.** A built-in **Subscriptions** sidebar destination
   groups locally cached `List-Unsubscribe` senders into one row per sender
   with message count, last received date, **Unsubscribe** (always showing an
   explicit confirmation describing the exact HTTPS/RFC 8058 or `mailto:`
   action before doing anything; never automatic), and **Archive all**
   (reversible via `UndoQueue`). Privacy disclosure is updated in `PRIVACY.md`
   and ADR-0006.
