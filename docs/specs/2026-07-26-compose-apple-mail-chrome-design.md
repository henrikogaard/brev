# Compose window Apple Mail chrome redesign

**Status:** Approved (2026-07-26)  
**Branch context:** `cursor/59b8288c`  
**Related:** reply quote CTE decode fix (build 10)

## Problem

The macOS compose window reads as three stacked pieces — crowded icon
toolbar with pill clusters, a filled field “well”, and a darker editor
slab — instead of one calm sheet. Formatting controls compete with
Send/Save for attention.

## Goals

1. One continuous compose surface (chrome + fields + body).
2. Primary toolbar limited to high-frequency actions; formatting mostly
   behind a Format menu (keyboard shortcuts unchanged).
3. Flat To / Subject / From rows with hairline dividers (Apple Mail–like).
4. No behavior changes to send, draft, AI, security, or quote loading.

## Non-goals

- New compose window architecture or ADR-level window model changes.
- iOS-only redesign beyond shared chrome tokens when cheap.
- Changing reply/forward quote semantics (already fixed to use decoded body).

## Design

### Toolbar (primary row)

Visible controls, leading → trailing:

| Control | Notes |
|---|---|
| Attach | Unchanged |
| Format | Menu: Bold, Italic, Underline, Link, Lists, Image, Clear, Undo, Redo |
| Templates / Signature entry | Keep existing affordances; avoid duplicate Signature if From-row picker remains |
| AI | Unchanged capability gate |
| Save Draft | Unchanged |
| Schedule | Unchanged |
| Editor appearance | Quieter control |
| Send | Trailing primary |

Remove rounded `toolbarGroup` pill backgrounds. Use borderless icon
buttons on the shared utility window surface.

### Header fields

- Rows: To (+ Cc/Bcc reveal), Subject, From (+ Signature).
- Treatment: no solid `bgSecondary` well / border card.
- Hairline `BrevDivider` between rows.
- Fixed label column; vertically center Cc/Bcc and Signature accessories.

### Body

- No separate rounded fill behind the editor.
- Share the utility window surface with fields.
- Keep horizontal padding generous (`BrevSpacing.xl` / existing comfort).
- Editor light/dark toggle remains.

### Platforms

- macOS is the primary visual target.
- iOS keeps compact toolbar policy; only adopt shared field/body surface
  changes that do not fight compact chrome.

## Success criteria

- [x] Compose screenshot reads as one sheet, not toolbar + card + black editor.
- [x] Format actions reachable via Format menu; ⌘B / ⌘I / etc. still work.
- [x] Reply quotes remain human-readable after body load.
- [x] Focused compose presentation tests / snapshots updated if chrome
      assertions exist.
- [x] `CHANGELOG.md` notes the chrome redesign under Unreleased.

## Risks

- Snapshot baselines for compose may need re-record.
- Users who relied on always-visible formatting icons need one extra click;
  mitigate via Format menu + shortcuts.
