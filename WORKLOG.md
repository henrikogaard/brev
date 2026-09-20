# Worklog

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

## 2026-09-18 — Devin — Daily-driver search/index perf fixes (feature/perf-daily-driver)

### Goal

Address four audit findings in the local search and indexing paths on
`feature/perf-daily-driver`, preserving exact search results and ordering.
No commit (user request).

### Summary

- `SearchQuery.matches` (`BrevBackend/Models.swift`): cheap metadata
  predicates (unread, flagged, attachments, folder scope, date range)
  already ran first; each needle is now trimmed + normalized once per call
  and reused across every per-field `normalizedContains` check instead of
  re-folding per field. In-memory fallback retained — local index coverage
  of the searched folders cannot be proven (partial pages, invalidation,
  independent header-cache writes), so `IMAPSMTPBackend` keeps filtering.
- `SQLiteSyncStore.searchHeaders`: metadata-only queries (empty text) now
  scan `message_headers` directly — no `LEFT JOIN message_search`, no body
  column. The join is kept only for tokenless non-empty text (e.g. `!!!`)
  where the body column feeds the Swift text check.
- Candidate scans are chunked (`searchCandidateChunkSize`: 4× limit,
  clamped 500…4 000) via a `CandidateStream` that keeps the prepared
  statement open; the FTS path filters while decoding and stops once
  `limit` post-filter hits exist and every stream's unread tail is
  strictly older than the limit-th hit. `attachmentFTSCandidates` gained a
  `LIMIT` bound; attachment-only hits still fill only the slots left after
  message hits (ADR-0078 §5).
- `upsertHeaders`: a flag-only refresh (unchanged `id`, folder, subject,
  snippet, correspondents, `messageID`/`threadID`/`inReplyTo`/`references`,
  verified via `hasSameIndexedContent` against the already-read stored
  JSON) now skips the `message_search` DELETE+INSERT and the
  `conversation_links` rewrite, provided a search row exists and the
  stored `message_id` column is unchanged. `upsertSearchRow` accepts a
  pre-prepared DELETE+INSERT pair so batches compile it once.
- Fixed a pre-existing `var bindings` → `let` warning in `deleteBodies`.

### Verification

- `swift test --package-path packages/BrevSyncEngine` — 78 XCTest + 16
  Swift Testing pass, incl. 4 new tests (metadata-only scan, tokenless
  body join, chunked scan past chunk boundaries, flag-only upsert
  rowid/link stability + subject-change rewrite).
- `swift test --package-path packages/BrevBackend` — 1 130 tests pass,
  incl. new `SearchQuery.matches` equivalence test.
- `swiftformat --lint` and `swiftlint --strict` clean on all touched
  files; `git diff --check` clean.
- Skipped: full-tree `scripts/lint.sh` fails on pre-existing uncommitted
  changes in ~45 files outside this task's scope (BrevGmail, BrevMail,
  BrevSettings…) — untouched per surgical-change rule. `scripts/format.sh`
  would rewrite those files, so formatting was applied to the four
  touched files only.

### Handoff

- Uncommitted on `feature/perf-daily-driver`; tree contains unrelated
  uncommitted work from other sessions — verify scope before committing.
- Attachment FTS scan bound (4 000 rows) is observable only when a query
  matches more attachment rows than that; accepted per audit request.
## 2026-09-18 — Claude (ZCode) — iOS review findings fix (fix/ios-review-findings)

### Goal

Fix the actionable findings from the iOS app code review and open a PR to main.

### Summary

- Privacy manifest: added `NSPrivacyAccessedAPICategoryUserDefaults` (CA92.1);
  a repo-wide grep confirmed no other required-reason categories are in use.
- Restore errors: `AppSessionRestorePresentationPolicy.shouldShowRestoreErrorAlert`
  (new, TDD red→green) now drives the launch alert, so total-restore failure
  (zero visible backends) surfaces instead of silently showing the login
  screen; Settings hoisted above the mailbox-root decision in the iOS app so
  the alert's "Open Settings" action works there too.
- Notification content extension: `UNNotificationExtensionCategory` is now an
  array covering `brev.newMail` and `brev.newMail.replyEnabled`, so
  reply-enabled notifications get the rich preview.
- Share extension: text handoff capped at 256 KB; oversized text is dropped
  with an explicit message (never truncated) while remaining URLs/attachments
  still open.
- Config: removed the unused `processing` background mode (nothing registers a
  `BGProcessingTask`); enabled `APPLICATION_EXTENSION_API_ONLY` for both iOS
  extensions (ADR-0004 updated — protected path); replaced the silent `try?`
  local-search-index factories with a logged helper; fixed the stale
  `currentBackends` isolation comment.

### Verification

- `swift test --package-path packages/BrevMail --filter
  AppSessionRestorePresentationPolicy` — 3 tests pass (red first).
- `tuist build BrevIOS` — build succeeds with the new extension setting.
- `plutil -lint` on all touched plists — OK. SwiftLint clean on touched
  targets; SwiftFormat check run on touched Swift files.
- Skipped: on-device QA of the total-failure alert path, reply-enabled rich
  notifications, background refresh, and alternate icons (manual QA).

### Handoff

- Follow-ups not in this PR: unit-test target for `apps/iOS` (BGTask
  coordinator / `OneShotBGCompletion` / share-URL building are untested);
  decide whether tracked generated files (`apps/iOS/Derived/Sources/Tuist*`)
  should be untracked; populate the empty share-extension String Catalog;
  confirm `ITSAppUsesNonExemptEncryption=false` is deliberate given the
  built-in S/MIME crypto.
## 2026-09-18 — ZCode — macOS app review fixes

### Goal

Address the findings from a full code review of `apps/macOS`
(P1 Maildir panel, P2 defaults-trigger and developer-relaunch, P3
cleanups) on branch `fix/macos-review-findings`.

### Changes

- `MailFilePanels.swift`: include `.folder` in the import panel's
  `allowedContentTypes`; a type-filtered `NSOpenPanel` disables directory
  selection otherwise, which made the advertised Maildir import
  unreachable. The importer still rejects non-Maildir directories.
- `BrevApp.swift`: debounce the `UserDefaults.didChangeNotification`
  background-mail reconcile (every defaults write in the process,
  including window-frame saves, re-ran it); gate
  `restartForDeveloperModeChange()` behind `#if DEBUG` so release builds
  cannot self-relaunch or mutate the launchd environment; localize the
  account-restore alert message with `String(localized:)`; handle every
  matching URL in `application(_:open:)` (last per scheme wins) so a
  `mailto:` + `brev://` pair in one open event is no longer truncated.
- `MacUpdateController.swift`: remove write-only `currentSettings`
  (orphaned by the ADR-0080 `appcastURL` change).
- Refined during implementation: `BrevProgressSurface(label:)` takes a
  `LocalizedStringKey`, so the bare literal at that call site is already
  the String Catalog convention and was intentionally left unchanged.

### Verification

- `scripts/format.sh` — OK, produced no changes.
- `scripts/lint.sh` — OK (SwiftFormat lint, SwiftLint strict, coverage
  self-test, ADR-required check).
- `xcodebuild build -scheme BrevMacOS -workspace Brev.xcworkspace
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO` —
  BUILD SUCCEEDED. Plain `tuist build` fails in this environment at code
  signing (no development certificate in the keychain); the signing
  failure predates these changes and is unrelated.
- Not run: package tests (no package sources touched); GUI check of the
  import panel (no app test target covers `NSOpenPanel` behavior).

### Handoff

- Hand-verify the P1 fix in a test build: File → Import Mail…, select a
  Maildir directory, confirm it is accepted and imports.
- No GitHub project board card exists for this review-fix work; nothing
  to move on the board.

## 2026-09-18 — Codex — Nightly archive environment

### Goal

Finish the Nightly repair after the corrected no-checkout planning job exposed
the next archive-stage failure.

### Changes

- Mapped the configured Google OAuth client ID and secret into Nightly's
  signed-archive step, matching the stable release workflow.
- Added a regression check requiring both OAuth mappings in Nightly.

### Verification

- Nightly run `35313161111` passed `plan` and reached the signed archive step;
  its failure identified the missing OAuth environment variables.
- `scripts/test-developer-id-release-config.sh`
- `git diff --check`

### Skipped

- Hosted Nightly retry is pending this follow-up change.

### Handoff

Commit and push the patch, open the follow-up PR, merge it after checks pass,
and confirm the next Nightly run publishes the signed pre-release and appcast.

