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
