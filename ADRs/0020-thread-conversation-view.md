# ADR-0020 — Thread Conversation View

**Status:** Accepted  
**Date:** 2026-05-30  
**Deciders:** Brev contributors

## Context

The Brev reading pane (`MessageDetailView`) shows exactly one message body. When a
thread contains multiple messages, only the newest is visible. Users expect a
Gmail/Apple Mail-style conversation view: all messages in a thread stacked in one pane,
each expandable to show its body.

The message list already groups rows by `threadID` and shows a count badge. This ADR
covers the reading surface only (and the complementary inline list expansion).

## Decision

1. **New view `ThreadConversationView`** for the reading pane when a thread has more
   than one member. `MessageDetailView` is not modified.

2. **Thread membership** is derived client-side by filtering
   `MailNavigationState.currentFolderHeaders` by `selectedHeader.threadID` and
   sorting ascending by date. No new `MailBackend` protocol methods are added.

3. **Capability gate**: both inline list expansion and `ThreadConversationView` are
   shown only when `backend.capabilities.contains(.serverSideThreading)`. When the
   capability is absent, existing single-message behaviour is completely unchanged.

4. **`ThreadMessageCard`** owns its own body-loading state (lazy, cached for view
   lifetime). Newest card is auto-expanded. Body loaded via `backend.body(for:sourceID:)`
   + `BodyRenderer.render(_:)` — the same pipeline as `MessageDetailView`.

5. **Inline list expansion** (`ThreadInlineChildRow`) uses `@State var
   expandedThreadIDs: Set<String>` in `MessageListView`. `MessageListVisibleHeaders`
   is not modified.

## Amendment (2026-08-12): unified inbox and collapse affordance

1. **Unified inbox grouping.** `UnifiedInboxListView` groups threads the same
   way `MessageListView` does. Because a unified list mixes accounts and
   `threadID` is only unique inside one source (ADR-0017), thread identity is
   `accountID:mailboxID:threadID` — see `UnifiedInboxThreadGrouping`. The
   capability gate is resolved per row's source, so a threaded account and an
   unthreaded one can sit in the same list.

2. **The chevron must collapse.** `MessageListRow` carries a
   `highPriorityGesture` for instant single-click selection inside a `List`,
   and that gesture wins over buttons nested in the row. The thread chevron was
   such a button, so `onToggleThread` never fired and `onActivate`'s
   `expandIfNeeded` meant a thread could only ever be expanded. The chevron is
   now a plain glyph whose frame is published to the row, and
   `MessageListRowTapRouting` decides toggle vs activate from the tap location.
   VoiceOver keeps an explicit expand/collapse action on the row.

3. **No dead affordance.** Point 3 above says single-message behaviour is
   unchanged without `.serverSideThreading`; `MessageListView.threadCount(for:)`
   now enforces that, so the count badge and chevron do not render where nothing
   can expand.

## Consequences

- Two new view files (`ThreadConversationView.swift`, `ThreadMessageCard.swift`) and one
  new utility (`ThreadMessageDerivation.swift`).
- One new list-row file (`ThreadInlineChildRow.swift`).
- `BrevMailRootView.readingPaneDetailPane` gains a small branching condition.
- Snapshot tests required for `ThreadConversationView` and `ThreadMessageCard`.
- Unit tests required for `ThreadMessageDerivation` and expansion state logic.
- `MessageDetailView` is untouched; rollback is safe.