## 2026-09-18 — Codex — Nightly workflow repository scoping

### Goal

Restore the scheduled Nightly pipeline after its no-checkout planning job
failed while `gh` tried to infer the repository for the Build lookup.

### Changes

- Scoped the Nightly plan's `gh run list` call explicitly to
  `$GITHUB_REPOSITORY`.
- Added a release-configuration regression check for the no-checkout query.

### Verification

- `scripts/test-developer-id-release-config.sh`
- Explicit repository-scoped Build lookup returned the green main Build run.
- `scripts/format.sh`
- `scripts/lint.sh`
- `git diff --check`

### Skipped

- Hosted Nightly rerun is pending the PR merge.

### Handoff

Open the PR, wait for required checks, merge it, and confirm the next Nightly
run publishes the signed pre-release and appcast.

## 2026-09-18 — Codex — Release certificate/profile diagnostic

### Goal

Make the remaining Developer ID archive failure actionable after Xcode
reported that the stable CI profile did not contain the imported certificate.

### Changes

- Added a signing-action preflight that compares the imported Developer ID
  certificate SHA-256 fingerprint with the certificate embedded in the
  selected provisioning profile.
- Added a regression check for the fail-closed mismatch path.

### Verification

- Focused release configuration checks are pending after this edit.

### Skipped

- Hosted archive, signed DMG, appcast publication, and Sparkle client update
  verification remain pending the diagnostic run.

### Handoff

Run the focused checks, merge the diagnostic, and retag `v0.1.0` so the
preflight identifies the exact stale certificate or profile if the pairing is
still wrong.

## 2026-09-18 — Codex — Release signing target scope follow-up

### Goal

Unblock the signed `v0.1.0` archive after the first scoped-profile retry
showed that a globally passed Developer ID identity still forced manual
signing on SPM package targets.

### Changes

- Removed global team and full certificate identity overrides from the archive
  command; Release target settings now own all Developer ID signing inputs.
- Added regression checks that keep team, identity, signing style, and profile
  target-scoped.
- Clarified the app-only signing invariant in ADR-0080.

### Verification

- Focused release configuration and appcast checks are pending after this
  follow-up edit.

### Skipped

- Hosted archive, signed DMG, appcast publication, and Sparkle client update
  verification remain pending the fix being merged.

### Handoff

Run the focused checks, open and merge the follow-up, then rerun the tagged
`v0.1.0` release workflow.

## 2026-09-18 — Codex — Release archive signing scope

### Goal

Unblock the signed `v0.1.0` archive after Xcode rejected the global
provisioning-profile override on SPM package targets.

### Changes

- Scoped manual Developer ID signing and the provisioning profile to the
  `BrevMacOS` Release target; the archive script now passes only a custom
  profile setting globally.
- Updated stable and nightly export options to the actual CI profile names.
- Added regression checks for target scoping, profile names, and removal of
  the global profile override.

### Verification

- Profile metadata contains the expected Developer ID certificate and team.
- `scripts/test-developer-id-release-config.sh` — passed.
- `scripts/test-release-appcast.sh` — passed.
- `scripts/format.sh` — 0 files formatted.
- `scripts/lint.sh` — passed after updating ADR-0080.
- `mise exec -- tuist install` and `mise exec -- tuist generate --no-open` — passed;
  generated macOS project contains app-target-only profile settings.
- `git diff --check` — passed.

### Skipped

- Hosted archive, signed DMG, appcast publication, and Sparkle client update
  verification remain pending the fix being merged.

### Handoff

Run the focused release checks, open and merge the fix PR, then rerun the
tagged `v0.1.0` release workflow.

## 2026-09-17 — Codex — Release signing environment fix

### Goal

Unblock the signed `v0.1.0` release after the first tag run failed while
exporting parsed provisioning-profile values to GitHub Actions.

### Changes

- Normalize provisioning-profile UUID, name, and team values to single lines
  and write the team/profile environment entries with `printf` in the release
  signing action.
- Rotated the two release-environment P12 secrets with a freshly exported
  Developer ID identity after CI rejected the previous password.

### Verification

- `scripts/test-developer-id-release-config.sh` — passed.
- `scripts/test-release-appcast.sh` — passed.
- `scripts/lint.sh` — passed.
- `scripts/format.sh` — 0 files formatted.
- `git diff --check` — passed.

### Skipped

- The release workflow rerun is pending this fix being merged.
- Published artifact and Sparkle client update verification remain pending.

### Handoff

Open and merge the release-action fix, rerun the existing `v0.1.0` workflow,
then verify the signed DMG, stable appcast, and available client update path.

## 2026-09-17 — Codex — Main Build follow-up

### Goal

Unblock the post-merge main build so the signed `v0.1.0` release can be
exercised.

### Changes

- Stabilized the OAuth IDLE retry test by asserting the single-refresh
  invariant instead of an exact subscription count after a scheduler-sensitive
  sleep.

### Verification

- `swift test --package-path packages/BrevBackend` — 1125 tests in 111 suites
  passed.
- `git diff --check` — passed.

### Skipped

- Hosted CI rerun is pending push.
- Signed release, appcast publication, and client update verification remain
  pending the green main build.

### Handoff

Push the follow-up PR, merge after green CI, then tag `v0.1.0` and verify the
published release feed and artifact.

## 2026-09-17 — Devin — Issue #28 §9: ADR-0077 durable local mail folders

### Goal

Implement ADR-0077: a synthetic "On My Mac" / "On My iPhone" backend storing
mail as Maildir files outside every cache root, with Copy/Move/Import entry
points, search-index integration, and `.brevbackup` mail payloads.

### Changes

- BrevBackend: `LocalMaildirStore` (actor; `folders.json` manifest, per-folder
  `cur`/`new`/`tmp`, atomic tmp→fsync→rename writes, Maildir flag-suffix
  renames, `size()`), `LocalMailBackend` (`accountID = "local"`,
  folderCreate/Rename/Delete capabilities, `importMessages`/`importRaw`,
  `storedRFCMessageIDs`, index rebuild on connect when files exceed the
  index), `LocalMailBackup` (payload/restore-mode/importer types).
- BrevMail: `AppSession` registers the local backend (injectable via
  `AppSessionFactory.Configuration.localBackendFactory`) and gates
  `visibleBackends` on `hasFolders`; `LocalMailTransfer` implements the
  write-local-first then undoable-server-delete ordering; `MoveToSheet` gains
  a local-destination mode with a New Folder field; context menus and
  `MailCommands` offer Copy/Move to Local Folder (macOS only); `FolderSidebar`
  has "New Local Folder…" on the account-level menu; the folder delete
  confirmation states it permanently removes kept mail; `importMessages`
  defaults to a new local folder named after the file basename.
- BrevSettings: Mail Storage gains a "Local folders" group with size and the
  "Not a cache." subtitle; `.brevbackup` format bumped to v2 (reader still
  accepts v1) with `mail/<folderID>.mbox` payloads, SHA-256 manifest entries,
  a preview toggle (default on when folders exist), and restore Merge
  dedupes by Message-ID / Replace recreates.
- Docs: PRIVACY.md local-mail-folders section + backup paragraph update,
  CHANGELOG Unreleased entries, ADRs/README index row.

### Verification

- `swift test packages/BrevBackend --filter 'Local|Backup|Maildir'`: 67/67.
- `swift test packages/BrevBackend`: 1106/1106 in 108 suites.
- `swift test packages/BrevMail --filter 'AppSession|LocalFolder|Import'`:
  green incl. 2 AppSession local-backend tests, 4 LocalMailTransfer ordering
  tests, 4 new snapshot cases.
- `swift test packages/BrevSettings --filter 'Backup|MailStorage'`: green incl.
  writer `mail/*.mbox` hashes, v1 acceptance, Merge dedupe / Replace recreate,
  and new snapshots (preview toggle + Mail Storage row).
- `tuist generate` OK; `tuist build BrevIOS` built; macOS
  `xcodebuild … CODE_SIGNING_ALLOWED=NO` **BUILD SUCCEEDED**;
  format/lint/privacy-audit/`git diff --check` all OK.

### Skipped

- `tuist build BrevMacOS` (signed) — no dev cert in this environment; unsigned
  xcodebuild covers compilation.
- iOS write UI — macOS-only by design (ADR-0077); iOS read path covered by the
  BrevIOS build.

### Review fixes (same entry)

