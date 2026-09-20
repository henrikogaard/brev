# iOS snapshot baseline policy

The required iOS snapshot lane uses `scripts/ios-simulator-destination.sh`
with `BREV_IOS_RUNTIME=27.0` and `BREV_IOS_DEVICE="iPhone 17 Pro"`. CI fixes
the test language and region to `en` / `en_US` so host locale settings cannot
change dates, number formatting, or localized controls. The current toolchain
is Xcode 27.0 (`27A5237l`) and the iOS 27.0 simulator runtime.

References are not refreshed merely because pixels differ. A refresh requires
visual inspection showing platform rendering drift only, with no changed text,
ordering, spacing, or control state. Use `RECORD_SNAPSHOTS=YES` only for that
reviewed refresh and commit the PNG with this metadata updated.

## Required iOS 27 lane

| Test | Reference | Verification |
| --- | --- | --- |
| `BrevMailRootViewSnapshotTests/rootViewWideLayout()` | `BrevMailRootViewSnapshotTests/rootViewWideLayout.root-wide.png` | Passed unchanged on iOS 27.0; no semantic or layout drift. |
| `MessageDetailViewSnapshotTests/bodyLoadErrorState()` | `MessageDetailViewSnapshotTests/bodyLoadErrorState.body-load-error.png` | Re-recorded on iOS 27.0 after visual review found only platform rasterization/antialiasing drift; text, geometry, and states match. |
| `BrevMailSnapshotTests/threadMessageCardCollapsedRenders()` | `BrevMailSnapshotTests/threadMessageCardCollapsedRenders.collapsed-brev-paper.png` | Passed on iOS 27.0 with the static body target; fixture renders Sigrid Moen. |
| `BrevMailSnapshotTests/threadConversationViewRendersDeterministically()` | `BrevMailSnapshotTests/threadConversationViewRendersDeterministically.thread-conversation-deterministic-brev-paper.png` | Passed on iOS 27.0 with the static body target; fixture renders the Hemsedal thread. |
| `BrevMailSnapshotTests/composeViewRendersSignaturePicker()` | `BrevMailSnapshotTests/composeViewRendersSignaturePicker.signature-picker.png` | Re-recorded after visual review; the iPhone fixture shows the Work signature picker and compose chrome. |
| `ComposeViewSnapshotTests/emptyCompose()` | `ComposeViewSnapshotTests/emptyCompose.empty-compose.png` | Re-recorded after visual review; the iPhone fixture shows the empty fields, sender, and toolbar. |
| `ComposeViewSnapshotTests/replyCompose()` | `ComposeViewSnapshotTests/replyCompose.reply-compose.png` | Re-recorded after visual review; the iPhone fixture shows the recipient chip, reply subject, sender, and quoted body. |
| `MessageDetailViewSnapshotTests/noSelectionPlaceholder()` | `MessageDetailViewSnapshotTests/noSelectionPlaceholder.no-selection.png` | Re-recorded after visual review; the iPhone fixture shows the envelope and no-selection copy. |
| `MessageDetailViewSnapshotTests/headerPresentRendersSubjectAndSender()` | `MessageDetailViewSnapshotTests/headerPresentRendersSubjectAndSender.header-present.png` | Re-recorded after visual review; the iPhone fixture shows subject, sender, recipients, date, and snippet. |

The required lane intentionally stays small and deterministic. It is the
blocking signal for stable UIKit snapshots, not a claim that every snapshot
suite is currently baseline-complete.

The seven formerly WebKit-backed cases now use the injected
`HTMLBodyRenderTarget.staticSnapshot` target for their UIKit chrome checks in
the required iOS lane. `HTMLBodyWebViewStore` creates WebKit lazily, so plain,
collapsed, and no-selection states do not start a WebContent process. The HTML
document wrapper, remote-content load plan, and blocker rule remain covered by
semantic tests.

| Probe | Disposition |
| --- | --- |
| `BrevMailSnapshotTests/threadMessageCardCollapsedRenders()` | Refreshed after visual review; current fixture renders Sigrid Moen. |
| `BrevMailSnapshotTests/threadConversationViewRendersDeterministically()` | Refreshed after visual review; current fixture renders the Hemsedal thread. |
All seven references were visually inspected and are now part of the required
lane; the five previously pending references are no longer deferred debt.

