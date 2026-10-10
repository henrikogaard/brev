# iOS sheet appearance and native utility sheets — runtime evidence, 2026-10-10

Slice 6 of the iOS UI/UX pass: audit findings H1, H2, H3, R12 and O4.

| Item | Value |
| --- | --- |
| Build | iOS Debug, `BREV_USE_MOCK=1` mock backend, no real accounts |
| Device | Own simulator (iPhone 17 Pro, iOS 27.0), created for this run and deleted afterwards |
| Driver | A temporary XCUITest bundle outside the repository; it is not committed |
| Variants | English light, English dark (system dark, follow-system), English with "Always dark" pinned on a light system, Norwegian light |

## What each shot proves

| Shot | Proves |
| --- | --- |
| `en-light-10-move-to`, `nb-light-10-move-to` | Move To is a native sheet: Cancel in the navigation bar, centred inline title, system search field, inset-grouped folder list (H2); localized in Norwegian |
| `en-dark-10-move-to`, `en-dark-15-task`, `en-dark-17-followup` | Sheets follow system dark: dark sheet background, theme row surfaces, accent tint (H1) |
| `en-light-pinneddk-10-move-to`, `en-light-pinneddk-15-task` | With the appearance setting "Always dark" on a light system the sheets are dark and match the app (H1, the case the old per-sheet pin got wrong) |
| `en-light-12-properties` | Properties: grouped list, Done in the navigation bar |
| `en-light-15-task`, `en-light-16-meeting` | Create Task / Create Meeting are forms with Cancel and Create in the navigation bar |
| `en-light-17-followup`, `nb-light-17-followup`, `en-dark-17-followup` | Follow Up: presets confirm on tap, custom date and a Set row, Cancel in the navigation bar |
| `en-light-18-ask-ai` | The AI sheet has a navigation bar titled "Ask AI" with Done, and the sender chip reads "Ledger & Co" rather than the address's local part (R12) |

Also checked in the same runs: every sheet closes from its navigation-bar
button and returns to the list.

## Not covered at runtime

- Note: the mock list has no selected source, so the root presents the Note
  sheet's `EmptyView` fallback (a blank sheet; unchanged by this slice).
  Covered by snapshots (`NativeUtilitySheetsSnapshotTests`, light, follow-system
  dark, always-dark).
- View Source and Show Headers: the iOS reader menu is long and the driver did
  not reach the items; covered by a loading-state snapshot only.
- Choose Mailboxes (O4) and Outbox: the mock has no new-account flow and no
  pending changes, so neither presents. O4 is covered by compile and review only.
- AX3: the list context menu cannot be scrolled reliably at AX3 by the driver,
  so no sheet was opened at an accessibility size. Follow Up's accessibility
  layout (wake time under the title) mirrors the snooze sheet and is not
  snapshot-tested because its times depend on the current clock.
- `performAccessibilityAudit` on Move To and Properties reports the system
  glass Cancel/Done buttons for contrast and "Dynamic Type partially
  unsupported" (H3). Those buttons carry no custom foreground style; the label is
  dark text on the sheet's glass and the audit does not name a failing colour
  pair. Not resolved here and not re-checked on the other sheets because the
  audit run did not finish in the time available on the loaded machine.
- VoiceOver speech for the "Make <mailbox> the default" labels was not heard.