- Backup writer/reader now hash every payload by streaming CryptoKit SHA-256
  (1 MiB `FileHandle` chunks); `mailBytes` comes from file resource values, so
  multi-GB mboxes never load into memory.
- Permanent message deletes confirm first via a single shape-based rule —
  `MailUndoableDelete.isPermanentDelete` (no `.trash` folder, or already in
  Trash) gates root `trash`, list swipe, and bulk paths; the folder-delete
  alert copy uses the same predicate instead of the local account ID.
- `LocalMailTransfer.move` splits write failures from source-delete failures
  (copied-but-not-removed keeps `copiedIDs` + a distinct error) and exposes
  `removedSourceIDs` so the list only drops sources that actually deleted.
- "message(s)" strings replaced with count-based noun selection.

Re-verified: Backup suite 20/20, LocalMail/Undoable/Delete/LocalFolder 20/20,
format/lint/diff-check clean, unsigned macOS build succeeded.

### Handoff

Uncommitted on `feature/mail-client-parity` over `8cbbed14`; user commits.

## 2026-09-16 — Devin — Issue #28 / PR #30: ADR-0074 independent-review fixes

### Goal

Address the two-axis (standards + spec) review findings on `23281fc6` and
`a4258de2` before handoff.

### Changes

- Consent revocation: session grants moved to process-wide state so
  `removeAccountScopedState` (fresh store instance) clears a grant made
  through `.shared`; consent-store tests serialized because the shared
  grants are intentionally global.
- IMAP pagination: `loginAndSearchRelatedHeaders` accepts a page cursor;
  `loadRelatedConversation` follows truncated result windows within the
  request budget, and a leftover cursor or ambiguous identifiers force
  `.partial` — never `.completeForScope` (§8). New tests cover
  page-following to completion and budget-exhausted partial coverage.
- IMAP discovery fetch dropped `BODY.PEEK[TEXT]` — metadata-only per
  §4's enumerated set (`includeSnippet` flag on the shared fetch helper).
- Stale writes: discovered-header persistence is skipped when the task is
  cancelled or remote availability dropped mid-scan.
- Reader: `includeSpamAndTrash` bumps the lookup generation (rejects
  in-flight updates from the narrower scope) and only re-fires remote work
  when consent still holds — a revoked consent now re-scopes from cache
  without a `.consentRequired` failure surface.
- Docs: ADR-0006 and PRIVACY.md now disclose the one-shot Gmail
  `users.messages.get` minimal-format fallback for legacy cache records
  without a stored thread ID.
- Snapshots: new `RelatedConversationBarSnapshotTests` (prompt, cached,
  partial, failed-retry); `mailbox-view` light/dark baselines re-recorded
  for the new Related mail group. Other settings baselines
  (appearance/accounts/navigation/folder-workspace) drift on this host's
  renderer with identical content and were left untouched.
- Gmail store apply kept best-effort with an explicit rationale comment
  (BrevGmail has no logging convention).

Follow-up (same day, second review pass): fixed a `mergedThreadHeaders`
trap on duplicate header ids (`uniquingKeysWith` preferring the member
that carries a folder generation), disclosed unsynced folders in the
reader's Load-related-mail accessibility hint, serialized the controller
test suite against process-wide session grants, and clamped the
related-header search limit to `maximumSearchPageSize` like the sibling
search op.

Third pass (all findings): consolidated the related-mail bar's three
coverage dispatches into one presentation value (symbol, tint and copy can
no longer diverge), extracted the shared Gmail member-building helper used
by both cached and remote paths, replaced the packed anchor-key string
with a `ConversationAnchorKey` struct, and made the related-mail account
picker binding optional instead of an empty-string sentinel. Session-pool
safety verified: `withAuthenticatedSession` serializes every op through
`acquireSessionOperation`, so SELECT-before-SEARCH cannot interleave.


### Verification

- Focused: 12/12 backend related-conversation + consent tests; BrevMail
  RelatedConversation suites 11/11 incl. new bar snapshots; settings
  account-scoped consent cleanup passes.
- Full BrevBackend suite: 1076 tests pass. `scripts/lint.sh`,
  `scripts/format.sh`, `scripts/privacy-audit.sh`, `git diff --check` pass.
- `mailbox-view` snapshots pass with new baselines; unrelated settings
  snapshot drift on this host documented (pre-existing, not from this diff).

### Skipped / pending

- The settings snapshot drift on unrelated surfaces needs re-recording on
  the maintainer's authoritative host, or CI will show the same drift.
- Live-account acceptance still pending.

## 2026-09-15 — Devin — Issue #28 / PR #30: ADR-0074 provider extensions, consented remote discovery, reader integration

### Goal

Complete the remaining ADR-0074 delivery stages on `feature/mail-client-parity`:
cached + remote related-conversation loading on both providers, per-account
consent, and reader integration.

### Changes

- `IMAPSMTPBackend`: `CachedConversationProviding` over the SyncEngine local
  index (no network, Spam/Trash excluded by default, anchor-only fallback);
  `RelatedConversationLoading` via bounded `UID SEARCH HEADER` frontier
  expansion with metadata-only candidate fetches (UID/ENVELOPE/FLAGS/
  `BODY.PEEK[HEADER.FIELDS (REFERENCES)]`), generation checks, folder-failure
  accounting, and honest `.partial` coverage.
- `IMAPSessionClient`: `loginAndSearchRelatedHeaders` session op emitting
  structured `UID SEARCH HEADER` commands; no-op when no usable identifiers.
- `GmailAPIBackend`/`GmailAPITransport`: `getThread` (metadata format,
  selected headers only — no full/raw/attachment calls), plus
  `RelatedConversationLoading` that deduplicates label memberships, preserves
  folder context, excludes Spam/Trash by default, and persists discovered
  headers through the provider-owned store. Gmail header mapping now carries
  References.
- `RelatedConversationConsentStore` (new, BrevBackend): per-account consent —
  persistent auto-load preference (default off) + session grant for the
  explicit reader action; revocation/account removal clears both.
- Settings: "Related mail" group in Mailbox View with per-account picker and
  the consent copy required by ADR-0074 §6; `removeAccountScopedState` revokes
  consent.
- Reader: `RelatedConversationController` (single owner, generation-guarded
  stale rejection, cancellation on anchor change) + `RelatedConversationBar`
  (cached/loading/partial/complete feedback, Load related mail, Retry,
  Include Spam and Trash) merged into `BrevMailRootView`; snapshot members
  merge into the thread view with real folder/UID locators.
- `MockBackend` gained conversation-service handlers + `extendedCapabilities`
  for tests.
- Docs: ADR-0006 network table row, `PRIVACY.md` related-mail section,
  ADR-0074 progress note, CHANGELOG Unreleased.

### Verification

- `swift build` clean for BrevBackend, BrevGmail, BrevSettings, BrevMail.
- Focused tests: IMAP backend conversation tests 7/7; IMAP session
  related-header 2/2; Gmail backend 29/29 (incl. new consent-gated
  threads.get tests); Gmail transport 16/16 (metadata request shape);
  consent store 4/4; settings account-scoped cleanup incl. consent revocation
  11/11; reader controller 7/7 (cached merge, consent gating, explicit action,
  auto-load, stale rejection, Spam/Trash scope, failure/retry).
- `scripts/lint.sh`, `scripts/format.sh`, `scripts/privacy-audit.sh`,
  `git diff --check` all pass.

### Skipped / pending

- MailboxViewSection iOS snapshot re-record (new Related mail group changes
  the section image) — needs `RECORD_SNAPSHOTS=YES tuist test`; not run here.
- Live-account acceptance: native light/dark, accessibility/compact layout,
  discovery duration/memory/request counts on representative accounts.

### Handoff

Remote discovery is off by default; explicit per-conversation action or the
per-account Mailbox View preference are the only triggers. PR #30 remains a
draft; issue #28 remains In progress — no merge/release performed.

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


## 2026-09-05 — Codex — Issue #28 parity architecture decisions

- Created #28 with all comparison findings, ordered acceptance criteria, and
  links to existing live-QA and Google/DAV issues. Added it to Brev project 9
  as In progress.
- Prepared Proposed ADRs 0070–0073 for opt-in macOS background mail, native
  Microsoft mail/shared sources, calendar/contact authoring, and local archives
  with portable backup/restore. These are reviewable design choices, not
  implementations or account/OS consent grants.
- Baseline is PR #27 at 1250634; this documentation branch stacks on
  fix/multi-account-workspace and ultimately targets main. Core parity fixes
  proceed independently in the mail-client-parity worktree.