The macOS snapshot lane also runs the stable AppKit suites that are compiled
out of an iOS destination: `FolderSidebarSnapshotTests`,
`MailRootStatusRailSnapshotTests`, `MessageListRowSnapshotTests`,
`ThreadInlineChildRowSnapshotTests`, and all nine `MailContextColumnSnapshotTests`
cases. This prevents an iOS job from reporting success after selecting only
macOS tests (zero executed tests).

## Explicitly deferred suites

These tests remain in the source tree and are probed separately or require a
semantic baseline decision. They must not be silently added to (or removed
from) the required lane.

| Suite | Reason it is deferred | Next action |
| --- | --- | --- |
| `BrevMailSnapshotTests` | Remaining folder/theme cases still have fixture text/order differences from older references (English folder names versus the older Norwegian reference). | Resolve the intended fixture semantics before refreshing the remaining cases. |
| `BrevMailViewSnapshotTests` | UIKit tests have no committed references; first-run recording is not platform drift evidence. | Review and record deterministic iOS 27 references as a dedicated baseline change. |
| `BrevMailRootViewSnapshotTests/rootViewCompactLayout()` | Current compact fixture/layout differs from the committed reference. | Reconcile the intended compact surface before any re-record. |
| `MessageNoteSheetSnapshotTests` | Existing references show semantic/layout differences on the current branch. | Review product intent before recording. |
| `AllAttachmentsViewSnapshotTests`, `ImportProgressBannerSnapshotTests`, `SavedSearchEditorViewSnapshotTests`, `MessageRawSourceSheetSnapshotTests` | No committed UIKit references. | Add reviewed references in separate focused changes. |

Run `scripts/check-ios-snapshot-baselines.sh` before changing the lane. It
fails if required references disappear or a deferred suite is no longer
documented, preventing a failing suite from being dropped just to make CI
green.

## PR #47 phone layout follow-up — 2026-09-19

`PhoneMailboxSnapshotTests` adds four iOS 27 references (inbox/search and folder
hierarchy, light and dark). These are intentional layout baselines: the search
control is bounded to 44 points, phone rows retain previews and wrap subjects,
and folder disclosure no longer consumes an empty leading column. The references
were visually inspected before comparison. The required iOS lane now selects
this suite. Older deferred snapshot debt remains separate.

The app-hosted `MailboxLayoutTests` reproduces the unbounded UIKit field at
319 points before the fix, then verifies a 44–52 point field under a full-screen
height proposal. This behavioral sizing test does not depend on pixels.

The same suite also covers a 660pt regular-width compose scene with a signature.
The reference was inspected on iPad Pro 13-inch / iOS 27 after moving secondary
iOS compose tools into overflow; Close, Send and More remain visible.

The narrow compose reference uses the iPhone-hosted regular-width fixture to
match the required CI destination. Comparing it with the iPad-hosted render
showed text antialiasing differences only; control positions, labels and state
were unchanged. The iPad comparison passed against its original capture.

## Compact settings rows — 2026-09-20

`CompactSettingsRowSnapshotTests` covers template and local-rule rows at 216pt
and 271pt content widths, representing padded 320–375pt phone settings. The
before render visibly lost the text and trailing actions. The reviewed new
references put content above Pin/Enable, Edit and a 44pt overflow menu; reorder
and Delete remain available in that menu. These two references join the iOS 27
CI lane. An existing iOS-only snapshot fixture enum needed internal visibility
for the Settings test target to compile; no unrelated references were refreshed.

The same suite now includes full Signature sections at 320pt and 375pt. The
old row collapsed the name field; the reviewed references keep the field on
its own line and put Enabled plus a 44pt action menu below it. Both sizes were
visually inspected before comparison. All three newly enlarged settings action
rows (templates, rules, signatures) now have compact coverage.

All seven `PhoneMailboxSnapshotTests` references are required by
`scripts/check-ios-snapshot-baselines.sh`, including on CI hosts that cannot
run the iOS 27 pixel comparisons. Missing or empty phone references fail the
presence gate.

The detached-reader action bar (660-point regular-width scene) and thread-summary
Retry panel have iOS 27 references covering their 44-point touch targets.
