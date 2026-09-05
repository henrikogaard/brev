# Worklog

## 2026-08-28 — Claude — Scroll-edge blur anchored to the list viewport

### Goal

Henrik confirmed rows still hard-cut at the top of the message list even
though the band logged "active" in the release app.

### Root cause and fix

The band was mounted at the pane top, which matched the list's clip edge
only when nothing sat above the list. The native Gmail account renders
the inbox category chips bar above the list, pushing the scroll viewport
down; rows clipped at the chips' bottom edge while the band floated in
the toolbar zone. PR #22 mounts the band on the list content itself —
below any bars when present, extending into the toolbar safe area when
absent (previous look preserved for accounts without bars), and removes
the pane-level mount for the list pane.

Follow-ups in the same round: #23 (SwiftFormat cleanliness on main) and
#24 — the release compiler requires explicit `self` inside the OSLog
autoclosure while SwiftFormat strips it; the band log now hoists the
width into a local. Lesson: never reference instance members directly
inside OSLog message interpolations.

### Verification

Full BrevMail suite 1,493 passed; `swift build -c release` for BrevMail
compiles; format + strict lint pass; daily driver rebuilt from clean
origin/main and relaunched live — unified log shows all bands active,
including the list band on its new anchor. Visual fade confirmation is
with Henrik.

## 2026-08-28 — Claude — Gmail empty-body root cause and band diagnostics

### Goal

Henrik reported the reader still showed only the snippet after PRs 16–18
merged and the daily driver was rebuilt, and the translucent overlay was
still missing.

### Findings

- The rebuilt release `Brev.app` is sandboxed and runs the live account on
  the native Gmail API adapter (`gmail.sqlite` open in the process), not
  the IMAP path — so PR #16 fixed a real bug in a backend this account no
  longer uses. The previous daily driver predated the adapter (merged
  Aug 25); today's rebuild switched the account's backend.
- Root cause of the snippet symptom on Gmail: `GmailSyncReconciler` stores
  `format=metadata` messages (payload = headers only), and
  `GmailAPIBackend.body(for:)` treated any non-nil payload as complete,
  returning an empty `MessageBody` without error — so the reader's snippet
  fallback rendered and no failure banner fired. Fixed in PR #19 with a
  red-first regression test (`upgradesMetadataPayloadMessage`); full
  BrevGmail suite 95/95.
- The `log` CLI is shadowed by zsh's builtin in this shell; every earlier
  "no logs" observation was wrong. `/usr/bin/log` works.
- The Aug 16 release-main installs failed to launch (entitlement macros),
  so the previous daily driver was effectively a Debug build; today's is
  the first launched Release daily driver. Mock/demo mode is developer-
  build-only, so the blur band could not be probed headlessly in Release —
  PR #20 adds a one-time "band active" notice per pane. After the rebuild,
  the release app logs all three bands active (240/280/1273pt panes), so
  the band mounts and reduces correctly under Release; visual confirmation
  of the fade is back with Henrik.

### Verification

- BrevGmail 95/95 with the new regression test; format + strict lint +
  ADR gate pass on both PR branches; daily driver rebuilt from clean
  origin/main via release-main and relaunched live.
- Post-relaunch unified log: three ScrollEdgeBlur "active" notices, no
  MessageBodyLoad or IMAPBodyFetch errors.

### Handoff