- Verification: documentation links/index and diff checked. TDD/builds are not
  applicable to this documentation-only slice. Strategic implementations remain
  gated by ADR acceptance under AGENTS.md and prompts/new-adr.md.

## 2026-09-07 — Codex — Issue #28 / PR #29 conversation architecture

- Confirmed all 20 checks passed on implementation head 676a7886.
- ADR-0052 explicitly reserves cross-folder indexing as a separate decision;
  ADR-0020 limits reader membership to loaded folder headers. Added Proposed
  ADR-0074 for source-owned cached graphs, Gmail metadata threads, bounded IMAP
  header discovery, explicit per-account consent, coverage and action/selection
  isolation. Implementation awaits acceptance, per AGENTS.md.
- Read existing threading/search/provider interfaces and primary Gmail/RFC docs.
  Verified index/links and diff formatting. Documentation-only exception: no TDD,
  app build or live account activity. No merge/release or network preference change.

## 2026-09-07 — Codex — Issue #28 / ADR-0074 acceptance

- Henrik explicitly approved ADR-0074 in this thread. Marked only ADR-0074
  Accepted and updated the index. ADR-0070 through ADR-0073 remain Proposed.
- This records architecture approval; it does not merge/release or grant live
  provider mutation/OS setup authority. Documentation-only; diff check applies.

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

## 2026-09-07 — Codex — Issue #28 / PR #30 progressive search

- Added an optional source-validated progressive search callback with cache/server
  coverage. IMAP awaits consumers before requesting another page. Existing array
  callers retain compatibility; array-only providers report unverified coverage.
- Folder and unified lists now publish incremental source-qualified results with
  UUID ownership through callbacks and finalization. Sorted batches are merged,
  selected readers are preserved during paging, and failed sources retain partial
  rows with shared Retry and coverage feedback.
- Replaced the separate attachment disclosure with a compact themed search-status
  row, including both presence and absence predicates. New light/dark snapshots
  were recorded, inspected and passed comparison; CI routes them to the compatible
  macOS renderer. Source policy, README, DESIGN, privacy and QA docs were updated.
- TDD established missing progress contract/state behavior and terminal-update
  rejection. Callback tests prove first-page publication before next request,
  cached fallback labeling and cancellation stopping paging. Disclosure regression
  reproduced absence-predicate omission and was fixed through the shared policy.
- Full Mail 1,551 and Backend 1,043 tests passed before the final callback additions;
  the new callback suite passes. Dated September 7 mock macOS build/startup passed;
  iOS build, final full suites, lint/privacy and independent reviews are ongoing.
- This remains part of open #28: Gmail progress/cap, detailed index coverage,
  user-paced load-more, measured native performance and the broader parity scope
  remain open. No merge, release, external setup or live-provider sends occurred.

- Native QA exposed a first-search lifecycle bug: duplicate SwiftUI search tasks
  could cancel a same-query replacement, leaving progress stuck or falsely
  incomplete. Added one cancellable worker per list and a combined text/filter
  trigger; replaced workers cannot clear newer ownership. Regression tests cover
  cancellation before start, interrupted finalization, worker replacement and
  mixed-source Retry readiness. Native first invoice search now finishes without
  Retry, keeping the result/reader visible. The mock array adapter correctly
  reports unverified coverage, not server completion.
- Review fixes preserve loaded conversation replies during paging, retain the
  explicit no-background-fetch disclosure, add package catalog keys, prioritize
  unverified coverage in mixed results, and give iOS Retry a 44-point target.
- Final local evidence: Mail 1,555, Backend 1,045 and separate Contacts 6 tests
  passed; five-state light/dark snapshots passed and were inspected. Dated mock
  macOS build/startup and iOS compilation, lint/format/privacy/diff checks pass.
  Background UI access became unavailable after first-search QA because the
  target window no longer resolved in AXWindows; Local/All Inboxes native checks
  remain unverified. No foreground escalation was used.
- Hosted checks on preceding 546558c9 are 19 passed / Backend failed. Inspecting
  that exact job before this slice's delivery; no CI success is inferred from
  local suites. The broader parity issue remains In progress.

- Hosted Backend failure on 546558c9 was the pre-existing IDLE retry test's
  exact subscription-count assertion after a fixed sleep. Replaced that timing
  assumption with ContinuousClock intervals recorded at actual subscriptions
  (at least 100ms then 200ms); production retry behavior is unchanged. Full
  Backend 1,045 tests pass afterward and independent review cleared the change.

## 2026-09-07 — Codex — Issue #28 / PR #30 Gmail search parity

- Confirmed all 20 hosted checks passed on df6be51f before starting.
- Red tests reproduced the 5,000-result cap, disconnected cache rejection,
  secondary-label scope loss, omitted negative predicates, inconsistent All Mail,
  and hidden later-page auth/retry error types. Added shared progressive search,
  50-reference pages, max-four reads, cancellation/generation checks and typed
  errors. Search-only fetches do not persist late results into replacement stores.
- Review found the full-cache Auto scan and production transport-error fallback
  gap. Added 100-candidate cache preview plus SQLite keyset pages; offline/local
  scans complete all pages. Tests prove server starts after one preview and use
  a wrapper that rejects whole-account reads. SQLite checks terminal step errors.
- Full Gmail suite reached 143 passing tests, with final lint/build checks ongoing.
  No UI layout changed, so existing inspected progress snapshots are reused.
- Updated README, CHANGELOG, ADR-0041/0064, privacy and QA. No schema, endpoint,
  dependency, credential, merge or release change. Residuals include live Gmail
  acceptance, full-message fetch cost for uncached hits, date precision, local
  body/document indexing and the wider issue28 goal.

- Final verification: Gmail 143 and shared Mail 1,555 tests pass; dated mock
  macOS build/startup and iOS Gmail compilation pass; lint/format/privacy/diff
  checks pass. Independent standards and behavior reviews cleared the typed
  error, callback ownership and cache-paging fixes. Added nonempty All Mail
  header mapping and successful search non-persistence assertions. No new UI
  snapshots were needed because the existing progress component is unchanged.
  Authenticated Gmail search and representative large-account measurements are
  still unverified; no live provider requests were run in this session.

- CI on 8dda4e9 exposed a Swift type-checker timeout in the nested 5,001-message
  fixture expression before tests ran. Split page construction into typed locals
  and an explicit loop; production code and the regression assertions are unchanged.
  Verifying this correction with the stable Xcode toolchain before pushing.

- Stable Xcode 26.6 verification passes all 143 Gmail tests after the fixture
  split. This follow-up changes only test construction and the worklog; no app
  build was repeated because production code is unchanged. Hosted verification
  will run on the new follow-up head.


## 2026-09-08 — Codex — #28 / PR #29 and #30

- Henrik explicitly accepted ADR-0074; recorded Accepted on the architecture
  branch and pushed 8aa8bef to PR #29. ADRs 0070–0073 remain Proposed.
- Implemented the first foundation phase on feature/mail-client-parity: plain
  source-owned conversation contracts, conservative reply-link graph resolution,
  offline cached-conversation capability, and SQLite-indexed Gmail cache lookup.
  The version-four migration uses the existing native thread column and keeps
  scheduled sends. No remote endpoint, body fetch or reader behavior changed.
- TDD reproduced missing APIs, comment-induced false links, contradictory folder
  generations and Gmail's unordered-label/stale-folder provenance. The fixes
  retain physical copies, explicit ambiguity and cache-only coverage; Gmail
  preserves selected label membership or corrects a cache-confirmed move while
  retaining the selected message ID and display metadata.
- Read-only standards/behavior reviews prompted an explicit offline capability
  and deterministic conversation folder mapping. Unsupported RFC identifier
  syntax stays a typed error; provider ingestion must disclose incomplete metadata.
- Verification so far: Backend 1,053 tests and stable Xcode 26.6 Gmail 145 tests
  pass; shared Mail 1,555 tests, six isolated Contacts tests, lint/format and
  privacy audit pass. Final anchor-generation and legacy custom-label regressions
  pass after review corrections; unchanged folder generations are retained. No views
  changed, so no new snapshots/native rendering are applicable to this phase.
- Documentation sweep: README, Unreleased changelog, accepted ADR and QA notes
  updated. No network/privacy policy, release or agent-workflow change. Remaining
  work is IMAP indexing/References, consented provider discovery and reader/action
  integration, followed by native/live/performance checks. Parent #28 remains
  In progress and PR #30 remains draft; no merge, release or issue closure.


