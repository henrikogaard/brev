# iOS slice 5: native search (audit Q1, Q2), 2026-10-10

Driven with a temporary XCUITest (not committed) on an iPhone 17 Pro and an
iPad Air 13-inch (M3) simulator, iOS 27, mock data (`BREV_USE_MOCK=1`).

| Screenshot | Shows |
| --- | --- |
| `en-light-01-list-bottom-search` | Search field and Compose in the bottom bar, no bands |
| `en-light-02-focused-scope-suggestions` | Focused field with close button, Current/All mailboxes scope bar, suggested filters and senders |
| `en-light-03-typed-field-tokens` | Typed text: "Search in From / Subject" and matching senders |
| `en-light-04-results-no-bands` | Results of a complete local search: scope bar only, no strip, chip row or status band |
| `en-light-05-scope-all-mailboxes` | Scope switched to All mailboxes |
| `en-light-06-unread-token`, `-07-sender-token-results`, `-08-subject-token-results` | Tokens in the field and the filtered results |
| `en-light-09-recent-searches` | Cancel returns the unfiltered list |
| `en-light-10-select-mode-no-search` | Selection mode replaces the bottom bar; no search field |
| `en-light-11/12-all-inboxes` | All Inboxes: no scope bar, no bands |
| `en-dark-*`, `nb-dark-*`, `en-light-ax3-*` | Dark, Norwegian and accessibility 3 |
| `ipad-en-*` | iPad: field at the top of the list column, scope bar, suggestions incl. search location |

`performAccessibilityAudit` on the focused field, results, tokens, sender
results and All Inboxes results reports only system-drawn elements: the
keyboard's "Typing Predictions" buttons (no description), the token field's
"Clear text" button (20 pt), the system "close" button (38 pt), and on iPad
pre-existing list-row Dynamic Type/clipping findings (audit L9). The old
18 pt predicate chip remove target and the grey status band no longer exist on
iOS. The footnote states are covered by the snapshot references
`PhoneMessageListSnapshotTests/searchFootnote*.png`.
