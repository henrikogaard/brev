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


## 2026-09-05 — Codex — PR #27 complete cached Smart View candidates

- Final backend inspection found two correctness gaps in ordinary cache search:
  IMAP truncates results at 50, and Gmail filters only the primary folder.
  Added failing regressions for 120 cached IMAP headers and a secondary Gmail
  label before replacing the saved-view candidate path.
- Added the source-scoped, read-only `cachedMessageHeaders` protocol seam.
  IMAP merges cached/indexed headers without the search cap; Gmail reads the
  requested label from its indexed local store; mock data follows the same scope.
  The fallback reports unsupported enumeration and never connects or fetches.
- Saved rows retain all cached folder memberships. All/any and negative folder
  conditions evaluate that set, while Sent/Trash exclusions also use reserved
  system labels. Tests first exposed multi-label negation and scope leaks.
- Verification: Backend 1,011, Gmail 100, Settings 335, and Mail 1,511 tests pass;
  the separate six Contacts tests passed earlier in this unchanged test area.
  Lint and format pass. Both app builds and final hosted checks are repeated for
  this follow-up. Native interaction remains blocked by the locked Mac.
- Updated ADR-0041 and the Unreleased notes to describe the final cache seam.
  No provider request, body fetch, external network behavior, release, or merge.

- Saved-view search refinements use the existing natural-language parser and
  expose only cache execution. This keeps visible chips consistent with actual
  matching and avoids offering a server mode that saved conditions cannot run.
  Existing parser tests and Mail build cover the reused parser; the search-menu
  interaction is included in the pending native pass because the Mac is locked.
- Added a native-view initialization regression for repeated saved-list creation.
  It failed with the prior ordinary-search default and now retains cache mode;
  returning to the normal list restores the normal provider-aware default.


## 2026-09-05 — Codex — Issue #28 core parity implementation

- Established an isolated feature/mail-client-parity worktree at #27's
  1250634 baseline. Integration will stack on fix/multi-account-workspace and
  eventually main. The umbrella is In progress on project 9; architecture
  proposals are separately reviewable in #29.
- First slice: make Undo failures visible and retryable, prevent overlapping
  reversals, preserve a later pending action, and refresh after a successful
  reversal. Existing root Undo closures now propagate errors to the queue.
- Tests exercise the existing public UndoQueue action boundary. A failed
  reversal test was red before implementation; retry, single-flight, and dismiss
  cases are covered. Light/dark failure feedback snapshots were added.
- Remaining work includes consistent registration across entry points, provider
  move identities, native Undo integration, scheduling/provider parity,
  conversation/search completeness, performance and live QA, and accepted-ADR
  implementation. This slice does not claim completion of #28.

- Undo slice verification: 1,518 BrevMail tests passed excluding the separate
  Contacts process; focused queue/error snapshots passed in both themes. Lint
  and format passed. Independent standards and behavior reviews found a stale
  failure/new-action defect, fixed with a red-green regression and re-reviewed
  without remaining material findings. Native/live acceptance remains pending.


## 2026-09-05 — Codex — Issue #28 move identities and native Undo

- Added provider-bound move reversals. IMAP retains tagged/untagged COPYUID
  mappings, bounds range parsing to requested UIDs, validates UIDVALIDITY before
  a reversal even on an already-selected mailbox, and does not retry a possibly
  partial NO response as COPY. Standard account provisioning forwards the result
  operation. Gmail reverses the move's label delta while preserving unrelated
  labels; preview backends preserve source ownership.
- Toolbar, row and bulk read/flag/move/trash paths now register shared Undo.
  Retry skips already completed move batches. Unchanged messages are excluded
  from flag inverses. Ordinary bulk unread deltas use actual changed/unread
  headers; label providers wait for their authoritative counts.
- The latest mail Undo survives its toast; leased mutations suspend Undo until
  their work finishes. Invocation order prevents older late results replacing
  newer Undo. Retired backend sessions cancel/invalidate queued work and reject
  late registrations or error publication.