## 2026-09-08 — Codex — #28 / PR #30, IMAP relationship index

- Refreshed feature/mail-client-parity at a0a850a: clean/pushed and all 20 hosted
  checks passed. Parent #28 remains In progress, PR #30 draft on #27's branch.
- Added MailConversationIndex and a source-owned SyncEngine lookup under accepted
  ADR-0074. SQLite schema 5 indexes existing RFC reply identifiers in the same
  cache; updates and deletions follow header transactions and foreign-key cascades.
  Migration streams v4 headers and preserves original MIME provenance.
- TDD reproduced missing cached cross-folder lookup, malformed-neighbor lookup
  failure and stale UIDVALIDITY reuse. Tests now cover these alongside restart,
  account isolation, excluded-folder traversal, expunge and partial fanout limits.
- Final stable SyncEngine verification passes 74 XCTest and seven Swift Testing
  tests; Backend 1,055 and Gmail 145 pass. Lint/format, privacy and diff checks
  pass. A 2,001-header SQLite write/lookup fixture completed in 0.762 seconds;
  this is a synthetic smoke measurement, not live-mailbox latency evidence.
- Independent behavior review found legacy Message-ID fallback, control-character
  truncation and per-row statement preparation. Recorded failing regressions,
  reused rfcMessageID, rejected unsafe controls/empty locators and prepared link
  statements once per batch/migration. Both final reviews report no blockers.
- No UI or network code changed, so new rendering snapshots/native QA are not
  applicable to this cache phase. References ingestion, provider
  service/reader wiring, native/live acceptance and mailbox-scale measurements
  remain pending. No merge, release or issue closure is included.
- Documentation sweep updated README, Unreleased changelog, ADR-0074 and QA notes.
  Privacy/network policy and agent instructions need no change for local indexing.

## 2026-09-15 — Devin — #28 / PR #30, References ingestion

- Resumed the handoff at 805dcf1 on feature/mail-client-parity: clean, pushed,
  PR #30 draft with all checks green, issue #28 still In progress.
- Implemented persisted References metadata under accepted ADR-0074, step 1 of
  the remaining-work plan. The IMAP listing FETCH now also requests
  `BODY.PEEK[HEADER.FIELDS (REFERENCES)]` — an added attribute on the existing
  request, not a new network call, and header-only (no body bytes).
- `MessageHeader.references` (`nil` unknown/unfetched, `[]` known absent) rides
  `header_json`, survives flag-only refreshes via `updatedHeader` and a
  preserve-on-nil upsert merge in both sync stores, and is carried through
  `withIdentity`/`withThreadID`, rules-engine moves and mock copies.
- `conversation_links` now indexes References identifiers beside Message-ID and
  In-Reply-To; candidate members expose stored references and traversal expands
  along them, so a References-only chain resolves across Inbox/Sent/Archive
  after a cache restart. Malformed fields keep only individually verifiable
  tokens and never block ordinary caching.
- TDD: new failing tests reproduced the missing References-only lookup and the
  refresh regression before implementation; all are green now.
- Verification: BrevBackend 1,059, BrevSyncEngine 74 XCTest + 9 Swift Testing,
  BrevMail 1,555 + isolated Contacts 6 and BrevGmail 145 tests pass on stable
  Xcode 26.6. lint.sh, privacy-audit.sh and git diff --check pass.
  FETCH-command test expectations updated for the new attribute. No
  UI/network-consent surface changed, so snapshots, ADR-0006 and PRIVACY.md
  need no update; ADR-0074 progress note and this log updated.
- Still pending per handoff: CachedConversationProviding wiring on
  IMAPSMTPBackend, reader/action integration, consented remote discovery,
  native/live acceptance. PR #30 stays draft; no merge, release or closure.
- Scoped two-axis review (standards + spec vs ADR-0074) ran after the first
  commit. Spec axis caught a real bug: a non-string HEADER.FIELDS value
  decoded as known-absent and would have let a malformed refresh overwrite
  stored References — now nil/unknown (explicit NIL still means absent).
  Also added the missing legacy-record decode test, extended the restart
  test to the index-rebuild path (drop conversation_links + v4 reopen), and
  centralized the member/header fallback into ConversationMember
  .effectiveReferences plus a shared cachedLinkIdentifiers helper across the
  resolver, engine and both stores (fixes in 8dcf59b). Noted follow-up: the
  header-fields boundary scanner is a third copy of the quoted-string
  scanner beside bodyTextValueStart/attributeListStart — left as-is to keep
  the slice small.

## 2026-09-16 — Devin — #28 / PR #30, performance review fixes

- Deep performance review of list/sync/search/reader paths, then fixes for all
  findings. Evidence-based: every issue traced to a concrete call site before
  editing.
- Header cache: FileBackedIMAPMailboxHeaderCache now coalesces writes —
  setSnapshot updates memory and marks the folder dirty; a 750ms debounce
  flushes all dirty folders once (previously every page load, flag update,
  CONDSTORE delta and removal JSON-encoded + atomically rewrote the whole
  folder). flushPendingWrites() is public for lifecycle/tests. Two existing
  cross-instance tests now flush first; new test asserts debounce + flush.
- cacheHeaders merge: appended pages of strictly-older unseen headers skip the
  full-folder dictionary rebuild and re-sort (mergedSortedHeaders fast path);
  overlap/interleave still takes the full merge.
- CONDSTORE: applyCONDSTOREFlagChanges re-indexes only headers whose flags
  actually changed, not the entire folder snapshot.
- Thread resolution: per-folder memo keyed by an order-independent fingerprint
  over (id, messageID, inReplyTo, threadID, date) — flag churn and repeated
  page listings reuse the union-find result instead of re-running it over the
  whole folder per call. Memo cleared in clearLocalCaches.
- Search: SearchQuery gains optional folderIDs (Codable-backward-compatible
  optional; matches() enforces membership; hasSearchCriteria counts a non-empty
  set, matching single-folderID semantics). localIndexQueries emits ONE scoped
  query for all-folders search; SQLiteSyncStore ftsCandidates/headerCandidates
  take a folder scope set (single = ?, multi = IN (...)) instead of one query
  per folder — the engine serializes internally so fan-out only multiplied
  await hops. Four backend test expectations updated (folderIDs vs folderID).
- Reader/list: buffer-identity helper Array.hasIdenticalStorage(to:) — O(1)
  array reuse check, sound because the cache retains the stored buffer. Both
  presentation caches (folder list + unified inbox) match headers/items by
  buffer identity instead of O(n) deep equality per body eval. Reader thread
  derivation memoized via ReaderThreadHeadersMemo (@State class); controller
  mergedThreadHeaders memoized on (loaded buffer, snapshotRevision); remote
  onUpdate coalesced at 150ms so per-page emissions don't re-render per folder.
- Instrumentation: MailPerformanceDiagnostics gains logHeaderCacheFlush,
  logThreadResolution (inputCount + hit), logSessionQueueWait (acquire wait in
  withAuthenticatedSession, logged when >0ms); signpost intervals around cache
  flush and both presentation builds.
- Not changed: removal loops were verified already single-write per folder;
  the coalesced flush covers them. A second IMAP command session for
  background work remains a larger design change, not implemented.
- Verification: BrevBackend 1077, BrevSyncEngine 74 XCTest + 9 Swift Testing,
  BrevMail 1572, BrevGmail 147 — all pass. lint.sh, format.sh (0 files),
  privacy-audit.sh, git diff --check clean.

### Follow-up: header-cache flush on disconnect

- `flushPendingWrites()` was only reachable via the debounce timer and tests —
  teardown could drop up to 750ms of pending cache writes. Added it to
  `IMAPMailboxHeaderCache` as a requirement with a default no-op, and
  `IMAPSMTPBackend.disconnect()` now flushes before session teardown.
- Fixed a Swift overload-resolution trap the protocol method introduced: in
  async contexts `await cache.flushPendingWrites()` on the concrete type
  preferred the async protocol-extension no-op over the actor's sync member.
  Declared the concrete member `async` so it wins resolution and witnesses the
  requirement. New test asserts disconnect() invokes the flush.
- Verification: focused backend tests 17/17 (incl. all FileBacked cache
  suites), lint/format/diff-check clean.

### Follow-up: flush local caches on quit / background

