# Folder Sync scope fix — 2026-09-30

Scope: resolve the unresolved Folder Sync observation from the
[settings assessment](../settings-assessment-2026-09-29/README.md) (screen 15:
"Folder Sync initially displayed an empty mailbox selector despite an active
mail window"). Branch `fix/settings-folder-sync-scope`, based on `origin/main`
at `d96fd4d9`. All mail and addresses in the screenshots are mock fixtures.

## Root cause

With the mailbox list ("Postkasser") visible, Mail's `navigation.selectedSourceID`
is nil — unified-inbox selection, reader reconciliation and mailbox switches all
clear it — while Mail's own UI falls back to
`preferredDefaultSection(in: visibleSourceSections)`. Settings received the raw
nil and published an empty scope, so Folder Sync rendered "Velg postkasse" with
no folders and every scoped control disabled. The fix resolves the same
effective source Mail displays (`selectedSourceID ?? preferredDefaultSection(…)?.id`)
before publishing the settings scope.

## Acceptance evidence

| Item | Acceptance criterion | Evidence |
| --- | --- | --- |
| Reopen from mailbox list | Folder Sync opened from "Postkasser" shows the active mailbox and its folders | Native before/after: [before](before-empty-selector.png) shows "Velg postkasse" and "Velg en postkasse over for å konfigurere mappene."; [after](after-reopen-resolved.png) resolves `Henrik Øgård (private)` with its ten folders |
| Multiple accounts | Switching the scope picker shows the selected account's folders | [after-account-switch-work.png](after-account-switch-work.png) lists the work folders (Clients, Harbour Logistics, Meridian Media, Northwind Energy); [entry](entry-mailbox-list.png) shows the two-account mailbox list used for the reopen |
| Saved choices stay per account | A choice made for one account is retained when returning to it | [after-private-choice-retained.png](after-private-choice-retained.png): private "Vis Archive i sidelinjen" stays off after visiting work, where the same control stayed on |
| Saved choices persist | Choices survive closing and reopening Settings | [after-settings-reopen-persisted.png](after-settings-reopen-persisted.png): private Archive still hidden after "Ferdig" → reopen → Folder Sync |
| Zero accounts | No mailboxes yields a clear empty state, not a broken control | Source-verified: policy returns nil, Settings shows "Open a mailbox in Mail to choose its settings." / "Choose a mailbox above to configure its folders."; covered by `staysEmptyWithoutAccounts` |
| Regression test | Focused policy test fails before the fix and passes after | `swift test --package-path packages/BrevMail --filter MailRootSettingsScopePolicyTests` — red with the old call site, 3/3 green with the fix |

## Reproduction

- Path A (original report): open a mailbox → Settings → Sync & Storage →
  Folder Sync.
- Path B (reproduced defect): back to "Postkasser" (mailbox list) → gear →
  Sync & Storage → Folder Sync. Before the fix this showed "Velg postkasse"
  with no folders; now it resolves the mailbox Mail is effectively showing.
- Account switch and persistence: open the scope picker (press and hold the
  scope row) → choose the other account → toggle "Vis Archive i sidelinjen" →
  switch account and back → close Settings ("Ferdig") → reopen → Folder Sync.

## Environment and checks

- iPhone 17 Pro simulator "Brev QA iPhone 17 Pro", UDID
  `DF87BEA6-DEC5-49C9-A776-14E5996E8CAA`, iOS 27.0, launched with
  `BREV_USE_MOCK=1` (mock fixtures; no live account was touched). The
  `serve-sim` mirror rendered the live frame; interactions were completed via
  the runtime accessibility targets.
- Focused: `MailRootSettingsScopePolicyTests` 3/3. `scripts/lint.sh` and
  `scripts/format.sh` clean.
- Full `packages/BrevMail` suite: 1,927 tests / 54 pre-existing pixel-snapshot
  issues on this host (macOS 27.0, 26A428). A control run with the change
  reverted reproduced the same 54; CI excludes those suites via the
  `snapshot-macos` job skip list. They are not caused by this change.

## Limits

- The original observation was macOS. This pass reproduced and verified the
  defect and fix on the iOS simulator; a macOS native re-check remains open
  (desktop QA was unavailable this session).
- The zero-account state is source- and test-verified only: the mock backend
  always provides accounts, so it was not exercised natively.
- No physical-device pass; that gap stays with the P0 item in the follow-up
  handoff.