- macOS Edit Undo uses focused mail commands with explicit priority for native
  text Undo managers. Settings/other windows retain native Undo/Redo. Menu state
  observes editing, key-window and Undo notifications. An experimental responder
  insertion was discarded after native tests demonstrated hosting/window routing
  problems; no view responder chain is modified in the final implementation.
- Tests were run red before fixes for silent errors, stale failures, partial
  MOVE retries, destination IDs, UIDVALIDITY, bulk flag preservation, late
  session callbacks, and native text/mail routing. Full checks and native QA
  are pending for this slice. #28 remains In progress; #29 awaits ADR acceptance.
- Additional finding for the migration/export slice: File-menu MBOX export
  contains headers without bodies; Settings exports reconstruct MIME and omit
  attachments. Repair these existing flows independently of new local archives.

### 2026-09-05 — Codex — Issue #28 / PR #30 review fixes and native checks

- Fixed review findings in the move/Undo batch: partial folder failures retain
  completed receipts and restore only failed rows; unified mutations reconcile
  per folder within each mailbox. Successful receipts are registered before
  stale UI response guards, so navigation changes do not lose source-owned Undo.
- Added shared junk reversal handling for root, rows and unified lists, native
  text-priority Undo/Redo commands, no-op flag registration filtering, explicit
  invalidation after non-reversible folder/label/block actions, and cancellation
  checks between provider/batch operations. An already transmitted provider
  request cannot be recalled; retired sessions suppress late UI publication.
- Gmail Undo retries retain per-message completion. IMAP uncertain move failures
  refresh source and destination; COPY fallback is limited to unsupported MOVE
  syntax. Mixed irreversible/reversible bulk commands deliberately offer no
  generic whole-command Undo.
- Added byte-wise mboxrd escaping after a red test showed non-UTF8 source skipped
  From-line escaping. Full MIME export wiring and raw-byte backend persistence
  remain pending; no claim of complete migration support.
- Build reproduced a Bash 3 empty OAuth argument-array failure after dependency
  download recovered. Applied the same nounset-safe expansion already used for
  optional build arguments. `scripts/test-build-run-env.sh` passed.
- Native mock build launched through `script/build_and_run.sh --mock --verify`
  using the dated test bundle in this worktree. CUA verified archive reduced
  Inbox from 29 to 28 messages, native Edit > Undo remained enabled after toast
  expiry, and Undo restored 29. Compose text Undo cleared entered test text;
  Redo restored it. After clearing/closing the empty composer, Cmd-Z reversed
  the earlier row flag action. No mail was sent.
- The row/drop wiring uses the tested provider receipt path; direct SwiftUI
  private action invocation is not an automated test seam. Native drag/drop,
  source-switch-during-network, multi-folder partial provider failure, selection
  restoration, offline queued Undo, and live IMAP/Gmail acceptance remain open.
- Full package suites passed before the last review fixes; final reruns and
  frozen review are recorded in the subsequent handoff. The app build warning
  in BrevApp.swift about the existing delegate Sendable capture is unchanged.

- Final local rerun passed 1,534 Mail tests, 1,020 Backend tests, and 102 Gmail
  tests. The subsequent same-folder filtering and cancellation checkpoints
  receive focused reruns. Lint/format passed. macOS test build and startup
  passed; the daily-driver bundle was untouched.
- Hosted checks for first-slice commit a72e3c1 showed Undo image differences on
  macOS 15 and an existing BrevDesign WindowAppearancePreferences process crash.
  Added Undo images to the established macOS 26+ snapshot group, retaining local
  image comparisons and behavior tests. Workflow YAML parses. The isolated
  WindowTrafficLightPolicy test passed using stable Xcode locally; the hosted
  process failure is not claimed fixed and will be checked on the next commit.