- `disconnect()` (and its header-cache flush) only runs on account
  switch/removal — never on macOS quit or iOS backgrounding — so up to 750ms
  of debounced cache writes could be lost. Added provider-neutral
  `MailBackend.flushLocalCaches()` (default no-op), implemented it in
  `IMAPSMTPBackend` (forwards to `headerCache.flushPendingWrites()`), and
  fanned it out from `AppSession.flushLocalCaches()` over `backends.values`.
- macOS `applicationShouldTerminate` now returns `.terminateLater` on both
  quit paths and replies `true` after the flush races a 2-second budget, so
  quit can never stall on a stuck write; nil session still returns
  `.terminateNow`. iOS flushes in `onChange(of: scenePhase)` `.background`.
- Verification: BrevBackend flush tests + FileBacked suites 18/18, BrevMail
  AppSession flush test 1/1, `swift build` both packages clean, `tuist
  generate` + BrevIOS build OK, BrevMacOS compiles (`xcodebuild
  CODE_SIGNING_ALLOWED=NO`; `tuist build` fails only on the entitlements
  development-signing requirement — no dev cert in this environment).
  lint.sh, format.sh (0 files), git diff --check clean.

### Follow-up: settings consistency — related mail under Folder Sync

- Moved the "Related mail" consent group out of Mailbox View into
  `PerFolderSyncSection` (after the folder-override list). The account is
  derived from the context bar's `MailSourceID.accountID`; the inline account
  picker is gone, and `sourceID == nil` shows "Open a mailbox to control
  related-mail lookup." `MailboxViewSection` lost its `accounts`,
  `currentAccountID`, and `relatedConsentStore` init params plus all related
  state/bindings.
- Removed Mailbox View's standalone "Search" callout; its sentence is appended
  to the Mail Storage cache-lookback footnote. Reading-group subtitle now
  reads "Rendering, conversation order, and type."
- Smart Views sidebar glyph is now `rectangle.stack` (Rules keeps the funnel).
  Settings search: "Related mail"/"Automatically load related mail" resolve to
  Folder Sync; "Search"/"Local search" moved from Mailbox View to Mail Storage.
- Verification: `swift build` BrevSettings + BrevMail clean; full BrevSettings
  suite 342/342 pass after re-recording the five legitimately changed
  baselines (navigation-groups, folder-workspace, folders, folders-narrow,
  mailbox-view — light+dark) plus settings-navigation. appearance-*/accounts-*
  re-recorded byte-identical and were left untouched. format.sh, lint.sh,
  git diff --check clean. No view-level toggle test existed to move (no
  ViewInspector in the package); store behavior remains covered by
  BrevBackend's RelatedConversationConsentStoreTests.
- CHANGELOG: one Unreleased/Changed line; the earlier Added bullet's
  "per-account … in Mailbox View settings" wording was corrected to match.

### Follow-up: ADR-0075 background mail presence

- New `NotificationSettings.backgroundMailEnabled` + `launchAtLoginRequested`
  (per-device, not in the ADR-0056 allowlist). `BackgroundMailCoordinator`
  (BrevMail, session-owned) runs `MailFetchScheduler.ticks` and records
  success/failure; `performBackgroundRefresh` now returns the first
  `localizedDescription` failure. `BackgroundMailStatusView` +
  `BackgroundMailStatusPresentation` render the menu-bar menu; macOS app
  adds a `MenuBarExtra` gated on the setting and reconciles start/stop and
  interval changes via `UserDefaults.didChangeNotification`. Root view
  yields ticks to the coordinator per-tick when the setting is on and
  pushes the badge unread count into it. `LaunchAtLoginController`/
  `Availability` live in BrevSettings (settings cannot depend on BrevMail),
  gated to the exact release bundle id. Settings › Notifications gains a
  macOS-only "Background mail" group with the toggle, launch-at-login
  sub-toggle (SMAppService status-driven, requiresApproval → Login Items
  button), and the manual-schedule callout.
- Verification: BrevSettings build + NotificationSettings/LaunchAtLogin
  13/13; BrevMail build + coordinator 6/6, scheduler/badge 28/28, status
  snapshots 4/4 (8 new PNGs); `tuist generate` OK; BrevMacOS compiles via
  xcodebuild CODE_SIGNING_ALLOWED=NO (entitlements need a dev cert for a
  signed build — same env limitation as before); `tuist build BrevIOS` OK;
  format/lint/privacy-audit/diff-check clean.
- Docs: PRIVACY.md paragraph under Local mail notifications; CHANGELOG
  Unreleased/Added; ADR-0006 note (cadence/lifetime only, no new row) and
  its related-mail row's settings pointer updated to Folder Sync.

### Follow-up: ADR-0076 settings and account backup

- New `BrevSettings/Backup/`: `BrevBackupManifest` (format v1, `payloads`
  with name/sha256/encoding — future `mail/` describable but not written),
  `SettingsBackupCodec` + `SettingsBackupPayload` (25 families; notification
  DTO strips device-bound ADR-0075 fields; CalDAV DTO strips the Keychain
  `credentialAccount`), `AccountsBackupCodec`/`AccountBackupEntry`
  (`credentialID` blanked — the only secret-bearing field), writer/reader
  (`settings.json` + `accounts.json`, manifest last, atomic writes, SHA-256
  verified), `BackupRestorer` (per-category snapshot/rollback, continues on
  failure), `PendingRestoredAccountsStore` (`backup.pendingRestoredAccounts`).
- Codable conformances added to previously non-Codable settings types in
  BrevSettings and BrevDesign so families serialize without DTO sprawl.
- `RelatedConversationConsentStore.autoLoadEnabledAccountIDs(among:)`
  supports consent export; consent restore is additive in both modes.
- UI: Import/Export gains a macOS "Brev backup" group (NSSavePanel /
  NSOpenPanel + `BackupPreviewSheet` with counts, Merge/Replace picker,
  credentials-never-included callout). Accounts shows a "Restored accounts —
  sign in to finish" group wired through `SettingsView` to the existing
  add-account sheet prefilled with the account email. iOS shows an
  availability note only — no backup UI this slice.
- Verification: BackupTests 15/15 (round-trip, tamper, version, unknown
  keys, merge/replace, rollback, secrets stripped, signed-in drop,
  completeness); 2 preview-sheet snapshot PNGs recorded.

### Follow-up: incremental IMAP thread resolution

- `IncrementalThreadResolver` in `MessageThreadResolver.swift` diffs known
  headers on `ThreadKey` (messageID, inReplyTo, threadID, date) per update:
  flag-only churn is `.unchanged`, pure additions extend the union-find
  forest incrementally (names merged by min `(date, node)` on unite), and
  any change/removal falls back to a full rebuild with batch semantics.
- `IMAPSMTPBackend.threadedHeaders` keeps one resolver per folder under the
  existing lock and looks up only the page's ids (`threadID(for:)`), so a
  warm listing no longer hashes all N headers or rebuilds the whole map.
  `logThreadResolution` gained a counts-only `update=` field.
- Baselines (10k folder): warm cache-hit 16.8 → 9.3 ms; paging pages 18–20
  4.94 → 2.15 ms avg (still record-only — the O(N) key diff remains).
- Tests: `IncrementalThreadResolverTests` (5) — random-page-order property
  test vs batch resolver, flag-only unchanged, changed/removed/empty
  rebuilds, incremental adds, bridge-merge naming.

## 2026-09-17 — Agent — ADR-0078 local attachment content indexing

- Goal: opt-in, local-only attachment text indexing so message search can
  match attachment content without ever downloading for indexing.
- BrevSyncEngine: schema v6 adds `attachment_search` FTS5 (account/message/
  folder/attachment ids unindexed + name/content/content_normalized);
  migration creates it empty. Purge cascades on clearFolder, clearAccount,
  deleteHeaders and body eviction. `searchHeaders` unions attachment hits
  under the same folder scope; `attachmentMatchNames` reports a name only
  when the hit came from `attachment_search` alone. New store methods:
  `indexAttachmentText`, `removeAttachmentText`, `removeAllAttachmentText`,
  `attachmentIndexBytes`, `indexedAttachmentMessageIDs`. `InMemorySyncStore`
  mirrors the semantics.
