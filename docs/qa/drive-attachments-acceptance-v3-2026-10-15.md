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
- The common save flow validates the folder, presents same-name conflict
  choices, reports progress, protects the source file from replacement,
  and invalidates late work when canceled or dismissed.
- This is synthetic package verification only. No app was launched and no
  live Google account/provider operation was performed.

## Verification

| Check | Result |
| --- | --- |
| TDD red run | Expected compile failure before implementation: the two model types did not yet exist; log at `/Users/devin/Library/Logs/brev-drive-calendar-save-red-20261015.log` |
| `swift test --package-path packages/BrevMail --filter 'GoogleDriveEventSave\|GoogleDriveSave'` | Pass — 15 tests in 2 suites |
| `swift test --package-path packages/BrevMail --filter GoogleDrive` | Pass — 31 tests in 5 suites |
| `swift test --package-path packages/BrevBackend --filter GoogleDrive` | Pass — 12 tests in 2 suites (also rerun after formatting) |
| `swift test --package-path packages/BrevMail --filter CalendarBrowsingSnapshotTests` | 4 new save-action snapshots pass; 4 pre-existing agenda/detail baselines mismatch on this host (`agenda-light/dark`, `detail-light/dark`) and were preserved |
| `scripts/format.sh` | Pass — 4/1290 files formatted; 175 skipped |
| `scripts/lint.sh` | Pass — SwiftFormat lint, SwiftLint strict, coverage self-test and ADR check |
| `git diff --check` | Pass |

Four new read-only/unavailable light/dark images were recorded without
refreshing unrelated baselines under
`packages/BrevMail/Tests/BrevMailTests/__Snapshots__/CalendarBrowsingSnapshotTests/`.

## Not verified

Authenticated Picker behavior, consent in a running app, actual file access,
Workspace export against Google, uploads, account switching, platform UI
accessibility, and remote outcomes remain unverified. Runtime/UI/live provider
testing was explicitly on hold for this implementation.

README sweep: setup, architecture, product layout, and supported provider
boundaries did not otherwise change. `PRIVACY.md`, ADR-0006, ADR-0072,
`CHANGELOG.md`, and `WORKLOG.md` record the new explicitly opted-in behavior.
