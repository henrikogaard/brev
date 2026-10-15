# Calendar Drive attachments acceptance evidence — v3 — 2026-10-15

Issue: [#14](https://github.com/henrikogaard/brev/issues/14). Branch:
`fix/drive-acceptance-gaps`, targeting `main`. This version adds a
user-initiated copy/save action for supported Drive-backed calendar event
attachments. Version 2 is preserved as a separate report.

## Scope

- The event still stores and opens its provider-neutral Drive URL. Saving
  requires explicit user intent, uses the event's source-linked Google
  account, authorizes the exact file through Google Picker, reads
  authoritative Drive metadata, then downloads or explicitly exports the
  file and uploads a copy to a selected folder.
- Read-only event sources qualify when their linked account is eligible.
  The flow does not call a calendar writer, rewrite the event link, add a
  file-ID persistence field, add OAuth scopes, or fetch arbitrary URLs.
- Generic external and CalDAV attachment links are unsupported; only
  allowlisted Drive and Workspace links are handled.
- The common save flow validates the folder, presents same-name conflict
  choices, reports progress, protects the source file from replacement,
  and invalidates late work when canceled or dismissed.
- This is synthetic package verification only. No app was launched and no
  live Google account/provider operation was performed.
- The targeted save-action snapshots verify rendered states with local test
  inputs only; they are structural snapshot evidence, not live UI/runtime or
  provider evidence.

## Verification

| Check | Result |
| --- | --- |
| Original implementation TDD red run | Expected compile failure before implementation: the two model types did not yet exist; log at `/Users/devin/Library/Logs/brev-drive-calendar-save-red-20261015.log` |
| Correction regression run | The shared conflict orchestration regression was run red before its fix. The two Picker-failure retry tests were also run red before the explicit retry fix: 10 assertion failures showed the event flow remained in `.picking` with a new token and retained payload, while shared save retained its Picker token. The first runnable correction suite also exposed upload errors leaving the shared save flow in `.uploading`; corrected. Other correction regressions were not each run against the pre-correction tree. |
| `swift test --package-path packages/BrevMail --filter 'GoogleDrivePickerFailureRetry\|GoogleDriveEventSave\|GoogleDriveSave'` | Pass — 30 tests in 3 suites in the earlier focused save/retry run; the final broad GoogleDrive gate below reran these suites |
| `swift test --package-path packages/BrevMail --filter CalendarDriveSaveEligibility` | Pass — 7 tests in 1 suite, including same-ID event/source/collection state replacement |
| `swift test --package-path packages/BrevMail --filter GoogleDrive` | Pass — 47 tests in 6 suites on the final correction worktree |
| `swift test --package-path packages/BrevBackend --filter GoogleDrive` | Pass — 13 tests in 2 suites in the earlier correction run; not rerun because BrevBackend was unchanged |
| `swift test --package-path packages/BrevMail --filter 'CalendarBrowsingSnapshotTests/eventDetailDriveSave'` | Pass — 2 tests in 1 suite, covering all 4 read-only/unavailable light/dark structural snapshot cases |
| Existing full snapshot findings | Four existing agenda/detail references mismatched (`agenda-light/dark`, `detail-light/dark`); cause unverified. Unrelated baselines were preserved. |
| `scripts/format.sh` | Pass — 0/1294 files formatted; 175 skipped |
| `scripts/lint.sh` | Pass — SwiftFormat lint, SwiftLint strict, coverage self-test and ADR check |
| `git diff --check` | Pass — final local diff |

Four read-only/unavailable light/dark images are recorded without
refreshing unrelated baselines under
`packages/BrevMail/Tests/BrevMailTests/__Snapshots__/CalendarBrowsingSnapshotTests/`.
They do not demonstrate behavior in a running app or against a live provider.

## Not verified

Authenticated Picker behavior, consent in a running app, actual file access,
Workspace export against Google, uploads, account switching, platform UI
accessibility, and remote outcomes remain unverified. No CI or runtime/UI/live
provider testing was performed in this code-and-push handoff; those require the
parent's separate QA handoff.

README sweep: setup, architecture, product layout, and supported provider
boundaries did not otherwise change. `PRIVACY.md`, ADR-0006, ADR-0072,
`CHANGELOG.md`, and `WORKLOG.md` record the new explicitly opted-in behavior.