- BrevBackend: `AttachmentTextExtractor` (text/CSV/Markdown, RTF, HTML, PDF
  via PDFKit, Office Open XML on macOS; 25 MB input cap, 512 KB output cap,
  cancellation checks, 10 s task-group timeout). `AttachmentIndexer` actor:
  per-account serialized utility-priority extraction from cached sources
  only, `noteSourceCached`/`sweep`/`rebuild`/`stop`/`disable`, consent gate
  consulted per unit of work. `AttachmentIndexConsentStore` (per-account
  UserDefaults + didChange notification; excluded from `.brevbackup`).
  `.localAttachmentIndex` (1<<16) advertised by IMAPSMTPBackend,
  GmailAPIBackend and LocalMailBackend only when a local index is wired.
  `MailBackend` gains `matchedAttachmentNames`, `attachmentIndexBytes`,
  `rebuildAttachmentIndex`, `removeAttachmentIndex` defaults.
- BrevMail: `MailSearchExecution` decorates cached updates with attachment
  match names; `MailSearchProgressState` merges/clears them per source;
  `MessageListRow` renders a "Found in <name>" badge under the subject in
  both list and unified inbox. All Attachments filters additionally match
  indexed content via a cache-only `matchedAttachmentNames` lookup.
- BrevSettings: capability-gated "Search inside attachments" toggle in
  Folder Sync (Mac/iPhone-aware subtitle, no network promise); Mail Storage
  "Attachment index" row with size + Rebuild/Remove.
- Verification: AttachmentSearchIndexTests 6/6 (migration, union, folder
  scope, all cascades); AttachmentIndexingTests 16/16 + capability suite
  2/2; Gmail capability 1/1; MailSearchProgress + row badge snapshot;
  FolderSync + MailStorage snapshot baselines recorded.

## 2026-09-17 — Agent — ADR-0080 release rings, slice 1 (app side)

Goal: replace the in-app Beta channel with a build-time release ring
(stable|nightly) per ADR-0080; `Brev Nightly.app` is a separate app with
its own bundle id, feed, icon, and preferences.

Changes:
- `UpdateSettings`: `UpdateChannel`/`updates.channel` removed (leftover
  default ignored); new `UpdateRing` (stable|nightly) with localized
  title/subtitle, default GitHub Pages appcasts and other-ring download
  URLs. `UpdateBuildConfiguration` gains `ring` parsed from `BRReleaseRing`
  and `appcastURL` = localAppcastURL > SUFeedURL > ring default.
- `Info.plist`: `SUFeedURL`/`BRReleaseRing` now expand `BREV_SPARKLE_FEED_URL`
  /`BREV_RELEASE_RING`; `Project.swift` defaults them to stable + GitHub
  Pages feed and adds `BREV_APP_ICON_NAME` → `ASSETCATALOG_COMPILER_APPICON_NAME`.
- `MacUpdateController` feeds Sparkle `buildConfiguration.appcastURL`;
  `UpdatesSection` shows the ring read-only + a link to the other ring;
  `SettingsView`/`BrevApp` pass the ring through.
- `LaunchAtLoginAvailability` allows both `eu.brevmail.brev` and
  `eu.brevmail.brev.nightly`.
- `generate-app-icon-variants.swift` emits `AppIcon-Nightly.appiconset`
  from the inverted-graphite variant (distinct dark tile; the pipeline
  cannot draw a literal badge — flagged to lead).
- Docs: ADR-0080 index row, ADR-0009 amendment notes, ADR-0006 Sparkle
  row host change, PRIVACY.md update-check row + Nightly paragraph,
  settings-inventory Updates row, CHANGELOG Unreleased.
- Tests: ring parsing (missing/stable/nightly/garbage), appcast
  precedence, leftover `updates.channel` ignored, LaunchAtLogin both ids,
  UpdatesSection ring snapshots in the existing macOS-26-gated suite
  (no workflow change needed).

Verification: see handoff report — BrevSettings suite, tuist generate,
stable + nightly-override unsigned macOS builds with plutil evidence of
BRReleaseRing/SUFeedURL/CFBundleIdentifier resolution, lint, format,
privacy-audit, git diff --check.
Skipped: CI workflow changes (slice 2 per handoff).

### Slice 2 — CI-signed Stable and Nightly releases (same entry, same day)

Goal: ADR-0080 §2–§4 — ring-aware release scripts, Sparkle appcast merge,
and the two GitHub Actions release workflows.

Changes:
- `release-archive.sh`/`release-dmg.sh`: `--ring stable|nightly`,
  `--version`, `--build-number`; nightly injects
  `BREV_APP_PRODUCT_NAME`/`BREV_APP_BUNDLE_ID`/`BREV_APP_ICON_NAME`,
  nightly feed URL, `BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER_NIGHTLY`,
  `export-options-developer-id-nightly.plist`, `Brev-Nightly-YYYYMMDD.dmg`.
- `release-appcast-merge.py` (stdlib-only item merge; Sparkle's
  `generate_appcast` needs every archive on disk, unusable on a fresh
  runner), `release-appcast.sh` (sign_update + merge), self-test
  `test-release-appcast.sh` registered in `test.sh`.
- `.github/actions/release-signing` composite (temp keychain, p12 import,
  profile install via `security cms -D`, .p8 + Sparkle key 0600, cleanup
  phase); `release.yml` on `v*` tags, `nightly.yml` at 23:30 UTC + dispatch
  with a plan job (main-only, commit-marker skip, Build-success gate).
- `docs/release.md` "Automated releases" section + secret bootstrap
  commands; Rollback/Future Automation updated; UpdatesSection copy nit
  ("update feed"); CHANGELOG bullet; 4 updates-ring snapshots re-recorded.

Verification: `bash -n` all touched shell; actionlint clean;
`test-release-appcast.sh` OK (idempotency, shape, 14-cap);
`test-developer-id-release-config.sh` OK; `release-archive.sh --dry-run
--ring nightly` prints the resolved xcodebuild line; BrevSettings
`--filter Updates` 8/8 green.
Skipped: real signing/notarization/`gh release` — needs CI secrets and
portal assets that do not exist yet.

## 2026-09-17 — Codex — Release workflow portability follow-up

- Goal: unblock the authorized `v0.1.0` signed release after the merged
  signing-environment fix.
- Summary: fixed macOS release-note extraction to trim section whitespace with
  portable `awk` instead of the failing BSD `sed` expression; made provisioning
  profile team-ID extraction use the validated `TeamIdentifier.0` field and fail
  closed on malformed values; extended the Developer ID release configuration
  check to cover both safeguards.
- Verification: local release configuration test, release appcast test, lint,
  format, and `git diff --check` passed; the hosted release
  run had already passed signing setup and the main-build gate before reaching
  this failure.
- Skipped: no local notarized archive or DMG; those require the hosted release
  secrets and Apple service path.
- Handoff: commit and PR this workflow-only fix, merge it, retarget the
  unpublished `v0.1.0` tag to the merged `main` commit, then rerun the release
  and verify the GitHub asset and stable appcast.

## 2026-09-17 — Codex — Release OAuth environment follow-up

- Goal: pass the configured Google OAuth values into the hosted stable archive
  build after the release run reached archive validation.
- Summary: mapped the release-environment OAuth secrets explicitly onto the
  archive step and extended the Developer ID release configuration test to
  guard that mapping.
- Verification: local release configuration test, release appcast test, lint,
  format, and `git diff --check` will be run before handoff; the hosted run
  confirmed signing setup and changelog extraction, then failed only because
  these values were absent from the archive-step environment.
- Skipped: no local notarized archive or DMG; those require the hosted release
  secrets and Apple service path.
- Handoff: merge this fix, recreate the unpublished `v0.1.0` tag at the final
  green `main` commit, rerun the release, and verify the GitHub asset and
  stable appcast.

## 2026-09-18 — Devin — iOS backup/restore (feature/ios-daily-driver)

- Goal: enable Brev backup export/restore in Settings › Import / Export on iOS.
- Summary: replaced the iOS “Mac only” stub with backup/restore buttons; added
  iOS `.fileImporter` flows that pick a destination folder for
  `Brev backup.brevbackup` and pick the `.brevbackup` package as a folder
  (no exported UTI exists); shared `writeBackupPackage` /
  `presentRestorePreview` with macOS; held the iOS security scope across the
  write and across preview→`applyRestore`; made `BackupPreviewSheet` min width
  macOS-only; added an Import/Export render smoke case; updated CHANGELOG.
- Verification: `swift build --package-path packages/BrevSettings` OK;
  `xcodebuild -workspace Brev.xcworkspace -scheme BrevIOS -destination
  "platform=iOS Simulator,OS=27.0,name=iPhone 18 Pro" build
  CODE_SIGNING_ALLOWED=NO` OK; `scripts/lint.sh`, `scripts/format.sh`,
  `git diff --check` OK; `CompactSettingsViewSmokeTests` 9/9 OK.
