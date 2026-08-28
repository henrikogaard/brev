# Mail status priority rail + narrow chrome polish

**Status:** Implemented  
**Date:** 2026-07-26  
**Branch context:** `cursor/59b8288c`  
**Related:** compose Apple Mail chrome (`2026-07-26-compose-apple-mail-chrome-design.md`), CancellationError / QP snippet fixes

## Problem

Mailbox chrome can stack multiple top `safeAreaInset`s (root status, import/sync
banner, offline) while compose success also lands as a full-width top status
(“Draft saved.”). That crowds the reading surface and fights the quieter
compose/list chrome from the Apple Mail pass.

## Goals

1. At most **one** top status rail on the mail root at a time.
2. Benign success feedback does not steal vertical space from mail.
3. Actionable failures remain visible and retryable.
4. Narrow compose chrome consistency only — no redesign beyond leftover density.

## Non-goals

- New design-system status component or ADR-level status architecture.
- Changing sync/import backend behavior beyond presentation selection.
- Full Settings / inspector chrome pass.
- iOS-only layout overhaul (shared policy applies where cheap).

## Design

### A. Priority rail (mail root)

Replace independent stacked top insets with a single resolver that picks one
presentation:

| Priority (high → low) | Source | Surface |
|---|---|---|
| 1 | Sign-in required | Top rail (warning), reconnect copy |
| 2 | Offline | Top rail (warning), Retry |
| 3 | Actionable sync/import failure | Top rail (warning), Retry when offered |
| 4 | Determinate import / index progress | Top rail (info), compact |
| — | Cancellation / non-actionable noise | Hidden (existing filter) |
| — | Benign success (draft saved, etc.) | Bottom toast, auto-dismiss |

Implementation sketch:

- Add `MailRootChromeStatusPolicy` (or extend `ImportProgressPresentation`) that
  returns a single optional top presentation given:
  `rootStatus`, `importSyncHealth`, `syncProgress`, `isOnline`.
- `BrevMailRootView` mounts **one** top `safeAreaInset`.
- Keep `ImportProgressBanner` / `BrevInlineStatus` as renderers; policy chooses
  which model to show, not three concurrent insets.

Conflict rule: if `rootStatus` is danger/warning with retry (load/refresh/
mutation failure), it outranks import progress. Success-tone `rootStatus` is
**not** shown on the top rail (see B).

### B. Success → toast

- `ComposeCompletionPresentation` success cases (at least `.savedDraft`, clean
  scheduled-send confirmation) route to a short-lived bottom toast instead of
  `MailRootStatus` top banner.
- Reuse `BrevToast` (already used for undo). Prefer a small transient toast
  queue or a single `ephemeralToast` state so undo + success don’t fight —
  undo keeps priority if both would show.
- Auto-dismiss ~2–3s; dismissible; no Retry.
- Warning completions (sent-but-Sent-copy-failed, queued Outbox, etc.) stay on
  the top rail as actionable/important.

### C. Import banner density

When the priority rail selects import/sync progress or recoverable failure:

- Match `BrevInlineStatus` vertical density (tighter padding, single-line title
  when possible).
- Prefer title + optional one-line message; drop tall multi-block layouts for
  failure when Retry is present.
- Determinate progress remains, but compact (no large empty chrome).

### D. Narrow compose chrome polish

Keep Approach B Apple Mail sheet. Only:

- Ensure compose completion/error rows don’t reintroduce a heavy well above the
  body.
- Align field/toolbar spacing with the flat hairline sheet (no regression to
  pill clusters or filled wells).
- No send/draft/AI behavior changes.

## Success criteria

- [x] Mail root never shows more than one top status inset in normal use.
- [x] “Draft saved.” appears as bottom toast, not a persistent top banner.
- [x] Offline / sync failure / sign-in still reachable with Retry where today.
- [x] Import progress still visible when it’s the highest-priority item.
- [x] Compose remains one continuous sheet (no field/body wells).
- [x] Focused presentation tests cover priority ordering + success toast routing.
- [x] `CHANGELOG.md` notes the quieter status chrome under Unreleased.

## Risks

- Toast + undo toast contention — mitigate with undo-wins rule.
- Users who relied on sticky “Draft saved.” may miss ephemeral toast — acceptable
  for polish; keep warnings sticky.
- Snapshot tests for import banner density may need re-record.

## Out of scope follow-ups

- Unified global status bus / notification center.
- Per-account sync badge in sidebar instead of top rail.
