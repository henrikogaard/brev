# Worklog

## 2026-10-29 — Agent — #269 synthetic optimized selection profiling

- Slice 5 on `feature/selection-profiling`, based on #274, targeting `feature/imap-selective-cache`, eventual main. Added an opt-in Release-only workload over the real navigation projection/selection model, separate signposts/timings and a CI Time Profiler capture script/job.
- Raw traces stay in ephemeral runner storage; only synthetic aggregate timings enter logs. This does not claim full SwiftUI frame/idle-memory acceptance. Space commands recovered, but local:mac-12gb still lacks Xcode; host tests remain deferred.
- Verification before push: shell syntax and diff/ADR checks. Swift compilation and actual profile capture await CI; no profile result or bottleneck claim yet. Instrumentation-only change, no TDD red/green claim. No application defaults, external calls, release, account data or versions changed; README/CHANGELOG/privacy docs need no update. Shared design updated.

## 2026-10-29 — Agent — #269 selective cache consumers and writer retirement

- Branch `feature/imap-selective-cache`, based on #273; target `feature/imap-sqlite-reads`, eventual main. Implementation-first draft stack continues per Henrik's instruction.
- Added selective windows/date/attachment/body query shapes and targeted flag/label/CONDSTORE/date-repair updates. Reconciliation reads affected rows; no-index production caching is memory-only. Moved the historical JSON writer into backend test fixtures and added a production read-only migration reader. Existing cross-store benchmarks seed historical JSON directly.
- Storage helpers no longer decode header JSON to count objects; existing backend metrics report indexed records. Updated fixture counts, lifecycle privacy documentation, accepted ADR implementation note, design and CHANGELOG.
- Added both-store selection and row/window-isolation tests. Diff/ADR checks before push; package/lint/native verification pending the requested review/fix pass. Known inherited formatting issues remain. No host-native test or real-account migration occurred. No performance or merge-ready claim.

## 2026-10-29 — Agent — #269 indexed IMAP read/migration slice

- Branch `feature/imap-sqlite-reads`, based on #272; target immediate parent `feature/imap-page-dual-write`, eventual main. Continuing all implementation PRs before the requested review/fix pass.
- Added account-bound indexed cache adapter, transactional missing-row legacy import and metadata/ID projections. Page cursors and indexed thread inputs no longer require a whole-folder snapshot; cached header lookup is bounded. Legacy data is retained when import fails. Compatibility SQL snapshots remain for the consumers replaced in slice 4.
- Added both-store import tests for newer-row preservation, migrated windows, generation rejection and source cleanup. Checks: diff/ADR before push; focused formatting reports outstanding indentation/loop-wrap issues, deferred to the requested review/fix pass. Package compilation/execution pending CI. No locally observed red run, host app test or real cache migration.
- Updated approved design and CHANGELOG. Privacy posture/network behavior unchanged; local lifecycle remains governed by ADR-0087. Runtime/cutover gates stay open; draft code is not a verified or shipped migration.

## 2026-10-29 — Agent — #269 IMAP page dual-write

- Continued slice 2b on `feature/imap-page-dual-write`, based on #271 at `652242e6`; target immediate parent `feature/imap-page-window-store`, eventual main. Henrik requested implementation PRs for all slices before the review/fix pass; work continues without waiting for each CI run.
- Added the backend-owned page-write capability and engine/store forwarding, with in-memory transaction parity. First and identified older pages use the atomic write; unidentified merges keep ordinary indexing. Legacy JSON remains authoritative and is still written; failed page writes keep the prior fallback.
- Synthetic engine/store tests cover first/older/empty windows, generation rejection and cleanup for both stores. Focused format/lint/diff checks before commit; package execution via CI. No locally observed red run because host native testing remains deferred. No real-account access, read cutover, merge or release.
- Documentation: design detailed contract and CHANGELOG updated. Existing ADR-0087 governs this seam; no new network/privacy behavior, QA evidence report, README or workflow change.

## 2026-10-29 — Agent — #271 legacy migration fixtures

- Fresh CI at `c8a681e8`, run `40781250508`, compiled successfully and passed all seven transactional page-window tests. BrevSyncEngine still failed three existing v4/v5 migration tests because they rewound the current database version without removing the v7 paging column. Other Build jobs passed.
- Corrected those synthetic fixtures to remove `imap_page_windows` and `next_page_token` before stamping the older version. Kept production migration strict; no duplicate-column suppression or data deletion outside disposable test stores.
- Pinned SwiftFormat lint passed for both changed test files; strict SwiftLint passed for AttachmentSearchIndexTests but reported the pre-existing optional-array `references == []` assertion in ConversationIndexTests at line 133. Left that unrelated assertion unchanged. Diff/ADR checks before push; fresh package CI remains required. No host/native tests or real-account operations. Scope remains partial slice 2a, with the runtime measurement gate unresolved.

## 2026-10-28 — Agent — #271 CI compilation correction

- CI at `d9795bb7`, run `40778430918`, failed BrevSyncEngine test compilation because the throwing `imapPageState` expression inside `#require` lacked an inner `try`; the other 20 checks passed. The new tests did not execute in that run.
- Separated the throwing metadata read from the optional requirement so Swift Testing's macro receives a nonthrowing value. No production code or acceptance criterion changed.
- Focused pinned formatting/lint and diff checks are repeated before push; package compilation and all seven page-store tests require fresh CI. Earlier app-build/other-package passes do not override this failed compilation. Host testing remains deferred.

## 2026-10-28 — Agent — #269 transactional page-store foundation

- Continued the approved plan on `feature/imap-page-window-store` in its own worktree, based on #270 at `208960eb`; the dependent PR targets `feature/imap-cache-baselines`, eventual integration main. #269 stays In progress. #270's BrevSyncEngine CI passed at `208960eb`, job `123114265373`, run `40772828311`.
- Detailed slice 2a before code, then added tests for transaction rollback, restart, page replacement, source isolation, cascaded cleanup and v6 migration/retry. Implemented internal schema-v7/page-write/read primitives using the existing header/FTS/conversation transaction. This is groundwork only; backend dual-writing, legacy migration and read cutover remain unfinished. Do not ship schema changes ahead of the outstanding live baseline.
- Verification: focused pinned formatting/lint and diff/ADR checks before commit; Swift package execution goes to CI. Tests were written before implementation, but no compatible permitted local runner was available to observe a red run. No red/green claim is made.
- Retried existing `local:mac-12gb` without creating a Space. Start reported running, but the command tool refused with no cua-spacesd support. Host native testing remains deferred. Usual connection recovery is `cua daemon stop && cua daemon start`; no daemon/security change was made.
- Documentation sweep: CHANGELOG records the schema preparation, and the shared design records the incremental boundary and evidence. No new network/data-deletion path or shipped read behavior means README/privacy docs/QA reports/AGENTS need no change. ADR-0087 already governs this schema and transactional ownership.
- Remaining work: verify CI, wire dual-writes in the next part of slice 2, collect the authorized runtime baseline before cutover, and retain the reader/UI gates. No merge, release, account migration or issue closure performed.

## 2026-10-28 — Agent — #269 synthetic header baseline implementation

- Goal: slice 1 of the approved storage/UI plan. Worktree `imap-cache-baselines`, branch `feature/imap-cache-baselines`, based on design commit `83b0fceb`; dependent PR targets `chore/visual-performance-plan`, whose PR #268 targets main. Issue #269 remains In progress because later slices and runtime gates are unfinished.
- Changes: synthetic 10k/50k JSON-versus-SQLite read suite, fresh readers, four alternating samples, explicit SQLite open/query/total timings and page/metadata parity assertions. Timing assertions are deliberately absent. Existing baseline suites and production behavior are unchanged. Added run/interpretation instructions to performance budgets and updated the shared design.
- Verification: pinned SwiftFormat lint and SwiftLint strict passed for the new suite; diff and ADR gates are checked before commit. Package compilation/execution will run in existing CI. No long host job, app/native test, snapshot or personal-cache access is performed. This instrumentation-only addition skips TDD, as stated in its detailed design.
- Documentation sweep: README, CHANGELOG, PRIVACY, ADRs and AGENTS need no changes because this adds test instrumentation only, with no shipped behavior, privacy or architectural change. Updated existing QA run instructions, not a new QA evidence report.
- Handoff: collect package CI before claiming the suite passes. Slice 1 remains open for the authorized runtime baseline under Q-1. No speedup, migration, merge, release, version change or issue closure is claimed.

## 2026-10-28 — Agent — #269 approved design and baseline slice

- Henrik approved the three-outcome design and requested work to start. Created tracking issue #269 and moved its card to In progress; integration remains main, with design PR #268 and a genuinely dependent baseline slice.
- Marked the design approved/building and wrote slice 1's detailed design before code: one synthetic JSON-versus-SQLite read suite at 10k/50k, alternating fresh readers, explicit open/query timings, functional parity assertions and no CI speed inequalities.
- Plan adjustment: keep the cross-store comparison in BrevSyncEngine tests, whose existing dependency direction permits both stores, rather than add a reverse dependency to BrevBackend. Existing baseline suites remain unchanged.
- Verification: document links, references and diff checks before push; no app, benchmark or snapshot run in this design update. Runtime profiling/host tests remain deferred under Q-1; no schema change, migration, merge or release performed.

## 2026-10-28 — Agent — Visuals/performance implementation design

- Goal: plan all three selected recommendations: ADR-0087 storage work, measured UI responsiveness and visual consistency. Branch `chore/visual-performance-plan` in its own worktree, based on `origin/main` `5ad74c0b`; target `main`. No existing PR covers this combined plan; Settings continues through #265 rather than a duplicate implementation.
- Changes: one Draft design in `docs/specs/2026-10-28-mail-visuals-and-performance-plan.md`, with requirements, ownership/contracts, staged rollout, decision proposals, verification gates and unresolved runtime-environment permission.
- Verification: all eight document links, explicit requirement/decision/question references, Draft status, conflict-marker check, `scripts/check-adr-required.sh`, and staged diff checks passed. Swift lint/format, benchmarks, package tests, builds, app launch and snapshots were not run locally because this slice changes Markdown only; TDD is not applicable. Host native testing remains deferred, and no new runtime evidence is claimed.
- Documentation sweep: README, CHANGELOG, PRIVACY, ADRs, release/QA reports and AGENTS need no change for a Draft coordination plan that preserves existing accepted decisions and changes no behavior. Later slices update their actual changed contracts and evidence.
- Handoff: publish the docs-only PR for review and stop for design approval before Phase 2. No merge, release, app-version change, data deletion or issue closure is authorized by this plan.

## 2026-10-28 — Agent — PR #256 integration review

- Reviewed per-account capability resolution, independent default-off consent switches and device-local persistence. No backend advertises the capability and the controller remains unconnected.
- Integrated the arrival-controller parent, preserving both ADR implementation-status sections, worklog histories, all consent strings and the main Calendar/Contacts/Tasks translations.
- Verification: structured catalog comparison and duplicate-key validation, targeted format and diff checks; updated CI required before merge. Existing iOS snapshots are earlier evidence, not a new runtime run. The Space is unavailable and no host test permission is assumed.
- Documentation sweep: added an Unreleased note for the explanatory Notifications section. No feature activation, new reachable network call, privacy-table change, release or issue closure.

## 2026-10-17 — Devin — #239 consent settings

- Goal: ADR-0088 slice 4 UI: per-account codes/links opt-ins.
- Changed: `SignInCodeSettingsGroup` (BrevSettings) appended to the
  Notifications pane; `NotificationSection` gains
  `signInAssessmentAvailable`, fed by `SettingsView` from the backend's
  extended capabilities; eight new strings with nb translations.
- Verified: iOS `SettingsFormSnapshotTests` 5/5 with new
  `forms.signin-codes-{light,dark,ax3}`; BrevSettings SignInCode /
  Notification / navigation / search suites 69 green; lint/format clean.
- Not changed: no AppSession wiring of `onChange`; PRIVACY.md waits for
  the first enabled provider.

## 2026-10-28 — Agent — PR #255 arrival corrections

- Recheck the specific code/link consent after asynchronous sender lookup, rather than accepting either consent. Already-cancelled work stops before folder/provider reads.
- Remove completed task handles so the controller does not retain every past inspection. Added empty-pending assertions and retained the lock-protected test recorder.
- Verification: targeted format and diff checks before push; updated CI remains mandatory. Regression assertions were added first, but compatible local execution is blocked by the Space toolchain and later network failure; no assertion-level red or local green is claimed.
- No production owner/caller or advertised provider capability is added. Existing ADR-0088 documents the disabled slice; no user-facing/network activation or additional privacy change.

## 2026-10-28 — Agent — PR #255 consent regression

- Review found that withdrawing code consent during sender lookup can still present a code when link consent remains enabled. Added a regression at that await boundary before changing production behavior.
- Protected the test double's concurrent body-read recording with a lock; the burst test previously mutated the same array from nonisolated async calls.
- Verification: diff check; regression execution pending CI. Space CommandLineTools cannot compile Swift Testing/SwiftUI macro dependencies, so no local test pass is claimed.
- Capability remains disabled and no production controller caller exists. No mail sent, account settings changed or live evidence claimed.

## 2026-10-17 — Devin — #239 arrival controller

- Goal: ADR-0088 slices 2 and 3 wiring without UI: a controller that turns
  `.messagesAdded` into memory-only sign-in presentations under every gate.
- Changed: `SignInCodeArrivalController`, `SignInCodePresenting`,
  `SignInCodePresentation` in BrevMail; ADR-0088 status subsection.
- Verified: `swift test --package-path packages/BrevMail --filter
  SignInCodeArrivalController` 9 green (consent before any work,
  capability gate, folder/trust gates, link vs code consent, consent
  recheck mid-flight, cancel/dismiss, burst cap, redaction, plain-text
  only); lint/format clean.
- Not changed: no AppSession owner, root-view caller, panel, settings UI,
  PRIVACY.md (nothing reachable while the capability is off).

## 2026-10-28 — Agent — PR #250 trust corrections

- Excluded initial/reconnect reconciliation from fresh-delivery recording, cleared provenance on connect/disconnect and checked connection generation before returning an assessment.
- Rejected duplicate DMARC tokens and duplicate header.from properties, including duplicates within the same segment.
- Regression tests were written first. Their first CI attempt exposed a test-call compilation error, corrected separately. Assertion-level red evidence was not obtained before correction: CI remains queued, and the Space became unreachable after its incompatible-toolchain failures. Do not count that attempt as red-green verification.
- Verification pending updated CI; targeted format and diff checks are run before push. No capability advertisement, production caller, mail send, privacy/network activation, release or issue closure.
- Documentation sweep: these are corrections to the disabled ADR-0088 implementation, not new user-facing behavior; no additional changelog or privacy-table change is needed.

## 2026-10-28 — Agent — PR #250 trust regression tests

- Review found reconnect catch-up admitted as fresh delivery and duplicate DMARC/header.from tokens accepted inside one segment, contrary to ADR-0088.
- Added regression assertions for both header cases, connect/reconnect exclusion and disconnect invalidation; existing label/time checks now run after a live refresh.
- Local test attempt in local:mac-12gb is blocked: CommandLineTools lacks the Testing module. Regression execution is delegated to CI, not reported as a red pass. Capability activation remains disabled and no mail was sent.
- Next: verify the expected CI failure, make the narrow correction, and require a green rerun before merging.
- First CI attempt did not reach assertions: the new refresh calls omitted the required folder argument. Corrected the test call sites; this compilation failure is not the expected regression evidence.

## 2026-10-16 — Devin — #239 ADR-0088 Gmail trust gates

- Goal: implement the provider-dependent gates of integration slice 1 for
  Gmail API accounts only (ADR-0088 amendment 2026-10-16), stacked on
  `docs/adr-0088-gmail-trust` in worktree `brev-signin-trust`
  (`feature/gmail-signin-trust`, uncommitted).
- Changed: `SignInTrustFailure`/`SignInTrustAssessment`/`SignInTrustAssessing`
  + `.trustedSignInAssessment` (extended capability bit 17, never advertised)
  in BrevBackend; `GmailSignInTrustAssessor`, `GmailFreshDeliveryRegistry`
  (200-entry, 10-minute, in-memory) and `GmailSyncOutcome`/`syncWithProvenance()`
  in BrevGmail; `GmailAPIBackend` conforms to `SignInTrustAssessing` with
  account → registry → label → `internalDate` → metadata-header gates.
  `correspondents` widened to internal for the assessor's mailbox parse.
- No panel, detector caller, settings UI, notification, advertised
  capability, or body fetch; the method is test-reachable only, so
  `PRIVACY.md` and the ADR-0006 network table intentionally unchanged.
- Verified: BrevGmail suite + BrevBackend filtered tests green;
  `scripts/lint.sh`, `scripts/format.sh` (no changes), `git diff --check`,
  `scripts/privacy-audit.sh` — see counts in the session report.
- Next: record E1-E5 in the disposable Gmail mailbox (E2/E3 need Henrik's
  per-run approval — they send real mail), then flip the capability on in
  a later slice.

## 2026-10-28 — Agent — PR #248 integration review

- Reviewed the scoped Gmail proposal and its explicit E1-E5 activation gate under Henrik's request to prepare and merge the open PRs.
- Integrated main and preserved both worklog histories. The amendment does not enable Gmail trust, change account settings or authorize sending test mail.
- Verification: diff and conflict-marker checks; updated-head CI required before merge. Live mailbox evidence is not available and remains required before capability activation.
- Documentation sweep: ADR-only integration; no product or network behavior changed, so no changelog or privacy update is needed for this PR.

## 2026-10-16 — Devin — #239 ADR-0088 scoped Gmail trust

- Goal: record Henrik's 2026-10-16 choice of a scoped Gmail trust model
  for the sign-in panel instead of parking #239.
- Changed: ADR-0088 gains "Amendment 2026-10-16: scoped Gmail trust" with
  the topmost `mx.google.com` trust rule, the Gmail fresh-delivery rule and
  the E1-E5 synthetic evidence table. Generic IMAP stays unsupported.
- Verified: docs-only; `git diff --check` clean. No code touched.
- Next: implement ordered header preservation and the assessment with unit
  fixtures; run E1-E5 in the disposable Gmail mailbox (E2/E3 need Henrik's
  per-run approval because they send mail).

## 2026-10-28 — Agent — PR #264 integration review

- Reviewed no-source presentation, settings handoff, source-change visibility, localized copy and snapshot coverage.
- Integrated main; preserved both sets of changelog and worklog additions. Settings source merged automatically.
- Verification: diff and conflict-marker checks; updated-head CI must pass before merging. Existing native UI evidence is earlier evidence; no additional local app run for this documentation-only conflict resolution.
- Documentation sweep: existing changelog covers the behavior; no new privacy, network or architectural decision. No issue closure or branch cleanup.

## 2026-10-28 — Agent — PR #261 integration review

- Reviewed date-cache bounds, locking, Release test guards, sidebar selection and lazy context menus against current main.
- Integrated main; resolved only the additive worklog conflict and preserved both histories. Code merged automatically.
- Verification: diff and conflict-marker checks; updated-head CI is the merge gate. No new local build or UI run, because the integration changes no behavior beyond the reviewed PR. Existing profiling and UI evidence remains earlier evidence.
- Documentation sweep: no new product, privacy or architecture change; existing PR documentation remains applicable. Do not close issues or delete branches.

## 2026-10-17 — Devin — #11 Google recurring create fix

- Found during the iOS live pass: creating a daily series on the Google
  calendar with the editor's default "Lokal (flytende)" time zone failed
  with "Leverandøren returnerte et svar Brev ikke kunne bruke"; a
  non-recurring event with the same settings saved fine.
- Cause: Google requires `start.timeZone`/`end.timeZone` on timed recurring
  events and answers 400, which `GoogleCalendarEventWriter` maps to
  `invalidResponse`.
- Changed: the writer pins a floating timed recurring event to the injected
  `localTimeZone` (device zone by default); single floating events are
  unchanged.
- Verified: `swift test --package-path packages/BrevCalendar --filter
  PIMEventWrite` 39 green (new `googleFloatingRecurrenceGetsTimeZone`);
  lint/format clean. Live retest pending a rebuilt simulator app.
- Observation: a 400 from Google surfaces as a generic "response Brev could
  not use"; the provider's error message is dropped. Not changed here.

## 2026-10-17 — Devin — #11 v8 addendum (iOS Google create + DAV lifecycle attempt)

- Goal: extend v8 with the second-session iOS legs and record the
  recurring-create defect found live.
- Changed: addendum table + O17-O19; two screenshots
  (`ios-google-recurring-create-error`,
  `ios-settings-google-event-cached-after-create`, both downscaled).
- Verified: `check-live-evidence-redaction.sh` clean over the evidence dir.
- Not run: DAV invalid-credential row — Norwegian keyboard mangles URL
  characters under `idb ui text`; noted the workaround for the next pass.

## 2026-10-17 — Devin — #11 live parity v8

- Goal: first live pass on the ADR-0089 projection fix against a real
  CalDAV server (Radicale) with new `QA-1016-` fixtures.
- Result: `docs/qa/pim-parity-v8-2026-10-17.md`; 7 rows Pass on iOS
  (daily/weekly projection, third-occurrence detail, first-occurrence
  editability, EXDATE collapse with coverage note, outage recovery), macOS
  rows Not run/Blocked (accessibility automation unavailable; Fetch schedule
  Manual), Google and lifecycle rows Not run.
- Observations O13–O16 recorded (exception handling gap, permanent stale
  banner, pre-#251 overlap, pre-#252 sticky notice).
- Verified: `scripts/check-live-evidence-redaction.sh` OK on the evidence
  folder. Docs-only; no code changed.

## 2026-10-17 — Devin — #11 recurrence exceptions (ADR-0089)

- Goal: close observation O13 from parity v8: one EXDATE collapsed a series
  to its master date.
- Changed: `PIMRecurrenceDescriptor.exdates` (verbatim bodies; tolerant
  decode), ICS and Google adapters capture them (Google `EXDATE;TZID=…`
  entries were previously classed as unrecognized), validator parses
  exclusions per basis, projector skips excluded/overridden slots while
  still consuming COUNT, moved instances render raw, cancelled markers
  render nothing, in-window unmatched exceptions fail closed.
- Verified: `swift test --package-path packages/BrevCalendar` 302 green
  (new EXDATE/exception tests, two existing tests updated to the new
  semantics); BrevMail calendar suites green; format clean; lint passes
  with the ADR-0089 status update.
- Not changed: RDATE, future-scope writes.

## 2026-10-16 — Devin — Calendar & Contacts settings layout

- Goal: Henrik flagged the Settings → Calendar & Contacts sources pane as
  rough during the #11/#14 live QA setup.
- Changed: `PIMSourcesSettingsView` gives each source switch its own
  full-width row, puts collections under a kind heading ("Calendars",
  "Contact groups", "Task lists") as single-line rows with inline
  primary/read-only markers, uses one switch size, folds the cached count
  into the status line, and skips the macOS-only Divider inside the iOS
  Form. Fixed a stray BEL control character in the nb "Background sync
  for %@" accessibility label. Google system contact groups stay listed
  (Henrik's choice).
- Verified: `swift test --package-path packages/BrevSettings --filter
  PIMSource` (35 passed); iOS `SettingsFormSnapshotTests` 5/5 with new
  `forms.pim-sources-{light,dark,ax3}` baselines; macOS layout checked in a
  live Brev Test build; lint and format clean.
- Note: on-state switches use `theme.accent`, which is greyscale in the
  default theme, so on and off differ mostly by knob position. Not
  changed here; it is a theme-wide decision.

## 2026-10-16 — Devin — Calendar deep-link notice

- Goal: Henrik saw "That event is no longer synced" stuck on an empty
  Calendar window in the live QA build.
- Cause: the notice comes only from a `brev://event` link whose record is
  not cached (both QA calendars were empty), and nothing ever cleared it.
- Changed: `CalendarBrowsingModel.dismissDeepLinkNotice()`; navigation,
  view-mode changes and a new selection clear the notice; the banner gets
  a close button ("Dismiss"/"Lukk").
- Verified: `CalendarBrowsingModel` suite 23 passed (new
  `deepLinkNoticeClears`); lint/format clean. The `detail-*` snapshot
  mismatches seen locally reproduce on clean `main` (host drift).
- Not changed: Contacts and Tasks have the same never-cleared notice.

## 2026-10-16 — Devin — AGENTS.md evidence-report rule

- Goal: stop sessions from producing new versioned QA reports for #11/#14
  when no new live evidence exists (Henrik, 2026-10-16).
- Changed: `AGENTS.md` gains "Evidence reports need new evidence".
- Verified: docs-only; `git diff --check` clean. No code touched.

## 2026-10-16 — Devin — #11

- Goal: implement ADR-0089 bounded calendar occurrence projection so
  repeating events render every date in the agenda, day, week, and
  month surfaces instead of only the stored DTSTART.
- Changed:
  - `BrevCalendar`: `PIMRecurrenceDescriptor` (lossless RRULE/RDATE/
    EXDATE + DTSTART basis), `recurrenceDescriptor` and
    `seriesMasterItemKey` on `PIMEvent`, `ICSParser`/`PIMDAVEventSync`
    descriptor capture, `GoogleCalendarEventSync` descriptor mapping
    and cancelled-instance markers, the strict `PIMRecurrenceValidator`,
    and the bounded `PIMOccurrenceProjector` with stable row IDs,
    DST-safe generation, and defensive bounds.
  - `BrevMail`: browsing model, grid layout, presentation helpers, and
    agenda/day/week/month views now consume `PIMEventOccurrence`;
    occurrence-aware selection retains the authoritative master; the
    agenda is a navigable 30-day range; later occurrences are read-only
    with a localized note and incomplete series get a coverage note
    (en + nb).
  - Docs: ADR-0089 implementation-status section, CHANGELOG entry.
- Review fixes applied: occurrence indices are ordinal (`emitted`
  position), so a weekly BYDAY starting mid-week and skipped monthly
  dates keep index 0 on the series start; the detail pane renders the
  selected occurrence's projected date via `occurrence:` on
  `CalendarEventDetailView`; the xcstrings file was restored and now
  carries only the two new keys (+22/0).
- Verified: `swift test --package-path packages/BrevCalendar` — 297
  tests green; BrevMail filtered suites (CalendarBrowsingModel,
  CalendarGridLayout, CalendarEventPresentation,
  PIMNativeChromePresentation, CalendarEditingModel, plus the two new
  detail-note snapshots — 81 tests) green; `scripts/lint.sh` and
  `scripts/format.sh` clean; `git diff --check` clean; unsigned xcodebuild
  builds of BrevMacOS and BrevIOS succeeded in the worktree.
- Snapshot baselines: the pre-existing `detail-*` and `month-*`
  references also mismatch on a clean `main` checkout on this host, so
  they were not re-recorded; only the four new note snapshots
  (`detail-later-occurrence-*`, `detail-incomplete-series-*`) were
  recorded.
- Next: commit + PR when the maintainer allows pushing.

## 2026-10-13 — Agent — Demo screenshots

- Goal: save demo screenshots of the iOS and macOS apps to the repository.
- Changed: added `docs/screenshots/` with six PNGs — macOS mail window and
  iOS inbox/reader, each in light and dark — and a `## Screenshots` section
  in `README.md` that switches them via `<picture>` + `prefers-color-scheme`.
- How they were captured: test builds in mock mode (`Brev Test` via
  `script/build_and_run.sh --mock`, `SIMCTL_CHILD_BREV_USE_MOCK=1` on an
  iPhone 17 iOS 27.0 simulator). macOS window captured at 1440x900 with
  `screencapture -l<WID>`; iOS via `simctl io screenshot` with the status
  bar overridden to 9:41 / full battery.
- Verified: images render; README markup follows GitHub's documented
  light/dark `<picture>` convention. Docs-only change — `scripts/lint.sh`
  and `scripts/format.sh` still run before the PR.
- Handoff: retake `docs/screenshots/*` when the shell changes materially;
  capture recipe is in this entry and in `.agents/skills/testing-brev-ui`.

## 2026-10-12 — Agent — iOS beta release script

- Goal: send an iOS beta to TestFlight with one command, as Catchlog does
  (`feature/ios-beta-release`). macOS release untouched.
- Changed: `scripts/release-ios-beta.sh` wraps the manual recipe in
  `docs/release.md`; `scripts/testflight-distribute.mjs` (copied from
  Catchlog, with a command-line entry) sets the notes and the optional
  external group; `scripts/test-release-ios-beta.sh` runs in `scripts/test.sh`.
- Decision: no Actions workflow. The repository is public, so a self-hosted
  runner on the release machine would run fork pull-request code next to the
  signing keys. The script is started over SSH instead; a public repository
  can be fetched there without the GitHub login.
- Decision: external-capable export by default (Henrik, 2026-10-12);
  `--internal-only` keeps the old policy.
- Verified: `scripts/test.sh --self-tests-only` and shellcheck locally;
  `--dry-run --current-checkout` on the Mac mini over SSH at `b7f85a0`
  (gates, launch regression, demo guard, archive, archive checks, local
  export). Nothing uploaded, no build number taken, checkout clean after.
- Found by the first dry run: xcodebuild echoes the settings of an
  `-xcconfig` file, so the provider settings were printed. The script now
  masks those lines; the rerun's log holds none of the values.
- Found by CI: `plutil` on the macOS 15 runner prints its "no value" error on
  stdout, which failed the script test there. The script and the test now go
  by exit status.
- Skipped: a real upload and the TestFlight follow-up (needs a release
  request); `scripts/lint.sh` and `scripts/format.sh` (no Swift changed).
- Handoff: the Mac mini has `~/.brev-ios-release/release.env` and the release
  checkout `~/Dev/Repos/.worktrees/brev/release`, which sits on this branch
  until the PR is merged.

## 2026-10-10 — Agent — Slice 8b iOS PIM chrome (findings P1-P4)

- Goal: native iPhone Calendar, Contacts and Tasks chrome, empty states and
  task editor (`fix/ios-pim-native`).
- Changed: shared "no sources" state with a button that opens Settings →
  Calendar & Contacts (new `SettingsView(pushesInitialSection:)` entry point,
  `BrevApp.openSettingsFromPIMCover`); Calendar layout menu, range title, +,
  Today, previous/next and sync moved into the navigation and bottom bars;
  month cells are single buttons with event dots and a label listing events;
  event blocks speak title, time and place; Dynamic Type scaling for the grids;
  `TaskEditorView` is a Form sheet on iOS; task rows split the completion
  switch from the text, 44 pt target, "Overdue" word; task delete asks first;
  Done is trailing and textPrimary on all three covers; PIM editor sheets use
  `brevSheetAppearance`. macOS windows unchanged (month grid and task editor
  macOS renders byte-identical to main).
- Verified: presentation tests (macOS `swift test`), iOS package build,
  iOS snapshots recorded on iOS 27, simulator walk-through with a seeded cache.
- Checkpoint commit: nb/dark/AX3 simulator screenshots, per-screen audit
  results and docs/qa evidence folder still to do.
- Observation (pre-existing, not fixed): tapping "Add DAV Source…" in
  Settings → Calendar & Contacts closes the whole Settings sheet in the iOS
  mock-mode simulator, also on main.

## 2026-10-03 — Agent — Issue #11 stub-DAV rows 2.7/2.8/4.3

- Goal: close the stub-matrix rows left open by the #3 reconciliation
  (2.7 attendee add/remove, 2.8 RSVP round-trip, 4.3 idle background
  pickup) with an iOS simulator pass against `scripts/stub-dav-server.py`.
- Run: `main` @ ed631a71, iOS Debug (mock mail, 5-min fetch), iPhone 17 Pro
  sim iOS 27.0, authed stub on :8643 seeded with the canonical seed plus a
  Hytte invite matching the mock mailbox's invite UID.
- Results: 2.8 ✓ (accept/maybe/decline each a chained If-Match PUT → 204;
  remote PARTSTAT ACCEPTED/TENTATIVE/DECLINED). 2.7 ✓* (attendee add and
  remove each PUT → 204 and reflected remotely; stub has no CalDAV
  scheduling, so live invite delivery stays with the live fixtures). 4.3 iOS
  ✓ (Background sync ON → injected event picked up by unprompted REPORTs at
  the 5-min cadence; verifies the #135 O3 fix). macOS legs not re-run.
- Changed: `docs/qa/pim-parity-matrix.md` rows 2.7/2.8/4.3, O3 status, new
  O7–O12 summary; new evidence dir `docs/qa/pim-parity-stub-dav-2026-10-03/`
  (screenshots, wire log, ICS before/after, README with observations).
- Observations (not fixed): raw `missingCredential` in the source row; RSVP
  strings unlocalized; attendee PUTs omit ORGANIZER under `METHOD:PUBLISH`;
  attendee field skips address validation; iOS dark-theme contrast on agenda
  titles and event sheets; Settings cached-event count stale after background
  sync.
- Skipped (evidence pass): package tests (no code touched until the O11
  follow-up below).
- Follow-up fix (same PR, #187): O11. The iOS Calendar/Contacts/Tasks
  full-screen covers and the macOS Calendar/Contacts/Tasks windows sat outside
  `.brevRootAppearance`, so they rendered the default `brevMonoLight` theme
  under a dark system appearance; each now applies the modifier. The stale
  banner's "Last updated" catalog key held raw `\(…)` source; rekeyed to
  `Last updated %@` with a guard in `MailStatusCopyLocalizationTests`
  (red → green). Verified on the sim (`ios-40`/`ios-41`); macOS compile only.
- Found: 168 catalog keys still use raw `\(…)` interpolation source (118
  BrevMail, 50 BrevBackend), so those strings never localize. Each needs its
  proper `%@`/`%lld` specifier; left for a follow-up.
- Handoff: live Google/CalDAV/CardDAV fixtures, macOS 2.7/2.8/4.3 re-runs and
  physical-iPhone QA still need Henrik. Observations O7–O10 and O12 are
  candidate follow-up issues.

## 2026-10-05 — Agent — IMAP trailing-UID literal compatibility

- Goal: make message bodies readable when a server returns the UID after
  the BODY literal, reproduced with Microsoft Exchange.
- Changed: consume the declared literal bytes before validating UID metadata
  from the same FETCH response. Stop collecting metadata at the response's
  close marker so later unsolicited updates cannot supply the requested UID.
  Raw-source and structured-part fetches share the completion validation.
- Verified: trailing-UID success cases failed before the fix; all 93
  IMAPSessionClientTests pass afterward. Regression cases cover exact byte
  preservation, wrong trailing UIDs with UID-looking body text, and later
  unsolicited responses. Full lint passes; format reports zero changed files.
  A dated macOS live test build installed and passed strict signature
  verification; the previously failing work message rendered successfully.
- Documentation sweep: CHANGELOG updated. No new network operation, public
  boundary, protected path, UI, setup contract, or privacy behavior changed;
  README, ADRs, PRIVACY, and UI snapshots need no update.
- Skipped: sending mail (not requested) and the full multi-package/iOS test
  matrix (narrow internal parser change; PR CI covers broader integration).
- Handoff: PR targeting main; upstream maintainer review/merge required.
  Personal OAuth configuration and live mailbox data remain outside Git.

## 2026-10-07 — Codex — PR #197 release signing recovery

- Goal: finish Developer ID app/widget provisioning and recover the existing v0.2.0 tag.
- Apple setup: registered stable/nightly macOS widget IDs, assigned the existing `group.eu.brevmail.brev` to all four app/widget IDs, regenerated the two app profiles, and generated two widget profiles. Validated active Developer ID profile type, team, exact bundle ID, App Group, expiry, and SHA-256 certificate match before uploading all four environment secrets to `release-signing`. Downloaded copies are in Henrik's Downloads folder.
- Fixed the open review finding: Release loads the signing action from `github.workflow_sha` after checking out the product tag. Product HEAD stays on the tag and setup/cleanup both use the repaired action.
- Verification: regression fixture failed before the workflow change; passes afterward and verifies current action content, unchanged tag HEAD, invalid revision rejection, tag format, ancestry, and green Build gates. Actionlint and Developer ID configuration self-test passed.
- Integration: merged current main after #196; retained both release-recovery and author-correction worklog entries.
- Scope: configuration only; no new Swift/UI tests or product build locally. Hosted signed archive/notarization is the remaining release verification. Existing ADR-0009/ADR-0080 distribution policy is unchanged; release runbook updated. README/privacy/agent instructions need no update.

## 2026-10-07 — Devin — Release recovery: widget profile + Sparkle key rotation

- Goal: produce the signed 0.2.0 release after moving to `release-signing` (#195).
- Findings: recovery dispatch 37629206211 reached the signed-archive step and failed with "No profile … matching 'Brev Stable Widgets Developer ID CI Distribution'". The widget extension (#144, ADR-0083) needs its own Developer ID profile that CI never installed. The 0.1.0 app profile also lacks the `group.eu.brevmail.brev` app-group entitlement.
- Changes: the `release-signing` action takes `widget-profile-base64`, verifies its team and certificate fingerprint, and exports `BREV_WIDGET_PROVISIONING_PROFILE_SPECIFIER`; the Release and Nightly workflows pass `BREV_MACOS_WIDGET_PROFILE_{STABLE,NIGHTLY}_BASE64`; release.md gets the portal and secret steps. At Henrik's request the Sparkle key was rotated: the new private key and public key (`bmBu…`) are set in `release-signing`. The original public key (`aFO3…`, embedded in 0.1.0) has no recoverable private half.
- Verification: actionlint, `scripts/test-developer-id-release-config.sh`, `git diff --check`.
- Next (Henrik): portal work to create the widget App IDs and profiles and regenerate the app profiles with App Groups; upload the four profiles; re-dispatch Release for `v0.2.0`.
## 2026-10-07 — Devin — Author name correction

- Henrik's name is "Henrik Øgård": fixed LICENSE, NOTICE, llms.txt and the ADR-0009 account-holder line. Apple signing-identity strings in ADR-0009, docs/release.md and scripts/release-archive.sh are left as-is because they must match the certificate common name.
- Verification: `git diff --check`.

## 2026-10-07 — Devin — Release environment startup probes

- Goal: find why `v0.2.0` release runs (and every nightly since Sep 23) fail with "job was not started because it repeatedly failed to be acquired".
- Added `ubuntu-release`, `ubuntu-probe-environment`, `macos-15-probe-environment` jobs and a push-to-main trigger (PAT cannot dispatch). Branch run: plain macOS and the fresh `runner-probe` environment start on both Linux and macOS; `release` jobs were rejected by branch policy as expected off main.
- Verification: actionlint, `git diff --check`.
- Next: the main run shows whether `release` fails on Linux too.

## 2026-10-06 — Devin — Stable release 0.2.0 prep

- Goal: Henrik asked for a stable 0.2.0 release installed on the dev Mac, as the baseline for a later Sparkle auto-update test.
- Changes: `BrevConstants.marketingVersion` and the committed project `MARKETING_VERSION` bumped 0.1.0 → 0.2.0; the accumulated `[Unreleased]` CHANGELOG notes became `## [0.2.0] - 2026-10-06` (required by `release.yml`), with a fresh empty `[Unreleased]`.
- Verification: format, lint, `git diff --check`; release itself is produced by `release.yml` on the `v0.2.0` tag after this merges.
- Next: tag `v0.2.0` on main once Build is green, install the notarized DMG as `/Applications/Brev.app`, then tag a follow-up release to exercise Sparkle updating 0.2.0.

## 2026-10-05 — Agent — Interpolated string-catalog key rekey

- Goal: finish the localization follow-up PR #187 flagged — 168 catalog keys
  (118 BrevMail, 50 BrevBackend) held raw `\(…)` interpolation source, which
  the `String(localized:)` runtime never looks up; Norwegian UI silently fell
  back to English for every one of them.
- Changed: rekeyed every `\(…)` catalog entry to the format specifiers the
  runtime generates — `%@` for String-like interpolations, `%lld` for the
  confirmed Int sites (`*.count`, `code` status codes, time deltas,
  `pendingUndoSendCountdown`, `Int(retryAfter.rounded())`, `rule.interval`,
  `draft.repeatInterval/repeatCount`, `overflow`, `selectionCount`, etc. —
  each verified against its call site). Same specifier rewrite applied inside
  nb translations. 44 rekeys landed on already-correct `%` keys and were
  deduped (keeping the hand-maintained translations); one stale
  `Google rejected the token exchange%@ (HTTP %@).` entry whose code slot
  mismatched the Int call site was removed. Zero `\(…)` keys remain.
- Tests: new `no catalog key keeps raw string-interpolation source` guard in
  `MailStatusCopyLocalizationTests` (BrevMail) and a new
  `BackendCatalogKeyFormatTests` suite (BrevBackend) scan the whole catalog so
  the pattern cannot regress.
- Verified: both suites pass on the rewritten catalogs (4/4 BrevMail, 2/2
  BrevBackend); the pre-existing nb status-copy and plural tests stay green;
  `xcodebuild -scheme BrevMacOS` compiles every catalog through xcstringstool
  and builds clean; swiftformat --lint and swiftlint clean on touched files.
  Catalog-vs-runtime key convention cross-checked against BrevGmail's working
  `HTTP %lld` entries (Int `statusCode` call sites).
- Post-push fix (found by UI test run): the rekey made `All folders in %@`
  and `all folders in %@` — case variants that generate the same
  `allFoldersIn(_:)` symbol and fail xcstringstool. The lowercase pair only
  fed the English mailbox-chat AI prompt (`scopeDescription`), so it is now a
  plain non-localized string; `all folders in the current account` lost its
  only call site and was removed from the catalog. Added a
  `no two catalog keys generate the same symbol` guard (approximates
  xcstringstool's key→symbol normalization) to both catalog test suites so a
  case/punctuation-variant key pair cannot regress.
- Verified live: testing run rebuilt the app on macOS + iOS sim with
  `-AppleLanguages nb` — `9 meldinger · 5 uleste`, `4 vist · 9 totalt`,
  `Sorter og filtrer, 2 filtre aktive`, `1 skjulte leste meldinger`, `+2 til`
  all render Norwegian where English leaked before.
- Skipped: undo-send countdown and attachment-header strings unverified live
  (no mock reachability); signing/cert build steps are CI's domain.
- Handoff: PR #189 to `main`; no merge without Henrik's authorization.

## 2026-10-06 — Devin — Settings flush-left pass (PR #191)

- Goal: Henrik flagged leftover left gaps (rows indented under group headers; Settings sidebar categories indented vs search field and Extensions).
- `SettingsGroup` no longer indents its rows by the symbol column — rows, previews, segmented controls and callouts share the header's left edge.
- macOS Settings sidebar: category and extension rows share one selection-pill style whose edges match the search field; extension icons use the shared symbol width and secondary tint; Extensions header aligns with row icons.
- Verified: `scripts/format.sh`, `scripts/lint.sh`, macOS `script/build_and_run.sh --mock` + rendered sidebar, iOS 27 simulator build.
- iPhone follow-up: Settings extension rows use the category rows' insets/height; mail sidebar Favourites/Smart Views/Accounts headers use the Apps header inset so headers line up with card rows.
- Folder Sync table header/rows drop their extra horizontal padding and use `SettingsSymbol`; Google placeholder row uses the shared symbol column and body title.

## 2026-10-06 — Devin — Settings alignment follow-up (PR #191)

- Goal: fix the live-QA alignment findings from the first pass (macOS Compose/Auto-Reply, iPhone large and accessibility text).
- Symbol column widened to 24 pt; `SettingsSymbol` steps wide glyphs (Abc, signature) down a scale instead of overlapping titles; Settings section lists reuse `SettingsSymbol`.
- iOS menu pickers offset the native button padding (`SettingsLayout.menuButtonInset`) so values end on the switch edge inline and start on the title edge when stacked; iOS pickers no longer `fixedSize` so stacked menus stay inside the pane.
- Compose "Manage recent recipients" is a custom disclosure row on the shared icon/title/trailing columns; Auto-Reply date pickers use label + trailing control rows; Notifications Authorization row stacks when it does not fit; Appearance Accent stays inline beside the label on iPhone at non-accessibility sizes.
- Verified: `scripts/format.sh`, `scripts/lint.sh`, `swift build`, iOS 27 simulator build + rendered Compose at large and accessibility-extra-large, macOS `script/build_and_run.sh --mock` build.
- Known: `mailStorageCacheLookbackSelectionStaysReadableInLightTheme` fails only in the full BrevSettings run (passes in isolation) on this host, identically on the previous commit — order-dependent pixel probe, not caused by this change.

## 2026-10-06 — Devin — Settings alignment pass (PR #191)

- Goal: make Settings text, icon and option columns line up consistently on macOS and iOS.
- Added `SettingsLayout` (20 pt symbol column, shared stacked-control indent, trailing popup slot, density-aware pane inset) and routed `SettingsGroup`, `SettingsRowLabel`, `SettingsSymbol`, picker/segmented rows, callouts, `SectionScaffold` and `SettingsView` headers/section lists through it.
- Appearance Accent/Themes now reuse `SettingsRowLabel`; Mailbox View preview moved inside the Mailbox list group; notification badge rows use distinct symbols.
- macOS popups hug their value and share the switches' trailing edge; iPhone picker rows wrap the label beside a hugging menu like switch rows, stacking only at accessibility sizes.
- Verified: `scripts/format.sh`, `scripts/lint.sh`, `git diff --check`, BrevSettings non-pixel tests (420 passed), `script/build_and_run.sh --mock` macOS build + rendered review of all panes, iOS 27 simulator build + rendered Compose at default and accessibility-extra-large text (content size restored to `large`).
- Skipped: pixel snapshot suites (pre-existing renderer drift on this host, see entry below); `tuist build BrevMacOS` fails here without `-skipMacroValidation` while the repo build script succeeds.

## 2026-10-06 — Devin — Appearance, navigation and performance assessment fixes

- Goal: implement Henrik's sidebar/Settings/accent assessment without removing
  destinations or mistaking mock timings for daily-driver readiness. Branch
  `fix/appearance-navigation-performance`, targeting `main`; no matching issue/card.
- Changed: shared root appearance across macOS windows; explicit Theme/System/Custom
  accent sources with legacy migration and preserved custom values; contrast-safe
  effective accents and filled-button foregrounds; adaptive Settings navigation and
  large-text controls; clearer mailbox scope, Accounts/Apps headings and neutral
  management menus. Appearance remains device-local per ADR-0056.
- Measurement changes: collector requires PID and run start; summaries distinguish
  visible body opening from fetch/render and launch from list reload. Budget output
  requires attributed cached workloads and 20 logged samples; external launch,
  scrolling and memory measurements stay explicit and missing evidence fails closed.
- Verified so far: 13 BrevThemes tests, 36 focused BrevSettings tests, six Python
  regression tests and performance-budget self-test. Final compilation, formatting,
  lint and visual regression checks are pending; results will be appended before push.
  Model/parser regressions were added alongside implementation rather than a separate
  red-first TDD cycle.
- Documentation sweep: ADR-0048, CHANGELOG, performance QA protocol and this log.
  No README/setup, privacy/network, version/release or agent-policy changes.
- Limits: representative two-account/10k-header Instruments evidence, physical-phone
  performance and live-provider provisioning/sign-off remain unverified. No merge,
  release, daily-driver replacement or issue closure is authorized.

## 2026-10-03 — Agent — Issue #3 PIM parent status reconciliation

- Goal: advance the provider-neutral Calendar/Contacts parent issue (#3) to
  its remaining gates without new implementation.
- Findings: the architecture gate the issue required is already satisfied —
  ADR-0072 (Accepted 2026-09-20) supersedes ADR-0039's authoring boundary;
  ADR-0084 (offline PIM write queue) is Proposed follow-up scope with no
  implementation in BrevCalendar/BrevMail yet. Sub-issues #4–#10, #12, #13,
  #15 are closed and Done; #11 parity QA (Backlog) and #14 Drive picking
  (In review) remain the open items.
- Verified: `swift test --package-path packages/BrevCalendar` — 257 tests in
  25 suites green on main content (14113dac + test-only 24de7e0a, run in the
  /private/tmp/brev-flake-fix worktree).
- Changed (GitHub-side only): refreshed issue #3's delivery-state section to
  2026-10-03 and commented with the evidence; board #3 Backlog → In
  progress → In review.
- Skipped: live Google/DAV QA (needs Henrik-provisioned disposable Google
  Workspace account and a DEVELOPMENT_TEAM-signed iOS build — #11 scope);
  stub-matrix rows 2.7/2.8/4.3 stay open until a dedicated serve-sim QA pass.
- Handoff: #3 closure waits on #11 live parity evidence and Henrik's
  sign-off in docs/qa/pim-parity-matrix.md. No merge without Henrik's
  authorization.

## 2026-10-03 — Agent — CI flaky-test triage and timeout fixes

- Goal: triage the three rerun-after-failure CI events from 2026-10-02 and
  fix what is actionable in the repo.
- Findings: PR #182's `test (BrevCrypto)` failure was `actions/checkout`
  DNS (`Could not resolve host: github.com`, three fetch retries exhausted;
  run 37015131553 attempt 1) — runner infrastructure, no repo change. PR
  #177's `test (BrevBackend)` was `older IMAP page reload emits updates
  for changed cached headers` hitting the 1s `nextIMAPEvent` default
  timeout (run 37000697020 attempt 1, IMAPSMTPBackendTests.swift:3287).
  PR #184's `test (BrevMail)` was `WorkflowNavigationReconciliationTests`
  post-undo restore exceeding its 1s poll budget (run 37059283658 attempt 1,
  WorkflowNavigationReconciliationTests.swift:126).
- Changed: `nextIMAPEvent`/`nextIMAPEventSkippingProgress` default timeout
  1s → 5s (explicit call-site timeouts unchanged); the reconciliation test's
  post-mutation and post-undo polling loops 50 → 250 × 20ms. Both only raise
  the wait ceiling; promptly-settling tests run as fast as before.
- Verified: focused suites pass locally
  (`swift test --package-path packages/BrevBackend --filter
  olderIMAPPageReloadEmitsUpdatesForChangedCachedHeaders`;
  `swift test --package-path packages/BrevMail --filter
  WorkflowNavigationReconciliation` — all six cases); `scripts/lint.sh` OK.
- Skipped: full package suites locally (CI runs them on the PR). Test-only
  change: no CHANGELOG, ADR, or snapshot impact.
- Handoff: PR to `main`; no merge without Henrik's authorization.

## 2026-10-02 — Agent — Density call-site wiring follow-up

- Goal: complete ADR-0085's implementation. A code review found that PR #180
  merged the `MailboxListDensity.platformDefault` enum and its tests, but the
  twelve `@AppStorage` call-site edits its description promised were never
  committed; on `main` a fresh macOS install still opened Comfortable.
- Changed: all density `@AppStorage` defaults now read
  `platformDefault.rawValue`; the settings-preview default in
  `MailboxViewSettings` uses `platformDefault` so the preview matches the
  shipped start state; ADR-0085 is Accepted with a delivery note.
- Verified: see the PR description. Snapshot suites set density explicitly
  and are unaffected by the default change; two unit assertions that pinned
  the old Comfortable default now assert platformDefault per ADR-0085, and
  the mail-storage contrast smoke test pins its layout density to Comfortable
  because its hard-coded pixel rectangle targets that layout.
- Handoff: follow-up PR to `main`; no merge without Henrik's authorization.

## 2026-10-02 — Agent — Mail list row performance and blocked-sender freshness

- Goal: code-first performance audit of the mail hot paths, then land the
  concrete fixes it justified.
- Audit result: the list pipeline is already well optimized — presentation
  snapshots are cached with full invalidation keys, date formatters are
  static-cached, thread counts are precomputed, and signpost instrumentation
  covers list build, reload, search, message open, and body render. The two
  real findings: `MessageListRowIndicator.indicators(for:)` was rebuilt at
  two call sites per row render, and the blocked-sender set was loaded once at
  view init and never rebuilt, leaving the "Blocked sender" indicator stale
  after an unblock in Settings.
- Changed: rows derive status indicators once per render pass; the indicator
  factory reserves its capacity; `BlockedSendersSettings.save` now posts
  `brev.blockedSendersDidChange` and the message list rebuilds its lookup
  set on that notification, matching the `brevFollowUpDidChange` pattern.
- Verified: see the PR description.
- Handoff: stacked slice PR targeting the density branch; no merge without
  Henrik's authorization.

## 2026-10-02 — Agent — Visual review batch (16 items)

- Goal: land the 2026-10-01 hard critique batch.
- Merged: #169 (mail toolbar hover help), #170 (settings popups on one
  trailing column), #171 (macOS Send as a real button), #172 (appearance
  resolved once at the root), #173 (settings layout polish: callouts fill
  their row, pane headings stop repeating the tab, Mailbox View flattened,
  680-point column), #174 (macOS list header), #175 (unread bar instead of a
  second circle), #176 (favourite shortcuts use filled glyphs), #177 (one
  heavy weight per row, date counts beside their labels), #178 (Favourites
  start with All Inboxes only, Smart Views header uses a text action), #179
  (row status glyphs beside the subject, hairline between rows), #180
  (desktop starts in Compact density, ADR-0085), #181 (reader actions on the
  trailing edge).
- Documentation note: each branch's own WORKLOG/CHANGELOG edit was dropped
  when the branches were merged onto the landed stack, because twelve of them
  edited the same two files and could not merge otherwise. This entry and the
  CHANGELOG block below carry the batch's documentation.
- Resolved without a code change, reasons in the individual PRs: chevrons on
  favourite rows (iOS drill-in affordance), the root back control (the leading
  control is a forward action and the list is always pushed), footer versus
  header (counts versus identity), the sidebar focus hand-off (deliberate
  Apple Mail parity), settings navigation depth (only Mailbox View nested),
  and segment-versus-picker alignment (the house rule, applied consistently).
- Verified: every PR reached 21/21 on its exact head before merge; local
  builds, focused suites, format and lint ran per branch.
- Skipped: pixel-baseline re-records — those suites are deferred in CI
  (macOS 15 runner, iOS 26.2 runtime) and this host is macOS 27, so recording
  here would replace macOS-26 baselines.

## 2026-10-01 — Agent — macOS message-list header

- Goal: item 8 of the 2026-09-30 visual review — the desktop message list had
  no visible mailbox title; the name and counts appeared only in the bottom
  status row ("9 meldinger · 5 uleste"), while iOS shows them in its
  navigation bar.
- Changed: added `messageListHeader` (macOS only) above `MessageListView` in
  the list column, mirroring the iOS header — mailbox name on the first line,
  account or smart-view context on the second, in the theme's headline and
  caption styles.
- Verified: rendered the window before and after (`Brev Test (2026-10-01)`);
  before, the list column's first row sat directly under the toolbar with no
  title; after, the header carries "Innboks" plus "Henrik Øgård (work)".
  `swift build --package-path packages/BrevMail`, `BrevMailNativeToolbar`
  (24 tests) and `scripts/lint.sh` / `scripts/format.sh` all pass.
- Skipped: pixel-suite re-record — `BrevMailRootViewSnapshotTests` renders
  this column and is deferred in CI on this macOS 27 host.
- Handoff: branch `fix/macos-list-header`, PR targets `main`.

## 2026-09-30 — Agent — Settings detail simplification (Security + Calendar & Contacts)

- Goal: work item 4 of the 2026-09-30 Brev follow-up handoff — make the
  Privacy & Security and Calendar & Contacts detail panes lead with the
  controls people change, keep reference material behind one disclosure
  each, keep every relocated control reachable from settings search, and
  correct the Calendar/Contacts/Tasks status documentation.
- Changes: `SecuritySection` hides the key-material record list, draft
  editor, and destructive actions behind "Manage key material" and the
  import/export toggles behind "Advanced"; `CalendarContactsSection` moves
  the capability lists into a "Capabilities and roadmap" disclosure,
  promotes browsing and authoring rows to available, and reuses the Sources
  label "Google Calendar & Contacts"; `SettingsSearch` adds the Sources,
  DAV, and capability vocabulary and expands the owning disclosure on
  arrival; the README Calendar and Contacts status matches shipped scope.
- Verified: `swift test --package-path packages/BrevSettings` — 434 tests /
  66 suites; the 29 remaining issues are the pre-existing macOS 26+ snapshot
  baselines failing on this macOS 27.0 host, byte-identical on `main`
  (`/tmp/brev-main-settings-test.log` vs
  `/tmp/brev-branch-settings-final.log`). Focused suites green (55/55).
  `scripts/lint.sh` and `scripts/format.sh` clean. Rendered macOS QA on
  `Brev Test (2026-09-30)` with AX-verified disclosure expansion, search
  navigation, and persistence across restart; iOS simulator QA through the
  `serve-sim` mirror.
- Skipped: CI (runs on the PR); macOS snapshot suites on this host (see
  above); physical iPhone cold launch (no device); live-provider checks
  (no provider behavior changed).
- Handoff: PR to `main` for review; no merge, release, or issue closeout
  without Henrik's authorization.
## 2026-09-30 — Agent — Folder Sync empty scope (follow-up handoff item 2)

- Goal: reproduce and fix the settings-assessment observation that Folder Sync
  showed an empty mailbox selector despite an active mail window.
- Changes: new `MailRootSettingsScopePolicy.effectiveSourceID` in BrevMail and
  a call-site change in `BrevMailRootView.settingsMailboxContext` — the
  settings scope now falls back to Mail's
  `preferredDefaultSection(in: visibleSourceSections)` when
  `navigation.selectedSourceID` is nil (unified inbox, reader reconciliation,
  mailbox switches). New `MailRootSettingsScopePolicyTests` (red before the
  call-site change, 3/3 green after). QA evidence:
  `docs/qa/folder-sync-scope-2026-09-30/`.
- Verified: focused BrevMail tests; iOS 27 simulator with mock fixtures —
  reopen from the mailbox list, two-account scope switch, per-account choice
  retention, and persistence across a Settings reopen; lint and format clean.
  Full BrevMail suite baseline: 54 pre-existing pixel-snapshot issues,
  reproduced identically with the change reverted.
- Handoff: macOS native re-check and the zero-account UI state remain
  unexercised natively (the mock backend always has accounts). No tracking
  issue existed for this observation.
## 2026-09-30 — Agent — Standard folder-name localization (PR #165)

- Goal: the mailbox sidebar showed English standard folder names inside
  the otherwise Norwegian UI (iPhone screenshot: Inbox/Drafts/Sent/Trash/
  Spam). `FolderAliasPreferencesPolicy.standardDisplayName(for:)` returned
  hardcoded English strings for all ten standard roles, and the
  message-list header used the raw server folder name.
- Changes: the ten names now resolve through
  `String(localized:bundle:.module)` and the BrevBackend catalog gained
  Norwegian (`nb`) translations (Innboks, Sendt, Utkast, Søppel,
  Søppelpost, Arkiver, Utsatt, Planlagt, Flagget, All e-post). The
  message-list header now resolves through
  `MailRootMessageListTitlePolicy.folderTitle` — the same alias → standard
  name → server name path as the sidebar. New `FolderAliasPreferencesTests`
  case asserts every standard role name has a translated `nb` value in the
  catalog; a new `MailRootComposePresentationPolicyTests` case pins the
  header path.
- Verified: red first (20 catalog issues before the entries; the header
  test failed to compile before `folderTitle` existed). Focused
  `swift test --filter FolderAliasPreferences` 6/6 green; full BrevBackend
  suite (1152 tests / 114 suites) green; focused BrevMail run (27 tests /
  5 suites) green; `scripts/format.sh` and `scripts/lint.sh` clean (no ADR
  required). Rendered simulator (iPhone 17 Pro, iOS 27, mock backend,
  `-AppleLanguages '(nb)'`, via `serve-sim`): the mailbox list shows
  Innboks, Utkast, Sendt, Søppelpost, Søppel and Arkiver with the custom
  "Clients" tree intact, and the message-list header shows "Innboks"
  (before: "Inbox"). Evidence: `docs/qa/folder-localization-2026-09-30/`.
- Skipped: physical-iPhone acceptance remains pending (handoff item 1).
  The macOS pixel-snapshot suites (`LocalFolderSnapshotTests` light+dark,
  `CalendarGridSnapshotTests`; 4 issues in the focused comparison) fail on
  this macOS 27 host and reproduce identically on a pristine `origin/main`
  checkout (`git archive d96fd4d9` → `/private/tmp/brev-main-clean`), so
  they are pre-existing environment-versus-baseline drift, not this branch.
- Handoff: provider-native labels (for example Gmail "STARRED") and custom
  provider folders intentionally keep their provider names.
## 2026-09-30 — Codex — fix/gmail-reauth-recovery

- Goal: stop a native Gmail (gmail-api) account from being sent to the IMAP
  password sheet when its sign-in is rejected. Reported from the phone as
  being "logged out after a while" with no way to stay signed in; the only
  offered repair could not fix an OAuth failure.
- Root cause: `AppSession.reauthenticate(account:)` recorded only
  `authFailedIMAPAccountEmail`, and `LoginViewPresentation.recoveryAction`
  returned `.updatePassword` for any failed email. That opens
  `MailAccountSetupSheet`, which wraps `IMAPAccountSetupSheet` — a password
  form. `GmailAPIError.reauthenticationRequired` already maps to
  `MailBackendError.authenticationRequired`, so a rejected Gmail grant did
  reach the recovery surface, with the wrong repair.
- Changed: `AppSession` records the failed account's backend identifier and
  exposes `authFailureRequiresGoogleSignIn` / `canStartGoogleReauthentication`;
  `reauthenticate(account:)` now returns `.googleSignInStarted` or
  `.credentialsRequired` and starts Google sign-in for a native Gmail
  account. `LoginViewPresentation.recoveryAction` gained
  `.googleReauthentication`, and `LoginView` shows "Sign in with Google
  again" for it. Both app hosts open the add-account sheet only for
  `.credentialsRequired`. Repair requires the native Google connector, so a
  build with only the IMAP browser route does not start a sign-in that would
  create a sibling IMAP account instead of repairing the failed one. The new
  string has a Norwegian catalog entry.
- Verified: red first — the new tests failed to compile with the missing
  `googleReauthentication` argument before the change. Green after: 6/6
  focused tests (`LoginViewPresentationTests` plus the three new
  `AppSessionTests`). Full BrevMail package run: 1928 tests in 299 suites,
  zero functional failures; all 54 issues are the documented local pixel-drift
  baseline inside
  `*SnapshotTests.swift` (16 suites). The LoginView snapshot scenarios set no
  backend identifier, so their rendering path is unchanged by this diff.
  `scripts/format.sh` 0/1205 files changed; `swiftformat --lint`, `swiftlint
  --strict`, the SwiftLint coverage self-test and `check-adr-required.sh`
  all exit 0.
- Limits: no live Google account, physical iPhone, or provider revocation
  test was available, so the refresh-failure versus revoked-grant split behind
  "logs me out after a while" is not reproduced. Snapshot baselines were not
  re-recorded. No merge, release, or version change.
- Documentation sweep: CHANGELOG Unreleased `### Fixed` entry and the String
  Catalog updated. No architecture, network, consent, preference-key, or
  agent-workflow change, so no ADR, README, PRIVACY, or AGENTS update.
## 2026-09-30 — Codex — fix/gmail-delta-tolerate-deleted-message (PR #163)

- Goal: stop Gmail delta sync from wedging permanently when a changed message
  was permanently deleted server-side. Reported from the phone as a persistent
  "Gmail avviste forespørselen (HTTP 404)" banner for henrik@ogard.no with no
  new mail appearing.
- Root cause: `GmailSyncReconciler.fetchDetails` fetched every changed message
  with `messages.get`; a permanently deleted id answers 404, which aborted the
  whole delta before the history cursor advanced. A `history.list` 404 already
  fell back to full sync; a per-message 404 did not. Device evidence:
  `gmail.sqlite` held history_id=1288802 with last_delta_sync_at 2026-09-29
  21:20:45 (cursor not advancing).
- Changed: `fetchDetails` now returns fetched messages plus missing ids; only
  `GmailAPIError.httpFailure(statusCode: 404)` is tolerated and every other API
  error still propagates. Delta sync removes missing ids locally, full sync
  skips them.
- Verified: red first — both new tests failed with the 404 before the change,
  green after. 12/12 Gmail sync reconciler tests and 163/163 BrevGmail tests
  pass. `scripts/lint.sh` gates: swiftformat 0/1205 files, swiftlint --strict
  clean (custom cache path because the default cache directory is outside the
  sandbox).
- Skipped: no physical-device or live-provider run; nothing is deployed. The
  separate "logs me out after a while" report is not proven fixed by this
  change and is tracked on its own.
- Handoff: PR #163 targets `main`. No merge, release, version change, or issue
  closure.

## 2026-09-29 — Agent — Nightly runner resilience (ADR-0080 §4)

- Goal: stop the nightly ring from failing on GitHub-hosted macOS
  runner-acquisition errors and from refusing to ship when main's head
  only has cancelled Build runs.
- Changes: `nightly.yml` `plan` now selects the newest `main` commit
  with a successful Build run and moves the cron to `47 23 * * *`
  UTC; new `nightly-retry.yml` watchdog re-runs only acquisition-class
  failures (build job with zero steps and no runner) at +40/+80
  minutes, bounded to three total attempts. ADR-0080 §4,
  `docs/release.md`, and CHANGELOG updated to match.
- Verified: actionlint + shellcheck on both workflows; green-SHA
  resolution and watchdog detection logic exercised against live run
  data (Sep 25/26/29 acquisition runs vs. Sep 23 green run; Sep 27
  plan-gate run correctly not retried). Full CI proof runs on the PR.
- Handoff: none. Watchdog schedules become active only after merge to
  `main`.

## 2026-09-29 — Agent — Related-conversation bar Dynamic Type overflow

- Goal: fix the one new defect from the 2026-09-29 main verification
  pass — at ~73%+ text size the bar's action chips overflowed and
  hyphenated mid-word.
- Changes: `RelatedConversationBar` now reads `dynamicTypeSize`; at
  `isAccessibilitySize` it renders the status row above a full-width
  stacked `actions` column instead of a trailing HStack group. New
  `assertBarAccessibility` snapshot case (`accessibility3`, 560x220)
  covers the stacked layout.
- Verified: `swift test --filter RelatedConversationBarSnapshotTests`
  records the new baseline; lint + format clean. The four pre-existing
  baselines mismatch identically on clean main — host baseline drift,
  unchanged by this diff.
- Handoff: snapshot baselines for this suite need a host-fresh re-record
  pass (pre-existing, tracked alongside the iOS baseline drift).


## 2026-09-29 — Agent — deterministic extraction timeout (#112)

- Goal: kill the 1 ms deadline race in `AttachmentTextExtractorTests.timeout`
  (issue #112) — the task-group sleep branch could lose the scheduling race
  and the work branch had no way to notice the budget on its own.
- Changes: `extract(data:mimeType:fileName:timeout:)` now derives a
  `ContinuousClock` deadline and threads it into the work task;
  `HTMLTextStripper.visibleText` gained an optional `deadline` checked
  between its decode/strip/unescape/collapse stages and throws
  `AttachmentTextExtractionError.timedOut` directly. Long regex passes can
  no longer outlive the caller's timeout unnoticed (the task group
  implicitly awaits cancelled children, so sync work previously escaped the
  bound entirely). MockBackend's call site updated for the new `throws`.
- Verified: `swift test --filter "AttachmentTextExtractorTests|AttachmentIndexing"`
  19/19 green; `scripts/lint.sh` + `scripts/format.sh` clean.
- Handoff: deadline checks sit between strip stages, so the residual
  overrun is bounded by one regex pass, not the whole pipeline.

## 2026-09-29 — Agent — Keyboard-nav sequence coverage (Codex #99)

- Goal: cover the changed navigation behavior the P1 review asked for —
  a pixel suite for the 2200-line container would be brittle, so the
  sequence derivation is extracted and unit-tested instead.
- Changes: `UnifiedInboxListView.keyboardNavigableSequence` lifted to a
  static pure helper (parents + expanded thread children interleaved);
  new `UnifiedInboxKeyboardNavTests` covers splice order, collapsed
  threads contributing only their parent, and no parent duplication.
- Verified: `swift test --filter UnifiedInboxKeyboardNav` 3/3 green.
- Handoff: collapsed date-section exclusion lives at the presentation
  snapshot layer and is already covered by
  `UnifiedInboxPresentationSnapshotTests`.


## 2026-09-28 — Agent — iPhone status banner inset card

- Goal: stop the top status banner (auth-required / offline) from
  reading as part of the navigation bar on iPhone — a full-width band
  flush under the title crowded the nav chrome (QA follow-up).
- Changes: `BrevInlineStatus` gains an `inset` presentation (rounded
  `bgSecondary` card with horizontal inset, no bottom hairline);
  `BrevMailRootView.topChromeStatusRail` opts in on iOS only — including
  the `.importProgress` case, which carries the auth-required banner
  (`ImportProgressBanner` gained a matching `inset` param applied to its
  iOS `standardBody` only). macOS keeps the full-width band; every other
  `BrevInlineStatus`/`ImportProgressBanner` call site unchanged.
  ADR-0013 updated to record the inset variant.
- Verified: `swift build` BrevMail + BrevDesign; lint/format clean.
- Skipped: device re-verify — visual delta delegated to the testing
  agent's next pass on the iPhone 17 sim.
- Handoff: banner-bearing snapshot fixtures are rare; if `snapshot-test`
  red on CI it's this change (expected visual delta, re-record then).


## 2026-09-28 — Agent — reconnect sheet title for OAuth reauth

- Goal: the #151 "Sign in again" reconnect sheet titled itself
  "Update mail password" even when the account re-authenticates via
  OAuth (Gmail now, Outlook later) — flagged in the continuation review.
- Changes: `IMAPAccountSetupSheet.setupTitle` now reads "Sign in again"
  (existing key, nb parity already present) when the resolved setup is
  OAuth — `setupPath` `.google`/`.outlook` or either server's
  authentication `.xoauth2` — and keeps "Update mail password" for
  password/app-password reauth.
- Verified: `swift build` on BrevMail; lint/format clean.
- Skipped: device re-verify (tiny conditional; covered by next QA pass).
- Handoff: none.

## 2026-09-28 — Agent — l10n catalog symbol collisions (Xcode 27 build blocker)

- Goal: restore local builds on Xcode 27.0-RC — `GenerateStringSymbols`
  rejected the BrevSettings (21 errors) and BrevMail (83 errors)
  `Localizable.xcstrings` imported by #148.
- Changes: deleted 9 dead keys with no call sites (`%lld%%`, `%@ → %@`,
  `%@, %@ theme`, `%@ theme, %@`, `Edit %@`, `Edit "%@"`,
  `Custom Date & Time`, `Move to Folder`, mojibake `\(nickname)` variants);
  renamed 45 colliding/un-nameable keys to explicit lookup keys
  (e.g. `blockSender.menu`, `form.type`, `contact.unknown`) whose entries
  carry an explicit `en` localization equal to the original key text, so
  displayed English and Norwegian strings are unchanged; updated the ~60
  Swift call-site literals in BrevMail/BrevSettings sources, including a
  few plain-string properties (`MailProfile.name`, command `title:`s,
  `BrevIconButton` accessibility labels) that resolved through the
  catalog implicitly. Logic comparisons in `MailtoURL` and
  `MailboxActionAgentPlanner` deliberately untouched.
- Verified: `xcstringstool generate-symbols` clean on both catalogs (0
  errors, all 19 catalogs in the tree clean); `swift build` succeeds for
  BrevSettings and BrevMail; `scripts/lint.sh` OK.
- Follow-up (CI `test (BrevSettings)` + `test (BrevMail)` failures):
  six tests compared localized strings to their old English keys —
  under `swift test` the catalogs are not compiled, so
  `String(localized:bundle:.module)` yields the key itself. Assertions
  now compare against `String(localized:)` of the renamed key
  (`savedInKeychain.badge`, `enableAiWriter.menu`,
  `couldntLoadFolders.plain`, `setFollowUpReminder.menu`,
  `couldntUpdateAiWriter.period`); all fixed suites pass locally.
  Swept all renamed literals for remaining test references — only
  unrelated fixtures remain (rule IDs, message subjects, JSON payloads).
- Skipped: full app xcodebuild + device verification (delegated to the
  testing agent's next pass); CI build job confirms the app target.
- Handoff: pattern documented for future catalog imports — keep keys
  symbol-safe; QA evidence that exposed this is in
  `docs/qa/continuation-review-2026-09-28.md`.

## 2026-09-28 — Codex — Microsoft OAuth registration and release wiring

- Goal: configure the existing public-client Exchange Online IMAP/SMTP OAuth
  flow and supply its client ID to stable releases and local verification.
- Changes: expose the repository client-ID secret throughout release.yml,
  forward the ID explicitly to the archive build, and document Entra account
  types, delegated Exchange permissions, Devin scope, and local configuration.
- Verification: archive forwarding dry-run failed before the fix and passed
  after it; scripts/test-developer-id-release-config.sh, actionlint on release.yml,
  scripts/lint.sh, scripts/format.sh, and git diff --check passed. Formatting
  changed no files. No Swift or view behavior changed.
- External setup: registered Brev for organizational and personal Microsoft
  accounts, with brev://oauth and public-client flows enabled; no client secret.
  After explicit approval of the portal catalog difference, added delegated
  IMAP.AccessAsUser.All and SMTP.Send under Microsoft Graph, removed User.Read,
  and verified tenant admin consent granted for both. Runtime Outlook resource
  scopes remain unchanged. GitHub repository secret and ignored local env are set.
- Local verification: tuist install and tuist generate --no-open passed. The
  generated Microsoft setting was empty despite the exported environment value,
  confirming the need for the explicit archive/run-script build setting.
  xcodebuild -showBuildSettings confirmed the explicit ID matches for both
  BrevMacOS and BrevIOS. After .env.local was populated, isolated archive dry-run
  fixtures from that file so developer settings cannot replace test values;
  the forwarding check, actionlint, bash syntax, and diff checks passed again.
  script/build_and_run.sh --verify --live failed on existing BrevSettings string
  catalog symbol collisions under Xcode 27 (27A266a). A temporary xcconfig with
  STRING_CATALOG_GENERATE_SYMBOLS=NO did not resolve it. Native button and live
  sign-in verification remain blocked; no unrelated localization files changed.
- Pending: Devin's repository-secret form is marked disabled by the page; asked
  Henrik to save the public ID there. Publisher verification remains separate;
  external organizations may require admin consent.
- Documentation sweep: .env.example and docs/release.md cover setup; CHANGELOG.md
  records the release configuration fix. No new network behavior, protected
  paths, or architectural decision requires a privacy or ADR change.
- Handoff: PR targets main. No release, deployment, merge, or live sign-in run.

## 2026-09-28 — Agent — ADR-0083 widget snapshot architecture (Phase B)

- **Goal:** satisfy the protected-path requirement before a WidgetKit
  extension can touch apps/*/Project.swift, and settle how widget data
  flows without dragging Realm/BrevBackend into an extension process.
- **Adds:** ADR-0083 (Proposed) — app writes `WidgetSnapshot.json` to an
  App Group container; the extension renders it only (no network, no
  Realm); narrow first scope (unread count + 3 previews), previews gated
  by the same privacy posture as notification previews. ADR index rows
  for 81/82 (pending PRs) added so numbering stays unambiguous.
- **Verified:** docs-only — `scripts/lint.sh` + `scripts/format.sh`
  clean; `adr-required` gate satisfied by the new ADR under `ADRs/`.
- **Skipped:** unit/UI tests and device verification (no code changed).
- **Handoff:** Henrik reviews; implementation PR follows acceptance.
- **Verified:** docs-only — ADR-0083 file added; index rows 0081-0083 all
  backed by ADR files on main. Lint/format not run (no code touched).
## 2026-09-28 — Agent — WidgetKit mail widget (Phase B, ADR-0083)

- **Goal:** first glanceable surface — Home Screen / Notification
  Center widget showing the unified-inbox unread count and newest
  previews, implemented per ADR-0083 (app-group snapshot, never the
  Realm store; zero network in the extension).
- **Adds:** `packages/BrevWidgets` (leaf, Foundation-only): Codable
  `WidgetSnapshot` + `WidgetSnapshotStore` App Group IO + the
  WidgetKit provider/views shared by both platform extensions.
  `WidgetSnapshotPublisher` in BrevMail publishes from the unread-badge
  choke point so widget and badge numbers can never disagree; previews
  come only from each backend's cached inbox headers (no I/O) and are
  gated by the existing `NotificationSettings.showPreviews`. iOS and
  macOS `BrevMailWidgets` extension targets (bundle stub only) plus the
  app-group entitlement on macOS.
- **Privacy:** PRIVACY.md documents the widget data flow; ADR-0006's
  zero-network posture is unchanged (extension makes no calls).
- **Skipped:** on-device widget render (extension needs a signed build
  on sim/device; deferred to device-verify pass).

## 2026-09-28 — Agent — feat/mail-summary-widgets (review fixes)

Goal: address the Codex review on the widget implementation PR.

Changes:
- macOS widget target bundle id now `$(BREV_APP_BUNDLE_ID).macos.widgets`
  + `BREV_APP_BUNDLE_ID` base setting → nightly ring keeps a
  host-prefixed extension id; added Manual/Developer ID Release signing
  consuming `BREV_WIDGET_PROVISIONING_PROFILE_SPECIFIER`.
- `release-archive.sh` resolves `BREV_MACOS_WIDGET_PROVISIONING_
  PROFILE_SPECIFIER[_NIGHTLY]` and passes it through; both export-options
  plists map the extension bundle id to its ring profile.
- `MailSummaryWidgetView`: `Color.accentColor` → `.tint` shape styles;
  BrevWidgets added to `no_literal_colors_in_views` coverage.
- `WidgetSnapshot.sameContent(as:)` — dedup ignores `generatedAt` so
  unchanged payloads actually skip the write/reload.
- `WidgetSnapshotPublisher` serializes commits via a task chain so
  newest publications always commit last.
- NotificationSection `showPreviews` toggle now posts
  `.brevNotificationSettingsDidChange`; the mail root observes it and
  republishes counts-only snapshots immediately when previews turn off.
- New `MailSummaryWidgetSnapshotTests` (small+medium, light+dark,
  empty) with recorded baselines; BrevWidgets added to the test matrix,
  macOS<26 skip list, and the snapshot-macos job.

Verified: `swift test --package-path packages/BrevWidgets` 5/5 pass;
lint.sh + format.sh clean; `tuist generate` reproduces the committed
xcodeproj.
Skipped: on-device widget render (needs signed run; deferred).
## 2026-09-28 — Agent — Store-protection launch cost fix (Codex #145)

- `fix/store-file-protection`: the migration walk over
  `Application Support/Brev` is now one-time — a successful traversal
  records `BrevStoreProtection.migrationWalked`, so later launches only
  re-assert the root class (new files inherit it) instead of
  re-enumerating a mail store that can hold tens of thousands of
  entries (Codex P2: avoid walking the full store on every launch).
  Failures leave the flag unset so the walk retries next launch.
- `UserDefaults` injectable via a defaulted parameter so tests run in
  isolated suites; new assertion covers the flag being recorded.
- Verification: `scripts/lint.sh` + `scripts/format.sh` clean.
  BrevStoreProtectionTests unchanged in count (3) — sim cannot persist
  protection classes, so coverage asserts the observable contract
  (root creation, traversal, flag), same as before.
- Skipped: device verification (PR held pending Henrik's ADR-0082
  acceptance).

## 2026-09-28 — Agent — Phase E docs: encryption ADR + l10n + offline audit

- `docs/phase-e-encryption-l10n`: ADR-0082 (Proposed) — at-rest
  encryption in two layers: file-protection class now (iOS,
  UntilFirstUserAuthentication so BGAppRefresh keeps working), then
  SQLCipher behind a per-install Keychain key with a Settings toggle.
  Local store is raw SQLite3 — no Realm in the tree (AGENTS.md's
  mention is stale).
- `docs/dev/localization.md` — the l10n scaffold: catalogs already
  exist per target (en-only); doc covers adding a locale, string
  rules, and a community-translation PR flow.
- `docs/qa/offline-audit-2026-09-28.md` — offline coverage is deep
  (mutation queue, caches, retention, staged sends); the remaining gap
  is offline PIM writes, not plumbing.
- Verification: docs-only change — no code built. Ran
  `scripts/lint.sh` + `scripts/format.sh` (clean); `adr-required` gate
  satisfied by the new ADR under `ADRs/`. Audit claims were re-checked
  against the tree: `OutboxView` and `ConflictReviewSheet` already ship
  (Codex review) so those gap rows were removed; ADR-0082 Layer B
  scoped to the SQLite stores only, with the file-backed caches named
  as a follow-up.
- Skipped: unit/UI tests (no code changed); device verification not
  applicable.

## 2026-09-28 — Agent — fix/auth-required-banner

- Credential rejections now classify as `authenticationRequired` sync
  health on both backends instead of being flattened to
  `providerError`, so the banner actually reaches its Sign-in branch.
- `GmailAPIBackend` gained `lastSyncRequiresReauthentication`
  (`isReauthenticationError` matches the provider-neutral
  `MailBackendError.authenticationRequired`); `IMAPSMTPBackend` /
  `IMAPSMTPBackendState` thread `requiresReauthentication` through
  `installCached`/`recordSyncFailure`/`recordBackgroundSyncFailure` and
  clear it on every success/non-auth error path.
- `ImportProgressPresentation` `showsRetryAction` →
  `action: ImportProgressBannerAction?` with `.retry` +
  `.reauthenticate`; the banner renders "Sign in again" and
  `BrevMailRootView.runImportBannerAction` forwards it to a new
  `onRequestReauthentication` callback. Both apps wire it to
  `session.reauthenticate(account:)` + the add-account sheet (macOS
  also seeds `addAccountPrefillEmail`), landing the user on the
  pre-filled "Reconnect your mailbox" flow.
- New user-visible string "Sign in again" added to the BrevMail
  catalog with its nb translation.
- Verified: GmailRuntimeSyncTests 7/7 (new rejected-credential test
  asserts `.authenticationRequired` health);
  SyncHealthReauthenticationFlagTests 2/2 (flag set/replaced/cleared);
  BrevMail ImportProgressPresentation 11/11 (new
  `authenticationRequiredOffersReauthenticate`); lint.sh + format.sh
  clean; swift build clean for BrevBackend/BrevGmail/BrevMail.
- Skipped: on-device re-verify (banner was previously unreachable —
  dead-path fix; sim OAuth re-challenge is covered by earlier QA).
- Also hardened `deferredRemoteDraftDiscoveryRetriesAfterForegroundRead`
  (#110, still flaky after #150's budget bump): the retry is only armed
  when a foreground read catches discovery in flight — a 1 s injected
  delay let the task finish naturally on loaded runners, so call 2
  could never arrive. First-call delay is now 15 s and wait budgets
  15 s; the test still completes in ~35 ms locally.


## 2026-09-28 — Agent — JMAP ADR + Phase C specs

- `docs/jmap-adr`: ADR-0081 (Proposed) turns the issue-#15 research
  into a decision — a `packages/BrevJMAP` package with a hand-rolled
  RFC 8620/8621 client over a `JMAPTransport` protocol, PKCE OAuth
  where offered, app passwords otherwise; EventSource push deferred to
  match the ADR-0037 posture. Implementation gated on a JMAP test
  account (Fastmail trial) + stubbed session fixture.
- Also verified while writing: the push-notification decision already
  exists (ADR-0037 — no hosted relay, BGAppRefresh only) and
  PRIVACY.md + Settings copy disclose the best-effort posture; no new
  ADR needed there. Graph is spec'd by ADR-0079 (Proposed) and its own
  gate is an Azure app registration — outside repo scope.

## 2026-09-28 — Agent — release-readiness report (Phase A legs 1–3)

- **Goal:** Phase A — commit the iPad pass, iOS VoiceOver sweep and
  snapshot-drift triage executed on main@333754c.
- **Adds:** `docs/qa/release-readiness-2026-09-28.md` +
  screenshot/diff-PNG folder (iPad walk, the iOS nav dead-zone evidence,
  snapshot reference/failure/diff images).
- **Headline findings:** HIGH — sync-error state leaves the iPhone nav
  row invisible to VoiceOver and untappable; MEDIUM — composer To/body
  fields lack accessible names; 23 snapshot mismatches all categorized
  as genuine post-merge UI drift awaiting one baseline-refresh PR.
- **Handoff:** nav dead-zone fix in progress; baseline refresh to follow.
## 2026-09-28 — Agent — VoiceOver nav dead zone + composer naming

- **Goal:** Phase A findings — the "Sync interrupted" rail rendered
  inside the nav-bar band (nav row AX-empty + untappable); composer
  To/body fields without accessible names.
- **Changes:** `mailRootStatusLayout` no longer wraps the iOS split view
  in `.safeAreaInset(edge:.top)` — on iOS 26+ that lands inside the
  column's nav-bar band and covers its controls. The rail now mounts via
  `.safeAreaInset` inside each pane's content (below the column's own
  nav bar): sidebar when compact, message list always (covers regular
  width alone), and the sibling compact reader stack. Composer:
  `RecipientChipField`'s inner TextField gets `.accessibilityLabel(label)`
  (To/Cc/Bcc — matches Subject, which was already labeled); the body
  UITextView/NSTextView get "Message body" labels.
- **Verified:** macOS + iOS builds green; lint/format clean. Device
  re-verify queued to the testing agent.
## 2026-09-28 — Agent — fix/deferred-draft-retry-wait

Goal: deflake `deferred remote draft discovery retries after a foreground
read` (issue #110) — the injected first-call delay equals the default
1 s `waitUntilCallCount` budget, so the test hair-triggers on loaded CI
runners and failed on PRs #106 and #142.

Changes: pass an explicit 5 s budget to both waits in the test; the
call-count assertions and injected timing are unchanged.

Verified: `swift test --package-path packages/BrevBackend --filter
deferredRemoteDraftDiscoveryRetriesAfterForegroundRead` — pass.
Skipped: full BrevBackend suite (timing-only change).
Next: merge before the other open PRs so subsequent CI runs stop
hair-triggering.
## 2026-09-28 — Agent — iOS snapshot baseline refresh (Phase A drift)

- **Goal:** clear the 23 iOS snapshot mismatches the release-readiness
  pass categorized as genuine post-merge UI drift (#105/#111/#126/#133).
- **Changes:** re-recorded 20 baselines on the CI-exact iPhone lane
  (iOS 27 sim, en/en_US). Also threaded the `RECORD_SNAPSHOTS=YES`
  env-flag `record:` argument into the four suites that lacked it
  (ComposeView, BrevMail, BrevMailRootView, MessageDetailView) —
  previously only PhoneMailbox/PIM suites could be re-recorded this way.
- **Verified:** record run wrote baselines; follow-up compare run:
  23 tests / 7 suites all pass. BrevSettings iOS lane green as-is.
- **Note:** record flag must reach the sim-hosted runner as
  `TEST_RUNNER_RECORD_SNAPSHOTS=YES` (xcodebuild strips the prefix into
  the test process); plain `RECORD_SNAPSHOTS=YES` does not propagate.
## 2026-09-28 — Agent — ADR-0084 (offline PIM write queue)

- **Goal:** decide how PIM writes behave offline — the one remaining
  gap in docs/qa/offline-audit-2026-09-28.md.
- **Adds:** ADR-0084 (Proposed): durable per-source intent queue for
  create/update/delete, optimistic cache apply with pending marker,
  replay through the existing write services (precondition
  re-resolution from #119/#120 keeps replays from 412-wedging),
  dedup/collapse rules, conflict review via the existing surface.
- **Verification:** docs-only; no code changed.
- **Handoff:** Henrik reviews; implementation (PIMPendingWriteQueue +
  editor offline path + Outbox surfacing) follows on acceptance.
## 2026-09-28 — Agent — Check Mail intent triggers real refresh (Codex)

- `feature/app-intents`: Codex found "Check Mail" was a no-op when Brev
  was already foregrounded — `openAppWhenRun` produces no scene-phase
  transition, so the existing inactive→active `refreshVisibleMail` path
  never ran. The intent now calls `BrevIntentHandoff.requestRefresh()`,
  which increments a monotonic `refreshRequestCount`; `BrevMailRootView`
  watches the counter and calls `refreshVisibleMail()` per increment,
  so repeated runs refire and cold-launch drains still work.
- Verified: `swift build --package-path packages/BrevMail` clean;
  lint.sh + format.sh clean. On-device Shortcuts run still pending
  (signed install + Shortcuts UI).

## 2026-09-28 — Agent — App Intents (Phase B)

- **Goal:** Phase B — Shortcuts/App Intents support ("Check Mail",
  "New Message") on both apps.
- **Changes:** `apps/{iOS,macOS}/Sources/BrevAppIntents.swift` —
  `CheckMailIntent` (foreground refresh rides the existing
  scenePhase→refreshVisibleMail path, no new network call per ADR-0006)
  and `ComposeMessageIntent` (to/subject/body → `BrevIntentHandoff`,
  drained into `pendingComposePrefill`). New shared
  `BrevIntentHandoff` (`@Observable`, BrevMail) replaces a first-pass
  `OpenURLIntent` design — `OpensIntent` needs iOS 18/macOS 15 while the
  deployment targets are 17/14, and `appintentsmetadataprocessor` can't
  parse `#available` inside `appShortcuts`. `SharedComposePayload.prefill`
  now accepts direct `brev://compose?to/subject/body` fields (attachment
  params ignored on that path — file confinement preserved) and returns
  an empty prefill for bare `brev://compose`;
  `MailExternalInputConsumerModifier` retries a pending prefill when
  `canPresentCompose` flips true (cold-launch ordering).
- **Verified:** `swift test --filter ComposeDraftBuilderTests` 40/40;
  both apps build; `appintentsnltrainingprocessor` trained both phrases;
  lint+format clean.
- **Skipped:** on-device Shortcuts run (needs a signed install + the
  Shortcuts UI) — deferred to the Phase A device leg.
- **Handoff:** watch CI; the `.onChange` handoff drain covers
  already-foreground launches, `.task` drain covers cold launch.
## 2026-09-28 — Agent — Google PIM source reconnect + 403 copy

- **Goal:** fix two findings from the #147 device verify: "Reconnect…"
  on a Google source opened the DAV credential form, and a disabled-API
  403 surfaced "Reconnect to grant access" copy.
- **Changes:** `reconnectGoogle(sourceID:)` on PIMSourceSettingsModel
  routes through `enableGoogleFeature` (OAuth reauthorization); the row
  menu shows "Re-authorize with Google…" for google providers. Google's
  403 error envelope is now classified — `accessNotConfigured` /
  `SERVICE_DISABLED` reasons throw `serviceDisabled` with accurate copy.
- **Tests:** 3 new discovery tests (403 reason matrix) + 2 model tests
  (OAuth routing, DAV refusal).
- **Known gap:** the Google sync/writer adapters (events, contacts,
  tasks) still map every 403 to authenticationRequired — same copy gap
  on post-discovery syncs; scoped to discovery where failures surface
  first.
## 2026-09-28 — Agent — l10n(nb): first non-English locale

- **Goal:** Phase E — ship Norwegian Bokmål as Brev's second language.
- **Adds:** `nb` in Tuist `defaultKnownRegions` for both app projects
  (knownRegions regenerated); `nb` stringUnits in every non-empty
  catalog (BrevMail 497/497, BrevGmail 35, BrevBackend 4, BrevSettings
  2, app targets + InfoPlist usage strings). ADR-0058 amended —
  it deferred the second-language step until native-speaker review.
- **Skipped:** CFBundleName/DisplayName/NSHumanReadableCopyright stay
  untranslated (product name does not localize).
- **Verification:** catalogs parse (all 14 JSON valid); iOS+macOS
  builds compile catalogs at build time. Snapshot lanes stay `en`.
- **Handoff:** native-speaker review pass — Henrik owns the wording;
  especially mail-domain choices (Kopi til/Blindkopi, Utboks,
  smartvisning, oppfølgingspåminnelse).
## 2026-09-27 — Agent — iOS mail polish (N-M7/P3/P4)

- `fix/ios-mail-polish`: M7 — `brevBottomBarScrollInset()` reserves
  bottom layout space equal to the floating toolbar pill on iOS so a
  row is never born underneath it. P3 — the reader's empty body state
  shows `BrevSkeletonText` while the body is still loading and a plain
  "No body content." when it finished empty. P4 — LoginView suppresses
  the Google-not-configured caption while a sign-in/restore error
  banner is up.
- New snapshot: LoginView `compact-error-over-google-caption`.
- Verified: LoginViewSnapshotTests pass on iPhone 17 sim; lint.sh +
  format.sh clean. The remaining iOS snapshot failures are pre-existing
  baseline drift (unrecorded baselines from #105/#111 plus simulator
  TZ) — not caused by this change.

## 2026-09-27 — Agent — macOS chrome polish (N-M5/N-M6/P2)

- `fix/macos-chrome-polish`: M5 — search-scope picker switched to
  `.menu` (was `.segmented`) in the compact toolbar strip. M6 — macOS
  Send is a text accent action in the chrome row; From row renders its
  label via `fromPickerLabel` aligned to the field gutter with an
  invisible Menu overlay for interaction. P2 — app-password credential
  mode gains a Username TextField with an email-address prompt.
- New macOS snapshot suite `ComposeViewMacOSSnapshotTests` (light+dark)
  wired into the macOS<26 skip regex and the `snapshot-macos`
  `-only-testing` list; `davConnectSheet` baseline re-recorded with the
  username field.
- Verified: ComposeViewMacOSSnapshotTests 2/2 pass; BrevSettings
  PIMDAVConnectFormTests 7/7; lint.sh + format.sh clean.

## 2026-09-27 — Agent — stub DAV seed local times (N-M9)

- `fix/stub-seed-local-times`: evt-standup/evt-review/
  task-harbour-data .ics switched from UTC 'Z' stamps to floating local
  times (+2h shift) so seeded demo data renders at the authored clock
  time in any timezone, matching the QA review screenshots.
- Data-only change; no code. lint.sh + format.sh unaffected paths.

## 2026-09-27 — Agent — iOS bottom glass search

- `fix/ios-bottom-search`: `MessageListSearchBand` moved from the top
  of the column VStack to `safeAreaInset(edge: .bottom)` in
  MessageListView and UnifiedInboxListView, lifted by
  `bottomSearchCapsuleLift` (56) so it clears the floating bottom-bar
  pill. `MessageListSearchField` restyled to a capsule: brevGlassSurface
  (Liquid Glass when the glass translucency mode is on) over the card
  material + hairline border fallback.
- Verified: `xcodebuild -scheme BrevMail -destination iPhone-17-sim`
  build clean; lint.sh + format.sh clean. Device check pending with the
  batch verification run.

## 2026-09-27 — Agent — D2 stale write precondition

- **Goal:** Fix matrix defect D2 — edits to seeded events 412 on every
  retry after a remote etag bump.
- **Diagnosis:** `CalendarEventDraft` captures `providerItemKey` /
  `providerVersion` at editor open; `PIMEventWriteService.update` PUTs
  them verbatim. Sync refreshes the cached record, but the open draft
  keeps replaying the stale `If-Match`. Same staleness applied to
  `delete` and to server-side resource renames (dead href).
- **Changes:** `PIMEventWriteService` update/delete now re-resolve the
  target through `eventStore` before writing — by record id, else by
  the (uid, recurrenceID) identity so a synced rename re-keys the write
  and the stored record (`store` gained a `superseding:` cleanup for
  the stale row). `If-Match` still guards: a remote change the cache
  has not merged still surfaces `conflict`. ADR-0072 write-path bullet
  extended; CHANGELOG entry added. Contacts/tasks write services share
  the latent shape — not changed here (D2 scope); noted in the PR.
- **Verified:** pending — BrevCalendar tests + lint/format.

## 2026-09-27 — Agent — D2 follow-up: contact/task write precondition

- **Goal:** Port the #119 stale-precondition fix to the contact and task
  write services (same latent shape — editor drafts replay the
  open-time href/etag, so retries after a remote bump 412 forever).
- **Changes:** `PIMContactWriteService` and `PIMTaskWriteService`
  update/move/delete re-resolve the target through the cache before
  writing — by record id, else uid — so a synced rename re-keys the
  write and the stored record (`store` gained `superseding:`; deletes
  clear both ids). Contact photo-change lookup also matches the
  resolved providerItemKey so a re-keyed row is still found. If-Match
  semantics unchanged; unmerged remote changes still conflict.
  ADR-0072 bullets for both services extended; CHANGELOG entry added.
- **Verified:** `swift test --filter 'PIMContactWrite|PIMTaskWrite'` —
  52/52, including 6 new re-resolution tests.

## 2026-09-27 — Agent — Editor conflict copy polish

- **Goal:** `CalendarEventEditorView` rendered `editing.lastError` at
  the bottom of a long form — a save conflict was invisible below the
  fold (flagged during D2 device verification).
- **Changes:** error now renders as `BrevInlineStatus` (danger tone)
  at the top of the form's VStack, replacing the hand-rolled `Text`;
  consistent with `TaskEditorView` and the codebase's status surfaces.
- **Verified:** new `CalendarEventEditorSnapshotTests.conflictCalloutRendersAboveFold`
  (macOS, baseline recorded on macOS 26.5) — conflict copy visible at
  top of form. Suite added to the macOS<26 skip list and the
  `snapshot-macos` job's -only-testing list.

## 2026-09-27 — Agent — Editor conflict copy: contact/task editors

- **Goal:** device verification of #121 flagged that ContactEditorView
  and TaskEditorView have the identical below-the-fold lastError
  rendering — extend the same top-of-form treatment for one coherent
  outcome.
- **Changes:** ContactEditorView hand-rolled Text -> BrevInlineStatus
  at top of form; TaskEditorView's existing BrevInlineStatus moved
  from bottom to top.
- **Verified:** PIMEditorConflictSnapshotTests (2 baselines, macOS
  26.5) — both banners at top; suite wired into the macOS<26 skip
  list and snapshot-macos -only-testing list.

## 2026-09-27 — Agent — Read-only hints on PIM detail panes (M4/P1)

- **Goal:** fix docs/qa/uiux-review-2026-09-27.md N-M4 — macOS PIM
  detail panes show no Edit/Delete on read-only sources with no
  explanation (also covers P1 "no hint why editing is absent").
- **Changes:** new `PIMDetailEditabilityHint` text resolver diagnoses
  the hidden-actions case (server read-only collection vs. missing
  `.write` capability on the source) and returns a localized
  explanation; CalendarEventDetailView, ContactDetailView, and
  TaskDetailView render it as a BrevInlineStatus where the action row
  would be. iOS inherits the same hint — the views are shared. Gating
  itself unchanged: the observed bare panes were sources without the
  "Allow editing" capability, which is working as designed but was
  invisible.
- **Verified:** PIMDetailEditabilityHintTests 5/5; new snapshot cases
  (calendar event detail-readonly light/dark, task detail-readonly
  light/dark, contact detail baselines now carry the banner).
  Pre-existing drift left alone: agendaRow/eventDetail/contactRow
  baselines mismatch identically on pristine main @1422851.
- **CI:** TaskDetailSnapshotTests wired into the macOS<26 skip regex
  and the snapshot-macos -only-testing list.

## 2026-09-27 — Agent — N-H1 iPhone PIM cover width

- **Goal:** UI/UX review N-H1 — Calendar/Contacts/Tasks full-screen
  covers on iPhone render wider than the screen in portrait, pushing
  content and the Done affordance offscreen-left.
- **Changes:** `CalendarRootView`/`ContactsRootView`/`TasksRootView` —
  the shared `.frame(minWidth: 760, minHeight: 480)` window minimum is
  now `#if os(macOS)`-gated; new `PIMRootViewSnapshotTests` (iOS
  snapshot-test allowlist) lock in compact iPhone13Pro rendering.
- **Verified:** 3 fresh iOS baselines recorded and replayed green on
  iPhone 17 / iOS 27.0 sim; lint.sh + format.sh clean.
- **Handoff:** device re-verify on the sim — rotate portrait/landscape,
  confirm Done is reachable on all three covers.
  calendar defect; iOS VoiceOver row 5.1 still untested.
## 2026-09-27 — Agent — N-H2 PIM live-refresh on source changes

- **Goal:** UI/UX review N-H2 — macOS Calendar/Contacts/Tasks windows
  stuck on "No sources connected" when a DAV source is connected while
  the window is open.
- **Changes:** `PIMSourceCoordinator.changes()` — AsyncStream tick per
  persisted mutation (connect/reconnect/sync+write toggles/transitions/
  removal), broadcast helper mirrors the BrevBackend `Broadcaster`
  pattern; browsing + editing models gain `observeSourceChanges()`;
  all three RootViews subscribe via `.task`. ADR-0072 contract bullet.
- **Verified:** new `changesStreamEmitsOnMutation` (3 ticks across
  toggle/disconnect/remove); BrevCalendar suite green; lint+format.
- **Handoff:** device re-verify — open Calendar window, connect stub
  source in Settings, expect rows without reopen.
  calendar defect; iOS VoiceOver row 5.1 still untested.
## 2026-09-27 — Agent — N-M1 landscape reader back button covered

- **Goal:** UI/UX review M1 — on iPhone landscape the floating
  Reply/Archive/Delete bar's hit region covered the nav-leading back
  chevron (AX: centre "covered by button Reply"); taps did nothing.
- **Changes:** `compactReaderToolbar` places the action group at
  `.topBarTrailing` when `verticalSizeClass == .compact`, `.bottomBar`
  otherwise; reads `verticalSizeClass` from the view environment.
- **Verified:** `xcodebuild -scheme BrevIOS` for iPhone 17 iOS 27 sim —
  BUILD SUCCEEDED; lint+format clean.
- **Handoff:** device re-verify — landscape reader → tap back chevron.
  calendar defect; iOS VoiceOver row 5.1 still untested.
## 2026-09-27 — Agent — N-M2 dangling demo-account record after removal

- **Goal:** UI/UX review M2 — removing the last account left a persisted
  record that raised "Account error" + a sticky "Saved account settings
  are incomplete" banner over onboarding on next launch.
- **Root cause:** `signInWithDemo` ran `install()` → `accountStore.add`,
  writing the demo preview account (`backendIdentifier: "demo"`) into
  the persistent store; nothing can restore a demo record, and removal
  inside a demo session only cleared the in-memory store.
- **Changes:** `BrevAccount.demoBackendIdentifier` constant; `install()`
  skips persisting demo-identifier accounts; `restoreAllAccounts()` and
  `restoreCurrentAccount()` purge stale demo records instead of
  erroring; `purgeStoredAccountAfterAuthenticationFailure` renamed to
  `purgeStoredAccount` (same cascade, general use).
- **Verified:** two new AppSession tests; full suite run below.
- **Handoff:** device re-verify — sign in demo → remove → relaunch →
  clean onboarding, no alert/banner.
  calendar defect; iOS VoiceOver row 5.1 still untested.
## 2026-09-27 — Agent — N-M3 add-mail sheet hides connect failure

- **Goal:** UI/UX review M3 — a failed IMAP connect (~80 s timeout)
  re-enabled "Add account" with no in-sheet error; the callout appeared
  only on the LoginView behind the sheet after Cancel.
- **Root cause:** `localStatus` rendered only inside the scrollable
  `statusAndGuidanceSection`, gated on `didStartDiscoveryProbe ||
  setupPath != .undiscovered` and below the fold on iPhone.
- **Changes:** `IMAPAccountSetupSheet` now pins an `actionStatus`
  `BrevInlineStatus` directly above the action buttons — `localStatus`
  first, else a banner derived from `session.signInError`; removed the
  duplicate render inside `statusView`. New snapshot
  `imap-connect-failure` covers the pinned banner.
- **Verified:** `swift test --filter LoginViewSnapshotTests` — new test
  green; the 7 onboarding snapshot mismatches reproduce identically on
  pristine main (pre-existing baseline drift, not re-recorded).
- **Handoff:** device re-verify — sheet → unreachable host → error
  inline without dismissing the sheet.

## 2026-09-27 — Agent — scheduled PIM sync (O3)

- `fix/pim-idle-sync`: O3 — the parity matrix's "does a remote DAV
  change land without Sync Now?" answer was *no*: `PIMSource.syncEnabled`
  was documented as the background-sync opt-in but nothing ever consumed
  it for scheduling. Added `PIMSyncScheduler` (session-owned, mirrors
  `BackgroundMailCoordinator`), ticking on the configured mail fetch
  interval via `MailFetchScheduler.ticks` and syncing every source with
  `syncEnabled` in a syncable status through the kind-matching
  `*SyncService.syncNow`. Same consecutive-failure backoff as mail.
- Wiring: `AppSession` owns the instance and the kind→service routing;
  the root view's `fetchIntervalRaw` task calls `start(interval:)` so
  the cadence tracks the user's mail schedule (manual parks ticks);
  macOS `reconcileBackgroundMail` also starts it so menu-bar-only
  presence still syncs.
- ADR-0006 network table: the six PIM sync rows now state the cadence
  ("scheduled cadence … while the source's sync is enabled, plus Sync
  Now/first-enable") — the opt-in itself is unchanged.
- Tests: `PIMSyncSchedulerTests` (driven-tick source) covers
  enabled-only filtering, per-pass source re-read, failure summary,
  manual mode, stop, restart no-op.
- Skipped: device verification deferred to the Phase A run on this
  branch once merged — scheduling behavior is unit-verified only.

## 2026-09-27 — Agent — Privacy policy storage audit (PR #109)

- **Goal:** name Ogard Labs as controller and make the public policy match
  Brev's current on-device storage and removal behavior.
- **Changed:** corrected the controller in `PRIVACY.md` and ADR-0006;
  described account metadata, mail/draft storage, PIM caches, exports,
  and voluntary contact; corrected access, erasure, and rectification text.
- **Verification:** inspected the account, mail, PIM, settings, and removal
  implementations; ran `git diff --check` and the privacy audit.
- **Skipped:** app builds and Swift tests, since this changes documentation
  only and no runtime behavior.
- **Handoff:** sync the same policy text to `brevmail.eu/privacy` before
  submitting Google OAuth branding; publishing remains separate.


## 2026-09-25 — Agent — Unified inbox keyboard-nav review follow-ups (#99)

- Codex P2: `keyboardNavigableItems` now builds from `dateSections`'s
  `visibleItems` when date grouping is on — collapsed sections no longer
  leak hidden rows into arrow-key selection.
- Codex P2: `selectMessage` gains `clearsBulkSelection` (default true);
  `selectAdjacentItem` passes false so arrows move the reader without
  dropping the bulk set, matching MessageListView's contract.
- Codex P1 (snapshot coverage) deferred: the list populates async from
  backends so a pixel suite can't capture deterministic content without
  a data-injection seam, and macOS pixel baselines need the canonical
  26+ host anyway. Flagged in the PR.
- Verified: `swift test --filter UnifiedInbox` (37 green),
  lint.sh + format.sh clean.


## 2026-09-25 — Agent — Unified inbox keyboard navigation (macOS)

- The merged "All Inboxes"/saved-search list had no focus machinery while
  the folder list did. Adds the MessageListView container contract to
  `UnifiedInboxListView`: focusSection/focusable/focused + focusEffectDisabled,
  arrow keys walk the merged displayed order (parents + expanded thread
  children across sources), Return activates like a click (drafts ->
  composer, threads expand, bulk toggles), pointer selection claims the
  key session, automatic selection-restore opts out of focus claiming,
  and sidebar mailbox activation hands the keyboard over via
  `messageListFocusRequestID`. ScrollViewReader added for selection
  scroll-follow (row ids are the composite `source:folder:message` ids).
- Verified: `swift build` for BrevMail clean; `scripts/format.sh --check`
  and `scripts/lint.sh` pass.


## 2026-09-25 — Agent — Prewarm navigation no longer reports as body-visible (#98)

- Codex P1 on #98: `MessageDetailView`'s prewarm `.task` races the mounted
  coordinator; the empty-document navigation can still be in flight when
  the delegate attaches, and its `didFinish` would drop the skeleton and
  record `ui.body.visible` before the message painted.
- `HTMLBodyWebViewStore` now tracks `prewarmNavigation` (cleared on
  completion and `releaseWebView`); the coordinator ignores that
  navigation's `didFinish` instead of measuring/reporting.
- Verified: `swift test --filter HTMLBodyDocument` (22 green, incl. new
  prewarmNavigation contract test), lint.sh + format.sh clean.


## 2026-09-26 — Agent — iPhone composer polish

- `fix/ios-composer-polish`: mobileToolbar title centred via overlay
  (was left-aligned beside Close); iOS Send is now a bold accent text
  button (was a 44pt borderedProminent capsule); shared fieldRows order
  To→From→Subject (was To→Subject→From, applies to macOS/iPad too);
  From-row label drops the person.crop.circle icon; keyboard utility
  bar gains the Format (Aa) menu between Attach and the overflow
  ellipsis. `utilityActions` updated to [.attach, .format, .moreActions].
- Verified on device: iPhone 17 iOS 27.0 sim (screenshot), iPhone 17
  iOS 26.5 (AX-driven: Format menu opens with all commands), iPad Pro
  13" iOS 27.0 (screenshot — sheet + bottom utility bar).
- lint.sh + format.sh clean; `swift test --filter ComposePresentationTests`
  23/23 pass. ComposeAccessibilityBoundsTests is iOS-only (UIKit) —
  exercised via CI/xcodebuild, not host swift test.
- macOS mock verification pending (build running).

## 2026-09-26 — Agent — UI/UX review batch 4 (M5 selection, M6 window sizes, M7 month grid)

- M5: new shared `PIMSelectionRowBackground` (rounded `BrevSelectionPalette`
  fill, `isActive: true`) applied via `.listRowBackground` in
  `CalendarAgendaView`, `ContactsListView`, `TasksListView` — the three
  PIM lists now match the mail list's neutral selection instead of the
  system accent highlight. No accent text was used for selected rows;
  text colors untouched.
- M6: Tasks `Window` gains `.defaultSize(width: 1000, height: 680)`
  (same as Contacts); `TasksRootView`, `ContactsRootView`, and
  `CalendarRootView` get `.frame(minWidth: 760, minHeight: 480)` so
  `contentMinSize` can't collapse them into toolbar overflow. Calendar
  had no root min — its leading-column min alone allowed <760, so the
  min was added there too.
- M7: `CalendarMonthView` — weekday header now footnote/semibold with a
  bottom hairline; day cells get separator-color top + trailing 1pt
  rules (was a `bgSecondary` top line only); day number gets leading
  padding. `CalendarEventChip` background is now the calendar colour at
  0.18 opacity (0.45 selected) — shared with the day all-day strip and
  week view by design. Cell min height unchanged (96).
- Verified on macOS mock with the stub DAV server (three sources:
  calendar CalDAV, contacts CardDAV, tasks CalDAV — the pre-existing
  localhost source had `missingCredential` after the restart, so new
  sources were added through the grouped sheet): `m5-agenda-selection`,
  `m5-contacts-selection`, `m5-tasks-selection`,
  `m6-tasks-window-default` (opens at 1000×680, no toolbar overflow —
  the » item is the designed secondary-actions menu),
  `m7-month-grid` (two same-day events, tinted chips, grid lines).
- Tests: `swift test --filter 'Calendar|Contacts|Tasks'` — 159 tests,
  10 snapshot issues, all reproduced identically on the `brev-main`
  worktree (env-vs-baseline drift; the month-grid/chip change is inside
  the already-failing `month-*` baselines, so intended diffs are masked
  — baselines not re-recorded). lint/format clean.


## 2026-09-26 — Agent — IMAP/SMTP provider compatibility (D5/D6, #11)

- `fix/imap-smtp-provider-compat`. D5: added
  `IMAPServerCapabilities.supportsCONDSTORE`; both `select` and
  `selectCONDSTORE` now omit the modifier when the server didn't
  advertise CONDSTORE (capability capture already covers greeting,
  STARTTLS CAPABILITY, LOGIN tagged OK, and XOAUTH2 tagged OK paths —
  no new round trip). `loginAndCONDSTORESync` callers tolerate nil
  HIGHESTMODSEQ.
- D6: `authenticate` prefers `AUTH PLAIN`, falls back to the
  `AUTH LOGIN` challenge exchange (334 → b64 user → 334 → b64 secret →
  235), else throws `authenticationUnavailable("AUTH PLAIN or AUTH LOGIN")`.
  `replyAdvertisesAUTHXOAuth2`/`replyAdvertisesAUTHPlain` merged into
  `replyAdvertisesAUTHMechanism(_:mechanism:)`.
- Tests: scripted transports now advertise CONDSTORE where they assert
  the modifier (capability state is overwritten per parse — atom sets
  must be complete per site); new tests cover plain SELECT, nil-modseq
  sync, AUTH LOGIN exchange, PLAIN-over-LOGIN preference, combined
  error. 162 tests pass; lint/format clean.
- Live re-verify (mailo.com): `--validate-smtp-setup
  --send-test-message --exercise-compose-lifecycle` → `imap-smtp-live-smoke:
  OK`; real message submitted through MailBackend, Drafts
  save/send/discard pass. Residual, unrelated to this change: multi-word
  TEXT / non-ASCII server-search guards fail (provider charset/TEXT
  gap — observation) and IDLE messagesAdded times out (provider emits
  no same-account APPEND notifications; flagged optional in script).
- D7 investigated, left design-level: no account persists after a
  failed manual add (keychain clean); "Reconnect your mailbox" is just
  `session.signInError != nil` (`LoginView` ~L158) and the sheet
  correctly stays open on failure — misleading copy, not zombie state.

## 2026-09-26 — Agent — iPhone composer header polish (fix/ios-composer-header)

- Root cause of Henrik's "He" chip: any trailing space committed the
  recipient input, and iOS autocorrect appends "He " mid-typing.
  `RecipientChipFieldPresentation.commitAction` now commits on
  comma/semicolon always, on space only when the text passes
  `RecipientAddressValidator.isLikelyEmailAddress`; otherwise untouched.
  TextField gets `.emailAddress` keyboard type/content type,
  `autocapitalization(.never)`, `autocorrectionDisabled` (iOS;
  autocorrectionDisabled unconditional).
- `RecipientChipField` is now generic over a `trailingAccessory`
  (default `EmptyView` via convenience init); ComposeView passes
  `carbonCopyControls` there and drops the outer HStack — Cc/Bcc stay on
  the To line while the suggestion list spans the field width below.
- Verified on iPhone 17 sim (mock): typed `henrik.ogard@mailo.com` +
  space → exactly one valid chip; "he " leaves input untouched with the
  full-width suggestion list under the Cc/Bcc line; screenshots in
  /Users/devin/evidence/composer/. macOS compose row visually unchanged.
- The large black disc in Henrik's screenshot is the iOS pointer-device
  cursor (host mouse rendered inside the simulator), not a Brev view.
- Tests: `swift test --filter 'RecipientChipFieldPresentation|
  ComposePresentation'` — 62 green (new tests folded into the existing
  suite in RecipientAddressValidatorTests.swift). lint/format clean.

## 2026-09-26 — Agent — QA live pass round 3 (#2, #11)

- iOS O6 retry succeeded: BrevIOS built with `DEVELOPMENT_TEAM=45AD7E7G5G
  -allowProvisioningUpdates` (worktree `/Users/devin/repos/brev-imapfix`
  on fix/imap-smtp-provider-compat) → keychain writes succeed; full
  iPhone 17 lifecycle pass (add → inbox → self-send → relaunch restore →
  remove). Ad-hoc `CODE_SIGN_IDENTITY="-"` alone still produces empty
  entitlements — the unsigned-build -34018 stays recorded as env-only.
  Recipient field quirk noted: To field committed a "He" chip
  mid-keystroke; pasting the address worked.
- §5 gates: VoiceOver reads macOS agenda rows and contact rows/detail
  (5.1 ✓); `-AppleLanguages '(nb)'` → English fallback only — catalogs
  ship `en` exclusively (5.3 ✓*); `NSReduceMotionEnabled` — PIM views
  have no animations (grep-clean), MessageListRefreshArrivalEffect
  honors the flag (5.4 ✓); macOS 5.2 stays untested (no per-app text
  size control; app ships MailboxView text-size control for mail only).
- O4 triaged (no fix): client emits RFC-correct `UID SEARCH TEXT …`
  (quoted ASCII atoms, CHARSET UTF-8 + literal only for non-ASCII) —
  mailo.com's TEXT indexing covers envelope headers only, provider
  limitation; diagnosis in account-lifecycle doc.
- Docs updated: account-lifecycle (iOS pass, O4), matrix (5.1/5.3/5.4,
  O6 resolved, Live providers row), no code changes.

## 2026-09-26 — Agent — QA live pass round 2 (#2, #11)

- Apps built from `fix/imap-smtp-provider-compat` (macOS
  `build_and_run.sh run --live`; iOS via xcodebuild to iPhone 17 sim,
  OAuth vars passed as build settings).
- Generic IMAP (mailo.com): **macOS full lifecycle pass** — autodiscovery,
  test connection, add, inbox load, compose self-send arrived in inbox,
  reconnect via transport-error Retry, Remove → keychain clean. Live
  smoke `--validate-smtp-setup --send-test-message
  --exercise-compose-lifecycle` → `imap-smtp-live-smoke: OK`. Residual:
  multi-word TEXT/non-ASCII server search fails on provider (O4); IDLE
  messagesAdded times out (provider emits no APPEND notifications).
- iOS live add blocked by environment: unsigned sim build → securityd
  -34018 on every keychain write; hand-signing entitlements breaks
  launch. Recorded as O6, not an app defect.
- Google leg: 2FA disabled but sign-in now stops at "Verify it's you"
  recovery-phone device verification — all paths need the QA phone or a
  trusted device; leg stopped per runbook (redacted evidence in
  `docs/qa/live-pass-2026-09-26/`). iOS onboarding lacks the Google row
  even with client ID baked (O5).
- Docs updated: account-lifecycle-2026-09-26.md (round-2 results),
  pim-parity-matrix.md (D5/D6 fixed, D7 reclassified, O4–O6, fixtures +
  Live providers row). No code changes this session.

## 2026-09-26 — Agent — UI/UX review items 1–8 (fix/uiux-top10)

- Merged #97 and #100 onto main via squash (3-way, post-merge
  `git diff origin/main <branch>` empty), rebased `fix/uiux-top10` onto
  the new main.
- Verified items 1–8 of `docs/qa/uiux-review-2026-09-26.md` on the macOS
  mock build (`Brev Test (2026-09-26).app`) and the iPhone 17 / iOS 27.0
  simulator: DAV grouped form, reader wrap at ~700 pt, iPhone thread
  expansion, sidebar glyph column + icons-off chevron gap, Advanced
  setup row + manual IMAP/SMTP form, PIM source toggle labels, Window →
  Message Viewer (⌘0 — Apple Mail's shortcut, not the doc's ⌥⌘N).
- Caveat: after an AppleScript window resize the reader body shows one
  stale clipped frame until the message is re-selected — remeasure fires,
  repaint lags one step. Functional; polish follow-up.
- Focused tests green (BrevMail 79, BrevSettings PIMSourceRow 8);
  lint/format clean. Snapshot suites not run in this pass.

## 2026-09-26 — Agent — UI/UX review top-10 batch 2 (items 9, 10, M9)

- Item 9 (M1): replaced the iOS `sidebarFooter` safe-area pill chips
  (Calendar/Contacts/Tasks/Settings) with in-scroll `BrevListRow` rows
  under a "More" section header at the end of the sidebar tree, using
  the same icon column (`sidebarMetrics.iconWidth`) and
  `showSidebarIcons` gating as the outbox row — no more overlap over
  the last mailbox rows on iPhone; iPad sidebar gets the same rows.
- Item 10 (M2/M3): unified the compose header label column — new shared
  `ComposeFieldLabel` used by `fieldRow` (From/Subject) and
  `RecipientChipField` (To/Cc/Bcc), and the chip field's label now uses
  the same `.firstTextBaseline` alignment instead of `.top` + manual
  padding. Reply quotes keep their `>` text but gain a 12 pt head
  indent plus an accent-coloured rounded bar drawn in
  `ComposeRichTextView.drawBackground` (`quoteBarRange`/`quoteBarColor`
  fed by `applyQuoteStyling`).
- M9: "Applies to all mailboxes" moved from an orphan banner in
  `settingsScope` to a `settingsScopeCaption` environment value
  rendered under the pane subtitle by `SectionScaffold`.

## 2026-09-26 — Agent — QA live pass attempt (#2, #11)

- Same branch, docs-only. `imap-smtp-live-smoke.sh` against the disposable
  mailo.com account: connect/restore/9-folder list/IDLE wiring pass, but
  `SELECT "INBOX" (CONDSTORE)` → `BAD` (server lacks CONDSTORE; client
  appends the modifier unconditionally — `IMAPSessionClient.swift` ~L3079)
  and SMTP advertises only `AUTH LOGIN` (`SMTPSessionClient` supports
  PLAIN/XOAUTH2 only). All mailbox+send stages blocked → defects D5/D6.
- macOS live test build: manual-IMAP add surfaces the SMTP error correctly
  but never completes, and leaves a zombie "Reconnect your mailbox" state
  (D7); no keychain residue.
- Google OAuth leg: sign-in launched fine but the QA account demands
  2-Step Verification (phone code) — leg stopped per runbook; needs
  Henrik. G matrix columns remain pending.
- Recorded in `docs/qa/account-lifecycle-2026-09-26.md` +
  `docs/qa/pim-parity-matrix.md` defects table. No secrets or account
  addresses committed (evidence is log citations + descriptions; two
  candidate screenshots were dropped because they contained addresses).

## 2026-09-26 — Agent — QA: stub-DAV PIM matrix + account lifecycle (#11, #2)

- Docs-only pass on `chore/qa-stub-dav-ios-2026-09-26`. Filled the
  credential-free cells of `docs/qa/pim-parity-matrix.md`: iOS columns for
  rows 1.6–1.9, 2.1–2.6/2.9/2.10, 3.1–3.8 (n/a where unsupported), 4.1/4.2;
  macOS cells for 1.7–1.9, 2.2, 2.6, 3.2/3.3/3.6, 4.3/4.4/4.6, 5.2 (iOS XL
  type), 5.5, 6.2–6.4. Google columns and live rows stay blank — marked
  "pending live pass" (repo-scoped secrets arrived 2026-09-26).
- Evidence in `docs/qa/pim-parity-stub-dav-2026-09-26/` (screenshots +
  stub request logs; synthetic seed content only). New defects/observations
  recorded at the matrix bottom: D1 iOS wrong-cred sheet shows no error
  callout, D2 stale seeded-href 412s, D3 dimmed contact-source toggles,
  D4 ~30 s TLS-error delay, O1–O3 observations.
- Issue #2: `docs/qa/account-lifecycle-2026-09-26.md` records
  `imap-smtp-local-smoke.sh` (OK) and `check-imap-oauth-setup.sh`
  (ready, 2 providers — so the missing-Google-client guidance is not
  reachable in this build), plus a code-cited list of UI affordances hidden
  for generic IMAP accounts.
- Verified: docs review only; no source changes, no tests run (none
  applicable). macOS mock app, iPhone 17 sim, stub DAV :8643/:8644 left
  running.

## 2026-09-26 — Agent — UI/UX review batch 3 (M4 search controls, M8 iPad calendar)

- M4: replaced the custom capsule search chips in `MessageListView`
  (`searchScopeBar`) and `UnifiedInboxListView`
  (`unifiedSearchExecutionBar`) with macOS-only `.segmented` Pickers —
  search location (Local/Auto/Server), folder scope (This folder/All
  mailboxes), and field scope (All/From/Subject/Attachment/Unread),
  each `.controlSize(.small).fixedSize()` with a localized
  `accessibilityLabel`. The 1pt separator rectangles between groups
  are gone; the bottom hairline, NL chip strip, and
  `ServerSearchSyntaxHint` are unchanged. The execution picker binds
  through a custom `Binding` so `hasUserSelectedSearchExecution` is
  still set before the assignment. iOS keeps the chip path (the whole
  `#else` branch plus the chip helpers under `#if os(iOS)`). Left
  `MessageListSearchField`'s `.default` focus ring alone — the ring in
  the review is the system focus ring in the reviewer's accent, which
  is what Apple Mail shows too.
- M8: `CalendarRootView.columnVisibility` now starts `.doubleColumn`
  so iPad portrait keeps the agenda column open (macOS was already
  two-column; verified the window still opens with both). The detail
  column renders a blank pane (`bgPrimary`) when
  `hasSelectableEvents` (`hasSources && !events.isEmpty`) is false, so
  "No event selected" no longer stacks with the leading column's own
  empty state.
- Left alone per scope: the modal "Done" presentation on iOS
  (presentation architecture).
- Verified: macOS mock screenshots `m4-search-segmented.png`,
  `m8-macos-calendar.png`; iPad Pro sim
  `m8-ipad-calendar-single-empty-state.png`.
  `swift test --filter 'MessageList|UnifiedInbox|Calendar'` 303 tests —
  only the 8 snapshot diffs (CalendarGridSnapshotTests,
  CalendarBrowsingSnapshotTests), all reproduced identically on a
  pristine origin/main worktree (`brev-main`) — same env-vs-baseline
  mismatch documented earlier. lint/format clean.

## 2026-09-26 — Agent — UI/UX review batch 5 (M10 accounts rows, M11 thread dots, M12 iOS chrome)

- M10: `AccountsSection.mailboxRow` now branches on the existing
  `AccountRowLayoutKind` — on compact (iOS) the mailbox name/email get
  the full row width and the enable `Toggle` + "Default mailbox"/
  "Make default" control move to a second line (the fixed 122 pt
  control frame is dropped there only). Identity, toggle, and default
  controls are factored into `mailboxIdentity`/`mailboxToggle`/
  `mailboxDefaultControl` shared by both branches. The boxed
  `BrevButton` "Add account" becomes a plain `plus.circle.fill` list-row
  action on iOS (`#if os(iOS)`); macOS keeps the button.
- M11: removed the `.padding(.leading, BrevSpacing.xl)` on
  `ThreadInlineChildRow` in `MessageListView`; inside the row the
  unread dot is 8 pt (matching the parent's dot column) and the child
  indent moved onto `BrevAvatarView` (`xl - sm`). Child selection now
  spans the full row width — intended.
- M12: iOS Mailboxes-root leading toolbar button now renders
  `Text(destination) + chevron.forward` in an HStack so it reads
  "Inbox ›" instead of icon-only. The iOS floating bottom-bar reserve
  moved to `MessageListPresentation.bottomBarScrollInset = 76` (was a
  48 literal) — the only `List` in `MessageListView` already gets
  `.brevBottomBarScrollInset()`, covering search results too. Added a
  one-line unit test pinning the value.
- Verified: `swift test --package-path packages/BrevSettings --filter
  Accounts` 19/19 green; `--package-path packages/BrevMail --filter
  'ThreadInlineChildRow|MessageListPresentation|MonoMailSelection'`
  34/35 pass — the same 5 snapshot diffs (MonoMailSelection ×4,
  ThreadInlineChildRow ×1) reproduce identically on the `brev-main`
  worktree, so pre-existing env drift; the intended M11 geometry
  changes are masked inside those already-failing baselines. Screens:
  `m10-iphone-accounts.png`, `m11-thread-dots.png`,
  `m12-iphone-root-toolbar.png`, `m12-iphone-inbox-footer.png`.


## 2026-09-26 — Agent — Sidebar flush-left refinement (PR #100)

**Goal:** Henrik: move mailbox folder rows further left — icons under the mailbox headers, Apple Mail gutter.

**Changes:** `FolderSidebarPresentation.macOSLayoutMetrics` `disclosureHitSize` 16→10 (Mail's leading gutter ≈ 7–10pt); macOS `folderRowControlSpacing` → 0 (the disclosure column carries the visual gap); `sidebarActionRow` leading now derives from the same column (`disclosureHitSize + folderRowControlSpacing`) instead of a hardcoded `xxs`; iOS `.folderContent` action rows drop the stale +44pt leading disclosure offset (`folderRowLeadingPadding(0)`, matching iOS folder rows — iOS disclosure is trailing). `⋯` smart-view menu target pinned at `BrevSpacing.lg` so the metric change does not shrink it.

**Verified:** rebuilt `Brev Test (2026-09-26)` — icons ~10pt right of header text, leaf/parent icons on one column, chevrons at the header edge; `swift test --filter 'FolderSidebarPresentation|MailboxGroupDisclosure|GmailNativeSidebar'` 42/42; lint.sh + format.sh clean.

**Skipped:** pixel snapshot baselines (same env-diff caveat as before).

## 2026-09-26 — Agent — Sidebar icons flush-left + View-menu icons toggle (PR #100)

- Goal: Henrik asked for mailbox folder icons "all the way to the left" and an easy way to turn icons off.
- macOS leaf rows no longer reserve a disclosure column; leaf icons (and All Inboxes / smart views / plugin rows) sit flush with the section-header text. Parent rows keep the chevron in that edge slot. Child depth indent is now 16pt so child icons start right of the parent icon.
- Removed the now-identical `SidebarActionRowAlignment` distinction and the dead disclosure placeholder.
- Added View → "Show Sidebar Icons" toggle bound to `folders.showIcons` (same preference as Settings → Mailbox View → Folders → Sidebar icons).
- Verification: lint.sh OK, format clean, FolderSidebar/MailCommand/Shortcut unit tests green, rebuilt mock app and checked the result visually. FolderSidebar pixel snapshots differ, as expected from the geometry change (they were already env-divergent on this machine). Re-record the baselines on the maintainer host.

## 2026-09-26 — Agent — Sidebar, DAV form, and compact rows (PR #100)

- **Goal:** Deliver the three Apple Mail-inspired UI polish changes requested
  for PR #100: shared sidebar folder glyph alignment, a native DAV source
  connection form, and a compact message-list leading gutter.
- **Changes:** Sidebar disclosure controls now trail folder content on macOS
  and iOS; macOS uses a 16pt disclosure hit target and matching 16pt folder
  depth indent. `PIMSourceConnectSheet` now uses a native grouped Form on
  macOS (default Form presentation on iOS), native picker/text-field chrome,
  localized section labels and footers, and validation callouts after input
  or attempted submission. `MessageListRow` now uses compact spacing and
  checkbox/unread-dot/avatar/content order; inline child rows already matched
  that order. Updated only the affected sidebar and message-row snapshot
  baselines through `RECORD_SNAPSHOTS=YES`.
- **Verified:** `swift test --filter FolderSidebar` passed (42 tests);
  `swift test --filter MessageListRow` passed (14 tests); BrevSettings PIM
  tests passed (35 tests in 3 suites); `scripts/lint.sh` passed; the macOS
  mock build passed and launched `Brev Test (2026-09-26).app`.
- **Skipped:** The requested iOS build could not resolve a destination:
  `xcodebuild` reported `iOS 26.5 is not installed` while the available
  simulator runtimes were iOS 26.5 and 27.0. The existing iOS simulator app
  was nevertheless relaunched successfully with mock mode. No visual
  inspection was performed.
- **Handoff:** The selected validation visibility variant is
  `didAttemptSubmit || hasAnyInput`, because `canSubmit` is validity-gated
  and pristine forms should not show warnings. PR checks were inspected
  separately and were green at the time of inspection.


## 2026-09-26 — Agent — D1/D4/D7 error-surfacing fixes (PRs #113, #114, #115)

- **Goal:** Fix QA matrix findings D1 (DAV connect sheet shows no server
  error on iOS), D4 (TLS-failure callout ~30 s late) and D7 (failed
  first-time add flips title to "Reconnect your mailbox").
- **Changes:** `PIMSourceConnectSheet` renders `model.lastError` inline
  after the first submit (PR #113, BrevSettings + snapshot test);
  `URLSessionPIMDAVTransport` gains `requestTimeout` and `PIMDAVClient`
  defaults it to 15 s for setup validation only (PR #114, ADR-0072
  updated); `LoginView` gates reconnect copy on
  `authFailedIMAPAccountEmail` (PR #115).
- **Verified:** lint.sh + format.sh clean on each branch; new
  `transportHonoursRequestTimeout` passes (dead endpoint fails ~0.6 s);
  new `davConnectSheetRendersSubmissionError` snapshot recorded and green
  on iPhone 17 / iOS 27.0.
- **Device verification:** handed to the UI testing pass (stub DAV
  wrong-credentials on iOS sim; manual-add failure copy on macOS).


## 2026-09-26 — Agent — D4 DAV setup timeout (PR #114)

- **Goal:** Bound DAV connect/reconnect validation so dead endpoints and
  stalled TLS handshakes surface an error inside ~15 s (QA D4).
- **Changes:** `URLSessionPIMDAVTransport(session:requestTimeout:)` —
  `timeoutIntervalForRequest`, default 60 s unchanged for the shared
  sync services; `PIMDAVClient` (setup-validation only) defaults to 15 s.
  ADR-0072 contract bullet updated.
- **Verified:** new `PIMDAVClientTests.transportHonoursRequestTimeout`
  passes (dead endpoint errors in ~0.6 s); lint.sh + format.sh clean.


## 2026-09-26 — Agent — D7 reconnect-copy gate (PR #115)

- **Goal:** Stop "Reconnect your mailbox" appearing after a failed
  first-time manual account add (QA D7) — nothing is stored to repair.
- **Changes:** `LoginView.connectionSectionTitle` and the repair subtitle
  now gate on `session.authFailedIMAPAccountEmail` (stored-account
  re-auth marker) instead of `signInError`. The failure callout itself
  is unchanged.
- **Verified:** lint.sh + format.sh clean; existing LoginView snapshot
  tests unaffected (repair state not injectable — `private(set)`).


## 2026-09-26 — Agent — Issue #2 missing Google config guidance

- **Goal:** Acceptance row — "missing Google client configuration produces
  actionable setup guidance" — previously the onboarding simply omitted the
  Google row.
- **Changes:** `AppSession.googleOAuthConfigIsInvalid` exposes the explicit
  config-check failure (`googleOAuthIsConfigured == false`); `LoginView`'s
  no-Google branch now renders a caption explaining the build lacks the
  client ID before the existing Add-mail-account controls. New compact
  snapshot `compact-google-unconfigured`.
- **Verification:** `scripts/lint.sh` + `scripts/format.sh` clean;
  `swift test --filter LoginViewSnapshotTests.compactGoogleUnconfigured`
  passes with a fresh macOS baseline (hint + Add mail account visible).
  iOS rendering shares the same `LoginView`; the iOS leg is covered by the
  session's O5 verification pass.
- **Handoff:** Nil (`googleOAuthIsConfigured` unset, e.g. tests/minimal
  fixtures) keeps the hint hidden — only an explicit check failure shows it.


## 2026-09-26 — Agent — DAV 401-challenge classification (D1 follow-up)

- **Goal:** Device verification of the D1 in-sheet callout showed real
  DAV servers answer wrong credentials with `401 + WWW-Authenticate`,
  which URLSession reports as `.userCancelledAuthentication` —
  `mapTransportError` classified it `transportFailed`, so the sheet
  showed "could not be reached" instead of the credentials copy.
- **Changes:** `PIMDAVClient.mapTransportError` maps
  `.userCancelledAuthentication` to `.authenticationRequired`; ADR-0072
  contract bullet documents both 401 shapes.
- **Verification:** new `challengedAuthenticationRequired` test in
  `PIMDAVClientTests`; suite 13/13 green; `lint.sh` + `format.sh` clean.
- **Handoff:** Verified on-device by A/B (bare-401 vs challenge-401
  stubs); the in-sheet text now matches macOS for the stub's real-world
  answer.

## 2026-09-26 — Agent — QA matrix + lifecycle doc update (D/O fixes verified)

- **Goal:** Record the D1/D3/D4/D7/O5 verification outcomes on
  `docs/qa/pim-parity-matrix.md` and close out the truncated O5
  paragraph in `account-lifecycle-2026-09-26.md`.
- **Changes:** 1.7 iOS ✓ (fixed #113; 401+challenge copy #117), 1.8
  iOS ✓ (~15 s bound, #114; macOS cells kept ⚠ — not re-verified on
  device), defect table statuses D1/D3/D4/D7/O5 resolved; O5 doc now
  explains the xcodebuild-override mechanism (`tuist generate` does not
  bake the client ID).
- **Verification:** device pass on iPhone 17 sim iOS 27.0 (Devin
  session 82de84bd); D3 re-verified as already-fixed by #101.
- **Handoff:** D2 (stale-href 412-forever) remains the one open
  calendar defect; iOS VoiceOver row 5.1 still untested.
## 2026-09-25 — Agent — AI sidebar assessment + chip/composer polish (#100)

- Assessed the AI sidebar live on macOS mock (sender card, Actions,
  scope chips, empty state, no-provider callout, composer). Findings:
  the panel is structurally solid — privacy line, honest disabled
  state, notice-with-CTA all present — with three fixable gaps:
  disabled scope chips silently dimmed, no keyboard send path, and a
  "no provider" message tripled across callout + placeholder + empty
  state (the last kept deliberately: callout explains, field previews).
- Disabled scope chips now carry a `.help` tooltip explaining what
  unlocks them ("View a single account to search all its folders."),
  via `chipDisabledHelp` on the scope context — unified inbox disables
  the account chip (`sourceID == nil`) so the hint resolves the
  otherwise-unexplained dimming.
- ⌘Return sends the chat question from the composer (Return keeps
  inserting newlines in the multi-line field); the field's AX hint
  advertises the shortcut.
- Verified: `swift test --filter MailboxChatScopeContext` 6/6 green
  (new contract test), 74-chat-suite run green, lint/format clean.
  The 8 MailContextColumn snapshot diffs reproduce identically on the
  unmodified tree — same env-vs-baseline mismatch documented above.
- Deferred: hiding the disabled composer entirely when `disabledReason
  != nil` (arguable — the greyed field previews the unlocked feature);
  snapshot re-record on the canonical host.
- Follow-up: `showIcons: false` now also hides the "All Inboxes" tray
  icon so icons-off is a fully text-only rail; the existing
  `allInboxesGlobalAlignment` no-icons case covers it (baseline still
  needs the canonical-host re-record — one new legit diff on top of
  the 11 env mismatches, verified by stash A/B).


## 2026-09-25 — Agent — Sidebar PR review follow-ups (#100)

- `FolderPreferences` gains a custom decoder: absent keys fall back to
  defaults, so pre-`showIcons` backups decode instead of `keyNotFound`
  rejecting the whole settings payload (Codex P1). New test covers a
  pre-icon backup payload.
- ADR-0056's synced allowlist now lists `folders.showIcons`; CHANGELOG
  Unreleased records the sidebar alignment + toggle + sender chip.
- `allInboxesGlobalAlignment` snapshot now covers `showIcons: false`
  too. Baselines for the new metrics + the no-icons image still need
  `RECORD_SNAPSHOTS=YES` on the canonical macOS 26+ host — this box's
  renderer differs from the recorded baselines (the known env diffs).
- Verified: `swift test --filter FolderPreferences` (5 green),
  `swift build --build-tests` on BrevMail, lint.sh + format.sh clean.


## 2026-09-25 — Agent — Sidebar flush-left + icon toggle + AI-sidebar polish

- Folder rows now flush-left under the section headers: macOS
  `folderRowBaseLeadingPadding` 4→0 and `folderRowDepthIndent` 12→8;
  iOS `folderRowDepthIndent` 16→12.
- New `folders.showIcons` pref (default true, synced) hides sidebar row
  icons for a compact text-only rail; Settings → Mailbox View →
  Folders → "Sidebar icons". Wired FolderPreferences → BrevMailRootView
  (@AppStorage) → FolderSidebarVisibilityPreferences → FolderSidebar
  guards (action rows, role icons, iOS list-row leadings).
- AI sidebar: sender scope chip shows the email local part instead of a
  mid-domain-truncated address; full address stays on the AX label.
- Verified: macOS device build (icons on/off via defaults), iOS sim
  (icons on/off), `swift test --filter 'MailboxChatScope|FolderSidebarPresentation'`
  (42 green), lint.sh + format.sh clean.


## 2026-09-25 — Agent — PR #93

**Goal:** Sidebar header consistency + alignment follow-up (Henrik's Apple Mail comparison screenshots).

**Changes:**
- `FolderSidebar` — unified all macOS section headers to one Apple Mail-style treatment: `caption` + `semibold` + `textSecondary`, flush-left at the disclosure column (`folderRowBaseLeadingPadding`), disclosure chevron trailing the label (10pt semibold, `textTertiary`) — matches Mail's "Favoritter / Smarte postkasser / Google" edge and the existing iOS text-then-chevron pattern.
- `profileSwitcher` (macOS): downgraded from `.body`/semibold/`textPrimary` title to the shared header style (was the inconsistent large header in the screenshot); now uses `sourceHeaderMinimumHeight` + `sourceHeaderVerticalPadding`.
- `mailboxDisclosureHeader` + `smartViewsSection` (macOS): reordered to label-then-chevron so header text sits flush-left at the chevron column instead of the icon column.
- Removed now-unused `sidebarHeaderLabelLeadingPadding`.

**Verification:** `scripts/lint.sh` + `scripts/format.sh` clean; rebuilt `Brev Test (2026-09-24).app` in mock mode and visually verified on device — "Mailboxes", "Smart Views", and both source headers share one flush-left muted header style; folder chevrons, icons, labels, and counts all sit on shared columns.

**Skipped:** iOS — branches untouched (headers already used label-then-chevron); snapshot baselines have pre-existing env drift.

## 2026-09-25 — Agent — Platform parity + performance smoke pass

- **Goal**: Post-merge iOS/macOS parity assessment + performance benchmark vs
  #304 budgets (user request).
- **Changes**: `docs/qa/platform-parity-2026-09-25.md` (parity matrix),
  `docs/qa/results/performance-mock-2026-09-25.json` (budget JSON),
  `performance-baseline-2026-09.md` Live-measurements section,
  `scripts/collect-performance-trace.sh` `--info` fix (export was silently
  empty — Performance events log at info level).
- **Verification**: both apps driven on identical mock fixtures; trace
  collected via fixed collector on macOS and `simctl spawn log show` on iOS;
  budget gate run and violations recorded in the doc.
- **Findings**: first rich-HTML thread open 1222 ms (over 600 ms hard limit,
  n=1, WKWebView first paint — needs warm live re-measure);
  `cached_inbox_query_ms` not measurable in mock; all other budgets pass or
  pass-by-proxy; parity confirmed on all user-visible surfaces.
- **Skipped**: true scroll frame p95 and the full #28 §5 live run — needs
  Instruments + a real mailbox.

## 2026-09-25 — Agent — Focused-pane selection tint (a11y follow-up)

- **Goal**: restore a visible keyboard-focus indicator after #95 removed the
  column outline, without reintroducing a drawn ring (Codex P1 on #95:
  keyboard-only users had no focus signal at all).
- **Changes**: `BrevSelectionPalette` `isActive: false` now demotes the
  selected-row fill from `selection` to `bgSecondary` (the Apple Mail
  focused-pane-owns-the-tint cue, documented in ADR-0002); `MessageListRow`
  gained `isFocusedPane` fed by `listKeyboardFocus`; the sidebar palette is
  keyed on `sidebarKeyboardFocus`; the sidebar claims focus on appear so an
  empty launch still lands arrows on the mailbox column (Mail cold-start).
- **Verified**: lint + format clean; live app — click list → list accent
  tint + sidebar muted; arrows move the focused pane's selection; mailbox
  activation hands focus to the list; no outline anywhere.
- **Skipped**: none. The 22 pre-existing snapshot env diffs reproduce
  identically on clean main on this machine — no new failures.

## 2026-09-25 — Agent — Settings sidebar flush-left + shared icons toggle (#100)

- **Goal**: Henrik asked for the mail-sidebar treatment in Settings too —
  rows aligned left under their section headers ("App", "Reading &
  Composing", "Organization") and honoring the same icons on/off toggle,
  on iOS and macOS.
- **Changes**: `SettingsView` — macOS sidebar rows `listRowInsets` leading
  4 → 0 so row content aligns under section headers; `sectionRow` and
  `pluginSettingsRow` gate their 18pt icon column on the same
  `folders.showIcons` pref (`@AppStorage`) the mail rail uses, so the
  Mailbox View → Folders → "Sidebar icons" switch compacts every rail at
  once. iOS compact + sidebar rows pick both up automatically.
- **Verified**: lint + format clean; `swift build` green; live app —
  toggle ON restores icons in settings + mail sidebars (icon column sits
  under section headers, Apple Mail layout), toggle OFF renders the dense
  text-only rail in both; A/B test run confirms the 34 BrevSettings
  snapshot diffs fail identically on clean HEAD (pre-existing macOS
  baseline env diffs — zero new failures from this change).
- **Skipped**: none.

## 2026-09-25 — Agent — iOS settings tap fix (found while verifying #100)

- **Goal**: while verifying the settings icons toggle on iOS, every
  settings row tap was dead — the whole section list was un-navigable.
- **Root cause**: `compactSettingsRows` wrapped each `NavigationLink` in a
  `.simultaneousGesture(TapGesture().onEnded { navigation.select(...) })`.
  The competing gesture suppressed link activation — confirmed via A/B
  build (dead on the parent commit too, so pre-existing, not from the
  icons-off change).
- **Fix**: drop the gesture; call `navigation.select(section)` in the
  pushed view's `.onAppear` instead — same sync timing, no conflict.
- **Verified on device**: Mailbox View, Accounts, etc. now navigate; the
  Folders scope picker, toggles, and the "Sidebar icons" pref all live and
  govern the iOS rail + settings icons identically to macOS.

## 2026-09-24 — Agent — Fix ComposePresentationTests overflow expectations

- `ComposePresentationTests` expected `overflowActions` without the new
  `.discardDraft` entry added in a367be9; updated the macOS + compact-iOS
  expectations and the accessibility value string so the BrevMail suite
  passes on this branch. Verified: `swift test --filter ComposePresentation`
  (57 tests green).

## 2026-09-24 — Agent — Round-2 verification fixes (PR #93 findings)

- Goal: fix the six findings the recorded round-2 verification pass
  reported on `a367be9` plus the N1 keyboard-nav remainder.
- Changes:
  - Calendar toolbar vanish (release-affecting): `.toolbar` items on
    the NavigationSplitView sidebar column only propagate to the macOS
    window titlebar when the column content is a `List` — the
    grid-mode views (`ScrollView`) silently dropped the layout picker,
    date navigation, New Event, and Sync. Replaced with a deterministic
    in-view `navigationHeader` (menu-style picker + date nav + actions)
    that renders identically in every mode on both platforms.
  - Compose Discard Draft: the `discardDraft` action existed in
    presentation + a11y strings but no menu rendered it — closing a
    compose window still silently saved. Wired a destructive
    `Discard Draft` item (trash icon) into the macOS overflow and iOS
    compact menus; `discardDraft()` cancels autosave, calls
    `backend.discard(draftID:)`/`(draftID:sourceID:)`, and closes
    without saving.
  - P5 HTML sent copies: `ComposeHTMLBodyPolicy.html(fromEditorText:)`
    escaped `>` quote markers to `&gt;` so sent copies showed literal
    `> ` lines. Consecutive `>`-prefixed runs now emit a real
    `<blockquote>` (already styled by the reader's blockquote CSS and
    every recipient client); `editorText(fromStoredHTML:)` round-trips
    blockquotes back to `>` lines so draft reopen keeps the quote.
  - P11 Find settings: validation warnings were silent no-ops —
    `statusAndGuidanceSection` only mounts after
    `didStartDiscoveryProbe`, but the validation early-return happened
    before the flag was set. Flag now marks before validation in both
    `discover` and `applySkip`.
  - N6 iOS reader overflow: the thread `…` menu held only thread
    controls — Reply/Reply All/Forward/Snooze were long-press only.
    iOS menu now leads with the consolidated per-card inventory acting
    on the thread's latest message.
  - N1 remainder: `focusSection()` puts sidebar + message list in the
    macOS Tab key loop, and arrow-key input now claims container focus
    so the accent focus ring actually appears.
- Verification: `swift build` clean; `swift test` filtered suites
  99/99 (ComposeDraftBuilder +2 round-trip tests, ComposePresentation,
  IMAPAccountSetup); `scripts/lint.sh` OK; swiftformat 0 changes.
  On-device verification pending on this commit.
- Skipped: P6 iOS stale calendar data — pending investigation
  (suspected environment artifact, not code).
- Next: merge into the stacked composer branch (PR #94); recorded
  re-verification of the six items.

## 2026-09-24 — Agent — Round-2 verification follow-ups (PR #93 re-verification findings)

**Goal:** Fix the two code-change findings from the `c2ae433` re-verification pass and one minor label wrap.

**Changes:**
- `MessageListView` — moved the macOS focus machinery (`focusSection`/`focusable`/`focused`/`focusEffectDisabled`/arrow+Return handlers/accent ring) off the `List` onto a wrapping `Group`: a `List`'s AppKit backing never joins the key loop, so the column could never be focused. `selectMessage` now also claims `listKeyboardFocus` so pointer interaction marks the list as the keyboard surface (Apple Mail ring-follows-focus).
- `MailNavigationState` — added `messageListFocusRequestID` token + `requestMessageListFocus()`; `MessageListView` observes it and claims focus.
- `FolderSidebar` — `.return` on a highlighted destination and `→` on a leaf call `onOpenMessages` (drill into the list, Finder column-view style); Outbox keeps its own activation on both.
- `BrevMailRootView` — `onOpenMessages` on macOS bumps `requestMessageListFocus()`, so any mailbox activation hands the keyboard to its list.
- `MockBackend.removeDraft` — discard now matches the draft's local id *and* its staged folder id (`draft-<id>`/remoteID), matching the local-id contract `IMAPSMTPBackend.discard` exposes. Fixes the iOS Discard leak where an auto-persisted reply draft survived because the composer's `draftID` (local UUID) never matched the `draft-<uuid>` folder key. New `discardByLocalIDRemovesSavedDraft` test covers it (and caught the first incomplete attempt at the fix).
- `CalendarRootView` — `.fixedSize()` on the layout Picker so "Month" stops wrapping to "Mont h" on iOS.
- `.agents/skills/testing-brev-ui/SKILL.md` — added sim PIM-source injection, focus-state AX caveat, and the ⌘W-keepalive/`reopen` note from the verification pass.

**Verification:** `swift test --filter discard` — 4/4 green incl. new test; `swift test` BrevMail 1869 tests, 84 issues all in `*SnapshotTests.swift` (pre-existing env baseline drift, zero functional failures); `swift build` macOS clean; `scripts/lint.sh` + `scripts/format.sh` clean.

**Skipped:** Device re-verification (testing agent) — pending.

**Handoff:** P11 (Add-account Find-settings) remains mock-limited — needs `imapAccountDiscoveryCoordinator` wired into the demo session or real-session verification.
- `AppSessionFactory` — demo session now gets an offline
  `imapAccountDiscoveryCoordinator` (built-in profile table + manual
  fallback only, no DNS/autoconfig) so the Find-settings flow — and
  the P11 validation status surface — is exercisable in mock mode
  without violating the zero-network default.

## 2026-09-23 — Agent — Round-2 UI/UX + a11y audit @ 4617777

- Rebuilt both apps off `4617777` and ran a recorded full-surface pass
  (mail, compose, PIM surfaces, settings, chrome, a11y readback).
- No release blockers; stub DAV sources now populate Calendar/
  Contacts/Tasks in mock. All #85 fixes hold; #89 verified.
- Findings + improvement roadmap in `docs/qa/uiux-audit-2026-09-23.md`:
  top items are macOS keyboard nav (N1, a11y), dark-mode empty panes
  (N2), macOS calendar rail confinement (N3), iOS reader menu parity
  (N6), compose quote hygiene (N5).

## 2026-09-23 — Agent — Release validation + calendar title TZ fix

- Full-suite validation on repaired main `14923a8`: every package
  functionally green (BrevBackend 1141, BrevCalendar 239, BrevGmail 160,
  BrevAI 52, others); BrevMail/BrevSettings pixel-snapshot diffs are
  pre-existing baseline/env mismatches reproduced on clean main.
- Runtime regression matrix re-run on both rebuilt apps: all 13
  verifiable items pass (see `docs/qa/release-validation-2026-09-22.md`).
- Fixed `CalendarGridLayout` day/week/month titles rendering in the
  system time zone rather than the passed calendar's (found by the
  date-dependent "range titles render per mode" test on PDT).

## 2026-09-23 — Agent — Re-land PR #85 after stale-base squash revert

- The #86 squash merge (`295d439`) carried a tree built before #85
  landed, silently reverting all 29 #85 files on main; #87 merged on
  top of that state. Re-applied #85's hunks onto `55d45ee` via a real
  3-way merge (overlap files: `WORKLOG.md`, `ContactsRootView.swift`
  — both merged cleanly with #87's additions preserved).
- Verified: all 29 restored files byte-identical to `38e9c35`;
  `lint.sh`/`format.sh` clean; 68 focused tests in 5 suites pass.
- Runtime re-verification on rebuilt apps follows before release.

## 2026-09-23 — Agent — Sent-copy markup rendering fix (release-validation nit)

- Goal: fix the reader showing literal `<br>`/`&lt;` markup on sent-copy
  bodies flagged in `docs/qa/release-validation-2026-09-22.md`.
- Root cause: two layers. `MockBackend` stored `draft.htmlBody` as the
  sent/draft copy's `plainText` with `html` unset, so plain-text surfaces
  (reader body, list snippet, reply quotes) rendered raw markup. And the
  real `MIMEMessageBuilder` built the `text/plain` alternative via a naive
  tag-strip that never unescaped entities and concatenated paragraphs —
  `&lt;` leaked into real outbound plain parts too.
- Changes: `HTMLTextStripper` gains `plainText(from:)` — block/`<br>`/`<hr>`
  boundaries become newlines, remaining tags spaces, entities unescaped,
  per-line whitespace collapsed. `MockBackend` sent/draft copies now mirror
  real mail: `html` = draft markup, `plainText` = stripped rendering,
  snippets stripped. `MIMEMessageBuilder` delegates its `text/plain` part
  to the same helper.
- Verification: 5 new/targeted cases green (sent-copy split + readable
  plain alternative), full MockBackend/MIMEMessageBuilder/IMAP parser/
  outbound suites 123/123, BrevMail compose/quote/detail suites 67/67,
  lint.sh + format.sh clean.
- Skipped: E2E render pass in the app (plain-text fix is unit-covered;
  reader path unchanged — it was fed bad data).
- Next: PR for review; parity-matrix stub-DAV rows continue separately.

## 2026-09-23 — Agent — Issue #11 stub-DAV parity rows (C/D mac)

- Goal: fill the CalDAV (C) and CardDAV (D) macOS cells of
  `docs/qa/pim-parity-matrix.md` that a localhost stub can honestly
  cover, ahead of maintainer live fixtures.
- Changes: `scripts/stub-dav-server.py` — a single-file Python stub
  speaking enough RFC 4791/6352/6578 for real flows: PROPFIND discovery
  (principal → home set → collections), sync-collection REPORT with
  sync-token expiry control, query/multiget REPORTs, GET, conditional
  PUT (If-None-Match/If-Match → 201/204/412), DELETE, optional Basic
  auth. Matrix filled for §1.6/1.7, §2.1/2.3/2.4/2.5⚠/2.9/2.10,
  §3.1/3.4/3.5/3.7/3.8, §4.1*/4.2/4.5/4.6⚠, §6.1 with wire-log line
  refs; wire logs + two evidence screenshots committed under
  `docs/qa/pim-parity-stub-dav-2026-09-23/`.
- Verification: stub smoke-tested with curl (207/401/412/201/204 paths,
  sync-token expiry); all UI cells driven end-to-end in the mock build
  via the real "Add DAV Source…" connect sheet.
- Found during verification (real defect): sync refreshes a cached
  item's etag but never its href — a server-side rename leaves the
  record pointing at a dead path and every subsequent write 412s with
  no self-heal (wire log L22/L27/L31). Also `lastError` callouts are
  never cleared on fresh editor opens (cosmetic).
- Skipped: iOS cells, Google fixture (none exists), §2.6–2.8
  recurrence/invite/RSVP and §3.6 groups (stub lacks multi-collection
  scheduling surface), §1.8 TLS failure (stub is plain http loopback).
- Next: maintainer live fixtures; stale-href defect proposed as a
  follow-up fix.

## 2026-09-23 — Agent — DAV stale-href write defect (found via #11 stub pass)

- Goal: fix the defect the stub-DAV parity pass surfaced — a synced
  event whose resource lives at a non-`{uid}.ics` href (server-side
  rename, or a server that never followed the RFC 4791 filename
  convention) stayed permanently unwritable; every PUT went to a dead
  path and 412'd as `conflict` with no self-heal.
- Changes: `PIMDAVEventWriter.update`/`delete` now address the stored
  `providerItemKey` href (new `hrefURL(for:)`), matching the contact
  and task writers; `create` keeps the `{sanitized-uid}.ics`
  convention. Sync merges in `PIMEventSyncService`,
  `PIMContactSyncService`, and `PIMTaskSyncService` drop a cached
  record when an incoming item shares its UID (and recurrence-id for
  exceptions) under a different href — new `PIMSyncItemIdentity`
  type — so a rename without a tombstone self-heals instead of
  shadowing the live record.
- Verification: `swift test` BrevCalendar 241/241 — new
  `davUpdateTargetsStoredHref` (writer targets stored href for both
  update and delete) and `davSyncSupersedesStaleHref` (delta sync
  drops the stale record, keeps the live one + untouched items);
  existing DAV update/delete/conflict tests updated to pass real hrefs
  and assert request URLs.
- Skipped: iOS E2E (writer fix is transport-level; sync merge is
  platform-independent). `CalDAVEventWriter` (invite-acceptance
  single-target flow) intentionally unchanged — it only creates.
- Next: merge; matrix §2.5 can flip to clean ✓ on the next pass.

## 2026-09-22 — Agent — Issue #11 parity matrix + closure-readiness sweep

- Added `docs/qa/pim-parity-matrix.md`, a fillable verification matrix
  covering every acceptance criterion of #11 (source lifecycle,
  calendar/contacts surfaces per provider, cross-source integrity,
  platform gates, privacy, final evidence table).
- Posted closure-readiness comments on issues #53, #5, #6, #7, #8,
  #10, #12, #13 (all slices merged; gate is maintainer QA), the R8
  Drive-source-kind recommendation on #14 (keep it an attachment path),
  and the maintainer-gated live-QA flag on #11 with the matrix link.
- Verification: docs only. Next: Henrik runs the matrix against live
  fixtures.

## 2026-09-22 — Agent — UI/UX audit fixes (docs/qa/uiux-audit-2026-09-22.md)

### Goal

Fix the confirmed findings from the same-day dual-platform UI/UX audit
(`docs/qa/uiux-audit-2026-09-22.md`): C1 smart-view filter leak, C2 iOS
PIM covers rendering as voids, C3 drafts dead-end on tap, plus the cheap
menu/footer/empty-state nice-to-haves (N1–N3, N5, N8, N11–N13). C4
(quit-on-last-window) and N4 (shortcut help inventory) verified as
non-issues; N6/N7/N9/N10 deferred as non-cheap.

### Changes

- C1: unified inbox re-seeds `mailboxFilter` to the smart view's own
  query on selection and clears it back to `.none` when leaving the
  view, so folder lists no longer inherit smart-view filters.
- C2: Calendar/Contacts/Tasks iOS covers now render the same empty-state
  surfaces as macOS instead of a blank cover.
- C3: draft rows in Drafts folders route through
  `MailComposePresentationActions.openDraft` →
  `MailNavigationState.presentDraft` → `ComposeView(existingDraft:)`,
  which seeds To/Cc/Bcc/Subject/body/draftID/remoteID so re-saving
  supersedes the same draft. `MailBackend.draft(for:)` added (default
  `nil`; IMAPSMTPBackend indexes staged drafts) as the richer restore
  path when a backend holds one.
- Menus: single AI Sidebar entry in a dedicated View group, deduplicated
  Calendar/Contacts/Tasks window commands, Keyboard Shortcuts help
  inventory reconciled. Message-menu alternate bindings (⌘U, ⌘S, ⌘F,
  ⌘[/⌘]) moved into an "Alternate Shortcuts" submenu — top level shows
  each action once while the key equivalents stay registered.
- N5: PIM sidebar columns get `navigationSplitViewColumnWidth` so the
  ~90pt rail no longer wraps copy mid-word.
- N8: iOS bottom-bar floating pill gets a reserved scroll-content margin
  so the last row isn't covered (`brevBottomBarScrollInset`).
- N11: `MessageListPresentation.emptyStatus` gains smart-view /
  saved-search scoped empty-state copy.
- N12: folder-stats footer on smart views/saved searches reports the
  view's own visible totals instead of unified-inbox aggregates.
- N13: Snooze/Unsnooze added to the macOS reader "…" toolbar menu for
  parity with the shared `messageMenu` inventory.
- Tests: `MessageListPresentationTests` gains empty-state coverage;
  `MailComposePresentationActionsTests` /
  `MailContextColumnSnapshotTests` updated for the `openDraft:` init.

### Round 2 — deferred findings N6/N7/N9/N10

- N6: `MessageListRow`'s `SpatialTapGesture` fired on secondary clicks,
  running `onActivate` and swallowing the context menu. macOS now
  ignores the tap for `rightMouseUp` and selects the row instead, so
  right-clicking any row selects it and opens its menu.
- N7: autocomplete suggestions extracted to `RecipientSuggestionList`,
  rendered as full-width rows below the field on both platforms
  (previously capped at 360pt).
- N9: draft autosaves that complete after the compose sheet dismisses
  (the completion request is torn down on sheet change) no longer drop
  their feedback — "Draft saved." toast now shows on iOS too.
  Send-result feedback stays request-gated.
- N10: thread cards and the reader share one header pattern — expanded
  cards render `displayName + <email>` and the shared
  `MessageDetailPresentation.collapsedRecipientLine` ("to A, B + N
  more"); collapsed cards keep the compact name/snippet line.
- Tests: `MessageDetailPresentationTests.collapsedRecipientLineMatches
  ReaderAndCards`; new iOS snapshot tests
  `threadMessageCardExpandedRenders` + `recipientSuggestionListRenders`
  registered in the snapshot lane's `-only-testing` list.

### Verification

- macOS `Brev Test (2026-09-22).app` (mock): VIP smart view → folder
  restores contents (C1); draft row reopen restores composer fields
  (C3); View/Message/Window menus show single entries (N1–N3); VIP
  footer reads "0 messages · 0 unread" (N12) with per-view empty copy
  (N11); Snooze… in reader "…" menu (N13); Calendar sidebar fits copy
  (N5).
- iOS sim (iPhone 17, iOS 27.0, mock): Calendar/Contacts/Tasks covers
  show proper empty states + Done (C2); compose ✕ autosaves a draft and
  tapping it reopens the composer with fields restored (C3); last inbox
  row clears the bottom pill (N8); VIP empty copy shown (N11).
- `swift test --filter MessageListPresentationTests|
  MailComposePresentationActionsTests|UnifiedInboxThreadGroupingTests`:
  37/37 pass. `scripts/lint.sh` and `scripts/format.sh` clean.
- Round 2: right-click on unselected "Ledger & Co" row selects it and
  opens the full context menu (N6); iOS compose "ing" query renders
  full-width suggestion rows that tap into chips (N7); closing compose
  with content shows "Draft saved." toast on iOS (N9); expanded thread
  card header matches the reader header — name + <email> + "to …"
  (N10). All four verified live by recorded QA pass.
- `swift test --filter MessageDetailPresentationTests`: 26/26 pass.
- Skipped: pixel-snapshot re-baselines for the two NEW snapshot tests
  (baselines record on first iOS-27 run; metadata check unaffected).

### Next

- PR targets main on `fix/uiux-audit-sep22`. All audit findings
  (C1–C4, N1–N13) are now addressed or verified as non-issues.


## 2026-09-22 — Agent — PR #82 review follow-up

- Confirmed review thread discussion_r4070538784: saving profiles reconciled
  navigation before the cached profiles received the saved membership.
- Assign the normalized profile cache synchronously before resolving the active
  profile and reconciling reader/mailbox selection. Persistence observation
  remains in place for external changes.
- Verification: all 11 MailProfile tests and scripts/lint.sh pass. No new snapshot:
  layout is unchanged. Native interaction QA is not yet performed. The private
  SwiftUI save handler is reviewed directly; existing tests cover the profile
  selection policy, not mounted-view callback ordering.
- Documentation sweep: changelog/worklog updated; architecture, privacy,
  provider behavior, setup and release procedures are unchanged.

## 2026-09-22 — Agent — Issue #81 (performance/stability pass)

### Goal

Audit-driven performance and stability pass across iOS and macOS,
fixing only confirmed hot-path allocations and per-render decodes.

### Changes

- `BrevMailRootView`: `cachedVIPSenderEmails` and
  `cachedCustomProfiles` @State caches replace per-body-eval
  `VIPSenderSettings.load()` (UserDefaults + JSON decode) and
  `MailProfileStorage.decode` calls; refreshed via onChange on
  the backing `AppStorage` values, matching the existing
  `cachedMailboxSourcePreferences` contract.
- New seams: `VIPSenderSettings.decode(_:)` and
  `MailProfileStorage.load()/storageKey`.
- `GmailAPIBackend`: shared RFC 2822 formatter for per-message
  Date-header parsing and a shared yyyy/MM/dd formatter for search
  query date ranges.
- `ICSParser`: TZID-keyed lock-guarded DateFormatter cache for
  zoned date parsing; `PIMDAVEventSync.icalTimestamp` and
  `MeetingTimeSuggestionFormatter` use shared/cached
  formatters. ADR-0072 note added (protected path).
- Audited, no change needed: snippet regex/preview caches in
  `MessageListPresentation`, `MessageListDatePresentation`,
  `SenderContextPanel`, `ThreadConversationRenderPool`
  permit protocol, iOS BGTask scheduling, Gmail Retry-After parsing.

### Verification

- `swift build`: BrevSettings, BrevCalendar, BrevGmail,
  BrevMail all green.
- `swift test`: VIPSender (27), ICS (12), Gmail suites (160),
  MeetingTime/MailProfile/SmartView/VIP (23) — all pass.
- `scripts/lint.sh`, `scripts/format.sh`: clean.
- Skipped: rendered verification — no user-visible behavior change.

### Next

- PR targets main; board → In review on merge.

## 2026-09-22 — Agent — PR #80 review follow-up

- Verified all three export findings in PR #80: same-subject exports overwrote
  bytes still used by share sheets; long Unicode subjects exceeded filesystem
  limits; the single-message error omitted localization.
- Use a unique temporary directory per export, preserving the visible filename;
  cap basename length by UTF-8 bytes including Unicode decomposition, leaving
  space for the extension and atomic-write suffix. Failed writes clean up their
  own directory. Successful exports remain in system temporary storage so a
  share extension can consume them; no persistent mail store is changed.
- Red/green: independent-export and long-Unicode-subject tests failed on main,
  then passed with the fix. Five focused tests and scripts/lint.sh pass.
- No layout or snapshot change; native share-sheet interaction not run.
  Documentation sweep: changelog/worklog updated; no new provider calls,
  architecture, setup or release changes.

## 2026-09-22 — Agent — Issue #79 (iOS/macOS parity gaps)

### Goal

Close the two real parity gaps from the 2026-09-22 audit: .eml export
on iOS and a Keyboard Shortcuts surface for iPad hardware keyboards.

### Changes

- `MessageEMLExport.writeToTemporaryFile`: cross-platform temp-file
  writer for the iOS share-sheet path (subject-named .eml, overwrite
  semantics).
- Reader + thread card .saveAs on iOS now export locally through
  `MailShareSheet` instead of routing to the macOS save panel; the
  `canExportEML` menu gate is lifted on reader surfaces (row menus
  stay macOS-only by design).
- New `MailHelpActions` focused value + `MailNavigationState.Sheet
  .keyboardShortcuts`; iPadOS gets a Help → Keyboard Shortcuts
  command menu presenting the shared reference view as a sheet.
  `MacMailAuxiliaryWindowPresenter` gained the exhaustiveness case.

### Verification

- `swift build --package-path packages/BrevMail`: green.
- `swift test --filter 'EMLExport|HelpActions'`: 6 new tests pass
  (temp-file naming/sanitizing/overwrite, help action forwarding).
- `tuist build BrevIOS`: green — iOS code paths compile.
- `scripts/lint.sh`, `scripts/format.sh`: clean.
- Skipped: rendered share-sheet/Help-menu verification on device —
  deferred to maintainer QA.

### Next

- PR targets main; board → In review on merge.

## 2026-09-22 — Agent — Issue #14 slice 2 (event Drive attachments + upload progress)

### Goal

Close the remaining codeable scope of #14: attach a Drive file to a
calendar event as a link, and give Drive uploads determinate progress
with a working cancel.

### Changes

- `PIMEventAttachment` on `PIMEvent`; ICS `ATTACH;VALUE=URI`
  parse/emit (`FMTTYPE`, `X-FILENAME`); Google `attachments[]`
  body entries + `supportsAttachments=true` on event insert/patch;
  attachment mapping in both event sync services.
- `GoogleDriveClient` upload progress: optional
  `onProgress` on create/update, ephemeral-session
  `UploadTransport` with delegate progress and task-cancellation
  propagation (`URLError.cancelled` → `CancellationError`).
- Event editor Attachments section (list/remove + Attach from Google
  Drive gated on Gmail-linked sources via
  `CalendarEditingModel.driveAttachAccountID`), new
  `GoogleDriveEventAttachSheet` (opt-in → picker → link
  attachment), detail view renders tappable links.
- `GoogleDriveSaveSheet`: determinate `ProgressView` + cancel.
- Docs: ADR-0072 slice note, ADR-0006 picker/Drive rows, PRIVACY.md,
  CHANGELOG.

### Verification

- `swift test --package-path packages/BrevBackend --filter GoogleDrive`:
  10 tests pass (new: progress reporting, cancellation propagation).
- `swift test --package-path packages/BrevCalendar`: 226 tests
  pass (new: ICS attach emit/round-trip, Google insert attachments,
  sync mapping).
- `swift test --package-path packages/BrevMail --filter GoogleDrive`:
  16 tests pass (new: pick→attachment mapping, draft round-trip,
  Drive eligibility on linked sources).
- `scripts/lint.sh` + `scripts/format.sh`: clean.
- Skipped: rendered verification (needs a real Google account and
  build-time picker credentials) — deferred to maintainer QA.

### Next

- PR targets main; board → In review on merge.
- #14 remains open for maintainer QA acceptance plus the deferred R8
  "Drive as source kind" decision.

## 2026-09-22 — Agent — Issue #14 slice 1 (Google Drive attachments)

### Goal

Ship the first codeable slice of #14: attach a Drive file (bytes or
link) in compose and save a message attachment to Drive, gated by the
narrow `drive.file` opt-in scope.

### Changes

- New `GoogleDriveClient` in BrevBackend: transport-injected
  Drive v3 calls (metadata, byte download, Workspace export, multipart
  create/update, name-conflict lookup). Stateless — the session
  resolves the account token per call.
- New `GoogleDriveFeature` + `GoogleDriveFileServing`
  adapter in BrevMail: Gmail-API eligibility, `drive.file`
  enablement via the shared Google re-authorization path, enabled state
  read from stored granted scopes.
- New `GoogleDrivePickerView` (WKWebView hosting Google's
  Picker), opt-in prompt, attach sheet (file/export-format/link) and
  save sheet (folder pick + replace/keep-both conflict).
- Wiring: ComposeView Drive menu item, MessageDetailView Save to Drive,
  `AppSession.googleDriveFeature`, AppSessionFactory
  configuration params, both app targets, Tuist-injected
  `BREV_GOOGLE_API_KEY`/`BREV_GOOGLE_APP_ID` Info.plist
  keys.
- Docs: ADR-0006 network table (picker + Drive rows, OAuth row
  updated), PRIVACY.md opt-in section, CHANGELOG, ADR-0072 slice note.

### Verification

- `swift build --package-path packages/BrevMail`: green.
- `swift test --filter GoogleDrive`: 8 BrevBackend client tests
  + 12 BrevMail feature/picker tests pass.
- Skipped: rendered verification — the picker needs a real Google
  account and build-time `BREV_GOOGLE_API_KEY`/`BREV_GOOGLE_APP_ID`;
  deferred to maintainer QA. Snapshot tests not added (sheets are
  WKWebView-hosted; covered by unit tests on outcomes/configuration).

### Next

- PR targets main; board → In review.
- Later slices: calendar-event attachment flow, live smoke evidence,
  R8 decision on Drive as a source kind.

## 2026-09-22 — Agent — Issue #12 slice 3 (retroactive merge note)

PR #76 (tasks browsing UI + Create Task provider targets) merged as
3f597943 after green CI. Its worklog entry was dropped from the PR
before merge; recorded here for completeness. Issue #12 stays open for
maintainer QA acceptance.

## 2026-09-22 — Agent — Issue #12 slice 2 (task write pipeline)

### Goal

Add the provider-neutral task write path on top of slice 1's read-only
sync: create, edit, complete, reorder/reparent, move, and delete for
Google Tasks and CalDAV VTODO sources behind the Editing opt-in.

### Changes

- New `GoogleTaskWriter` (tasks.insert/patch/delete/move REST calls,
  etag If-Match preconditions, cleared fields as JSON null) and
  `PIMDAVTaskWriter` (VTODO PUT/DELETE on the collection URL, stored
  href for updates/deletes, If-None-Match create).
- New `PIMTaskICSWriter` — canonical VTODO serialization mirroring
  `PIMEventICSWriter` (escaping, 75-octet folding, STATUS mapping,
  X-APPLE-SORT-ORDER / RELATED-TO;RELTYPE=PARENT / URL).
- New `PIMTaskWriteService` — capability-gated entry point
  (`.write` capability + non-read-only collection). Google in-list
  reorder/reparent routes through `tasks.move`; cross-collection
  moves are delete+create on both providers (Google Tasks has no
  cross-list move); a post-create delete failure surfaces as conflict.
- `PIMSourceSettingsModel.canToggleWrite` now allows tasks sources
  (Google and CalDAV); Google enablement reuses the existing
  `enableGooglePIMWriteFeature` re-auth path with the `tasks` scope.
- Wired `pimTaskWriteService` into `AppSession`/`AppSessionFactory`.
- Docs: ADR-0072 slice-2 section, ADR-0006 network table (CalDAV task
  write + Google Tasks write rows), PRIVACY.md task-write opt-in
  wording, CHANGELOG.

### Verification

- `swift test --filter PIMTaskWriteTests`: 20/20 pass (ICS writer,
  Google writer, DAV writer, service gating, cross-collection move).
- Full `swift test` on BrevCalendar: 220/220 pass.
- `swift test --filter PIMSourceSettingsModelTests` on BrevSettings:
  21/21 pass.
- Skipped: rendered verification (no task browsing UI yet — a later
  slice), live Google/DAV writes (no test accounts in this session).

### Next

- #12 slice 3: task browsing UI + Create Task from Message target
  integration (`MessageTaskPayload`/`MessageTaskCreationTarget`
  already exist in BrevMail).

## 2026-09-22 — Agent — Issue #49 (compose viewport overflow at accessibility sizes)

### Goal

Fix the compose sheet laying out wider than the phone viewport at the
largest Dynamic Type sizes, clipping fields and hiding Close/Send/More.

### Root cause

Sheet presentations size content to its ideal width. The recipient and
subject UITextField adaptors (and the body UITextView) report their
intrinsic text width as ideal — ~547pt combined at accessibility5 — so
the sheet's content laid out wider than the 320–430pt viewport.

### Changes

- ComposeView: cap the content's ideal width at 320 (narrowest supported
  phone) for compact iOS layouts, and cap the accessibility-layout
  ScrollView's content the same way so it cannot scroll horizontally.
- ComposeView: remove fixedSize from the mobile toolbar title and Send
  label (Send label now capped at xxxLarge via the dense-chrome range);
  drop fixedSize() from the From-row signature picker so it truncates.
- Tests: ComposeAccessibilityBoundsTests hosts the real view at ideal
  width under accessibility5 traits and asserts no laid-out subview
  exceeds 320pt. Fails without the fix (546pt overflow), passes with it.
- CI: added the suite to the iOS Simulator -only-testing list.

### Verification

- iOS Simulator (iPhone 18 Pro, iOS 27): ComposeAccessibilityBoundsTests
  green with fix; red without it (OVERFLOW dump shows 546pt content).
- swift test --package-path packages/BrevMail — logic green; 21
  pre-existing pixel-snapshot failures on this macOS 27 host, all on the
  CI macOS<26 skip list and unrelated to this change.
- scripts/lint.sh — clean.
- phoneCompose snapshots re-recorded byte-identical — the .image(size:)
  strategy does not exercise ideal-width sheet sizing; the new bounds
  test is the regression coverage.

### Skipped

- Real-app rendered verification — the Mac was locked for GUI automation
  and simctl cannot dismiss the system URL-open dialog; maintainer QA on
  #49 covers open/dismiss on device.
## 2026-09-22 — Agent — Issue #51 (reader stuck at Loading message)

### Goal

Diagnose and fix the conversation reader pinning at "Loading message…"
with the main thread looping in SwiftUI layout.

### Root cause

`ThreadConversationRenderPool.withBodyLoadPermit` suspended queued
waiters on a plain `withCheckedContinuation` with no cancellation
handling. A card whose `.task(id: isExpanded)` was cancelled while
queued (collapse, thread switch, scroll off-screen) never resumed —
`loadBody`'s `defer` never ran, `isLoading` stayed true, and the
spinner re-invalidated layout forever. The 15s timeout only covered the
backend read, not the permit wait.

### Changes

- ThreadConversationRenderPool: permit waiters are cancellation-aware —
  a cancelled waiter resumes with `false` and throws
  `CancellationError`; a waiter already resumed by a releaser ignores
  late cancellation (it owns the transferred permit).
- MessageBodyLoadTimeoutRace: extracted a generic `race` so the
  conversation card's timeout now bounds permit-wait + backend load.
- ThreadMessageCard: `bodyWithReaderTimeout` races the whole
  permit+load span against the 15s timeout.
- Tests: cancelledWaiterStopsWaiting — red without the fix (hangs),
  green with it.

### Verification

- swift test --filter ThreadConversationRenderPoolTests — 4/4 green;
  the new test hangs forever without the fix (verified by stash).
- swift build --package-path packages/BrevMail — clean.
- scripts/lint.sh — clean.

### Skipped

- Device/simulator reproduction — the Mac was locked for GUI automation;
  the unit test reproduces the exact hang mechanism (cancelled permit
  waiter). Maintainer QA on #51 covers the rendered path.

## 2026-09-22 — Agent — Issue #12 slice 1 (task read sync)

### Goal

First slice of #12: a Tasks source kind with read-only sync for Google
Tasks and CalDAV VTODO collections.

### Changes

- BrevCalendar: `PIMSourceKind.tasks`, `PIMTask`/`PIMTaskStore`/
  `JSONPIMTaskStore`, `GoogleTaskSync` (`tasks.list` paged reads,
  `updatedMin` cursor, tombstones), `PIMDAVTaskSync`
  (`sync-collection` + VTODO-filtered `calendar-query` fallback,
  ETag diff, `calendar-multiget`), `PIMTaskSyncService`
  (per-collection isolation, cursor-after-save, one full-resync retry),
  `ICSParser.parseTasks` for VTODO, task-list discovery for Google
  (`tasklists.list`) and DAV (`supported-calendar-component-set`
  must advertise VTODO).
- BrevMail: `AppSession`/`AppSessionFactory` construct and expose
  `PIMTaskSyncService`.
- BrevSettings: Tasks source kind in the connect form, picker, source
  list, and Sync Now plumbing; Editing toggle stays unavailable for
  tasks sources (no write pipeline yet).
- apps: pass `pimTaskSyncService` into Settings on both platforms.
- Docs: ADR-0072 #12 slice 1 contract entry, ADR-0006 network table
  rows for CalDAV/Google task sync, PRIVACY.md task sync section,
  CHANGELOG entry.

### Verification

- swift test --package-path packages/BrevCalendar — 192/192 green
  (14 new PIMTaskSync tests)
- swift build --package-path packages/BrevMail — clean
- swift test --package-path packages/BrevSettings — logic green; 34
  pre-existing pixel-snapshot failures on this host (all on the CI
  macOS<26 skip list; unrelated surfaces)
- scripts/lint.sh — clean (SwiftFormat + SwiftLint + adr-required)

### Skipped

- App-level xcodebuild verification — SettingsView signature change is
  additive with a default; both call sites updated and compile-checked
  via package builds. CI runs the full app builds.
- Rendered verification — pending; #12 acceptance.

### Next

- #12 slices 2+: task write pipeline, task browsing UI, Create Task
  from Message target.

## 2026-09-22 — Agent — Issue #12 slice 3 (tasks browsing UI + Create Task)

- Goal: ship the Tasks surface and wire Create Task from Message into
  provider task lists per ADR-0072 — closing the loop on the slice-1/2
  sync and write pipelines.
- Changes: TasksBrowsingModel (cache-only load, collection-grouped
  sections, hidden/search/list filters, completed toggle, staleness,
  brev://task deep links); TasksEditingModel + TaskDraft over the
  TaskWriting seam (PIMTaskWriteService); TasksRootView/TasksListView/
  TaskDetailView/TaskEditorView mirroring the contacts surface;
  MessageTaskTarget replacing the Reminders-or-share enum with provider
  task lists via PIMTaskMessageCreator; macOS Tasks window (Window menu
  + sidebar footer) and iOS full-screen cover; PIMDeepLink .task case.
- Fixes during verification: TasksEditingModel guard failures now set
  lastError (contacts-editor parity) instead of throwing silently.
- Verification: 24 new Swift Testing cases green
  (TasksBrowsingModelTests, TasksEditingModelTests) plus the updated
  MessageTaskPayloadTests; lint.sh and format.sh clean.
- Skipped: rendered verification of the Tasks window (no signing cert
  locally); pixel snapshots unchanged — the surface rides existing
  coverage. Live-provider write smoke tests remain the maintainer gate.
- Next: #12 stays In progress pending maintainer QA; remaining issue
  scope is rendered/live verification, not code.

## 2026-09-22 — Agent — Issue #9 slice 3 (photos, dates/URLs, duplicate suggestions)

- Goal: close the three remaining contact gaps on the merged write
  pipeline + editor (PR #68) — photo set/replace/remove, date and URL
  fields, and review-first duplicate suggestions.
- Changes: `PIMContact` gains `photoData`, `dates`, `urls`; vCard
  writer/parser manage BDAY/ANNIVERSARY/X-ABDATE/URL/PHOTO
  version-aware and preserve unknown fields; Google People writer adds
  `:updateContactPhoto`/`:deleteContactPhoto` (bytes never in
  updatePersonFields) and birthdays/events/urls field mappings; sync
  parses the same fields so masks never erase unseen provider values;
  write service diffs stored-vs-draft photo state; editor gains photo
  (PhotosPicker), URLs, Dates sections; detail pane shows photo/URLs/
  dates plus a Possible Duplicates section fed by the pure
  `ContactDuplicateSuggestions` scorer (Review selects only — never
  merges); ADR-0006 gains CardDAV/Google contact-write rows, PRIVACY.md
  documents photo uploads, ADR-0072 records the slice.
- Verification: 26 PIMContactWrite + 19 PIMContactSync cases green
  (photo set/replace/remove round-trip on both writers, date+URL
  round-trip, unknown-field preservation with photos); 49 affected
  BrevMail cases green (draft mapping, duplicate ranking + no-mutation,
  editor/detail snapshots re-recorded); lint.sh and format.sh clean.
- Fixes during verification: parser `=\n` quoted-printable unfold
  swallowed the property after a base64 payload's `=` padding — now
  joins only when the next line is not itself a property; merge now
  unfolds raw vCards so folded PHOTO payloads leave no orphan lines;
  duplicate name matching compares display and split name forms so
  cross-form twins still match; AppSessionFactory now shares each
  `JSONPIM*Store` across sync/write services — the write service's
  private store instance left list/detail stale until relaunch
  (found by E2E on a stub CardDAV server; affected events/tasks too).
- Skipped: live-provider evidence (Google Workspace + writable CardDAV
  photo/date round-trips) — maintainer-gated per the issue; rendered
  verification of the PhotosPicker sheet itself.
- Next: maintainer QA on issue #9; remaining issue scope is live
  evidence and duplicate merge actions (out of "review-first" scope).

## 2026-09-21 — Agent — Issue #13 slice 1 (Google Meet conferences)

### Goal

Implement #13: read and render Google Meet (and generic) conferences
on synced events, and let the editor request a new Meet conference on
Google targets — without losing conference data on edits, moves, or
CalDAV round-trips.

### Changes

- BrevCalendar: PIMConference record on PIMEvent (kind, provider key,
  name, join URL, dial-ins, lifecycle status, isCreationRequest
  intent flag).
- BrevCalendar: GoogleConferenceMapping shared by sync and the write
  service — conferenceData entry points, hangoutLink fallback,
  pending-create kind via the createRequest solution key, unknown
  solutions stay joinable.
- BrevCalendar: Google writer sends conferenceData.createRequest with
  a fresh requestId plus conferenceDataVersion=1, and maps the
  response conference back into the stored record; writes without the
  intent omit conferenceData so synced conferences survive edits.
- BrevCalendar: ICS writer emits CONFERENCE;VALUE=URI;LABEL and the
  parser reads it back; X-GOOGLE-CONFERENCE / meet.google.com mark the
  kind as Meet; CalDAV create drops an unfulfillable Meet intent but
  keeps synced conferences.
- BrevMail: event draft preserves synced conferences, exposes a Meet
  toggle only for Google targets; moving to Google re-requests the
  conference, moving to CalDAV keeps it via ICS; detail pane renders
  name/status/join/dial-ins.

### Verification

- swift test --filter PIMEventSyncTests — 18/18 green
- swift test --filter PIMEventWriteTests — 25/25 green
- swift test --filter CalendarEventDraftTests|CalendarEditingModelTests
  — 21/21 green
- scripts/lint.sh — clean

### Skipped

- Rendered verification — pending; maintainer QA on #13.

## 2026-09-21 — Agent — Issue #10 slice 5 (per-recipient contact actions)

### Goal

Close the remaining functional gap of #10: every message participant —
not only the sender — opens the shared contact card or editor.

### Changes

- BrevMail: MailSenderContactActions.lookup(email:) — stateless
  cache-only resolution that cannot clobber the sender panel's state.
- BrevMail: MessageDetailView recipient chips become buttons when
  contacts infrastructure exists; they present the shared
  SenderContactDetailSheet (with Open in Contacts deep link) or the
  shared ContactEditorView pre-filled from the participant.
- BrevMailRootView wires senderContactActions into MessageDetailView.

### Verification

- swift test --filter MailSenderContactActions — 8/8 green
- swift build --package-path packages/BrevMail — clean

### Skipped

- Rendered verification — pending; acceptance criterion on #10.

## 2026-09-21 — Agent — Issue #10 slice 4 (event/contact deep links)

### Goal

Fourth slice of #10 (ADR-0072): event and contact deep links reopen
the correct Brev item and fail safely after source removal.

### Changes

- BrevMail: PIMDeepLinkPolicy (brev://event?id= / brev://contact?id=
  build + strict parse), PIMDeepLinkCopy pasteboard helper.
- BrevMail: CalendarBrowsingModel.revealEvent and
  ContactsBrowsingModel.revealContact — ensure-loaded reveal, filter
  clearing, selection, day anchoring, and an inline deepLinkNotice on
  a cache miss; both root views render the notice.
- BrevMail: Copy Link on CalendarEventDetailView and
  ContactDetailView; Open in Calendar on the invite card (reconciler
  cachedEvent(forUID:) lookup); Open in Contacts on the sender contact
  sheet (dismisses before opening for the iOS cover handoff).
- Apps: both entry points hoist the browsing models onto the session
  and route brev:// links to the shared instances; iOS openURL now
  routes brev:// internally.
- Fix: injectCardDAVContactSync installs the lookup provider through
  the CardDAVContactSyncSupporting existential when available — the
  MailBackend requirement's extension default no-ops when conformance
  is inherited without an override (caught by AppSessionTests on CI).

### Verification

- swift test --filter PIMDeepLinkPolicyTests/CalendarBrowsingModel/
  ContactsBrowsingModel/CalendarInviteReconciler — 44 green
- swift test --filter AppSession — 76 green (incl. the CardDAV
  provider-injection case)
- swift build --package-path packages/BrevMail — clean

### Skipped

- Rendered verification (macOS window + iOS cover reveal) — pending;
  acceptance criterion tracked on #10.
- Per-recipient contact actions — deferred to a later slice.

## 2026-09-21 — Agent — Issue #10 slice 3 (RSVP reconciliation)

### Goal

Third slice of #10 (ADR-0072): after the invite reply is sent,
reconcile the response with the synced calendar event and explain
partial outcomes.

### Changes

- BrevMail: CalendarInviteReconciler (UID match across sources,
  account-then-recipients attendee identity, write via the shared
  service, explicit updated/notSynced/notWritable/noMatchingAttendee/
  failed outcomes); CalendarInviteResponsePresentation gains a
  reconciliation-aware confirmation; ThreadMessageCard and
  MessageDetailView reconcile after a successful send; the root view
  and both app entry points wire the reconciler.

### Verification

- swift test --filter CalendarInviteReconciler — 6/6 green
- swift build --package-path packages/BrevMail — clean
- scripts/lint.sh — clean (ADR-0072 updated)
- xcodebuild BrevMacOS + BrevIOS — both build

### Skipped

- Detached reader windows keep the mail-only confirmation (no session
  services there); rendered verification stays with maintainer QA.

### Next

- Later #10 slices: event/contact deep links, per-recipient actions.

## 2026-09-21 — Agent — Issue #10 slice 2 (participant contact actions)

### Goal

Second slice of #10 (ADR-0072): shared contact card + Add to Contacts
from the sender panel, and compose autocomplete over the shared PIM
contact cache.

### Changes

- BrevCalendar: PIMContactSyncService.contact(matchingEmail:for:) —
  cache-only exact-email lookup.
- BrevBackend: ContactLookupResult.sourceLabel (optional provenance).
- BrevMail: PIMContactLookupAdapter (shared cache → ContactLookupProviding,
  legacy CardDAV adapter kept as fallback); MailSenderContactActions
  (resolve/open/add/canEdit); SenderContactDetailSheet; SenderContextPanel
  contact actions; ContactEditorView draft init; AppSession injects the
  PIM adapter on every backend; both app entry points wire the model.

### Verification

- swift test --filter PIMContactLookupAdapter|MailSenderContactActions — 9/9 green
- swift build --package-path packages/BrevMail — clean
- scripts/lint.sh — clean (ADR-0072 updated)
- xcodebuild BrevMacOS + BrevIOS — both build

### Skipped

- Rendered interaction verification stays with maintainer QA.

### Next

- Later #10 slices: RSVP reconciliation, per-recipient actions,
  deep links.

## 2026-09-21 — Agent — Issue #10 slice 1 (create event from message)

### Goal

First slice of #10 (ADR-0072): route Create Event from Message through
the shared calendar editor and writable PIM sources instead of only
the local EventKit handoff.

### Changes

- BrevMail: MessageEventDraftBuilder.calendarDraft builds a
  CalendarEventDraft (subject, attendees, received timestamp, Brev
  deep link). CalendarEventEditorView gains a draft-taking
  initializer. MessageCreateEventSheet resolves writable targets and
  picks the shared editor or the EventKit fallback; the decision is
  unit-tested via MessageCreateEventRouting.
- BrevMailRootView takes an optional CalendarEditingModel; both app
  entry points construct it from the session write service and
  coordinator.

### Verification

- swift build --package-path packages/BrevMail — clean
- swift test --filter MessageEventDraftBuilder|MessageCreateEventRouting|CalendarEditingModel — 21/21 green
- swiftformat on touched files — no changes
- scripts/lint.sh — clean (ADR-0072 updated)
- xcodebuild BrevMacOS + BrevIOS — both build

### Skipped

- Rendered interaction verification stays with maintainer QA.

### Next

- Later #10 slices: RSVP reconciliation, participant contact cards,
  Add/Update Contact, autocomplete labels, deep links.

## 2026-09-21 — Agent — Issue #7 slice 2 (event editor UI)

### Goal

Second slice of #7 (ADR-0072): the event editor surface on top of the
slice-1 write pipeline — create/edit/delete for timed, all-day, and
repeating events on writable Google/CalDAV sources.

### Changes

- BrevMail: CalendarEventDraft (form state with provider-identity
  carry-through and RRULE mapping), CalendarEditingModel (writable
  targets, create/update/delete/move/future-scope dispatch behind a
  CalendarEventWriting seam), CalendarEventEditorView (the sheet),
  Edit/Delete actions on the detail pane, a New Event toolbar item on
  the root view.
- BrevCalendar: GoogleCalendarEventWriter sends sendUpdates=all on
  insert/patch/delete so invitees are notified; canWrite on
  PIMEventWriteService is nonisolated for synchronous UI gating.
- Recurring scope: All Events patches the master; This and Future
  Events truncates the master RRULE and creates a new series.
  Single-occurrence exceptions deferred (multi-VEVENT / recurringEventId).
- Apps: both BrevApp shells construct CalendarEditingModel over the
  session's PIM services.
- Docs: ADR-0072 slice-2 entry, CHANGELOG bullet, PRIVACY.md attendee
  notification note.

### Verification

- swift build --package-path packages/BrevMail: clean.
- swift test --package-path packages/BrevMail --filter
  CalendarEditingModelTests|CalendarEventDraftTests: 17/17 green.
- swift test --package-path packages/BrevCalendar --filter
  PIMEventWriteTests: 19/19 green.
- scripts/lint.sh: clean (ADR-0072 updated in the same commit).
- xcodebuild BrevMacOS (macOS, arm64) and BrevIOS (iPhone 17
  simulator): both BUILD SUCCEEDED.

### Skipped

- Rendered verification of the sheet: no live writable source in this
  environment; ViewInspector/snapshot coverage deferred with the rest
  of the calendar surface.

### Handoff

- Next: PR targets main, then issue #9 (contact authoring) reuses the
  same slice shape for CardDAV/Google People.

## 2026-09-21 — Agent — Issue #9 slice 2 (contact editor UI)

### Goal

Second slice of #9 (ADR-0072): the contact editor surface on top of
the slice-1 write pipeline — create/edit/delete on writable Google and
CardDAV contacts sources.

### Changes

- BrevMail: ContactDraft (form state with provider-identity
  carry-through and display-name resolution), ContactsEditingModel
  (writable targets — per-book for CardDAV, account-wide for Google —
  create/update/delete/move dispatch behind a ContactWriting seam),
  ContactEditorView (the sheet), Edit/Delete actions on the detail
  pane with a provider-impact delete confirmation, a New Contact
  toolbar item on the root view.
- Group membership: Google contact groups edit as toggles over
  discovered collections (memberships field); CardDAV categories edit
  as comma-separated text.
- Fixed: ContactsRootView.groupNames matched collection.id against
  providerKey groupKeys — never resolved; now matches providerKey.
- Apps: both BrevApp shells construct ContactsEditingModel over the
  session's PIM services.
- Docs: ADR-0072 #9 slice-2 entry, CHANGELOG bullet.

### Verification

- swift build --package-path packages/BrevMail: clean.
- swift test --package-path packages/BrevMail --filter
  ContactsEditingModelTests|ContactDraftTests: 14/14 green.
- scripts/lint.sh: clean (ADR-0072 updated in the same commit).
- xcodebuild BrevMacOS (macOS, arm64) and BrevIOS (iPhone 17
  simulator): both BUILD SUCCEEDED.

### Skipped

- Rendered verification of the sheet: no live writable source in this
  environment; snapshot coverage deferred with the rest of the
  contacts surface.

### Handoff

- Next: PR targets main. Open acceptance criteria on #9 that remain:
  photo upload, date/URL fields (shared-model extension), duplicate
  suggestions, and redacted live evidence against Google Workspace and
  a writable CardDAV server.

## 2026-09-21 — Agent — Issue #9 slice 1 (contact write pipeline + editing opt-in)

### Goal

First slice of #9 (ADR-0072): the provider-neutral contact write path —
vCard serialization with unknown-field merge, Google People and CardDAV
write adapters, a capability-gated write service — plus the Editing
opt-in extended to contacts sources.

### Changes

- BrevCalendar: PIMVCardWriter (vCard 3.0 create, raw-payload merge on
  update preserving unknown properties and VERSION, TEXT escaping,
  75-octet UTF-8-safe folding), GooglePeopleContactWriter
  (createContact / updateContact with updatePersonFields mask /
  deleteContact, etag precondition, 400 FAILED_PRECONDITION mapped to
  conflict, myContacts membership never sent), PIMDAVContactWriter
  (PUT to {collection}/{uid}.vcf on create, to the stored href on
  update; DELETE on the href; If-None-Match / If-Match preconditions),
  PIMContactWriteService (canWrite gate, provider dispatch, Google
  group-as-membership on create, single-record cache patching).
- BrevSettings: canToggleWrite now covers connected Google and CardDAV
  contacts sources; the Google write re-auth path is unchanged.
- BrevMail: AppSession carries pimContactWriteService; the factory
  wires it over the shared coordinator, contact store, credentials,
  and the Google token provider.
- Docs: ADR-0072 #9 slice-1 entry, CHANGELOG bullet, PRIVACY.md
  contacts-editing paragraph.

### Verification

- swift build --package-path packages/BrevCalendar + BrevMail: clean.
- swift test --package-path packages/BrevCalendar --filter
  PIMContactWrite: 16/16 green.
- swift test --package-path packages/BrevSettings --filter
  PIMSourceSettingsModel: 21/21 green.

### Skipped

- xcodebuild app builds: no app-target surface touched (session wiring
  compiles under the BrevMail package build).
- Live provider evidence: deferred to the maintainer QA pass per
  issue #9 acceptance criteria.

### Handoff

- Next: PR targets main; slice 2 is the contact editor UI (form,
  group picker, photo handling, delete confirmation). Dates/URLs need
  a shared-model extension — tracked in the ADR deferral list.

## 2026-09-21 — Agent — Issue #7 slice 1 (event write pipeline + editing opt-in)

### Goal

First slice of #7 (ADR-0072): the provider-neutral event write path —
ICS serialization, Google/CalDAV write adapters, a capability-gated
write service — plus the per-source Editing opt-in that authorizes it.
The editor UI is the next slice.

### Changes

- BrevCalendar: PIMEventICSWriter (RFC 5545 VCALENDAR with TEXT
  escaping, TZID/VALUE=DATE forms, RRULE/RECURRENCE-ID, ATTENDEE
  PARTSTAT, VALARM, 75-octet UTF-8-safe folding),
  GoogleCalendarEventWriter (events.insert/patch/delete, If-Match etag,
  body mapping), PIMDAVEventWriter (PUT/DELETE on collection URL,
  If-None-Match create / If-Match update+delete),
  PIMEventWriteService (canWrite gate, provider dispatch, single-record
  cache patch), PIMSourceCoordinator.setWriteEnabled,
  GooglePIMScopes.scopes(for:write:) with calendarEvents/contacts.
- BrevMail: AppSession.pimEventWriteService +
  enableGooglePIMWriteFeature (re-auth with write scopes, then flips
  the capability); GooglePIMEnablementCoordinator gained a write flag;
  AppSessionFactory constructs the write service on the shared stores.
- BrevSettings: PIMSourceSettingsModel.setWriteEnabled (Google routes
  through re-auth, DAV is local-only, disable is always local),
  canToggleWrite/isWriteEnabled; source rows show an Editing switch
  for connected Google/CalDAV calendar sources.
- apps: both BrevApp closures pass the write flag through; SettingsView
  gained onEnableGooglePIMWrite.
- Privacy: PRIVACY.md editing paragraph + ADR-0006 rows for CalDAV and
  Google Calendar event writes (off by default, Editing-gated).

### Verification

- 19 new BrevCalendar write-path tests pass (ICS writer, both provider
  writers incl. precondition/conflict mapping, service gating,
  create/update/delete cache behavior, coordinator capability).
- 5 new BrevSettings tests pass (DAV toggle, Google handler routing,
  missing-handler error, local-only disable, canToggleWrite gating);
  full PIMSourceSettingsModel suite 21/21.
- swift build clean for BrevCalendar, BrevSettings, BrevMail.
- scripts/lint.sh clean (SwiftFormat + SwiftLint --strict +
  adr-required); xcodebuild BrevMacOS and BrevIOS both succeed.

### Skipped

- Live-provider evidence stays the maintainer QA gate.

### Next

- #7 slice 2: the event editor UI on this write path.
## 2026-09-21 — Agent — Issue #6 slice 4 (day/week/month grids)

### Goal

Fourth slice of #6 (ADR-0072): day, week, and month grid layouts for
the Calendar surface sharing selection and date navigation with the
agenda — closing the "agenda, day, week, and month views share
selection and date navigation" acceptance criterion.

### Changes

- BrevMail: CalendarGridLayout (pure grid math — day coverage with
  all-day exclusive ends and multi-day spans, first-weekday-aware
  weeks, complete-week month cells, sweep-line overlap lanes, range
  titles), CalendarBrowsingModel gains viewMode/selectedDay/
  navigation/per-day accessors, CalendarDayView + shared
  CalendarDayColumn (hour lanes, all-day strip, lane-split blocks),
  CalendarWeekView (7 columns + shared ruler + per-column all-day
  strip), CalendarMonthView (weekday header + day cells with 3 chips +
  overflow), CalendarRootView toolbar gains a segmented layout picker
  and prev/today/next with a range title.
- CI: CalendarGridSnapshotTests registered in the macOS<26 skip list
  and the snapshot-macos only-testing list.

### Verification

- 16 new grid-layout tests + 3 model navigation tests + 4 snapshot
  renders pass; full filtered run 33 tests green.
- scripts/lint.sh clean (SwiftFormat + SwiftLint --strict +
  adr-required).
- xcodebuild build BrevMacOS and BrevIOS (CODE_SIGNING_ALLOWED=NO) —
  both succeed.

### Skipped

- Pixel baselines recorded on macOS 27 — this host's renderer; the
  repo's earlier baselines were recorded on macOS 26 and already drift
  locally. Re-record on a macOS 26 host if the snapshot job flags them.
- Live-provider evidence stays the maintainer's QA gate.

### Next

- #7 event authoring.

## 2026-09-21 — Agent — Issue #8 slice 2 (contacts browsing: list + detail + groups + search)

### Goal

Second slice of #8 (ADR-0072): a first-class Contacts surface that
browses the synced contact cache — alphabetical list, contact detail,
group filter, local search — on macOS and iOS, without issuing provider
requests.

### Changes

- BrevMail: ContactsBrowsingModel (cache-only load across contacts
  sources, hidden-collection filtering covering CardDAV collectionID
  and Google groupKeys paths, local search, letter bucketing,
  stale-source detection, per-source cache-failure isolation, Sync Now
  passthrough), ContactPresentation (pure formatting: monograms,
  subtitles, label normalization, addresses, letter keys, search
  corpus), ContactsListView + ContactRowView (letter sections,
  monogram avatars, subtitle rows), ContactDetailView (all model
  fields incl. labeled emails/phones/addresses, notes, groups,
  provenance), ContactsRootView (split view, search, group filter,
  Sync Now, stale/error banners, empty states).
- macOS: Window("Contacts") scene + Window menu command.
- iOS: sidebar-footer Contacts button (FolderSidebar onOpenContacts)
  presenting the surface as a full-screen cover with Done.
- CI: ContactsBrowsingSnapshotTests registered in the macOS<26 skip
  list and the snapshot-macos only-testing list.

### Verification

- 22 new behavior tests + 4 snapshot renders pass
  (ContactsBrowsingModel, ContactPresentation,
  ContactsBrowsingSnapshot).
- scripts/lint.sh clean (SwiftFormat + SwiftLint --strict +
  adr-required).
- xcodebuild build BrevMacOS and BrevIOS (CODE_SIGNING_ALLOWED=NO) both
  succeed — app targets compile in Swift 6 mode.

### Skipped

- Pixel baselines recorded on macOS 27 — this host's renderer; the
  repo's earlier baselines were recorded on macOS 26 and already drift
  locally. Re-record on a macOS 26 host if the snapshot job flags them.
- Live-provider evidence stays the maintainer's QA gate.

### Next

- #9: contact authoring on the same cache.

## 2026-09-21 — Agent — Issue #6 slice 3 (calendar browsing: agenda + detail + search)

### Goal

Third slice of #6 (ADR-0072): a first-class Calendar surface that browses
the synced event cache — agenda list, event detail, local search — on
macOS and iOS, without issuing provider requests.

### Changes

- BrevMail: CalendarBrowsingModel (cache-only load across calendar
  sources, hidden-collection filtering, local search, day bucketing,
  stale-source detection, per-source cache-failure isolation, Sync Now
  passthrough), CalendarEventPresentation (pure formatting: agenda
  times, day titles, recurrence summaries, RSVP/reminder labels, search
  corpus), CalendarAgendaView + CalendarEventRowView (day sections,
  collection color bars, cancelled strikethrough, join-link icon),
  CalendarEventDetailView (all model fields incl. attendees/RSVP,
  reminders, notes, provenance), CalendarRootView (split view, search,
  Sync Now, stale/error banners, empty states).
- macOS: Window("Calendar") scene + Window menu command.
- iOS: sidebar-footer Calendar button (FolderSidebar onOpenCalendar)
  presenting the surface as a full-screen cover with Done.
- CI: CalendarBrowsingSnapshotTests registered in the macOS<26 skip
  list and the snapshot-macos only-testing list.

### Verification

- 19 new behavior tests + 4 snapshot renders pass
  (CalendarBrowsingModel, CalendarEventPresentation,
  CalendarBrowsingSnapshot). Full BrevMail package: 45 calendar-related
  tests green.
- scripts/lint.sh clean (SwiftFormat + SwiftLint --strict +
  adr-required).
- xcodebuild build BrevMacOS and BrevIOS (CODE_SIGNING_ALLOWED=NO) both
  succeed — app targets compile in Swift 6 mode.

### Skipped

- Pixel baselines recorded on macOS 27 — this host's renderer; the
  repo's earlier baselines were recorded on macOS 26 and already drift
  locally. Re-record on a macOS 26 host if the snapshot job flags them.
- Live-provider evidence stays the maintainer's QA gate.

### Next

- #6 slice 4: day/week/month grid views sharing selection/navigation.
- #8 slice 2: contacts browsing UI on the same pattern.

## 2026-09-21 — Codex — Issue #6 collection discovery (slice 1)

### Goal

First slice of #6 (ADR-0072): discover and persist the calendars /
address books a connected PIM source exposes, list them in Settings with
per-collection visibility, and keep the cached list intact on refresh
failure. Item sync and browsing views land in later slices.

### Changes

- BrevCalendar: PIMCollection + PIMDiscoveredCollection models,
  PIMCollectionStore/JSONPIMCollectionStore (per-source file inside the
  source cache directory so the removal contract applies unchanged),
  PIMDAVCollectionDiscovery (principal → home-set → Depth:1 listing,
  resourcetype filtering, privilege-derived read-only, CTag/ETag/sync
  hints, credential-safe redirects), GooglePIMCollectionDiscovery
  (calendarList + contactGroups with pagination, injected access token),
  PIMCollectionService (serial refresh preserving visibility, failure
  marks source failed without blanking the cache).
- BrevGmail: GmailAccountConnector.accessToken(for:) exposes the shared
  grant to PIM adapters.
- BrevMail: AppSession.pimCollectionService + factory wiring via
  Configuration.googlePIMAccessTokenProvider.
- BrevSettings: source rows list collections with visibility toggles and
  a Refresh Collections action; connect/Google enablement run one
  best-effort discovery inside the same user gesture.
- Apps: macOS + iOS wire the token provider and pass the service to
  SettingsView.
- Docs: ADR-0072 contract log slice entry; ADR-0006 network table rows
  for DAV collection PROPFIND and Google collection listing; PRIVACY.md
  collection-discovery paragraph; CHANGELOG Unreleased.

### Verification

- swift test (BrevCalendar): 111 tests pass, incl. new
  PIMDAVCollectionDiscovery (7), GooglePIMCollectionDiscovery (4),
  PIMCollectionService (6), JSONPIMCollectionStore (4) suites.
- swift test --filter PIMSourceSettingsModel (BrevSettings): 16 pass,
  incl. 4 new collection tests.
- swift build clean for BrevCalendar, BrevSettings, BrevMail, BrevGmail.

### Skipped

- Full tuist app builds and pixel snapshots — left to CI; 34 pre-existing
  BrevSettings snapshot mismatches on this host are environmental
  (macOS 27 renderer vs macOS-26 baselines).
- Live-provider smoke against real Google/CalDAV accounts — maintainer
  acceptance gate for #6.

### Next

- #6 slice 2: event sync engine + local cache (sync-collection /
  syncToken incremental paths per ADR-0072 sync rules).

## 2026-09-21 — Agent — Issue #8 slice 1 (contact sync engine + cache)

- Goal: give connected contacts sources a real sync pass per ADR-0072 —
  initial + incremental sync, per-scope failure isolation, durable
  cache, cursors wiped on removal.
- Changes: PIMContact/PIMContactField/PIMContactAddress model with
  adapter-owned rawPayload; JSONPIMContactStore (per-source file under
  the cache dir) and JSONPIMContactSyncCursorStore (under the wiped
  cursor dir, scope = collection for CardDAV / source for Google);
  GooglePeopleContactSync (connections.list paging, syncToken-only
  incremental, 410/400-expired → full resync); PIMDAVContactSync
  (sync-collection with multiget fill-in, addressbook-query + ETag-diff
  fallback); PIMVCardParser covering FN/N/NICKNAME/EMAIL/TEL/ADR/ORG/
  TITLE/NOTE/CATEGORIES/REV/UID and HTTPS-only PHOTO URIs;
  PIMContactSyncService (serial, user-initiated, per-scope failure
  isolation, local-only searchContacts).
- Settings: Sync Now menu item + cached contact count on contacts
  source rows; enabling sync runs one immediate pass in the gesture.
- Wiring: AppSession.pimContactSyncService via AppSessionFactory; both
  app targets pass it to SettingsView.
- Verification: 16 new tests pass (CardDAV incremental/multiget/
  fallback, Google full/incremental/410, hidden-skip, failure
  isolation, auth stop, kind guard, local search, vCard edge cases).
  BrevCalendar, BrevSettings, BrevMail packages build clean.
- Skipped: app builds left to CI (no local signing cert); pixel
  snapshots unchanged. Local BrevSettings snapshot mismatches are
  pre-existing macOS-27 renderer drift.
- Next: #8 slice 2 browsing UI (list/detail/group filter) and
  compose-autocomplete migration; live-provider evidence stays the
## 2026-09-21 — Agent — Issue #6 slice 2 (event sync engine + cache)

- Goal: give connected calendar sources a real sync pass per ADR-0072 —
  initial + incremental sync, per-collection failure isolation, durable
  cache, cursors wiped on removal.
- Changes: PIMEvent/PIMEventStatus/PIMEventPerson/PIMEventReminder model
  with adapter-owned rawPayload; JSONPIMEventStore (per-collection files
  under the source cache dir) and JSONPIMSyncCursorStore (under the
  wiped-on-removal cursor dir); GoogleCalendarEventSync (events.list
  paging, syncToken-only incremental, 410 → full resync); PIMDAVEventSync
  (RFC 6578 sync-collection with multiget fill-in, bounded
  calendar-query + ETag-diff fallback); PIMEventSyncService (serial,
  user-initiated, per-collection failure isolation, cursor committed
  after the generation). ICSParser gained parseEvents (all VEVENTs),
  STATUS/PARTSTAT/VALARM/CONFERENCE/LAST-MODIFIED/TZID capture, Codable
  RecurrenceRule and public parseRecurrenceRule.
- Settings: Sync Now menu item + cached event count on calendar source
  rows; enabling sync runs one immediate pass in the same gesture.
- Wiring: AppSession.pimEventSyncService via AppSessionFactory; both app
  targets pass it to SettingsView.
- Verification: 23 new tests pass (DAV incremental/multiget/fallback/501
  degrade, Google full/incremental/410, hidden-skip, failure isolation,
  auth stop, kind/status guards, ICS field parsing). BrevCalendar,
  BrevSettings, BrevMail packages build clean.
- Skipped: app builds left to CI (no local signing cert); pixel snapshots
  unchanged — the new row content rides existing snapshot coverage.
  Local BrevSettings snapshot mismatches are pre-existing macOS-27
  renderer drift (identical failures on clean main).
- Next: #6 slice 3 browsing UI (agenda/day/week/month + detail), then
  search/offline-stale states; live-provider evidence stays the
  maintainer gate.

## 2026-09-20 — Codex — Issue #5 Google reauthorization + removal UX

### Goal

Slice 3 for #5 (ADR-0072): let a Google mail account enable Calendar or
Contacts through a fresh user-initiated authorization that extends the
shared grant, then register the linked source. Read-only scopes only;
sync scheduling and authoring land later.

### Changes

- Merged PR #55 (ADR-0072 acceptance) into main.
- BrevBackend: `GoogleOAuthFlow` accepts `additionalScopes` on signIn and
  authorization-URL building; mail baseline is always included.
- BrevGmail: `GmailAccountConnector.enablePIMFeature` requests the union
  of stored and requested scopes, validates account subject and granted
  superset, and stage-then-swaps token+config with rollback.
- BrevCalendar: `GooglePIMScopes` read-only scope mapping;
  `PIMSourceCoordinator.connectGoogleSource` registers a linked source
  with no credential of its own (idempotent per account+kind).
- BrevMail: `AppSession.enableGooglePIMFeature` +
  `GooglePIMEnablementCoordinator` hook; factory configuration wiring.
- BrevSettings + both apps: per-Google-account enable rows in
  Settings → Calendar & Contacts; placeholder only when the session
  cannot authorize.
- Docs: ADR-0072 contract log slice 3; ADR-0006 Google rows cover
  feature-triggered reauthorization; PRIVACY.md documents the reauth
  flow; CHANGELOG Unreleased updated.
- Slice 4 (removal UX): `AppSession.linkedPIMSources` +
  `removeAccount(_:deleteLinkedSourceCache:)` remove linked sources with
  the account (best-effort, local-only); AccountsSection removal dialog
  names linked sources and offers the two-step cache choice; sign-out
  removes linked sources with kept caches. Capability summary now lists
  Google enablement as available.

### Verification

- swift test BrevGmail --filter GmailPIMEnablement: 7 pass (union
  request, grant swap, identity mismatch, partial grant, lost mail
  access, cancellation, missing config).
- swift test BrevCalendar --filter PIMSourceCoordinator: 13 pass
  (Google source registration, idempotency, credential-free removal).
- swift test BrevBackend --filter GoogleOAuthFlow: 34 pass (additional
  scopes in the authorization URL).
- swift test BrevSettings --filter PIMSourceSettingsModel: 12 pass
  (handler gating, forward+reload, declined grant).
- swift test BrevMail --filter 'linkedPIM|removeAccount': 5 pass
  (linked-source query, removal deletes caches on request, keeps them
  otherwise); BrevSettings AccountsSectionPresentation: removal message
  coverage.
- swift build BrevMail clean; swiftformat + swiftlint clean on touched
  files.

### Next

- Land the stack: #56 (lifecycle), #57 (settings surface), #58 (Google
  enablement), and the removal-UX PR merge to main in order. Remaining
  #5 scope: retain-linked-sources via PIM-only grant (ADR retention
  path); live-provider smoke stays a maintainer gate.

## 2026-09-20 — Codex — Issue #5 PIM source lifecycle foundation

### Goal

First implementation slice for #5 (provider-neutral Calendar/Contacts
sources, ADR-0072): the source record, serial lifecycle coordinator, DAV
setup validation, and removal semantics. Settings UI, Google
reauthorization and sync scheduling land in later slices.

### Changes

- Merged PR #52 (covers #49/#51/#53) and closed redundant PR #54.
- Recorded ADR-0072 acceptance in PR #55 (docs-only: status, ADR-0039
  supersede note, ADR index, README roadmap).
- New in BrevCalendar: PIMSource record + kind/provider/capability/
  seven-state status vocabulary; JSONPIMSourceStore record persistence;
  FilePIMSourceLocalDataStore two-step removal (cursors/drafts always
  die, readable cache only on explicit choice); PIMDAVClient manual +
  RFC 6764 well-known validation with HTTPS enforcement, hop-by-hop
  redirects, and actionable errors; PIMSourceCoordinator serial
  lifecycle with stage-then-swap credentials and provider-free removal;
  PIMSourceStatusPresenter shared status presentation.
- ADR-0072 gained an implementation contract log; PRIVACY.md and
  ADR-0006 document the new DAV setup calls (explicit connect only, no
  background traffic).

### Verification

- swift test --package-path packages/BrevCalendar: 88 tests, 13 suites
  pass — including new coverage for connect staging/rollback, rejected
  reconnect preserving credentials, removal semantics, HTTPS/TLS/refused
  cross-origin redirects, and status presentation.
- swiftformat + swiftlint --strict clean on all touched files.
- BrevCalendar is an ADR-0005 protected path: the PR includes the
  ADR-0072 contract-log update as required.

### Next

- #5 slice 2: settings Sources UI + section copy update; slice 3: Google
  feature-triggered reauthorization; live-provider smoke remains an
  issue-level acceptance gate.

## 2026-09-20 — Codex — #4 and backlog sequencing

- Expanded Proposed ADR-0072 against all ten #4 criteria: domain/service
  contracts, source ownership, native consent constraints, caches, conditional
  writes, field preservation, recurrence, offline drafts and delivery gates.
- Reconciled README and ADR-0039/0009/0043 without claiming acceptance or
  shipped PIM support. Settings replacement copy is specified for acceptance;
  current UI remains unchanged while the old boundary still applies.
- Verified official Google and DAV references. Google's installed-app OAuth
  guidance excludes incremental authorization; #5 must prove feature-triggered
  native reauthorization and credential preservation before implementation ships.
- Board: #1/#4 In progress; #3/#5/#6/#7/#8/#11 P0 → P1 so #4 remains the
  immediate P0 prerequisite. Added #9 as a dependency of #10's writable contact
  actions. No issues closed or moved to Done.
- Verification: relative ADR links, lint, format and diff-check pass.
  Documentation-only TDD/build/snapshot exception; no code, scopes, network
  traffic, release behavior or permissions changed. README/ADRs/WORKLOG updated;
  PRIVACY, CHANGELOG, AGENTS and runtime settings need no change for a proposal.
- #2 preflight: checked configuration contains macOS Google client settings,
  but no disposable BREV_LIVE_* account values or iOS Google client settings.
  Requested the secure test-account configuration location; no live mail sent.
- Handoff: review and accept/narrow ADR-0072 before source/authoring work.

## 2026-09-20 — Codex — PR #48 pre-merge review

- Addressed the OAuth review finding: ADR-0072 now explicitly preserves the
  required non-confidential macOS Desktop credential from accepted ADR-0067.
  PKCE remains required; iOS uses its separate secretless native client.
- Documentation-only correction; TDD/build exception. Checked against ADR-0067
  and the existing token-exchange contract, with diff-check before commit.
- Henrik authorized merging the open PRs. The architecture remains Proposed;
  this correction does not introduce provider implementation or account changes.

## 2026-09-20 — Codex — #1 and iPhone account alignment

- Reproduced account-header indentation from Henrik's screenshot. Moved the
  iOS disclosure arrow trailing and matched folder-row padding; macOS unchanged.
- Inspected failing light/dark mailbox renders, updated only their references,
  and passed all seven phone snapshot cases. This is a visual regression check;
  no new logic test or test-only layout API was needed.
- Runtime semantic readback confirms inbox Refresh/Compose/Filter and mailbox
  Settings/Show messages at all twelve Dynamic Type categories. Settings and
  Compose open at the largest category. Restored the original large size.
- Reader AX snapshots did not settle; spoken VoiceOver and the reader back
  control remain unverified. #1 stays open with explicit partial QA evidence.
- Filed #49, Ready/P1, for reproduced compose horizontal overflow and missing
  Close/More at the largest accessibility category. Stored synthetic screenshot
  and filtered labels only in docs/qa/iphone-accessibility-2026-09-20.
- #2 preflight reported missing disposable credentials; no live connection or
  message transmission. The secure configuration location was requested.
- Verification: simulator build, seven phone snapshot cases, baseline inventory,
  lint, formatting and diff-check. CHANGELOG, QA and WORKLOG updated; README,
  ADRs, privacy and workflow contracts are unchanged by this layout correction.
- Handoff: review the alignment change, verify spoken VoiceOver/reader control,
  then address #49 before calling the compose accessibility flow accepted.

## 2026-09-20 — Codex — #1 / PR #50 reader hierarchy follow-up

- Reproduced Henrik's oversized account-address screenshot at accessibility5.
  Applied the existing iOS reader chrome range and middle truncation to account
  metadata; body text is unchanged. Labelled and reduced the loading indicator.
- Added standard/accessibility phone conversation snapshots. Inspected the old
  oversized rendering, observed the expected changed-reference failure, recorded
  corrected references, and passed nine phone cases across six tests.
- Simulator build/run, native loading screenshot, lint, zero-change final format,
  baseline inventory and diff-check pass. Stored synthetic screenshot in QA docs.
- The sample reader still stalls. A process sample shows repeated main-thread
  SwiftUI layout work; root cause is not established. Filed #51 Ready/P1 rather
  than claiming the UI styling fixes delivery. Raw diagnostics remain local.
- Updated CHANGELOG and QA evidence. No architecture, network, privacy, setup or
  workflow change: README/ADRs/PRIVACY/AGENTS need no update. No physical-device or
  spoken VoiceOver signoff. Continue existing PR #50; no merge or release.


## 2026-09-20 — Codex — PR #48 review follow-up

- Preserve ADR-0039’s live DAV/OAuth proof prerequisite before browsing; map legacy #121 evidence to #5, with #11 extending parity coverage.
- Require a separate validated PIM-only grant before retaining sources during mail removal, and clear the removed mail credential.
- Verification: checked the proposal against ADR-0039 and PRIVACY.md; documentation-only change, no runtime tests required. ADR-0072 remains Proposed.

- Additional PR #48 review: route reads/writes through explicit adapter boundary in the diagram; require validated narrower shared Google grants on PIM removal, with disclosed revoke/reconnect fallback. State DAV privilege-narrowing limits. Checked scenario consistency and diff whitespace; documentation-only.

- Final removal clarification for PR #48: separately delete source-owned unsent editor drafts and staged attachments after warning and confirmation; allow cancellation. Include this lifecycle in removal tests. Documentation-only, checked against the separate-draft invariant.

## 2026-09-20 — Codex — #49 / #51 native UI polish

- Followed the requested merge and polish pass. PR #50 merged; PR #48 review
  follow-ups preserve live DAV proof and safe removal of combined Google grants.
- Diagnosed the sample reader freeze as repeated command environment closure
  invalidation. Added stable routing identity with latest-owner dispatch and a
  hosting-controller regression; verified rendered body and Reply on simulator.
- Proved compose flow overflow with a failing width test, bounded measurement
  and placement, added accessibility form scrolling and standard/AX5 snapshots.
- Reduced duplicate desktop compose tools and labelled Send; inspected native
  test-app compose, mailbox and settings. No message sent or daily app replaced.
- Verification: iOS 9 tests/3 suites; macOS 6 tests/3 suites; native builds,
  lint, zero-change format, baseline inventory and diff check. All 12 simulator
  text sizes expose Close/Send/More. QA evidence and limits are in
  docs/qa/native-polish-2026-09-20/README.md.
- Initial broad macOS run had an unrelated profile-manager snapshot mismatch;
  no unrelated baseline changed. Physical VoiceOver, another runtime/device and
  live-provider coverage remain pending. No new release or version change.
- Documentation sweep: updated CHANGELOG, QA evidence and WORKLOG. No public
  architecture, provider, privacy, setup or workflow change; README, PRIVACY,
  ADRs and AGENTS need no change for this implementation. Hand off in review.

- PR #52 follow-up: native plain-renderer QA exposed joined paragraphs while HTML
  import was pending. Added a failing fallback regression and preserved the
  supplied plain alternative; native screenshot now retains paragraph spacing.
  Restored busy-state disabling on the accessibility toolbar and registered the
  new desktop snapshot explicitly in CI. Configuration selection needs no TDD;
  the one-line disable restores the existing header invariant without a new
  async-send fixture. Focused body, compose policy and snapshot checks rerun.

- Final handoff: PR #48 merged as a72e652e; all six review findings resolved.
  The final documentation-only head passed local lint/diff checks; hosted rebuild
  remained queued, with the unchanged runtime tree already green at e316db69.
  PR #50 is merged as 98e517aa. Integrated main into PR #52, preserving both
  append-only worklog entries. Final iOS command exits successfully with 37
  tests/5 suites after disabling stalled diagnostic collection; macOS follow-up
  exits successfully with 29 tests/3 suites. #49/#51 remain In review.


## 2026-09-20 — Codex — PR #52 sidebar polish

- Used Henrik's Brev/Apple Mail comparison to reduce desktop sidebar hierarchy
  noise: account sections have compact labels and trailing disclosure, folders
  no longer inherit an extra account indent, All Inboxes aligns with folder icons,
  labels use regular body type, counts are tertiary, and selection uses one fill.
  Quieted the desktop profile control while preserving theme tokens and iOS UI.
- Continued feature/native-ui-polish / PR #52 targeting main; checkout was clean.
- Visual regression loop: old macOS sidebar suite passed, intentional styling
  produced 11 reference failures, inspected light/dark/hierarchy renders, refreshed
  only those references and passed 39 sidebar tests across two suites. All 11
  existing phone snapshot cases (7 tests) passed without baseline changes.
- Native dated Brev Test build passed. Inspected both accounts, collapse/expand,
  nested rows and selecting the second account Inbox. No live mail changes.
- Lint, format and diff check passed. Updated CHANGELOG and QA documentation;
  no provider, privacy, public design-token, setup or architectural change, so
  README/PRIVACY/ADRs/AGENTS need no update. Physical VoiceOver remains unverified.


## 2026-09-20 — Codex — PR #52 sidebar top alignment

- Aligned profile, All Inboxes and Smart Views text/icon columns on desktop.
  Replaced the native borderless menu label with a plain menu button so SwiftUI
  respects its layout; moved the profile chevron to the trailing edge. Removed
  the extra profile gap and put Smart Views disclosure in the icon column.
- Inspected intentional snapshot failures and refined the rendered alignment;
  refreshed only the 11 sidebar references. Native profile menu opens with All
  Mailboxes and Manage Profiles. Decorative symbols are hidden from accessibility.
- Verification: macOS sidebar snapshots and unchanged phone snapshots rerun;
  dated test-app build, lint/format and diff check. No new provider, privacy,
  architecture or settings behavior; only CHANGELOG, QA and WORKLOG need updates.


## 2026-09-20 — Codex — PR #52 sidebar scope hierarchy

- Continued clean feature/native-ui-polish / open PR #52 to main after approval
  of the scope/destination proposal. Moved desktop scope selection into a fixed
  Mailboxes header, preserving custom profile names and management access.
  All Inboxes stays first; Smart Views consolidates create/manage in one menu.
- Visual regression loop: 11 expected old-reference failures, inspected renders,
  fixed safe-area header overlap using a separate stack header, then refreshed
  references. Four desktop tests/11 cases and seven iOS tests/11 unchanged cases
  pass. Native dated mock build passes; scope menu, Smart Views expansion,
  management sheet and unified inbox checked. Lint/format/diff check pass.
- No business-logic change; used rendered visual regression and native action
  checks rather than a new unit test. Initial test command from workspace root
  had no BrevMail scheme; reran successfully from packages/BrevMail.
- Updated CHANGELOG and QA evidence. README, privacy, ADRs and AGENTS need no
  change: no setup, architecture, network or workflow changes. Physical spoken
  VoiceOver and live-provider QA not run. No merge/release/version change.

## 2026-09-20 — Codex / Sol — #53 / PR #52 full native audit follow-up

- Started from clean feature/native-ui-polish at 1a3c6b9b, continuing open PR
  #52 to main. Created #53 for all nine approved audit findings and moved its
  project card to In progress. Four Sol agents own isolated sidebar, mail-shell,
  reader/contrast and compose slices; integration owns settings and QA.
- Removed duplicate fetch guidance and isolated the accounts pixel selection.
  Two accounts references were inspected/refreshed; four tests in two suites
  pass. The broad settings snapshot selection had fourteen pre-existing
  mismatches on macOS 27; unrelated references were preserved.
- Original iPhone snapshots pass (seven tests / eleven cases). Strengthened
  shared fixtures with explicit text-size traits, navigation hosting and a
  two-account/long-name/nested sidebar case. Integrated all four Sol slices and
  reviewed follow-ups restoring custom profile names, true folder nesting,
  active mailbox qualifiers, native menu semantics and narrow row metadata.
- All nine audit findings are implemented: sidebar hierarchy/alignment,
  desktop initial columns and narrow rows, Dynamic Type/contrast, primary
  toolbars, iPhone account/status context, compact reader metadata, compose
  hierarchy and single fetch guidance. Final render review also fixed a clipped
  local-folder creation footer and removed the duplicate iPhone thread menu.
- Behavioral red/green evidence comes from the slice policy/body/contrast tests;
  cosmetic changes use failed prior-reference comparisons, visual inspection,
  then updated pixel baselines. No mirror unit tests were added for spacing.
  Corrected cropped/time-dependent fixtures and a 50 ms async test assumption
  exposed by the old hosted CI failure. Unrelated snapshot debt is unchanged.
- Final checks: BrevMail behavior 1,606 tests/247 suites; Mac mail pixel selection
  37 tests/12 suites; iOS selection 18 tests/5 suites (13 phone renders); themes
  9 tests; focused settings 4 tests/2 suites. Lint, zero-change format, baseline
  inventory and diff check pass. Dated Mac mock build/startup verification and
  iOS build/explicit mock launch pass. Native sidebar, reader, menus and compose
  inspected on both platforms; no mail sent.
- Fresh 1440 pt native root probe resolves sidebar/list to 240/420 pt without
  clearing saved window state. Existing-window divider retention remains an
  inference; the observed initial split and constraints are recorded in QA.
- Documentation sweep: CHANGELOG, QA evidence/baseline policy and WORKLOG
  updated; ADR-0002 documents the protected theme contrast change. README,
  PRIVACY, ADR-0006 and AGENTS need no updates: setup, network behavior, privacy
  and repository workflow are unchanged. Physical spoken VoiceOver, live
  providers, unrelated Settings snapshots and maintainer acceptance remain open.
- QA scope, commands and limitations are tracked in
  docs/qa/native-audit-polish-2026-09-20.md. No live mail, daily-driver replacement,
  version change, merge or release operation was performed.
- Published the integrated changes in existing PR #52 and moved #53 to
  In review; #49/#51 remain open/In review. Resolved the obsolete compose-menu
  review thread after checking the updated overflow policy, tests and native
  accessibility menu role. Hosted CI then found a stale compact-layout source
  check requiring the removed content frame. Reproduced that failure, checked
  the policy and outer split modifier instead, and passed the focused check and
  complete `scripts/test.sh --self-tests-only` set. No production code changed
  for this CI correction; hosted checks must rerun on the follow-up head.

## 2026-09-20 — Codex — #5 slice 2 settings source surface

- Built on feature/pim-source-lifecycle (PR #56, stacked on the ADR-0072
  acceptance PR #55). Moved issue #5 to In progress on the board and posted
  the slice plan as an issue comment.
- Settings Sources UI (BrevSettings): PIMSourceSettingsModel view-model
  wrapping PIMSourceCoordinator; PIMDAVConnectForm pure validation
  (discovery email, manual HTTPS endpoint with loopback exception,
  app-password + bearer modes); PIMSourcesSettingsView group with
  per-source shared status, sync opt-in toggle, disconnect, credential
  reconnect sheet, and removal confirmation offering keep-cache vs
  delete-cache (unsent drafts always die, provider data never touched).
  Google enablement listed as "Not available yet" until reauthorization.
- CalendarContactsSection copy replaced per ADR-0072: direction summary
  now describes optional Google/DAV sources; DAV connect joined
  "Available now"; Google enablement, browsing, unified search and
  event/contact authoring are "Not available yet" (accepted scope).
  The ADR-0039 "full PIM editing outside Brev" boundary text removed.
- Wiring: AppSession.pimSourceCoordinator built by AppSessionFactory
  (JSON store + per-source data dirs under Application Support/Brev,
  Keychain credentials); SettingsView passes it to the section; both app
  targets updated.
- Verification: 27 new/updated tests in 4 suites pass (form validation,
  model lifecycle incl. reconnect failure preserving state, row
  presentation action matrix, scope presentation contract). BrevMail
  package builds clean. swiftformat + swiftlint --strict clean on all
  touched files.
- Skipped: pixel snapshot for the new group — local macOS 27 renderer
  does not match the macOS-26-recorded baseline (32 pre-existing
  mismatches in the suite confirm); behavior coverage added instead.
  iOS/macOS app builds left to CI (tuist graph unchanged, one added
  SettingsView argument).
- Next: slice 3 Google feature-triggered reauthorization plus
  mail-account-removal handling of linked sources (acceptance criteria);
  live-provider smoke remains the maintainer gate.

## 2026-09-19 — Codex — Public TestFlight beta without demo mail

### Goal

Create a public TestFlight signup path while ensuring externally distributed
Release builds cannot launch or expose the demo mailbox.

### Changes

- Created the App Store Connect external group `Public Beta` and configured its
  public link. The link is not operational while the group has zero builds. No
  historical build was added because the existing processed builds predate the
  current source baseline and cannot be tied to this guard.
- Moved the demo-startup branch in `AppSessionFactory.makeDefault` behind a
  compile-time `DEBUG` gate, so an injected request is ignored in Release.
- Added a Release-compiled regression test and CI invocation for the exact
  injection seam.
- Added a separate external-TestFlight export policy. The existing internal
  policy remains explicitly internal-only.
- Documented the external upload flow and public group link.

### Verification

- Red: the new Release test proved an injected request created `MockBackend`
  before the factory gate was added.
- Green: the focused Release test and the Debug `AppSessionFactoryTests` suite
  pass; the internal/external export-policy test, format, lint, ADR check, and
  `git diff --check` pass. Existing unrelated Swift 6 concurrency warnings were
  emitted while compiling `BrevMail`.

### Handoff

- Upload a fresh Release archive from the reviewed/merged commit, wait for App
  Store Connect processing, add it to `Public Beta`, and complete Beta App
  Review. The public group intentionally has zero builds until then.

## 2026-09-19 — Devin — Daily-driver UI + reliability perf pass (feature/perf-daily-driver)

### Goal

Land the BrevMail UI scan/render and launch/reliability findings from the
daily-driver audit (batches C and D, interrupted mid-flight — this entry
completes, fixes, and verifies them).

### Summary

- `ThreadConversationRenderPool` (new, `BrevMail`): one pool per
  `ThreadConversationView` keeps an 8-slot LRU of `HTMLBodyWebViewStore`s
  and funnels body/attachment fetches through 4 permits, so "Expand All"
  no longer spawns a WKWebView + parallel backend read per card.
  `HTMLBodyWebViewStore.releaseWebView()` drops the WebKit instance on
  collapse/evict; re-expand lazily recreates it from the same store.
- `FollowUpReminderIndex` (new): active reminders grouped by message ID
  at settings (re)load; identical exact→account→global resolution to
  `FollowUpSettings.reminder(for:sourceID:)` but O(bucket) per row.
- `MailboxListTemporalInvalidationTracker` + `LocalMessageWorkflowLookup`
  + `LocalMessageWorkflowLookupCache`: the last-week invalidation scan and
  snooze/done/note membership checks are memoized instead of rescanning
  all headers per body evaluation.
- `MessageListPresentationSnapshot`/`UnifiedInboxPresentationSnapshot`
  compute unread/pinned counts and per-thread buckets inside the cached
  build; `blockedSenderEmailSet` materializes the blocklist once.
- `MessageListSearchChipsCache`/`UnifiedInboxSearchChipsCache` memoize
  NL search-chip regexes per (text, folder, execution, scope, day).
- Compose: `ComposeBodyTextSelection(characters:)`/`ComposeBodyInsertionPoint
  (characterCount:)` borrow the live text storage per caret update instead
  of copying the whole document twice; `ComposeHTMLPublicationController`
  takes a producer thunk so the attributed-string copy is only paid when
  the debounce fires, and skips republishing unchanged HTML.
- `SenderContextPanel`: cached `DateFormatter` per locale+timezone.
- Reliability/launch: `MailFetchBackoffSchedule` + coordinator `now:` seam
  stretch the fetch cadence after consecutive failures (root view and
  background coordinator both gated); `DeferredLocalSearchIndex` defers
  the local index's SQLite open off first paint; settings sections decode
  persisted payloads into `@State` once and refresh via dedicated
  notifications (`brevPendingRestoredAccountsDidChange`,
  `brevAppearanceThemeSettingsDidChange`,
  `brevMailboxSyncSettingsDidChange`) instead of blanket
  `UserDefaults.didChangeNotification`; `RetiredSecurityMaterialMigration`
  records a completion key so launch stops re-enumerating defaults;
  `MailStorageSection` counts snapshot headers via a placeholder
  `Decodable` envelope; `AvatarImageDecoding` cache keys hash source
  bytes once (SHA-256) instead of pinning/re-hashing the payload;
  share extension no longer double-handles a provider that conforms to
  both `public.url` and a file type.
- Gmail `connect()` on a warm cache returns after activating draft ops
  and runs the network pass in a background `initialSyncTask`
  (`initialSyncSettled()` is the test/lifecycle seam); `reconcileExclusive`
  joins concurrent refresh callers to one in-flight reconcile.

### Fixes made during stabilization

- `MailFetchBackoffSchedule.permitsAttempt` only gates once `extraDelay`
  has grown — the original gated on every attempt since the last, which
  skipped all driven ticks after the first (real-clock `now`) and hung
  every coordinator test awaiting a second refresh; it would also have
  dropped slightly-early timer-coalesced ticks in production with no
  failure involved. `MailFetchSchedulerTests` updated to the corrected
  semantic.
- `ComposeBodySelectionTests` expected `", "` to be a whitespace-only
  selection — it trims to `","`, non-empty. Changed to `" "`.
- `ContactsAccessPolicyTests.realMailboxLeavesContactsAvailable` pins
  the process-wide `allowsSystemContactsAccess` with defer-restore —
  `AppSessionTests` demo sign-ins flip it under parallel scheduling
  (pre-existing race, flaky loss on the full suite).

### Deferred findings (recorded, not implemented)

- `MailNavigationState.selectMessage` re-stores `currentFolderHeaders`
  per click — CoW makes the assignment cheap, but observers still fire;
  needs a same-content skip that is itself not O(n).
- `MailScrollEdgeBlurView.reduceToBareBackdrop` re-walks the material's
  layer tree per trigger — bounded (~15 layers) with an existing retry
  ladder; low magnitude, cosmetic code path.

### Verification

- `swift test --package-path packages/BrevMail` — 1627/1627 pass
  (was hanging before the `permitsAttempt` fix; suite had 3 issues).
- `swift test --package-path packages/BrevBackend` — 1130/1130.
- `swift test --package-path packages/BrevGmail` — 152/152.
- `swift test --package-path packages/BrevSyncEngine` — 78 XCTest + 16
  Swift Testing.
- `swift test --package-path packages/BrevSettings` — 374 tests; the 9
  issues are pre-existing snapshot mismatches that reproduce identically
  on clean `main` (host/baseline renderer drift), unrelated to this diff.
- `scripts/lint.sh`, `scripts/format.sh`, `scripts/privacy-audit.sh`,
  `git diff --check` — clean (ADR-0003 updated for the BrevAvatars
  protected-path change).

### Handoff

- `GmailAPIDraftBackendTests` restart/recovery tests noted by batch B as
  timing-flaky under full-suite parallel load; green this run.
- Manual QA owed: expand-all on a long thread (pool behavior), settings
  panes reflecting external writes, background-mail backoff in practice.

## 2026-09-19 — Devin — UI/UX consistency pass (feature/uiux-consistency)

### Goal

Fix the UI/UX audit findings across iOS/iPadOS/macOS: honest
capability-gated menus, consolidated reader actions, accessibility,
canonical Flag terminology, shared BrevDesign components, iPad keyboard
undo, and focused presentation tests.

### Changes (this session's files)

- `MessageCommandPresentation`: all menu titles localized via
  `String(localized:bundle:.module)`; unsupported actions omitted rather
  than disabled; new `readerMenu(...)` surface (same inventory minus
  row-only Select/Pin to Top).
- `DetachedMessageCommand`: extended to the full reader action set with
  `init?(menuAction:)` and `dismissesWindow`; bus dispatch unchanged.
- `BrevMailRootView`: extended detached-command dispatch (snooze, done,
  local-folder filing, block-sender alert, sheets, view-source/headers,
  open-in-new-window); iOS compact reader + `MailDetachWindowPolicy`
  routing; double-open dedup via `lastOpenInNewWindowRequest`; macOS
  fallback toolbar gained Mark Read/Unread; iOS ellipsis deduplicated.
- `MessageDetailView`: consolidated iOS overflow menu + reader-body
  context menu + detached-window overflow all render `readerMenu`;
  print/PDF run locally, everything else via the command bus.
- `ThreadConversationView`: per-card `.contextMenu` reusing
  `readerMenu` + bus dispatch; per-message print/PDF reusing the thread
  print pipeline; AI summary failure state gained a Retry button
  (`aiSummaryRetryAction`).
- `MessageListView` / `UnifiedInboxListView`: shared `MailBulkActionBar`;
  unread dot exposes a VoiceOver "Unread" label on non-compact rows;
  child rows take mailbox font-family/text-size/density; iOS row menus
  never emit Print/PDF; unified inbox is per-source capability-gated.
- `ThreadInlineChildRow`: preference-derived fonts/spacing + labelled
  unread dot.
- `MailUndoCommands`: iPadOS ⌘Z mail-undo command group (text-editor
  undo still wins via responder chain); registered in
  `apps/iOS/BrevApp.swift`.
- `KeyboardShortcutsHelpView`: inventory extracted to
  `MailKeyboardShortcutInventory`, corrected bindings (⌘⇧U/⌘U read,
  ⌘⇧L/⌘S flag, ⌫ delete, ⌘Z undo on both platforms), macOS-only flags.
- `FolderSidebarPresentation`: removed dead `canOpenInNewWindow` /
  `canDownloadOffline` params that produced inert entries.
- Tests: `MessageCommandPresentationTests` updated (stale section
  expectation fixed for the omission rule) + new coverage for print/PDF
  omission, `readerMenu` parity, detached-command mapping, and window
  dismissal; new `MailKeyboardShortcutInventoryTests` pins the help
  panel against real `keyboardShortcut` registrations.

### Verification

- `swift build --package-path packages/BrevMail` — green.
- `swift test --package-path packages/BrevMail` — 1638 tests; all pass
  except 21 snapshot-image diffs in suites CI already skips under
  `swift test` (`.github/workflows/build.yml` macOS<26-era skip list):
  MailContextColumn, DetachedMessageWindow, ThreadInlineChildRow,
  LocalFolder, MonoMailSelection, SavedSearchEditorView,
  ConversationWorkspace snapshot tests. Two of these
  (ThreadInlineChildRow, DetachedMessageWindow) cover intentionally
  changed UI and may need reference re-recording on the snapshot runner;
  the rest are unrelated/host rendering noise (SavedSearchEditorView is
  the other session's file).
- `swiftformat --lint` on all touched files — clean.
- Filtered re-run after formatting: 30 tests in
  MessageCommandPresentation + MailKeyboardShortcutInventory — pass.

### Skipped verification

- iOS/iPadOS compile — later verified green via
  `swift build --triple arm64-apple-ios17.0-simulator` (BrevMail +
  BrevSettings). Snapshot re-recording requires the CI xcodebuild job.

### Handoff

- Tree still contains the other agent's mid-flight edits (ComposeView,
  sheets, BrevSettings, `.swiftlint.yml` literal-color rule extension).
  Do not commit this file set wholesale.
- If CI's snapshot job flags ThreadInlineChildRow or
  DetachedMessageWindow references, re-record them — both diffs are
  intentional (preference-driven child-row typography + unread-dot
  label; detached-window overflow menu).

## 2026-09-19 — Devin — UI/UX consistency pass, sheets/settings scope (feature/uiux-consistency)

### Goal

Fix the audit findings assigned to the sheets/settings stream: adaptive
sheet sizing, iPad split widths, 44 pt touch targets, canonical
BrevDesign surfaces/chips, headline sheet titles, accessible icon
buttons, and package-aware localization.

### Changes (this session's files)

- `BrevDesign`: new `BrevIconButton` (44 pt iOS hit target around a
  compact glyph + required accessibility label), `BrevChip` capsule
  style for filter/toggle chips, `BrevQuietSurface` inset-surface
  modifier; `BrevButton` gained a `bundle:` initializer (String Catalog
  extraction from SPM packages) and a 44 pt iOS minimum height;
  `BrevInlineStatus` action/dismiss hit areas enlarged.
- `ComposePresentation` + tests: regular iOS compose minimum 680→660
  (macOS stays 680); iOS toolbar hit target 36→44.
- `ComposeView` / `RecipientChipField`: 44 pt iOS targets on toolbar,
  editor-appearance, Cc/Bcc reveal, attachment-remove, chip-remove and
  suggestion rows; Esc cancel / ⌘↵ send shortcuts.
- Mail sheets (`MoveToSheet`, `ScheduleSendSheet`, `ComposeLinkSheet`,
  `MessageTaskSheet`, `MessageEventSheet`, `MessageNoteSheet`,
  `MessagePropertiesSheet`, `MessagePropertiesPresentation`,
  `MailboxActionAgentSheet`, `TemplatePickerView`, `ThemePickerView`,
  `MessageRawSourceSheet`, `MailProfileManagementSheet`,
  `InitialMailboxSelectionSheet`, `SnoozePickerView`,
  `FollowUpDatePickerView`, `ScheduleSendDateResolver`,
  `MailboxChatPanel`, `MailboxChatScopeContext`,
  `ServerSearchSyntaxHint`, `OutboxView`, `AllAttachmentsView`):
  desktop-only `frame(minWidth:)`/`minHeight` gated under
  `#if os(macOS)` (or driven by platform-aware policy); consistent
  localized dismiss/close controls; `.title`→`.headline` sheet titles;
  44 pt iOS targets; `.brevQuietSurface`/`.brevChip` migrations;
  `String(localized:bundle:.module)` sweep; initial-mailbox sheet wraps
  the list in a `ScrollView` with a 44 pt default-mailbox control.
- `BrevSettings`: `SettingsView` iOS split minimum 760→680 (ideal 740);
  `SectionScaffold`/`SavedSearchEditorView`/`BackupPreviewSheet` titles
  → `.headline`; quiet-surface migration across Accounts, Notification,
  VacationResponder, MailboxView, Security, AIProviderSettingsPanel,
  MailFolderExportStatusView, RulesSection, SignatureSection,
  TemplatesSection, `SettingsSectionComponents` (picker label +
  `SettingsInfoCallout`); `ServerRuleEditorView` and
  `SecuritySection` export sheet frames macOS-gated; rules ↑/↓
  text buttons, signature reorder/delete and template pin/reorder
  controls → `BrevIconButton`/accessible buttons with 44 pt iOS targets;
  Accounts overflow menu → 44 pt iOS target; remaining bare
  `BrevButton`/`Label` titles localized.
- `.swiftlint.yml`: `no_literal_colors_in_views` now also covers
  `Color(hex:)` and BrevMail/BrevSettings sources.
- Small cross-scope fixes in core-surface files kept additive:
  `.brevChip` on the inbox-category bar (MessageListView),
  `.brevQuietSurface` on the iOS sidebar profile picker
  (FolderSidebar) and security badge (ThreadMessageCard), localized
  detached-window action labels + invite/remote-content buttons
  (MessageDetailView, ThreadMessageCard), and a one-line SwiftLint
  directive fix in `BrevMailRootView` (`:next`→`:this`) so the doc
  comment stays attached — required for `lint.sh` to pass.

### Verification

- `swift build --package-path packages/BrevMail` — green.
- `swift build --package-path packages/BrevSettings` — green.
- `swift build --triple arm64-apple-ios17.0-simulator` for both
  packages — green; caught and fixed an iOS-only type-inference break
  in `MailKeyboardShortcutInventory.sections` (`#if` inside `.map`
  left the section literal as `Any` on iOS — array is now typed and the
  macOS-only-entry filter split out).
- `swift test --package-path packages/BrevMail` filtered run —
  62 tests across ComposePresentation, ScheduleSendDateResolver,
  MessagePropertiesPresentation, InitialMailboxSelectionPresentation,
  MailboxChat scope/notice, FollowUpReminderPresentation,
  AttachmentSearchPresentation, ComposeRecipientAutocomplete — pass.
- `swift test --package-path packages/BrevSettings` — 374 tests; all
  non-snapshot tests pass. 34 snapshot issues are image diffs in
  BackupPreviewSheet/MailFolderExportStatus/MailStorageSection/
  BrevSettingsSnapshot suites — expected: the quiet-surface and
  headline-title changes are intentional visual diffs; references need
  re-recording on the CI snapshot runner (same situation as the
  core-surfaces session documented).
- `mise exec -- swiftformat --lint .` — clean (19 touched files
  reformatted for `#if` indentation).
- `mise exec -- swiftlint --strict --quiet` — clean;
  `scripts/test-swiftlint-coverage.sh` — OK.

### Skipped verification

- Snapshot re-recording (needs CI snapshot host); iOS device/UI tests;
  `check-adr-required.sh` is a staged-files gate — no protected-path
  changes made.

### Handoff

- Tree mixes both agents' uncommitted edits on
  `feature/uiux-consistency`; review `git diff` per file before
  committing rather than committing wholesale.
- Re-record the BrevSettings snapshot references listed above (and the
  core-surfaces references from the other entry) on the snapshot
  runner, or confirm CI's skip list covers them.


## 2026-09-19 — Codex — PR #47 and board hygiene

- Goal: assess open PR readiness, reconcile the Brev board, and select the next
  implementation priority. No application implementation was requested.
- Live assessment: PR #47 at `5e7227415982308346884079eed58a348d89b063`
  targets main, has 20 successful checks and four unresolved current review
  threads. Targeted source inspection supports concerns about scene-unscoped
  reader commands, detached-sheet ownership, workflow selection reconciliation,
  and unlocalized PDF errors. This was not a full independent code review.
  The PR also records 22 BrevMail and 34 BrevSettings snapshot failures locally;
  reference updates and native QA remain pending despite green hosted CI.
- Board: added PR #47 as In progress/P1; assigned P1 to issues #1 and #2 while
  retaining Ready. Kept #4 Ready and the dependent PIM work in Backlog. Corrected
  ADR-0055 to ADR-0039 in #3/#4 and privacy ADR-0008 to ADR-0006 in #4/#5/#12/#14.
  Updated #4 to complete the existing Proposed ADR-0072 rather than draft another.
  Issue bodies were read back after editing. Legacy board cards were preserved.
- Recommendation: repair #47 on its existing branch first, with regression
  coverage for two-window routing, detached presentation, and Snooze/Done/undo
  navigation. Reconcile snapshots and perform iPhone/iPad/macOS QA next; then
  execute #1 accessibility and #2 real-provider lifecycle acceptance. Complete
  and obtain acceptance of ADR-0072 before starting #5.
- Verification: refreshed origin refs; inspected PR checks/reviews, all 255
  pre-change project items, all 15 open public-repository issues, ADRs and source.
  No application tests/builds or native/account QA run for this triage-only pass.
  No merge, closure, Done transition, release, or branch/worktree deletion.
- Documentation sweep: only this worklog needs a local update; no product,
  architecture, privacy behavior, or release content changed. This audit entry
  remains local and uncommitted; application source is unchanged.


## 2026-09-19 — Codex — PR #47 review remediation

- Goal: continue the assessed PR here, fixing its four current review findings.
  Worktree: `/Users/henrik/.codex/worktrees/ff7b/brev`; local branch
  `feature/pr47-review-fixes`, based on PR head `5e722741`. Push destination is
  the existing `feature/uiux-consistency` branch and PR #47, targeting main.
- Changes: replaced process-wide reader command broadcasts with an injected
  owner, including the compact iPhone reader and thread cards. Detached macOS
  presentation actions activate the captured mailbox window after closing the
  reader. iPad detached commands open a mailbox scene using a one-shot opaque
  UUID handoff; only in-memory content is retained, with abandoned handoffs
  expiring after five minutes. Restored scenes cannot replay consumed commands.
- Workflow: both lists observe externally changed local workflow state. Unified
  navigation excludes workflow-hidden messages while preserving source identity
  and search semantics. Localized per-card PDF failures. Fixed the newly added
  detached overflow menu's light-theme tint and refreshed its inspected baseline.
- TDD: a hosted parent-binding test failed on undo before the folder observer;
  unified Snooze/Done cases failed before unified reconciliation. All four hosted
  folder/unified x Done/Snooze cases pass, including real UndoQueue reversal.
  The one-shot handoff test failed before implementation and passes with two
  independent source-owned commands, single consumption, and no message content
  in serialized scene payloads. Updated the old dismissal test to cover visible
  presentation handoff while preserving inline macOS toggles.
- Verification: iOS Simulator build succeeded (Xcode 27.0); 1,573 BrevMail and
  365 BrevSettings non-snapshot tests passed. Lint, format, privacy audit,
  extension-plist checks and diff-check passed. Full suites reproduced the PR's
  22 Mail and 34 Settings pixel mismatches before the detached baseline update;
  the full Mail run additionally exposed the now-updated old dismissal contract.
  Remaining pixel baselines were not blindly re-recorded from this macOS 27 host.
- Final verification: 35 focused tests across five suites passed, including the
  refreshed detached-reader snapshot and Contacts access policy. The final full
  BrevMail run had 1,634 tests with exactly 21 remaining snapshot issues and no
  behavior failures. The final iOS build passed; format changed zero files and
  lint/diff-check passed. The 34 Settings snapshot issues remain unchanged.
- Rendered evidence: inspected the detached baseline and new render; the new
  overflow icon was initially near-white, then visibly theme-colored after the
  tint fix. iPhone 18 Pro / iOS 27 launched in explicit mock mode and runtime AX
  exposed Refresh, Compose, Settings and Sort/filter names. Automated row and
  toolbar taps did not produce the expected navigation, so this does not prove
  reader-menu interaction, VoiceOver, or Dynamic Type acceptance. iPad multi-scene
  presentation and real-provider lifecycle QA remain pending.
- Documentation sweep: updated CHANGELOG and ADR-0033 for command ownership and
  handoff behavior. README/product scope and external-network/privacy behavior
  are unchanged. No issue closure, Done transition, merge, release or daily-driver
  rebuild was performed. Prior hygiene entry above is historical; both worklog
  entries are included with this PR update.

- Post-push integration check: GitHub reported a CHANGELOG-only conflict with
  main's TestFlight entry at the same insertion point. Moved this follow-up's
  changelog bullets within Unreleased to preserve both entries without merging
  branches or rewriting history. No application source changed in this follow-up.

## 2026-09-19 — Codex — PR #47 iPhone layout correction

- Goal: address the supplied Mailboxes/Inbox screenshots before acceptance.
  Continued `feature/pr47-review-fixes` in the ff7b worktree, pushing to the
  existing `feature/uiux-consistency` PR targeting main; board moved to In progress.
- Fixed an unbounded UIKit search field (319pt in the red simulator test, now
  44pt). Raised iOS sender/subject typography while preserving size preferences,
  restored configured previews, and allowed phone subjects to wrap to two lines.
  Added navigation titles, moved Compose to the bottom toolbar, kept Settings
  only in the mailbox toolbar, and distinguished the workspace AI menu icon.
  Removed empty leading disclosure space and redundant account indentation on
  iOS folder rows; expandable folders retain a separate 44pt trailing control.
- TDD: search sizing reproduced the 319pt failure in a hosted iPhone simulator
  before passing. Preview/Settings policy tests failed first, then passed.
  Final focused Mac package run: 44 tests across four suites passed. Four new
  iOS pixel references (two parameterized tests) were inspected and comparison
  passed in light/dark; the required iOS snapshot CI lane includes them.
  iOS app build, lint, format and snapshot metadata checks passed.
- Rendered QA: iPhone 18 Pro/iOS 27 in explicit mock mode. Verified mailbox
  selection, message opening, search narrowing to GitHub, and Compose open/close.
  The automation tap helper was ineffective; explicit touch-down/up plus field
  focus made these interactions work. Reader screenshot was inspected, but its
  runtime AX snapshot did not settle, so reader-menu/Back and VoiceOver are not
  claimed verified. No real-account mail was sent or changed.
- Remaining: full VoiceOver/Dynamic Type and iPad acceptance, real-account QA,
  and the separately recorded 21 Mail/34 Settings baseline mismatches. Those
  older baselines were not refreshed in this pass. No merge/release/Done action.
- Documentation sweep: CHANGELOG and iOS snapshot policy updated. README, ADRs,
  privacy documentation, and external network behavior need no changes for this
  platform layout correction; architecture and public APIs are unchanged.

## 2026-09-19 — Codex — PR #47 merge and TestFlight preparation

- Henrik authorized merging PR #47 when ready and deploying the new iOS build
  to TestFlight. Refreshed checks and all six review threads before merging.
- Fixed the two new findings: reader Block Sender now starts/finishes the root
  mutation request and rejects stale success/error responses; macOS and iPad
  detached readers receive the host's local-filing availability.
- Verification: 53 existing focused tests passed across request/source/work
  blocking policies, action availability, handoff and workflow reconciliation;
  iOS simulator build and lint passed. No new red/green test was added for these
  private scene-wiring changes: the existing policy tests cover the behavior,
  and call-site inspection plus both platform builds verify the wiring. Native
  multi-window/slow-provider acceptance remains a TestFlight QA item.
- Apple currently reports 0.2.2 (4) VALID. Next candidate is 0.2.3 (5), archived
  with explicit version/build overrides from the merged main commit. The checked-in
  internal-only export policy and existing Henrik Internal QA group are used.
  Upload and Apple processing will be recorded separately from merge/build.

- Further pre-merge review: fixed per-card PDF body failures being swallowed,
  localized the empty-subject export filename, hid Archive for already-archived
  reader/card messages, resolved detached folders from the clicked source, and
  condensed all iOS compose toolbars so narrow regular-width iPad scenes retain
  Send. The compose policy regression failed first (four assertions), then the
  63-test focused suite passed. Added a visually inspected 660pt regular-width
  compose reference, rendered on the iPad Pro 13-inch simulator.
- The first hosted Gmail run failed the existing scheduled-send restart test.
  The full 152-test local Gmail suite passed, as did ten consecutive focused
  runs. No Gmail delivery code was changed; the final head must pass hosted CI.
  The pre-fix archive is superseded and will not be uploaded.

- Cross-device verification found text antialiasing drift between the iPad and
  iPhone hosts in the new narrow-compose reference. Visually inspected both
  images and their difference, then aligned the reference with the iPhone CI
  host. No production code changed in this baseline correction.
- Final review follow-up: card Print now reports body-fetch errors instead of
  opening incomplete output, and shortcut help restores Command-Delete. The
  shortcut inventory failed first against the incorrect glyph. Native print
  panel error automation is impractical in the package runner; error flow was
  inspected and both platform builds cover the call sites. Device print QA
  remains pending. All five phone snapshot comparisons passed after the
  reviewed antialiasing-only reference correction.

- The latest hosted Gmail run reproduced the restart test failure. Inspection
  found the test assumed each delivery request starts a fresh pass, whereas
  GmailScheduledDeliveryDriver explicitly joins an in-flight startup pass.
  After reviewed rescheduling, that pass may retain its earlier due-message
  snapshot. The test now drives bounded subsequent passes before asserting
  exactly two sends and an empty outbox; its no-automatic-retry assertions are
  unchanged. Production Gmail scheduling code is unchanged.
- Verification of the scheduling-test correction: the revised restart test
  passed in all ten full-suite repetitions. Nine complete 152-test runs passed;
  one encountered an unrelated SQLite trigger-setup failure in the cleanup
  test. Final-head hosted CI remains required. The five phone snapshots also
  passed with xcodebuild exit 0 when simulator diagnostic collection was
  disabled; the earlier post-test stall was in diagnostic collection.

- Final detached-reader finding: Read, Flag, and Done now return to the owning
  mailbox, like other stateful detached commands. This deliberately avoids
  retaining an immutable header after mutation; subsequent actions use the
  owner's refreshed state. The policy test failed for all three actions before
  the fix. Offline download still keeps the detached reader open.

### 2026-09-20 — Codex — PR #47 final iPad handoff

- All twenty checks passed at c60830d. A final review found iPad handoff ignored
  the non-dismissal policy for Keep Offline. Applied the existing tested policy
  at the scene call site. No new policy or visual layout was introduced; this
  private scene-wiring correction uses the existing command policy test and
  iOS build, with native multi-window acceptance still pending.

- Pre-merge source safety: a detached action now requires its loaded source
  section, synchronously applies that source's folders/mailbox context, and
  rejects unavailable sources. A queued mutation also rejects a later source
  switch. Reader-menu calls use the same handoff. The two-account regression
  failed six assertions before the fix, including the wrong permanent-delete
  classification when the previous source lacked Trash.
- iPad mail Undo now appends to the native Undo/Redo group instead of replacing
  it. Native command-menu automation is unavailable in the package runner;
  existing Undo routing tests and iOS compilation validate the supported seams.
- Verification: all 36 focused source-handoff, source-sync, command and native
  Undo routing tests passed after the red regression; lint and format passed.
  The separate local-folder visibility test failed under hosted load but passed
  locally (11 tests). It uses fixed 50ms sleeps around asynchronous refresh;
  final-head CI remains the merge gate.

- iOS CI caught a startup crash from the appended mail Undo duplicating native
  Command-Z. Corrected iPad mail Undo to Command-Option-Z, preserving native
  Command-Z/Shift-Command-Z, and updated the help inventory and changelog.
  The crashing app bootstrap is the red reproduction; app-hosted verification
  and the iOS inventory test are required before pushing this correction.
- App-hosted iOS startup/search-layout verification passed with xcodebuild exit
  0 after the shortcut correction. The iPad inventory run also exposed old
  macOS-only test assumptions; platform filtering is now asserted correctly,
  and native Redo is listed on both platforms (red regression verified).
- Final shortcut inventory: four tests pass on macOS and four on iPad with
  xcodebuild exit 0. Lint/format pass. Native iOS Undo/Redo are retained, mail
  Undo uses the non-conflicting Command-Option-Z chord, and the app-hosted
  startup regression is green.

- Further review: detached header resolution now falls back to MailBackend's
  cache-only enumeration contract, supporting native Gmail without a separate
  point-lookup service. Payload source IDs are forwarded explicitly, and a
  removed account is no longer substituted with another backend. Both resolver
  regressions failed before the fix.
- Compact template/rule rows now keep text above Pin/Enable and Edit, with
  reorder/Delete in a 44pt overflow menu. Rendered the old clipping at 216/271pt
  content widths, then visually inspected both corrected references. Added the
  two cases to the compatible iOS snapshot lane and baseline inventory. Fixed
  an existing iOS snapshot fixture access-level compiler error to run that target.
- Verification: 12 resolver tests pass; both compact Settings snapshots match
  their visually inspected references with xcodebuild exit 0. Lint and format
  pass. No new external network calls or privacy changes; the fallback uses
  the existing explicitly cache-only MailBackend contract.

- Integrated origin/main (743c459c) into the review branch without rewriting
  history. Resolved the sole changelog conflict by preserving both sets of
  entries. This brings PR #46's Release demo-mailbox guard and export-policy
  documentation into the archive source; all earlier archives are superseded.
  Final archive source must still match merged main exactly before upload.

- Unified workflow navigation now reuses the visible list's complete filter and
  sort pipeline, retaining thread members for expanded-row navigation. The
  hosted unread-filter regression failed four assertions before the fix; all
  five workflow cases now pass, including Snooze/Done/Undo.
- Signature controls now put the name field above Enabled and an overflow menu
  on iOS. Recorded the old collapsed-field render, then inspected corrected
  320/375pt references. Templates, rules and signatures are the complete set of
  settings rows touched by the new 44pt icon controls.
- The Release-only demo-mailbox guard passed locally after integrating main.
- All four compact Settings snapshot cases pass with xcodebuild exit 0 after
  visual review; lint, format and baseline metadata checks pass. Native menu
  interaction and real-account acceptance remain TestFlight QA items.

- Reader-command iPad scenes now take precedence over the shared Settings flag.
  Opening Settings explicitly clears that scene's consumed payload, preserving
  subsequent Settings access. The routing regression failed before the fix;
  all four restore/presentation policy tests now pass. Native multi-window
  interaction remains device QA; no additional visual layout changed.
- App-hosted iOS startup/search tests pass with xcodebuild exit 0 after the
  routing change; lint, formatting and diff-check pass. No snapshot refresh
  needed because only scene selection changed.

- Gmail now vends the existing cached-header extension using its account/message
  point lookup and preserves label/All Mail membership. Detached resolution
  treats an available point service's miss as authoritative, avoiding fallback
  folder scans for absent messages. The service regression failed before the fix.
- Final CI encountered a signal-11 crash in the unchanged native window test
  and a timing-sensitive attachment extraction timeout assertion. The 30 window
  policy tests pass locally; no production behavior was changed for either.
- Verification: all 30 Gmail reader tests, 12 detached resolver tests and 11
  attachment extractor tests pass; lint/format/diff-check pass. Cache-only
  service tests cover label membership, All Mail exclusion, missing IDs and
  zero transport calls. No visible layout changed or new network path added.

- Preserved the originating folder in detached-reader scene identity and all
  three iOS open-window call sites; exact membership lookup refuses unrelated
  labels. Same-source cross-folder reader actions now activate their target
  folder before mutation responses are matched. Two regressions failed three
  assertions before the fix. This carries identifiers only, not mail content.
- Verification: 21 tests across payload, resolver and handoff suites pass,
  including both same-source and cross-source cases. App-hosted iOS tests pass
  with xcodebuild exit 0; lint/format/diff-check pass. No pixel changes required
  baseline updates; native multi-window QA remains pending.

- Reader presentation actions no longer apply mailbox folders or change the
  visible conversation. Folder catalogs are required only for destination/role
  commands; mutation commands still activate their response context. Reply,
  Reply All and Forward now pass their explicit source through both in-place
  and detached compose paths. The loaded/failed-folder presentation regression
  failed 21 assertions before the fix.
- Verification: 22 handoff/resolver/payload tests and app-hosted iOS tests pass;
  lint, formatting and diff-check pass. No visual baseline changed. Native
  multi-window and real-account acceptance remain internal TestFlight QA.

- Block Sender now activates the target mutation folder only after confirmation;
  opening/cancelling the prompt preserves navigation. Extended the presentation
  regression (three red assertions) and verified confirmed activation separately
  for loaded and failed folder catalogs. Shared context preparation revalidates
  the source at confirmation time.
- Verification: all three handoff tests (five parameterized cases total) and
  app-hosted iOS tests pass; lint, formatting and diff-check pass. The change
  affects confirmation routing only, so no pixel references were updated.

- Exact detached-reader cached lookup now uses the payload folder ID directly
  even when folder enumeration fails. The empty-catalog regression failed before
  the fix. Added all five phone references to the baseline presence gate. A
  temporary fixture with an empty inbox PNG passed before and fails after the
  inventory change; the real baseline inventory passes.
- Verification: all 14 detached resolver tests, baseline inventory, lint,
  formatting and diff-check pass. No view layout changed; existing rendered
  references remain valid. Release archive validation covers the iOS build.

- macOS detached readers now wait for synchronous owner acceptance before
  closing. Admission rejects occupied presentation slots, unavailable compose
  or local-filing actions, and busy mutation lifecycles. Shared in-place dispatch
  uses the same admission checks. The presentation-admission regression failed
  all 15 sheet-backed commands before the fix. Native multi-window interaction
  remains manual QA; no rendered geometry changed.
- Verification: all 44 presentation/handoff/resolver tests pass; macOS sources
  compile through the package test build. Lint, formatting and diff-check pass.
  Release archive will verify the shared root on iOS; no snapshot refresh needed.

- Two hosted BrevDesign runs crashed with signal 11 around the unchanged native
  WindowAppearancePreferences test, including one after its assertions passed.
  The test now disables AppKit release-on-close because Swift owns its NSWindow
  until scope exit, avoiding competing lifetime ownership. Production window
  behavior is unchanged. Hosted crash is the red reproduction; local focused
  verification follows, with final-head CI still required.
- Verification: all 30 window-appearance tests pass, followed by three passing
  repetitions. Lint, formatting and diff-check pass. This test-only lifetime fix
  needs no changelog, ADR, privacy or snapshot update.

- Detached admission now reserves presentation space for actions that may ask
  for confirmation (Snooze, Delete, Block Sender), including existing reader
  prompts outside navigation.presentedSheet. Block Sender checks mutation
  availability without activating its folder before confirmation. If work
  becomes busy before confirmation, it reports the conflict instead of silently
  dropping the action. Four regression assertions failed before the fix.
- Verification: 45 presentation/handoff/resolver tests pass, as do lint,
  formatting and diff-check. Confirmation-capable actions conservatively
  reserve a presentation slot even when their current state may avoid a prompt.
  No pixel geometry changed; native confirmation QA remains pending.

- Expanded every detached-reader action and overflow target to 44pt on iOS,
  retaining compact macOS controls. Thread-summary Retry uses the same floor.
  Captured and inspected before renders, then the two new snapshots failed
  against the smaller references after the fix. Added the new references to
  the required inventory. Shared chip/surface public initializers and modifier
  methods now document their intent.
- Verification: all seven phone snapshot cases pass with xcodebuild exit 0
  after visual inspection; the prior five references are unchanged. Baseline
  inventory and formatting pass. Updated ADR-0002 for the protected shared
  component API documentation, then reran lint. Native interaction and Dynamic
  Type remain device QA.

- Corrected Settings keyboard-help metadata to macOS-only, matching the actual
  command registrations. The previous test incorrectly claimed an iPad binding;
  the corrected expectation failed before the metadata fix. No new shortcut
  registration or settings-routing behavior was introduced.
- Verification: all four inventory tests pass on macOS and iPad (xcodebuild
  exit 0); lint, formatting and diff-check pass. Platform filtering is covered
  directly by inventory tests; no new view styling or pixel references changed.

- Permanent-delete reader commands now retain a source-owned confirmation
  target without activating its folder. Confirmation revalidates the source
  before switching; cancellation preserves the original conversation. Covered
  Trash and no-Trash accounts. Two navigation assertions failed before the fix.
  Confirmation-time busy state reports the same explicit conflict as Block
  Sender.
- Verification: all 46 presentation/handoff/resolver tests pass, including both
  permanent-delete cases; lint, formatting and diff-check pass. No rendered
  layout changed; native confirmation interactions remain device QA.

- Keep Offline is handled directly in MessageDetailView using a shared retention
  action also used by the root. It toggles the same account-scoped pin and keeps
  the existing best-effort body prefetch, without a scene handoff. Menu labels
  invalidate after the local toggle. Busy single-reader and thread-card menus
  disable compose actions; roots include their exact compose-blocked state.
- Two regressions failed 12 assertions before the fixes: reader/card compose
  availability and local detached retention handling with source isolation.
- Verification: all 33 menu/retention tests and seven phone snapshot cases pass
  (xcodebuild exit 0); lint/format/diff-check pass. Existing snapshot references
  remain unchanged. The same explicit Keep Offline operation performs the same
  provider body prefetch, so no new network/privacy behavior was introduced.

- Documented all previously undocumented public initializer signatures changed
  by this PR: both root constructors, detached reader payload/view, single-reader
  and conversation views. Clarified source/folder identity, one-use handoff and
  local-filing parameters. Documentation-only exception: no TDD or new snapshots
  needed; lint/format/diff-check validate the update.

- Compact compose overflow retains registered plug-in views. The rendering test
  mounts its host in a UIWindow and fails without the contribution before passing
  with it. Unified/smart/saved-search Open in New Window no longer selects the
  target in its owner; the regression caught source, selection and callback changes.
- Verification: 12 focused tests pass, including all seven phone snapshot cases
  with unchanged references; lint/format/diff-check pass. Updated Unreleased
  behavior notes. No architecture, privacy or workflow contract changed.

- Documented Keep Offline's explicit provider body prefetch in PRIVACY.md and
  ADR-0006, covering list, unified and reader paths, local pin scope, removing
  a pin, and best-effort availability. Documentation-only exception: no TDD or
  pixel update; privacy audit, lint, formatting and diff-check validate the edit.

## 2026-09-20 — Codex — #4 and backlog sequencing

- Expanded Proposed ADR-0072 against all ten #4 criteria: domain/service
  contracts, source ownership, native consent constraints, caches, conditional
  writes, field preservation, recurrence, offline drafts and delivery gates.
- Reconciled README and ADR-0039/0009/0043 without claiming acceptance or
  shipped PIM support. Settings replacement copy is specified for acceptance;
  current UI remains unchanged while the old boundary still applies.
- Verified official Google and DAV references. Google's installed-app OAuth
  guidance excludes incremental authorization; #5 must prove feature-triggered
  native reauthorization and credential preservation before implementation ships.
- Board: #1/#4 In progress; #3/#5/#6/#7/#8/#11 P0 → P1 so #4 remains the
  immediate P0 prerequisite. Added #9 as a dependency of #10's writable contact
  actions. No issues closed or moved to Done.
- Verification: relative ADR links, lint, format and diff-check pass.
  Documentation-only TDD/build/snapshot exception; no code, scopes, network
  traffic, release behavior or permissions changed. README/ADRs/WORKLOG updated;
  PRIVACY, CHANGELOG, AGENTS and runtime settings need no change for a proposal.
- #2 preflight: checked configuration contains macOS Google client settings,
  but no disposable BREV_LIVE_* account values or iOS Google client settings.
  Requested the secure test-account configuration location; no live mail sent.
- Handoff: review and accept/narrow ADR-0072 before source/authoring work.

## 2026-09-20 — Codex — PR #48 pre-merge review

- Addressed the OAuth review finding: ADR-0072 now explicitly preserves the
  required non-confidential macOS Desktop credential from accepted ADR-0067.
  PKCE remains required; iOS uses its separate secretless native client.
- Documentation-only correction; TDD/build exception. Checked against ADR-0067
  and the existing token-exchange contract, with diff-check before commit.
- Henrik authorized merging the open PRs. The architecture remains Proposed;
  this correction does not introduce provider implementation or account changes.

## 2026-09-20 — Codex — #1 and iPhone account alignment

- Reproduced account-header indentation from Henrik's screenshot. Moved the
  iOS disclosure arrow trailing and matched folder-row padding; macOS unchanged.
- Inspected failing light/dark mailbox renders, updated only their references,
  and passed all seven phone snapshot cases. This is a visual regression check;
  no new logic test or test-only layout API was needed.
- Runtime semantic readback confirms inbox Refresh/Compose/Filter and mailbox
  Settings/Show messages at all twelve Dynamic Type categories. Settings and
  Compose open at the largest category. Restored the original large size.
- Reader AX snapshots did not settle; spoken VoiceOver and the reader back
  control remain unverified. #1 stays open with explicit partial QA evidence.
- Filed #49, Ready/P1, for reproduced compose horizontal overflow and missing
  Close/More at the largest accessibility category. Stored synthetic screenshot
  and filtered labels only in docs/qa/iphone-accessibility-2026-09-20.
- #2 preflight reported missing disposable credentials; no live connection or
  message transmission. The secure configuration location was requested.
- Verification: simulator build, seven phone snapshot cases, baseline inventory,
  lint, formatting and diff-check. CHANGELOG, QA and WORKLOG updated; README,
  ADRs, privacy and workflow contracts are unchanged by this layout correction.
- Handoff: review the alignment change, verify spoken VoiceOver/reader control,
  then address #49 before calling the compose accessibility flow accepted.

## 2026-09-20 — Codex — #1 / PR #50 reader hierarchy follow-up

- Reproduced Henrik's oversized account-address screenshot at accessibility5.
  Applied the existing iOS reader chrome range and middle truncation to account
  metadata; body text is unchanged. Labelled and reduced the loading indicator.
- Added standard/accessibility phone conversation snapshots. Inspected the old
  oversized rendering, observed the expected changed-reference failure, recorded
  corrected references, and passed nine phone cases across six tests.
- Simulator build/run, native loading screenshot, lint, zero-change final format,
  baseline inventory and diff-check pass. Stored synthetic screenshot in QA docs.
- The sample reader still stalls. A process sample shows repeated main-thread
  SwiftUI layout work; root cause is not established. Filed #51 Ready/P1 rather
  than claiming the UI styling fixes delivery. Raw diagnostics remain local.
- Updated CHANGELOG and QA evidence. No architecture, network, privacy, setup or
  workflow change: README/ADRs/PRIVACY/AGENTS need no update. No physical-device or
  spoken VoiceOver signoff. Continue existing PR #50; no merge or release.


## 2026-09-20 — Codex — PR #48 review follow-up

- Preserve ADR-0039’s live DAV/OAuth proof prerequisite before browsing; map legacy #121 evidence to #5, with #11 extending parity coverage.
- Require a separate validated PIM-only grant before retaining sources during mail removal, and clear the removed mail credential.
- Verification: checked the proposal against ADR-0039 and PRIVACY.md; documentation-only change, no runtime tests required. ADR-0072 remains Proposed.

- Additional PR #48 review: route reads/writes through explicit adapter boundary in the diagram; require validated narrower shared Google grants on PIM removal, with disclosed revoke/reconnect fallback. State DAV privilege-narrowing limits. Checked scenario consistency and diff whitespace; documentation-only.

- Final removal clarification for PR #48: separately delete source-owned unsent editor drafts and staged attachments after warning and confirmation; allow cancellation. Include this lifecycle in removal tests. Documentation-only, checked against the separate-draft invariant.

## 2026-09-20 — Codex — #49 / #51 native UI polish

- Followed the requested merge and polish pass. PR #50 merged; PR #48 review
  follow-ups preserve live DAV proof and safe removal of combined Google grants.
- Diagnosed the sample reader freeze as repeated command environment closure
  invalidation. Added stable routing identity with latest-owner dispatch and a
  hosting-controller regression; verified rendered body and Reply on simulator.
- Proved compose flow overflow with a failing width test, bounded measurement
  and placement, added accessibility form scrolling and standard/AX5 snapshots.
- Reduced duplicate desktop compose tools and labelled Send; inspected native
  test-app compose, mailbox and settings. No message sent or daily app replaced.
- Verification: iOS 9 tests/3 suites; macOS 6 tests/3 suites; native builds,
  lint, zero-change format, baseline inventory and diff check. All 12 simulator
  text sizes expose Close/Send/More. QA evidence and limits are in
  docs/qa/native-polish-2026-09-20/README.md.
- Initial broad macOS run had an unrelated profile-manager snapshot mismatch;
  no unrelated baseline changed. Physical VoiceOver, another runtime/device and
  live-provider coverage remain pending. No new release or version change.
- Documentation sweep: updated CHANGELOG, QA evidence and WORKLOG. No public
  architecture, provider, privacy, setup or workflow change; README, PRIVACY,
  ADRs and AGENTS need no change for this implementation. Hand off in review.

- PR #52 follow-up: native plain-renderer QA exposed joined paragraphs while HTML
  import was pending. Added a failing fallback regression and preserved the
  supplied plain alternative; native screenshot now retains paragraph spacing.
  Restored busy-state disabling on the accessibility toolbar and registered the
  new desktop snapshot explicitly in CI. Configuration selection needs no TDD;
  the one-line disable restores the existing header invariant without a new
  async-send fixture. Focused body, compose policy and snapshot checks rerun.

- Final handoff: PR #48 merged as a72e652e; all six review findings resolved.
  The final documentation-only head passed local lint/diff checks; hosted rebuild
  remained queued, with the unchanged runtime tree already green at e316db69.
  PR #50 is merged as 98e517aa. Integrated main into PR #52, preserving both
  append-only worklog entries. Final iOS command exits successfully with 37
  tests/5 suites after disabling stalled diagnostic collection; macOS follow-up
  exits successfully with 29 tests/3 suites. #49/#51 remain In review.


## 2026-09-20 — Codex — PR #52 sidebar polish

- Used Henrik's Brev/Apple Mail comparison to reduce desktop sidebar hierarchy
  noise: account sections have compact labels and trailing disclosure, folders
  no longer inherit an extra account indent, All Inboxes aligns with folder icons,
  labels use regular body type, counts are tertiary, and selection uses one fill.
  Quieted the desktop profile control while preserving theme tokens and iOS UI.
- Continued feature/native-ui-polish / PR #52 targeting main; checkout was clean.
- Visual regression loop: old macOS sidebar suite passed, intentional styling
  produced 11 reference failures, inspected light/dark/hierarchy renders, refreshed
  only those references and passed 39 sidebar tests across two suites. All 11
  existing phone snapshot cases (7 tests) passed without baseline changes.
- Native dated Brev Test build passed. Inspected both accounts, collapse/expand,
  nested rows and selecting the second account Inbox. No live mail changes.
- Lint, format and diff check passed. Updated CHANGELOG and QA documentation;
  no provider, privacy, public design-token, setup or architectural change, so
  README/PRIVACY/ADRs/AGENTS need no update. Physical VoiceOver remains unverified.


## 2026-09-20 — Codex — PR #52 sidebar top alignment

- Aligned profile, All Inboxes and Smart Views text/icon columns on desktop.
  Replaced the native borderless menu label with a plain menu button so SwiftUI
  respects its layout; moved the profile chevron to the trailing edge. Removed
  the extra profile gap and put Smart Views disclosure in the icon column.
- Inspected intentional snapshot failures and refined the rendered alignment;
  refreshed only the 11 sidebar references. Native profile menu opens with All
  Mailboxes and Manage Profiles. Decorative symbols are hidden from accessibility.
- Verification: macOS sidebar snapshots and unchanged phone snapshots rerun;
  dated test-app build, lint/format and diff check. No new provider, privacy,
  architecture or settings behavior; only CHANGELOG, QA and WORKLOG need updates.


## 2026-09-20 — Codex — PR #52 sidebar scope hierarchy

- Continued clean feature/native-ui-polish / open PR #52 to main after approval
  of the scope/destination proposal. Moved desktop scope selection into a fixed
  Mailboxes header, preserving custom profile names and management access.
  All Inboxes stays first; Smart Views consolidates create/manage in one menu.
- Visual regression loop: 11 expected old-reference failures, inspected renders,
  fixed safe-area header overlap using a separate stack header, then refreshed
  references. Four desktop tests/11 cases and seven iOS tests/11 unchanged cases
  pass. Native dated mock build passes; scope menu, Smart Views expansion,
  management sheet and unified inbox checked. Lint/format/diff check pass.
- No business-logic change; used rendered visual regression and native action
  checks rather than a new unit test. Initial test command from workspace root
  had no BrevMail scheme; reran successfully from packages/BrevMail.
- Updated CHANGELOG and QA evidence. README, privacy, ADRs and AGENTS need no
  change: no setup, architecture, network or workflow changes. Physical spoken
  VoiceOver and live-provider QA not run. No merge/release/version change.

## 2026-09-20 — Codex / Sol — #53 / PR #52 full native audit follow-up

- Started from clean feature/native-ui-polish at 1a3c6b9b, continuing open PR
  #52 to main. Created #53 for all nine approved audit findings and moved its
  project card to In progress. Four Sol agents own isolated sidebar, mail-shell,
  reader/contrast and compose slices; integration owns settings and QA.
- Removed duplicate fetch guidance and isolated the accounts pixel selection.
  Two accounts references were inspected/refreshed; four tests in two suites
  pass. The broad settings snapshot selection had fourteen pre-existing
  mismatches on macOS 27; unrelated references were preserved.
- Original iPhone snapshots pass (seven tests / eleven cases). Strengthened
  shared fixtures with explicit text-size traits, navigation hosting and a
  two-account/long-name/nested sidebar case. Integrated all four Sol slices and
  reviewed follow-ups restoring custom profile names, true folder nesting,
  active mailbox qualifiers, native menu semantics and narrow row metadata.
- All nine audit findings are implemented: sidebar hierarchy/alignment,
  desktop initial columns and narrow rows, Dynamic Type/contrast, primary
  toolbars, iPhone account/status context, compact reader metadata, compose
  hierarchy and single fetch guidance. Final render review also fixed a clipped
  local-folder creation footer and removed the duplicate iPhone thread menu.
- Behavioral red/green evidence comes from the slice policy/body/contrast tests;
  cosmetic changes use failed prior-reference comparisons, visual inspection,
  then updated pixel baselines. No mirror unit tests were added for spacing.
  Corrected cropped/time-dependent fixtures and a 50 ms async test assumption
  exposed by the old hosted CI failure. Unrelated snapshot debt is unchanged.
- Final checks: BrevMail behavior 1,606 tests/247 suites; Mac mail pixel selection
  37 tests/12 suites; iOS selection 18 tests/5 suites (13 phone renders); themes
  9 tests; focused settings 4 tests/2 suites. Lint, zero-change format, baseline
  inventory and diff check pass. Dated Mac mock build/startup verification and
  iOS build/explicit mock launch pass. Native sidebar, reader, menus and compose
  inspected on both platforms; no mail sent.
- Fresh 1440 pt native root probe resolves sidebar/list to 240/420 pt without
  clearing saved window state. Existing-window divider retention remains an
  inference; the observed initial split and constraints are recorded in QA.
- Documentation sweep: CHANGELOG, QA evidence/baseline policy and WORKLOG
  updated; ADR-0002 documents the protected theme contrast change. README,
  PRIVACY, ADR-0006 and AGENTS need no updates: setup, network behavior, privacy
  and repository workflow are unchanged. Physical spoken VoiceOver, live
  providers, unrelated Settings snapshots and maintainer acceptance remain open.
- QA scope, commands and limitations are tracked in
  docs/qa/native-audit-polish-2026-09-20.md. No live mail, daily-driver replacement,
  version change, merge or release operation was performed.
- Published the integrated changes in existing PR #52 and moved #53 to
  In review; #49/#51 remain open/In review. Resolved the obsolete compose-menu
  review thread after checking the updated overflow policy, tests and native
  accessibility menu role. Hosted CI then found a stale compact-layout source
  check requiring the removed content frame. Reproduced that failure, checked
  the policy and outer split modifier instead, and passed the focused check and
  complete `scripts/test.sh --self-tests-only` set. No production code changed
  for this CI correction; hosted checks must rerun on the follow-up head.

## 2026-09-20 — Codex — #5 slice 2 settings source surface

- Built on feature/pim-source-lifecycle (PR #56, stacked on the ADR-0072
  acceptance PR #55). Moved issue #5 to In progress on the board and posted
  the slice plan as an issue comment.
- Settings Sources UI (BrevSettings): PIMSourceSettingsModel view-model
  wrapping PIMSourceCoordinator; PIMDAVConnectForm pure validation
  (discovery email, manual HTTPS endpoint with loopback exception,
  app-password + bearer modes); PIMSourcesSettingsView group with
  per-source shared status, sync opt-in toggle, disconnect, credential
  reconnect sheet, and removal confirmation offering keep-cache vs
  delete-cache (unsent drafts always die, provider data never touched).
  Google enablement listed as "Not available yet" until reauthorization.
- CalendarContactsSection copy replaced per ADR-0072: direction summary
  now describes optional Google/DAV sources; DAV connect joined
  "Available now"; Google enablement, browsing, unified search and
  event/contact authoring are "Not available yet" (accepted scope).
  The ADR-0039 "full PIM editing outside Brev" boundary text removed.
- Wiring: AppSession.pimSourceCoordinator built by AppSessionFactory
  (JSON store + per-source data dirs under Application Support/Brev,
  Keychain credentials); SettingsView passes it to the section; both app
  targets updated.
- Verification: 27 new/updated tests in 4 suites pass (form validation,
  model lifecycle incl. reconnect failure preserving state, row
  presentation action matrix, scope presentation contract). BrevMail
  package builds clean. swiftformat + swiftlint --strict clean on all
  touched files.
- Skipped: pixel snapshot for the new group — local macOS 27 renderer
  does not match the macOS-26-recorded baseline (32 pre-existing
  mismatches in the suite confirm); behavior coverage added instead.
  iOS/macOS app builds left to CI (tuist graph unchanged, one added
  SettingsView argument).
- Next: slice 3 Google feature-triggered reauthorization plus
  mail-account-removal handling of linked sources (acceptance criteria);
  live-provider smoke remains the maintainer gate.

## 2026-09-21 — Agent — Issue #8 slice 1 (contact sync engine + cache)

- Goal: give connected contacts sources a real sync pass per ADR-0072 —
  initial + incremental sync, per-scope failure isolation, durable
  cache, cursors wiped on removal.
- Changes: PIMContact/PIMContactField/PIMContactAddress model with
  adapter-owned rawPayload; JSONPIMContactStore (per-source file under
  the cache dir) and JSONPIMContactSyncCursorStore (under the wiped
  cursor dir, scope = collection for CardDAV / source for Google);
  GooglePeopleContactSync (connections.list paging, syncToken-only
  incremental, 410/400-expired → full resync); PIMDAVContactSync
  (sync-collection with multiget fill-in, addressbook-query + ETag-diff
  fallback); PIMVCardParser covering FN/N/NICKNAME/EMAIL/TEL/ADR/ORG/
  TITLE/NOTE/CATEGORIES/REV/UID and HTTPS-only PHOTO URIs;
  PIMContactSyncService (serial, user-initiated, per-scope failure
  isolation, local-only searchContacts).
- Settings: Sync Now menu item + cached contact count on contacts
  source rows; enabling sync runs one immediate pass in the gesture.
- Wiring: AppSession.pimContactSyncService via AppSessionFactory; both
  app targets pass it to SettingsView.
- Verification: 16 new tests pass (CardDAV incremental/multiget/
  fallback, Google full/incremental/410, hidden-skip, failure
  isolation, auth stop, kind guard, local search, vCard edge cases).
  BrevCalendar, BrevSettings, BrevMail packages build clean.
- Skipped: app builds left to CI (no local signing cert); pixel
  snapshots unchanged. Local BrevSettings snapshot mismatches are
  pre-existing macOS-27 renderer drift.
- Next: #8 slice 2 browsing UI (list/detail/group filter) and
  compose-autocomplete migration; live-provider evidence stays the
## 2026-09-21 — Agent — Issue #6 slice 2 (event sync engine + cache)

- Goal: give connected calendar sources a real sync pass per ADR-0072 —
  initial + incremental sync, per-collection failure isolation, durable
  cache, cursors wiped on removal.
- Changes: PIMEvent/PIMEventStatus/PIMEventPerson/PIMEventReminder model
  with adapter-owned rawPayload; JSONPIMEventStore (per-collection files
  under the source cache dir) and JSONPIMSyncCursorStore (under the
  wiped-on-removal cursor dir); GoogleCalendarEventSync (events.list
  paging, syncToken-only incremental, 410 → full resync); PIMDAVEventSync
  (RFC 6578 sync-collection with multiget fill-in, bounded
  calendar-query + ETag-diff fallback); PIMEventSyncService (serial,
  user-initiated, per-collection failure isolation, cursor committed
  after the generation). ICSParser gained parseEvents (all VEVENTs),
  STATUS/PARTSTAT/VALARM/CONFERENCE/LAST-MODIFIED/TZID capture, Codable
  RecurrenceRule and public parseRecurrenceRule.
- Settings: Sync Now menu item + cached event count on calendar source
  rows; enabling sync runs one immediate pass in the same gesture.
- Wiring: AppSession.pimEventSyncService via AppSessionFactory; both app
  targets pass it to SettingsView.
- Verification: 23 new tests pass (DAV incremental/multiget/fallback/501
  degrade, Google full/incremental/410, hidden-skip, failure isolation,
  auth stop, kind/status guards, ICS field parsing). BrevCalendar,
  BrevSettings, BrevMail packages build clean.
- Skipped: app builds left to CI (no local signing cert); pixel snapshots
  unchanged — the new row content rides existing snapshot coverage.
  Local BrevSettings snapshot mismatches are pre-existing macOS-27
  renderer drift (identical failures on clean main).
- Next: #6 slice 3 browsing UI (agenda/day/week/month + detail), then
  search/offline-stale states; live-provider evidence stays the
  maintainer gate.

## 2026-09-22 — Agent — Issue #12 slice 3 (tasks browsing UI + Create Task)

- Goal: ship the Tasks surface and wire Create Task from Message into
  provider task lists per ADR-0072 — closing the loop on the slice-1/2
  sync and write pipelines.
- Changes: TasksBrowsingModel (cache-only load, collection-grouped
  sections, hidden/search/list filters, completed toggle, staleness,
  brev://task deep links); TasksEditingModel + TaskDraft over the
  TaskWriting seam (PIMTaskWriteService); TasksRootView/TasksListView/
  TaskDetailView/TaskEditorView mirroring the contacts surface;
  MessageTaskTarget replacing the Reminders-or-share enum with provider
  task lists via PIMTaskMessageCreator; macOS Tasks window (Window menu
  + sidebar footer) and iOS full-screen cover; PIMDeepLink .task case.
- Fixes during verification: TasksEditingModel guard failures now set
  lastError (contacts-editor parity) instead of throwing silently.
- Verification: 24 new Swift Testing cases green
  (TasksBrowsingModelTests, TasksEditingModelTests) plus the updated
  MessageTaskPayloadTests; lint.sh and format.sh clean.
- Skipped: rendered verification of the Tasks window (no signing cert
  locally); pixel snapshots unchanged — the surface rides existing
  coverage. Live-provider write smoke tests remain the maintainer gate.
- Next: #12 stays In progress pending maintainer QA; remaining issue
  scope is rendered/live verification, not code.

## 2026-09-22 — Agent — Issue #9 slice 3 (photos, dates/URLs, duplicate suggestions)

- Goal: close the three remaining contact gaps on the merged write
  pipeline + editor (PR #68) — photo set/replace/remove, date and URL
  fields, and review-first duplicate suggestions.
- Changes: `PIMContact` gains `photoData`, `dates`, `urls`; vCard
  writer/parser manage BDAY/ANNIVERSARY/X-ABDATE/URL/PHOTO
  version-aware and preserve unknown fields; Google People writer adds
  `:updateContactPhoto`/`:deleteContactPhoto` (bytes never in
  updatePersonFields) and birthdays/events/urls field mappings; sync
  parses the same fields so masks never erase unseen provider values;
  write service diffs stored-vs-draft photo state; editor gains photo
  (PhotosPicker), URLs, Dates sections; detail pane shows photo/URLs/
  dates plus a Possible Duplicates section fed by the pure
  `ContactDuplicateSuggestions` scorer (Review selects only — never
  merges); ADR-0006 gains CardDAV/Google contact-write rows, PRIVACY.md
  documents photo uploads, ADR-0072 records the slice.
- Verification: 26 PIMContactWrite + 19 PIMContactSync cases green
  (photo set/replace/remove round-trip on both writers, date+URL
  round-trip, unknown-field preservation with photos); 49 affected
  BrevMail cases green (draft mapping, duplicate ranking + no-mutation,
  editor/detail snapshots re-recorded); lint.sh and format.sh clean.
- Fixes during verification: parser `=\n` quoted-printable unfold
  swallowed the property after a base64 payload's `=` padding — now
  joins only when the next line is not itself a property; merge now
  unfolds raw vCards so folded PHOTO payloads leave no orphan lines;
  duplicate name matching compares display and split name forms so
  cross-form twins still match; AppSessionFactory now shares each
  `JSONPIM*Store` across sync/write services — the write service's
  private store instance left list/detail stale until relaunch
  (found by E2E on a stub CardDAV server; affected events/tasks too).
- Skipped: live-provider evidence (Google Workspace + writable CardDAV
  photo/date round-trips) — maintainer-gated per the issue; rendered
  verification of the PhotosPicker sheet itself.
- Next: maintainer QA on issue #9; remaining issue scope is live
  evidence and duplicate merge actions (out of "review-first" scope).

## 2026-09-23 — Agent — Sent-copy markup rendering fix (release-validation nit)

- Goal: fix the reader showing literal `<br>`/`&lt;` markup on sent-copy
  bodies flagged in `docs/qa/release-validation-2026-09-22.md`.
- Root cause: two layers. `MockBackend` stored `draft.htmlBody` as the
  sent/draft copy's `plainText` with `html` unset, so plain-text surfaces
  (reader body, list snippet, reply quotes) rendered raw markup. And the
  real `MIMEMessageBuilder` built the `text/plain` alternative via a naive
  tag-strip that never unescaped entities and concatenated paragraphs —
  `&lt;` leaked into real outbound plain parts too.
- Changes: `HTMLTextStripper` gains `plainText(from:)` — block/`<br>`/`<hr>`
  boundaries become newlines, remaining tags spaces, entities unescaped,
  per-line whitespace collapsed. `MockBackend` sent/draft copies now mirror
  real mail: `html` = draft markup, `plainText` = stripped rendering,
  snippets stripped. `MIMEMessageBuilder` delegates its `text/plain` part
  to the same helper.
- Verification: 5 new/targeted cases green (sent-copy split + readable
  plain alternative), full MockBackend/MIMEMessageBuilder/IMAP parser/
  outbound suites 123/123, BrevMail compose/quote/detail suites 67/67,
  lint.sh + format.sh clean.
- Skipped: E2E render pass in the app (plain-text fix is unit-covered;
  reader path unchanged — it was fed bad data).
- Next: PR for review; parity-matrix stub-DAV rows continue separately.

## 2026-09-23 — Agent — Issue #11 stub-DAV parity rows (C/D mac)

- Goal: fill the CalDAV (C) and CardDAV (D) macOS cells of
  `docs/qa/pim-parity-matrix.md` that a localhost stub can honestly
  cover, ahead of maintainer live fixtures.
- Changes: `scripts/stub-dav-server.py` — a single-file Python stub
  speaking enough RFC 4791/6352/6578 for real flows: PROPFIND discovery
  (principal → home set → collections), sync-collection REPORT with
  sync-token expiry control, query/multiget REPORTs, GET, conditional
  PUT (If-None-Match/If-Match → 201/204/412), DELETE, optional Basic
  auth. Matrix filled for §1.6/1.7, §2.1/2.3/2.4/2.5⚠/2.9/2.10,
  §3.1/3.4/3.5/3.7/3.8, §4.1*/4.2/4.5/4.6⚠, §6.1 with wire-log line
  refs; wire logs + two evidence screenshots committed under
  `docs/qa/pim-parity-stub-dav-2026-09-23/`.
- Verification: stub smoke-tested with curl (207/401/412/201/204 paths,
  sync-token expiry); all UI cells driven end-to-end in the mock build
  via the real "Add DAV Source…" connect sheet.
- Found during verification (real defect): sync refreshes a cached
  item's etag but never its href — a server-side rename leaves the
  record pointing at a dead path and every subsequent write 412s with
  no self-heal (wire log L22/L27/L31). Also `lastError` callouts are
  never cleared on fresh editor opens (cosmetic).
- Skipped: iOS cells, Google fixture (none exists), §2.6–2.8
  recurrence/invite/RSVP and §3.6 groups (stub lacks multi-collection
  scheduling surface), §1.8 TLS failure (stub is plain http loopback).
- Next: maintainer live fixtures; stale-href defect proposed as a
  follow-up fix.

## 2026-09-23 — Agent — DAV stale-href write defect (found via #11 stub pass)

- Goal: fix the defect the stub-DAV parity pass surfaced — a synced
  event whose resource lives at a non-`{uid}.ics` href (server-side
  rename, or a server that never followed the RFC 4791 filename
  convention) stayed permanently unwritable; every PUT went to a dead
  path and 412'd as `conflict` with no self-heal.
- Changes: `PIMDAVEventWriter.update`/`delete` now address the stored
  `providerItemKey` href (new `hrefURL(for:)`), matching the contact
  and task writers; `create` keeps the `{sanitized-uid}.ics`
  convention. Sync merges in `PIMEventSyncService`,
  `PIMContactSyncService`, and `PIMTaskSyncService` drop a cached
  record when an incoming item shares its UID (and recurrence-id for
  exceptions) under a different href — new `PIMSyncItemIdentity`
  type — so a rename without a tombstone self-heals instead of
  shadowing the live record.
- Verification: `swift test` BrevCalendar 241/241 — new
  `davUpdateTargetsStoredHref` (writer targets stored href for both
  update and delete) and `davSyncSupersedesStaleHref` (delta sync
  drops the stale record, keeps the live one + untouched items);
  existing DAV update/delete/conflict tests updated to pass real hrefs
  and assert request URLs.
- Skipped: iOS E2E (writer fix is transport-level; sync merge is
  platform-independent). `CalDAVEventWriter` (invite-acceptance
  single-target flow) intentionally unchanged — it only creates.
- Next: merge; matrix §2.5 can flip to clean ✓ on the next pass.

## 2026-09-24 — Agent — Round-2 verification fixes (PR #93 findings)

- Goal: fix the six findings the recorded round-2 verification pass
  reported on `a367be9` plus the N1 keyboard-nav remainder.
- Changes:
  - Calendar toolbar vanish (release-affecting): `.toolbar` items on
    the NavigationSplitView sidebar column only propagate to the macOS
    window titlebar when the column content is a `List` — the
    grid-mode views (`ScrollView`) silently dropped the layout picker,
    date navigation, New Event, and Sync. Replaced with a deterministic
    in-view `navigationHeader` (menu-style picker + date nav + actions)
    that renders identically in every mode on both platforms.
  - Compose Discard Draft: the `discardDraft` action existed in
    presentation + a11y strings but no menu rendered it — closing a
    compose window still silently saved. Wired a destructive
    `Discard Draft` item (trash icon) into the macOS overflow and iOS
    compact menus; `discardDraft()` cancels autosave, calls
    `backend.discard(draftID:)`/`(draftID:sourceID:)`, and closes
    without saving.
  - P5 HTML sent copies: `ComposeHTMLBodyPolicy.html(fromEditorText:)`
    escaped `>` quote markers to `&gt;` so sent copies showed literal
    `> ` lines. Consecutive `>`-prefixed runs now emit a real
    `<blockquote>` (already styled by the reader's blockquote CSS and
    every recipient client); `editorText(fromStoredHTML:)` round-trips
    blockquotes back to `>` lines so draft reopen keeps the quote.
  - P11 Find settings: validation warnings were silent no-ops —
    `statusAndGuidanceSection` only mounts after
    `didStartDiscoveryProbe`, but the validation early-return happened
    before the flag was set. Flag now marks before validation in both
    `discover` and `applySkip`.
  - N6 iOS reader overflow: the thread `…` menu held only thread
    controls — Reply/Reply All/Forward/Snooze were long-press only.
    iOS menu now leads with the consolidated per-card inventory acting
    on the thread's latest message.
  - N1 remainder: `focusSection()` puts sidebar + message list in the
    macOS Tab key loop, and arrow-key input now claims container focus
    so the accent focus ring actually appears.
- Verification: `swift build` clean; `swift test` filtered suites
  99/99 (ComposeDraftBuilder +2 round-trip tests, ComposePresentation,
  IMAPAccountSetup); `scripts/lint.sh` OK; swiftformat 0 changes.
  On-device verification pending on this commit.
- Skipped: P6 iOS stale calendar data — pending investigation
  (suspected environment artifact, not code).
- Next: merge into the stacked composer branch (PR #94); recorded
  re-verification of the six items.

## 2026-09-24 — Agent — Round-2 verification follow-ups (PR #93 re-verification findings)

**Goal:** Fix the two code-change findings from the `c2ae433` re-verification pass and one minor label wrap.

**Changes:**
- `MessageListView` — moved the macOS focus machinery (`focusSection`/`focusable`/`focused`/`focusEffectDisabled`/arrow+Return handlers/accent ring) off the `List` onto a wrapping `Group`: a `List`'s AppKit backing never joins the key loop, so the column could never be focused. `selectMessage` now also claims `listKeyboardFocus` so pointer interaction marks the list as the keyboard surface (Apple Mail ring-follows-focus).
- `MailNavigationState` — added `messageListFocusRequestID` token + `requestMessageListFocus()`; `MessageListView` observes it and claims focus.
- `FolderSidebar` — `.return` on a highlighted destination and `→` on a leaf call `onOpenMessages` (drill into the list, Finder column-view style); Outbox keeps its own activation on both.
- `BrevMailRootView` — `onOpenMessages` on macOS bumps `requestMessageListFocus()`, so any mailbox activation hands the keyboard to its list.
- `MockBackend.removeDraft` — discard now matches the draft's local id *and* its staged folder id (`draft-<id>`/remoteID), matching the local-id contract `IMAPSMTPBackend.discard` exposes. Fixes the iOS Discard leak where an auto-persisted reply draft survived because the composer's `draftID` (local UUID) never matched the `draft-<uuid>` folder key. New `discardByLocalIDRemovesSavedDraft` test covers it (and caught the first incomplete attempt at the fix).
- `CalendarRootView` — `.fixedSize()` on the layout Picker so "Month" stops wrapping to "Mont h" on iOS.
- `.agents/skills/testing-brev-ui/SKILL.md` — added sim PIM-source injection, focus-state AX caveat, and the ⌘W-keepalive/`reopen` note from the verification pass.

**Verification:** `swift test --filter discard` — 4/4 green incl. new test; `swift test` BrevMail 1869 tests, 84 issues all in `*SnapshotTests.swift` (pre-existing env baseline drift, zero functional failures); `swift build` macOS clean; `scripts/lint.sh` + `scripts/format.sh` clean.

**Skipped:** Device re-verification (testing agent) — pending.

**Handoff:** P11 (Add-account Find-settings) remains mock-limited — needs `imapAccountDiscoveryCoordinator` wired into the demo session or real-session verification.
- `AppSessionFactory` — demo session now gets an offline
  `imapAccountDiscoveryCoordinator` (built-in profile table + manual
  fallback only, no DNS/autoconfig) so the Find-settings flow — and
  the P11 validation status surface — is exercisable in mock mode
  without violating the zero-network default.

## 2026-09-25 — Agent — PR #93

**Goal:** Sidebar header consistency + alignment follow-up (Henrik's Apple Mail comparison screenshots).

**Changes:**
- `FolderSidebar` — unified all macOS section headers to one Apple Mail-style treatment: `caption` + `semibold` + `textSecondary`, flush-left at the disclosure column (`folderRowBaseLeadingPadding`), disclosure chevron trailing the label (10pt semibold, `textTertiary`) — matches Mail's "Favoritter / Smarte postkasser / Google" edge and the existing iOS text-then-chevron pattern.
- `profileSwitcher` (macOS): downgraded from `.body`/semibold/`textPrimary` title to the shared header style (was the inconsistent large header in the screenshot); now uses `sourceHeaderMinimumHeight` + `sourceHeaderVerticalPadding`.
- `mailboxDisclosureHeader` + `smartViewsSection` (macOS): reordered to label-then-chevron so header text sits flush-left at the chevron column instead of the icon column.
- Removed now-unused `sidebarHeaderLabelLeadingPadding`.

**Verification:** `scripts/lint.sh` + `scripts/format.sh` clean; rebuilt `Brev Test (2026-09-24).app` in mock mode and visually verified on device — "Mailboxes", "Smart Views", and both source headers share one flush-left muted header style; folder chevrons, icons, labels, and counts all sit on shared columns.

**Skipped:** iOS — branches untouched (headers already used label-then-chevron); snapshot baselines have pre-existing env drift.

## 2026-09-25 — Agent — Platform parity + performance smoke pass

- **Goal**: Post-merge iOS/macOS parity assessment + performance benchmark vs
  #304 budgets (user request).
- **Changes**: `docs/qa/platform-parity-2026-09-25.md` (parity matrix),
  `docs/qa/results/performance-mock-2026-09-25.json` (budget JSON),
  `performance-baseline-2026-09.md` Live-measurements section,
  `scripts/collect-performance-trace.sh` `--info` fix (export was silently
  empty — Performance events log at info level).
- **Verification**: both apps driven on identical mock fixtures; trace
  collected via fixed collector on macOS and `simctl spawn log show` on iOS;
  budget gate run and violations recorded in the doc.
- **Findings**: first rich-HTML thread open 1222 ms (over 600 ms hard limit,
  n=1, WKWebView first paint — needs warm live re-measure);
  `cached_inbox_query_ms` not measurable in mock; all other budgets pass or
  pass-by-proxy; parity confirmed on all user-visible surfaces.
- **Skipped**: true scroll frame p95 and the full #28 §5 live run — needs
  Instruments + a real mailbox.

## 2026-09-25 — Agent — Message-open renderer pre-warm (perf P1)

- **Goal**: close the `ui.body.visible` over-budget gap measured in the
  mock performance smoke pass (1222 ms first rich-HTML open vs the
  600 ms `cached_thread_open_ms` budget).
- **Changes**: `HTMLBodyWebViewStore` gains a shared hidden warm store
  (`prewarmSharedRenderer()`) that spins the shared WebKit process pool
  and pre-compiles the `WKContentRuleList` remote-content blocker off the
  open path; `prewarm()` now also kicks the blocker compile. The mail
  root invokes it in the existing background-phase startup task, gated
  on the `body.useRichRenderer` preference (plain-text users never mount
  a web view). New test asserts the warm-up is idempotent.
- **Verification**: `swift test --filter HTMLBodyDocument` 21/21 pass;
  lint + format clean. Rebuilt the mock app and re-measured
  `ui.body.visible` end-to-end: 242 ms first open / 164 ms second open,
  vs 1222 ms before (budget 600 ms). The detail view's own store is
  pre-warmed at mount as well, so the warm path survives per-store
  mounts, not only the shared process pool.
- **Skipped**: live-mailbox warm re-measure — needs a real account (#11).

## 2026-09-25 — Agent — Focused-pane selection tint (a11y follow-up)

- **Goal**: restore a visible keyboard-focus indicator after #95 removed the
  column outline, without reintroducing a drawn ring (Codex P1 on #95:
  keyboard-only users had no focus signal at all).
- **Changes**: `BrevSelectionPalette` `isActive: false` now demotes the
  selected-row fill from `selection` to `bgSecondary` (the Apple Mail
  focused-pane-owns-the-tint cue, documented in ADR-0002); `MessageListRow`
  gained `isFocusedPane` fed by `listKeyboardFocus`; the sidebar palette is
  keyed on `sidebarKeyboardFocus`; the sidebar claims focus on appear so an
  empty launch still lands arrows on the mailbox column (Mail cold-start).
- **Verified**: lint + format clean; live app — click list → list accent
  tint + sidebar muted; arrows move the focused pane's selection; mailbox
  activation hands focus to the list; no outline anywhere.
- **Skipped**: none. The 22 pre-existing snapshot env diffs reproduce
  identically on clean main on this machine — no new failures.

## 2026-09-25 — Agent — Settings sidebar flush-left + shared icons toggle (#100)

- **Goal**: Henrik asked for the mail-sidebar treatment in Settings too —
  rows aligned left under their section headers ("App", "Reading &
  Composing", "Organization") and honoring the same icons on/off toggle,
  on iOS and macOS.
- **Changes**: `SettingsView` — macOS sidebar rows `listRowInsets` leading
  4 → 0 so row content aligns under section headers; `sectionRow` and
  `pluginSettingsRow` gate their 18pt icon column on the same
  `folders.showIcons` pref (`@AppStorage`) the mail rail uses, so the
  Mailbox View → Folders → "Sidebar icons" switch compacts every rail at
  once. iOS compact + sidebar rows pick both up automatically.
- **Verified**: lint + format clean; `swift build` green; live app —
  toggle ON restores icons in settings + mail sidebars (icon column sits
  under section headers, Apple Mail layout), toggle OFF renders the dense
  text-only rail in both; A/B test run confirms the 34 BrevSettings
  snapshot diffs fail identically on clean HEAD (pre-existing macOS
  baseline env diffs — zero new failures from this change).
- **Skipped**: none.

## 2026-09-25 — Agent — iOS settings tap fix (found while verifying #100)

- **Goal**: while verifying the settings icons toggle on iOS, every
  settings row tap was dead — the whole section list was un-navigable.
- **Root cause**: `compactSettingsRows` wrapped each `NavigationLink` in a
  `.simultaneousGesture(TapGesture().onEnded { navigation.select(...) })`.
  The competing gesture suppressed link activation — confirmed via A/B
  build (dead on the parent commit too, so pre-existing, not from the
  icons-off change).
- **Fix**: drop the gesture; call `navigation.select(section)` in the
  pushed view's `.onAppear` instead — same sync timing, no conflict.
- **Verified on device**: Mailbox View, Accounts, etc. now navigate; the
  Folders scope picker, toggles, and the "Sidebar icons" pref all live and
  govern the iOS rail + settings icons identically to macOS.

## 2026-09-26 — Agent — Sidebar flush-left refinement (PR #100)

**Goal:** Henrik: move mailbox folder rows further left — icons under the mailbox headers, Apple Mail gutter.

**Changes:** `FolderSidebarPresentation.macOSLayoutMetrics` `disclosureHitSize` 16→10 (Mail's leading gutter ≈ 7–10pt); macOS `folderRowControlSpacing` → 0 (the disclosure column carries the visual gap); `sidebarActionRow` leading now derives from the same column (`disclosureHitSize + folderRowControlSpacing`) instead of a hardcoded `xxs`; iOS `.folderContent` action rows drop the stale +44pt leading disclosure offset (`folderRowLeadingPadding(0)`, matching iOS folder rows — iOS disclosure is trailing). `⋯` smart-view menu target pinned at `BrevSpacing.lg` so the metric change does not shrink it.

**Verified:** rebuilt `Brev Test (2026-09-26)` — icons ~10pt right of header text, leaf/parent icons on one column, chevrons at the header edge; `swift test --filter 'FolderSidebarPresentation|MailboxGroupDisclosure|GmailNativeSidebar'` 42/42; lint.sh + format.sh clean.

**Skipped:** pixel snapshot baselines (same env-diff caveat as before).

## 2026-09-26 — Agent — Sidebar icons flush-left + View-menu icons toggle (PR #100)

- Goal: Henrik asked for mailbox folder icons "all the way to the left" and an easy way to turn icons off.
- macOS leaf rows no longer reserve a disclosure column; leaf icons (and All Inboxes / smart views / plugin rows) sit flush with the section-header text. Parent rows keep the chevron in that edge slot. Child depth indent is now 16pt so child icons start right of the parent icon.
- Removed the now-identical `SidebarActionRowAlignment` distinction and the dead disclosure placeholder.
- Added View → "Show Sidebar Icons" toggle bound to `folders.showIcons` (same preference as Settings → Mailbox View → Folders → Sidebar icons).
- Verification: lint.sh OK, format clean, FolderSidebar/MailCommand/Shortcut unit tests green, rebuilt mock app and checked the result visually. FolderSidebar pixel snapshots differ, as expected from the geometry change (they were already env-divergent on this machine). Re-record the baselines on the maintainer host.

## 2026-09-26 — Agent — Sidebar, DAV form, and compact rows (PR #100)

- **Goal:** Deliver the three Apple Mail-inspired UI polish changes requested
  for PR #100: shared sidebar folder glyph alignment, a native DAV source
  connection form, and a compact message-list leading gutter.
- **Changes:** Sidebar disclosure controls now trail folder content on macOS
  and iOS; macOS uses a 16pt disclosure hit target and matching 16pt folder
  depth indent. `PIMSourceConnectSheet` now uses a native grouped Form on
  macOS (default Form presentation on iOS), native picker/text-field chrome,
  localized section labels and footers, and validation callouts after input
  or attempted submission. `MessageListRow` now uses compact spacing and
  checkbox/unread-dot/avatar/content order; inline child rows already matched
  that order. Updated only the affected sidebar and message-row snapshot
  baselines through `RECORD_SNAPSHOTS=YES`.
- **Verified:** `swift test --filter FolderSidebar` passed (42 tests);
  `swift test --filter MessageListRow` passed (14 tests); BrevSettings PIM
  tests passed (35 tests in 3 suites); `scripts/lint.sh` passed; the macOS
  mock build passed and launched `Brev Test (2026-09-26).app`.
- **Skipped:** The requested iOS build could not resolve a destination:
  `xcodebuild` reported `iOS 26.5 is not installed` while the available
  simulator runtimes were iOS 26.5 and 27.0. The existing iOS simulator app
  was nevertheless relaunched successfully with mock mode. No visual
  inspection was performed.
- **Handoff:** The selected validation visibility variant is
  `didAttemptSubmit || hasAnyInput`, because `canSubmit` is validity-gated
  and pristine forms should not show warnings. PR checks were inspected
  separately and were green at the time of inspection.

## 2026-09-29 — Agent — Runner startup diagnostics

- Goal: distinguish nightly runner-pool failures from release-environment startup failures.
- Added three independent manual startup probes for macos-15 without an environment, macos-15 with release, and macos-26 with release. No checkout, secret references, signing, or publishing; token permissions are empty. Added a QA runbook including annotation retrieval when logs do not exist.
- Verification: actionlint, git diff --check, and scripts/lint.sh passed; scripts/format.sh changed 0 of 1,194 files. Hosted probes require the workflow on main and remain pending maintainer merge approval.
- TDD omitted for diagnostic workflow configuration; validate YAML/actions and embedded shell instead. No app builds or snapshots needed because application behavior is unchanged. README, privacy, and ADR changes are unnecessary; this uses existing hosted CI and changes no product or release policy.

## 2026-09-29 — Agent — Google configuration and issue #14

- Goal: provision the existing Google integrations and make Drive Picker configuration reach local and archived app bundles. Branch `feature/google-drive-build-config` starts at `03c818c1`; integration target is `main`.
- Enabled Calendar, People, Tasks, Drive, and Picker APIs in the existing OAuth project. Saved the seven existing feature scopes in Data Access, preserving mail scopes. Created a Picker key restricted to Drive/Picker APIs and the Google Drive/Docs website origins. Stored values only in ignored, mode-600 local settings and GitHub's `release` environment secrets.
- Fixed missing bundle entries on both platforms, local dotenv/build injection, and nightly/release archive inputs. API-key injection uses a protected temporary xcconfig, including an explicit empty value to clear stale generated settings. Added setup/QA guidance and focused regression checks.
- Verified: regression reproduced missing Info.plist entry before the fix; environment and release-configuration scripts passed afterward. Lint, format (0 files changed), actionlint, shell syntax, and diff checks passed. Built and launched `Brev Test (2026-09-29).app` in mock mode; bundle Picker key, project number, and macOS OAuth client match local settings without exposing values. Picker key absent from build log. Daily-driver app untouched.
- Remaining: no authenticated Drive/PIM CRUD smoke or iOS build was run in this pass. Google data-access verification, native Picker referrer compatibility, failure/cleanup scenarios, and maintainer QA acceptance remain separate gates. Devin secrets remain unchanged pending the user's answer. Issues #3/#11/#14 stay open; issue #14 returns to In review with this PR.
- Documentation sweep: README, CHANGELOG, QA runbook, and this log updated. No privacy, ADR, or agent-policy change: this wires already documented, opt-in integrations without adding endpoints, scopes in code, or architecture.

## 2026-09-29 — Agent — Native UI/UX audit fixes

- Goal: address the six native audit findings and the requested compact mobile folder list. Worktree `c798/brev`, branch `feature/uiux-audit-fixes`, integration target `main`, starting at `6399f36f`; no existing PR or matching open issue at start.
- Changed: adaptive iPhone parent/reply typography and readable conversation identity; WKWebView width tracking after its initial layout; invalid-recipient send gating with visible correction; compact search scope/filter menus and unverified-coverage recovery; Norwegian app-owned labels and consistent elapsed ages. Removed outer mobile folder-row padding/gaps while keeping 44-point controls. The original Favorites suggestion was subsequently implemented below.
- Regression caught during native verification: search status sizing pushed the macOS split view outside the window. Corrected wrapping and the Retry action's intrinsic sizing; repeated the original search, retry, and narrow-window scenario successfully.
- Verified: 190 focused Swift tests in 13 suites; 15 iOS snapshot/accessibility tests in 3 suites reported passing; macOS dated mock build and iOS simulator build; native resize, compose rejection, search, phone reader, compact folders, and accessibility-extra-large inbox. Lint passed, format changed 0 of 1,195 files, diff check passed. See `docs/qa/uiux-fixes-2026-09-29/README.md` for reproducible acceptance evidence and screenshots.
- Limits: seven existing macOS message-row pixel comparisons also fail with the original source from the base commit on this host; references preserved. iOS reader test runners can stall after reporting their results; teardown status is recorded separately in the QA note. No live-provider send, physical-device/VoiceOver, release, deployment, or maintainer acceptance. The simulator was restored to normal text size; the daily-driver app was not replaced.
- Documentation sweep: CHANGELOG, ADR-0025 clarification, QA evidence, and this log updated. README/setup, PRIVACY/ADR-0006, architecture, versions, and agent conventions are unchanged; no new external network behavior. Delivery is a review PR, without merge or issue-closeout authorization.

## 2026-09-29 — Agent — Desktop sizing, mobile Favourites, settings assessment

- Continued the same user-authorized UI/UX branch, target main, with no matching issue or existing PR. Added source-scoped mobile Favourites, optional Drafts/Sent shortcuts, native reorder/visibility editor, persisted preferences, and collapsed-by-default account groups that preserve saved expansion.
- Extended existing desktop text size to shared tokens/inherited labels and auxiliary editors; independent density affects chrome, mail, compose, and settings. Moved desktop controls/search ownership to Appearance and documented the contract in ADR-0012. iOS retains its Dynamic Type policy.
- Verification: Favourites red-to-green; 197 mail tests, 38 settings tests, and 2 design tests passed. All 16 iOS comparison/accessibility tests reported passing; xcodebuild stalled at teardown and its task-owned wrapper was stopped. Native Favourites add/reorder/navigation/persistence, phone search/filter, and invalid-recipient warning/disabled Send verified. Both native targets built; dated mock macOS identity preserved. Lint and format checks recorded in the QA report.
- Native desktop Small/Compact and Large/Spacious main/settings views verified before screen lock. Remaining native Compose size extremes, final Settings search, secondary Mailbox View tabs, Updates/About walkthrough are blocked by the locked Mac. No daily-driver replacement, live send, physical-device QA, release, or deployment.
- Settings assessment covers all 21 built-in destinations (19 native, two source-only), with 20 captured screens and a proposed eight-category plus About/Updates structure. Broad regrouping is a proposal; only sizing ownership moved.
- Known pixel limits: seven existing message-row comparisons reproduce with the original base source; eight settings navigation/folder comparisons persist in a font-only control. References preserved; no broad baseline re-record.
- Documentation sweep: CHANGELOG, ADR-0012/0025, QA evidence, settings assessment, and WORKLOG updated. README/setup, privacy/network defaults, versions, and agent policy are unchanged. Delivery is a review PR; no merge or issue-closeout authorization.

## 2026-09-29 — Agent — PR #162 navigation polish and settings regrouping

- Goal: polish the iPhone Favourites/sidebar and implement the user's approved eight-category Settings structure plus About & Updates, using a consistent hierarchy on both platforms. Continued `feature/uiux-audit-fixes` in `c798/brev`, from `ff66f53d`, targeting `main` through existing PR #162. No matching issue.
- Changed: inset mobile groups, aligned icons and quiet counts, compact checkmark/reorder editor, readable accessibility labels/counts; compact Settings category sidebar with desktop subpage pickers and phone push navigation. Writing groups compose/signatures/templates/AI Writer; Send safety precedes expandable recipient history. Moved consent to Privacy, browser choice to Reading, and iCloud preferences to Sync & Storage, preserving keys, deep links and opt-in defaults.
- Verified: 43 mail tests; 51 settings tests including eleven desktop image comparisons; eight phone image comparisons across targeted runs. Native simulator add/remove/reorder, disclosure, Writing/Compose/Done and control-search routing passed. Both native apps built; dated macOS mock app launched; real serve-sim frame inspected. Lint, format (0/1,201 changed), actionlint and diff checks passed. Evidence and official Apple/Spark/Mailspring comparison: `docs/qa/navigation-polish-2026-09-29/README.md`.
- Snapshot note: final macOS checks showed tiny symbol-raster differences, inspected and refreshed only the eleven already-intentionally-changed navigation references; rerun passed. Four untouched folder references retain their earlier host-font mismatch, and the seven pre-existing message-row failures remain outside scope. No comparison tolerance relaxed. Initial phone recording failures/runner cleanup are separate from the successful final comparisons, which exited normally.
- Limits: Mac locked, so interactive desktop Settings walkthrough remains unverified; native AppKit snapshots are rendering evidence only. No physical-device/VoiceOver audio, live provider, update/import/export or consent-changing integration QA. Simulator choices restored; daily-driver app untouched. No merge/release/version change or issue closure.
- Documentation sweep: README, CHANGELOG, PRIVACY navigation paths, ADR-0006/0012, the prior assessment, this log and fresh QA evidence updated. No new architecture, endpoint, consent default, retention policy, setup step, or agent workflow; no new ADR or AGENTS change needed. Delivery continues in PR #162 for maintainer review.

## 2026-09-29 — Codex — PR #162 native Settings and toolbar follow-up

- Continued the existing branch/PR from `2ec5e19b` after the user unlocked the Mac. Native verification reproduced two Settings defects: sidebar arrow keys did not select categories, and search results had text-only hit regions. Added focused key handling and full-row hit testing.
- Fixed the user-reported toolbar regression: desktop sizing is applied to pane content before attaching toolbars, preventing Compact controls from squeezing native buttons. Small/Compact and Large/Spacious preserve normal toolbar proportions. Compose, Search and sidebar toggle actions passed.
- Verified the native Settings category/subpage walkthrough, exact-control searches (Gravatar, Browser, iCloud), About/Updates presentation and live sizing of an already-open Compose window. No messages sent or consent changed; original sizing restored and dated mock identity retained. Forty existing Settings tests, including eleven image comparisons, passed. Native toolbar geometry uses rendered red/green evidence because offscreen SwiftUI snapshots do not reproduce window toolbar hosting.
- Documentation sweep: CHANGELOG and both QA reports updated, with eleven native screenshots; no new architecture, endpoint, preference key or privacy behavior. TestFlight was separately authorised and will be recorded with upload/processing evidence; PR #162 remains unmerged.

## 2026-09-29 — Codex — PR #162 internal TestFlight upload

- User authorised TestFlight deployment, without PR merge. Archived `8b3ffbd9fce5befacc32c05cbbbcdc4b01db7db3` as iOS `0.2.3 (6)` with explicit build/version overrides, preserving the repository fallback. All 21 source-commit CI checks passed.
- Verified the existing Google iOS client against the shipping bundle/team in Google Cloud and injected its callback/redirect plus existing Microsoft/Drive configuration through a private temporary xcconfig. No console permissions, OAuth grants or provider settings changed. Removed the temporary configuration after upload.
- Passed team/privacy/export-policy scripts, Release demo-request guard, archive build, extension version checks and strict code-signature verification. Internal-only upload exited 0 with EXPORT SUCCEEDED at 19:25 CEST. Apple upload `4f7b85df-535a-442e-b764-598d2244a262` is PROCESSING with no errors or warnings; processed-build availability and internal-group assignment are still pending.
- Documented archive/source/configuration evidence in `docs/qa/testflight-uiux-2026-09-29.md`, updated release setup and the desktop sizing contract, and reconciled native QA limits. No physical-device installation or live-provider acceptance is claimed. PR #162 remains unmerged.

## 2026-09-29 — Codex — PR #162 desktop Favourites and appearance

- Continued `feature/uiux-audit-fixes` from `7382bc24`, target main, after explicit user approval of desktop Favourites, a softer default dark theme and simpler transparency settings. Existing PR #162 is the tracker; no matching issue/project card. Fetched origin; main remains `6399f36f`.
- Implemented compact desktop Favourites and editor with saved visibility/order, source-scoped navigation, persistent collapsed accounts, counts and context/drop routing. Fixed arrow navigation handing focus to messages before Return/Right. Added Brev Mono Grey as default dark theme while preserving saved theme IDs and accents.
- Replaced confusing window controls with Off / Sidebars only / Full windows, explanatory previews and opacity endpoints up to 100%. Fixed opaque root backing hiding sidebar material, aligned Settings/utility chrome coverage, and corrected the dark separate-toolbar background. Removed the inactive macOS flat-reader message-card opacity control; retained its stored/iPad behavior.
- Verified: 57 mail tests (20 sidebar/editor image comparisons), 51 settings tests (five appearance image comparisons), 31 design tests and 9 theme tests; dated mock macOS build and iOS simulator build. Native account switching, editor visibility/reordering, saved expansion, keyboard focus, theme selection, Norwegian labels, Settings coverage and live compose/separate-reader transparency passed. No messages sent or daily-driver replacement.
- Repository gates: lint, format (0/1,203 files changed), actionlint and diff checks passed.
- Native control subsequently reported App quit/cgWindowNotFound while the dated process was running; extra full-screen/resize and final preference restoration remain unverified. Exact last verified settings and screenshot evidence are in `docs/qa/desktop-sidebar-2026-09-29/README.md`. New desktop accessible move actions are not VoiceOver-audio tested; broader pre-existing pixel failures are not claimed as passing.
- TestFlight follow-up: App Store Connect now reports build 0.2.3 (6) VALID, INTERNAL_ONLY and IN_BETA_TESTING, already included in Henrik Internal QA. No additional group mutation required. That build predates this pass; physical-device installation remains unverified.
- Documentation sweep: README, Unreleased CHANGELOG, existing theme/settings/window/message-opacity ADRs, QA records and this log updated. No new architecture, network endpoint, consent, privacy, version or agent-policy change. Delivery continues through PR #162; no merge, issue closure or maintainer acceptance is claimed.

## 2026-09-29 — Codex — PR #162 CI and device-crash follow-up

- Reproduced the failing repository-self-tests job on `3fb795a3`: the compact-layout checker still matched the old no-argument toolbar helper. Updated it to require the active-theme argument and retain explicit background/visibility safeguards. The focused check and complete `scripts/test.sh --self-tests-only` pass with compiler access; the initial sandbox run could not compile its autodiscovery fixture.
- App Store Connect crash evidence confirms iOS 0.2.3 (6) exits approximately 0.2 seconds after launch on iPhone 17 Pro Max/iOS 27.0, with EXC_BAD_ACCESS in a stack guard during mailbox-root construction. Build 5 has a preceding stack-overflow report in the same root-construction chain. The raw reports remain temporary local diagnostics; no private report contents are committed. A Release/phone-stack regression is being prepared; no crash fix or replacement deployment is claimed in this CI commit.


## 2026-09-29 — Codex — PR #162 iPhone launch stack correction

- Reproduced the device failure in an optimized iOS Simulator test with a temporary 1 MiB main-thread stack guard: signal 11 before the first mailbox frame. Apple crash reports for internal builds 5 and 6 identify the same mailbox construction chain. Raw reports remain outside the repository.
- Added six fixed-size deferred SwiftUI construction boundaries between existing mailbox-root stages. This preserves root-owned state and modifier order while allowing each stage to unwind before the next is evaluated. The exact Release regression now passes, one executed test with no skips. Added it to CI independently of the iOS 27 pixel-baseline gate.
- Verified: 15 Release iOS rendering tests, including the wide mailbox root and phone sidebar/editor references; 40 macOS navigation/reader-retention tests; lint, format (0/1,205 changed), actionlint, diff, signing-team/privacy-manifest/export-policy scripts. CI's original repository-self-tests failure is corrected in pushed commit `e7ee40bf` and the hosted job passes.
- TestFlight replacement build 7 preparation is authorised by the user's earlier deployment request. The physical iPhone is unavailable to CoreDevice; local regression and later Apple processing must not be described as physical-device acceptance. Simulator interaction, release demo guard, archive/upload and exact-head CI are still being completed.
- Documentation sweep: Unreleased CHANGELOG, release runbook, existing TestFlight QA record and this log updated. No public API, package boundary, provider/network, persistence, consent or architectural decision changed; no new ADR, README, PRIVACY or AGENTS change required. Continue existing PR #162, without merge or issue closure.


## 2026-09-29 — Codex — PR #162 crash-fix TestFlight delivery

- Archived `08c129299b48e8c41ebb6d9aae5cfe400519006e` as iOS 0.2.3 (7), preserving the repository version fallback and build 6's verified provider configuration. All 21 source CI checks passed, including the new Release phone-stack test on hosted iOS 26.2. Local iOS 27.0 regression, 15 Release rendering tests, 40 macOS navigation tests and the Release demo-request guard passed.
- Simulator native walkthrough through serve-sim passed message open/back, Favourites/account switching and Compose open/dismiss. Original inbox restored and temporary mirror removed. No mail sent or daily-driver replacement.
- Signed archive, metadata, extension versions, provider parity and privacy/export checks passed. Uploaded at 22:23:43 CEST. Apple reports COMPLETE without errors/warnings, build VALID/INTERNAL_ONLY/IN_BETA_TESTING. Added build 7 to the existing Henrik Internal QA group and verified membership; published English test notes describing the cold-launch check.
- Updated the existing TestFlight evidence with source, CI, red/green reproduction, deployment and limits. Physical-phone acceptance remains pending: CoreDevice could not reach the phone, and the user has been asked to update and cold-launch. PR #162 remains unmerged. This documentation follow-up changes no archive inputs; its CI status is separate from the verified archive-source run.

## 2026-09-30 — Agent — PR #166 mail status localization

- Goal: finish the user-visible half of the mixed-language UI cleanup. Mail status banners, error messages, and empty states inside `packages/BrevMail` were hardcoded English, so a Norwegian interface showed Norwegian folder names next to English failures and empty states. Branch `fix/localize-mail-status-copy` from `origin/main` `d96fd4d9`, targeting `main`; folder-name localization is the separate PR #165 and the Gmail re-auth recovery is PR #164. No matching issue, so no project card.
- Changed: 40 `stringUnit` keys plus one plural added to the BrevMail String Catalog (1116 → 1156); status/error/empty-state copy in nine BrevMail files resolves through `String(localized:bundle:.module)` with runtime `%@`/`%lld` keys; `BrevStatusBanner` gains an optional `bundle:` parameter so package call sites read the package catalog (ADR-0013 amended); `MailStatusCopyLocalizationTests` guards the keys; `MessageListPresentationTests` updated for the `Clear Filters` key collision.
- Verified: focused BrevMail tests green (28 MessageListPresentation tests plus the new localization suite); `scripts/format.sh` 0/1206 changed and `scripts/lint.sh` OK; rendered simulator run (iPhone 17 Pro, iOS 27, mock backend, `-AppleLanguages '(nb)'`, driven through xcodebuildmcp with `simctl` screenshots) captured the search, filter, and spam empty states in Norwegian in `docs/qa/mail-status-localization-2026-09-30/`, matching catalog values.
- Limits: physical-iPhone acceptance pending (handoff item 1; the device is blocked on the Gmail 404 session failure that PR #164 addresses). The reader preview-only banner is catalog- and test-verified only because the mock backend cannot fail a body load. The full BrevMail suite shows 54 host-renderer snapshot mismatches on this macOS 27 host that reproduce byte-identically on a pristine `origin/main` checkout; they are pre-existing environment drift, not this branch, and baselines were not re-recorded.
- Documentation sweep: CHANGELOG Unreleased Fixed entry, QA evidence, ADR-0013 amendment, and this log. No README/setup, PRIVACY/network, version, release, or agent-policy change; no new ADR required. Delivery is a review PR; no merge or issue-closeout authorization.


## 2026-10-05 — Agent — PIM parity QA follow-ups (O7–O10, O12)

- Goal: fix the codeable findings from the stub-DAV parity matrix in
  `docs/qa/pim-parity-stub-dav-2026-10-03/README.md` (O7–O12). Branch
  `fix/pim-qa-followups` stacks on `fix/l10n-interpolated-catalog-keys`
  (PR #189) because both edit `Localizable.xcstrings`.
- O7 (source row showed raw enum): 13 `String(describing: error)` sites in
  `PIMEventSyncService`, `PIMTaskSyncService`, `PIMContactSyncService`,
  `PIMCollectionService` now render through a shared `PIMErrorText` helper
  that prefers `LocalizedError.errorDescription` — the sync error enums
  already carried localized text, `describing` just bypassed it.
- O8 (English RSVP badges/sentences): `CalendarInviteResponsePresentation`
  had no `String(localized:)` at all — reply badge ("Responded", the local
  response label), confirmation prefixes, and all reconciliation sentences
  now localize via `.module`; `AttendeeState.displayLabel` stays an English
  model token (Models.swift has no localized strings) with a localized
  `responseLabel` at the presentation layer. 12 new keys + nb entries in the
  BrevMail catalog.
- O9 (attendee PUT lacked ORGANIZER): `PIMEventWriteService` claims a DAV
  organizer when an event has attendees but none set — basic-auth username
  when `@`-shaped, else `source.principalURL`. `PIMEventICSWriter` emits
  `mailto:` only for mailbox-shaped values (URI values pass verbatim) and
  `ICSParser.parsePerson` now accepts any URI cal-address, not just mailto,
  so the organizer round-trips through sync.
- O10 (attendee field took non-addresses): `addAttendee()` reuses
  `RecipientAddressValidator.isLikelyEmailAddress` and shows an inline
  caption-styled error that clears on edit.
- O12 (stale cached counts): `PIMSourceSettingsModel.observeSourceChanges()`
  subscribes to `coordinator.changes()` — every `markStatus` a background
  sync writes emits — and reloads; wired via a second `.task` in
  `CalendarContactsSection`, same pattern as the browsing models.
- O1 already fixed on main (`PIMDetailEditabilityHint` in contact/task/event
  detail views). O11 was fixed in PR #187.
- Verified: `swift test` BrevCalendar 264/264 (incl. new organizer-URI
  round-trip, organizer-inject create/update, no-attendee no-organizer,
  PIMErrorText); BrevSettings 26/26 (incl. new observer test); BrevMail
  filtered suites green incl. catalog symbol/format guards; swiftformat +
  swiftlint clean on touched files; `xcodebuild -scheme BrevMacOS` pending
  in background at write time.
- Skipped: live stub-DAV replay (no server in this environment); UI pass on
  the attendee hint handed to the testing agent.

- Post-commit: `xcodebuild -scheme BrevMacOS` BUILD SUCCEEDED. Testing run
  verified ALL five follow-ups live on macOS nb — O8 invite badge
  ("Godtatt" + nb reconciliation sentence), O12 live row refresh
  (`Klar`→`Mislyktes` and `5 → 6 hendelser bufret` without reopening
  Settings), O10 attendee rejection caption, O7 readable nb error text for
  missingCredential AND transport families, and O9 via
  `scripts/stub-dav-server.py` (stored ICS carries
  `ORGANIZER:mailto:qa@local.test` + attendee PARTSTAT). ADR-0072 log entry
  added for the CI `adr-required` gate (BrevCalendar sources are protected
  paths). testing-brev-ui skill gained a stub-DAV/PIM section.

## 2026-10-06 — Agent — Appearance accent verification handoff

- Goal: verify the integrated ADR-0048 accent work and lead-owned appearance/settings/sidebar/performance changes on `fix/appearance-navigation-performance`; preserve the combined worktree for review, with no commit or push.
- Verification: `scripts/format.sh` completed (8/1,209 files formatted; 159 skipped); `scripts/lint.sh` passed (SwiftFormat lint 0/1,209, strict SwiftLint, coverage self-test, and ADR-required check). Focused tests passed: BrevThemes 13, BrevSettings 66 across four suites, and BrevMail `FolderSidebarPresentation` 37. No root-appearance policy test suite was present.
- Full nonpixel suites passed with CI pixel filters: BrevSettings 420 tests/62 suites; BrevMail 1,855/276; BrevBackend 1,152/114. BrevMail's separate `ContactsAccessPolicyTests` passed 6 tests, and the Release `AppSessionFactoryTests.releaseBuildIgnoresInjectedDemoRequest` guard passed.
- `tuist generate` and unsigned Debug builds of `BrevMacOS` and `BrevIOS` passed. The iOS build used Xcode 27 RC and simulator UDID `8E780854-5816-4435-AD8F-8098DF847EB5` (iPhone 17, iOS 27.0). Xcode 27 emitted diagnostics in unrelated BrevMail/BrevAvatars sources, but both schemes built successfully.
- The requested iOS `accessibleAppearance(dark:)` snapshot test passed on rerun (2 cases). Its first run created these references, now retained for pixel review: `packages/BrevSettings/Tests/BrevSettingsTests/__Snapshots__/CompactSettingsRowSnapshotTests/accessibleAppearance-dark.appearance-accessible-light.png` and `.../accessibleAppearance-dark.appearance-accessible-dark.png`. The first run exited 65 after first-recording failures and a 600-second simulator-diagnostics timeout; the rerun passed.
- Focused macOS snapshots were not re-recorded: `FolderSidebarSnapshotTests` reported 20 image mismatches across Gmail-native sidebar, all-inboxes alignment, smart views, compact profile scopes, and desktop favorites/editor variants; `AIWriterSectionMacSnapshotTests/desktopSizing` mismatched `packages/BrevSettings/Tests/BrevSettingsTests/__Snapshots__/BrevSettingsSnapshotTests/capture-_-theme-name-size.desktop-small-compact.png` and `...desktop-large-spacious.png`. These comparisons ran on macOS 26.5.2; no base-branch comparison was made, so they are not classified as pre-existing macOS 27 renderer failures.
- The iOS-only imported-system-accent fallback assertion was not executed (the full package tests ran on macOS; the iOS app build compiled the implementation). No UI was launched or driven, `/Applications/Brev.app` was left untouched, and the combined worktree remains uncommitted and unpushed for lead review.

## 2026-10-06 — Agent — Appearance catalog and snapshot cleanup

- Goal: remove String Catalog ordering churn while preserving the integrated appearance work, then refresh only the two new accessible-appearance iOS references for lead pixel review. No commit or push.
- Rebuilt both catalogs from their `HEAD` bytes plus exactly the intended additions: BrevMail `Accounts` and `Apps`, and eight BrevSettings appearance/settings strings. A parsed assertion confirmed every existing entry and metadata value is unchanged, with no removals or unexpected additions; original `HEAD` ordering and two-space JSON formatting were restored.
- Scoped SwiftFormat on `AppearanceSection.swift`, `SettingsSectionComponents.swift`, and `CompactSettingsRowSnapshotTests.swift` changed 0/3 files. `scripts/lint.sh` passed once after all edits (SwiftFormat lint 0/1,209; strict SwiftLint; coverage self-test; ADR-required check).
- On Xcode 27 RC, iPhone 17 / iOS 27.0 simulator `8E780854-5816-4435-AD8F-8098DF847EB5`, record mode wrote only these references: `packages/BrevSettings/Tests/BrevSettingsTests/__Snapshots__/CompactSettingsRowSnapshotTests/accessibleAppearance-dark.appearance-accessible-light.png` and `.../accessibleAppearance-dark.appearance-accessible-dark.png`. The record invocation intentionally exits 65 because SnapshotTesting reports record-mode issues; the no-diagnostics rerun passed both dynamic cases. The iOS-only `importedSystemSourceFallsBackToThemeOnIOS()` test passed separately (1 test), after the combined filter without `()` selected only the snapshot case.
- Existing macOS snapshot differences remain pending comparison against `main`; no existing baselines were changed. Full suites and builds were intentionally not rerun per the handoff. Simulator remains running, no UI was driven, and `/Applications/Brev.app` was untouched.

## 2026-10-06 — Agent — Appearance runtime verification

- macOS mock: separate Settings and Mail changed light/dark together; accent
  search, Theme/System/Custom selection, requested `#111111` preservation and
  Follow theme reset passed. Favorites/Smart Views management and standalone
  Calendar/Contacts/Tasks/Shortcuts opened; Shortcuts also followed light mode.
- iPhone 17/iOS 27 mock: normal and accessibility-extra-large layouts passed,
  including Increased Contrast, custom `#111111` round-trip, theme chooser
  selection/dismissal and reset. Temporary appearance values and simulator
  accessibility settings were restored. Existing toolbar-gear Settings access
  remains deliberate; no duplicate Apps row is required.
- Limits: OS-accent notification delivery, exhaustive sidebar keyboard navigation,
  scoped folder-sync caption, filled-button-specific runtime contrast and all
  iOS destination flows were not exercised. Model tests cover numerical contrast;
  screenshots are visual evidence, not measurements.
- No blueprint change: simulator accessibility toggles are reversible test
  fixtures, not development-environment setup. No daily-driver replacement,
  provider authentication or real message sending occurred.
- Baseline comparison: pristine `ed631a7` reproduces all 20 sidebar and two
  desktop Settings snapshot mismatches on macOS 26.5.2 / Xcode 26.6. Four
  Favorites-editor renders are pixel-identical across base and branch; other
  differences match the intentional headings, ellipsis actions, source picker
  and neutral symbols. Existing references were not rewritten to mask host
  drift. New iOS accessibility snapshots pass. Canonical-host refresh of the
  changed desktop references remains a follow-up.

## 2026-10-06 — Devin — PR #191 Folder Sync header cleanup

- Goal: Henrik flagged the top of iPhone Folder Sync as looking bad (duplicate title, cramped mailbox picker on a grey band, black filter field).
- Changes: Folder Sync scope bar is now a standard `SettingsPickerRow` (Mailbox title/subtitle, menu shows display name, email only when names collide); iOS scope bar uses the pane surface with a 1 pt separator (macOS keeps `bgSecondary`). iOS `SectionScaffold` no longer repeats the navigation title in-pane. iOS filter field uses a search-style quiet surface; filter/Refresh stack at accessibility sizes; "Show" header no longer breaks mid-word; AX folder rows use a dedicated stacked layout so the retention menu never clips.
- Verification: `scripts/format.sh`, `scripts/lint.sh`, `git diff --check`, iOS simulator build; testing agent measured iPhone 17 at large (dark + light) and AX-XL plus macOS Folder Sync scope bar.
- Open: at AX-XL the pinned Mailbox bar takes ~40% of the screen; dark-mode navigation bar (black) vs pane (grey) contrast band and Notifications "Request Access" pill contrast observed but not changed.

## 2026-10-06 — Devin — PR #191 iPhone Settings scope inline

- Goal: Henrik said the Folder Sync top still did not look better (pinned grey Mailbox strip under a black large-title area).
- Changes: on iOS, Settings panes no longer pin a scope bar; the Folder Sync mailbox picker and Mail Storage account row render inside the scroll content via a `settingsScopeAccessory` environment in `SectionScaffold`. Folder Sync uses a single-line Mailbox row (custom wrapping `Menu` at accessibility sizes so the label never clips). iOS detail panes paint `BrevWindowSurfaceBackground(.content)` under the safe area so the navigation title shares the pane colour. macOS keeps the pinned scope bar.
- Verification: format, lint, `git diff --check`, iOS simulator build, macOS mock build; testing agent measured iPhone 17 large text (dark + light) and AX-XL, Mail Storage/Appearance spot checks, and Mac Folder Sync.

## 2026-10-07 — Codex — Release environment startup evidence

- Goal: troubleshoot release acquisition failures without running a release or modifying the release environment, secrets, or protections.
- Ran the existing main startup diagnostic (`37613181185`). Concurrent PR #193 reached main during investigation; preserved that work and used its allowed-main Linux/fresh-environment comparison (`37613417608`). Linux `release` fails acquisition, while fresh Linux/macOS environment jobs pass. Feature-branch release rejections were excluded from acquisition evidence.
- Built and pushed a manual environment-input diagnostic on `chore/runner-environment-diagnostics` (`505132e0`) before the concurrent probes reached main. Its workflow has no checkout, secret references, token permissions, signing, or publishing. Created empty `runner-diagnostic-2026-10-07` with a custom branch policy permitting only that diagnostic branch. Run `37613566767` confirms restricted-environment Linux startup; macOS controls remained queued at inspection.
- Delivery scope narrowed to this evidence report and Support draft on `docs/runner-startup-evidence`, based on current main `1dce2573`. The diagnostic branch/environment are retained; no overlapping workflow implementation is proposed. Support draft has not been sent.
- Verification: diagnostic configuration passed actionlint; format changed zero Swift files; lint and diff checks passed. Real Actions metadata/annotations provide runtime evidence. App tests/builds, snapshots, privacy audit, CHANGELOG, and ADR changes are not applicable to a CI evidence report; release signing validity and full release completion remain unverified.
- Final comparison: main run `37613417608` completed with acquisition failures for Ubuntu, macOS 15, and macOS 26 using `release`, and successful plain/fresh-environment controls. Restricted fresh environment also passed macOS 26 in run `37613566767`; its macOS 15 environment job remains queued and is not counted as a pass. Refreshed local lint, format (zero changes), and diff checks passed on the documentation branch.
- Refreshed final result: all five jobs in restricted-environment run `37613566767` passed, including macOS 15 (runner ID 1000023109). Updated the report and PR evidence to replace the earlier queued snapshot. Evidence PR #194 targets main; no merge or release authorization was requested or exercised.
- Cross-checked Devin's proposed secret-edit cause against current secret metadata: signing/OAuth secrets were last updated September 17; Google API key/app ID were added September 29, after observed acquisition failures. No current secret has a September 24–25 edit timestamp. Run 36073145304 reports workflow success but skips the build; run 35933998396 actually passes the build. The report records Oslo dates and distinguishes skipped builds from successful startup. No secret values were accessed or changed.

## 2026-10-07 — Codex — Release signing environment recovery

- Authorization: Henrik requested completing recovery and merging the necessary changes. Merged evidence PR #194 after every check passed, then based `fix/release-environment-recovery` on current main `cae71ea2`. No other feature PR is in scope.
- Created `release-signing` and verified all five startup probes before credentials (run `37622714025`) and after all credentials (run `37623249131`). Final branch policies permit only `main` and `v*` tags; the temporary diagnostic-branch exception was removed. The old release environment remains intact.
- Populated 12 environment secrets and the Sparkle public variable from existing local sources; Microsoft client ID remains inherited from the repository secret. Exported only the valid matching Developer ID identity from Keychain with a random temporary P12 password. OpenSSL legacy-mode verification confirms its public certificate matches both stable/nightly CI profiles. Removed the temporary P12/password/source after upload. No secret contents are recorded.
- Changed stable, nightly, and startup probes to `release-signing`. Added manual stable dispatch for an existing tag because rerunning an old run preserves the old workflow. Checkout is pinned to the selected tag ref; format, main ancestry, green Build, and release-overwrite protections remain enforced against the checked-out tag SHA.
- Added a real shell-gate fixture: distinct workflow/tag commits prove Build is checked for the tag; missing Build, malformed tags, and unrelated ancestry are rejected. The original workflow fails the manual-tag fixture; the updated workflow passes. Integrated it into the existing release-config self-test.
- Updated ADR-0080, release/diagnostic runbooks, and Unreleased changelog. Verification: startup comparisons, actionlint, release dispatch fixture, and developer-ID release-config tests pass. Lint/format and PR checks follow. Archive/notarization/publication are not yet verified; the recovery dispatch will use the unchanged v0.2.0 tag after merge.
- Credential continuity blocker discovered before merge/publication: the canonical checkout's local Sparkle key/public variable differs from the existing release environment. Neither the legacy local export, Desktop seed, nor separate Rista export matches the original public key. The published September 23 Nightly embeds the original key and its DMG signature cryptographically verifies against it. Thus changing to a local replacement key would break existing update verification.
- Restored the original public variable in `release-signing` and removed only the mismatching private-key copy created by this session. Eleven correct environment secrets remain; the original Sparkle private-key backup is required before recovery PR #195 can merge safely. Asked Henrik for its secure source/location, not its contents. The P12 password question was resolved by selective Keychain export and needs no user action.
- Re-saved the original release environment/policy configuration with identical values and read back unchanged main/v* restrictions; Ubuntu acquisition still fails in run `37624988515`. No original secrets were changed or deleted. Apple notarization API authentication with the selected local key passed.
- PR #195 contains the scoped recovery implementation and verification. Hosted CI is still running with no observed failures; do not merge or dispatch the release until both the required checks and Sparkle credential continuity are satisfied. Merge authorization is already granted; no additional approval is needed once those prerequisites pass.

## 2026-10-07 — Devin — Chrome, appearance reset and Settings polish

- Goal: Henrik's 0.2.0 feedback — toolbar band tinted by mail content, blur behind toolbar buttons, Appearance reset, AI Sidebar toggle, Apple-style Settings, raw Gmail `CATEGORY_*` labels.
- Reader pane uses an opaque theme fade instead of the content blur; message list drops its mid-pane blur and the category bar is opaque. SwiftUI toolbar gains a trailing `sidebar.right` AI Sidebar toggle (the AppKit toolbar is opt-in only; its defaults also include the item). `AppearanceReset` restores Appearance-owned preferences. `SettingsGroup` renders rows in a rounded quiet surface with icon-free headings. Gmail hides CATEGORY_/UNREAD/CHAT labels from folders and chips.
- The monospace look on Henrik's Brev.app comes from the persisted Mailbox View font preference (user setting, not changed).
- Verification: lint, format, BrevGmail tests, BrevSettings AppearanceThemeSettings tests, BrevMail toolbar/visibility tests, macOS mock build.

### 2026-10-07 — Devin — Chrome/Settings polish follow-up (#199)

- Folder Sync table, About rows and Smart Views now use the shared grouped surface (`settingsGroupedSurface()`); iOS switch column widened to 52 pt; AX-size header drops the "Keep offline" column; iOS Reset to Defaults is bordered.
- AI Sidebar toolbar/menu labels now localized (`MailContextColumnVisibility.toolbarLabel`).
- Earlier "Settings stays English under nb" finding was a launch-argument artifact; relaunched with `open -n … --args -AppleLanguages "(nb)"`, Settings is Norwegian on both the test build and installed 0.2.0.
- Verified: format, lint, BrevSettings build, live mac + iOS sim re-test at 5d00392. BrevSettings/BrevMail pixel snapshots fail locally on this macOS 26.5 host; the same 14 BrevSettings tests fail on clean `origin/main`, so they are host renderer drift, not re-recorded. CI skips them on macos-15.
- Open: iOS AX XL app-icon captions hyphenate mid-word and grid stays two columns.

## 2026-10-07 — Devin — Stable release 0.2.1 prep

- Goal: Henrik approved merging #199 and releasing, to test Sparkle auto-update from the installed 0.2.0.
- Changes: `marketingVersion` and project `MARKETING_VERSION` 0.2.0 → 0.2.1; `[Unreleased]` notes became `## [0.2.1] - 2026-10-07`.
- Next: tag `v0.2.1` once Build on main is green; Henrik runs Check for Updates in 0.2.0 himself.

## 2026-10-07 — Devin — Sparkle installer fails in sandboxed release

- Goal: Henrik's Check for Updates in 0.2.0 found 0.2.1 but failed with "An error occurred while running the updater".
- Cause: the release app is sandboxed with `SUEnableInstallerLauncherService`, but `BrevMacOSRelease.entitlements` lacked the `com.apple.security.temporary-exception.mach-lookup.global-name` exception for `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki` that Sparkle's installer needs. Confirmed absent from the installed 0.2.0 signature.
- Changes: add the exception to the release entitlements; `scripts/release-installed-verify.sh` now fails when it is missing.
- Skipped: a local signed archive (no Developer ID cert on this host); verify on the next release DMG.
- Next: 0.2.0/0.2.1 cannot self-update; Henrik installs the next release manually once, then auto-update is tested against the release after it.

## 2026-10-07 — Devin — Stable release 0.2.2 prep

- Goal: ship the Sparkle sandbox entitlement fix (#200) so auto-update can be tested from 0.2.2 → 0.2.3.
- Changes: version 0.2.1 → 0.2.2; changelog heading.
- Next: tag `v0.2.2` after Build is green; Henrik installs it manually; then cut 0.2.3.

## 2026-10-08 — Devin — DMG drag-to-install repair / 0.2.3

- Goal: fix the missing Applications shortcut Henrik found in 0.2.2.
- Cause: the hdiutil fallback packaged the entire Xcode export directory without creating a shortcut.
- Changes: stage only the app, add the shortcut in both packaging paths, and reject invalid mounted layouts before publication. Prepare the already-approved 0.2.3 update-test release.
- Verification: passed the real-hdiutil regression for fallback and modeled create-dmg packaging, including rejection of missing/wrong Applications shortcuts and Xcode export logs; Developer ID release config and shell syntax checks; format and lint. CI remains pending. Signed artifact verification follows release; Henrik drives Check for Updates himself.
- Documentation sweep: release runbook updated; no app behavior, architectural, privacy, or setup change.

## 2026-10-08 — Devin — Mail list scroll chrome follow-up

- Goal: match the supplied Apple Mail reference: scrolling rows behind a blurred mailbox header, and continuous neutral reader chrome.
- Changes: reserve mailbox title/category controls with a safe-area inset and let inner lists scroll under the full-height blur; clip rows at the outer pane boundary. Preserve the original title in the no-folder empty state. Unified/smart and saved-search lists retain their title without a misleading selected-account context. Keep a solid Reduce Transparency fallback and remove the separate reader fade and macOS related-conversation background.
- Verification: `scripts/format.sh` and `scripts/lint.sh` passed. The focused blur retry, pane-surface, related-conversation and header suites passed 20 tests; after changing the new snapshot to title-only, its focused test passed again. Recorded only the five related-conversation references and `mailboxHeader.mailbox-title.png`. `./script/build_and_run.sh --mock` succeeded at 0.2.3 (35). Live dark/full-transparency scrolling was verified for a folder and All Inboxes, including the footer boundary and neutral reader surface. The pre-existing ViewBuilder warning in `MessageListView.swift` and non-Sendable conversion warnings in `BrevMailRootView.swift` remain. Full package suites, iOS and live-provider QA were not rerun for this macOS-only surface correction.
- Snapshot evidence: `mailbox-title` renders only `MailListTitle`; it is not proof of scroll layout or the Reduce Transparency fallback. The live scrolling check is the geometry evidence, and no system appearance settings were changed.
- Documentation sweep: changelog updated. No new ADR needed: this repairs the existing ADR-0015 surface policy without adding a new rendering architecture. No setup, privacy, network, signing or release changes. iOS keeps its existing header stack and related-conversation background.
- Handoff: PR targets main; do not merge or release without Henrik's approval. The installed daily-driver app and Check for Updates remain untouched.
- Recorded overflow QA follow-up: list blur, category actions and footer boundaries passed, but expanding a long conversation in a short window exposed sharp reader text in the toolbar safe area. Clip macOS reader content before applying the shared pane surface, so only neutral window material extends behind the toolbar. Re-test overflow before acceptance.
- Overflow re-test: rebuilt the mock test identity with the clipping fix. The four-message Hemsedal conversation passed top/middle/bottom scrolling in light and dark mode at the app's minimum allowed 1440×652-point window; all expanded messages stayed reachable, no sharp text entered the toolbar, list blur and footer containment still passed. Recorded UI reproduction/re-test is the regression evidence for this geometry-only modifier; no new isolated snapshot was added because it would not exercise the native window safe area. Production Brev and the updater were untouched.
- Verification: focused BrevMail tests passed (14 tests across `MailPaneSurfacePolicyTests` and `MailScrollEdgeBlurRetryStateTests`); `scripts/format.sh` and `scripts/lint.sh` passed. The accepted live UI re-test remains the GUI evidence; no build or UI rerun was performed.

## 2026-10-08 — Devin — PR #202 native-toolbar scroll-under correction

- Henrik correctly rejected the preceding acceptance: clipping removed sharp text but also removed the content that should be blurred behind the actual native toolbar. Blur below the toolbar was insufficient.
- Expand the pane's top clip boundary by the measured toolbar safe-area inset, without moving layout or expanding its footer/side bounds. Overlay non-fading blur in that top region; keep the solid Reduce Transparency fallback. Explicitly allow macOS reader scroll overflow and preserve the separate fixed list controls.
- Rebuilt mock 0.2.3 (37). Recorded light/dark UI testing proved moving blurred rows and expanded four-message Hemsedal content behind the actual native toolbar up to the window edge. Toolbar icons stayed sharp; footer remained contained. This supersedes the previous uniform/clipped-toolbar acceptance.
- Long single-message overflow was not demonstrated: the selected mock message fitted without scrolling. iOS and live-provider QA were not rerun. No snapshot was added: this regression requires native-window safe-area geometry and scrolling, covered by the recorded runtime check rather than an isolated view image.
- Documentation sweep: updated the Unreleased changelog. Existing ADR-0015 still governs shared chrome/readability; no new architecture, setup, privacy, network, signing or release behavior. Production Brev and updater untouched. Do not merge or release without approval.
- Local verification: the focused BrevMail policy tests passed (14 tests in 2 suites); `scripts/format.sh` and `scripts/lint.sh` passed. No build or GUI tests were rerun; the testing agent's recorded native-toolbar retest remains the runtime evidence.

## 2026-10-08 — Devin — PR #202 crash recovery and compact mailbox toolbar

- Recovered `fix/mail-list-scroll-chrome` at `54020b2`, with four saved, uncommitted UI edits. Continue the existing PR, not a sibling.
- Move the mailbox title/account into the default macOS toolbar beside the filter. Retain the in-pane title for the opt-in AppKit toolbar, which owns its items separately. Replace the category/header material with the opaque theme surface; preserve the toolbar-only scroll-under blur and footer clipping.
- The opaque category background used SwiftUI's default safe-area extension and painted over the list toolbar strip. Constrain it with `ignoresSafeAreaEdges: []` so list rows remain visible and blurred beneath the toolbar.
- Verified: focused policy tests passed (14 tests in 2 suites), and format/lint passed before the final one-line background change. The mock app was rebuilt; live scrolling shows blurred list and reader content under the toolbar, with sharp mailbox controls and the title beside the filter. The existing title snapshot is unchanged, because acceptance depends on live window geometry. Dark mode was not rechecked.
- Documentation sweep: changelog/worklog only. No architecture, privacy, setup, iOS, signing or version change. Do not merge/release, replace the daily-driver app, or trigger Check for Updates.
- Follow-up: All Inboxes and other cross-account views omit the last account subtitle; focused `MailRootMessageListTitlePolicy` coverage checks folder-only, unified inbox, Smart View and no-folder cases. The policy filter passed (28 tests in 5 suites).
- Follow-up: Hide the macOS 26 glass capsule behind the toolbar mailbox title with `.sharedBackgroundVisibility(.hidden)`; mock build 0.2.3 (42) passed, pending visual review.

## 2026-10-08 — Devin — Stable release 0.2.4 prep

- Goal: publish the approved PR #202 mailbox toolbar and scroll-under changes in stable 0.2.4.
- Merge: squash-merged PR #202 as `233f335`; `main` and the PR branch now match the approved `b7258c6` content.
- Changes: bumped the shared marketing version and four project settings from 0.2.3 to 0.2.4; moved the current Unreleased fixes under the dated release heading.
- Verification: `git diff origin/main b7258c6 --stat` was empty after merge. Build, Release workflow, and published artifact/appcast checks follow the release commit.
- Handoff: do not install into `/Applications` or run Check for Updates; Henrik performs the update test.

## 2026-10-08 — Devin — Plain category tabs on shared blur

- Goal: try Henrik's approved replacement for the opaque category pills: plain labels and a subtle selected underline over one shared blurred header.
- Changes: macOS-only tab styling; reuse the existing non-fading within-window blur and theme wash for the fixed header, with an opaque Reduce Transparency fallback. Keep iOS chips, toolbar scroll-under geometry, category actions and footer boundaries unchanged.
- Isolation: branch `fix/mac-category-blur` in `/Users/devin/repos/brev-category-blur` starts from stable main; unfinished PR #203 quick-reply edits in the original checkout are untouched.
- Verification: `scripts/format.sh` and `scripts/lint.sh` passed; 38 focused BrevMail tests in 3 suites passed; new light/dark category snapshots recorded and passed. `script/build_and_run.sh --mock` built the isolated dated test identity; the running mock Mac app (default toolbar, `BREV_ENABLE_NATIVE_TOOLBAR=0`) passed category selection, shared-blur scrolling in light/dark, All Inboxes, reader toolbar scroll-under, title placement, footer and divider checks. The test recording is stored under `/Users/devin/screencasts/brev-category-default-blur/`. iOS runtime and Reduce Transparency fallback were not checked; iOS's existing chip path is unchanged.
- Launch note: the experimental `BREV_ENABLE_NATIVE_TOOLBAR=1` bridge crashed at startup with the already-documented `SwiftUI.BarAppearanceBridge`/`NSToolbar` observer conflict; the shipped/default toolbar is flag 0 and was stable. This is not a new category-row crash.
- Documentation sweep: changelog/worklog only. No architecture, privacy, setup, network, signing or version changes; no new ADR required. No production install, updater, merge or release.

## 2026-10-08 — Devin — Sidebar unread and reader quick reply

- Goal: add account-row Inbox badges, message-list unread pills, and inline reader quick replies on macOS and iOS.
- Changes: normalized macOS account rows; added the destination unread-count policy and title pill; added a localized quick-reply bar using the notification reply draft/delivery pipeline; wired typed text into the full reply composer while preserving quote protection. Added focused policy/prefill tests and Norwegian translations.
- Verification: focused BrevMail policy/prefill tests passed; `scripts/format.sh` reported no formatting changes; `scripts/lint.sh` passed. Mock macOS build/run succeeded as 0.2.4 (44), PID 4399; iOS 27 simulator build succeeded and the app launched on `8E780854-5816-4435-AD8F-8098DF847EB5` (PID 4921). The default mock backend omits `.smtpOAuth`, so the quick-reply bar is correctly hidden and its empty/typed states could not be captured; no send was attempted.
- Screenshots: `/Users/devin/qa/sidebar-quick-reply/mac-light-list.png`, `mac-light-reader.png`, `mac-dark-reader.png`, `iphone-list.png`, and `iphone-reader.png`. Quick-reply screenshots are unavailable because the mock lacks `.smtpOAuth`.
- Handoff: use mock only; do not touch `/Applications/Brev.app`. No PR or CI wait requested.

## 2026-10-08 — Devin — Quick-reply mock preview

- Goal: expose quick reply in the mock apps without changing the root capability gate or default mock capability set.
- Changes: macOS and iOS app demo-backend factories now pass `.full.union(.smtpOAuth)`; `MockBackend.send(draft:)` and `save(draft:)` mutate only its in-memory actor store.
- Verification: macOS mock build 0.2.4 (46) and iOS 27 simulator build/launch passed. Focused BrevMail tests passed (38 tests, 6 suites); format reported 0/1,213 changed; lint passed.
- Screenshots: captured and inspected `mac-light-quick-reply-empty.png` and `iphone-reader-quick-reply.png`; the bar does not collide with either reader footer, and the Mac screenshot has no focus ring. The keyboard-up capture shows the field focused but no software keyboard. Mac typed, dark, sent, and expanded-composer states remain uncaptured: the app's accessibility provider reported that PID 6202 did not answer.
- Handoff: mock apps remain running; never touch `/Applications/Brev.app`.

## 2026-10-08 — Devin — PR #203 quick-reply and toolbar QA fixes

- Goal: preserve quick-reply text through quote-body refresh, identify the actual recipient, and prevent Mac title truncation.
- Changes: apply the existing prefill policy when rebuilding reply bodies; resolve the bar's recipient from reply targets; size the Mac title and context to their content; carry quick-reply prefill through detached iPad compose; select only replyable messages; and bind queued sends to their original source/backend.
- Verification: focused BrevMail tests passed (58 tests, 10 suites); iOS quick-reply snapshots passed (1 test, 2 light/dark references); the FolderSidebar run passed the 16 changed account-row snapshots, while the 4 unchanged Favorites-editor references remain mismatched from host-renderer drift reproduced on pristine `ed631a7`. Added only the two quick-reply PNGs and refreshed the 16 account-row PNGs. `scripts/format.sh` reported 0/1,213 files formatted; `scripts/lint.sh` passed. The dated mock build passed as 0.2.4 (49), PID 7134, and the requested iOS 27 simulator build passed.
- Warnings: existing non-Sendable closure conversions in `BrevMailRootView.swift`, a non-Sendable app-delegate capture in `BrevApp.swift`, and BrevThemes visibility warnings appeared during builds/tests; they did not fail verification. The snapshot test runner also logged unavailable Contacts/Intents XPC services on this host.
- Handoff: no GUI QA or CI was run/watched. The dated mock test app remains running; `/Applications/Brev.app` was not touched.

## 2026-10-08 — Claude Code — PR triage, merges and stable release 0.2.5 prep

- Goal: assess open issues/PRs, land the external IMAP fix, recover the crashed Devin session's PRs, and cut 0.2.5.
- Issues: #3, #11 and #14 have their implementation merged; all three wait on live Google/Drive QA (disposable Workspace account, signed iOS build) and maintainer sign-off. No issue state changed.
- Closed without merging: #190 (identical commit already on main as 9b648769), #200 (already on main as c0b86890), #198 (superseded by #199; the Gmail nested-label `nearestAncestor` piece is not on main and is noted on the PR).
- Merged: #188 (external, kdegeek; main merged into the branch to resolve CHANGELOG/WORKLOG, 93/93 IMAPSessionClientTests pass locally; review note left about draining to the tagged line before throwing on an untagged `* ` line). `gh pr merge --auto` merged it immediately because main has no required checks. #203 and #204 (CHANGELOG/WORKLOG-only conflicts resolved; prior PR CI green). #187 (kept main's macOS BrevApp.swift since #191 already themes the PIM windows; only the iOS covers needed the fix; MailStatusCopyLocalization tests pass).
- Skipped: Devin's in-progress runtime check of #203 quick reply in the running test apps did not finish before the crash and was not redone; post-merge CI on main gates the release tag.
- Release: bumped marketing version 0.2.4 → 0.2.5 in BrevConstants and both project files; moved Unreleased entries under 0.2.5. Tag `v0.2.5` follows a green Build on this commit.

## 2026-10-09 — Claude Code — iOS Apple Mail-style reader header

- Goal: rethink the iOS reader top (Henrik approved an Apple Mail layout): related-mail bar off the top, compact header, Original toggle into the ••• menu. Branch `feature/ios-reader-header` from `origin/main` @ faafd40e.
- Changed: `RelatedConversationBar` is macOS-only; iOS gets `RelatedConversationReaderPresentation` (menu items and footnote status per controller state), menu section and footnote views injected through a new `relatedConversationController` environment value from `BrevMailRootView`. `MessageDetailView` has an iOS `phoneHeader` (avatar, one-line sender, short date via `MessageReaderHeaderPresentation.shortDate`, "to" toggle, subject below, hairline) with From/To/Cc/Bcc/Date in the expanded details; the HTML rendering toggle is an overflow-menu item on iOS. `ThreadMessageCard` phone header shows name plus short date on one line; `ThreadConversationView`'s ••• menu carries the related-mail items and the footnote. ADR-0074 consent is unchanged: remote search still runs only from the explicit Load/Retry actions or the per-account preference. Added nb strings for the two new copy keys; recipient labels (To/Cc/Bcc) now resolve through the string catalog.
- Verification: new Swift Testing suites (short date, related-mail menu/footnote presentation) failed to compile first, then passed; full `swift test --package-path packages/BrevMail` on macOS reports 83 snapshot issues both on this branch and on pristine `origin/main` (same host-renderer drift; 1962 vs 1946 tests, all new tests pass). iOS snapshots re-recorded on an iOS 27 simulator for the header, thread cards, thread view and the PhoneMailbox detached-reader/conversation references (the other PhoneMailbox references already mismatch from host-renderer drift and were left alone), plus new accessibility-size header and footnote baselines. `scripts/lint.sh` and `scripts/format.sh` clean. Both apps built (see PR). Runtime pass on a private iOS 27 simulator, dark + Norwegian, mock data: message, thread, ••• menu, Load related mail (temporary mock handler, reverted), Original toggle, expanded recipients.
- Not reproduced: the blank grey avatar from the real TestFlight message. `BrevAvatarView` renders initials for that sender name in mock data and in the snapshot; the blank circle probably comes from a resolved contact/BIMI/favicon image on the real account.
- Handoff: the mock demo account has no `.relatedConversationLoading`, so the related-mail menu items were exercised with a temporary local patch only. Screenshots in `docs/qa/ios-reader-header-2026-10-09/`.

## 2026-10-09 — Claude Code — Mac toolbar band colour mismatch

- Goal: Henrik reported the Mac top bar has a different colour from the themed glass panes, as if an extra background/accent layer sits on it.
- Cause: `MailToolbarScrollUnderModifier` and `MailListHeaderModifier` (`MailWindowScrollEdgeBlur.swift`) overlaid `theme.bgPrimary` at 35% on top of the scroll edge blur. The pane below has no such wash, so the band read as a separate colour.
- Change: remove the 35% overlay in both places; the band is blur-only, as `MailWindowScrollEdgeBlur`'s own doc describes. Reduce Transparency still uses the opaque theme fill.
- Verification: swiftformat lint 0/1; swiftlint clean on the file; `script/build_and_run.sh install-run --mock` built and launched; window captures of the mock test app (solid default and `-window.translucencyMode glass`) show the toolbar band matching the panes. A window-only capture cannot show the desktop through glass, so Henrik should confirm on his wallpaper.
- Skipped: no snapshot test, because the band depends on live window safe-area geometry (same reason as #202/#204).

## 2026-10-09 — Claude Code — ADR-0086 per-section font family (Proposed)

- Goal: Henrik asked for a font choice per UI section after finding that only one "Message font" exists (it was never per-section; ADR-0012 moved text size to Appearance in #162).
- Change: drafted ADR-0086 (Proposed): four sections (sidebar, message list, reader, compose) each pick one `MailboxFontFamily`; read-time fallback to `mailbox.fontFamily`; section set through the SwiftUI environment at pane roots; one Fonts group in Appearance. Indexed in `ADRs/README.md`. No code.
- Henrik accepted with compose following the reader and the toolbar mailbox title staying System; ADR updated to Accepted with three sections.
- Implementation (same PR): `BrevFontSection`, `SectionFontFamily` wrapper and `\.brevFontFamily` environment in BrevDesign; `brevFont` applies the family design. Pane roots in `BrevMailRootView` set their section inside the toolbar modifiers. List, reader, thread card and compose body read their section through the wrapper. Appearance gets a Fonts group; Mailbox View loses Message font (iOS keeps its text-size preview using the reader font); search routes "font" to Appearance; Reset clears section keys and the legacy key. String catalogs updated (en + nb); three stale keys removed.
- Live check (mock app, launch-argument fonts): sidebar, list and reader follow their keys; toolbar mailbox title stays System. A blank reader HTML body after launch also happens on clean `origin/main` (mock app: 2/5 with legacy serif, 1/5 with System), so it is pre-existing; a follow-up task was flagged. Setting `\.brevFontFamily` on the reader pane root made it much worse (5/6), so the reader pane sets no environment and its text uses `@SectionFontFamily(.reader)` only (4/5 rendered without it). macOS text-style fonts did not visibly render `.rounded`, so non-default designs use the explicit-size path.
- Verification: BrevDesign tests pass (6 new); BrevSettings focused suites pass (64 tests incl. 2 new reset/apply-all tests and updated search tests). Full BrevSettings run: the remaining failures are the same 12 pixel/smoke tests that fail on clean `origin/main` on this host. swiftformat/swiftlint clean on touched files; BrevMail builds.
- iOS: re-recorded `CompactSettingsRowSnapshotTests/accessibleAppearance` (light/dark) on the iPhone 18 Pro iOS 27 simulator after making the Fonts group wrap at accessibility sizes (the first version widened the pane); re-run passes. `compactSignature` fails on this host before and after this change (not touched).
- BrevDesign `SplitViewTransparencyPassStateTests` "settled pass re-arms itself" is timing-flaky on clean `origin/main` too (1/4 runs).
- Not verified: the macOS Fonts group in Settings was not seen live (Brev cannot be driven in the background); fonts were exercised through launch arguments instead.
- Merge (Henrik asked to merge #206 and #207): #206 squash-merged as e7475081 after a CHANGELOG/WORKLOG-only conflict with #209 (its one red check was the BrevSyncEngine search timing test, 0.103 s vs 0.098 s). #207 merged origin/main (CHANGELOG/WORKLOG only); after the merge BrevMail builds for iOS 27 and macOS, and the focused BrevMail reader-header, BrevSettings and BrevDesign font tests pass. CI on the final #207 commit was not waited for.

## 2026-10-09 — Claude Code — iOS add-account sheet theme and layout

- Goal: fix the iOS add-account sheet rendering the light theme in dark mode and tidy its layout.
- Changes: the iOS add-account sheet now applies `.brevRootAppearance(session:)` (same cause as the PIM covers in #187); the login-screen setup sheet does the same on iOS. On iOS, Add moved to the navigation bar and is hidden while OAuth sign-in is the primary path; the bottom button stack is gone, status stays pinned, and Test connection shows only next to editable manual server fields (`IMAPAccountSetupPresentation.showsToolbarAddAction` / `showsInlineTestConnection`). Provider shortcuts use `BrevButton` secondary; scroll padding moved inside the scroll view so content scrolls under the nav bar. macOS layout unchanged.
- Verification: see the PR description (BrevMail presentation tests, lint, format, iOS 27 simulator dark-mode `nb` screenshots in `docs/qa/ios-account-setup-2026-10-09/`).
- Handoff: no snapshot added; the sheet has no iOS snapshot pattern (existing LoginView snapshots are macOS-only).

## 2026-10-09 — Claude Code — Native iOS snooze picker sheet

- Goal: Henrik said the iOS snooze popup looked horrible. Rebuild it as a native iOS sheet. Branch `fix/ios-snooze-picker` from `origin/main` @ faafd40e.
- Changed: `SnoozePickerView` iOS path is now a `NavigationStack` with an inline "Snooze" title, Cancel as `.cancellationAction`, an inset-grouped themed `List` (subject as a footnote header, quick rows with icon, title and right-aligned wake time, a "Choose date & time…" row that pushes a graphical date picker plus time row with Snooze as `.confirmationAction`), `.medium`/`.large` detents (large for the custom screen and at accessibility sizes), a visible drag indicator and a themed sheet background. Rows are single accessibility elements ("Tomorrow morning, Tuesday 9:00 AM"); the wake time drops below the title when it does not fit. New `SnoozeSchedule` helper holds the date logic (injected `now` and `Calendar`) and adds "This evening" (18:00, before 17:00) and "This weekend" (Saturday 09:00, Monday to Thursday). Visual time labels drop "today"/"tomorrow" because the titles already say it. macOS keeps its original layout and its original three options; only the row model is shared. Call sites keep `.brevTheme(theme)`, which already pins the colour scheme and sits under the app's `.brevRootAppearance`; the sheet rendered dark in dark mode in the two call-site paths exercised (reader, list).
- Verification: `SnoozeScheduleTests` (8) written and run; a first version of the compact label test failed (DateFormatter relative dates ignore the injected `now`), which led to the catalog-based wording. New iOS snapshot suite `SnoozePickerSnapshotTests` (light, dark, accessibility) recorded and re-run green on an iOS 27 simulator; added to the CI iOS snapshot list. `scripts/lint.sh`, `scripts/format.sh`, macOS `swift build`, iOS `BrevIOS` build clean. Runtime pass on a private iOS 27 simulator, mock data, Norwegian: dark and light, reader-path and list-path sheets, custom date screen and accessibility text size, using temporary local launch hooks (removed; grep confirms none remain) because the simulator control tool was not granted. Before/after screenshots in `docs/qa/ios-snooze-picker-2026-10-09/`.
- Not verified: tapping through the real reader ••• menu and swipe actions (hooks set the same state those actions set); the Unified Inbox call site (same view, same `.brevTheme(theme)`); VoiceOver output (label wording is set in code, not heard).

## 2026-10-09 — Claude Code — Stable release 0.2.6 prep and iOS TestFlight 0.2.6 (9)

- Goal: ship the merged iOS polish (#208 add-account sheet theme/layout, #209 Apple Mail–style reader header, #210 native snooze picker) plus #206/#207 as 0.2.6, and upload the matching iOS build to internal TestFlight.
- Changes: bumped marketing version 0.2.5 → 0.2.6 in BrevConstants and both project files; moved Unreleased entries under 0.2.6. Tag `v0.2.6` follows a green Build on this commit.
- iOS: TestFlight 0.2.6 (9) is archived from this commit with explicit MARKETING_VERSION/CURRENT_PROJECT_VERSION overrides and provider settings injected through a private temporary xcconfig (values never logged); build 8 (0.2.5) was uploaded outside this session.
- Skipped: physical-device cold launch (maintainer QA after TestFlight processing).

## 2026-10-09 — Claude Code — Release builds use the macOS 26 SDK

- Goal: Henrik's installed Brev.app has no glass circles behind toolbar buttons, unlike local test builds.
- Cause: `/Applications/Brev.app` 0.2.5 has `DTSDKName` macosx15.5 / Xcode 16.4 because `release.yml` and `nightly.yml` ran on `macos-15`. macOS 26+ runs older-SDK apps in compatibility mode without the current design. Local test builds (Xcode 27, macosx27.0) show it. Not a macOS version or user setting.
- Change: `release.yml` and `nightly.yml` run on `macos-26` (runner-diagnostics 2026-10-07 showed it starts in `release-signing` with Xcode 26.6). `scripts/release-artifact-verify.sh` fails a DMG whose app SDK is older than macosx26; `scripts/test-release-dmg.sh` covers the new defect. ADR-0080 amended. `build.yml` unchanged (still macos-15).
- Verification: `scripts/test-release-dmg.sh` failed on the new old-SDK case before the guard and passes after; actionlint clean on both workflows.
- Not verified: no Xcode 26.6 locally (only 27.0), so the first compile with the release toolchain is the next nightly after merge. Cut 0.2.6 only after that nightly is green.

## 2026-10-09 — Claude Code — macOS list and avatar hot paths

- Goal: Henrik asked for better macOS performance. A read-only survey ranked suspects; this PR takes the three that are small, certain and testable.
- Changes: `MailPinnedMessages.messageIDs(in:sourceID:)` decodes the at most 500 stored pin keys once instead of base64-encoding a key for every loaded header (`MessageListView.refreshPinnedMessageIDSet`). `MailNavigationState` keeps a lazily rebuilt ID→index map (`@ObservationIgnored`, invalidated on any `currentFolderHeaders` change) for `selectedHeader`, `updateHeader` and `replaceCurrentFolderHeaders`. `AvatarDisplayImageCache` (main actor, NSCache, keyed by resolver, normalized email, preferences and pixel size) lets recreated `BrevAvatarView` rows draw the last decoded photo on their first frame.
- Measured (release build, throwaway benchmark, not committed): pin refresh over 10k headers 2.68 ms → <0.01 ms with no pins, 3.07 ms → 0.02 ms with 20 pins.
- Verification: new tests for pin decoding (incl. parity with the old key check), selectedHeader behaviour (replace, in-place edit, duplicate IDs) and the avatar display cache. BrevAvatars 41/41 pass. BrevMail list/navigation filter: the only failures are 10 pixel snapshots that fail identically on clean origin/main on this host. swiftformat/swiftlint clean.
- Deferred (bigger, need design): whole-folder JSON header cache decode/rewrite on folder open (move paging to the SQLite `message_headers` table); per-row selection invalidation; remote-content regex scan on the main actor; retention sweep before startup-ready; first rich-HTML open never re-measured after the #98 prewarm.

## 2026-10-09 — Claude Code — 0.2.6 release point moved past #211/#212

- `chore(release): cut 0.2.6` (78f33e29) was never tagged: its push-event Build runs were cancelled repeatedly by later pushes to main (build.yml `cancel-in-progress`), and #211 landed after it, moving signed releases to the macOS 26 SDK. Tagging 78f33e29 would have released with the pre-#211 workflow and the old SDK.
- This commit folds the #211/#212 Unreleased entries into 0.2.6. The PR-event Build on this exact commit satisfies release.yml's "green Build on the tag SHA" gate without racing main pushes; main is then fast-forwarded to it and `v0.2.6` tagged here.
- iOS TestFlight 0.2.6 (9) was archived from 78f33e29; #211/#212 are release-infra and macOS-only, so the iOS content matches.
- Caveat from #211: the macos-26 release toolchain had not compiled in CI before this release; a toolchain failure fails the Release run closed (no GitHub Release or appcast item).

## 2026-10-09 — Claude Code — blank reader HTML body after launch (no code change)

- Goal: fix the macOS reader's HTML body rendering blank right after launch (mock build, "Stavanger rollout" thread; reported 1/5 with System font, 2/5 with serif, 5/6 with `brevFontSection(.reader)`).
- Finding: not a Brev bug. WebKit's unified-log activity state for the reported runs (12:48–13:02) shows the body page never had `IsVisible` in all 9 blank launches (state 184 → 56: in window, occluded, visually idle). WebKit then suspended the page's WebContent process (`freezeLayerTree` reason 4) and dropped its layers. cua-driver still captures the occluded window, so the SwiftUI chrome looks normal and the web body is an empty box. Every launch where the window was visible rendered.
- Repro: `open -j` (launch hidden) gives a blank body 5/5 on clean `origin/main`; bringing the same window forward renders it within 4 s 5/5. Visible launches rendered 0 blank out of ~95 across `origin/main`, `faafd40e` (0.2.5), serif/System fonts, a CPU-saturated host, background launch, AX-tree capture, and a local repro build with `brevFontSection(.reader)` on the reader pane.
- Consequence: the 2026-10-09 #207 entry's "pre-existing blank reader body" and the 5/6 rate with `brevFontSection(.reader)` came from occluded-window captures. Dropping the reader environment font for that reason was not necessary.
- Verification tip: before trusting a screenshot of a Brev web body, make sure the window was visible on screen during load (not hidden, covered, or on an idle display).
- Verification: no code changed, so no tests run.

## 2026-10-09 — Claude Code — reader pane sets its font section (ADR-0086)

- Goal: put `brevFontSection(.reader)` back on the reader, now that the blank-body "regression" that kept it out turned out to be an occluded-window capture artifact (see #214).
- Changes: `.brevFontSection(.reader)` on the macOS/iPad reader pane root and the iOS compact reader root in `BrevMailRootView` (inside the toolbar modifiers, like sidebar and list), and on the detached reader window root. ADR-0086 decision 4 updated; CHANGELOG entry under Unreleased.
- Verification: swiftformat/swiftlint clean on the touched files; macOS mock test build installs; BrevIOS builds for the iOS Simulator. Visible launch with `-font.reader serif`: reader title, metadata and thread cards are serif, list and sidebar stay System, body renders.
- Blank-body count: 10 of 10 visible launches rendered (`-font.reader serif`, mock build from the branch merged with main, screen unlocked). An earlier run with the screen locked showed 9 of 10 blank because no launch became visible (WebKit activity state 184 → 56), the known hidden-window artifact.
- No snapshot test: the change is pane-root wiring in `BrevMailRootView`, which has no snapshot coverage; `brevFont` itself already reads the environment.

## 2026-10-09 — Claude Code — ADR-0003 note for #212

- #212 touched `packages/BrevAvatars/Sources` (an ADR-required protected path) without an ADR change, and was merged while the `adr-required` check was red. This adds the missing ADR-0003 amendment describing `AvatarDisplayImageCache`. Lesson: check `adr-required` before merging, even though `main` has no required checks.

## 2026-10-09 — Agent — iOS UI/UX and accessibility audit (no code change)

- Goal: audit every reachable iOS surface against the iOS HIG / iOS Mail and produce findings plus PR slices.
- Changes: new `docs/qa/ios-ux-audit-2026-10-09/` (README with findings table and 8 PR slices, 62 screenshots, per-screen `performAccessibilityAudit` output, theme contrast table). No product code touched.
- Verification: temporary XCUITest walker (removed, never committed) on own iPhone 17 Pro and iPad Pro 11 iOS 27 simulators (deleted afterwards), mock backend only; variants en/nb, light/dark, AX3/AX5, four built-in themes.
- Skipped: VoiceOver speech, Reduce Motion/Transparency/Bold Text toggles, PIM screens with data, attachments/HTML/banners, widgets and extensions (see README section 4).
- Handoff: local branch `audit/ios-ux-2026-10-09` also carries an unpushed local merge of `origin/fix/ios-account-setup-sheet` (#208); cherry-pick the audit commit if #208 is not merged first.

## 2026-10-09 — Claude Code — iOS Settings panes as forms (slice 7 of the iOS UI/UX pass)

- Goal: audit findings T1-T9 (`docs/qa/ios-ux-audit-2026-10-09`): Settings panes as native forms, one flat root list, labeled mailbox switches with a default-mailbox checkmark list, iOS-only copy, confirmations for destructive actions, Settings as a sheet over mail. Branch `fix/ios-settings-forms` from `origin/main` @ 42656635.
- Changes: `SectionScaffold`, `SettingsGroup` and the row components render a `Form`/`Section` on iOS and stay unchanged on macOS (`SettingsGroupStack`, `SettingsRowStack`, `SettingsButton`, `SettingsButtonRow`, `settingsInlineSurface`, `settingsFormChrome` are the seams). New iOS pages: account detail (Show in Mail switches, default mailbox checkmarks, confirmed sign out and remove), per-account notification switches, per-folder sync page. Smart Views reorders with `.onMove` (new `SmartMailboxSettings.moveEntries`); the saved-search editor is a navigation-bar sheet; the sidebar Smart Views sheet in `FolderSidebar.swift` too. `BrevApp.swift` presents Settings as a `.sheet` (add-account sheet hangs off Settings while it is open). Settings search drops Mac-only rows on iPhone. ADR-0002 got a note on `BrevButton` vs form row buttons.
- Decisions: row subtitles are not shown under iOS rows (accessibility hint plus section footers instead), per the audit. `BrevQuietSurface.swift` itself is untouched because BrevMail/compose/reader use it; Settings stops using it on iOS. The quiet-hours picker keeps hour menus (the model stores whole hours, so a time `DatePicker` would drop minutes).
- Verification: red-to-green Swift Testing for `NotificationPanePresentation`, account detail presentation, search platform adjustment and Smart View drag reorder; `swift test` on macOS has the same 48 snapshot issues in the same 5 suites as `origin/main` @ 42656635 (macOS 27 host vs macOS 26 references), +14 passing tests; new iOS suite `SettingsFormSnapshotTests` (root, Accounts, Notifications denied state, Appearance x light/dark/AX3) and re-recorded `CompactSettingsRowSnapshotTests` pass on iOS 27.0; swiftlint strict and swiftformat clean on touched files; simulator walk with a temporary XCUITest (not committed) in light, dark, nb and AX3 with accessibility audits, evidence in `docs/qa/ios-slice7-settings-2026-10-09/`.
- Skipped / not verified: `scripts/lint.sh` stops on two pre-existing swiftformat findings in BrevAvatars and BrevMail tests (not touched). Outbox "Discard All Pending Changes" and task delete confirmations (T5) live in BrevMail files outside this slice. `BrevSettingsSnapshotTests` iOS references (not in CI) were not re-recorded. Audit "Text clipped" on a few plain button rows is not reproducible visually.
- Handoff: slice 6's shared sheet modifier is not used here (Settings applies `.brevRootAppearance(session:)` directly); swap it in when that lands.

- Follow-up (same PR): the root rows were 74 pt because the shared row added a 44 pt minimum-height frame on top of the default list insets. Removed it (and the zero-inset override on extension rows, and the callout padding on iOS), so rows use the system metrics (52 pt on iOS 27). The root now uses the existing task groups (App, Reading & Composing, Organization, Sync & Storage, Privacy & Security, Advanced) so every section has a header. Re-recorded only the 3 root form snapshots and the 2 signature snapshots; the other baselines still match. Contrast item on the root audit appears only at the initial scroll position (search-field glass over a header).

## 2026-10-09 — Claude Code — iOS a11y slice 4: contrast contract, scalable controls, plurals, extension strings

- Goal: audit slice 4 (G1-G3, N1-N4, X1, X3) from the 2026-10-09 iOS UX audit. Branch `fix/a11y-contrast-strings` from `origin/main` @ 42656635.
- Changes: ADR-0002 contrast contract (accent/warning/danger text 4.5:1, success/info glyphs 3:1, `BrevTheme.controlBorder` 3:1, `accentTextOnTint`); 31 palette colours in 15 built-ins moved in HSL lightness only; `BrevIconButton`/`BrevButton`/`BrevChip`/`BrevStatusBanner` use `@ScaledMetric` with a 44 pt iOS floor (`BrevHitTarget`); `BrevMotion`/`brevWithAnimation`/`.brevAnimation`; widget `containerBackground` + `privacySensitive` and nb catalog; share extension catalog (14 keys, nb); notification content uses Dynamic Type, a neutral avatar and `DefaultContentHidden`; 17 BrevMail count strings got en/nb plural variants; N4 literals in the seven presentation files now use `String(localized:bundle:.module)` with nb entries.
- Verification: palette/contrast tests over all 37 built-ins (red on the old palette: 55 issues, green after); catalog tests for widget + share extension nb; BrevThemes 19, BrevDesign 52, BrevWidgets catalog tests, BrevMail targeted suites pass; swiftlint --strict clean; swiftformat clean on touched files. iOS app builds with the temporary XCUITest; `performAccessibilityAudit` on inbox and reader in 5 variants (screenshots in `docs/qa/ios-slice4-a11y-2026-10-09/`).
- Snapshot re-records (only those that pass on an unmodified baseline here and legitimately changed): macOS LoginView wide-light, compact-google-and-imap, compact-google-imap-fallback (secondary button outline), MailContextColumn mailbox-no-selection (chip text); iOS reply-compose, conversation-accessibility (2), related-conversation footnote failed/partial. Many other BrevMail/BrevSettings/BrevWidgets macOS and iOS snapshots already fail on this host (macOS 27 / iOS 27 sim) at baseline; they were not re-recorded.
- Skipped/follow-up: avatar initials contrast (BrevAvatars palette) is still flagged by the audit; `withAnimation` call sites in thread/list/follow-up views and the `%lld hidden read message%@` / `%lld attachment%@` suffix keys belong to files owned by other slices; share-extension UI (X2) untouched.
- CI follow-up (same slice): `swift test` on the macos-15 runner only copies `Localizable.xcstrings` (log shows "Copying Localizable.xcstrings"), so plural variations and nb values are not resolved there and lookups return the key text. Strings asserted by tests (remote-content copy, reminder offsets, repeat count) now pick separate singular/plural keys in code (`1 hour before` / `%lld hours before`). Mirrored CI locally by running the CI `swift test` invocation with an emptied catalog: 1890 behaviour tests pass. Plural variations remain for strings only shown in the app. The macos-15 `snapshot-test` job in run 37958744726 was cancelled, not failed.


## 2026-10-09 — Claude Code — macOS list keyboard and reader polish (PR 1 of 2)

- Goal: close four small macOS gaps from a UI survey. Branch `feature/macos-list-keyboard-polish` from `origin/main`; PR 2 (`feature/macos-list-multiselect`) stacks on it.
- Changes: the focused message list handles bare Delete/Forward Delete (single or checked messages, through the existing `deleteRow`/`bulkDelete` paths, so undo, rollback and the permanent-delete confirmation still apply; once per press, never on key repeat), Escape (clears checked messages, otherwise ignored), Home/End and Page Up/Page Down (ten rows). Key mapping and index math live in `MessageListKeyboardNavigation`; `MailNavigationState.moveSelection` applies it. The help window gains a macOS-only "Message List" section. Both macOS "More message actions" menus get `.help`. `MailboxFilterMenu` already had `.help(...)` on origin/main, so it is unchanged. The attachment caption in `MessageDetailView` uses a plural catalog entry (`%lld attachments`, en and nb); it was the only "attachment(s)" site. Thread card headers get a hover background (`theme.bgSecondary`), an Expand/Collapse tooltip and a stronger chevron on macOS via `ThreadCardHeaderAffordance`; iOS is unchanged.
- Verification: new `MessageListKeyboardNavigationTests` (11) and `MessageAttachmentCountLabelTests` (2) written first (red: `moveSelection` missing, then Norwegian plural not resolved through a `locale:` argument, which led to resolving via the compiled `nb.lproj`); `MailKeyboardShortcutInventoryTests` and `MailStatusCopyLocalizationTests` pass; `swiftlint` clean on touched files; `scripts/check-adr-required.sh origin/main` passes (no protected paths touched).
- Skipped: no UI-driven check of the key handlers or hover (Brev ignores background UI driving); no snapshot test for the thread card hover, which only appears under a live pointer. Unified Inbox list (`UnifiedInboxListView`) has its own key handling and is not changed.
- Notes: repo-wide `swiftformat --lint .` reports 2 files that also fail on clean `origin/main` and are untouched here (`AvatarDisplayImageCacheTests.swift` hoistTry, `MailPinnedMessagesTests.swift` sortImports). `ConversationWorkspaceSnapshotTests` fails the same 4 tests (6 issues) on clean `origin/main` and with this change.

## 2026-10-09 — Claude Code — iOS compose slice (audit C1–C10)

- Goal: slice 3 of the iOS UI/UX audit (`65b1ef26`, not added to this branch): compose cancel, focus, attachments and native compose sheets. Branch `fix/ios-compose-native` from `origin/main` @ 42656635.
- Changes: `ComposeDismissalPolicy` (dirty detection, Cancel decision, swipe blocking; pure, tested) drives a Cancel button, a Delete Draft / Save Draft dialog and `interactiveDismissDisabled`; a presentation-delegate proxy (`ComposeDismissAttemptObserver`) routes the blocked swipe to the same dialog. `ComposeFocusPolicy` focuses To on new mail and the body above the quote on replies, and chains Return. The paperclip is a menu (`ComposeAttachMenuPolicy`): Photo Library, Take Photo and Scan Documents only when available, Attach File. The editor font is a `UIFontMetrics` body font (the initial text previously kept UIKit's default font). Link, Schedule Send and Templates are `NavigationStack` forms/lists on iOS; the Drive sheets share `GoogleDriveSheetChrome` (no 560 pt minimum on iOS). The reply attribution is localized and local-time. Camera usage string added to `apps/iOS` Info.plist (+ nb) and PRIVACY.md.
- Cause found for C10: the body editor wrote its selection bindings during `makeUIView`/`updateUIView`; those writes are now deferred.
- Cause found for the swipe hook: `presentationController` on a child controller fabricates a throwaway presentation controller; the delegate must be installed on the root of the parent chain.
- Verification: new Swift Testing suites for dismissal, focus, attach menu and attribution (red → green); `swift test` on the touched suites passes; iOS device build, iOS simulator run with a temporary XCUITest (not committed) for focus, dirty Cancel, blocked swipe, clean Cancel/swipe, reply focus, attach menu, link and template sheets in en light/dark, nb dark and AX3; `performAccessibilityAudit` run on compose. iOS snapshots re-recorded after review (`docs/qa/ios-snapshot-baselines.md`).
- Skipped / unverified: Take Photo and Scan Documents (simulator has neither), Schedule Send and Drive sheets at runtime (mock has no scheduled send; no Google client; covered by snapshots), C4 (From/Cc/Bcc row restructure) and most of C6 (display names, contact picker) were left out of this slice. `scripts/format.sh` was not run: `swiftformat` flags two untouched files on `main` (`AvatarDisplayImageCacheTests`, `MailPinnedMessagesTests`). Unrelated iOS and macOS snapshot references fail to compare locally on this runtime and were not touched.
- Handoff: the reply attribution change is the one macOS-visible change (shared formatter); gate it with `#if os(iOS)` if that is not wanted. Merge-order note: the string catalog and `Info.plist` are shared with the other iOS slices.

## 2026-10-09 — Claude Code — iOS reader push and Apple Mail action bar (slice 1 of the iOS UX audit)

- Goal: audit findings R1–R6, R11 and L8 (reader slice). Branch `fix/ios-reader-push-action-bar` from `origin/main` @ 42656635.
- Changes: on iPhone the reader is now the split view's detail column pushed with `preferredCompactColumn = .detail` (system push, interactive edge swipe, Back names the mailbox); `MailCompactReaderStack` and its test are deleted. `CompactReaderChromePolicy` (pure) holds the after-archive policy (`CompactReaderRemovalPolicy`: show the survivor that inherited selection, else pop) and the bar inventories. Archive, Delete, Junk and the Move sheet settle the reader through it once the move succeeded. Bottom bar is Archive (Delete when no archive folder) · Move · Reply menu · New Message; previous/next chevrons use the new `MailNavigationState.previousHeaderID/nextHeaderID`; the second ••• is gone and the nav-bar ••• (message or conversation) gains "Ask AI" via `readerAskAIAction`. Undo/ephemeral toast sits above the bottom bar inside the reader (safe-area inset), `BrevToast` has 44 pt buttons and posts a VoiceOver announcement on iOS. Header sender and "to" rows are 44 pt and the sender opens the contact card; conversation cards drop the raw address, read sender/date/snippet as one element, subject is a heading, thread animations honour Reduce Motion; quick reply has 44 pt buttons, Send return key, themed placeholder, scaled glyph and announcements.
- Gotcha worth keeping: an environment value that is a fresh closure on every root body pass (non-Equatable) invalidated the whole reader subtree each pass and froze the app on the first reader push (main thread 100% busy in `MessageListRow.body`). `ReaderAskAIAction` is `Equatable` (always equal) for that reason. A first attempt with `navigationDestination(isPresented:)` on the list pane showed the same freeze, which was this bug, not the navigation approach.
- Verification: `CompactReaderChromePolicyTests`, `MailNavigationAdjacentHeaderTests` written first (red = missing symbols), then green. macOS `swift build` for BrevMail; iOS `BrevIOS` build; lint and format. iOS 27 simulator pass with a temporary XCUITest (never committed): open, edge-swipe back, archive from the reader, next/previous, conversation reader, archive-to-empty pop, `performAccessibilityAudit` on the reader (no issues), en/nb × light/dark. Screenshots in `docs/qa/ios-slice1-reader-2026-10-09/`.
- Not verified: VoiceOver speech (announcements are posted, not heard); the Move sheet path through the reader; unified-inbox previous/next (walks the selected account's loaded headers only); Dynamic Type AX5 on the new bars; iPad regular width (unchanged path, not driven).
- Handoff: "extend the undo window while VoiceOver runs" (L8) is not done (`UndoQueue` timeout is created in `BrevMailRootView` but lives with the list slice's toast timing). Per-card "Message display" ••• in conversation cards remains.
- Follow-up (review): the phone reader header rows kept their 44 pt frames but the visible name and "to" lines are flush again (name bottom-aligned, "to" top-aligned, avatar centred, frames overlap the surrounding whitespace by 12 pt via negative padding; accessibility sizes keep the stacked layout). Audit on the reader: no issues, both rows report 326×44. Re-recorded `header-present` and `detachedReader`.

## 2026-10-10 — Claude Code — iOS onboarding keyboard traits, sign-in errors and share extension (slice 8c, O1–O3, X2)

- Goal: audit findings O1, O2, O3 and X2. Branch `fix/ios-onboarding-share-extension` from `origin/main`. O4 (initial mailbox selection) belongs to another slice.
- Changes: add-account email field is `.username` with a Go key that runs Find settings (`IMAPAccountSetupPresentation.emailSubmitAction`), password field is `.password`, host/port/username-template fields get URL/number keyboards and no autocapitalisation, field labels are read by VoiceOver. Login shows a neutral "Google sign-in isn't available in this build" notice (`LoginViewPresentation.showsGoogleUnavailableNotice`), explanatory text is callout size on iOS, and `signInError` is announced. `AppSessionPresentation.keychainLockedMessage(for:)` gives iPhone/iPad their own copy. `ImportProgressPresentation` strings are localized (nb added) and the banner keeps its 44 pt "Sign in again" button separate for VoiceOver (`accessibilityGrouping`). The share extension hosts a SwiftUI `ShareSheetView` in a `UIHostingController`; `ShareSheetContent` holds the pure state logic and lives in `ShareHandoffURL.swift`, which BrevIOSTests already compiles, so the protected `Project.swift` stays untouched.
- Verification: new Swift Testing suites (`OnboardingErrorCopyTests`, `ShareSheetContentTests`, `IMAPAccountSetupKeyboardTraitsTests`), iOS banner snapshots recorded on an iOS 27 simulator with `-testLanguage en`, simulator run of login, add account and the share extension (invoked from Safari) in en/nb, light/dark, AX3. Evidence in `docs/qa/ios-slice8c-onboarding-share-2026-10-10/`.
- Skipped / unverified: VoiceOver speech; the sign-in banner on a live account (the mock has no auth-failed health, covered by snapshot); Return flowing to Password for a password provider; tapping "Open Brev" in the extension.
- Handoff: the macOS pixel snapshot `LoginViewSnapshotTests.compactGoogleUnconfigured` shows the old developer copy and needs re-recording on a macOS 26 host (this host is macOS 27 and every Login snapshot drifts here). The add-account sheet still shows developer copy for an unconfigured Google client ("A platform-specific Google OAuth client ID is needed…", `IMAPAccountSetupPresentation.oauthAction`). The share extension lists Safari's extra "URL" file as an attachment (pre-existing hand-off behavior, now visible). `apps/iOS/BrevIOS.xcodeproj/project.pbxproj` is tracked but only changes at release cuts, so the Tuist regeneration diff was left out.

## 2026-10-10 — Claude Code — iOS message list: selection mode, unread dot, swipe parity (audit slice 2)

- Goal: audit findings L1–L7, L9–L11 (L8 shipped in #224). Branch `fix/ios-list-selection-swipes` from `origin/main` @ f4555690.
- Changes: `MailNavigationState.isSelecting`/`isInSelectionMode`/`beginSelection`/`endSelection` give selection an explicit mode (a Select button in the root toolbar enters it; Cancel or any consumed selection ends it; folder/mailbox switches end it). iOS uses `MailSelectionToolbar` (Select All/Cancel top, Mark menu, Move, Archive, Delete bottom, `BulkActionIconButton` now `@ScaledMetric` with a 44 pt floor); the inline `MailBulkActionBar` stays macOS-only. `MessageListRow` shows an accent unread dot, a semibold-only-when-unread sender, a scalable selection circle, hides the avatar initials from VoiceOver and speaks the date ("25 minutes ago"); at accessibility sizes the thread badge moves under the sender. Phone swipes: leading = read toggle; trailing (edge first) = Archive/Delete, Flag, More (action sheet from `swipeMoreActions`). Phone context menu: `MessageContextMenuLayout.compact` (Reply, Mark, Move/Archive/Delete, Select, then More). Date headings are non-interactive `.isHeader` rows on compact width. `MailDenseChromeDynamicType` caps now apply on macOS only (`mailDenseListChromeDynamicType()`). All Inboxes passes `isCompactWidth`. Root: title is the navigation title with an unread subtitle (iOS 26), Refresh button hidden on compact width, pull to refresh runs `refreshVisibleMail` (own `Task`, falls back to a cached reload when it returns nil), message-list pane no longer forces an opaque nav bar (`MailPaneSurfacePolicy.messageList`). Empty/error states use `ContentUnavailableView` on iOS. macOS overflow items "Done"/"Select All" are localized ("Mark as Done"…).
- Verification: Swift Testing written for swipe/menu ordering, selection state, subtitle, spoken date, sender weight, pane policy (added alongside the implementation, run green); iOS snapshots `PhoneMessageListSnapshotTests` (7); iOS 27 simulator with a temporary XCUITest (not committed): Select → Select All → Archive (mode ends) → Cancel, leading/trailing swipe, More sheet, context menu, All Inboxes, en light, nb dark, AX5; `performAccessibilityAudit` on list, selection mode and All Inboxes (see PR for what remains). Screenshots in `docs/qa/ios-slice2-list-2026-10-10/`.
- Not done / notes: a large navigation title was tried and is not honoured by the compact split view's content column on iOS 27 (title stays inline), so the title is inline with a subtitle. The account line was dropped from the subtitle because it truncated beside the toolbar buttons. Search field and bands untouched (slice 5). "N selected" is not shown in the title (Unified keeps its selection locally); the Select All/Deselect All label and enabled bottom bar carry the state. Long-press More menu on very short screens still scrolls.

## 2026-10-10 — Claude Code — iOS Mailboxes list and iPad compose sheet (slice 8a, audit S1–S3, I1–I3)

- Goal: native Mailboxes list on iPhone and a form-sheet compose on iPad. Branch `fix/ios-mailboxes-ipad` from `origin/main`.
- Changes: `FolderSidebar` renders a `List(.insetGrouped)` on iOS (Favourites, Smart Views, Apps, one collapsible section per account; unread count trailing; shared `MailboxListRow`/`MailboxDisclosureRow`); macOS code path untouched apart from moving iOS-only branches out. Large "Mailboxes" title (profile name for a custom profile), profile switcher is a leading menu, Edit opens the favourites editor, "Inbox ›" shortcut and `MailRootSidebarToolbarPolicy` removed. `MailRootComposePresentationPolicy.surface` keeps compose in a sheet unless a new window is explicitly requested; compose sheets use `.presentationSizing(.form)` (iOS 18+). Detached reader/compose scenes apply `.brevRootAppearance(session:)`. Sidebar nav bar no longer paints an opaque background, which hid the large title.
- Verification: Swift Testing written first (unread phrase, account header value, nav title, compose surface), macOS `swift build` and filtered `swift test`, iOS `BrevMail` and `BrevIOS` builds, five iOS snapshots re-recorded or added in `PhoneMailboxSnapshotTests` (`-testLanguage en`), temporary XCUITest on own iPhone 17 Pro and iPad Air 13-inch (M3) simulators, evidence in `docs/qa/ios-slice8a-mailboxes-ipad-2026-10-10/`.
- Skipped / unverified: VoiceOver speech; `.isSelected` read back from the runtime tree; Stage Manager multi-window. Seven other `PhoneMailboxSnapshotTests` cases (favourites editor, settings categories, expanded inbox, conversation, inbox search, snooze picker) differ from their references on a local iOS 27 simulator and are not touched by this slice.
- Handoff: `restorationBehavior(.disabled)` for the compose scene needs iOS 18 and `SceneBuilder` cannot apply it conditionally; nothing creates the compose scene now, but a scene stored by an older build is not removed. The compose `openWindow` branches in `BrevMailRootView` stay for a future explicit "Open in New Window" action. The reader's two adjacent "•••" buttons (R3) belong to the reader slice and are still visible on iPad.

## 2026-10-09 — Claude Code — macOS reader attachment drag-out, Save All, double-click open

- Goal: Apple Mail parity for reader attachment rows on macOS. Branch `feature/macos-attachment-drag-save-all`, target `main`.
- Changes: `MessageDetailView` attachment rows (macOS only, `#if os(macOS)`) gain drag-out to Finder or another app (`NSItemProvider.registerFileRepresentation`, bytes fetched lazily through the existing `downloadAttachment` backend path and written off the main actor to `$TMPDIR/BrevAttachmentDrag/<uuid>/<original name>`), double-click to open in the default app (existing Open action), a `bgSecondary` hover fill and a `.help` tooltip with filename and size. Messages with two or more downloadable attachments get a "Save All…" header button: `NSOpenPanel` folder pick, then each file goes through the existing `downloadedAttachmentURL` staging path and is copied under a sanitized, collision-free name. Pure rules live in the new `MessageAttachmentExportPolicy` (which attachments qualify, destination names, help text, drag staging, stale-staging prune). Strings added to `Localizable.xcstrings` (en + nb, manual). iOS rendering is unchanged. `ThreadMessageCard` has no attachment list, so nothing to change there.
- Privacy/local data: no new network calls (same backend download as Save/Open). Drag staging folders are removed on the next drag once older than one hour, a stricter cleanup than the existing Quick Look/Open temp files (which are never pruned by the app).
- Verification: `MessageAttachmentExportPolicyTests` (12) written first, failed to compile (red), pass after implementation. Related suites (`MessageAttachment*`, `MessageDetail*`, `MessageCommandPresentation`) pass. `swift build --package-path packages/BrevMail` clean; `xcodebuild -scheme BrevMail -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED. swiftformat and swiftlint clean on touched files. `scripts/check-adr-required.sh origin/main` passes (no protected paths touched).
- Pre-existing failure: `DetachedMessageWindowSnapshotTests` "reader-content" does not match its reference on clean origin/main (42656635) either (same host renderer drift); not re-recorded. Repo-wide `swiftformat --lint .` also reports 2 files not touched here (`AvatarDisplayImageCacheTests.swift` hoistTry, `MailPinnedMessagesTests.swift` sortImports), both from #212 already on main.
- Not verified: an actual drag into Finder or a compose window and the Save All panel were not driven at runtime (no GUI drive in this session); the file-representation provider and panel flow are compiled and covered only through the pure policy tests. Duplicate names follow the existing "name (1).pdf" convention rather than Finder's "name 2.pdf".
- Handoff: `origin/main` advanced to a69e297c (release fold) after this branch was cut; `CHANGELOG.md` and `WORKLOG.md` will need a trivial merge when the PR lands.



## 2026-10-09 — Claude Code — macOS list multi-select (PR 2 of 2)

- Goal: Command-click, Shift-click, Shift-arrow and Command-A on the macOS message list, and a reader pane for multi-selection. Branch `feature/macos-list-multiselect`, stacked on `feature/macos-list-keyboard-polish` (PR 1).
- Changes: `MessageListSelectionMath` (pure: toggle, range from anchor, extend, select all, plain; a range of one row is reported as no checked rows) and `MessageListClickModifier`. `MessageListView` reads the click modifiers from `NSApp.currentEvent` in the row tap gesture (thread chevron still wins), keeps the Shift anchor and cursor in `@State` that follow the selected row while nothing is checked, handles Shift-Up/Down in the existing arrow key handler, and publishes a select-all action as a focused value only while the list container has focus. `MailCommands` gains Edit > Select All Messages (Command-A, macOS), disabled unless the list is focused, so the standard Select All keeps working in text fields. Plain click on macOS now always returns to single selection (it used to toggle once any row was checked); plain arrows after a range collapse to the range cursor. The bulk bar's five handlers moved into `makeBulkSelectionActions()`, which the bar and the new `MessageBulkSelectionPane` share via `MailNavigationState.bulkSelectionActions` (not observed, refreshed on every selection change). With two or more rows checked the macOS reading pane shows "N messages selected" with Mark Read, Mark Unread, Flag, Archive, Delete and Clear Selection. iOS code paths are unchanged.
- Verification: `MessageListSelectionMathTests` (21, one failing first run led to fixing Command-click on the lone selected row), `MessageBulkSelectionPresentationTests` (3, en and nb plurals via `.lproj`), extended `MailKeyboardShortcutInventoryTests`; `swift build` clean.
- Skipped: no UI-driven check of clicks, Command-A or the pane (Brev ignores background UI driving); drag to folder uses the existing `draggablePayload`, which already carries the whole bulk selection, but was not exercised. The reader toolbar still shows single-message actions (Reply and so on) for the previously selected message while the pane is up; hiding them is a follow-up. Thread child rows and the Unified Inbox list keep their previous click handling.

## 2026-10-10 — Claude Code — iOS sheet appearance and native utility sheets (audit H1–H3, R12, O4)

- Goal: slice 6 of the iOS UI/UX audit. Branch `fix/ios-native-utility-sheets` from `origin/main` @ f4555690.
- Changes: one `brevSheetAppearance(_:)` modifier in `RootAppearance.swift` (pure `BrevSheetAppearanceResolution` plus tint, `presentationBackground`, hidden grouped-list background; macOS keeps `brevTheme`) replaces every `.brevTheme(theme)` on a presented view in BrevMail, including the snooze, schedule-send, compose-sheet, template and Drive call sites. Move To, Copy To, Note, Properties, View Source/Show Headers, Create Task/Meeting (and their unavailable sheets), Follow Up, Outbox and Choose Mailboxes are `NavigationStack` sheets on iOS with Cancel/Done/Save/Create/Continue in the navigation bar; the Mac dialogs are untouched behind `#if os(macOS)`. Choose Mailboxes gained Skip (finishes without saving) and a default-mailbox checkmark list. The Ask AI sheet has a title and Done, "on this device" copy, no Command-Return hint and a display-name sender chip.
- Verification: `SheetAppearanceTests` (resolution cases plus a source scan that fails on `.brevTheme(` in BrevMail sources) and a new sender-chip test; iOS snapshot suite `NativeUtilitySheetsSnapshotTests` (also in the CI iOS list); simulator run with a temporary XCUITest outside the repo.
- Not verified at runtime: see the PR body and `docs/qa/ios-slice6-sheets-2026-10-10/README.md`.
- Handoff: H3's other sites (add-account sheet, theme picker Done, PIM covers) are outside this slice's files.

## 2026-10-10 — Claude Code — iOS native search: scopes, tokens, suggestions (slice 5, audit Q1, Q2)

- Goal: replace the hand-built bottom search capsule and the stacked bands above results with the system search field. Branch `fix/ios-native-search` from `origin/main` @ 939e72ae.
- Changes: iOS uses `.searchable(text:tokens:isPresented:)` on the message list pane (`mailListSearch` in `MessageListSearchField.swift`; the `UITextField` capsule is deleted, macOS `NSSearchField` untouched). On iOS 26 the bottom bar carries `DefaultToolbarItem(kind: .search)` next to Compose (behind `#if compiler(>=6.2)`); earlier iOS puts the field in the navigation bar drawer. `.searchScopes` gives "Current mailbox" / "All mailboxes" on folder lists (not All Inboxes, smart views, saved searches or the attachments pane). Predicate chips became tokens (`MailSearchToken`: Unread, Flagged, Has attachments, sender, date, and From/Subject field tokens that scope the typed text). Tokens compose into the same query string the planner already parses, so `MailNavigationState.searchText` is now computed (`searchFreeText` + `searchTokens`) and every list, debounce and cache key is unchanged; assigning `searchText` still replaces the whole query. Typed predicates ("unread from ada@x.no last week") turn into tokens when the user submits. `.searchSuggestions` offers recent searches (UserDefaults, device only), suggested filters, senders from the loaded headers, From/Subject field tokens and the Local/Auto/Server search location; no network calls. The "This folder · Filters" strip, chip row and grey status band are gone on iOS (folder list and All Inboxes); `MailSearchStatusView` is now a footnote under the results, shown only while cached matches await the server, an attachment-content scan runs, a source failed, or a server-only search could not be verified (`MailSearchFooterPolicy`). Cancel clears query, tokens and scope. Mailbox scope no longer resets on pull to refresh on iOS (only on a folder switch).
- Verification: Swift Testing for token composition, scope → query/folder mapping, extraction, suggestions, recents, footer policy, navigation state and catalog nb presence (written alongside the types; macOS `swift test` filtered run 209 tests green); iOS `BrevMail` and `BrevIOS` builds; swiftlint --strict and swiftformat clean on touched files; iOS snapshots `searchFootnoteFailed`, `searchFootnoteServerStage` (new) and `PhoneMailboxSnapshotTests/inbox(dark:)` (search capsule removed from the fixture) recorded on iOS 27. Simulator pass with a temporary XCUITest (not committed) on own iPhone 17 Pro and iPad Air 13-inch: focus, scope switch, token add/remove, sender and field tokens, results without bands, Cancel, selection mode hides search, All Inboxes, `performAccessibilityAudit`, en/nb x light/dark and AX3. Evidence in `docs/qa/ios-slice5-search-2026-10-10/`.
- Not verified: VoiceOver speech (token and scope labels come from the system `Label`/`Text`; read from the accessibility tree only); the footnote on a live failed server search (mock never fails; covered by snapshot and policy tests); iOS 17-25 placement (drawer field) compiles but was only run on iOS 27; Dynamic Type of the system chrome. The system "close" button is 38 pt and the token "Clear text" button 20 pt; both are OS-drawn and the audit flags the latter.
- Handoff: the server-syntax hint (`ServerSearchSyntaxHint`) is macOS-only now. `MailSearchOptionsBar`, `CollapsibleOptionsStrip` and `NaturalLanguageSearchChipStrip` are macOS-only in practice; their iOS branches are dead and can go with the next cleanup.

## 2026-10-10 — Claude Code — Flaky WorkflowNavigationReconciliationTests

- Goal: find why `external workflow changes and undo update reader membership without a reload` fails now and then on CI (PR #184 run 37059283658, PR #208 run 37914826898, PR #227 run 38017695869, always `unified → false, snooze → false`, line 126, `["a", "c"]` instead of `["a", "b", "c"]`) and make the test deterministic. Branch `fix/flaky-workflow-reconciliation-test` from `origin/main` @ 936c1985.
- Cause: `MessageListView` starts two tasks on appear, `.task(id: reloadKey)` and the search `.task`. The search task goes through `MailSearchTaskOwner.run`, which adds a hop. When the first load finishes before that hop runs, the list loads a second time. The test moved on as soon as the first load showed three headers, set the workflow state, and polled the header count. The late second load filters with the live binding, so it produced `["a", "c"]` before SwiftUI had rendered the change. The poll saw two headers, the test undid at once, and SwiftUI then rendered a state equal to the one it rendered last. `onChange(of: localMessageWorkflowState)` never fired, and the headers stayed at `["a", "c"]` for good. That is why #185's larger budget only made the failure slower (8.9 s with 50 polls, 28 s with 250).
- Changed (test only): the harness reports the workflow state its view tree rendered (`Model.didRender`, fed by an `onChange` on the harness), and the test awaits `model.rendered(...)` after the change and after the undo instead of polling the header count. Both tests get `.timeLimit(.minutes(1))` so a missing render fails instead of hanging. Assertions are unchanged.
- Verification: with temporary logging in `MessageListView.reload` and `MailNavigationState.replaceCurrentFolderHeaders` (not committed), `taskpolicy -b swift test --package-path packages/BrevMail --skip-build` reproduced the CI failure in 4 of 14 runs before the change. The log of each failing run shows the second load applying `["a", "c"]` and no `onChange` at all. After the change: 0 of 20 runs with the same logging (the late second load landed mid-test 33 times), 0 of 10 runs without logging, and `--filter WorkflowNavigationReconciliation` 25 of 25 idle and 25 of 25 with 54 busy loops. The filtered loop never failed before the change either (33 of 33), so it proves little alone. `scripts/lint.sh` OK, `swiftformat --lint` clean on the file.
- Skipped: CHANGELOG, ADR and snapshots (test-only change). The 83 snapshot issues that the full BrevMail suite reports on this macOS 27 host are the same in every run, before and after.
- Handoff: the double startup load is product behaviour and is not touched here. It costs a second first-page fetch when it happens (2 of 24 loads in an ordinary local full-suite run, most loads at background priority). Worth its own issue.

## 2026-10-10 — Claude Code — PR #232 review follow-up

- Codex review (P2): `Model.rendered(_:)` stored a checked continuation that task cancellation could not resume, so a render that never arrived would hang the suite past `.timeLimit`. The wait now uses `withTaskCancellationHandler` and resumes the stored continuation on cancellation; the assertions after it then fail normally.
- Verification: `swift test --filter WorkflowNavigationReconciliation` 15/15 green in a loop after merging current main; swiftlint strict and swiftformat clean on the file.

## 2026-10-10 — Claude Code — message list loads once on appear

- Goal: stop `MessageListView` fetching a folder's first page twice when it appears (found in PR #232). Branch `fix/message-list-single-appear-load` from `origin/main` @ afb668c5.
- Changes: the search trigger on `MessageListView` is an `.onChange` of the same search text and filter key instead of a `.task(id:)`. The `.task(id:)` also ran on appear, where the `reloadKey` task already loads the folder (or runs the search when search text is set), so with empty search text `reload()` could run a second time once the first load had cleared `activeFolderLoadRequest`. A search text or filter change still calls `reloadForSearchChange()`; `searchWork` cancels the previous run and `onDisappear` cancels the last one, as before. The modifier sits in `body` because one more `.onChange` in the `workflowObservedContent` chain exceeds the type checker's budget.
- Verification: new `MessageListAppearLoadTests` (hosted list, counting backend that answers on the main actor). Before the fix: 2 first-page fetches on appear and 3 after clearing a search (red). After: 1 and 2, and an appearance with search text runs 1 search and 0 folder fetches. swiftformat and swiftlint clean on the touched files; `xcodebuild -scheme BrevMail -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED.
- Pre-existing failures: full `swift test --package-path packages/BrevMail` fails 53 pixel-snapshot tests in 17 snapshot suites on this host (macOS 27.0.1). The same 53 fail with the source change reverted; no other test fails.
- `UnifiedInboxListView` has one `.task(id: loadKey)` for folder and search loads, so it has no second appear load; unchanged.
- Not changed: a filter-key change with empty search text still reloads the folder, as it did. On appear that needs `navigation.searchExecution` to differ from the backend default with no user selection, which `init` already rules out.

## 2026-10-10 — Claude Code — PR #233 review follow-up

- Codex review (P2): a folder switch resets search options in the `reloadKey` task (`reconcileSearchExecutionWithBackendCapabilities()`, scope and all-folders resets), which changed the observed search key and ran `reloadForSearchChange()`; with empty search text that fetched the folder's first page a second time.
- Change: the search observer now watches `SearchChangeTrigger(text:filterKey:)` and asks `MessageListReloadPolicy.searchChangeNeedsReload(oldSearchText:newSearchText:)`. Without search text before and after, an options-only change does not reload; entering, changing or clearing text, and option changes while searching, reload as before.
- Verification: hosted test "a search option change with empty search text does not refetch the folder" failed before the change (2 fetches) and passes after; 3 new policy tests; `swift test --filter "MessageList|MailSearch|UnifiedInbox"` 271 tests green (snapshots skipped); iOS `BrevMail` build succeeds; swiftlint strict and swiftformat clean on touched files. Merged current main (#230 search rework) first.

## 2026-10-09 — Claude Code — ADR-0087 IMAP header pages from SQLite (Proposed)

- Goal: Henrik chose to design the folder-switch speed-up (whole-folder JSON header cache) before building it.
- Change: drafted ADR-0087 (Proposed): SQLite becomes the IMAP header store, paging metadata moves to `folder_sync_state` plus an `imap_page_windows` table, full-folder consumers become queries, memory-only fallback without an index, lazy per-folder migration, storage UI reads SQLite, and a measure-first rollout with targets. Amends ADR-0029, ADR-0030 and ADR-0082 §3 once accepted. No code.
- Evidence: a read-only code survey (callers, schema v6, nullability, encryption, tests, local cache sizes 0.5–0.8 KB/header). Cold folder open and SQLite page reads at 10k/50k are still unmeasured; step 1 of the rollout measures them.
- Next: Henrik accepts or edits; implementation is four stacked PRs.

## 2026-10-10 — Claude Code — PR #217 review follow-up (ADR-0087, still Proposed)

- Codex review (P2): the consumer table kept "Existing `allIndexedHeaders` path" for attachment enumeration, which pages every header into memory and filters there (`IMAPSMTPBackend` cached-attachment enumeration), contradicting decision 3 ("no consumer scans a whole folder").
- Change: that row now calls for a selective engine query for attachment-bearing or cached-body rows, with a short paragraph explaining why. Status is unchanged (Proposed); no code. Merged current main.

## 2026-10-10 — Claude Code — ADR-0087 accepted

- Henrik approved ADR-0087 on 2026-10-10. Status changed Proposed → Accepted in the ADR and the index; ADR-0029, ADR-0030 and ADR-0082 carry an "Amended by ADR-0087" line and the index rows say so.
- No code in this PR. Implementation follows the ADR's rollout: measure first (cold open and SQLite page reads at 10k/50k), then the four stacked PRs; the cutover ships only if it meets the ADR's targets.

## 2026-10-10 — Claude Code — Slice 8b runtime QA evidence (PR #234)

- Goal: capture simulator evidence for P1-P4. Added `docs/qa/ios-slice8b-pim-2026-10-10/` (empty states en light/dark, nb light, en AX3; Settings page from the empty state; a11y audit text; snapshot references).
- Verification: temporary XCUITest outside the repo on own iPhone 17 Pro iOS 27 simulator (deleted after). No product code changed.
- Not verified: screens behind a connected source (month, week, task editor, delete confirmation, Contacts editor): Add DAV Source dismisses the whole Settings sheet in mock mode (pre-existing), so only snapshot-test renderings exist.

## 2026-10-10 — Claude Code — Add DAV Source closed all of Settings (iOS 27)

- Goal: fix tapping "Add DAV Source…" dismissing the whole Settings sheet (pre-existing on main, found during slice 8b QA).
- Finding: reproduced on an iOS 27 simulator. About 1.2 s after the connect sheet opens SwiftUI logs four refused presents on the Settings sheet and calls the root `showSettings` binding with false while its getter still returns true. The credential sheet and removal dialog in the same view are never built; moving the root Settings `.sheet` below the covers did not help. Root cause inside SwiftUI not isolated.
- Change: on a compact-width iOS Settings stack, `PIMSourcesSettingsView` pushes `PIMSourceConnectSheet` (new `isPushed`: no own NavigationStack, no Cancel) with `navigationDestination` on the Add row, for both connect and reconnect. Regular width and macOS keep the sheet. `navigationDestination` on the whole group changed its layout, so it sits on the row.
- Verification: iPhone 17 Pro iOS 27 simulator: button pushes the form, back returns to Calendar & Contacts, Settings stays open, layout matches before. `swift test` BrevSettings: 47 pre-existing macOS pixel-snapshot failures, identical on an untouched checkout; lint/format clean; BrevSettings builds for macOS and iOS.
- Not verified: Reconnect Source push (needs a connected source), iPad regular width, submitting the form.

## 2026-10-10 — Claude Code — Mac release 0.2.7 prep

- Goal: ship the iOS UX pass slices merged since 0.2.6 (#222, #219, #224–#231, #233–#235 and others) as Mac `v0.2.7`. iOS TestFlight is launched by Henrik from another Mac (this Mac has no `.env.local`).
- Changes: marketing version 0.2.6 → 0.2.7 in BrevConstants and both project files (regenerated in a clean env, no other diff); Unreleased entries moved under 0.2.7. Tag `v0.2.7` follows a green PR-event Build on this commit; main is fast-forwarded to it so the tag SHA has that Build.
- Verification: see PR; release workflow run is recorded in the handoff.

## 2026-10-11 — Claude Code — Quiet Mac related-mail bar

- Goal: Henrik found "Viser bufret samtale." plus two buttons above every Mac reader message off.
- Change: new `RelatedConversationBarPresentation` (status loading/failed/partial or none; actions Retry, Load related mail, Spam and Trash in the old order). No sentence for cached/complete, Spam and Trash only after a lookup result, bar not rendered when empty (`BrevMailRootView.showsRelatedConversationBar`). Removed three unused strings; improved two nb translations. Phone reader unchanged.
- Verification: 9 new presentation tests (red first, then green); BrevMail iOS build, lint, format. Removed the two idle-state bar snapshots (their output changes); the partial, failed and accessibility baselines are untouched.
- Not verified: pixel snapshots (all five bar baselines already fail on this macOS 27 host, so none could be re-recorded here; CI's macOS 26 job compares the remaining three), the bar visually in the running Mac app.

## 2026-10-11 — Codex — Glass envelope icon PR

- Request: replace the three app icons with Frost, Smoke and Obsidian; make 02 Smoke the default and update brev-site. Follow-up: switching Frost to Smoke changed the Dock size.
- Implemented SVG masters with compact optical drawings, direct per-size rasterization, vector PDF previews, opaque iOS catalogs and multi-resolution ICNS for all running macOS variants. Removed the old Icon Composer override. Kept persisted IDs and backup compatibility; Smoke is the new default and login brand. Updated target manifests, generated projects, translations and ADR-0004. The three Dock variants now share the same loading path and measured bounds.
- Verification: 7 AppIconPreferences tests passed after expected red failures; 4 icon-only login snapshots updated and passed; macOS dated mock build/launch and iOS Simulator build passed; native selector exercised; 74 catalog entries checked for dimensions and iOS alpha rules; regeneration deterministic; lint/format/ADR checks passed. Full commands and limits are in `docs/qa/glass-icons-2026-10-11/README.md`.
- Existing failures: seven other LoginView snapshots also fail with the exact original source and artwork. Their baselines were preserved. Physical-device iOS switching and automated Dock pixel capture were not verified.
- Delivery: feature/glass-envelope-icons targets main. Companion website PR: https://github.com/henrikogaard/brev-site/pull/1. No issue was assigned; no issue/project closeout is claimed. No release or deployment. README, CHANGELOG, ADR-0004 and asset-generation notes updated; privacy, release and agent documents require no change.

## 2026-10-11 — Claude Code — Mac release 0.2.8 prep

- Goal: ship #238 (quiet related-mail bar, clearer nb copy) and #237 (glass envelope icons, Smoke default) as Mac `v0.2.8`. iOS TestFlight is Henrik's, from another Mac.
- Changes: marketing version 0.2.7 → 0.2.8 in BrevConstants and both project files (regenerated in a clean env, no other diff); Unreleased entries moved under 0.2.8. Tag `v0.2.8` follows a green PR-event Build on this commit; main is fast-forwarded to it.

## 2026-10-11 — Claude Code — ADR-0088 sign-in code panel (issue #239, Proposed)

- Goal: assess and start issue #239 (floating panel with sign-in codes and links on arrival). The feature reads mail content and has privacy and spoofing implications, so per AGENTS.md this is an ADR-first change.
- Assessment (read-only): feasible as a macOS view-layer feature. Gaps: the arrival hook (`MailEvent.messagesAdded`) is consumed in `BrevMailRootView` and has no age check; new mail has a snippet only, so the body and `Authentication-Results` need a fetch; only DMARC failure is parsed today; no `NSPanel` exists. Closed-window behaviour of the subscription is unverified.
- Change: `ADRs/0088-sign-in-code-and-link-panel.md` (Proposed) and an index row. No code.
- Next: Henrik answers the three open questions and accepts the ADR; then slice 1 (pure detector).

## 2026-10-15 — Agent — PR #241 / issue #239

- Goal: revise the Proposed ADR-0088 for the user-approved review direction without accepting it or implementing the feature.
- Change: record independent per-account/device opt-ins defaulting off, provider-established trusted authentication, the conservative proposed DMARC-only policy, unchanged-message and 60-second defaults, delivery-provenance and cache-persistence limits, panel focus constraints, and deferred iOS notification privacy design. ADR status remains Proposed.
- Merge: merged `origin/main` at `3a553ddbf754a0adb110598dec48108e8a7e8b41`. The only merge conflict was this additive WORKLOG append: kept main's “Mac release 0.2.8 prep” entry and the PR's ADR-0088 history, followed by this handoff. No rebase or force-push.
- Verification: `git diff --check`, `git diff --check --cached`, `scripts/lint.sh`, and `scripts/format.sh` passed in that order; format changed 0/1285 files. App tests/builds and runtime focus/subscription/cache checks are skipped; the PR-specific change remains design-only, and no runtime behavior is claimed.
- Documentation sweep: preserved main's README, CHANGELOG, release and screenshot updates. This PR ships no feature, so it adds no PRIVACY.md or ADR-0006 behavior update; ADR-0088 was already indexed.
- Handoff: Henrik's explicit ADR acceptance and the listed provider-trust, DMARC-policy, provenance, lifecycle and focus evidence gates remain required before implementation.

## 2026-10-15 — Agent — Issue #239 / ADR-0088 acceptance and provider audit

- Goal: continue after Henrik's "design look good - continue", recording acceptance of the revised ADR and checking the first provider-evidence gate before feature code.
- Scope: continued the clean `docs/adr-0088-sign-in-code-panel` worktree/PR #241 targeting `main`; no sibling PR, PR merge, or issue closure.
- Changes: marked ADR-0088 and its index Accepted, including the aligned DMARC-only policy; added a source-linked provider-readiness audit. Both adapters currently discard duplicate authentication results in their body mapping and lack trusted receiving-service provenance. IMAP listing additions and Gmail reconcile diffs lack delivery origin. Gmail's documented timestamp can be selected for migrated mail. None of these facts proves fresh, authenticated delivery.
- Storage/lifecycle: verified ordinary IMAP file-cache and Gmail SQLite body-write paths in source. The SwiftUI-owned event subscription is identified, but closed-window lifetime remains runtime-unverified. No raw private mail or live sign-in contents were accessed.
- Verification: `git diff --check`, `scripts/lint.sh`, and `scripts/format.sh` passed in that order; format changed 0/1285 files (174 skipped). TDD, app builds and runtime checks were skipped because only ADR/index/worklog documentation changed; this audit is not live-provider evidence.
- Documentation sweep: no shipped feature or changed network/storage behavior, so README, CHANGELOG, PRIVACY, ADR-0006, release/QA guides and AGENTS remain unchanged.
- Handoff: provider-dependent implementation is blocked on receiving-service trust and delivery-origin evidence. Do not add an enabling capability, body-read hook or panel based on raw headers. Isolated synthetic provider validation is the next gate; acceptance is not a relaxation of it. GitHub Projects remains inaccessible with the available token; intended design-review status is In review, not Done.

## 2026-10-15 — Agent — Issue #239 / PR #241 isolated detector

- Goal: implement only the provider-independent part of ADR-0088 slice 3, following Henrik's accepted design and parallel-work request. Continued remote branch `docs/adr-0088-sign-in-code-panel` / existing PR #241 targeting `main`; isolated local worktree `/Users/devin/repos/brev-239`, local tracking branch `issue-239-detector`, root verified before edits. PR converted to draft for code WIP.
- Changes: internal pure `SignInCodeDetector` and ephemeral `SignInCandidate` in BrevMail, plus synthetic English/Norwegian Swift Testing fixtures. Conservative explicit-context recognition, 4–8 ASCII code characters, exact HTTPS destination and actual host, exact visible-host comparison, ambiguity and numeric false-positive rejection. Unsupported markup and URL shapes fail closed. Candidate serialization is absent and standard descriptions/reflection are redacted; no production caller, cache, logging, storage, sync, network, body fetch, settings, provider capability, panel or notification was added.
- TDD: added fixtures first; `swift test --package-path packages/BrevMail --filter SignInCodeDetectorTests` failed as expected because the detector was undefined. After implementation and a token-boundary review, the same filter passed: 8 tests / 75 parameterized and standalone cases. `scripts/lint.sh` passed (including strict SwiftLint, coverage self-test and ADR gate); `scripts/format.sh` passed with 0/1287 files changed; whitespace checks passed. Installed the missing mise/pinned tools using the existing documented setup. No effective pre-commit hook was present; its lint checks were run explicitly. Existing `EventModifiers.function` deprecation warning is unrelated.
- Documentation sweep: ADR-0088 now records this isolated status and deliberate grammar limits without changing provider safeguards. README, CHANGELOG, PRIVACY, ADR-0006, release/QA guides and AGENTS remain unchanged: no shipped/user-facing behavior, setup contract, network or persistence behavior changes. No UI strings were introduced; detection fixtures cover EN/NB.
- Skipped: full app builds, full package snapshot suite, live mailbox access and UI testing (no app integration or view changes). Provider trust/fresh-delivery evidence and integration-time candidate lifecycle audits remain required; these synthetic tests prove neither provider eligibility nor server-side link safety. Both adapters remain unsupported for live presentation. The installed daily-driver app and other issues' work were untouched.
- Delivery: reviewed the focused diff and batched one implementation commit/push to the existing draft PR. Workflows were inspected: PR synchronization triggers macOS Build/Lint even for drafts; this unavoidable cost was reported before pushing, with no workflow edits, dispatches or reruns. Stop at the first pushed milestone for parent review; no open-ended CI loop, merge, issue close or Done transition. GitHub Projects again denied access; intended status is In progress → In review.

## 2026-10-15 — Agent — Issue #239 / PR #241 device-local consent model

- Scope: parent explicitly authorized the independent model-only part of ADR-0088 slice 4 and one batched push. Verified isolated worktree `/Users/devin/repos/brev-239`, local branch `issue-239-detector`, and matching local/remote head `5b7ec71`; continuing `docs/adr-0088-sign-in-code-panel` targeting `main`. Detector and its 75-case milestone are unchanged.
- Changes: `SignInCodeSettings` stores independent code/link booleans per stable account ID in supplied local UserDefaults only. Both default off with no global enable; malformed or mismatched records fail closed. Explicit removal deletes persisted consent, including the key when empty. Fixed constants leave messages unchanged and specify a 60-second timeout. No settings-store, lifecycle, detector, UI, provider, body-fetch, network or notification integration; consent never establishes eligibility.
- Verification: tests written first; focused red failed on the absent model (and a missing test-only import, subsequently corrected). `swift test --package-path packages/BrevSettings --filter 'SignInCodeSettings|BackupTests|PreferenceSync'` passed 40 tests in 4 suites, covering new consent tests, existing backup tests and preference-sync suites. New tests prove independent toggles, account isolation, injected persistence, malformed-data off, stored deletion, backup export exclusion, non-enabling/non-overwriting import in merge and replace modes, and cloud allowlist exclusion. `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` passed after a test-only formatting fix; `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` changed 0/1289 files; `git diff --check` passed. No installed pre-commit hook; lint ran explicitly.
- Documentation sweep: updated ADR-0088 implementation status; no backup payload or cloud allowlist changes. README, CHANGELOG, PRIVACY, ADR-0006, QA/release docs and AGENTS remain unchanged because no shipped behavior, UI, network flow or candidate storage was added. The isolated model's consent-only persistence is documented here and in ADR-0088; integration-time privacy disclosures remain required before shipping. No user-visible strings introduced.
- Recovery/reverification: after a tool/runtime error the unstaged consent files, ADR edits and test cache disappeared without a Git head change; cause unconfirmed. Restored the reviewed contents and repeated checks. Dependency-mirror authentication blocked the unmodified test command before build; the cache-backed equivalent `swift test --skip-update --package-path packages/BrevSettings --filter 'SignInCodeSettings|BackupTests|PreferenceSync'` passed the same 40 tests in 4 suites. Lint, format (zero changes), unstaged and staged whitespace checks passed again. No implementation changes were needed.
- Handoff: no detector rerun (untouched), full app/native runtime or live-provider tests (no integration), servers, workflow reruns or dispatches. Both providers remain unsupported; receiving-service trust, fresh delivery, body-cache/lifecycle audits, UI and app wiring remain blocked/deferred. One push only, then stop without CI watch or PR description changes (parent owns review/update). No merge, closure or Done transition; board access previously denied, intended status In review. Future paid macOS-triggering pushes require explicit approval, not merely a warning.

## 2026-10-15 — Agent — #11 / #3 PIM parity evidence v2

- Goal: reconcile genuine Calendar/Contacts acceptance gaps without rebuilding
  #3, duplicating #239/#14, or implementing Proposed ADR-0084.
- Changes: added `docs/qa/pim-parity-v2-2026-10-15.md`; preserved the canonical
  matrix and prior artifacts. Separates fresh automated results from inherited
  stub/macOS/iOS evidence, live-provider gates and maintainer acceptance;
  supplies exact isolated runtime plans and credential references, never values.
  No new reproducible code defect established; documentation-only TDD exception.
- Verification on base `3a553ddbf754a0adb110598dec48108e8a7e8b41`:
  BrevCalendar 264 tests/26 suites; focused BrevMail PIM scheduler/RSVP/hint
  22 tests/3 suites; focused BrevSettings PIM model/row/DAV form 41 tests/3
  suites. All exited 0. `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh`,
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 formatted), and
  `scripts/privacy-audit.sh` passed. Exact filters/tool versions in the report.
- Skipped: UI, live Google/DAV CRUD, macOS timed-idle pickup, physical iPhone,
  full app/release builds and unrelated snapshots: no UI/live approval and
  dedicated fixture/signing/device acceptance remains outstanding. No snapshot
  baselines changed. Existing iOS stub 2.7/2.8/4.3 not needlessly repeated.
- Documentation sweep: QA and this log only; no product, privacy/network,
  architecture, release/version, or agent-policy change requiring other docs.
- Handoff: `fix/pim-parity-gaps` targets `main`; stop after first batch push.
  Draft PR held for parent cost direction because every PR triggers macOS
  Build/Lint, unlike feature-branch pushes. Board access denied; intended
  evidence-handoff state In review, never Done. #3/#11 stay open pending
  provider/platform evidence and Henrik's sign-off. No merge/release requested.

## 2026-10-15 — Agent — #11 / PR #245 PIM parity runtime v3

- Goal: resume approved isolated runtime acceptance without product edits.
- Added `docs/qa/pim-parity-v3-2026-10-15.md`; preserved prior evidence.
  Fresh iOS 27 simulator and owned local DAV fixtures established.
- Runtime: event/contact search and same-process offline cached reads worked;
  All Events conditional save worked. Stopped at first product defect:
  This and Future Events on the first occurrence leaves duplicate rows and
  an old series with UNTIL before DTSTART, persisting after manual sync.
  Recording, screenshots, redacted logs and cache evidence retained outside
  the checkout; portable screenshot URLs are embedded in the v3 report.
- Blocked: macOS no-launch app-group isolation preflight; no signing identity
  for persistent-Keychain proof; no safe live Google attempt or dedicated DAV
  credentials. Remaining recovery/localization/accessibility rows stopped for
  the defect; no physical iPhone or live-provider acceptance claim.
- No product/source/entitlement changes. Settled 327-test automated evidence
  was not rerun. Validation passed once with
  `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted);
  `git diff --check` passed before delivery.
- Delivery: committed as `docs(qa): record isolated PIM runtime acceptance
  findings` and pushed once to `origin/fix/pim-parity-gaps` for PR #245. No PR
  edits/comments, CI dispatch/watch, issue closure or release. Parent decides
  the proposed first-occurrence boundary fix and next runtime scope.
- Documentation sweep: QA and worklog only; no product, privacy, architecture,
  release/version or agent-policy change. Owned app/stub remain running;
  exact PIDs, UDID, port and paths are in the report.

## 2026-10-15 — Agent — #11 / PR #245 recurrence boundary correction

- Goal: address the first-occurrence duplicate reproduced in v3 without
  replacing historical evidence or changing provider/network boundaries.
- Changes: keep the original event in the editor draft; use the ordinary
  series update/move path when truncation would precede its start. For a
  later split, retain the unedited original master rather than applying
  the new series' title and dates to past occurrences. Added first-boundary
  and original-field regression assertions.
- Verification: the new first-occurrence regression failed against HEAD
  source with three expected issues (split/update count, recurrence count,
  and saved identity); after restoring the authored sources byte-for-byte,
  the two future-scope tests passed and the combined editing/draft suites
  passed (22 tests). `scripts/format.sh` formatted 0/1285 files (175
  skipped); `scripts/lint.sh` passed.
- Not verified: UI, live-provider, macOS isolation, recurrence expansion,
  and future-scope deletion. These remain outside this verification; no
  runtime acceptance is claimed.
- Documentation sweep: CHANGELOG and ADR-0072 reflect the behavior fix;
  v3 only corrects publication/access wording and retains its failure
  evidence. No views, strings, privacy/network calls, schema, signing,
  README setup or release settings changed. Other recurrence behaviors,
  including future-scope deletion, require separate verification.

## 2026-10-15 — Agent — #11 / PR #245 PIM runtime retest v4

- Goal: execute the exact approved first-occurrence regression at
  `9cb1cd9737ea69dc7068b70e39f42bab749dbe89`, then independent iOS/stub rows.
- Rebuilt BrevIOS for the existing owned iOS 27 simulator, preserved v3
  failing server/cache records separately, and reseeded the exact original
  series. Reconnected process-only mock credentials. Stub cursor expiry/full
  sync established one server/cache/list record before recording.
- Runtime: title edit → All Events → title edit → This and Future Events
  with dates unchanged → explicit sync passed. One record, original UID/key
  and UTC dates, COUNT=5, no UNTIL; both writes were conditional PUT 204.
- Stopped independent continuation at a newly reproduced populated AX3
  event-detail layout defect: fixed horizontal actions fragment Delete and
  Copy Link into narrow multiline labels. Default Large restores the normal
  row; AX3 reproduces. Proposed adaptive action layout requires parent review;
  no product edits made by the runner.
- Added `docs/qa/pim-parity-v4-2026-10-15.md` with exact identity proof,
  primary annotated recording, screenshot comparison, gaps and reusable
  processes. Devin attachments require session access; they are not public
  or portable GitHub embeds. Historical v2/v3 evidence remains intact.
- Remaining NB/Contacts/reduced-motion/VoiceOver/source-failure/cache-removal
  rows paused under the first-defect rule. No macOS launch, live-provider
  retry, signed-Keychain or physical-device claim. Settled automated and
  parent focused checks inherited rather than rerun.
- Publication: the runtime runner did not run repository lint/format/diff
  checks or commit/push; its runtime checks are reported above. This
  publication phase passed `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
  `git diff --check`. One documentation-only commit,
  `docs(qa): record recurrence retest and accessibility findings`, was pushed
  once to `origin fix/pim-parity-gaps`. Tested source revision
  `9cb1cd9737ea69dc7068b70e39f42bab749dbe89` is distinct from the publication
  commit; no CI was dispatched or watched. App PID 7682 and stub PID
  5246/port 18643 remain running; owned simulator is left English/dark/AX3.
- Documentation sweep: QA and worklog only; no product/privacy/architecture/
  release/agent-policy change or new skill/blueprint edits. Parent decides
  the AX3 proposal and resumption; #11/#3 remain acceptance-gated.

## 2026-10-15 — Agent — #11 / PR #245 adaptive Calendar actions

- Goal: correct the v4 iOS AX3 action-label wrapping without shrinking text.
- Changes: Calendar detail measures its action row at ideal width and falls
  back to leading-aligned vertical actions when it does not fit. Button
  handlers, localization, roles and accessibility grouping are unchanged.
  Added narrow-width light/dark snapshots in the existing Calendar suite.
- Verification: `RECORD_SNAPSHOTS=YES swift test --package-path packages/BrevMail
  --filter CalendarBrowsingSnapshotTests.eventDetailNarrowActions` recorded
  only the new dark/light references (record mode emitted its expected
  notices); the same focused test without recording passed both cases.
  `scripts/format.sh` formatted 0/1285 files (176 skipped);
  `scripts/lint.sh` passed. Historical v4 failure evidence remains intact.
- Not verified: no runtime retest, app launch, UI driving, simulator use, or
  broad suite was run on this worktree. The iOS AX3 retest remains assigned
  to the isolated child after review of this pushed change.
- Documentation sweep: CHANGELOG and WORKLOG updated. No new view API,
  theme token, architecture, provider call, persistence, privacy, setup or
  release behavior; README, ADRs, PRIVACY and AGENTS need no change.

## 2026-10-15 — Agent — #11 / PR #245 PIM runtime retest v5

- Goal: retest the approved adaptive Calendar action layout at
  `bbe06d81b50ad19dc49169cab951f42d5a91ba6f`, then collect a bounded independent
  populated Calendar/Contacts batch under the revised stop policy.
- Rebuilt/installed only on owned simulator
  `0AAE0F16-6167-435E-884F-C0BA50E05A67`, reused original stub PID 5246/18643,
  and reconnected process-local mock credentials. Same writable event and all
  three actions were verified before comparison. No recurrence retest.
- Calendar actions passed EN light/dark Large and AX3, plus NB light/dark AX3:
  full scaled labels and preserved order. Edit/cancel, safe deletion-dialog
  dismissal and copied-link identity passed without provider mutation. An
  explicit Cancel button was not visible in the AX3 popover. Final original
  event and two contact payloads match their pre-v5 copies.
- Continued independent EN/NB/light/dark/Large/AX3 lists, details and editors.
  Collected Contacts AX3 action fragmentation and NB standard TYPE=WORK
  rendering as English "Work"; no product fixes made. Reduced Motion is
  preference readback plus functional navigation only; complete AX traversal
  and actual VoiceOver spoken readback remain unverified.
- A separate owned CardDAV source on 18644 failed as induced without blocking
  healthy Calendar sync/read, then recovered through Sync Now. After preserving
  state, "remove, keep cached copy" left Charlie byte-identical on disk but
  inaccessible in list and exact-ID deep link. Froze that mutation flow;
  delete-cache removal was not executed. No secondary PUT/DELETE/POST.
- Added `docs/qa/pim-parity-v5-2026-10-15.md`, one primary annotated recording
  and session-access-only screenshot links. v2/v3/v4 evidence remains intact;
  no binary artifacts tracked. Remaining live-provider/macOS isolation/signing/
  physical-device/acceptance gates are unchanged; no auth retries or Drive work.
- Handoff: app PID 12451, original stub 5246/18643 and secondary stub 15161/18644
  remain running. NB/dark/AX3 original writable Calendar detail is visible;
  Reduce Motion preference On, VoiceOver Off. Keep the removed source's
  preserved cache/server for review; credentials are process-only.
- Publication: runtime runner did not run repository lint/format/diff checks or
  commit/push; its runtime results and bounded findings are reported above.
  Subsequent publication passed `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
  `git diff --check`. One documentation-only commit,
  `docs(qa): record PIM accessibility and cache acceptance findings`, was
  pushed once to `origin fix/pim-parity-gaps`. Tested source revision
  `bbe06d81b50ad19dc49169cab951f42d5a91ba6f` remains distinct from the
  evidence-only publication commit. No PR comments/edits, CI dispatch/watch,
  issue closure or merge in this publication.
- Documentation sweep: v5 QA and appended worklog only; no product/privacy/
  architecture/release change, no new skill/blueprint edits or proposals.
  Parent review of the three independent findings and remaining acceptance
  gates is required; #11/#3 remain open.

## 2026-10-15 — Agent — #11 / PR #245 retained-cache browsing

- Goal: preserve access to explicitly retained, disconnected PIM caches after
  source removal without restoring active source metadata, credentials,
  consent, provider connectivity, synchronization, or write capability.
- Changes: added marker-based per-kind retained-cache discovery and
  registered-source exclusion; wired active-first, duplicate-free cache
  loading, localized disconnected-source failures, stale banners, and
  active-source-only sync guards across Contacts, Calendar, and Tasks.
  Added focused source-store, coordinator, and browsing-model coverage.
  Contacts actions now use the authored adaptive narrow-width layout and
  standard labels localize while arbitrary labels remain unchanged. The
  duplicate `Other` catalog entry was removed while preserving the
  pre-existing translation. ADR-0072 and CHANGELOG were updated.
- Verification:
  `swift test --package-path packages/BrevCalendar --filter
  'PIMSource(Coordinator|Store)Tests'` passed 22 tests in 2 suites.
  `swift test --package-path packages/BrevMail --filter
  '(ContactsBrowsingModelTests|CalendarBrowsingModelTests|TasksBrowsingModelTests|ContactPresentationTests|ContactsEditingModelTests)'`
  passed 71 tests in 5 suites; after adding the absent-source editability
  assertion, `swift test --package-path packages/BrevMail --filter
  'ContactsEditingModelTests'` passed 9 tests in 1 suite.
  After changing the file-backed regression to use a fresh contact store
  after source removal, `swift test --package-path packages/BrevMail
  --filter 'ContactsBrowsingModelTests'` passed 18 tests in 1 suite.
  `RECORD_SNAPSHOTS=YES swift test --package-path packages/BrevMail
  --filter 'ContactsBrowsingSnapshotTests/contactDetailNarrowActions'`
  recorded only the new light/dark references and exited 1 on the two
  expected record-mode notices. The same command without recording passed
  both snapshot cases. Generated:
  `packages/BrevMail/Tests/BrevMailTests/__Snapshots__/ContactsBrowsingSnapshotTests/contactDetailNarrowActions-mode.detail-narrow-actions-light.png`
  and
  `packages/BrevMail/Tests/BrevMailTests/__Snapshots__/ContactsBrowsingSnapshotTests/contactDetailNarrowActions-mode.detail-narrow-actions-dark.png`.
  The first lint run identified SwiftFormat await-hoisting issues, which
  were corrected; the final `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh`
  passed, including SwiftLint coverage and ADR checks.
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` passed after the corrections,
  formatting 3 of 1,285 files; the final format run changed 0 of 1,285
  files, and SwiftFormat lint found 0 files requiring formatting.
  `git diff --check` passed after the final worklog update.
- TDD limitation: the layout and source-store API edits were authored before
  this test pass; the retained-cache model and coordinator coverage was added
  afterward. No provider network traffic, app launch, simulator/UI runtime
  retest, or broad runtime QA was performed. Full package gates remain
  optional final checks only.
- Documentation sweep: README and PRIVACY were left unchanged because this
  implements the existing ADR-0072 cache lifecycle without changing privacy
  posture, setup, or provider network behavior. Remaining acceptance gates
  are the parent review, snapshot pixel review, and isolated runtime QA.

## 2026-10-15 — Agent — #11 / PR #245 bounded v6 runtime evidence

- Goal: retest the approved Contacts actions/localization/retained-cache delta
  at `3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f`, using the original frozen
  v5 Charlie fixture without reconnecting/recreating/deleting it.
- Changes: new `docs/qa/pim-parity-v6-2026-10-15.md` and this append only.
  Earlier reports/artifacts preserved. No product edits or source revision
  change. Evidence links require originating-session access, not public or
  portable GitHub embeds.
- Runtime: targeted owned iOS simulator rebuild/install; preflight and
  post-install comparison proved frozen cache/marker identity preserved.
  Original list/exact-link reads and read-only capabilities passed, with zero
  frozen-source requests from 19:17:45 to 19:49:58 UTC. Contacts EN/NB
  light/dark AX3 labels/order/scaling passed. Edit canceled; deletion popover
  safely dismissed; initial immediate-copy assertion retained the prior link,
  then one settled retry matched Alice. Original active contact cache unchanged.
  No visible explicit Cancel or standalone disconnected-detail notice claimed.
- Distinct source `pim-247b38a5-71ed-4cd5-9999-44d22e7faa53`, port 18645:
  NB WORK displayed Arbeid and custom qa-lab stayed unchanged. UI delete-cache
  removal eliminated only Delta's local source/cache; its exact link showed
  the localized missing notice. Charlie remained reachable and byte-identical.
  Both remote payloads remained unchanged; no remote PUT/DELETE.
- Inherited parent report, not this runner's execution: CI 21/21 passed and
  full BrevCalendar 266 tests/26 suites passed; full local BrevMail 2194
  tests/331 suites failed with 89 snapshot mismatches across
  Login/Compose/Mail Context/Local Folders/PIM. CI snapshots reportedly passed
  the same SHA. Host drift is only a hypothesis, not base-verified; do not
  claim a full local pass. No broad rerun.
- Limits: no existing retained Calendar/Tasks fixtures, so optional smoke not
  manufactured. AX bridge unavailable; no spoken VoiceOver or fresh motion
  claim. Final motion/VoiceOver preferences both read 0. macOS, live providers,
  signed-Keychain persistence and physical iPhone remain acceptance gates.
  Recurrence and prior settled runtime/checks were not rerun.
- Handoff: app PID 24123, stubs 5246:18643 / 15161:18644 / 23594:18645 left
  running on owned simulator 0AAE0F16-6167-435E-884F-C0BA50E05A67, NB/dark/AX3,
  original Charlie detail. Preserve the frozen fixture. Primary recording:
  `/Users/devin/screencasts/pim-v6-ios-primary/pim-v6-ios-primary-edited.mp4`;
  exact manifests/screenshots under
  `/Users/devin/pim-parity-evidence/v6-20261015-a/`.
- Publication: runtime runner did not run repository lint/format/diff checks
  or commit/push; parent-reported automated results and limitations above were
  not rerun or independently verified here. Subsequent publication passed
  `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
  `git diff --check`. One documentation-only commit,
  `docs(qa): record retained cache and contacts runtime verification`, was
  pushed once to `origin fix/pim-parity-gaps`. Tested source revision
  `3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f` remains distinct from the
  evidence-only publication commit. No CI dispatch/watch, PR/issue actions,
  merges or releases. Documentation sweep: QA/worklog only; no product/privacy/
  architecture/release change, no new blueprint/skill edits or proposals.
  #11/#3 remain acceptance-gated.

## 2026-10-15 — Agent — #11 / PR #245 bounded v7 runtime evidence

- Goal: execute the approved still-open recurrence and Calendar/Tasks retained
  cache cases at HEAD `3a784926563571a59e60b552ce4e7cf6180436d9`, product
  unchanged from v6 `3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f`.
  Reused app/simulator; no rebuild, reinstall, product or harness edits.
- Changes: new `docs/qa/pim-parity-v7-2026-10-15.md` and this append only.
  All v2-v6 evidence preserved. New distinct synthetic sources on ports
  18646–18649 used existing DAV/VTODO support; no external providers.
- Runtime failure: distinct daily COUNT5 masters appeared October 16, but
  October 18 day grid was empty; actual third occurrences were unreachable.
  Later future edit/delete stopped before any mutation. No DTSTART workaround.
  Proposed narrow parent-review scope: bounded recurrence projection and
  occurrence-aware selection; no split/count correctness claim or product fix.
- Independent runtime: Calendar and Tasks keep-cache list/exact-link reads
  passed read-only. Active Settings/registry excluded them; markers/cache
  remained, cursors absent, Tasks toggles/sync inert. Separate delete-cache
  fixtures removed only local state; missing exact links verified, remote
  payloads unchanged, retained keep links still readable. First deleted Tasks
  presentation lacked a captured notice; repeat showed the localized notice.
  Source-specific measured removal/read windows had zero requests; all new
  logs had zero PUT/DELETE. Diagnostic GETs attributed separately.
- AX3: Edit text aligned behind native back chrome did not activate; the tap
  scrolled to top. After scrolling clear, Edit opened and canceled normally.
  No persistent untappable overlap reproduced. All prior cache bytes/mtimes,
  registry and frozen Charlie provider payload preserved. No VoiceOver speech,
  full AX traversal or fresh motion claim.
- Limits/inherited: later-scope mutation QA remains blocked. No broad suites,
  settled Contacts/first-boundary/Copy Link retests, live-provider auth, macOS
  launch, signed-Keychain persistence or physical-device evidence. Parent
  reports automatic CI 20 pass/0 fail/0 pending/1 snapshot skip; not rerun.
  Prior local snapshot mismatches remain unresolved; host drift not proven.
- Evidence: `/Users/devin/pim-parity-evidence/v7-20261015-a/`, including exact
  identities/payload hashes/request windows and `final-evidence.json`; single
  annotated recording
  `/Users/devin/screencasts/pim-v7-ios-primary/pim-v7-ios-primary-edited.mp4`.
  Attachment links require session access, not public/portable GitHub embeds.
- Reusable state: app 24123; prior stubs 5246:18643 / 15161:18644 /
  23594:18645; new stubs 30916:18646 / 30925:18647 / 30946:18648 /
  30955:18649. Owned simulator 0AAE0F16-6167-435E-884F-C0BA50E05A67,
  NB/dark/AX3, original Alice after cancellation. Keep Charlie and new retained
  caches frozen; new delete-source provider payloads remain on their stubs.
- Publication: the bounded runtime procedure above is complete at approved
  checkout HEAD `3a784926563571a59e60b552ce4e7cf6180436d9`, using unchanged
  product revision `3dc2986a2b1ae9b0a20dc4c5be0e7f26439ac83f`; no product change
  was made. The runtime runner did not run repository publication
  lint/format/diff checks or commit/push. This documentation-only publication
  passed `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` and
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1,285 files formatted), and
  `git diff --check`. One documentation-only commit,
  `docs(qa): record bounded v7 recurrence and retained-cache evidence`, was
  pushed once to `origin fix/pim-parity-gaps`. No tests were rerun for
  publication; TDD was skipped as docs-only. No CI dispatch/watch, PR/issue
  actions, merge, release or Done transition. Documentation sweep: QA/worklog
  only; no product/privacy/architecture changes or new blueprint/skill edits.
  Parent decision needed before recurrence implementation; #11/#3 remain
  acceptance-gated.

## 2026-10-15 — Devin — #14 Drive attachment acceptance gaps

- Goal: close reproduced transport gaps in the existing Drive implementation, not rebuild #77/#78 or configuration repair #161. Isolated worktree/branch `fix/drive-acceptance-gaps`, based on `origin/main` at `3a553dd`; target `main`.
- TDD: multipart create/update structure and native cancellation assertions failed; cancel-then-retry through the production upload transport crashed because its session was invalidated. All reproduction used synthetic data and injected transports/URLProtocol, not Google.
- Changes: CRLF before multipart content boundaries; preserve native cancellation; one ephemeral upload session and immutable progress delegate per operation with explicit session cleanup. Narrow `drive.file`, UI, calendar/contact features and configuration unchanged.
- Verification: BrevBackend GoogleDrive filter passed (12 tests, 2 suites); BrevMail GoogleDrive filter passed (16 tests, 3 suites); `scripts/format.sh` passed (0/1285 files formatted, 174 skipped); `scripts/lint.sh` passed (SwiftFormat lint, SwiftLint strict, coverage self-test, ADR check); `git diff --check` passed. The first format attempt found `mise` absent; installed it and the pinned project tools, then reran format and lint successfully. UI and live Google checks were intentionally skipped per scope; see the explicit limitations below.
- Not verified: authenticated macOS/iOS Picker, attach/save/export/referrer/error/revoke/offline/remote cleanup. UI testing needs explicit approval, approved disposable-account access and private Picker configuration; no login challenge bypass attempted.
- Docs sweep: Unreleased CHANGELOG and new `docs/qa/drive-attachments-acceptance-v2-2026-10-15.md` updated; README, privacy/ADR-0006, ADR-0072, AGENTS and release docs unchanged because feature/architecture/privacy/workflow boundaries did not change.
- Handoff: stop at first push; opening even a draft PR triggers macOS CI and is held for cost authorization. Project token denied access; intended status after verified push is In review, not Done. No merge, issue close, release or version change.

## 2026-10-15 — Devin — #14 calendar Drive attachment save (PR #244)

- Goal: add a user-initiated way to save a supported Drive-linked calendar event attachment into a selected Drive folder without changing event persistence or contacting arbitrary URLs.
- Changes: strict Drive URL parsing, source/account-qualified event save and Picker authorization, metadata-verified download/export, shared conflict/upload model with source-file overwrite protection, localized detail action and save sheet, and new synthetic model/snapshot coverage. Privacy, ADR-0006, ADR-0072, CHANGELOG and versioned QA evidence updated; v2 evidence preserved.
- TDD red run: new focused tests initially failed because the new save-model types did not yet exist; persisted at `/Users/devin/Library/Logs/brev-drive-calendar-save-red-20261015.log`.
- Verification: focused BrevMail tests passed (15 tests/2 suites for the new models; 31 tests/5 suites for all GoogleDrive tests); BrevBackend GoogleDrive passed (12 tests/2 suites, rerun after formatting). New light/dark save-action snapshots passed; four existing agenda/detail references mismatched in the full snapshot run. Their cause is unverified and all unrelated baselines were preserved. Format passed (4/1290 files formatted; 175 skipped) and lint passed (SwiftFormat, SwiftLint strict, coverage self-test, ADR check). `git diff --check` passed.
- Not verified: live Google, app launch, or interactive runtime/UI testing; all remained on hold. No calendar writer or persistent Drive file-ID schema added.

## 2026-10-15 — Devin — PR #244 Drive event-save correction batch

- Goal: address the reviewed lifecycle, payload-retention, source-eligibility, Picker-authorization, error-privacy, MIME, and documentation gaps without committing or pushing before parent review.
- Changes: operation identity and cancellation checks are enforced across async phases; terminal cancellation clears the shared staged payload and prevents restart; retryable upload errors return to Picker; source-qualified eligibility and Picker authorization remain model-tested. Restored global Workspace MIME semantics and retained event-only format restrictions. Corrected ADR-0006's Drive API row and updated v3 evidence.
- Red/repair evidence: before the conflict fix, the real pick → conflict → Replace regression timed out with zero replacement uploads and uncleared payload bytes; it now passes for both Replace and Keep Both even when cancellation is attempted immediately. The first runnable correction suite also exposed an upload-error state that remained `.uploading`; the model now returns to a retryable Picker state. A source-invalidation assertion was aligned with the model's cancellation outcome. Other correction regressions were not all separately run against the pre-correction tree.
- Verification: the final focused save/event filter passed (28 tests/2 suites); `CalendarDriveSaveEligibility` passed (6 tests/1 suite); the targeted snapshot filter passed 2 tests across all 4 read-only/unavailable light/dark cases. Earlier correction runs passed BrevMail GoogleDrive (43 tests/5 suites) and BrevBackend GoogleDrive (13 tests/2 suites); BrevBackend was unchanged and not rerun. Final `scripts/format.sh` passed (0/1294 files formatted; 175 skipped); `scripts/lint.sh` passed (SwiftFormat lint, SwiftLint strict, coverage self-test, ADR check); `git diff --check` passed.
- Not verified: no CI, app launch, or runtime/UI/live-provider testing, per scope. The four existing agenda/detail snapshot mismatches remain with cause unverified; unrelated baselines were preserved.
- Handoff: one correction commit/push to existing PR #244 is authorized; the parent owns the next review, CI, and QA steps. No second commit is needed to record the push SHA.

## 2026-10-15 — Devin — PR #244 Picker-failure retry correction

- Goal: prevent Picker initialization errors from automatically recreating a failed Picker.
- Changes: event Picker failures now cancel the current operation, clear staged/preparation authorization state, and return to intent with a generic error; shared save Picker failures enter an explicit Retry phase, clear Picker credentials, and retain the staged payload. Retry starts a fresh operation; stale Picker callbacks are ignored.
- Red evidence: before the fix, the two new tests produced 10 assertion failures: the event flow remained in `.picking` with a new token and retained payload, and the shared flow retained its Picker token.
- Verification: `swift test --package-path packages/BrevMail --filter CalendarDriveSaveEligibility` passed (7 tests/1 suite); `swift test --package-path packages/BrevMail --filter GoogleDrive` passed (47 tests/6 suites); `swift test --package-path packages/BrevMail --filter 'CalendarBrowsingSnapshotTests/eventDetailDriveSave'` passed (2 tests/1 suite, all 4 light/dark cases). The earlier focused save/retry filter passed (30 tests/3 suites); final broad GoogleDrive run reran these suites. `scripts/format.sh` passed (0/1294 files formatted; 175 skipped); `scripts/lint.sh` passed (SwiftFormat lint, SwiftLint strict, coverage self-test, ADR check); `git diff --check` passed. BrevBackend GoogleDrive remains at its previously verified 13 tests/2 suites and was not rerun because it is unchanged.
- Not verified: full snapshots, CI, app launch, or runtime/UI/live-provider testing; the four existing agenda/detail snapshot mismatches remain with cause unverified, and unrelated baselines were preserved.
- Handoff: one correction commit/push to existing PR #244 is authorized; the parent owns the next review, CI, and QA steps. No second commit is needed to record the push SHA.

## 2026-10-15 — Devin — PR #244 follow-up review nits

- Goal: apply the three small, authorized follow-up corrections without changing the reviewed save implementation.
- Changes: added the Norwegian translation for the save-preparation retry message, corrected the v3 focused-test filter, and made both event-save wait helpers record timeout failures.
- Verification: `swift test --package-path packages/BrevMail --filter 'GoogleDrivePickerFailureRetry|GoogleDriveEventSave|GoogleDriveSave'` passed (30 tests/3 suites); the catalog JSON parsed and the exact Norwegian value was asserted; `scripts/format.sh` passed (0/1294 files formatted; 175 skipped); `scripts/lint.sh` passed (SwiftFormat lint, SwiftLint strict, coverage self-test, ADR check); `git diff --check` passed after this log entry.
- Scope exclusions: no full suites, BrevBackend tests, snapshots, CI, UI/runtime, or live-provider testing were run.
- Handoff: one follow-up commit containing these four paths is authorized for the existing PR branch; the parent owns the subsequent CI and QA steps.

## 2026-10-15 — Devin — #14 / PR #244 bounded runtime evidence v4

- Goal: establish safe authentic Drive QA prerequisites at `0f10db03ea930859e7b3fae691fc1c37087e944d`, then test only reachable isolated states.
- Verification: built and ran the pinned iOS Debug app in a fresh owned simulator with synthetic loopback CalDAV data. Verified an actual read-only, unlinked source shows both attachment links without Save in EN/NB, including reselection and large-text reachability. Local event bytes were unchanged and no DAV PUT/DELETE occurred. Evidence is synthetic-native only; native AX/VoiceOver semantics were not verified.
- Blocked: Picker API key/app ID are unavailable; dedicated Google credentials were not exercised and no eligible Google-linked source/real file fixtures were established. All positive provider save/export/conflict/cancel/retry and denial/revocation/offline rows remain blocked. macOS was not launched because genuine App Group isolation is unavailable.
- Changes: new v4 evidence report; v2/v3 and production sources preserved. No package/backend/snapshot suites were rerun for this docs-only update (TDD not applicable). Prior automated results remain separate evidence.
- Documentation sweep: README, CHANGELOG, privacy, ADRs and AGENTS need no change for this evidence-only update. Runtime skill safety corrections require a separate approved follow-up; blueprint safety guidance is proposed through its approval flow.
- Handoff: one docs-only push to existing PR #244; parent owns review, CI and future QA. No merge, issue closure, Done transition, release or workflow dispatch. Owned simulator and local fixture server remain available; reconnect the synthetic source before additional sync after locale relaunch.

## 2026-10-15 — Devin — #14 / PR #244 frozen diagnosis and evidence v5

- Goal: persist the accepted base/head snapshot diagnosis and finish the two remaining bounded automated checks; preserve v2–v4 and production code.
- Frozen evidence: base `3a553ddbf754a0adb110598dec48108e8a7e8b41` and PR `663607645ac29a87abb7a1ecee08af25811d59f5` produced byte-identical images for all four old agenda/detail cases. Locale/time-zone-sensitive references and the pre-existing Copy Link row explain visible discrepancies; no Drive regression indicated. Two synthetic OAuth callback checks passed. These accepted results were not rerun or rederived. Original raw artifacts became unavailable after inspection; v5 retains that caveat and frozen hashes rather than claiming a retained archive.
- New checks at `6636076`: BrevMail `--filter 'ComposeNativeSheetsSnapshotTests/driveSheetChrome'` ran zero tests because the suite requires UIKit, so its structural snapshot remains unverified. BrevBackend `--filter 'OAuthTokenRefresherTests/permanentRefreshFailureRequiresSignIn'` passed (1 test/1 suite). Both commands ran once with snapshot recording disabled; no platform bootstrap or runtime launch.
- Repository checks: passed — `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` (SwiftFormat: 0/1294 files required formatting; SwiftLint strict, coverage self-test and ADR check passed), `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` (0/1294 files formatted), and `git diff --check`.
- Documentation sweep: new v5 report and this entry only; no README, CHANGELOG, privacy/ADR, AGENTS or release change is warranted for frozen/new test evidence. TDD is not applicable to this docs-only update. Provider configuration/disposable access, positive runtime/remote outcomes, real macOS isolation, iOS/AX coverage and maintainer acceptance remain open.
- Handoff: one Conventional Commit/push to the existing branch, then stop for parent review. No old snapshot repair, full-suite rerun, CI watch/dispatch, PR edit, merge, closure, Done transition or release.

## 2026-10-15 — Agent — PR #241 main integration

- Goal: integrate reviewed sign-in branch `b356355` with approved `main` `7117491`.
- Merge: fast-forwarded from `fbcb2cd` to `b356355`, then merged `main` with `--no-ff`. The only conflict was the additive WORKLOG append; preserved sign-in and main/Drive histories verbatim. No other manual edits.
- Verification: BrevSettings focused filter passed (40 tests/4 suites); BrevMail `SignInCodeDetectorTests` passed (8 tests/1 suite); `bash scripts/test-release-dmg.sh` passed once for stable and nightly artifacts (stapler/Gatekeeper checks skipped by the script); lint passed; format changed 0/1298 files; `git diff --check` passed.
- Limits: no broad suites, app/runtime checks, or CI watch. The prior intermittent CI DMG negative-fixture failure remains unexplained; this local pass does not establish its cause.
- Handoff: parent owns PR description and post-push CI follow-up.

## 2026-10-15 — Devin — #11 / ADR-0089 bounded recurrence design

- Goal: publish the bounded recurrence design Henrik explicitly approved,
  in a separate ADR-only draft PR targeting `main`.
- Changes: ADR-0089 and its index entry record a lossless eligibility
  descriptor, bounded local projection, explicit unsupported/incomplete
  coverage, stable occurrence/master separation and separately verified
  future-scope writes. ADR-0088 remains reserved in PR #241.
- Evidence: v7 on PR #245 reproduced missing later COUNT5 occurrences;
  source review confirmed raw-record-only browsing and a summary-only,
  lossy recurrence parser. No implementation or additional runtime evidence
  is claimed by this design.
- Verification: `git diff --check`, local ADR-link/index validation,
  `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh`, and
  `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` passed (SwiftFormat lint:
  0/1294 files require formatting; format: 0/1294 files formatted;
  SwiftLint strict, coverage self-test and ADR check passed). TDD,
  package suites, builds and UI testing were not run because this is an
  ADR-only change.
- Documentation sweep: ADR/index/worklog only. No product, setup, privacy,
  network, release or workflow change; README, CHANGELOG, PRIVACY and AGENTS
  need no update. Existing QA evidence and fixtures remain untouched.
- Handoff: design accepted; draft PR and its automatic CI authorized.
  No implementation, merge, issue closure, Done transition or release.

## 2026-10-16 — Agent — PR #241 accepted ADR-0089 integration

- Goal: integrate approved `main` `effa78b` into the sign-in branch at `c3d38ab`; this is a docs-only integration, not a design or implementation change.
- Merge: resolved only `ADRs/README.md` and `WORKLOG.md`. Kept Accepted ADR-0088 and ADR-0089 rows in ascending order and removed the obsolete ADR-0088 reservation note. Preserved both existing Worklog histories; ADR-0089 remains byte-identical to `main`. All non-document files match `c3d38ab` and the lead-reviewed merge tree `22c844d`.
- Verification: local links in ADR-0088, ADR-0089 and the index passed; all 89 ADR rows are unique and ascending. `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` passed (0/1298 files formatted); `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` passed (0/1298 files require formatting; SwiftLint strict, coverage self-test and ADR check passed); `git diff --check` passed after this entry.
- Limits: no Swift/package tests, DMG rerun, app/runtime/UI or CI checks; prior focused tests and DMG evidence remain frozen at `c3d38ab`. No product files changed.
- Handoff: parent owns review, PR description and CI; no PR/issue updates or PR merge performed.

## 2026-10-16 — Agent — PR #245 main integration

- Goal: integrate approved `main` `7117491` into the PIM parity branch at `bb093f0`.
- Merge: resolved only additive CHANGELOG and WORKLOG conflicts. Unreleased has one Fixed heading retaining the PIM Calendar/Contacts and Drive multipart/cancellation fixes; the Drive Added entry remains. Preserved PIM v2–v7 and main Drive worklog history verbatim. Non-document files match the lead-reviewed merge tree `7bdb66e`.
- Verification: BrevCalendar PIM store/coordinator filter passed (22 tests/2 suites); focused BrevMail model/presentation/Drive filter passed (138 tests/13 suites); focused Calendar browsing snapshots passed (3 tests/1 suite, six light/dark cases, recording disabled). Catalog JSON parsed; 1,293 keys checked (17 main-only, 6 PIM-only, no differing two-sided changes), with merged values matching branch changes.
- Repository checks: `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` passed (0/1294 files require formatting); `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` passed (0/1294 files formatted); `git diff --check` and staged diff check passed.
- Limits: no full suites, snapshot re-recording, unrelated agenda/detail snapshots, app/runtime/UI checks, or CI watch. No product edits were made during integration.
- Handoff: parent owns post-push PR updates and CI.

## 2026-10-16 — Agent — PR #245 follow-up main integration

- Goal: integrate approved `main` `a624386` into the PIM parity branch at `5594453`.
- Merge: resolved only the additive `WORKLOG.md` conflict, preserving the complete PIM v2–v7 and sign-in/Drive histories verbatim. ADR-0088, ADR-0089 and the index are byte-identical to `main`. The four sign-in source/test files are byte-identical additions from `main`; no pre-existing app/package file changed. The staged tree differs from the lead-reviewed tree only in `WORKLOG.md`.
- Verification: ADR relative links passed; the index has 89 unique ascending rows, with ADR-0088 and ADR-0089 Accepted. `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` passed (0/1298 files formatted; 185 skipped); `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` passed (0/1298 files require formatting; SwiftLint strict, coverage self-test and ADR check passed); `git diff --check` passed after this entry.
- Limits: no Swift tests, builds, DMG, app/runtime/UI or CI checks were run. The four additions are the exact tested main files already covered by PR #241; the frozen PR #245 focused 22 Calendar, 138 Mail, six snapshot cases, and 40 settings/8 detector results were not rerun. The new automatic CI run is the combined gate.
- Handoff: parent owns PR description, CI and PR merge. No PR/issue actions performed.

## 2026-10-25 — Devin — PR #264

- Goal: finish the Calendar, Contacts and Tasks no-sources empty-state pass on
  `fix/pim-empty-states`.
- Changes: wired macOS actions to open Calendar & Contacts Settings at the
  requested pane; hide the middle/list and search chrome when no sources exist;
  paint the theme background on all surfaces; keep the iOS action at a 44-point
  minimum. The English/Norwegian Bokmål catalog and CHANGELOG entries are
  included. No split-view restructuring was needed.
- Verification: `scripts/format.sh` and `scripts/lint.sh` passed after the last
  code change. `PIMNativeChromePresentationTests` passed 18/18. The six changed
  iOS no-source baselines were limited to three Calendar native-chrome variants
  (Light, Dark, AX3) and three compact PIM root covers (Calendar, Contacts,
  Tasks). `ios-pim-root-after-record.xcresult` passed 3/3; the native-chrome
  rerun passed its dynamic test across three variants. The mock app and required
  screenshots are saved under `~/evidence/pim-empty/` (macOS
  Calendar/Contacts/Tasks in Light and Dark, iOS Calendar in Light and Dark,
  Settings on Calendar & Contacts, and Norwegian Calendar).
- Localization: the requested `open -n` launch left the Calendar empty-state
  copy in English. The direct test-binary launch with `-AppleLanguages "(nb)"`
  rendered `Ingen kalendere` with the translated message and action.
- Skips/limits: no full suites or CI watch per scope; live iOS accessibility
  frame measurement remains unavailable, though `.frame(minHeight: 44)` and the
  presentation test cover the target. The optional `origin/main` comparison
  screenshot was not taken. No board transition was made because the PR
  description has no issue ID; intended status is In review.
- Handoff: PR #264 description, CI and merge decision stay with the lead and
  Henrik.

## 2026-10-22 — Agent — Mail-list selection CPU

- Goal: reduce repeated message-row date formatting, macOS sidebar selection,
  and message context-menu work during rapid list selection.
- Changed: added a bounded compact-date-label cache and locale parity test;
  hoisted the active desktop favorite lookup out of per-folder selection;
  moved row menu construction into `MessageRowContextMenu`.
- Verification: focused suites passed after formatting — date presentation
  10 tests, `FolderSidebarPresentationTests` 41 tests, and
  `MessageCommandPresentationTests` 29 tests. `scripts/format.sh` passed
  (1/1302 files formatted; the follow-up format lint found 0/1302 files
  needing changes); `scripts/lint.sh` passed.
- Measurements: three alternating matched Debug runs per side (main totals
  5,664/5,566/5,454; branch 5,441/5,512/5,448). Median row-body samples were
  532 main / 345 branch; sidebar-row samples 256 / 92 and favorite-candidate
  samples 145 / 14. Relative-label samples were 209 / 11; the extracted menu
  initializer had 1 branch sample median, while its body and legacy helpers
  were unsampled. See
  `/Users/devin/brev-perf-out/REPORT.md` for per-run data and artifacts.
- Limits: matched C emitted 4 main and 7 branch `ui.body.visible` spans,
  not ten; `cached_thread_open_ms` was absent and IDs are not logged. No iOS
  simulator interaction or live-provider measurement was performed.
- Net: Brev-owned per-row and sidebar samples fell ~85%, but total
  main-thread samples for the burst moved only ~2% (SwiftUI/AttributeGraph
  dominate in Debug), so no user-visible speedup is claimed and CHANGELOG is
  unchanged. A Release-config trace is the next measurement.
- Handoff: committed on `fix/mail-list-selection-cpu`; parent owns the PR.

## 2026-10-22 — Agent — PR #261 CI repair

- Goal: make the date-cache tests compile in CI's Release configuration.
- Changed: guarded the Debug-only hit-counter assertions while keeping the
  cached-label equality assertion active in Release.
- Verification: Release and Debug `MessageListDatePresentationTests` each
  passed 10 tests; targeted SwiftFormat and strict SwiftLint passed; diff check
  passed.
- CI evidence: Release compilation reported the Debug-only accessor missing at
  test lines 154 and 168, failing both `snapshot-test` and `test (BrevMail)`.
- Handoff: this is the single mechanical fix for PR #261; awaiting its rerun.

## 2026-10-22 — Devin — UI polish branch follow-up (no issue number)

- Goal: implement and refine critique items M1–M3 and I1–I3; “Ask Henrik” excluded.
- Changes: aligned macOS toolbar/thread presentation and equal-width Appearance controls; grouped iOS Mailboxes, polished compose chips and row geometry, and normalized compact Unified Inbox presentation. The AppKit Appearance segmented control now receives the theme accent through `selectedSegmentBezelColor` on updates; the iOS Cc/Bcc accessory retains its 44 pt hit shape while reducing the one-line To row height. Updated Unreleased changelog. Re-recorded only affected Compose, Mailboxes, and Appearance snapshot references.
- Verification: format and lint passed; macOS and iOS mock builds passed. Focused toolbar (24), Unified Inbox (4), FolderSidebar (41), PhoneMailbox (6 tests/9 cases), and Compose tests passed in prior runs. ComposeViewSnapshotTests passed (3/3) after refreshing only empty/reply references. The BrevSettings macOS surfaces test exercised light and dark; the Appearance references now pass, while 10 snapshots for other surfaces still mismatch on this host. Fresh captures are under `/Users/devin/brev-after/`; the iOS compose capture shows one recipient chip, the keyboard, and a one-line To row comparable in height to From.
- Limits: the 10 non-Appearance BrevSettings snapshot mismatches were not compared against clean main in this run. Five PhoneMailbox snapshot failures (19 total, 14 passed) were previously reproduced on clean main (`06c7b19`); the full-suite run hung after results and was interrupted with exit 143. No CI watch or PR action.
- Handoff: parent creates the PR and owns the CI follow-up.

## 2026-10-24 — Agent — PR #260 reader/list polish

- Goal: reduce reader/list chrome and make thread opening target the newest message unless a specific message was selected.
- Changes: removed thread-card accent bars; separated explicit reader selection from parent thread-row selection; moved quick reply into reader scroll content, hid it at compact width, and added Reply All/Forward to the compact Reply menu; made the unread marker a dot sized to `max(7, textSize.listTitlePointSize * 0.6)` on macOS (iOS remains 10 pt), defaulted folder statistics off in both list views and `MailboxViewSettings.defaults`, removed visible date-header counts, and separated iOS 26 Search and Compose toolbar items. Added the Fixed changelog entry.
- Verification: focused ThreadConversationExpansionPolicy, MailRootQuickReplyPolicy, and BrevMailNativeToolbar suites passed (37 tests); MailboxViewSettings passed (3 tests). After the macOS dot-size correction, ThreadConversationExpansionPolicy passed (11 tests), MessageListRowSnapshotTests passed (9/9) after re-recording the dot-affected references (five MessageListRow PNGs differ in the final diff), MailRootComposePresentationPolicy and BrevMailNativeToolbar passed (27 tests), and MailboxViewSettings passed (3 tests). `scripts/format.sh` and `scripts/lint.sh` passed. The parent-row regression is `parentRowSelectionOfOlderHeaderOpensNewestAndChildSelectionStaysSelected`.
- Screenshots: refreshed Mac inbox/reader and iPhone list/reader/Reply-menu captures are saved in `/Users/devin/brev-review/chrome/`; the before captures are retained there as well. The E80 light-mode captures show Compose separate from Search, the newest message expanded without a compact quick-reply bar, and the Reply menu options. Final Mac captures: `/Users/devin/brev-review/chrome/after-mac-inbox-reader-light-v2.png` and `/Users/devin/brev-review/chrome/after-mac-inbox-reader-dark-v2.png`.
- Handoff: `fix/reader-list-chrome` remains stacked on PR #260 (`fix/macos-ios-polish-pass`); no clean-main PhoneMailbox/BrevSettings snapshot drift or new user-visible strings were introduced.

## 2026-10-25 — Devin — UI polish branch follow-up (stacked on PR #263)

- Goal: implement UI direction items #5, #6 remainder, #10 without reactions, and #12 on `fix/list-reader-search-polish`.
- Changes: thread counts are plain secondary text; Mac row toggles remain geometrically stable and show only on hover/selection, while iPhone separators align with sender text and thread chevrons are hidden. Mac unread count remains in the window subtitle; date sections collapse only on Mac. `showFolderStats` still has a Settings consumer, so its setting and list footer remain. Reader body/header alignment and Mac subject metadata now match the requested layout; the existing trailing subject menu was not changed. Mac search uses a segmented scope row, keeps free text out of filter tokens, and shows retry only for finished partial results.
- Verification: focused BrevMail tests passed (36 tests/5 suites); snapshot tests passed (11 tests/2 suites) after updating only five affected references. The Mac mock build and requested iOS 27.0 iPhone 17 simulator build succeeded. `scripts/format.sh`, `scripts/lint.sh`, and `git diff --check` passed. Before/after UI evidence is saved in `/Users/devin/evidence/list-reader-search/`.
- Limits: the iOS package-scheme snapshot route did not produce test results; the workspace lacks a `BrevMail` scheme, and the package-scheme attempt reported `command failed with exit code 0 but produced no further output`. The simulator build and live captures are not reported as iOS snapshot-test coverage.
- Handoff: branch is stacked on `origin/fix/reader-list-chrome`; no reactions action was added or moved. The lone trailing subject control is the existing `threadActionsMenu` in `ThreadConversationView.swift`. No PR or post-push CI watch is requested.

## 2026-10-25 — Devin — PR #263 review fixes

- Goal: show Mac partial-results status only for completed searches with failures, align it with row text, and remove the custom selection bar.
- Changes: `.unverified`-only searches remain retryable but no longer count as partial; the status line uses the list text-column inset. Removed the explicit `RoundedRectangle` selection overlay from shared message rows; selected rows use the system highlight.
- Verification: `MailSearchProgressTests` passed; the affected search-status and selected-row snapshots passed after re-recording only the two search-state images and the selected-row image. `scripts/format.sh`, `scripts/lint.sh`, and `./script/build_and_run.sh --mock` passed. Refreshed and visually inspected the Mac Light list, Dark list, and search-query evidence in `/Users/devin/evidence/list-reader-search/`.
- Limits: no CI checks were watched per the handoff scope.
- Handoff: ready to commit and push `fix/list-reader-search-polish`; do not open a PR.

## 2026-10-25 — Devin — stacked Mailboxes and compose polish

- Goal: implement direction-spec items #9, #11, and #13 on `fix/iphone-mailboxes-compose`, stacked on `fix/list-reader-search-polish`.
- Changes: #9 moves Settings to a leading gear menu, preserves profile switching there, keeps Edit at trailing, uses outline sidebar symbols, renames Favourites to Favorites without changing Bokmål, and removes the Apps header. #11 adds the iPhone collapsed Cc/Bcc/From summary, circular theme-backed Send state, inset separators and recipient truncation. #13 adds the live subject title, a unified-window style, and SwiftUI toolbar items in ComposeView.
- Verification: `scripts/format.sh` and `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` passed. Targeted macOS compose tests passed (39 tests, 5 suites) after re-recording the light/dark ComposeView macOS snapshots. The Mac mock app built and launched. The base-branch snapshot run also mismatched those same ComposeView references on this host before they were re-recorded.
- Limits: a live capture of the presenter-created “New Message” window (`/Users/devin/evidence/mailboxes-compose/diagnostic-mac-compose-no-toolbar.png`) shows the titlebar/toolbar is blank: the window has `.unified` style, but the presenter creates an `NSWindow` and sets `toolbarStyle` without assigning an `NSToolbar`, so the SwiftUI `.toolbar` items are not installed. The fallback title is “New Message” in the window list and the field summary renders, but Send/format/attachment/overflow controls are absent. Installing a native toolbar or changing the presenter/window architecture is a structural change; stop here pending direction. The iOS simulator build emitted no conclusive completion result (`error: the following command failed with exit code 0 but produced no further output` after compile warnings), so iPhone live captures and iOS snapshot recording remain incomplete. No base/after screenshot set was completed. No TDD skill was available in the active plugin set, so no red/green cycle was run.
- Handoff: #9 WIP `c98e5aa` remains pushed. Compose and documentation edits are local and uncommitted; no final commit or push was made because the Mac toolbar requires a structural decision. Do not open a PR or watch CI.

## 2026-10-25 — Devin — native compose toolbar follow-up

- Goal: finish the approved native toolbar bridge and verify compose items #9, #11, and #13.
- Changes: the auxiliary compose presenter now retains a delegate-backed unified `NSToolbar` with Send, flexible space, format, attachment, and overflow in the requested order. Toolbar controls reuse the compose's existing SwiftUI actions; the duplicate SwiftUI toolbar was removed. Added configuration coverage for item order and title fallback.
- Verification: the focused BrevMail run passed 40 tests in five suites, including auxiliary-window configuration and Mac compose snapshots. `scripts/format.sh` and `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` passed. The Xcode 27.0 RC iOS simulator build succeeded; the live iPhone 17 compose showed the collapsed row, expanded fields, grey invalid Send, accent valid Send, no placeholder, and a middle-truncated long recipient chip.
- Limits: the Xcode workspace `BrevIOS` scheme does not include `BrevMailTests`; the targeted `xcodebuild test` request for `longRecipientAddress` exited 70 with “Tests in the target ‘BrevMailTests’ can’t be run because ‘BrevMailTests’ isn’t a member of the specified test plan or scheme.” The on-device live check covered the long chip, but its iOS snapshot test was not executed. Mac native-toolbar visual evidence and the complete before/after light/dark screenshot set are still pending.
- Handoff: native toolbar configuration tests pass; next capture the native Mac compose window and finish the evidence set before commit/push.

## 2026-10-25 — Devin — compose toolbar rendering follow-up

- Goal: verify the native compose toolbar after its hosted controls received explicit AppKit sizing and complete the available compose evidence.
- Changes: the presenter now gives toolbar-hosted SwiftUI controls explicit 42 × 36 point frames. The Mac mock shows the title and all four requested controls in one native unified toolbar.
- Verification: focused compose tests passed (40 tests/5 suites); format and lint passed; the Mac mock rebuilt and launched. Visually inspected Mac compose light/dark and iPhone compose empty/long-recipient light/dark. The iPhone captures show To directly below the title bar, disabled/enabled Send styling, a collapsed optional-field summary, no recipient placeholder, and the long address middle-truncated in its chip.
- Limits: the iOS snapshot test remains unavailable because `BrevMailTests` is not in the `BrevIOS` scheme. The complete requested set is not finished: valid base and after Mailboxes light/dark captures and a Bokmål iPhone compose capture are still missing; the earlier `before-iphone-parent-mailboxes-light.png` depicts the inbox rather than Mailboxes. The Mac captures include a macOS notification banner.
- Evidence: compose captures are in `/Users/devin/evidence/mailboxes-compose/` as `after-iphone-compose-{empty,long-recipient}-{light,dark}.png` and `after-mac-compose-{light,dark}.png`.
- Handoff: host appearance restored to Light. No post-push CI watch requested.

## 2026-10-25 — Agent — stacked Mailboxes and compose review follow-up

- Goal: finish the review fixes for locale-aligned Mac compose labels, To-row separators, and the iPhone Mailboxes toolbar.
- Changes: Mac compose labels now share a locale-sized, trailing-aligned column; the collapsed Cc/Bcc/From row keeps its address in the content column; the To separator begins at the label edge on both platforms. The iOS sidebar's leading Settings gear is the only Settings entry point, leaving Edit alone at trailing.
- Verification: `scripts/format.sh`, `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh`, and the focused BrevMail tests passed. The Xcode 27.0 RC iPhone 17 build succeeded; `./script/build_and_run.sh --mock` rebuilt and launched the Mac app. Visually inspected the Mailboxes-root, empty/long-recipient compose, Bokmål compose, and clean Mac compose window captures.
- Limits: iOS snapshot tests remain unavailable through the `BrevIOS` scheme because `BrevMailTests` is not part of its test plan; live iPhone captures were inspected instead. The Mac build retains existing warnings for deprecated `EventModifiers.function` and non-Sendable closure conversions.
- Evidence: refreshed after captures are in `/Users/devin/evidence/mailboxes-compose/`; valid base Mailboxes captures remain there. The Mac screenshots are window-only and contain no notification banners.
- Handoff: host appearance is Light. Commit and push the completed follow-up; do not open a PR or watch CI.

## 2026-10-29 — Agent — PR #273 review repairs

- Goal: prevent stale legacy JSON from restoring deleted indexed rows and remove per-message conversation traversal from cached page reads.
- Changes: schema v8 persists account/folder import-completion markers in the import transaction. Markers survive folder clearing and generation changes and cascade on account deletion. Both stores share retry behavior. Page threading batches indexed reply identifiers across the page, preserving cross-folder links and account isolation; inherited formatting findings are fixed. ADR-0087 and CHANGELOG updated; no new network calls, opt-ins, UI strings, or privacy-policy changes.
- Verification: reproduced the resurrection failure before the fix. The final BrevSyncEngine run passed 78 XCTest and 28 Swift Testing tests, excluding the expensive header-read baseline; new coverage exercises failed cleanup, reopen/deletion/retry, generation reset, schema-v7 upgrade, transaction rollback and page graph isolation/deduplication. The focused IMAP backend cache/thread run passed 73 tests. Pinned repository lint/format, focused lint on the final schema expectations, and diff checks passed.
- Limits: the original full Debug run was cancelled during the 50k-header baseline after revealing stale schema expectations; no complete new cold-header baseline, native app acceptance, live-mailbox migration, or Release performance claim. CI/review settlement and combined validation with PR #274 are still required. The merge credential currently cannot merge PRs; no merge performed.

## 2026-10-29 — Agent — PR #273 destructive-mutation migration preflight

- Goal: stop move/delete operations from removing indexed headers before an unopened folder's first legacy import, without inferring historical deletion from paging cursors.
- Changes: preflight every source folder before server/cache mutation for move/undo, trash/permanent deletion, remote-draft cleanup, folder deletion/flush and junk training. Local migration errors propagate rather than reporting successful offline enqueueing; cancellation is preserved. No schema or import-filter change. ADR-0087 and CHANGELOG distinguish this fix from unresolved historical absence ambiguity; no network, privacy policy, setup, UI-string or release change.
- Verification: red-green SQLite regressions cover eight entry points, multi-folder batch failure, reopening with retained stale JSON, undo-source migration and preservation of a newer legacy-only UID. Initial tests failed with 36 assertions; adding an offline queue exposed 12 further swallowed-error/queued assertions before error classification was fixed. Final four parameterized tests (17 cases) pass, as do 1,163 backend tests, 78 XCTest plus 32 Swift Testing sync tests (excluding IMAPHeaderReadBaselineTests), pinned repository lint/format and focused final lint/format. Privacy-audit coverage, public-source markers, OpenPGP-retirement and telemetry-artifact self-tests pass; non-executable self-test scripts were invoked with bash. Telemetry bundle checks skip absent app builds.
- Handoff: isolated repair based on `8ba8154fa827a8d7d0025a96bc571b7bb95e62df`; parent owns integration into existing PR #273, stacked validation, review replies and hosted CI. No native/live tests or new header-read performance run requested. Review 4413521103 remains unresolved for already-shipped ambiguous histories; no quarantine or authoritative-source policy is implemented, and newer legacy-only rows remain recoverable. No new PR, merge, issue change or original-branch push.

## 2026-10-29 — Devin — PR #274 selective-cache review repair

- Goal: repair comment 6498247342 on the pinned selective-cache slice, using
  `fix/pr-274-review-16784` only. Original parent/base: `4bf1d31f1c78748b0b49a5eb5dfd9dd34b2f595f`;
  original PR head/repair starting point: `08535128a46fc38dec5946229214cab411f9dfb5`.
- Changes: prepare unopened legacy folders before account/folder/set-scoped
  cache-only search and saved-view enumeration; select exactly `Date.distantPast`;
  preserve fractional retention cutoffs using integer candidates plus exact-date
  filtering; gate background repair on invalid dates in the returned page.
  Attachment/body selection unions indexed candidates before primary-key reads.
  The local smoke now uses production SQLite/legacy-reader/memory seams.
- Regression evidence: new date/search tests failed before implementation;
  the page-repair regression fails with the old unconditional scheduling guard
  and passes with the fix. Query-plan coverage rejected a folder-wide date-index
  read, then passed with expression-index/body-primary-key candidates and exact
  header-key lookup. Final focused sync run: 15 tests passed.
- Verification: pinned SwiftFormat 0.58.7 on assigned files and `scripts/lint.sh`
  (SwiftLint 0.63.0) passed; `scripts/imap-smtp-local-smoke.sh` and
  `scripts/test.sh --self-tests-only` passed. BrevBackend: 1,163 tests passed.
  BrevSyncEngine excluding `IMAPHeaderReadBaselineTests`: 78 XCTest + 31 Swift
  Testing tests passed. Settings storage behavior: 23 passed; mailbox storage: 9 passed.
  Standalone `swift build` for BrevSyncEngine and BrevBackend passed on macOS.
- Storage review: legacy JSON files intentionally count once as objects, not as
  messages; indexed counts are separate, and legacy bytes remain included.
  Existing object/header copy stays accurate. ADR-0087 and CHANGELOG updated;
  README, PRIVACY and ADR-0006 need no change (no setup or network-policy change).
- Remaining: four existing Settings storage snapshots mismatch this host's
  current rendering; UI sources and baselines were not changed. Current light/dark
  PNGs and a light baseline were visually inspected and supplied in the session
  to show the layout mismatch, not populated-cache acceptance. Full app/iOS builds,
  live-provider/UI testing and header-read performance acceptance were not run in
  this repair lane. No daily-driver app was replaced.
- Handoff: parent owns schema-v8 migration replay and shared threading, restack,
  original-PR push, CI/review settlement and merge. This patch neither changes the
  schema nor adds a new index test conformer; no parent fix was duplicated.

## 2026-10-29 — Agent — PR #273/#274 combined verification

- Restacked the selective-cache slice and its review repair onto the durable-import/page-threading parent. Resolved only adjacent additions, formatter overlap and append-only documentation conflicts; retained both regression sets.
- Combined checks passed: 78 XCTest and 34 Swift Testing sync tests (excluding the expensive header-read baseline), all 1,163 backend tests, pinned repository lint/format, and repository self-tests including the production-seam local IMAP/SMTP smoke. Query-plan coverage confirms indexed attachment/body candidates and exact header-key reads.
- Hosted CI, four unaccepted storage snapshot differences, native/runtime acceptance and merge access remain open. No real-account migration, app installation, release, or performance acceptance is claimed. Keep the storage slices paired and issue #269 open.

## 2026-10-29 — Devin — PR #274 attachment follow-up

- Goal: repair reviews 4413512120/4413512356 from pinned integrated head
  `6d725f8661ad4989b6e3c2196b966af93f5d09d7` on `fix/pr-274-followup-16784` only.
- Changes: source/parsed-body caches enumerate account/folder-scoped IDs without
  decoding payloads; attachment enumeration unions those IDs with indexed
  candidates and fetches missing headers in batches of at most 256. No whole-folder
  header fallback, network fetch, or cache rewrite was introduced. Schema v9
  transactionally installs the attachment expression index on existing v7/v8
  stores; fresh databases share its DDL, and in-memory schema expectations match.
- Red-green: new tests first returned only 2 of 265 cached attachments, lacked
  the upgraded expression index, and failed the migration-error expectation.
  They now pass for memory and reopened file caches, including parsed/MIME-only
  attachments, duplicate/orphan IDs, body precedence and account/folder isolation.
  v7/v8 upgrade/reopen EXPLAIN uses the expression index; failed creation preserves
  v8 data/windows/import markers and succeeds on retry after removing the fault.
- Verification: 1,163 backend tests; 78 XCTest + 37 Swift Testing sync tests
  (excluding the expensive header-read baseline); pinned full lint/format;
  repository self-tests; standalone backend/sync package builds all passed.
- Docs: ADR-0087/CHANGELOG updated. README, PRIVACY, ADR-0006 and UI snapshots
  need no changes: no setup, external network, privacy policy or UI change.
- Handoff: parent owns first-import coverage filtering, integration/restack,
  original-PR push and review/CI settlement. No patch to that migration logic.
  No native app/iOS build, live/UI test or performance acceptance run here.
  Settings lane separately reproduced all four storage snapshot mismatches on
  pristine main on the same host; no baseline changed in this follow-up.