- Required summary-router / summary-tables skills were not installed in the
  available catalog or searched skill roots. Used the repository's table format
  directly for evidence reports.

- Final review caught retirement before an Undo task starts. A deterministic
  red test confirmed the canceled task still invoked the provider action.
  Added a cancellation check before invocation; subsequent green evidence is
  included in the final focused queue run.

## 2026-09-05 — Codex — Issue #28 / PR #30 Undo reader restoration

- Verified c858d68 was pushed and its 19 hosted checks completed successfully,
  including the earlier Design process failure and Mail snapshot configuration.
  The parent issue remains In progress; no merge/release or architecture
  acceptance was inferred.
- Added navigation context to forward-operation leases. Move receipts now use
  the provider's restored ID mapping to reselect the original reader message.
  The selection is restored only in the original folder/search or aggregate
  view and only if the user did not change selection while Undo was running.
- The reader retains a confirmed restored header when the first refreshed page
  contains only newer mail. A fetched header replaces that temporary copy;
  explicit removal, navigation, or selection changes release it. Shared junk
  actions use the same restoration path.
- Red-green regressions proved the original next-message focus bug, older-page
  loss after restoration, and junk fallback missing selection restoration.
  Tests also cover other folders, same-view mid-Undo selection, colliding IDs
  across sources, All Inboxes context, and releasing/replacing retained headers.
- Public header identity remapping preserves recipients, flags, attachments,
  RFC threading metadata, and the non-RFC provider-ID threading fallback.
- Final package, lint, mock native checks and frozen review follow below.
  Full MIME export, offline queued Undo, scheduling, complete conversation/
  search coverage, live/performance acceptance, and proposed ADRs remain open.

- Verification: 1,543 Mail tests and 1,020 Backend tests passed; formatter/lint
  and diff checks passed. Both frozen reviewers found no material findings.
  The dated mock build/startup passed. CUA verified selected mock bill ->
  toolbar Archive -> Cmd-Z restored Inbox 28 -> 29 and reopened the same bill
  in the reader. The settled screenshot showed matching sender details.
- Documentation sweep: CHANGELOG and this log updated; README architecture,
  privacy/network tables, ADRs and AGENTS are unchanged because this adds only
  transient reader restoration within existing provider-bound actions.

## 2026-09-05 — Codex — Issue #28 / PR #30 original MIME bytes

- Added a provider-neutral original-byte export contract. IMAP fetch/cache now
  keeps literal MIME bytes and derives text only for rendering, without storing
  duplicate decoded and raw copies. Legacy text caches remain readable but are
  refreshed from the server when original-byte export is requested.
- Gmail stores original MIME in the existing source-cache table as BLOB;
  legacy TEXT remains rendering-only. Cache account/message purge behavior is
  unchanged. Original-byte cache reads work offline and validate source identity.
- Red-green tests reproduced non-UTF8 MIME changing from 344 to 347 bytes,
  proved literal/cache round-trip fidelity, verified IMAP legacy-cache refresh
  followed by offline reads, and verified Gmail byte fidelity through SQLite
  restart, legacy-cache replacement, and account-scope rejection.
- This is the data foundation for complete export. File-menu and Settings
  export callers still need conversion to the new API, streaming/progress/cancel
  handling, and safe output publication. Their previous body/attachment gaps
  are not claimed fixed.
- Privacy/docs sweep: no new provider endpoint, account permission or cache
  category is added; existing message-source retrieval and purge rules apply.
  Original MIME remains in the existing provider-owned, evictable caches.

- Review identified the secondary index-cache provenance gap. Added explicit
  original-byte store/read methods and schema 4 provenance in BrevSyncEngine.
  Migration leaves legacy rows unverified, original writes mark bytes atomically,
  and legacy overwrites clear the marker. Account/message purges keep their
  existing lifecycle.
