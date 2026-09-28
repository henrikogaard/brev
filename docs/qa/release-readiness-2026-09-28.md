# Brev release-readiness verification — 2026-09-28

Revision: `main` @ `333754c` — all prior work merged, including the `test
(BrevMail)` CI fix (#136). Three legs: an iPad walk (never covered before), an
iOS VoiceOver sweep of the mail surfaces (mailbox / reader / composer —
not the PIM surfaces tracked as matrix row 5.1, which remain untested),
and an iOS snapshot
baseline-drift audit (no re-record — categorized list only).

Environments exercised:

| Leg | Build / device | Modes |
| --- | --- | --- |
| iPad pass | `BrevIOS` team-signed from `main` @ `333754c`, iPad Pro 13" (M5) sim `94CF6E4E…`, iOS 27.0, live demo-ish session (mailo.com + Gmail accounts present) | Portrait + landscape, light |
| VoiceOver | Same build, iPhone 17 sim `8E780854…`, iOS 27.0 | VoiceOver ON (real engine, toggled via Settings → Accessibility), Gmail account with sync-error state |
| Snapshot drift | `packages/BrevMail` scheme (standalone), iPhone 17 sim | `xcodebuild … -testLanguage en -testRegion en_US test`, CI `-only-testing:` list |

Screenshots live in `docs/qa/release-readiness-2026-09-28/`.
Recording: `rec-phasea-0928` (this pass).

**Input caveat (iPad):** the iOS accessibility bridge binds to only one
simulator per session and stayed bound to the iPhone; iPad was driven by
screen-coordinate input + `simctl io` framebuffer screenshots. All iPad
assertions are framebuffer-verified, not AX-verified.

---

## Leg 1 — iPad pass (iPad Pro 13", iOS 27)

Verdict: **the iPad layout is fundamentally sound** — three-pane split view,
all PIM covers, calendar grids, composer, settings and landscape all render
correctly. The N-H1 cover-clipping bug does NOT reproduce on iPad. No new
high-severity issues.

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Mailbox list 3-pane (folders / list / detail) portrait | ✅ renders correctly | `ipad-01-launch.png` |
| 2 | Reader portrait | ✅ | `ipad-02-reader-portrait.png` |
| 3 | Calendar cover — no N-H1 clipping, back/dismiss reachable | ✅ | `ipad-03-calendar-cover.png` |
| 4 | Contacts cover — no N-H1 clipping | ✅ | `ipad-04-contacts-cover.png` |
| 5 | Tasks cover | ✅ (minor polish, below) | — |
| 6 | Calendar Agenda / Week / Month grids, stub seeds at ~09:30 / ~13:00 local | ✅ all three correct | `ipad-03-calendar-cover.png` |
| 7 | Event detail + P1 read-only caption | ✅ | — |
| 8 | Composer — centered card, draft banner | ✅ | — |
| 9 | Settings split view; Calendar & Contacts with connected StubDAV source | ✅ | — |
| 10 | All Inboxes + bottom search capsule — layout sane at iPad width | ✅ capsule centers correctly, does not collide with stats pill | — |
| 11 | Search filters + scope chips + "Search finished. Some results may be missing" | ✅ | — |
| 12 | Landscape reader — back button visible/tappable (N-M1 holds on iPad) | ✅ | `ipad-05-landscape-reader.png` |

Minor polish observations (not blockers):
- **Contacts/Tasks covers open with a collapsed narrow list column** on iPad —
  the content column starts squeezed and needs widening. Cosmetic.
- **Bottom search capsule on iPad:** lays out sanely — centered, floats above
  the bottom bar, no overlap with the stats pill. The `bottomSearchCapsuleLift`
  spacing looks correct at iPad scale.
- **Teal rectangular focus outline over calendar agenda rows (the known M5
  caveat): not observed** in this pass — agenda rows showed no focus ring
  during touch-driven navigation.

Not exercisable on iPad in this pass (honest gaps):
- **Onboarding** — the sim already has live accounts and `demoModeEnabled`;
  a true clean-onboarding run needs a wiped sim. Not tested.
- **Pointer/trackpad hover states** — `simctl` cannot synthesize trackpad
  hover; needs a device or iPadOS pointer simulation. Not tested.
- **The iOS AX bridge limitation** meant the iPad was driven blind of AX —
  labels/focus-order on iPad were not audited (iPhone covered that in leg 2).

---

## Leg 2 — iOS VoiceOver (iPhone 17, iOS 27)

Verdict: **VoiceOver coverage is largely good** — mailbox rows announce
comprehensively, focus order is logical, bottom chrome and banners are
labeled. Two real defects found (nav-bar dead zone in sync-error state;
composer field naming gaps) plus minor polish notes.

VoiceOver was genuinely enabled (Settings → Accessibility → VoiceOver,
gestures-modal dismissed, focus box + speech confirmed on device).

### Verified under real VoiceOver (focus box + traversal observed)

| Surface | Result |
| --- | --- |
| Mailbox list rows | ✅ announce "Unread, G, Google, 4, 2h, Sikkerhetsvarsel, Du har gitt Brev tilgang…" — sender, subject, unread state, age all in the label |
| Section headers | ✅ announce e.g. "Yesterday, 1 messages, expanded" — count + expanded state |
| Bottom search capsule (#133) | ✅ `textinput "Search messages"`, receives VO focus |
| Compose button | ✅ `button "Compose"`, receives VO focus, last in order |
| Focus order | ✅ banner → rows (auto-scrolls, paginated) → capsule → Compose |
| Sign-in banner | ✅ label + "Try Again" + "Dismiss" all labeled |
| Inline banner ("Gmail authorization has expired") | ✅ label + "Refresh" + "Dismiss" |
| Reader | ✅ "Back to messages", subject, sender, "4 messages from 1 participants", "Conversation controls" combobox, message cards announce "Google, Collapsed/Expanded message", body label, bottom bar Reply / Archive[disabled] / Delete / "More message actions" |
| Row swipe actions | ✅ Flag / Read revealed on swipe |

### Findings

| Sev | Finding | Evidence |
| --- | --- | --- |
| **high** | **Nav bar dead zone in the "Sync interrupted" state.** With the compact "Sync interrupted. Sign in again to continue." pill showing, the nav row (compact pill + INBOX title + ≡ hamburger + ↻ Retry) is **not exposed to accessibility at all** — the AX group contains no children, so a VoiceOver user cannot open the mailbox drawer, read the title, or hit Retry. It was also completely unresponsive to taps (coordinate tap, held-press, edge-swipe) across an app restart — while list rows and banners responded normally. **Caveat:** this needs physical-device confirmation; the sim state may contribute. But the missing AX children is an app-side fact, not an input artifact — under VO those controls simply don't exist. | `ios-vo-nav-deadzone.png` |
| medium | Composer field naming: the To field announces only its placeholder `name@example.com` (no field name); the body `multilinetextinput` has no accessible name at all. VO users can't tell which field they're on. (Post-#111 composer.) | AX tree |
| polish | Collapsed thread-message cards announce sender only — "Google, Collapsed message" — no subject; expanded siblings give more context. | AX tree |
| polish | Some thread-child rows surface as `label`/`unknown` rather than `button` — they announce but their activate affordance is ambiguous to VO. | AX tree |

### VO items not reached (drawer blocked by the dead zone above)
- **Mailbox drawer contents** (folder list, Smart Views, Settings entry) —
  the hamburger would not open the drawer in the sync-error state. Folder
  labels were verified earlier on iPad visually; VO audit pending the nav fix.
- **Settings toggles** — unreachable without the drawer.
- **Account-add sheet** — partially covered previously (fields labeled);
  full VO traversal not re-run this pass.

**Rotor/nav:** VO focus navigation via Ctrl+Option+Left/Right worked
throughout (focus box rendered, order sane). Rotor specifics (headings/
landmarks) not exercised — the sweep covered linear traversal.

---

## Leg 3 — iOS snapshot baseline drift (no re-record)

Command (CI-exact, standalone scheme — `-workspace` does not contain it):
`cd packages/BrevMail && xcodebuild -scheme BrevMail -destination 'platform=iOS
Simulator,id=8E780854-5816-4435-AD8F-8098DF847EB5' -skipMacroValidation
-testLanguage en -testRegion en_US -only-testing:… test`

Result: **TEST FAILED** — 23 tests in 7 suites, 20 issues (plus one benign
600 s diagnostics-collection timeout caused by a mid-run sim shutdown, not a
test failure).

### Failing suites/tests — categorized

Category **(a) = genuine UI drift from merged PRs → needs RECORD_SNAPSHOTS
refresh.** Category **(b) = sim-renderer noise.** **All inspected diffs are
structural — no category-(b) noise found.**

| Suite / test | Category | Cause (from diff images) |
| --- | --- | --- |
| `BrevMailRootViewSnapshotTests.rootViewWideLayout` | (a) | **#133** — new bottom search capsule present in actual, absent in reference |
| `ComposeViewSnapshotTests.emptyCompose` | (a) | **#111** — composer header/field shifts |
| `ComposeViewSnapshotTests.replyCompose` | (a) | **#111** |
| `BrevMailSnapshotTests.composeViewRendersSignaturePicker` | (a) | **#111** |
| `BrevMailSnapshotTests.threadConversationViewRendersDeterministically` | (a) | **#105/#126** — reader toolbar/actions layout |
| `MessageDetailViewSnapshotTests.headerPresentRendersSubjectAndSender` | (a) | **#105/#126** — detail header chrome |
| `PIMRootViewSnapshotTests.contactsCoverCompact` | (a) | cover header + bottom-search realignment (#133-adjacent) |
| `PIMRootViewSnapshotTests.tasksCoverCompact` | (a) | same |
| `PIMRootViewSnapshotTests.calendarCoverCompact` | (a) | same |
| `PhoneMailboxSnapshotTests.narrowCompose` | (a) | **#111** |
| `PhoneMailboxSnapshotTests conversation(accessibility:)` light | (a) | **#133** — capsule + toolbar change |
| `PhoneMailboxSnapshotTests conversation(accessibility:)` dark | (a) | same |
| `PhoneMailboxSnapshotTests phoneCompose(accessibility:)` light | (a) | **#111** |
| `PhoneMailboxSnapshotTests phoneCompose(accessibility:)` dark | (a) | **#111** |
| `PhoneMailboxSnapshotTests mailboxes(dark:)` ×2 | (a) | **#133** |
| `PhoneMailboxSnapshotTests twoAccountMailboxes(dark:)` ×2 | (a) | **#133** |
| `PhoneMailboxSnapshotTests inbox(dark:)` ×2 | (a) | **#133** — removed top band + shifted rows |

Diff evidence: `snap-rootwide-reference.png` vs `snap-rootwide-failure.png` vs
`snap-rootwide-difference.png` (bottom capsule clearly new);
`snap-contactscover-difference.png` (cover realignment).

### Passed (not drifted)
`bodyLoadErrorState`, `noSelectionPlaceholder`, `threadMessageCard*`,
`recipientSuggestionList`, `ComposeAccessibilityBoundsTests`,
`CompactSettingsRowSnapshotTests` — baselines still match.

### Recommendation
Every failure inspected is genuine drift from intentionally-merged UI changes
(#105 toolbar, #111 composer, #133 search capsule, plus the PIM cover
realignment). Refresh the baselines in one `RECORD_SNAPSHOTS` run — none of
these look like regressions to fix; the code intentionally moved these pixels.
xcresult: `~/Library/Developer/Xcode/DerivedData/BrevMail-chsgvjtvjjhaoocrpaoogkbseuxs/Logs/Test/Test-BrevMail-2026.09.28_01-36-45--0700.xcresult`.

---

## Summary

| Leg | Verdict |
| --- | --- |
| iPad | ✅ healthy — no new high-severity; onboarding + hover untested |
| iOS VoiceOver | ⚠️ one high finding (nav dead zone in sync-error state, VO-invisible controls) + medium composer naming; rest solid |
| Snapshot drift | 23 failures, all genuine-UI-drift (category a) → one RECORD_SNAPSHOTS refresh PR covers them |

Fix-first candidate from this pass: the **iOS nav-bar dead zone** — in the
sync-error state VoiceOver cannot reach the mailbox drawer and the row ignores
taps; confirm on device and investigate the collapsed banner overlay's
hit-testing/accessibility exposure.
