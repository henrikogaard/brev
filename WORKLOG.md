# Worklog

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


## 2026-09-24 — Agent — Fix ComposePresentationTests overflow expectations

- `ComposePresentationTests` expected `overflowActions` without the new
  `.discardDraft` entry added in a367be9; updated the macOS + compact-iOS
  expectations and the accessibility value string so the BrevMail suite
  passes on this branch. Verified: `swift test --filter ComposePresentation`
  (57 tests green).

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
- swift build clean for 