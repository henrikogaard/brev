# Worklog

## 2026-08-28 — Claude — Mail reader regressions triage (diagnosis only)

### Goal

Diagnose Henrik's two reported daily-driver regressions after today's
`Brev.app` 0.1.0 rebuild: (1) opened mails show only the list snippet, and
(2) the mail list/reader no longer hides scrolled content behind the
translucent overlay.

### Findings

- Today's `Brev.app` (installed 15:11) is the first daily-driver rebuild
  since 2026-08-16, so the real regression window is Aug 16 → Aug 28 of
  legacy `main`, not just today's five merges. Legacy history is reachable
  with `git fetch https://github.com/henrikogaard/brev-legacy.git main`.
- The public snapshot is functionally identical to legacy `main` (only
  version numbers, comment scrubbing, removed deprecated AI aliases), so the
  publish itself did not drop reader/overlay code.
- Symptom 1 is consistent with live IMAP body loads failing or exceeding the
  15 s `bodyWithReaderTimeout`: `MessageDetailView.loadMessage` seeds the
  snippet, and on failure with a snippet present it clears `errorMessage`,
  so the failure is silent. Mock-mode rendering of current `main` is correct
  (verified against the 2026-08-27 test build pixel-for-pixel), pointing at
  the Aug 25–26 IMAP/perf hot-path changes rather than the view layer.
- Symptom 2 suspect: `perf(macos): smooth split-view resizing` (72b21475)
  and `fix(macos): deduplicate split-view repairs` (ffd94c56) reduced the
  `SplitViewTransparencyProbe` repair passes; a missed late chrome rebuild
  leaves split-view columns opaque. Timing-dependent, so a small mock window
  does not reproduce it. The scroll-edge-blur CA internals still exist on
  this macOS (probe: CABackdropLayer + gaussianBlur present), and WKWebView
  height measurement plus content-rule compile work in isolation.
- Repo fix applied: removed the stale generated symlink
  `Brev.xcworkspace/xcshareddata/swiftpm/Package.resolved` that pointed at
  the deleted `~/Dev/Repos/.staging/brev-public-20260828/` staging dir; it
  broke every local `xcodebuild` ("Package.resolved doesn't exist"). After
  `tuist install` + `tuist generate`, `script/build_and_run.sh install-run
  --mock` works again.

### Root cause found (symptom 1)

A focused sweep of legacy main c13a66a6..a57b64a3 found the definite bug:
`withResponseTimeout`'s cancellation handler disconnects the shared IMAP
transport without clearing `authenticatedSessionIdentity`
(IMAPSessionClient). Every message open cancels background refresh reads
(`beginForegroundIMAPRead` → `cancelBackgroundRefreshTasks`), so the next
body fetch skipped login and ran on a dead socket, timed out at 15 s, and
the reader silently kept the snippet (the failure branch cleared
`errorMessage`). Mock backends never construct a session client, which is
why mock runs and the test suite never showed it.

### Fixes (three PR branches)

- `fix/imap-cancelled-read-teardown`: command-read cancellation teardown
  now goes through `resetAuthenticatedSession()` so the next operation
  reconnects and logs in again; the structured-body fallback logs the
  error it previously swallowed (category `IMAPBodyFetch`). New regression
  test: `cancelledCommandReadInvalidatesReusedSession` (red at 127 s of
  timeouts before the fix, green at 0.01 s after).
- `fix/reader-silent-body-load-failure`: the reader shows a "Showing a
  preview only" warning banner with retry instead of silently keeping the
  snippet; failure routing is a tested policy
  (`MessageDetailPresentation.bodyLoadFailureOutcome`), and the error is
  logged (category `MessageBodyLoad`).
- `fix/macos-translucency-resilience` (symptom 2, mechanism-hardening —
  root cause not reproduced headlessly): the split-view transparency
  settled pass verifies its own result and re-arms while it keeps finding
  restored opaque fills; the scroll-edge blur retries its backdrop
  reduction before failing closed and logs when it disables itself
  (category `ScrollEdgeBlur`).

### Verification

- BrevBackend: full suite, 1,010 tests passed (incl. the new regression
  test). BrevMail: `MessageDetailPresentation`/`StateResetPolicy` suites
  (28) and `MailScrollEdgeBlurRetryState` (2) passed; full suite run
  recorded per branch before push. BrevDesign:
  `SplitViewTransparencyPassState` suite (5) passed.
- `scripts/format.sh` no changes; `scripts/lint.sh` strict + ADR gate OK.
- Mock test builds of public `main` and legacy `c6314bf2` both render the
  demo thread card correctly; the 2026-08-27 dated test build matches.

### Handoff

- `/Applications/Brev Test (2026-08-28).app` was last installed from legacy
  `c6314bf2` during bisection; rebuild from `main` before reusing it.
- Symptom 2's exact live trigger remains unconfirmed (background UI driving
  cannot scroll the app; live-window capture is blocked); the new
  `ScrollEdgeBlur` log will name the fail-closed reason if it recurs.
- Deferred IMAP follow-ups: cancellable `acquireSessionOperation`
  (cancelled waiters park until the session frees) and bounded OAuth
  refresh coordination (`OAuthRefreshCoordinator.run` has no deadline).
- Daily-driver rebuild from merged main needs Henrik's explicit
  release-main request.

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

## 2026-08-28 — Codex — Public runner CI repair

### Goal

Make the first public GitHub Actions matrix match the repository's documented
platform and test-runtime boundaries.

### Summary

- Made the release checkout self-test accept clean current `origin/main` while
  preserving rejection for dirty, stale, and non-main checkouts.
- Serialized PKCS#12 fixture suites so hosted runners do not race duplicate
  identity imports.
- Deferred macOS 26+ Settings pixel baselines on macOS 15 runners while keeping
  all behavior tests active.
- Made the BrevDesign job tolerate only the known post-pass AppKit signal 11;
  assertion failures still fail the job.

### Verification

- `scripts/test.sh --self-tests-only`: passed.
- BrevCrypto: 10 tests passed.
- KeychainSMIMEResolver: 5 tests passed.
- BrevSettings hosted-runner slice: 304 behavior tests passed; the 10 deferred
  visual tests passed on a compatible macOS 27 host.
- Preference-sync coalescing stress loop: 20/20 focused runs passed with a
  locked counter and deadline-based observation.
- BrevMail hosted-runner split: the main behavior suite and all six
  ContactsAccessPolicy tests pass in separate processes, eliminating global
  demo-gate state leakage without dropping coverage.
- BrevDesign CI suites: 35 tests passed.
