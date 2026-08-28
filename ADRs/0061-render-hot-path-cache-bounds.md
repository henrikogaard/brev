# ADR-0061: Bounded caches for render and backend hot paths

- **Status:** Proposed
- **Date:** 2026-08-24
- **Deciders:** Henrik

## Context

Brev evaluates date labels, snippet sanitization, theme colors, and sender
avatars repeatedly while mailbox rows render. These paths previously rebuilt
formatters and regular expressions or retained one entry per sender without a
process-lifetime bound. Avatar rows also persisted expired SQLite records until
the same sender was requested again. The work must preserve the privacy and
capability boundaries in ADR-0003, ADR-0006, and ADR-0028 while reducing
avoidable allocation and storage growth.

On macOS, every `NavigationSplitView` layout also asked each pane's AppKit
transparency probe to walk the enclosing split-view subtree immediately and
again after two fixed delays. Divider drags therefore accumulated recursive
post-layout work. Reader and AI Sidebar resize samples also wrote directly to
`AppStorage` or `SceneStorage` for every pointer event.

## Decision

Use bounded, process-local caches for deterministic render/backend helpers:

1. Reuse configured IMAP date formatters and search-date formatters.
2. Compile the fixed snippet-sanitization regular expressions once per
   process and reuse them for replacement passes.
3. Cache parsed `BrevColor` values with a bounded `NSCache`; the stored hex
   string remains the Codable/source-of-truth representation.
4. Bound `AvatarResolver`'s in-memory entries, evict expired entries eagerly,
   and evict the least-recently-used entry when the bound is reached.
5. Throttle deletion of expired SQLite avatar rows during cache reads/writes;
   this prevents stale senders from accumulating without adding a full-table
   delete to every row lookup.
6. Coalesce macOS split-view transparency repair to one immediate pass per
   run-loop turn and one replaceable pass after layout settles. Keep transient
   divider samples in view-owned memory, and persist pane widths only when the
   drag ends or the reader-width debounce settles. Coalescing is keyed by the
   enclosing `NSSplitView`, not by each pane probe, and delayed passes carry a
   generation token so superseded GCD work cannot apply.

No new external calls, telemetry, or user-visible storage controls are added.
`PreferenceSyncStore` continues to reconcile its allowlist on
`UserDefaults.didChangeNotification` because Foundation does not provide
changed-key information and the current store has no safe coalescing seam.

## Rationale

Configured formatter and regex reuse removes repeated construction from paths
that execute once per envelope or visible row. `NSCache` is appropriate for
theme colors because it is thread-safe and may discard entries under memory
pressure. Avatar eviction uses recency so active senders remain warm while a
large mailbox cannot grow the actor indefinitely. Throttled SQLite cleanup
balances retention with the cost of scanning the cache table.

Split-view transparency remains an AppKit compatibility repair, but resize
bursts should not queue unbounded work. Coalescing preserves the final repair
while removing redundant traversal. Persisted pane widths are restoration
state, not live animation state, so one settled write retains behavior without
putting preference writes on the drag path.

Unbounded dictionaries, per-call formatter construction, and per-call regex
compilation were rejected because their cost scales with mailbox size and
render invalidations. A new notification or persistence protocol for preference
sync was rejected because it would expand the API without a reliable changed-key
signal from `UserDefaults`.

## Consequences

### Accepted

- A rarely used avatar may be recomputed after LRU eviction or process memory
  pressure; the persistent cache remains available when its row is valid.
- Formatter and regex caches are implementation details and do not alter public
  domain models or view/backend boundaries.
- Expired avatar rows are removed opportunistically during normal cache use.
- Divider drags update visible layout continuously while restoration storage is
  updated once at drag end or after the reader width settles.
- If SwiftUI reinstalls an opaque split-view fill during a resize burst, the
  replaceable settled pass clears it after the final layout.

### Risks

- Foundation formatter thread-safety assumptions remain platform-dependent;
  only configured read-only instances are shared, and formatter creation is
  lock-protected.
- `NSCache` eviction is nondeterministic under memory pressure; callers must
  treat cache hits as an optimization, never as required state.

## References

- ADR-0002: Theme system architecture
- ADR-0003: Sender avatar resolution
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0028: Roadmap to v2 and architectural invariants
- ADR-0028: Standards-first IMAP/SMTP roadmap
- `packages/BrevBackend/Sources/BrevBackend/IMAPSessionClient.swift`
- `packages/BrevMail/Sources/BrevMail/MessageListPresentation.swift`
- `packages/BrevThemes/Sources/BrevThemes/BrevColor.swift`
- `packages/BrevAvatars/Sources/BrevAvatars/AvatarResolver.swift`
- `packages/BrevAvatars/Sources/BrevAvatars/AvatarCache.swift`
- `packages/BrevDesign/Sources/BrevDesign/Components/BrevWindowSurfaceBackground.swift`
- `packages/BrevMail/Sources/BrevMail/BrevMailRootView.swift`
- `packages/BrevMail/Sources/BrevMail/MailContextColumn.swift`
