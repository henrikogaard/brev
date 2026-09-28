# Offline Coverage Audit — 2026-09-28

**Scope:** what Brev can do with no network, on `main @ e06fab9`.
Evidence is code paths, not device runs; the device legs live in the
QA matrix.

## What works offline today

| Capability | Mechanism | Where |
|---|---|---|
| Read cached headers/threads | `SQLiteSyncStore` + header caches (`FileBackedIMAPMailboxHeaderCache`) | BrevSyncEngine, BrevBackend |
| Read cached bodies / attachments | `IMAPMessageBodyCache` + body retention + `MessageOfflineRetentionOverrideStore` | BrevBackend, BrevMail |
| Read/flag/move/copy/delete/junk/label edits | `OfflineMutationQueue` (`PendingMutation.Kind`) — durable, deduped, retried on reconnect | BrevBackend |
| Queue replies/forwards | `sendStagedDraft` pending mutation + draft staging store | BrevBackend |
| Offline search | `MailLocalSearchIndex` fallback (`MessageSearchFallback`) | BrevBackend/BrevMail |
| Offline detection shown to user | `NetworkReachabilityMonitor` → status UI + `handleNetworkStatusChange` replays the queue | BrevMail |
| Scheduled sends | `ScheduledOutbox` persists across quit | BrevMail |
| PIM (calendar/contacts/tasks) browsing | SQLite caches populated by sync services | BrevCalendar |

## Gaps

| Gap | Impact | Candidate fix |
|---|---|---|
| PIM writes offline | Event/contact/task edits appear to target live servers; no offline PIM write queue found | Extend the mutation queue or reject edits while offline with copy |
| Attachment download when body cached | Cache-miss attachment fetch fails mid-message | Already surfaces as a retryable error — acceptable; verify UX |

Note: pending mail mutations are already visible — `OutboxView`
(sidebar → Outbox) lists each queued operation with retry/discard, and
`ConflictReviewSheet` surfaces conflicted replays per account. Those
were previously listed as gaps; they are shipped surfaces, verified in
the UI/UX review.

## Recommendation

The queue + cache architecture is solid and the pending-work surfaces
(Outbox, conflict review) already ship. The remaining daily-driver gap
is **PIM writes while offline** — event/contact/task edits have no
offline queue, so they either fail or need explicit offline copy.
