# Nested / Threaded Message Display — Design Spec
**Date:** 2026-05-30  
**Status:** Approved  
**Author:** Agent (brainstorming session)

---

## Context

Today Brev groups messages by `threadID` in the message list — a collapsed row shows a count badge (`threadCount`) — but there is no conversation view. `MessageDetailView` takes a single `header: MessageHeader?` and loads exactly one body via `backend.body(for: header.id)`. Opening a 3-message thread shows only the newest message body.

---

## Goals

1. **Inline expansion** in the message list: thread rows expand in place to show indented child rows for each message in the thread (oldest → newest). Tapping a child selects and opens that message.
2. **Conversation reading pane**: when a multi-message thread is selected, render all messages stacked in the reading pane (Gmail / Apple Mail style), each as an expandable card with lazy body loading. Newest card expanded by default.

---

## Constraints (from AGENTS.md + ADRs)

- No literal colors in views — use `@Environment(\.brevTheme)`.
- Views consume plain `MessageHeader` / `MessageBody` models only — no Realm, no the provider types.
- Capability-driven UI — both features gated on `backend.capabilities.contains(.serverSideThreading)`.
- When capability is absent, existing behavior is completely unchanged.
- No new external network calls. Thread membership derived client-side from in-memory headers.
- New reading surface requires ADR (ADR-0010).
- New views require snapshot tests; new logic requires Swift Testing unit tests.

---

## Data Layer & Fixture Fix

### MockBackend threadID fix

`m1` ("Friday standup notes", Alex Berg) currently has `threadID: "t1"`, isolating it from the three reply messages `m17`/`m18`/`m19` which use `threadID: "thread-standup"`. Fix: set `m1.threadID = "thread-standup"`. This makes the standup thread 4 messages long and is the intended state.

Side effect: the `"preview inbox includes enough example mail for grouped demos"` test in `MockBackendTests.swift` may need its expected per-thread count updated. Verify and fix as part of the fixture change.

### Thread message derivation

No new backend API required. Thread members are derived by:

```swift
navigation.currentFolderHeaders
    .filter { $0.threadID == selectedHeader.threadID }
    .sorted { $0.date < $1.date }   // oldest → newest
```

This is pure, cheap, and already in memory. `MailNavigationState.currentFolderHeaders` is owned by `MessageListView` and already contains all loaded headers for the selected folder.

### Capability gate

```swift
backend.capabilities.contains(.serverSideThreading)
```

When absent: list shows collapsed rows, reading pane shows existing `MessageDetailView` unchanged.

---

## Feature 1: Inline List Expansion

### New types

**`ThreadInlineChildRow`** (`ThreadInlineChildRow.swift`)  
A lightweight `View` for indented child entries. Shows: sender avatar (via `BrevAvatars`), sender name, date, read indicator dot, one-line snippet. Tapping sets `navigation.selectedMessageID` to that child's ID.

### Changes to `MessageListView`

- Add `@State private var expandedThreadIDs: Set<String> = []`.
- For rows where `threadCount(for: header) > 1` AND `.serverSideThreading` capable:
  - Show a disclosure chevron on the trailing side of the row (rotates 90° when expanded, animated).
  - Chevron tap (not row tap) toggles `expandedThreadIDs` membership for `header.threadID`.
  - Row tap selects the message as today (unchanged).
- When `header.threadID` is in `expandedThreadIDs`, insert child rows immediately below the parent, derived by filtering `headers` (the existing `@State` array) and sorting ascending by date. Children are rendered inside the same date section as the parent.

### What does NOT change

- `MessageListVisibleHeaders` — remains a pure grouping utility, no expansion awareness.
- Swipe actions and context menu — on parent row only.
- Pinning — unaffected.
- Expansion state resets on folder change (same behavior as selection today). No UserDefaults persistence in v1.

---

## Feature 2: ThreadConversationView

### New files

| File | Purpose |
|------|---------|
| `ThreadConversationView.swift` | Conversation stack; owns expansion state |
| `ThreadMessageCard.swift` | One expandable card per message |

### `ThreadConversationView`

**Inputs:** `threadHeaders: [MessageHeader]` (sorted oldest → newest), `backend: any MailBackend`, `sourceID: MailSourceID?`, `navigation: MailNavigationState`, `isWorkBlocked: Bool`.

**Owns:** `@State var expandedID: MessageHeader.ID?` initialised to `threadHeaders.last?.id` (newest auto-expanded).

**Body:** `ScrollView` > `LazyVStack(spacing: 0)` of `ThreadMessageCard`s. On appear, scrolls to the expanded card.

### `ThreadMessageCard`

**Collapsed state:** sender avatar + name, date, subject (first card only or if different from thread subject), 1-line body snippet.

**Expanded state:** full sender/recipient header (From / To / CC), body loaded lazily via `backend.body(for: id, sourceID: sourceID)` + `BodyRenderer.render(_:)`, attachments list, calendar RSVP if invite present (gated on `.serverSideCalendarReply` as today).