- A red integration test reproduced index-only offline failure after a fetch.
  It is green with the real SQLite index across restart, and rejects a later
  unverified overwrite. Added in-memory/SQLite marker lifecycle tests and legacy
  migration assertions. ADR-0030 records this cache representation detail.

- Connected single-message Save As in folder/unified lists to rawMessageData
  and an atomic byte writer. New rawMessageBytes capability prevents text-only
  adapters from offering an export they cannot preserve. IMAP/Gmail advertise
  it; Gmail source actions remain available for offline cached messages.
- Red-green EML output regression proved exact non-UTF8 bytes and menu gating.
  Existing raw-source/attachment cache tests and Gmail offline source view pass.
  ADR-0045 records the resolution of its previously documented String-fidelity
  risk. Full folder File-menu/Settings export is still pending.

- Final verification: 1,543 Mail, 1,023 Backend, 103 Gmail, 74 SyncEngine
  XCTest tests and 2 SyncEngine Swift Testing tests passed. Lint/format,
  diff checks, and the dated mock macOS build/startup passed. Both review axes
  cleared the provenance and Save As consumer changes.
- EML fidelity is verified by reading back temporary output bytes. Native Save
  As against a live mailbox was not run; the mock backend intentionally lacks
  original-source capability. No new view layout was introduced.

## 2026-09-06 — Codex — Issue #28 / PR #30 full-folder export

- Replaced the File menu's metadata-only path and Settings' reconstructed-body
  exports with a shared original-MIME exporter. It streams pages/messages,
  follows empty intermediate pages, deduplicates IDs, detects repeated cursors,
  and captures the source mailbox/folder before destination selection.
- MBOX is staged and atomically replaces the approved output only on success.
  EML files are grouped into a new collision-safe directory with byte-bounded,
  safe names. Unapproved replacements are rejected, including destination-folder
  selection on iOS. Security-scoped folder access is held through the operation.
- Added shared compact status/cancel controls for Mail and Settings. Background
  file work is separate from UI updates, which are limited to 10 Hz. Completed,
  failed and canceled exports allow another attempt. Pending picker callbacks
  are invalidated when their mailbox session retires.
- Settings has independent export mailbox/folder selection and cancellable,
  identity-bound catalog loading. File export status reserves footer space.
  iOS uses the system folder picker; macOS uses native save/open panels.
- Corrected privacy text claiming no export network activity. Missing original
  messages may be downloaded. No new provider endpoint or permission is added.
- Tests reproduced page truncation/missing MIME, late cancellation replacing
  old output, unapproved overwrite, and a retired picker starting stale work.
  Green coverage includes full payloads, attachments/non-UTF8, EML collisions,
  Unicode names, controller completion/cancel/retry, and session retirement.
- Rendered/inspected light and dark status snapshots. Final package/native
  checks and review follow. Live provider/native iOS picker acceptance remains
  separate from local tests and builds.
- Additional area 9 finding: real IMAP/Gmail adapters currently do not expose
  MailImporting; only MockBackend does. The old Settings import buttons offered
  predictable unsupported operations and terminal states prevented retry.
  Unsupported import is now explained/disabled; real source-owned import remains
  required work under the parent goal.

- iOS package compilation passed for the document-picker implementation with
  security-scoped destination access. Native picker interaction is still a
  device acceptance check. Interactive controls have 44-point iOS targets.
- Export catalog retries now refresh the SwiftUI task identity instead of
  launching an unowned task, so an old-account retry cannot populate a new
  account's picker. Session tokens reject destinations selected after retirement.
- UTC mbox envelope timestamps use ctime day padding; the MIME payload remains
  byte-preserving mboxrd output. See RFC 4155 Appendix A for envelope context.

- Verification: 1,030 Backend, 1,543 Mail and 6 separate Contacts tests passed.
  Settings passed 338 tests excluding the older AI Writer macOS snapshot suite.
  Its 3 tests produce 9 pixel mismatches here and on unchanged canonical base
  1250634; the old baselines were preserved. New export snapshots passed.
  The dated September 6 macOS build/startup and iOS Settings package compilation
  passed. Native CUA inspection was unavailable because the Mac was locked.
  Privacy audit and diff checks passed.
