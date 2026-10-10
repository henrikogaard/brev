# iOS Mailboxes list and iPad compose sheet — runtime evidence, 2026-10-10

Slice 8a of the iOS UI/UX pass: native Mailboxes list and iPad compose sheet
(audit findings S1, S2, S3, I1, I2, I3).

| Item | Value |
| --- | --- |
| Build | iOS Debug, `BREV_USE_MOCK=1` mock backend (two accounts), no real accounts |
| Devices | Own simulators, created for this run and deleted afterwards: iPhone 17 Pro and iPad Air 13-inch (M3), iOS 27.0 |
| Driver | A temporary XCUITest bundle outside the repository; it is not committed |
| Variants | English light, English dark, Norwegian dark, English at AX3 (`UICTContentSizeCategoryAccessibilityXL`); iPad portrait and landscape, English light |

## What each shot proves

| Shot | Proves |
| --- | --- |
| `en-light-01-mailboxes` | Large "Mailboxes" title, inset-grouped list, Favourites / Smart Views / Apps / one section per account, unread counts as trailing secondary text, no "Inbox ›" button, Edit and Settings at the trailing edge, profile menu at the leading edge |
| `en-light-02-account-expanded` | An expanded account shows its folders in the same card; nested folders indent and use a disclosure control |
| `en-light-03-smart-views` | Smart Views use the same row style as every other row |
| `en-light-04-list-back-says-mailboxes` | Opening a mailbox pushes the list and Back reads "Mailboxes" (S1) |
| `en-light-05-edit-favourites` | Edit opens the existing favourites editor (reorder and hide) |
| `en-dark-*`, `nb-dark-*` | Dark theme and Norwegian copy ("Postkasser", "Rediger", "Favoritter", "Apper") |
| `en-light-ax3-*` | At AX3 titles wrap, icons scale with the text, unread counts drop under the title and no row truncates |
| `ipad-en-02-reply-form-sheet`, `ipad-en-03-new-message-form-sheet` | Reply and New Message present a form sheet over the split view (I1); the reader and list stay visible behind it |
| `ipad-en-04-relaunch-no-compose-window` | A fresh launch after Reply and New Message comes up with the main window only (I1) |
| `ipad-en-05-portrait-sidebar` | Sidebar over the list in portrait |
| `ipad-en-06-landscape-three-column`, `ipad-en-07-landscape-account-wraps` | Landscape three-column layout; "Henrik Øgård (private)" wraps to two lines in the 240 pt sidebar instead of truncating (I3). The XCUITest landscape capture arrives rotated; the files here are rotated back |

## Accessibility tree (XCUITest)

- All Inboxes is one button: label "All Inboxes", value "16 unread".
- A collapsed account header is one header button: value "Collapsed mailbox, 11 unread"; expanded it reads "Expanded mailbox".
- Smart Views is a header button with value Collapsed or Expanded.
- Folder rows read "Inbox", value "11 unread". The selected trait is set in code (`.isSelected` on the selected row) but was not read back from the runtime tree.
- No "Show messages" button exists any more.

`performAccessibilityAudit()` on the Mailboxes screen reports no contrast and no hit-area issue. It still
reports "Dynamic Type font sizes are partially unsupported" for the system Edit bar button, and "Text clipped"
without naming an element (visually nothing is clipped; the same pair shows on the other screens in the audit).

## Not covered at runtime

- VoiceOver speech: the tree and traits are asserted, nothing was heard.
- Drag and drop of a message onto a folder row (kept, not exercised).
- iPad Stage Manager and Split View multi-window behaviour.
- A relaunch with a compose scene persisted by an older build: nothing creates the compose scene any more, so there
  is nothing new to restore, but a scene already stored by an old build is not removed. `restorationBehavior(.disabled)` needs
  iOS 18 and `SceneBuilder` cannot apply it conditionally on a deployment target of 17.