**Per-card state:** `@State var messageBody: MessageBody?`, `@State var isLoading = false`, `@State var errorMessage: String?`. Body fetched once on first expansion and cached for the view lifetime (no re-fetch on collapse/re-expand).

### Wiring in `BrevMailRootView`

Replace `readingPaneDetailPane` with:

```swift
private var readingPaneDetailPane: some View {
    let threadHeaders = threadHeadersForSelection()
    if backend.capabilities.contains(.serverSideThreading),
       threadHeaders.count > 1 {
        ThreadConversationView(
            threadHeaders: threadHeaders,
            backend: selectedBackend,
            sourceID: navigation.selectedSourceID,
            navigation: navigation,
            isWorkBlocked: isMessageWorkBlocked
        )
        .frame(minWidth: 400)
        .brevMailPaneSurface(.content)
        .brevMailFallbackToolbar { toolbarDetail }
    } else {
        MessageDetailView(
            backend: selectedBackend,
            sourceID: navigation.selectedSourceID,
            header: navigation.selectedHeader,
            navigation: navigation,
            isWorkBlocked: isMessageWorkBlocked
        )
        .frame(minWidth: 400)
        .brevMailPaneSurface(.content)
        .brevMailFallbackToolbar { toolbarDetail }
    }
}

private func threadHeadersForSelection() -> [MessageHeader] {
    guard let threadID = navigation.selectedHeader?.threadID else { return [] }
    return navigation.currentFolderHeaders
        .filter { $0.threadID == threadID }
        .sorted { $0.date < $1.date }
}
```

`MessageDetailView` is **not modified**.

---

## ADR-0010

A short ADR to be written before implementation. Key points:

- **Context:** Single-message reading pane insufficient for threaded mail.
- **Decision:** New `ThreadConversationView` for multi-message threads. Capability-gated. Client-side thread derivation from in-memory headers. `MessageDetailView` untouched.
- **Consequences:** New snapshot tests required; no new backend protocol methods; `BrevMailRootView` gains a small branching condition.
- **Status:** Accepted.

---

## Tests

### Unit tests (Swift Testing)

| Suite | What it covers |
|-------|---------------|
| `ThreadMessageDerivationTests` | Filtering by threadID, sort order (oldest→newest), empty input, single-message thread returns one element |
| `ThreadConversationExpansionTests` | Default-expanded is newest header, toggling expandedID, nil when no headers |
| `MessageListInlineExpansionTests` | expandedThreadIDs toggle, children derived correctly, children sorted ascending, capability-absent hides disclosure control |

### Snapshot tests (iOS UIKit, existing pattern)

| Snapshot | Parameterised over |
|----------|--------------------|
| `ThreadConversationView` — all cards collapsed | `BrevTheme.brevBuiltIns` |
| `ThreadConversationView` — newest card expanded | `BrevTheme.brevBuiltIns` |
| `ThreadMessageCard` — collapsed | one representative theme |
| `ThreadMessageCard` — expanded | one representative theme |

### Existing tests to verify unchanged

- `MessageListVisibleHeadersTests` — must pass unmodified.
- `MessageDetailPresentationTests` — must pass unmodified.
- `MockBackendTests` — adjust expected count for standup thread after threadID fix; all other assertions must pass.

---

## Verification

```bash
cd packages/BrevBackend && swift build && swift test
cd packages/BrevMail && swift test
tuist build BrevMacOS
```

All must pass. Lint and format clean (`scripts/lint.sh`, `scripts/format.sh`).

---

## Files changed / created

| Path | Change |
|------|--------|
| `ADRs/ADR-0010.md` | New — thread conversation view ADR |
| `packages/BrevBackend/Sources/BrevBackend/MockBackend.swift` | Fix `m1.threadID` |
| `packages/BrevBackend/Tests/BrevBackendTests/MockBackendTests.swift` | Adjust standup thread count assertion |
| `packages/BrevMail/Sources/BrevMail/ThreadConversationView.swift` | New |
| `packages/BrevMail/Sources/BrevMail/ThreadMessageCard.swift` | New |
| `packages/BrevMail/Sources/BrevMail/ThreadInlineChildRow.swift` | New |
| `packages/BrevMail/Sources/BrevMail/MessageListView.swift` | Add `expandedThreadIDs`, disclosure chevron, child row rendering |
| `packages/BrevMail/Sources/BrevMail/BrevMailRootView.swift` | Replace `readingPaneDetailPane` with thread-aware branch |
| `packages/BrevMail/Tests/BrevMailTests/ThreadMessageDerivationTests.swift` | New |
| `packages/BrevMail/Tests/BrevMailTests/ThreadConversationExpansionTests.swift` | New |
| `packages/BrevMail/Tests/BrevMailTests/MessageListInlineExpansionTests.swift` | New |
| `packages/BrevMail/Tests/BrevMailTests/BrevMailSnapshotTests.swift` | Add ThreadConversationView + ThreadMessageCard snapshots |
| `CHANGELOG.md` | Add entry under Unreleased |
| `WORKLOG.md` | Add agent session entry |
