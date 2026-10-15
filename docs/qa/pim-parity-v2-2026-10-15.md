# Calendar/Contacts parity evidence v2 — 2026-10-15

**Bottom line:** implementation is present; #11 remains an evidence and
maintainer-acceptance gate for #3. This pass performs automated regressions,
not a new UI, stub-server, real-provider or physical-device run.

| Provenance | Value |
| --- | --- |
| Issues | [#11](https://github.com/henrikogaard/brev/issues/11), parent [#3](https://github.com/henrikogaard/brev/issues/3) |
| Base tested | `3a553ddbf754a0adb110598dec48108e8a7e8b41` (`origin/main` at start) |
| Branch / target | `fix/pim-parity-gaps` → `main` |
| Changes | This new evidence report and an appended WORKLOG entry only; no product behavior changes |
| Authorization | Parallel implementation request, **not** approval to drive UI or access live PIM data |
| Preserved evidence | [Original matrix](pim-parity-matrix.md), [Oct 3 stub report](pim-parity-stub-dav-2026-10-03/README.md), all existing screenshots/logs unchanged |

## Scope and reconciliation

- ADR-0072 is **Accepted** (2026-09-20). #3 does not need rebuilding or a new
  authoring decision. ADR-0084 remains **Proposed**: its supersession prose
  (and the anticipatory note in ADR-0072 rule 6) does not authorize an offline
  replay queue. No queue is implemented by this pass.
- #239 sign-in and #14 Drive belong to other work. This report does not certify
  either and does not add their scopes to the PIM acceptance contract.
- Historical results below are attributed to their recorded runs, not rerun
  claims. Shared code and unit success never substitute for platform runtime
  or real-provider evidence.
- The original matrix's final “stub DAV complete” labels overstate its blank
  cells. Its “Live providers” row records IMAP/SMTP, not live CalDAV/CardDAV
  or Google Calendar/People acceptance. Do not close #11 from that summary.

| Existing evidence | Reconciled meaning / remaining gap |
| --- | --- |
| Oct 3 matrix 2.7 | iOS simulator attendee add/remove and conditional PUT passed on stub. Not invitation delivery; stub has no scheduling service. |
| Oct 3 matrix 2.8 | iOS simulator accept/maybe/decline PARTSTAT round-trip passed. Not real-provider notification delivery. |
| Oct 3 matrix 4.3 | iOS **foreground-idle** scheduled pickup passed with Background sync ON and 5-minute cadence. Not suspended/terminated iPhone execution. macOS timed pickup remains unproven. |
| O7–O10, O12 | Already fixed by [#190](https://github.com/henrikogaard/brev/pull/190), commit `9b64876`: readable error text, localized RSVP, organizer attribution, attendee validation, source-row observation. Oct 5 WORKLOG records macOS nb/stub verification; ADR-0072 implementation log and current source confirm these are not new implementation tasks. |
| O9 organizer | Current DAV create/update fills missing organizer when attendees exist; parser/writer retain URI values. This repairs payload attribution but does not prove a real scheduling server accepts the organizer or delivers invitations. |
| O11 theme | Already fixed in [#187](https://github.com/henrikogaard/brev/pull/187); Oct 3 report includes before/after captures. No theme rewrite here. |
| Platform localization | Matrix 5.3's English-only note predates nb translations and #190. Oct 5 macOS nb evidence and Oct 10 iOS empty-state nb evidence supersede that note, but do not cover all populated editor/readback states. |
| Oct 10 iOS PIM polish | [Slice 8b report](ios-slice8b-pim-2026-10-10/README.md) covers empty states in light/dark/nb/AX3, not populated calendars/contacts or their editors. It records unresolved audit flags requiring manual interpretation, not a clean accessibility pass. |
| Oct 10 Add DAV navigation | Later WORKLOG entry records the compact-width pushed connect form fix and simulator verification. Do not re-file the older slice-8b dismissal as an unfixed bug without reproducing on current code. |
| Recurrence 2.6 | Original “edit-one vs edit-series” wording is not the shipped contract: `CalendarRecurringEditScope` exposes All Events and This and Future Events. README defers single-occurrence edits. Validate those supported scopes; request a decision before expanding scope. |

## Fresh automated evidence

All six commands exited **0**. Swift 6.3.3 (driver 1.148.6), Xcode 26.6
(`17F113`), mise 2026.10.10, SwiftFormat 0.58.7, SwiftLint 0.63.0.
All checks use synthetic fixtures or static repository checks; no
live-provider credentials were bound.

| Check | Result | Evidence scope |
| --- | --- | --- |
| `swift test --package-path packages/BrevCalendar` | PASS: 264 tests / 26 suites | PIM source/collection lifecycle, DAV and Google adapter doubles, sync/write/conflict/serialization contracts; not remote services |
| `swift test --package-path packages/BrevMail --filter 'PIMSyncSchedulerTests\|CalendarInviteResponsePresentationTests\|PIMDetailEditabilityHintTests'` | PASS: 22 tests / 3 suites | Scheduler opt-in/ticks and presentation; not wall-clock app pickup or pixels |
| `swift test --package-path packages/BrevSettings --filter 'PIMSourceSettingsModelTests\|PIMSourceRowPresentationTests\|PIMDAVConnectFormTests'` | PASS: 41 tests / 3 suites | Source model/row/form logic; not OAuth UI or Keychain/device proof |
| `MISE_EXEC_AUTO_INSTALL=0 scripts/lint.sh` | PASS | Repository formatting/lint/enforcement entry point and SwiftLint coverage self-test |
| `MISE_EXEC_AUTO_INSTALL=0 scripts/format.sh` | PASS: 0/1,285 formatted; 174 skipped | No unrelated tracked files changed |
| `scripts/privacy-audit.sh` | PASS | Static privacy audit; not a live network trace |

Total: **327 tests** in the named runs. Execution logs are retained outside
the checkout under `/Users/devin/pim-parity-evidence/01-brevcalendar-tests.log`
through `06-privacy-audit.log` in the originating session; these paths are
not portable repository evidence. The command results above are the durable
summary. Local setup installed missing mise via Homebrew and used the existing
blueprint's direct SwiftFormat release-asset fallback after GitHub API rate
limiting. `MISE_EXEC_AUTO_INSTALL=0` prevented unrelated Tuist/Periphery
installs; it did not skip lint/format or change their pinned tools.

TDD exception: documentation-only reconciliation; no behavior changed and no
new defect claimed. Existing tests are run as regression evidence because PIM
fixes and iOS UI changes landed after the matrix's cited automated baseline.
No snapshot baselines are re-recorded. No app build, UI test, simulator run,
provider login, or provider mutation is claimed in this pass.

## Remaining acceptance, by evidence layer

| Layer | What remains before acceptance |
| --- | --- |
| Implementation | No new reproducible defect established by this reconciliation. Do not rebuild #3 or reimplement O7–O12. New failures require a focused Swift Testing red/green fix within accepted scope. |
| Automated | Results above refresh only the listed contracts, not all packages or release builds. |
| Stub runtime | macOS 4.3 remains an exact timed-idle test; macOS 1.8 timeout and 2.5 stale-href post-fix runtime legs remain unrecorded in the matrix. macOS RSVP 2.8 remains blank. iOS 2.2/2.3/2.6, 3.2/3.3, 4.4–4.6 remain missing or partial. Do not repeat Oct 3 iOS 2.7/2.8/4.3 merely to refresh a date. |
| Real Google | Both platforms: lifecycle 1.1–1.5/1.9 completeness; event/contact CRUD, recurrence, group assignment, attendee delivery/RSVP, sync recovery, mixed Google+DAV isolation, cache removal and cleanup. Earlier consent/re-auth/403 evidence is partial, not full parity. |
| Real DAV | Both platforms: dedicated generic CalDAV/CardDAV fixture lifecycle, TLS/error cases, CRUD, conflict preservation, recurrence, scheduled pickup and cache/removal preservation. Stub success cannot satisfy this gate. |
| macOS runtime | No fresh run here. Prior partial VoiceOver/keyboard results do not cover every editor, failure state or current scaling/reduced-motion behavior. |
| iOS runtime | No fresh simulator or physical-device run here. Populated current PIM screens need light/dark, en/nb, AX text-size/readback and reduced-motion coverage; Oct 10 empty-state results do not replace this. |
| Maintainer acceptance | Still absent; only Henrik can accept the final provider/platform table and matrix sign-off. #3 and #11 remain open. |

## Exact next runtime passes — prepared, not executed

Before any UI run, obtain explicit approval and read the complete
`.agents/skills/testing-brev-ui/SKILL.md`. Use `Brev Test (YYYY-MM-DD).app`,
an owned build-output directory and an isolated profile/simulator. Never
replace or kill `/Applications/Brev.app`, use `--release-main`, shut down
another session's simulator, or attach to its app/stub process. Validate
build-script stop/launch behavior before using it on a shared host. Redact
recordings and logs before attaching; keep auth values out of commands/logs.

| Priority / rows | Required starting state and actions | Passing evidence |
| --- | --- | --- |
| 1 — macOS 4.3 | Own local stub on an unused port, own synthetic source and profile; Background sync initially OFF. Connect explicitly, enable Background sync, select 5-minute fetch (not Manual), wait for initial sync to finish. Inject one uniquely named owned event remotely. Leave app idle in foreground, no Sync Now/reconnect/relaunch, for two fetch intervals plus 30 seconds. | Timestamped injection and unprompted REPORT within the observation window; cached count changes without reopening Settings; opening calendar shows event without causing the first fetch. Disable background sync, inject a second owned event, observe one interval with no scheduled pickup, then manually sync for cleanup. Label as foreground-idle only. |
| 2 — bounded macOS regressions | Own stub/profile: retry missing 1.8 timeout using an owned silent listener (not an HTTP stub that fails TLS instantly); for 2.5 open editor, change remote version/href, Save before sync then sync/retry. Exercise macOS RSVP 2.8 on own synthetic invite. | Submission exits at configured request-timeout bound with actionable copy; stale write reports conflict and preserves remote; retry uses current href/etag. RSVP has conditional versions and correct PARTSTAT. No claim of invite delivery. |
| 3 — remaining iOS stub cells | Own signed simulator/profile and disposable stub data. Search across own sources; offline cached event/contact restore; supported recurring scopes; interrupt only the owned source, expire its cursor and clear/rebuild its cache. | 2.2/2.3/2.6, 3.2/3.3 and 4.4–4.6 each have before/action/after evidence, unchanged healthy source, and no lost accepted cached generation. |
| 4 — live G/C/D | First verify fixtures contain **only** dedicated synthetic QA data and consent/signing gates below are satisfied; otherwise stop before syncing. Create one unique event/contact per owned collection using prefix `brev-pim-20261015-<run-id>`. Browse/search, edit, sync/relaunch/offline restore, apply supported recurrence and group operations. Use a second dedicated synthetic recipient for attendee/RSVP; create remote conflicts only on those records. | Platform × provider row results; provider-side verification of exact owned IDs and versions, separate invitation delivery/RSVP outcome, conflict preservation, reconnect/refresh/denial and source removal. Never infer delivery from a 2xx write. |
| 5 — cross-source and cleanup | With only approved disposable G/C/D fixtures, mutate one owned record while another owned source is unavailable. Exercise cursor recovery/full resync and local keep/delete-cache removal paths. | Only intended source changes, healthy cache survives, removal performs no provider deletion. Then explicitly delete only run-owned synthetic records remotely and verify those IDs absent; source removal alone is not cleanup. |
| 6 — platform/readback | On populated Calendar/Contacts and editors: en + nb, light + dark, default + accessibility text size, VoiceOver traversal/labels, reduced motion, macOS keyboard focus/actions, physical iPhone foreground/relaunch and separately documented suspension behavior. | Redacted rendered evidence and spoken/readback results; retained audit flags adjudicated, no clipped critical controls. Physical-device/OS execution distinguished from simulator. No promise of polling while suspended. |

## Credential and acceptance gates

Discovery checked **references only**; no values were read or used.

| Category | Gate / owner |
| --- | --- |
| Decision | Parent/Henrik: explicitly approve the bounded UI pass and fixture use. Accept the shipped series/future recurrence boundary or commission a separate scope decision; do not silently mark single-occurrence editing passed. |
| Credential | Existing `secret:repo:henrikogaard/brev:BREV_QA_GOOGLE_EMAIL`, `BREV_QA_GOOGLE_PASSWORD`, `BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID`, `BREV_GOOGLE_OAUTH_CLIENT_SECRET`, `BREV_GOOGLE_OAUTH_IOS_CLIENT_ID` are available by reference. Their presence is not proof login/consent works. No credentials were requested directly from Henrik. |
| Credential | No dedicated CalDAV/CardDAV endpoint/credential references were listed. The `BREV_LIVE_MAIL_*`/IMAP/SMTP references describe a disposable mail account, not authorization or capability for DAV. Parent must identify approved dedicated DAV endpoints, credential references, synthetic collection IDs and a synthetic invite recipient; never substitute personal calendars/contacts. |
| macOS-host | This host is macOS, so macOS availability itself is not a blocker. UI approval, isolated build/profile/ports and a working toolchain remain prerequisites for runtime evidence. Team-signed iOS build/Keychain identity must be available; unsigned historical -34018 is not a product failure. |
| Henrik-only | Google previously demanded recovery-phone/device verification. Status was not re-probed here; Henrik must complete any challenge normally. No bypass. Physical iPhone access and final maintainer sign-off remain separate. |

## Delivery / documentation sweep

- GitHub project query returned `Resource not accessible by personal access
  token`. No board change claimed. Intended state: In progress while gathering
  evidence; In review only for the evidence handoff, never Done/accepted.
- Only new QA evidence and WORKLOG need changes. README/product behavior,
  CHANGELOG, PRIVACY/ADR-0006, architecture decisions, release docs and AGENTS
  are unchanged: no setup, shipping behavior, network/privacy, policy, or
  distribution changes. Historical matrix/report content remains untouched.
- Build and Lint workflows run on every `pull_request`, with macOS jobs and
  no draft/docs-only guard; pushes run only for `main`. This feature-branch
  push is safe from those triggers, but opening a draft PR is not. Hold PR
  creation for parent cost direction rather than editing gates or using skip
  markers. No CI dispatch/rerun, merge, issue closure, version or release.
- Suggested draft title: `docs(qa): reconcile Calendar and Contacts parity evidence`.
  Target `main`; reference #11 and #3, **not** closing keywords. Description:
  new versioned evidence, inherited-vs-fresh results, remaining provider/device
  gates and commands above; documentation-only TDD exception. Parent review at
  the first pushed milestone precedes any further work.
