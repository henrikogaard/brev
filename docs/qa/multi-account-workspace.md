# Multi-account workspace regression checks

Review baseline: `0902c93e`. Implementation branch: `fix/multi-account-workspace`.
Use a dated Brev Test app with mock mailboxes first. Do not replace Brev.app.

| Scenario | Required result | Automated coverage |
| --- | --- | --- |
| Open a unified/smart/saved-search row | Collection remains selected; reader uses the owning source | MailNavigationStateTests |
| Old page finishes after scope changes | No old items, cursor, selection, or loading state is published | MailListLoadOwnershipTests, MailRootResponseSourceTests |
| One account succeeds and another fails in a bulk action | Successful changes remain; only failed rows return | MessageListMutationRollbackTests |
| Profile account is unavailable during load/save | Membership and active profile survive; no fallback to unrelated mail | MailProfileTests |
| Same raw message ID in two accounts | Independent pins; no pruning on profile load | MailPinnedMessagesTests, unified presentation tests |
| Another account finishes restoration | Existing workspace and reader remain mounted; subscriptions update | Native shell/rendered check |
| Cold Gmail page | Missing-message requests overlap with maximum concurrency four; attachment metadata and order retained | GmailAPIBackendTests |
| Gmail listing fails with a cached folder | Cached rows remain readable | GmailAPIBackendTests |
| One source delays its response | Healthy source publishes before the delayed response | MailConcurrentWorkTests |
| Search is cancelled during debounce | No backend work starts for that query | MailListLoadOwnershipTests |
| Refresh while cached mail is visible | Cached reading remains available | MailRootWorkBlockPolicyTests |

## Verification record

- BrevMail: 1,503 tests plus the six ContactsAccessPolicy tests passed in the
  separate-process arrangement already used by CI.
- BrevBackend: 1,010 tests passed. BrevGmail: 99 tests passed. BrevSettings:
  314 tests passed.
- SwiftFormat, strict SwiftLint, repository self-tests, privacy audit, and
  whitespace checks passed. The compact width check now validates the new
  320-point message list minimum within the existing 960-point window budget.
- Native macOS test builds and launch verification passed with the dated test
  identity. iOS Simulator builds passed; device QA is separate.
- Native mock UI: All Inboxes showed 38 messages across two mailboxes; opening
  the work conversation retained the unified list. A Work-only profile showed
  nine messages, persisted across relaunch, and left both the profile picker
  and its mailbox available. Saving Profiles returned to the main window with
  no Cancel/Done toolbar leakage. The reader identified the work mailbox.
- Updated macOS light sidebar snapshots and dark 400/760-point conversation
  snapshots were rendered, inspected, and compared; a profile-manager snapshot
  covers the window-local action buttons.
- Live Gmail/IMAP account acceptance remains separate under issue #2. No live
  mailbox mutations, send actions, release build, or daily-driver replacement
  were part of this verification.

The request tests exercise cancellation, superseding publication, and a source
completion barrier. They do not establish live-provider latency or frame-time
budgets. Cold Gmail cache misses still fetch full MIME data because metadata-only
responses omit attachment structure; those fetches are limited to four at once.
Cached reads use indexed label pages and coalesced background reconciliation.

Legacy pins cannot be assigned safely because their stored value contains no
account identity. The original records remain intact, and the UI explains that
messages must be pinned again. The new 500-pin global limit reports an error
rather than pruning another profile's pins.


## Settings consistency follow-up

The Settings window receives explicit mailbox identity and cached folders from
Mail. Folder Sync has a visible mailbox selector. Source changes reset the
folder editor; same-source cache updates refresh it without a provider-current
mailbox fallback. Retention overrides use SourceFolderID, including an explicit
Default choice that supersedes legacy folder-only preferences for that source.

Regression coverage includes duplicate INBOX identifiers across accounts and
mailboxes, retention persistence, retention sweep targets, search control names
and destinations, and malformed folder hierarchy handling. Snapshot coverage
includes light/dark Accounts, Appearance, Mailbox View, and wide/narrow Folder
Sync. The compact table uses native labeled controls and a folder filter.

Native acceptance sequence after unlocking the Mac:

1. Select Private in Mail, open Folder Sync, and verify Private's identity and
   folders. Change to Work in Mail, reopen Settings, and verify Work's folders.
2. Change the Settings mailbox selector and confirm both identity and folder
   contents change without changing the account's default.
3. Search for font, text size, remote images, and fetch schedule. Open a result
   and confirm the named control is visible in the appropriate pane.
4. Filter nested folders, edit retention/visibility in the mock account, switch
   mailboxes, and verify no preference crosses to an identically named folder.
5. Navigate Settings and its search results with the keyboard; check VoiceOver
   announces each folder's retention and visibility controls unambiguously.

The Mac locked during native verification. Accounts/navigation inspection and
rendered snapshots were completed; the remaining sequence above is explicitly
pending, not inferred from package tests.


## Divider and Settings group verification