- Review identified an additional Settings retirement race: after switching
  from account A to B, replacing backend A did not invalidate A's pending export.
  Settings now observes all account backend identities, using the same
  reconciliation rule as Mail. Added replacement and reorder/addition tests.
- Behavior review found the legacy macOS platform gate still disabled File-menu
  export despite the new source action. A failing policy test reproduced it;
  macOS now permits the command while folder/source/raw-byte capability and
  operation-state checks determine availability. The iOS menu remains absent.
- Settings now owns the export controller above individual sections. Navigating
  to another section keeps the task and footer controls alive; backend retirement
  is observed at that same level. The former section-owned controller canceled
  work on deallocation. Controller behavior is automated, but mounted page-switch
  lifetime/interaction remains native QA: the Mac is locked and this package has
  no mounted-view introspection fixture. No new testing dependency was added for
  that structural ownership change.
- A real-cache regression reproduced successful publication of a partial folder
  while offline. IMAP bulk enumeration now bypasses cache/transport fallbacks
  and follows server pages or throws, matching Gmail; ordinary message browsing
  keeps its existing offline behavior. Tests cover disconnected partial caches
  and transport loss on a later page without replacing prior output. ADR-0045
  and PRIVACY document this full-folder completeness requirement.
- Documentation sweep: updated CHANGELOG, PRIVACY, this worklog and the existing
  multi-account QA checklist. No new endpoint, provider permission, architectural
  archive service, setup, build target or release is introduced, so README,
  AGENTS and a new ADR do not need changes for this export slice.

## 2026-09-06 — Codex — Issue #28 / PR #30 durable Gmail staging

- Verified all 19 hosted checks passed on folder-export commit 3d89edd. The
  parent remains In progress and strategic ADRs in #29 remain unapproved.
- Scheduled-send inspection found Gmail draft/attachment staging was memory-only.
  Added account-owned staging to SQLite schema 2 and wired the adapter's default
  to use it. Restarts preserve local/provider draft identity and attachment bytes;
  sync/cache eviction preserves staging and account removal clears it atomically.
- Added transactional attachment byte limits, remote-ID replacement, and deletion
  of attachments staged before the first draft save. Staging operations now throw
  persistence/read errors; provider submission requires successful initial staging.
- Confirmed remote save/send results survive local acknowledgement/cleanup errors,
  which are surfaced through sync health. This avoids retrying confirmed provider
  operations as if they failed. Gmail scheduled send itself is still pending.
- Red-green tests reproduced restart attachment loss and loss of a confirmed
  remote draft identity after local acknowledgement failure. Coverage also checks
  write failure preserving old content, version-1 migration, account isolation,
  cache reset, byte limits, and draft/attachment removal. Full Gmail suite: 118
  tests passed. Final lint/build and review evidence follows.
- Documentation sweep: CHANGELOG, PRIVACY and ADR-0064 record local staging and
  its ownership. README/setup and UI layout are unchanged. No new network call,
  service, release, daily-driver install, or architecture approval is introduced.
- Discard retries now finish local cleanup when Gmail reports that the remote
  draft is already absent. Other provider errors preserve staging. Red-green
  coverage confirms 404 cleanup and 403/500 retention.
- Dated macOS mock build/startup, iOS Gmail package compilation, lint/format,
  privacy audit and diff checks passed. UI layout is unchanged, so no new
  snapshots were added. Live Gmail and native restart acceptance remain pending.
- Scheduler follow-up must store explicit scheduling intent separately from
  autosaved Draft.scheduledFor values: choosing a date while composing is not
  authorization to send until the user submits the schedule.
