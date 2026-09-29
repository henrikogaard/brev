# Navigation polish — 2026-09-29

The iPhone mailbox screen and Settings now share compact, grouped navigation.
This pass implements the approved eight-category Settings proposal and polishes
the existing Favourites feature in PR #162, on `feature/uiux-audit-fixes`, targeting
`main`. The previous branch head was `ff66f53d`. The initial pass was review work; the later internal TestFlight deployment is recorded separately below.

## Reference comparison and design decisions

Competitor comparison used official product documentation and the supplied Apple
Mail screenshot. These are reference findings, not hands-on competitor app tests.
No saved Product Design user context was available; the user's compactness and
cross-platform consistency requests guided the pass.

| Reference | Relevant pattern | Applied to Brev |
| --- | --- | --- |
| [Apple Mail mailboxes](https://support.apple.com/en-ie/104971) | A short list of useful mailboxes, editable ordering, and clear mailbox rows | Inset Favourites and account groups, inset separators, aligned icons and quiet trailing counts |
| [Spark sidebar customisation](https://sparkmailapp.com/help/tips-tricks/customize-the-sidebar) | Choose shortcuts and reorder them; keep less-used folders behind a second level | Checkmark selection and native drag handles in the editor; accounts expand on demand |
| [Mailspring multiple accounts](https://www.getmailspring.com/docs/setting-up-multiple-accounts) | Distinguish the unified destination from account-specific destinations | All Inboxes stays explicit; individual inboxes and Drafts/Sent retain their account identity. Mailspring is a desktop reference here |

The previous screen's flat hierarchy, capsule badges and large utility labels
made it feel busier than its information warranted. The new screen groups
related rows and uses the same icon/text alignment throughout. Compactness comes
from removing redundant padding; buttons retain a 44-point minimum target.
Accessibility text wraps, with readable unread/draft descriptions below the
label. Decorative icons stay within their columns.

| Screen | Before | After |
| --- | --- | --- |
| Mailboxes | [Flat hierarchy](ios-before.jpg) | [Inset groups](ios-after.jpg) |
| Favourites editor | [Switches](editor-before.jpg) | [Checkmarks and reorder handles](editor-after.jpg) |
| Account folders | — | [Expanded account with aligned folders](ios-expanded.jpg) |
| iPhone Settings | — | [Eight categories plus About & Updates](ios-settings.jpg) |
| Writing | — | [Send safety before recipient history](ios-writing.jpg) |
| Settings search | — | [Gravatar result opens and scrolls to Privacy](ios-settings-search.jpg) |

Screenshots above are from the real iPhone simulator app, in Norwegian, using
mock mail and fixture addresses. The optional Example Plugin row is a fixture
contribution and remains separate from built-in categories.

## Settings organisation

| Category | Subpages |
| --- | --- |
| Accounts & Connections | Accounts; Calendar & Contacts |
| Appearance | Shared desktop text size/density, themes and appearance |
| Mailboxes & Reading | Mailbox View; Smart Views |
| Writing | Compose; Signature; Templates; AI Writer |
| Notifications | Notification preferences |
| Rules & Organisation | Rules; VIP & Reminders; Auto-Reply |
| Privacy & Security | Privacy; Security |
| Sync & Storage | Folder Sync; Mail Storage; Preferences; Import / Export |
| About & Updates | About; Updates |

Desktop uses a compact sidebar and native segmented subpage pickers. iPhone uses
the same categories with push navigation. Developer remains capability-gated;
extensions appear only when contributed. Existing leaf IDs, saved preference
keys, consent defaults and account scope are preserved.

Writing puts Send safety after defaults, with recent recipients in a disclosure.
Privacy now owns remote-image and avatar-source consent. Browser choice moves to
Mailbox View's Browser tab; iCloud preference sync moves to Preferences under
Sync & Storage. Search lists the category and exact leaf destination and opens
the matching control. No new endpoint or external network behavior was added.

Desktop render evidence is in the committed snapshot references:

- [Writing, light](../../../packages/BrevSettings/Tests/BrevSettingsTests/__Snapshots__/BrevSettingsSnapshotTests/capture-_-theme-name-size.compose-light.png)
- [Privacy, dark](../../../packages/BrevSettings/Tests/BrevSettingsTests/__Snapshots__/BrevSettingsSnapshotTests/capture-_-theme-name-size.privacy-dark.png)
- [Large text with spacious density](../../../packages/BrevSettings/Tests/BrevSettingsTests/__Snapshots__/BrevSettingsSnapshotTests/capture-_-theme-name-size.desktop-large-spacious.png)

These are AppKit-rendered snapshots, not interactive desktop-window captures.

## Verification

Environment: macOS host with Xcode 27, iOS 27 simulator
`20E1894E-648E-4BBD-A273-555EDE378FB7` (Brev UIUX QA 2026-09-29), mock mode.
Native simulator screenshots use normal Dynamic Type and light appearance;
snapshot comparisons additionally cover dark and accessibility text layouts.

| Check | Result and scope |
| --- | --- |
| Mail behaviour | 43 tests in 3 suites passed: Favourites persistence/order/count semantics, sidebar presentation and disclosure |
| Settings behaviour and desktop renders | 51 tests in 5 suites passed, including 11 desktop image comparisons for Writing, Signature, Privacy, preference sync, navigation, and small/compact versus large/spacious sizing |
| iPhone renders | Eight final image comparisons passed across targeted runs: mailboxes light/dark, expanded accounts light/dark, editor, long-account accessibility layout, and normal/accessibility Settings categories |
| Native iPhone interaction | Added/removed a Sent shortcut; dragged an inbox and restored its order; expanded/collapsed account folders; entered Writing and Compose; verified Done; searched Gravatar and reached its control under Privacy |
| Native app builds | Both targets built; the dated macOS mock app launched. The daily-driver app was not replaced |
| Simulator mirror | A real frame rendered at localhost:3200; mirror retained for review |
| Repository checks | Lint, format (0 of 1,201 files changed on final check), actionlint and diff checks passed |

Focused commands:

```sh
swift test --package-path packages/BrevMail --filter 'MailboxFavoritesTests|FolderSidebarPresentationTests|MailboxGroupDisclosureTests'
swift test --package-path packages/BrevSettings --filter 'SettingsNavigationStateTests|ComposeSettingsTests|AvatarPrivacySettingsTests|PreferenceSyncSettingsTests|BrowserSettingsTests|AIWriterSectionMacSnapshotTests/(navigationPolish|desktopSizing|settingsNavigationPresentsSearchableTaskGroups)'
```

The phone cases run with `xcodebuild -scheme BrevMail` from `packages/BrevMail`,
the explicit simulator above, `-skipMacroValidation`, `-testLanguage en`,
`-testRegion en_US`, and `-parallel-testing-enabled NO`, selecting
`PhoneMailboxSnapshotTests` methods `mailboxes`, `twoAccountMailboxes`,
`favoritesEditor`, `accessibleFavorites`, and `settingsCategories`. Successful
final comparison runs exited normally. Initial missing-reference recording runs
reported their expected failures; a stalled recording runner was stopped only
after its test cases had finished.

The final desktop comparison exposed small system-symbol raster differences
(for example 583 of 2,688,000 pixels in Writing), with unchanged layout and text.
Inspected and refreshed only the eleven intentionally changed/new navigation
references, then reran to a passing exit. No comparison tolerance was relaxed.
Four untouched standalone folder snapshots retain their earlier known host-font
mismatch and were not re-recorded. The broader settings-surface suite and the
seven previously failing message-row comparisons are not claimed green.

## Unlocked desktop follow-up

The user unlocked the Mac and requested completion of the native checks later
on 2026-09-29. This follow-up used the dated mock app built from `2ec5e19b` plus
the Settings interaction and toolbar corrections included with this evidence.

Three reproducible native defects were fixed:

- Clicking Writing, pressing Tab to focus the sidebar, then Down left Writing
  selected. Handling the arrow key directly now selects Notifications; Up
  returns to Writing. The prior outer move-command handler did not receive
  this native-list interaction. The fix uses SwiftUI's
  [focused key-press handling](https://developer.apple.com/documentation/swiftui/view/onkeypress(keys:phases:action:)).
- Clicking the centre of a search-result row could miss its text hit regions.
  The result now has a full-width rectangular hit area. Repeating the same
  row click on Gravatar opens Privacy and scrolls to the control.

- Small/Compact sizing inherited into the split-view toolbar and squeezed single
  buttons into vertical pills. Sizing now wraps pane content before toolbars are
  attached. Native Small/Compact and Large/Spacious checks preserve circular
  controls; Compose, Search and sidebar hide/show actions passed. The main-window
  screenshots below were refreshed after this correction.

These were manual red/green checks against the real native first-responder and
hit-testing behavior; no synthetic test was added that merely repeats the
handler's implementation. Existing navigation and pixel coverage was rerun:
**40 tests in two suites passed, including eleven image comparisons**, with no
snapshot reference changes. The dated macOS build/launch, lint, format and diff
checks passed. The keyboard change is macOS-only; the shared search-result hit
area also applies to regular-width iPad Settings. No fresh iPad interaction was
performed in this follow-up. The subsequent
[iOS Release archive](../testflight-uiux-2026-09-29.md) built successfully; the
earlier iPhone evidence remains applicable to its separate compact navigation.

| Native scenario | Result and evidence |
| --- | --- |
| Writing subpages | Compose, Signature, Templates and AI Writer opened correctly; [Send safety remains above recipient history](macos-writing-native.png) |
| Keyboard category selection | Sidebar Tab focus, Down from Writing to Notifications, and Up back to Writing passed after the fix |
| Search to exact controls | [Gravatar → Privacy](macos-settings-search-native.png), [Browser → Mailbox View's Browser tab](macos-browser-native.png), and [iCloud → Sync & Storage / Preferences](macos-preference-sync-native.png) passed; no consent switches changed |
| Mailbox View tabs | Reading, Message List, [Folders](macos-folders-native.png), and Browser opened with their expected controls |
| About & Updates | About displayed version/build, licence and repository; [Updates displayed its controls](macos-updates-native.png). The dated test build correctly reports unavailable Sparkle configuration; no update check or installation was triggered |
| Compose sizing | [Small/Compact](macos-compose-small-native.png) and [Large/Spacious](macos-compose-large-native.png) rendered correctly in the same already-open compose window. Labels, subject, editor text and spacing updated without reopening it |
| Settings and main-window sizing | [Large Settings](macos-settings-large-native.png) kept category labels readable, including wrapped labels. [Large main window](macos-main-large-native.png) and [restored Small/Compact](macos-main-small-native.png) show the shared change |

The temporary recipient-free mock draft was closed without sending. Small text, Compact
density and the existing theme were restored; the main window remains open.
No daily-driver replacement or real message sending occurred. The lock-screen
blocker is resolved for this scoped Settings and sizing walkthrough.

## Limits and follow-ups

No physical device, VoiceOver audio, live-provider sending, import/export,
update installation or consent-changing integration test was performed. The
iPhone's existing shortcut choices and order were restored after interaction
checks. Desktop Favourites and a revised main-window sidebar are still proposed
polish, not part of the implemented phone Favourites grouping.

The earlier [full settings assessment](../settings-assessment-2026-09-29/README.md)
remains the record of deeper follow-ups: simplify certificate/source setup,
investigate the empty folder-scope selector, and reduce repeated explanatory copy.
Those are outside this navigation pass. No matching issue exists; PR #162 carries
the scope, verification and remaining checks. The user separately authorised an
internal TestFlight deployment. PR merge and issue closure remain unauthorised.

Internal TestFlight delivery is tracked in the [deployment record](../testflight-uiux-2026-09-29.md).
