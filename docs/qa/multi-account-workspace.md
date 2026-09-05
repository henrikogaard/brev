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