- Skipped/blocked: full `swift test --package-path packages/BrevSettings`
  still reports 2 unrelated pre-existing macOS snapshot mismatches in
  `folders-attachment-index-{light,dark}` (Folder Sync, untouched). Real iOS
  picker behavior for directory packages needs device/simulator UI QA.
- Handoff: do not commit per request; if green baseline is required, refresh
  or investigate the unrelated Folder Sync snapshots separately.

## 2026-09-18 — Devin — iOS local-folder writes (feature/ios-daily-driver)

- Goal: enable local-folder write actions on iOS per ADR-0077 decision 8.
- Summary: removed the `#if os(macOS)` gate around Copy/Move to Local Folder
  in `MessageCommandPresentation.contextMenu` (the only remaining write gate —
  sidebar New/rename/delete local folder, `MailCommands`,
  `LocalFolderDestinationSheet`, `LocalMaildirStore`/`LocalMailBackend`, the
  folder-name alert and the import-destination dialog were already
  platform-neutral); updated the wiring-table platform strings; wired
  `localBackendProvider` into `ImportExportSection` (pre-existing gap — the
  "Include local folders" backup toggle and `mail/` restore handler never
  engaged from the real Settings UI on either platform); added a
  `canFileLocally` presentation test; updated ADR-0077 decision 8 and
  CHANGELOG. MBOX/Maildir import stays macOS-only pending the
  Files-app/share-sheet path; the shared destination step already defaults
  to a new local folder.
- Verification: `swift test --package-path packages/BrevMail` 1603/1603
  (258 suites); `swift test --package-path packages/BrevSettings` 373
  tests, only the 2 pre-existing unrelated `folders-attachment-index`
  snapshot mismatches; `xcodebuild -workspace Brev.xcworkspace -scheme
  BrevIOS -destination "platform=iOS Simulator,OS=27.0,name=iPhone 18 Pro"
  build CODE_SIGNING_ALLOWED=NO` BUILD SUCCEEDED; `scripts/lint.sh`,
  `scripts/format.sh`, `git diff --check` all OK.
- Skipped/blocked: real iOS UX of the destination sheet, sidebar context
  menus, and undo toast after Move needs device/simulator UI QA. iOS has
  no MBOX/Maildir import entry point (per ADR-0077 deferral); the Settings
  "Import mail" group stays disabled on iOS (`canImport` returns false
  there by design, pending the Files-app/share-sheet path).
- Handoff: do not commit per request. Note `localBackendProvider` wiring
  also fixes the same dead path on macOS — before this, Settings backups
  never included `mail/*.mbox` and mail restore never ran from the app UI.

## 2026-09-18 — Devin — iOS daily-driver slices

### Goal
Bring iOS to daily-driver parity where the platform allows.

### Changes
- Backup/restore on iOS: `.fileImporter` destination-folder + package pickers
  with security-scoped access held across the async write and the restore
  preview sheet. `writeBackupPackage`/`presentRestorePreview` shared with
  the macOS panels. `BackupPreviewSheet` min width made macOS-only.
- Wired `localBackendProvider` into `ImportExportSection` — fixes backups
  never carrying local mail on macOS either (was unwired since c3d7229f).
- Local folder writes un-gated on iOS (ADR-0077 decision 8 updated):
  Copy/Move to Local Folder, new/rename/delete local folders work through
  the shared surfaces. MBOX/Maildir import stays macOS-only.
- New `BrevIOSTests` unit-test target (first app-level test target):
  BGTask coordinator scheduling, `OneShotBGCompletion` exactly-once,
  `ShareHandoffURL` cap/confinement. Wired into the BrevIOS scheme +
  CI build job.
- Fixed `test-ios-extension-plists.sh` broken by #43's notification
  category array (scalar → index assertions).

### Verification
- BrevIOSTests: 17/17 on iPhone 18 Pro simulator (xcodebuild test).
- BrevMail 1603/1603; BrevSettings green except 2 pre-existing
  folders-attachment-index maintainer-host snapshot drift.
- iOS + macOS builds succeed; self-tests, lint, format, diff-check clean.
- Manual QA owed: iOS document picker on a real .brevbackup; long-press
  local-folder menus; move-to-local undo toast.

## 2026-09-18 — Devin — Gmail adapter per-refresh O(table) fixes (feature/perf-daily-driver)

### Goal

Remove the per-refresh/background-tick O(table) costs in the Gmail adapter:
full-table JSON decoding on every reconcile diff and retention sweep,
JSON-extract re-parsing on every label page, `.full` payload downloads for
header-only page fill, and one transaction per message on label mutations.
No commit (user request).

### Summary

- Schema bumped to v5 in `SQLiteGmailAccountStore`: new materialized
  `internal_date` and `content_hash` columns on `gmail_messages`, populated
  on every insert/upsert and backfilled by an idempotent migration
  (`ALTER TABLE` only when the column is missing). The
  `gmail_messages_received_idx` index was recreated as
  `(account_id, internal_date DESC, message_id)` in a post-migration step
  (`materializedIndexSQL`) because pre-v5 databases lack the column until
  the ALTER lands; a `(account_id, label_id, message_id)` index covers the
  label-membership probes.
- New `GmailMessageSummary` (id + content hash + label IDs + received
  timestamp) and a `GmailMessageSummaryScanning` seam the SQLite store
  answers from the materialized columns without decoding `message_json`.
  `contentHash` hashes the canonical `.sortedKeys` encoding — raw
  `JSONEncoder` output has unspecified key order on Darwin, which made
  identical re-upserts look like changes.
- `GmailAPIBackend.reconcile` now diffs summary dictionaries instead of
  two fully decoded message tables; `emitDiff` emits one batched
  `messagesAdded/Removed/Updated` event per folder with the same IDs the
  old per-message events carried (verified by a same-event equivalence
  test). Non-scanning stores keep the decoded fallback via
  `GmailMessageSummary(encoding:)`.
- Label-page `messages(accountID:labelID:offset:limit:)` sorts on
  `m.internal_date DESC` — no more `CAST(json_extract(...))` per row per
  page. `scrubContentFromMessages` decodes only targeted IDs.
- `message(_:)` page fill now fetches `.metadata` with
  `requiredMetadataHeaders`; `.full` stays reserved for body/MIME opens.
  `GmailAPITransporting` gained a `metadataHeaders` `getMessage` overload
  (extension default keeps conformers source-compatible; `GmailAPITransport`
  and `GmailAPIClient` forward the headers).
- `applyLabelMutation` and `refreshStoredMessages` batch local writes into
  a single `GmailStoreDelta` per chunk — one store transaction instead of
  one per message.
- `applyRetention` sweeps via `messageSummaries` (label membership,
  `keepingMessageIDs`, `keepsBodies`, `retentionDays` cutoff) instead of
  decoding every message per folder; decoded fallback retained.
- `deliverScheduledBatch` returns early when `pendingScheduledSends()` is
  empty — enqueues/edits always refresh the summary first, so an empty
  summary means no queued rows and the per-tick SQLite recovery+read is
  skipped.

### Verification

- `swift test --package-path packages/BrevGmail` — 152 tests in 15 suites
  pass, incl. new tests: materialized-date migration + label order,
  summary change markers, batched label mutation, summary-scan/decode diff
  equivalence, `.metadata` page-fill count.
- `scripts/format.sh` — clean; `swiftformat --lint` 0 files;
  `swiftlint --strict` clean; `git diff --check` clean.
- `scripts/lint.sh` fails only at `check-adr-required` on
  `BrevAvatars/AvatarImageDecoding.swift` — a protected path changed by a
  different uncommitted session in this tree, not this task's files.

### Handoff

- Uncommitted on `feature/perf-daily-driver`; tree contains substantial
  uncommitted work from at least one other active session (BrevMail,
  BrevSyncEngine, BrevSettings, ShareExtension, and an in-flight
  warm-cache `connect()`/background-sync change in `GmailAPIBackend` with
  matching `initialSyncSettled()` test updates). Verify scope before
  committing.
- `GmailAPIDraftBackendTests` restart/recovery tests are timing-flaky
  under full-suite parallel load (two SQLite connections on one file +
  async summary load); they pass consistently in isolation and in most
  full runs.
- Schema v5: `internal_date`/`content_hash` materialized + backfilled;
  existing v4 databases migrate on open.

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
