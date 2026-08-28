# Worklog

## 2026-08-28 — Codex — Initial public repository

### Goal

Publish Brev from a clean, independently versioned source baseline.

### Summary

- Prepared the final private-repository source as a single public baseline.
- Reset the app version to `0.1.0`.
- Kept current architecture decisions and renumbered their ADRs.
- Excluded superseded decisions, old branches, release artifacts, and historical
  QA records from the public baseline.
- Preserved the unresolved iPhone accessibility and live-provider acceptance
  checks as public follow-up work.

### Verification

- `gitleaks`: no findings in the public snapshot.
- `scripts/test-public-source-markers.sh`: passed.
- `scripts/privacy-audit.sh`: passed.
- `scripts/format.sh` and `scripts/lint.sh`: passed.
- ADR numbering, references, labels, and local Markdown links: passed.
- Swift package tests: BrevAI 52, BrevBackend 1,009, BrevCalendar 60,
  BrevMail 1,489.
- Generated-project macOS and iOS Simulator builds: passed with existing Swift
  concurrency warnings under Xcode 27.
- iPhone accessibility labels remain a runtime check because no simulator was
  booted during the cutover.
- Remaining live Gmail and IMAP account lifecycle rows require real accounts
  and devices; they remain public follow-up work.
