# Release validation — 2026-09-22

Validated on `main` @ `14923a8` (repair commit re-landing PR #85 after the
stale-base squash in #86 reverted it). Both apps rebuilt off this commit
in mock mode: macOS `Brev Test` + BrevIOS on iPhone 17 simulator.

## Merge history note

- `38e9c35` — #85 UI/UX audit fix set (C1–C3, N1–N13).
- `295d439` — #86 parity-matrix docs. **Squashed off a pre-#85 base; its
  tree silently reverted all 29 #85 files.** Regression found and
  runtime-verified by the post-merge validation pass.
- `55d45ee` — #87 contact-editing gaps (merged on top of the revert).
- `14923a8` — re-land of #85 via real 3-way merge. Verified: all 29
  restored files byte-identical to `38e9c35`; the two overlap files
  (`WORKLOG.md`, `ContactsRootView.swift`) carry both #85's and #87's
  hunks.

## Runtime regression matrix (recorded, both platforms)

| Item | Result | Evidence |
|---|---|---|
| C1 smart-view filter leak → folder blank list | pass (macOS + iOS) | recording, r4-02, r4-09 |
| C2 iOS Calendar/Contacts/Tasks covers → empty states | pass | r4-04 |
| C3 draft row reopens composer with fields | pass (macOS + iOS) | r4-06 |
| N1–N3 menu dedup / View menu / Window menu | pass | AX dump + recording |
| N5 PIM rail ~225pt, clean copy wrap | pass | r4-03 |
| N6 right-click unselected row selects + opens menu | pass | recording |
| N7 full-width autocomplete rows → chip | pass | recording |
| N8 last row clears iOS bottom pill | pass | r4-07 |
| N9 "Draft saved." toast | pass | r4-05 |
| N10 unified expanded-card header | pass | r4-01 |
| N11 per-view empty copy | pass | recording |
| N12 view-scoped footer counts | pass | recording |
| N13 Snooze… in reader "…" menu | pass | recording |

Also smoke-verified: reply→send lands in Sent, external-recipient guard
dialog fires, Tasks renders, Settings (Accounts/Appearance/Calendar &
Contacts) render fully, drafts persist across rebuilds.

## Test suites on repaired main

| Package | Result |
|---|---|
| BrevCalendar | 239 tests / 25 suites — pass |
| BrevMail | functional green; 85 pixel-snapshot failures are pre-existing baseline/render-env mismatches that reproduce on unmodified clean main |
| BrevBackend | 1141 tests / 113 suites — pass |
| BrevSettings | functional green; 34 pixel-snapshot failures — same pre-existing env mismatch |
| BrevAI / BrevAvatars / BrevCrypto / BrevDesign / BrevGmail / BrevPlugins / BrevSyncEngine / BrevThemes | all green (52+38+10+37+160+13+16+9 tests) |
| lint.sh / format.sh | clean |
| iOS snapshot baselines | committed + green (recipientSuggestionList, threadMessageCardExpanded) |

Fixed during validation: `CalendarGridLayout` day/week/month titles
rendered in the **system** time zone instead of the passed calendar's —
`.formatted` ignores the `calendar` argument. One real bug found by a
date-dependent test on a PDT machine; fixed via `titleStyle` helper in
`CalendarGridLayout.swift` (verified: "range titles render per mode" now
green on non-UTC).

## Close-readiness per open issue

| Issue | State | Gate |
|---|---|---|
| #53 | implemented (PR #52) | maintainer acceptance |
| #5 | implemented (PRs #56–59) | live-provider evidence |
| #6 | implemented (PRs #60, 61, 63, 65) | live-provider evidence |
| #7 | implemented (PRs #66, 67) | rendered share-sheet/Help verification |
| #8 | implemented (PRs #62, 64) | native interaction QA |
| #9 | implemented (PR #87) | live contacts source for editing QA |
| #10 | implemented (PRs #69, 70) | rendered verification |
| #11 | parity matrix ready (PR #86) | live fixtures run (Workspace + CalDAV + CardDAV) |
| #12 | implemented (PRs #72, 75, 76) | maintainer QA acceptance |
| #13 | implemented (PR #71) | rendered verification |
| #14 | code merged (PRs #77–78) | R8 decision (recommended: attachment path only) + live Drive QA |
| #15 | no code needed | maintainer go/no-go decision |

## Known gaps / maintainer-side only

- #87 contacts editing + calendar month grid are unreachable in mock
  (no PIM source) — need a real DAV/Google source.
- #11 matrix and #14 Drive picker QA need a disposable Google
  Workspace account + CalDAV/CardDAV credentials at run/build time.
- Board moves and issue closes: maintainer only (repo rule).
- Release tagging/signing/notarization: maintainer.

## Minor observations (non-blocking)

- Sent-copy quoted body renders literal `<br>`/`&lt;` HTML entities in
  the reader — likely pre-existing mock-quote formatting; worth a look
  pre-release.
