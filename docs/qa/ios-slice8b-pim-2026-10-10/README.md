# iOS slice 8b QA evidence: native Calendar, Contacts, Tasks (2026-10-10)

Runtime evidence for audit findings P1-P4 (`docs/qa/ios-ux-audit-2026-10-09/README.md`, section 2.9) on branch `fix/ios-pim-native` (PR #234, draft), head `93bcc4f9` at capture time.

| Item | Value |
| --- | --- |
| Toolchain | Xcode 27, iOS 27.0 simulator runtime |
| Device | Own simulator `brev-8b-qa` (iPhone 17 Pro, 402x874 pt), deleted after the run |
| Data | `BREV_USE_MOCK=1` only, no real accounts; stub CalDAV/CardDAV server `scripts/stub-dav-server.py` was started but could not be connected (see Known limits) |
| Driver | Temporary XCUITest project kept outside the repo (scratchpad), attached to `eu.brevmail.brev.ios`; one `performAccessibilityAudit(for: .all)` per screen for en-light and en-AX3 |
| Variants | English light, English dark, Norwegian (`-AppleLanguages (nb)`) light, English AX3 (`simctl ui content_size accessibility-large`) |

## Audit findings in scope

| ID | Finding (before) | Slice change under test |
| --- | --- | --- |
| P1 | Empty state names a Settings path but has no button; search field shown with nothing to search | `ContentUnavailableView`-style state with an "Open Calendar & Contacts Settings" button that opens the pane; search hidden until there is data |
| P2 | Calendar controls in one in-content HStack, sub-44 pt chevrons, Done leading | Today, +, view picker, range title in the nav/bottom bars; Done trailing |
| P3 | Month cell label is the date only, tap gesture, fixed sizes | One button per cell with a spoken event list, event dots, scaled metrics |
| P4 | Task editor is a macOS dialog; completion merged into row; no delete confirmation | Form sheet with Cancel/Save, separate completion switch, 44 pt checkbox, "Overdue" word, delete confirmation |

## Screenshots (`screens/`, JPEG q70 of the simulator frame)

Each variant has `<variant>-calendar-empty`, `-contacts-empty`, `-tasks-empty` and `-settings-from-empty` (the Calendar & Contacts Settings page opened by the empty-state button; P1).

| Variant | Files |
| --- | --- |
| English light | `en-light-*.jpg` |
| English dark | `en-dark-*.jpg` |
| Norwegian light | `nb-light-*.jpg` |
| English AX3 | `en-ax3-*.jpg` (Calendar, Contacts, Tasks empty states, Settings page) |

What they show: all three covers have Done trailing in the primary text colour, an icon, a title, the actual iPhone path ("Settings → Calendar & Contacts", which is where compact Settings lists the pane) and a button; no search field. The Settings page shows "No sources connected yet", Add DAV Source and the Google row. nb strings are translated; the long nb button label fits in one line. At AX3 the icon, title, message and button scale and wrap with no truncation.

## Not captured at runtime: screens that need a connected source

Month grid with dots, week view, nav/bottom-bar controls (P2/P3), task rows and editor, delete confirmation (P4) and the Contacts list/editor are behind a connected PIM source. Tapping "Add DAV Source…" in Settings dismisses the entire Settings sheet in mock mode (reproduced here from both the empty-state route and Mailboxes → Settings → Calendar & Contacts; the process does not crash, there is no crash report; the Settings and connect sheet are both gone within 0.4 s). The brief records the same behaviour on `main`; it is not changed by this slice and was not fixed here. A temporary in-app auto-connect hook was considered and not used. `snapshot-reference/` therefore points at the committed snapshot test renderings (copied as JPEG from `packages/BrevMail/Tests/BrevMailTests/__Snapshots__/`):

| File | Shows |
| --- | --- |
| `month-light/dark/ax3.jpg` | Month grid with event dots (P3) |
| `day-light.jpg` | Day grid |
| `task-rows-light/dark/ax3.jpg` | Task rows with separate completion control and Overdue text (P4) |
| `*-cover-compact.jpg` | Calendar, Contacts, Tasks covers (`PIMRootViewSnapshotTests`) |

The task editor Form sheet, delete confirmation, week view and Contacts editor have no snapshot image in this folder and are unverified at runtime.

## Before shots (not rebuilt)

`origin/main` was not rebuilt; the audit's before images are reused: `docs/qa/ios-ux-audit-2026-10-09/screens/en-light-15-calendar.jpg`, `en-light-50-calendar.jpg`, `en-light-51-contacts.jpg`, `en-light-52-tasks.jpg` (and the matching `a11y-audit/en-light/*.audit.txt`).

## Accessibility audit (`a11y-audit/`)

`performAccessibilityAudit(for: .all)`, issues collected rather than failing. en-light and en-AX3 only.

| Screen | Light | AX3 |
| --- | --- | --- |
| Calendar empty | contrast (Done), dynamicType x4, textClipped x1 | same set |
| Contacts empty | contrast (Done), dynamicType x4, textClipped x1 | dynamicType x1 (Edit) |
| Tasks empty | contrast (Done), dynamicType x4, textClipped x1 | same set as light |
| Settings page from empty | textClipped x1 ("Add DAV Source…") | same |

Notes: the audit flags the empty-state text and toolbar nodes as Dynamic Type and clipping issues although the AX3 screenshots show the text scaling and wrapping fully, so "textClipped" and "dynamicType" look like false positives for these screens (to be confirmed with a VoiceOver/Larger Text hand pass). The Done contrast report remains in light mode and AX3 for Calendar and Tasks; its cause was not isolated (the button sits on a system-drawn capsule). Compare the audit's pre-slice reports for the same screens: `ios-ux-audit-2026-10-09/a11y-audit/en-light/50-calendar.audit.txt` etc.

## Observations

- Empty-state titles read "No tasks sources connected" and "No contacts sources connected" (pre-existing wording, ungrammatical; follow-up candidate).
- Contacts and Tasks use a large title while Calendar uses an inline title; not confirmed as intended, inconsistent when the three are compared side by side.
- Contacts list and editor: not reachable without a source (see above); nothing broken observed in the empty state.

## Known limits

VoiceOver speech, Reduce Motion, iPad, a live DAV source, the Calendar week view and nav/bottom-bar controls, the task editor and delete confirmation, and the Contacts editor were not run on a simulator in this pass.
