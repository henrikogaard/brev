# iOS slice 7: Settings panes as forms (2026-10-09)

Evidence for `fix(ios): Settings panes as Forms, flatter navigation and iOS-only copy`
(audit findings T1 to T9 in `docs/qa/ios-ux-audit-2026-10-09`).

Run: iPhone 17 Pro simulator, iOS 27.0, Debug build in mock mode, driven by a
temporary XCUITest that was not committed. Each pane screenshot has a matching
`performAccessibilityAudit()` result.

## Screenshots

| Set | Files | Content |
| --- | --- | --- |
| `en-light-*` | 25 | Settings over mail, Accounts, account page (switches, default mailbox checkmark), Notifications, Appearance, Smart Views (list, edit mode, editor), Folder Sync, Mail Storage, Privacy, Auto-Reply, Rules, Import / Export and more |
| `en-dark-*`, `nb-light-*`, `nb-dark-*` | 5 each | Root, Accounts, account page, Notifications, Appearance |
| `en-ax3-*` | 5 | Same panes at Accessibility 3 text |

## Accessibility audit

Issues other than "Dynamic Type font sizes are partially unsupported"
(reported on footers and rows near the bottom edge of every long list, with
no visible cause) and "Contrast nearly passed":

| Pane | Remaining |
| --- | --- |
| Settings root | one "Contrast failed" on an unlabeled node, only at the initial scroll position (it does not reproduce after scrolling; the bottom search field's glass overlaps a section header there). The original audit also reported one contrast item at AX5. Hit areas pass. |
| Accounts | "Text clipped" on the Add account row, not visible in the screenshots at default or AX3 size |
| Account page, Notifications, Appearance | none (hit areas pass) |
| Calendar & Contacts, Signature | "Text clipped" on the Add DAV Source / Add Signature rows, same pattern |
| Folder Sync | "Text clipped" on Refresh and the filter field |
| Import / Export | contrast on the disabled Export as MBOX / EML rows; clipped Select folder row |
| About | hit area on the repository link |
| Auto-Reply, Mail Storage | unlabeled element and "Label not human-readable" on the raw account address |

The before-state of this audit (T1 to T9) had 5 contrast failures on
Notifications, an unlabeled switch per mailbox and 8 items on Appearance;
Notifications and Appearance now report none besides the Dynamic Type note.

## Row heights

Rows use the system list metrics (no extra padding or minimum-height frames):
52 pt for single-line rows on iOS 27, 40 pt section headers, and taller only
for two-line or multi-line content. Measured from the accessibility tree:
`02-settings-root` 52, `04-notifications` 52, `03b-account-detail` 52 (68 for
two-line rows). Before this follow-up the root rows were 74 pt.