- Review-driven lifecycle fixes add account foreign-key ownership, per-draft
  single-flight operations, and session invalidation that drains local writes
  before account purge. Red-green regressions cover old acknowledgements after
  remove/re-add and connect completing after disconnect. In-memory staging now
  matches SQLite's remote-alias and pre-save attachment cleanup contract.
- Residual parent-area-5 finding: the separate sync reconciler can still
  republish connected metadata after disconnect without a generation check.
  Draft writes remain blocked by their retired coordinator; broader sync-task
  retirement is pending reliability work rather than completed by this slice.
- Added the previously omitted BrevGmail package to hosted CI's test matrix so
  these regressions run on PRs. This one-line configuration change skips TDD;
  workflow YAML parsing and the actual package suite verify it locally.

## 2026-09-06 — Codex — Issue #28 / PR #30 Gmail scheduled delivery

- Added schema-3 submitted schedules with frozen MIME, metadata-only list reads,
  atomic claims and attempt-owned completion. Autosave dates do not create intent.
  Gmail now queues scheduled sends, restores them, runs an in-process 30-second
  worker, and exposes existing quit/background scheduling hooks.
- Outbox shows current-account schedules with time changes, cancellation and an
  explicit reviewed retry. A stale date sheet cannot authorize an uncertain retry.
  Sidebar counts use account-scoped outbox events instead of body reloads/polling.
- Tests cover queue persistence, due delivery once, competing SQLite claims,
  restart/uncertainty holds, retry classification, frozen content, newer-edit
  retention, Date header refresh, and preventing protected requests from falling
  through to plaintext. Full Gmail S/MIME preparation remains provider-parity work.
- Found and fixed nil-folder event handling that reloaded unified views for
  outbox-only metadata. New light/dark scheduled-row snapshots were rendered and
  inspected; the compatible-renderer CI group includes them.
- First hosted Gmail job on a0f664a exposed an older Swift Testing macro expansion
  error in GmailRuntimeSyncTests. Awaiting Task.value before #require fixes that
  test portability issue. Other 19 checks on a0f664a passed. Hosted confirmation
  of this fix and final full-suite/build/review verification follow.
- Existing IMAP scheduled editing, full-content editor handoff, unified multi-
  account Outbox, offline startup editing, live-provider QA and broader goal
  requirements remain open; this slice does not establish full provider parity.
- Review fixes add session-owned claims and weak live-owner tracking to avoid
  treating another active backend as interrupted. Ownership is read under the
  SQLite write transaction; failed queue initialization does not register a live
  owner or publish connected state. Automatic attempts stop at ten.
- Confirmed delivery with failed local deletion is held for review without
  automatic resend. Date-only autosaves are not scheduling intent; content and
  other metadata changes remain protected from delivery cleanup.
- Full local verification so far: 1,030 Backend, 1,546 Mail and 131 Gmail tests
  pass. Native mock macOS build/startup and iOS Mail/Gmail compilation pass.
  Light/dark scheduled-row snapshots pass. Native CUA inspection is unavailable
  because the Mac is locked; live Gmail delivery/quit/Outbox acceptance is pending.
- Final verification: Gmail 131, Mail 1,546, Backend 1,030, and separate Contacts
  6 tests pass. Native dated mock macOS build/startup and iOS Mail/Gmail builds
  pass. Lint, unchanged formatter output, privacy audit, workflow YAML parsing
  and diff checks pass. Both review axes cleared the final race/error fixes.
  UI copy changes reuse the inspected scheduled-row component; full native
  Outbox interaction/live-provider acceptance remains unverified while locked.

## 2026-09-06 — Codex — Issue #28 / PR #30 IMAP scheduled editing

- Added shared Outbox scheduling controls for IMAP, staged-write readback, optional
  cancellation recovery, current-metadata serialization, per-account delivery and
  per-draft edit exclusion, and account lifetime checks around local cleanup.