- Live Gmail adapter QA (issue #2) remains open; this bug shipped through
  that gap.
- If the overlay still looks wrong to Henrik despite "band active" logs,
  the next probe is visual (mask/geometry), not mounting.

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


## 2026-09-04 — Codex — Multi-account review remediation and UI redesign

### Goal

Address the nine reviewed multi-account reliability/performance findings, then
apply the requested conversation-reader and multi-mailbox sidebar redesign.
Baseline: `0902c93e`; branch: `fix/multi-account-workspace`; target: `main`.
The initial canonical checkout was clean and had no open PR.

### Changes

- Separated virtual collection browsing from source-owned reader selection;
  explicit row selection restores its headers after auxiliary presentation.
- Guarded reload/search/page publication by request ownership and cancellation;
  root folder/mailbox/command responses and optimistic reader updates also
  reject a different account when raw folder/message IDs collide.
  debounced search and bounded source work. Source discovery publishes progress,
  retains failed cached accounts, has a timeout/retry, and cancels superseded work.
- Settled bulk mutation outcomes per source, preserving successes and restoring
  a failed reader only when the user has not selected another message.
- Preserved temporarily unavailable profile membership and added explicit
  removal of unavailable memberships. Empty profiles cannot compose through an
  unrelated account, while the existing single-account folder fallback works.
- Scoped pins to account/mailbox/message, preserved legacy data with a visible
  reassignment notice, and kept a global 500-pin limit with explicit feedback.
  Added the v2 key to the existing opt-in preference-sync allowlist.
- Kept mail roots mounted across account changes; subscriptions use backend
  instance identity, and removed/replaced account work cannot restore stale rows.
- Added indexed SQLite Gmail label pagination, cache-first reads, bounded cold
  fetches, and coalesced account refresh tasks that cancel on disconnect.
- Kept mailbox selectors above the folder tree, shortened row source labels,
  made the profile picker discoverable, and flattened conversation sections.
  Native profile actions now stay inside the auxiliary window instead of
  leaving title/toolbar state in the main mail window.
- Corrected a pre-existing test-thread race by isolating native NSToolbar tests
  to the main actor. Updated the compact-layout contract and snapshot CI routing.

### Verification

- Red/green regressions covered collection preservation, stale/cancelled loads,
  partial rollback, unavailable profiles, pin collisions, cached Gmail failures,
  indexed pagination including 120 rows across three pages, progressive source
  publication, search debounce, fallback context, and reader header recovery.
- BrevMail: 1,503 tests plus six isolated ContactsAccessPolicy tests passed.
  BrevBackend: 1,010; BrevGmail: 99; BrevSettings: 314 passed.
- The unsplit Contacts run exposed the known process-global demo gate race;
  final runs use the existing CI split. A native toolbar test crash exposed
  off-main AppKit creation; the main-actor correction passed the full suite.
- Format, strict lint, self-tests, privacy audit, and git diff checks passed.
- Native mock build/launch and rendered interaction checks passed. The profile
  toolbar leak and blank-reader row selection were reproduced during native QA
  before their fixes. Updated snapshots cover sidebar, reader, and profile UI.
- macOS and iOS Simulator builds passed. Existing app-delegate/SDK warnings are
  distinct from build success. No physical-device or live-provider acceptance
  is claimed; issue #2 remains outside this mock verification.

### Documentation and handoff

CHANGELOG, PRIVACY, ADR-0020, ADR-0050, ADR-0056, and the focused QA matrix were
updated. README and AGENTS need no change because setup, repository layout, and
workflow remain the same. Demo body text is fixture-only; layout changes were
verified by rendered snapshots/native checks rather than logic-only TDD.

Cold Gmail reads intentionally retain full MIME data for attachment correctness,
so the performance improvement is cache-first indexed reads and four concurrent
cold requests, not elimination of all cold payload transfer. Legacy pins remain
recoverable as original records but require reassignment. These limits belong in
the PR. Open a non-draft PR to main; do not merge or replace `/Applications/Brev.app`.


## 2026-09-05 — Codex — PR #27 contrast and reading layout follow-up

### Goal

Implement the approved contrast, proportions, selection, typography, and
conversation-density recommendations; assess Settings afterward without
changing its specific screens. Continue `fix/multi-account-workspace` from
`604c8c81`, targeting the existing PR #27 to main.

### Changes

- Revised only the default monochrome text tokens, keeping all theme IDs,
  custom palettes, and custom accent settings intact. Added a 24-pair contrast
  matrix with a 4.5:1 text threshold and selection indicator checks.
- Shared opaque selection roles across main rows, thread children, and folders.
  Active/inactive selection keeps readable foregrounds. Removed blocked-sender
  row dimming while preserving its status indicator; raised essential metadata
  size and retained subject/sender emphasis.
- Added a 420-point preferred desktop list and 1440x820 new-window default while
  preserving the 960-point compact minimum and saved geometry. Bounded thread
  content to 840 points and reduced header/body gaps.
- Moved thread display-mode switching into its header menu. Dark-mode WebKit
  canvases explicitly match bgPrimary; original message styling remains an
  available mode. Body line height is 1.5.
- PR #27's hosted failures were all the root view expression exceeding the CI
  compiler's type-check budget. Split it into smaller opaque view expressions
  and extracted the backend-session observer, without changing modifier order.

### Verification and handoff

- Contrast, preferred-width, and body-canvas tests failed before the fixes.
  Final focused behavior tests passed. Rendered default light/dark active and
  inactive selections, wide conversations, and affected existing snapshots.
- BrevThemes: 8 tests passed. BrevMail: 1,506 plus the isolated six Contacts
  policy tests passed. Lint/format and repository self-tests passed.
- Native mock launch and compact/wide rendering were checked with the dated
  test identity. iOS/hosted builds are checked separately in the PR handoff.
- Updated ADR-0069 because BuiltIns.swift is protected; no new public theme
  fields or network behavior. README/PRIVACY/AGENTS need no change for this
  visual and compiler follow-up. Palette/configuration and visual-layout edits
  use calculated contrast and rendered snapshots rather than logic-only tests.
- Settings-specific changes are intentionally outside this implementation;
  its requested assessment follows the verified mail UI pass.

### Hosted compiler follow-up

- Hosted macOS compilation passed at 654f9acf. The new BrevThemes contrast test
  hit an older-compiler type-check limit in chained channel calculations.
  Replaced that expression with typed scalar steps; all eight focused tests
  pass locally. This changes test compilation only, not production colors.
- The committed dated mock build installed and launched successfully. Settings
  was assessed read-only across Accounts, Appearance, Mailbox View, and Folder
  Sync; no account preferences or Settings implementation were changed.


## 2026-09-05 — Codex — PR #27 Settings consistency follow-up

### Goal and changes

- Fixed the seven Settings assessment findings on the existing
  fix/multi-account-workspace branch, targeting main through PR #27.
- Mail publishes explicit mailbox context only when its source selection or
  workspace revision changes. Folder Sync follows that context, labels its
  current mailbox, reuses cached folders, and loads only the requested source.
- Folder retention now persists SourceFolderID overrides. Legacy folder-only
  values remain fallback; choosing Default overrides that legacy value for
  the selected source without affecting other mailboxes. Retention sweeps and
  storage repair use the same source-aware resolution.
- Folder Sync uses lazy compact rows, parent/child indentation, filtering,
  native retention pickers, and explicit visibility labels. Narrow layouts
  stack controls when needed. Settings search indexes visible control labels
  and scrolls to a chosen result, including the appropriate Mailbox View pane.
- Shared selection roles live in BrevDesign. Settings navigation is wider and
  uses the same opaque selected-row styling as Mail. Account actions are in a
  menu; default-account and default-mailbox states have distinct labels.
- Appearance puts a sample-mail preview before optional window detail controls.
  Mailbox View is grouped into Reading, Message list, Folders, and Sender images.
  Storage/repair account scope and app-wide retention defaults are explicit.

### Verification and handoff

- Failing tests established source isolation, search omissions, missing source
  context/hierarchy APIs, and scoped override summaries before implementation.
- Settings and Mail package suites, separate Contacts tests, default light/dark
  snapshots at regular/narrow sizes, macOS test installation, iOS Simulator
  build, lint/format, and privacy checks were run. Final counts and hosted
  results are recorded in the PR handoff.
- Native Settings Accounts and navigation were inspected. The Mac locked during
  Folder Sync navigation; the tool requested a manual unlock. End-to-end native
  mailbox switching, search scrolling, and keyboard/VoiceOver checks remain
  unavailable until unlocked. Offscreen rendered snapshots are verified.
- Updated ADR-0012 for the shared selection/context contract and CHANGELOG for
  the visible behavior. README, PRIVACY, and AGENTS need no changes: setup,
  workflow, providers, and external network behavior are unchanged.
- No merge, release, version change, issue closure, or daily-driver replacement.


### Final rendered polish

- Narrow Folder Sync rows keep the retention label beside their stacked picker;
  the mailbox scope header fills and aligns with the Settings content column.
- Snapshot hosting now attaches an offscreen NSWindow and drains AppKit layout,
  so the navigation list and native controls are actually rendered. Added full
  light/dark Folder Sync workspace captures with the visible mailbox identity.
- This improves automated rendered evidence while leaving the locked-Mac native
  interaction limitation explicit. No screenshot was substituted for native QA.

- Final keyboard-path inspection aligned arrow navigation with pointer
  selection: leaving an extension page clears its contribution and any old
  search anchor. Left/right arrows remain available to native controls.


## 2026-09-05 — Codex — PR #27 separator and navigation follow-up

- Reproduced the white sidebar gutter in the running dated mock app and saved
  before/after native captures. A pixel regression over a contrasting backing
  failed before the fix, then passed when the full hit target owned its themed
  backdrop. The visible boundary is one physical pixel; the wider drag target
  stays usable. The split container also paints beneath native divider gaps.
- Sidebar drag state now consumes successive global pointer positions, avoiding
  moving-coordinate feedback and the dead zone after reversing from a clamp.
  SceneStorage is updated on release, including the final pointer sample.
  Unit tests cover ordinary movement, reversal at the limit, and release state.
- Sampled the running mock process during repeated drag gestures and verified
  repeated native drags moved the edge to the requested positions. This is
  interaction evidence, not a claimed FPS or live-provider latency benchmark.
- Accounts now belongs to App; Advanced is a normal section with flat rows.
  Native Accounts, Advanced, and Extensions alignment were visually checked.
  Updated grouping tests and full navigation snapshots in light/dark themes.
- The Mac locked again while continuing the earlier pending search checks.
  The current divider, resize, and navigation checks completed before lock;
  prior search scrolling and full keyboard/VoiceOver acceptance remain pending.
- The user's later mailbox/profile simplification question was answered with
  a compact-switcher recommendation. Its implementation awaits their choice;
  it is separate from this completed separator/navigation scope.
- Final tests, builds, lint, self-tests, and hosted checks are recorded in the
  PR handoff. ADR-0012/0053 and CHANGELOG updated; README/PRIVACY/AGENTS do not
  need changes because setup, network behavior, and workflow are unchanged.


## 2026-09-05 — Codex — PR #27 profile-filtered mailbox groups

- Implemented the clarified profile model after the user's Apple Mail/eM Client
  comparison: profiles choose which mailbox groups are visible; the groups
  stack vertically and can be expanded independently. The profile chooser is
  a compact native menu, and All Inboxes/Smart Views remain global shortcuts.
- Removed two-line account cards, the redundant Mailboxes heading, and the
  separate folder-owner caption. Each mailbox header owns its indented tree.
  Addresses remain in help/accessibility labels; collapsed headers show counts.
- Expansion is stored locally under mailbox.disclosureState. Saved empty state
  is respected and hidden profile members retain their expansion choice.
  Reading a virtual collection does not expand a mailbox; physical folder
  selection reveals its source without closing others.
- The two-expanded-mailbox snapshot exposed duplicate provider folder IDs being
  reused by SwiftUI. Rows now use SourceFolderID; both Inbox trees render and
  only the selected source/folder highlights. Snapshot stores are isolated so
  saved disclosure state cannot pollute another fixture.
- Updated profile-management copy to say mailboxes, and recorded the final
  interaction model in DESIGN.md. Existing provider/profile filtering and
  account connections remain unchanged; no new network calls or dependencies.
- Unit and rendered checks cover independent groups, persistence, empty saved
  state, hidden profile members, both themes, filtered profiles, and identical
  folder IDs. Final package/build/lint/CI evidence is in the PR handoff.
- The initial compact-menu trial was exercised natively (38-message aggregate,
  9-message Work inbox, and Manage Profiles). The final stacked-group native
  check was blocked when the Mac locked; an unlock was requested while code
  checks continued. Do not count the superseded trial as native verification
  of the final layout.
- Documentation sweep: CHANGELOG, DESIGN, WORKLOG, and QA notes updated.
  README/PRIVACY/AGENTS/ADRs need no change: setup, architecture, workflow,
  theme schema, and external network behavior are unchanged. Existing ADRs
  0002/0004/0017/0028 were consulted for layout and source ownership.


### Hosted compiler correction

- CI caught a stray @ViewBuilder annotation left on the state-restoration
  helper when the old account-header view was removed. Removed the annotation;
  restoration is an ordinary Void method. This has no layout or state-policy
  change and is verified by the existing disclosure tests and rebuilt targets.


### Preference-sync test isolation

- The next hosted run passed both builds and Mail tests but exposed a parallel
  Settings test race: an observer accepted another store's global notification.
- Added a deterministic unrelated notification to reproduce the wrong-key
  assertion, then restricted that observer to its own store. The production
  notification center and local/remote sync behavior remain unchanged.


## 2026-09-05 — Codex — PR #27 thread selection and Smart Views

- Goal: repair inline reply selection and replace the clipped Smart View form
  with consistent condition editing, visibility controls, and display ordering.
- Reproduced the reported native blank reader with Flagged active, expanded
  Kitchen drawings, and Kari's unflagged child selected. The reader used the
  filtered header set while inline rows used full thread context. Added a red
  regression, then retained context for matching threads across reconciliation.
- Moved the saved-view editor into BrevSettings so Settings and Mail use the
  same compact sheet. Added all/any condition groups, compatible comparisons,
  cached header date/status predicates, source-owned mailbox/folder choices,
  Sent/Trash inclusion, and legacy predicate migration. Name and every condition
  must be valid before Save; long groups scroll above the fixed action footer.
- Added Settings > Smart Views and a matching sidebar management sheet. The
  entire section or individual built-in/custom entries can be hidden. Shared
  display order persists separately from visibility and retains hidden entries.
- Saved message views now use existing source-scoped cache-only search across
  profile folders. Cache results retain thread context, deduplicate label aliases
  while keeping a matching folder membership, and use the existing load ownership
  guard. Query changes participate in task cancellation; typing filters completed
  cached results without re-reading folders. No new backend API or network call.
- Regression checks: filtered child selection failed before the fix; any/all,
  negative/status/date/source conditions and display-order tests failed before
  their implementations; a label-alias test caught duplicate IDs before deduplication.
- Verification: BrevMail 1,511 tests plus the separate six ContactsAccessPolicy
  checks pass; BrevSettings 333 tests pass. Light/dark editor, management,
  sidebar and Settings-navigation snapshots were inspected and updated. macOS
  test install/launch, iOS Simulator build, lint/format, and repository self-tests
  pass. Final short status labels are covered by the focused editor snapshot run.
- Native limitation: the Mac locked after the initial reproduction and before
  final click-through verification. The dated mock test app is installed; final
  reply-selection, Smart View save/cancel, reorder/hide/restore and live-provider
  acceptance remain manual checks in docs/qa/multi-account-workspace.md.
- Documentation sweep: updated README, CHANGELOG Unreleased, DESIGN, ADR-0041
  implementation status and QA notes. Privacy and agent workflow are unchanged.
  Branch remains fix/multi-account-workspace with PR #27 targeting main; no
  merge, release, version change, or issue closure is authorized.