The dated mock app reproduced the bright inspector gutter. The revised app
painted both the resize target and split-container gaps with themed surfaces.
Native captures show no bright vertical bar. Repeated left/right drags moved
the sidebar to the requested positions; unit tests cover immediate reversal
at width limits and final-sample persistence. No frame-rate claim is made.

Accounts was verified under App, and Advanced/Extensions were verified with
matching headers and unindented rows. The Mac locked again before the older
search-scroll and complete keyboard/VoiceOver acceptance sequence resumed.
Those remaining checks are still pending; the current reported visual defects
were verified in the running app.


## Profile-filtered stacked mailbox groups

Profiles choose the visible mailbox set; they do not act as an inbox or alter
connections. Mailboxes have compact disclosure headers and separate folder
trees. Local expansion state survives profile changes/relaunches. Duplicate
folder IDs across sources have distinct rendered identities.

Automated coverage includes two expanded mailboxes with identical Inbox IDs,
selection in only one tree, a profile showing only one source, collapsed groups,
and restoration including an intentionally empty set. Light/dark screenshots
cover the final layout.

Native acceptance after unlock:

1. Expand Private and Work together. Select either Inbox; the other group must
   remain expanded and the selected folder must belong to the correct source.
2. Collapse Work, select All Inboxes, and open a Work message. Work must remain
   collapsed while the aggregate remains selected.
3. Change the active profile, then return. Its mailbox set must match the saved
   membership and prior disclosure choices must return.
4. Relaunch the dated mock app and confirm the disclosure choices restore.
5. Open the profile menu by keyboard and reach Manage Profiles.

The earlier single-menu trial passed native navigation checks, but those are
not evidence for the final stacked layout. The Mac locked before this final
native sequence; rendered and behavior tests are tracked separately.


### Thread selection and Smart Views follow-up

- Reproduction captured in the native test app: select Private Inbox, enable
  Flagged, expand Kitchen drawings, select Kari's unflagged reply. The old
  reader became empty. The regression test now retains the reply and thread
  context across header reconciliation.
- Verify the same flow after installing this revision, including direct
  selection of each inline child and refresh while it remains selected.
- Open Smart Views from the sidebar control and Settings > Smart Views. Create
  a named view with any matching, a sender rule and subject rule; add a negative
  comparison, a date, a mailbox and a source-owned folder. Verify Save validation
  rejects blank criteria and that Cancel leaves the stored view unchanged.
- Verify an archived cached message matches a folder rule; exclude/include Sent
  and Trash; switch profiles and confirm only their mailbox sources are searched.
- Hide a built-in view and a custom view, reorder both, close/reopen Settings,
  and restore visibility. Hide the whole section and restore it from Settings.
- Final native follow-up was interrupted by the Mac locking after installation;
  package tests and light/dark hosted-view snapshots remain the automated evidence.

- Backend follow-up: automated tests now cover 120 cached IMAP headers beyond
  the normal 50-result search cap, Gmail secondary labels, duplicate rows,
  combined/negative folder membership, and Sent/Trash labels outside primary folders.


### Issue #28 Undo acceptance

- Compare toolbar, context-menu, swipe and bulk read/flag/archive/move/delete.
  Verify the latest action remains available in Edit > Undo after the toast
  disappears; Command-Z in search/compose text must use native text history.
- Reverse an IMAP move and verify the restored message uses the new server UID;
  repeat across folder/profile navigation and a mailbox replacement. A changed
  UIDVALIDITY must fail safely without moving a different message.
- Verify Gmail move Undo preserves existing custom labels and subsequent
  unrelated flag updates. Retry a compound Undo after a partial failure and
  confirm already restored batches are not moved again.
- Remove/replace an account while a reversal is pending; no stale error or
  action should reappear in the replacement session.
- Native interaction and live-account checks remain pending. Unit/contract and
  snapshot results do not establish those acceptance outcomes.

### Issue #28 native Undo check, 2026-09-05

Dated mock app from `feature/mail-client-parity`, launched with the guarded
build script and inspected by CUA using its exact worktree bundle path:

| Check | Observed result |
| --- | --- |
| Toolbar Archive | Selected mock bill left Inbox; 29 messages became 28 |
| Native Undo after toast expiry | Edit menu retained Undo Mail Action; message returned and count became 29 |
| Compose text Undo / Redo | Entered text cleared with Cmd-Z and returned with Shift-Cmd-Z |
| Mail action after editor closes | Row flag remained during text editing and reverted with Cmd-Z after closing the empty composer |

This verifies native routing and successful mock reversal. It does not prove
live provider failures, offline replay, complete selection restoration, or
multi-account/performance acceptance.

### Issue #28 restored reader, 2026-09-05

The selection-restoration mock build passed startup verification. CUA selected
the mock bill, archived it through the toolbar, and invoked Cmd-Z. Inbox returned
from 28 to 29 messages and the reader reopened that same bill, with its matching
sender context. Automated tests cover reassigned IMAP IDs, incomplete first-page
refreshes, source collisions, All Inboxes, and navigation during reversal.
Live-provider and offline queued-action acceptance remain separate.