- Backoff survives reconnect and public hooks. Interrupted/uncertain delivery,
  missing content and ten failed attempts stay visible for reviewed recovery.
  Scheduled SMTP uncertainty has one retry route in Outbox; ordinary offline
  conflicts are unchanged. Gmail adopts the compatible optional cancellation
  result without changing its stored draft behavior.
- TDD reproduced duplicate retries, interrupted-claim bypass, lost unavailable
  intent and uncertain delivery leaving Outbox. Focused scheduling tests passed
  after fixes; full suites, native builds, lint and independent review follow.
- Updated CHANGELOG, ADR-0022, PRIVACY and QA guidance. README setup and backend
  direction are unchanged. No new external calls or background execution model.
- Remaining: frozen IMAP submission/journal, full draft editor handoff, unified
  Outbox, offline startup, live/native acceptance and the broader issue28 scope.

- Independent standards/behavior review identified missing-store recovery and
  cancellation during SMTP. Regression tests reproduced both; schedule metadata
  remains discoverable without staging, and canceled attempts require review.
  Canceling a recoverable schedule also clears its retained draft date, verified
  by a failing/passing persistence assertion. Date-only rescheduling intentionally
  keeps metadata authoritative to avoid rewriting concurrently edited bodies.

- Final local suites: Backend 1,038, Mail 1,546, Gmail 131 and separate Contacts
  6 passed. Dated mock macOS build/startup passed. iOS Mail/Gmail compilation,
  lint, formatter check, privacy audit and diff checks passed before the final
  review fixes; macOS and lint/privacy were rerun green afterward. Final iOS Mail
  rebuild also passed. Native interactions/live-provider sends remain unverified;
  the Mac was locked during the prior native attempt. No UI layout changed, so
  existing inspected scheduled-row snapshots were not re-recorded.

## 2026-09-06 — Codex — Issue #28 / PR #30 IMAP search completeness

- Verified all 20 hosted checks passed on e81ca6d1, the preceding scheduling fix.
- Red tests reproduced ordinary page-only adapters returning unsupported, cached
  hits hiding online results, cache search truncating 120 matches to 50, and
  canceled final responses being returned as success. Generalized existing
  bounded server pagination to ordinary queries, removed paged-result/cache caps,
  retained cache-only privacy, and added final-response cancellation checks.
- Coverage includes empty intermediate pages, duplicate IDs, legacy adapters with
  over 200 candidates reporting incomplete coverage, and ordinary/attachment
  repeated-cursor rejection. The
  full array contract remains; progressive UI and coverage reporting are next.
- Updated CHANGELOG, ADR-0041, privacy/search disclosure, and native QA guidance.
  README setup/provider scope and protected architectures are unchanged. Tests,
  builds and independent review are in progress. No new provider endpoint, body
  fetch for ordinary search, attachment index, merge, or release is included.

- Review found that later-page failures could still fall back to a small cache,
  and ordinary legacy adapters would become unbounded. Red tests reproduced
  both. Later-page/folder failures now report incomplete search; legacy ordinary
  requests remain bounded and report limit exhaustion. Production uses pages.
  Removed the obsolete cache-hit-only diagnostics case and clarified test names.

- Attachment-source failures after a server page are also surfaced as incomplete,
  rather than converted to cache success. Public search/cache enumeration checks
  cancellation after local reads; final canceled responses cannot publish.
- Local verification: Backend 1,042 and Mail 1,546 tests passed before the last
  review delta, with dated mock macOS startup and iOS Mail compilation, lint,
  formatter and privacy checks. Final delta reruns follow below. No layout
  changes or snapshots were added. Native/live large-mailbox performance and
  progressive-result UX remain unverified and explicitly open.

- Final delta verification passed: Backend 1,042, Mail 1,546; dated mock macOS
  build/startup and iOS Mail compilation; lint/formatter, privacy audit and diff
  checks. Separate standards and behavior reviewers cleared the error/cancellation
  fixes. Native/live acceptance and progressive search remain open.
