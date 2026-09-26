# Brev UI/UX review — 2026-09-26

Revision: `fix/sidebar-compact-alignment` @ `28de262` (PR #100).
Reviewer stance: Apple-platform designer doing a pre-v1 pass; reference apps are
Apple Mail, Calendar, Contacts and Reminders. This is a critique, not a pass/fail
regression run. No app code was changed.

Environments exercised:

| Platform | Build | Modes covered |
| --- | --- | --- |
| macOS 26 | `Brev Test (2026-09-26).app` (mock, `./script/build_and_run.sh --mock`) | Light + Dark (in-app Appearance), 1440 / 900 / 700 pt widths |
| iPhone 17, iOS 27 (`8E780854…`) | `BrevIOS` from this revision, `BREV_USE_MOCK=1` | Light + Dark, Dynamic Type medium + accessibility-extra-large |
| iPad Pro 11-inch (M5), iPadOS 27 (`3E3909F4…`) | same build | Light + Dark, portrait split view |
| Stub DAV server | `scripts/stub-dav-server.py --port 8643` | CalDAV calendar, CardDAV, CalDAV tasks connected through Settings |

Screenshots live in `docs/qa/uiux-review-2026-09-26/` (referenced below).
Recording: `/Users/devin/screencasts/rec-08c0a49d-7ccd-4e72-82a8-e70f5f4c4c9d/rec-08c0a49d-7ccd-4e72-82a8-e70f5f4c4c9d-edited.mp4`.

Not reached in this pass (called out honestly rather than inferred): Calendar /
Contacts / Tasks **editors** (no create/edit affordance found in the UI on any
platform), iPad Contacts/Tasks, iPad rotation, macOS toast/banner states (none
were triggered by the mock data), Settings sections beyond Accounts, Appearance,
Mailbox View and Calendar & Contacts (rail was inspected, individual sections
were spot-checked only), swipe-back gesture on iPhone (chevron back was used).

---

## Top-10 "fix first"

| # | Severity | Surface (platform) | Finding | Screenshot |
| --- | --- | --- | --- | --- |
| 1 | high | Add DAV Source sheet (macOS + iOS) | Three stacked black segmented pills, premature warning box, custom field chrome, weak grouping — the least native sheet in the app | `macos-19…`, `macos-27…`, `iphone-04…` |
| 2 | high | Reader (macOS) | At ~700 pt window width the message body is clipped mid-line and the rest of the pane is blank | `macos-32-dark-window-700w.png` |
| 3 | high | Thread view (iPhone) | Opening a 2-message thread shows every message collapsed; tapping a row only toggles the header, no body is ever shown | `iphone-09-dark-thread-all-collapsed.png` |
| 4 | high | Sidebar (macOS, PR #100) | Parent-folder glyphs sit ~10 pt right of leaf glyphs (chevron + icon vs icon only); Apple Mail keeps one glyph column | `macos-03-light-parent-vs-leaf-icon-x.png` |
| 5 | high | Sidebar icons-off (macOS, PR #100) | Disclosure chevron touches the folder label with 0 pt gap; 10 pt hit target is below Apple's 16 pt minimum | `macos-05-light-icons-off-chevron-touching-label.png` |
| 6 | high | Add mail account sheet (macOS) | "Advanced setup" disclosure ignores mouse clicks (works only via AX press); choosing "Manual IMAP/SMTP" shows a warning dead-end instead of a form | `macos-28-dark-add-account-manual-blocked.png` |
| 7 | high | Settings → Calendar & Contacts sources (macOS + iOS) | Two per-source toggles (Background sync / Editing) have no visible label; on iPhone collection names truncate to "Stub Ca…" at default type size | `macos-20…`, `iphone-03…` |
| 8 | high | Window menu / main window (macOS) | Closing the main window leaves no menu path to reopen it (Window menu lists only Calendar/Contacts/Tasks/Settings; File has no New Viewer Window); Dock reopen resets to a different mailbox | `macos-29-dark-main-window.png` |
| 9 | medium | Mailboxes root + iPad sidebar (iOS) | Calendar / Contacts / Tasks are floating pill chips overlapping list rows instead of sidebar rows | `iphone-02…`, `ipad-02…` |
| 10 | medium | Composer (macOS) | To / From / Subject labels sit at three different x positions; reply quote renders as raw `>` lines | `macos-13…`, `macos-14…`, `macos-30…` |

---

## Findings by severity

### High

#### H1 — Add DAV Source sheet is non-native (macOS + iOS)
- **Surface:** Settings → Calendar & Contacts → Add DAV Source…
- **What's off:** Source type, Discover/Manual and App password/Access token are
  three stacked segmented controls with a heavy black selected segment (custom
  pill, not `NSSegmentedControl`/`Picker(.segmented)`). A yellow warning box with
  three validation rows ("Enter a server URL…", "Enter a username", "Enter an
  app-specific password") is shown *before* the user has typed anything. Text
  fields use flat dark rounded chrome rather than the system bezel, and on iOS
  they are not in an inset-grouped `Form`. Segment labels truncate on iPhone
  ("Contacts (CardDA…"). Grouping is weak: Server / Credentials / Display name
  have headings but no visual grouping.
- **Why it matters:** Apple's "Add Account" flows use one picker at most,
  never show validation until submit/blur, and use standard grouped forms.
- **Fix:** Collapse to a single `Picker` for source type (segmented on macOS,
  menu on iOS); derive auth mode from the field the user fills; move
  validation to on-submit inline errors; use `Form` with `.formStyle(.grouped)`
  (macOS) / `.insetGrouped` (iOS) and plain `TextField`/`SecureField`.
- **Screenshots:** `macos-19-light-add-dav-sheet-premature-validation.png`,
  `macos-27-dark-add-dav-sheet-stacked-pills.png`,
  `iphone-04-dark-add-dav-sheet-stacked-pills.png`.

#### H2 — Reader clips at 700 pt width (macOS)
- Body text ends mid-line ("…before our next check-" / "in." cut) and the
  remainder of the reader pane is blank; the sidebar and list stay full width
  while the reader shrinks to ~260 pt. Apple Mail collapses the sidebar first
  and never clips body text.
- **Fix:** set minimum column widths on the `NavigationSplitView` (sidebar
  collapses first), and let the message body scroll rather than fix its height.
- `macos-32-dark-window-700w.png`, `macos-31-dark-window-900w.png`.

#### H3 — iPhone thread opens fully collapsed
- Tapping a 2-message thread shows two collapsed header rows and no body;
  tapping a row only toggles header detail. Single-message reader is fine.
- **Fix:** expand the latest (or first unread) message on open, like Mail.
- `iphone-09-dark-thread-all-collapsed.png`.

#### H4 — Sidebar glyph column is not shared between parent and leaf rows (macOS, PR #100)
- Measured in the mock: top-level leaf icons (Inbox, Drafts…) at x≈22, parent
  icons (Archive, Imported) at x≈32 because the chevron is inline; child icons
  at x≈45. Apple Mail aligns all glyphs in one column and puts the chevron in a
  reserved gutter. Group header text ("Henrik Øgård (private)") starts at the
  chevron x, not the glyph x.
- **Fix:** reserve a fixed chevron gutter for every row (leaf rows render it
  clear) so icons share one column; indent children by one gutter width.
- `macos-02-light-sidebar-icons-on.png`, `macos-03-light-parent-vs-leaf-icon-x.png`.

#### H5 — Icons-off mode: chevron touches label; 10 pt hit target (macOS, PR #100)
- With View → Show Sidebar Icons off, `folderRowControlSpacing` = 0 leaves the
  disclosure chevron flush against the folder name; `disclosureHitSize` is
  10 pt. Leaf labels do keep a stable column (good), but parents look
  "⌄Imported".
- **Fix:** keep ≥ 4 pt between chevron and label, restore ≥ 16 pt hit size.
- `macos-04-light-sidebar-icons-off.png`, `macos-05-light-icons-off-chevron-touching-label.png`.

#### H6 — Add mail account sheet affordances (macOS)
- "Advanced setup" disclosure did not react to clicks on the chevron or label
  (only AX `press` toggled it). After choosing "Manual IMAP/SMTP" the sheet
  shows a warning "Enter a valid email address before editing IMAP/SMTP
  settings" instead of the server form — a dead end. The sheet has ~180 pt of
  empty space below the field, and the email field shows a mint focus ring.
  Same pattern on iOS: provider shortcuts are three left-aligned boxed buttons
  of different widths; sheet has no navigation bar; "Test connection" is a
  disabled ghost label.
- **Fix:** make the whole disclosure row a `Button`; show the manual form
  with the email field required at submit; size the sheet to content; use a
  `NavigationStack` with title + Cancel on iOS; standard bordered buttons.
- `macos-28-dark-add-account-manual-blocked.png`,
  `iphone-06-dark-add-account-sheet.png`, `iphone-07-dark-add-account-advanced-buttons.png`.

#### H7 — DAV source rows: unlabeled toggles, truncation (macOS + iOS)
- Each source row has two faint toggles whose meaning ("Background sync",
  "Editing") is only exposed via AX; visually they read as disabled controls.
  iPhone row truncates "Stub Ca…" and wraps "Stub Calendar" under the type.
- **Fix:** label the toggles (or move them into the ⋯ menu / a detail view);
  put collection names on their own line.
- `macos-20-light-settings-dav-sources-unlabeled-toggles.png`, `iphone-03-dark-settings-dav-sources-truncated.png`.

#### H8 — No way to reopen the main viewer from menus (macOS)
- Window menu lists Calendar, Contacts, Tasks and "Brev Settings" (Settings
  belongs in the app menu, ⌘,) but not the mail viewer; File has no "New
  Viewer Window". After ⌘W the only route back is the Dock icon, and the
  window reopened on a different account's inbox.
- **Fix:** add Window → Message Viewer (⌥⌘N like Mail), list the viewer in the
  Window menu, restore last selection.
- `macos-29-dark-main-window.png`.

### Medium

| ID | Surface (platform) | Finding | Fix | Screenshot |
| --- | --- | --- | --- | --- |
| M1 | Mailboxes root / iPad sidebar (iOS) | Calendar, Contacts, Tasks are floating pill chips that overlap the last list rows ("Newsletters") | Make them sidebar rows (or a tab bar) | `iphone-02-dark-mailboxes-root-chips-overlap.png`, `ipad-02-light-sidebar-overlay-pim-chips.png` |
| M2 | Composer (macOS) | To ≈ x336, From ≈ x328, Subject ≈ x318 — label gutter not aligned; Send is a filled black capsule heavier than Mail's toolbar icon | Right-align labels in a fixed-width gutter; use toolbar send | `macos-13-light-composer-field-rows.png`, `macos-30-dark-composer-label-gutter.png` |
| M3 | Reply composer (macOS) | Quote renders as raw `>` prefixed lines instead of a coloured quote bar | Render blockquote with leading accent bar | `macos-14-light-composer-reply-quote.png` |
| M4 | Search (macOS) | Scope pills (All/From/Subject…) are heavy black chips; search field shows a prominent mint focus ring around the pane | Use `NSSearchField` tokens/menu; drop custom focus ring | `macos-07-light-search-scope-chips.png`, `macos-08-light-search-field-focus-ring.png` |
| M5 | Selection colour (macOS) | Calendar/Contacts/Tasks lists use a filled teal selection; mail list uses neutral grey — inconsistent | Use one selection style (system accent) | `macos-22-light-calendar-event-selected-teal.png` |
| M6 | PIM windows (macOS) | Tasks opens tiny with toolbar overflow (») and truncated title; Calendar opens large; default sizes inconsistent | Set sensible min/default sizes per scene | `macos-25-light-tasks-window-tiny-default-overflow.png` |
| M7 | Calendar month view (macOS) | No grid lines, event chips are grey/black blocks not coloured by calendar, weekday header tiny | Adopt Calendar-style grid with calendar colour chips | `macos-23-light-calendar-month-grid.png` |
| M8 | Calendar (iPad) | Opening Calendar hides the agenda column; two empty states ("No calendars connected" + "No event selected") side by side; modal "Done" in a primary surface | Show agenda column; single empty state | `ipad-03-light-calendar-empty-no-agenda-column.png`, `ipad-04-light-calendar-double-empty-state.png` |
| M9 | Settings (macOS + iOS) | Orphan caption "Applies to all mailboxes" sits above the section title; Mailbox View tabs reuse the heavy black pill | Move caption below title; use system tab style | `macos-17-light-settings-appearance.png`, `iphone-12-dark-settings-appearance.png` |
| M10 | Settings → Accounts (iPhone) | Both mailbox rows truncate to "Henrik Øgår…" and are indistinguishable; "Add account" is a boxed button | Show address on its own line; plain list-row button | `iphone-05-dark-settings-accounts-truncated.png` |
| M11 | Thread list (macOS) | Unread dot column shifts between parent and child rows | Fix dot to a constant leading column | `macos-10-light-thread-list-unread-dot-columns.png` |
| M12 | Mailboxes root (iPhone) | Top-left button is a forward chevron (›) at the root — reads as "go forward"; footer pill "9 messages · 5 unread" + compose overlaps the last row | Use sidebar glyph; add bottom inset for the pill | `iphone-02-dark-mailboxes-root-chips-overlap.png`, `iphone-14-light-inbox.png` |

### Polish

| ID | Surface (platform) | Finding | Fix | Screenshot |
| --- | --- | --- | --- | --- |
| P1 | Contacts detail (macOS) | Phone/email labels shown as raw vCard types ("Work,voice") | Map to localized labels (work, mobile) | `macos-24-light-contacts-detail-raw-vcard-labels.png` |
| P2 | Calendar agenda (macOS) | Stub events show 12:30–12:50 AM — looks like a UTC conversion, verify time-zone handling | Format in local zone | `macos-21-light-calendar-agenda-empty-detail.png` |
| P3 | Reader (iPhone) | "Dark" pill floats at top-right of body (per-message dark toggle); not an Apple Mail idiom | Move to ⋯ menu | `iphone-13-light-reader.png` |
| P4 | Dynamic Type (iPhone) | At accessibility-extra-large rows scale correctly but group header ("Today 2") and footer pill stay small and the pill covers rows | Scale headers with `.dynamicTypeSize`; inset list bottom | `iphone-10-dark-inbox-axXL.png`, `iphone-08-dark-settings-axXL.png` |
| P5 | Window menu (macOS) | Calendar/Contacts/Tasks lack shortcuts; "Brev Settings" duplicated in Window menu | Add ⌥⌘1-3, remove duplicate | — |
| P6 | Settings → Accounts (macOS) | Fine overall, but ⋯ menu button and "Default account" badge are visually lighter than the rest of the row | Align weights | `macos-16-light-settings-accounts.png` |

---

## What already feels good (do not regress)

| Surface | Why it works |
| --- | --- |
| Message list typography (macOS + iOS) | Sender bold / subject regular / preview secondary is a clean 3-tier hierarchy; date grouping headers and footer count match Mail |
| Empty folder state (macOS Trash) | Centered glyph + short copy, nothing heavy — `macos-09-light-trash-empty-state.png` |
| Dark palette (macOS + iOS) | Neutral greys, no coloured tint on chrome, good contrast — `macos-29-dark-main-window.png`, `iphone-11-dark-inbox-default.png` |
| iOS Settings root and iPad inbox split | Native inset-grouped list, large title, glass toolbar groups, sensible column proportions — `ipad-01-light-inbox-split.png`, `iphone-14-light-inbox.png` |
| Sidebar icons toggle plumbing | View → Show Sidebar Icons and Settings → Mailbox View → Folders → "Sidebar icons" stay in sync and update live; leaf labels keep a stable column with icons off |
| AX labels | Sidebar rows, toolbar buttons, DAV toggles, list rows all expose meaningful labels (e.g. "Background sync for localhost", row summaries with unread state) |
| iPhone single-message reader | Header, avatar, action bar and body spacing are close to Mail — `iphone-13-light-reader.png` |
| Sort/filter popover (macOS) | Standard menu with checkmarks — `macos-06-light-sort-filter-menu.png` |

---

## Screenshot index

All files in `docs/qa/uiux-review-2026-09-26/`: `macos-01` … `macos-32`
(light 01–25, dark 26–32), `iphone-01` … `iphone-14`, `ipad-01` … `ipad-06`.
Names encode platform, mode, surface and the finding they support.
