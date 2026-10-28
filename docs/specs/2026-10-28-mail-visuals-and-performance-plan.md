# Mail visuals and performance

Size: Full, spanning persistence, backend queries and shared UI.
Status: Building, slice 2 of 8; slice 1 runtime gate remains open
Owner: Henrik · Started: 2026-10-28 · Approved: 2026-10-28, Henrik
Tracking: [#269](https://github.com/henrikogaard/brev/issues/269).
Baseline: `origin/main` at `5ad74c0b388466a5f842dcb43b8834f74cc413ee`.
Working assumptions: synthetic benchmarks can run in CI; runtime profiling and visual acceptance wait for an authorized, compatible environment. No performance improvement has been measured for this plan.

## 1. Requirements

### Sources

| ID | Source | Contribution |
|---|---|---|
| S1 | Henrik, 2026-10-28: "do 1-3", following the visuals/performance review | Implement the storage, UI-responsiveness and visual-consistency recommendations. |
| S2 | [ADR-0087](../../ADRs/0087-imap-header-pages-from-sqlite.md) | Accepted SQLite ownership, migration, selective-query design and staged measurement gates. |
| S3 | [Performance budgets](../qa/performance-budgets.md) and [live scenarios](../qa/performance-live-run.md) | Fixture sizes, existing timing/memory targets and measurement conditions. |
| S4 | [Body parity design](2026-07-25-message-body-read-compose-parity-design.md), [ADR-0002](../../ADRs/0002-theme-system.md), [ADR-0028](../../ADRs/0028-mail-provider-architecture.md) | Shared typography/insets, theme/focus contracts and rendering boundaries. |
| S5 | Henrik's latest directions: leave icons alone; defer host native testing | No icon work, no host app/snapshot tests without a new permission. |
| S6 | [AGENTS.md](../../AGENTS.md), [ADR-0006](../../ADRs/0006-telemetry-and-privacy.md) | Workflow, test-app isolation, privacy, no new reachable network behavior. |
| S7 | Current implementation and existing PR #265 | Preserve current optimizations and continue the existing Settings outcome rather than duplicate it. |

### Requirements map

| ID | Requirement | Priority | Acceptance criterion | Sources |
|---|---|---|---|---|
| FR-1 | Read indexed IMAP headers, individual lookups and paging metadata from the account database. | Must | After migration, cache-first folder paging returns the same source-owned rows/windows and tokens without a whole-folder JSON read. | S1, S2 |
| FR-2 | Persist page members, flags, removals and UIDVALIDITY/MODSEQ state consistently. | Must | Atomic page/window writes and row-level mutations pass parity, invalidation, restart and interruption tests; a flag update does not rewrite a folder snapshot. | S2 |
| FR-3 | Migrate legacy folder caches safely and retire the duplicate file-backed path. | Must | A valid legacy fixture imports missing rows and metadata transactionally; cleanup only follows committed validation; failed/interrupted migration remains recoverable. Storage metrics/clear operations use the authoritative store. | S2, S6 |
| FR-4 | Reduce a demonstrated source of unnecessary selection/render work. | Must | Matched optimized traces show reduced work at the chosen boundary, without regressing existing timing/memory gates or source/selection behavior. File splitting alone is not completion. | S1, S3, S7 |
| FR-5 | Improve wide-reader comfort and shared alignment. | Must | Plain/Brev-generated text uses a readable measure and consistent Detail/Thread insets at narrow/normal/wide sizes. Arbitrary sender HTML, print and compose retain their existing contracts. | S1, S4 |
| FR-6 | Make default-theme interaction states distinguishable. | Must | Targeted light/dark, active/inactive window, keyboard focus, unread and disabled-state checks pass, including accessibility sizes. Existing theme contrast contracts remain green. | S1, S4 |
| FR-7 | Finish the existing native Settings outcome. | Must | PR #265 is brought current, passes focused verification and receives the previously deferred native-rendering check before it can be considered ready. | S1, S5, S7 |
| NFR-1 | Bound local work as mailbox size grows. | Must | ADR-0087's cold first-50-row query at 50k headers is at most 200 ms; 10k-folder flag persistence at most 5 ms; zero full-folder decodes on the migrated cold-open path; idle memory no higher than its matched baseline. | S2 |
| NFR-2 | Preserve the existing interaction budgets. | Must for hard limits; Should for targets | On the documented fixture/build/host: usable inbox target/hard limit 800/1500 ms; query 200/400 ms; cached thread 300/600 ms; scroll p95 16/32 ms; idle RSS 600/900 MB. Record target misses; never relabel a policy self-test as a live benchmark. | S3 |
| NFR-3 | Preserve data/privacy and observable behavior. | Must | No new external calls or automatic prefetch; blocker/JS/privacy checks pass; migration cannot erase data on failure; stale async results cannot replace the selected message. | S4, S6 |
| CON-1 | Preserve provider-neutral UI, plain models and existing packages. | Must | No provider type checks/SQL types in views; no new framework, package or public design-system contract without its ADR process. | S4, S6 |
| CON-2 | Do not disturb the daily-driver app or host desktop. | Must | Only isolated test identities and synthetic stores; no host app/snapshot tests, real cache migrations or personal mailbox profiling without specific permission. | S5, S6 |
| CON-3 | Preserve delivery gates. | Must | Focused PRs follow branch, tests/checks, commit, push and review workflow; no merge, release, deployment, app-version change or issue closure is implied by this plan. | S6 |
| ASM-1 | CI remains available for synthetic package validation. | Assumption | Verify in slice 1; unavailable CI is a blocker, not permission to skip verification. | S3, S6 |
| ASM-2 | A compatible isolated runtime environment will become available. | Assumption | Q-1 resolves before runtime measurement or visual acceptance; no local runtime results are assumed. | S5 |

### Traceability and dependencies

- S1 priorities 1/2/3 map to FR-1–3/NFR-1, FR-4/NFR-2 and FR-5–7 respectively.
- S2's four-stage rollout is retained in slices 1–4; its downgrade risk is addressed by proposed D-2, not an automatic wipe.
- S3 maps to NFR-1/2 and the measurement owner; S4 maps to FR-5/6 and CON-1; S5 maps to CON-2 and the icon exclusion.
- S6 governs every slice; S7 maps to FR-4/7 and the rule against replacing working caches/prewarming or duplicating #265.
- FR-2/3 depend on FR-1's store contracts. FR-4 depends on fresh profiling, not the September/October measurements. FR-7's native acceptance is blocked by Q-1.

## 2. Scope

- In: FR-1–7, NFR-1–3 and CON-1–3, through independently reviewable slices.
- Out: icon changes, per Henrik on 2026-10-28. Broad feature additions, decorative effects and a UI/framework rewrite were not part of the selected review recommendations.
- Later: host/runtime verification until Q-1 is resolved; exact UI observation-boundary changes until a trace supplies evidence. Existing provider QA issues and sign-in activation remain separate work, not acceptance criteria for this batch.

## 3. Conceptual design

### Purpose and trust boundaries

Make existing mail easier to read and faster to navigate, keeping local data safe. The user operates the existing workspace; providers continue to use the existing authenticated adapters. Local measurements consume synthetic fixtures and produce content-free summaries.

```text
User -> Workspace/Reader -> provider-neutral backend -> Account header store
                                 |                        |
                       existing provider calls     legacy-cache migration

Synthetic fixtures -> Measurement runner -> local timing/memory summaries
```

Provider/mail HTML is untrusted: preserve remote-content blocking and stale-result guards. Legacy files may be malformed or stale: validate identity/UIDVALIDITY and commit before cleanup. Trace artifacts may disclose mail: synthetic fixtures and identifier/content-free summaries are mandatory.

### Capabilities and components

| Component | Responsibility | Requirements |
|---|---|---|
| Account header store | Authoritative persisted rows, page windows, local queries and migration state | FR-1–3, NFR-1/3 |
| Backend adapter | Source identity, provider paging and consistent mutations/events through current seams | FR-1–3, CON-1 |
| Measurement runner | Reproducible synthetic baselines, matched traces and budget evaluation | FR-4, NFR-1/2, CON-2 |
| Workspace/Reader | Narrow observation boundaries, shared reading layout and interaction states | FR-4–6, NFR-2/3 |
| Existing Settings outcome | Complete #265 through its current branch/PR | FR-7, CON-3 |

Domain concepts: an account owns its database; a folder belongs to one account; a page window records membership for a server cursor; UIDVALIDITY identifies a folder generation; a presentation snapshot derives visible rows; a measurement run identifies commit, build, fixture, environment and scenario without message content.

## 4. Logical design

### Contracts and data ownership

| Owner | Contract and guarantees | Readers/dependencies |
|---|---|---|
| Account header store | Async bounded pages/lookups and selective retention/attachment/thread queries; transactional rows plus window metadata; unknown future schema fails closed. | Backend and existing local-index bridge. Views never read SQL. |
| Backend adapter | Preserve `MailBackend` behavior, account/folder ownership, UID cursor meaning and change-event semantics. Missing SQLite uses the accepted memory-only fallback. | Workspace and other existing consumers. |
| Migration path within the store boundary | On first eligible folder open, import only validated legacy data; make crash/retry idempotent; never clear authoritative rows to resolve a conflict. | Existing legacy-file reader, until retirement. |
| Measurement runner | Isolated fixture creation, repeatable scenarios, local signposts and summarized durations/memory. Missing or incomparable results remain missing. | CI for behavior checks; authorized runtime host for timing/visual acceptance. |
| Workspace/Reader | Selection does not require rebuilding unrelated projections; moved logic preserves identity, cancellation and update semantics. Layout uses theme/style inputs. | Existing presentation caches, BodyRenderer and native/WebView controls. |

The store owns headers, page membership and sync metadata. The backend owns provider-session state. The workspace owns transient selection and derived presentations. The shared body style owns typography inputs. The measurement runner owns fixture/run metadata. No second persisted header cache or new durable UI state is introduced.

Integration remains request/response plus existing backend events. Dual-writing metadata is a temporary rollout state under ADR-0087, not permanent authority shared between two stores. SQLite becomes authoritative only after the tested read cutover.

These contracts follow D-1's existing designs, D-2's preservation rule, D-3's evidence gate, D-4's limited reading measure and D-5's ownership of the existing Settings outcome.

### Scenario walkthroughs

1. **Cold folder open:** backend requests a bounded page; the store validates/migrates that folder if needed, commits rows plus windows, returns headers/token, and the workspace derives its existing presentation. Cleanup cannot precede a successful import. FR-1/3, NFR-1/3.
2. **Refresh or flag mutation:** backend commits the relevant rows/window and generation metadata atomically; a first-window replacement preserves older visited windows; removed members produce existing removal events. No JSON snapshot rewrite occurs after cutover. FR-2, NFR-1/3.
3. **Interrupted/invalid migration:** the transaction rolls back or reopens consistently; malformed data and wrong-generation metadata are not made authoritative; the source remains available for recovery. Future schemas are never wiped automatically. FR-3, NFR-3.
4. **Rapid selection during sync:** baseline and changed optimized builds replay the same synthetic workload; the trace identifies the observation/computation to move. Existing source identities, thread child/parent intent and async generation guards are characterized before changing that boundary. FR-4, NFR-2/3.
5. **Wide reader and Settings:** plain/generated text gains the proposed readable measure without altering arbitrary sender HTML. Narrow and accessibility layouts keep full usable width. Native active/inactive/focus checks and #265 verification run only after Q-1 is resolved. FR-5–7, CON-2.

### Performance and safety mechanisms

| Requirement | Mechanism | Sufficiency argument |
|---|---|---|
| NFR-1 | Indexed bounded queries, row updates and selective thread/attachment inputs | Initial display reads 50 rows rather than decoding 10k–100k rows. Verify query plans and touched-row/file counts as well as time. Lazy legacy migration is measured separately, not hidden inside a claimed steady-state result. |
| NFR-2 | Same optimized build, fixture and scenario before/after | Use 10k default, 50k storage comparison and 100k spot check. Report repeat count, median/p95 and memory. CI policy self-tests prove thresholds only; actual durations require runtime evidence. |
| NFR-3 | Transaction boundaries, generation checks and existing privacy controls | Failure before commit leaves legacy data intact; results from old selections/generations cannot apply; no additional provider/HTML requests are introduced. |
| CON-2 | Disposable caches/test identity and runtime permission gate | No real accounts, daily-driver bundle or host windows are needed for synthetic package checks. Runtime work stays blocked rather than silently moving to the host. |

### Risks

| Risk | Mitigation/gate |
|---|---|
| Lost page membership, thread links or UIDVALIDITY correctness | Transaction and parity characterization tests before read cutover. |
| Database contention erases query gains | Measure foreground reads during writes first; introduce a separate read connection only if evidence requires it. |
| Generic HTML is damaged by a width constraint | Constrain plain/Brev-owned containers only; preserve sender HTML layout and remote-content rules. |
| A UI refactor changes behavior but not latency | Trace selects the boundary; matched measurements and existing behavioral tests are required. |
| No compatible profiling/rendering environment | Q-1 blocks runtime gates; keep affected work unverified and do not claim completion. |

## 5. Decisions

### D-1: Reuse the accepted designs (Accepted constraints, 2026-10-28)

ADR-0087 governs persistence; the existing body-parity design and ADR-0002 govern shared appearance/focus. This plan coordinates their remaining work rather than introducing a competing architecture or new design system. Protected-path changes still follow the repository ADR gate.

### D-2: Preserve future/failed schema data (Accepted, 2026-10-28)

Keep the current unknown-schema fail-closed behavior and accepted memory-only fallback. Do not automatically wipe/recreate a newer or unsuccessfully migrated database. This trades temporary offline unavailability on manual downgrade for preservation of local data. It settles the optional wipe suggestion in ADR-0087's risk section without introducing a destructive recovery path.

### D-3: Measure before choosing a UI refactor (Accepted, 2026-10-28)

Reuse current projection caches and renderer prewarming. Select one observed expensive boundary, characterize it, change it, then compare. Moving files or adding caches without trace evidence is not a delivered optimization.

### D-4: Start with a conservative reading measure (Accepted, 2026-10-28)

Evaluate approximately 72 characters for plain/Brev-generated text on wide Mac readers, through the existing style/layout ownership. Narrow layouts use available width; arbitrary sender HTML, print and compose remain unchanged. No new preference or public design-system API is proposed. Native review may adjust the exact measure before implementation is accepted.

### D-5: Continue #265 in place (Accepted workflow constraint)

Do not create a sibling Settings rewrite. Its existing native forms and ADR amendment are the starting point, but green CI does not replace the deferred rendered check or authorize host testing.

## 6. Coverage

| Requirements | Design owner | Slices | Current evidence |
|---|---|---|---|
| FR-1/2, NFR-1 | Store/backend | 1–4 | Accepted ADR; implementation and measurements pending. |
| FR-3, NFR-3 | Store/backend migration | 2–4 | Existing transactional schema code inspected; new migration pending. |
| FR-4, NFR-2 | Measurement/workspace | 1, 5–6 | Existing signposts/caches inspected; fresh trace pending. |
| FR-5, FR-6 | Workspace/Reader | 7 | Shared style and targeted snapshots exist; new native/layout acceptance pending. |
| FR-7 | Existing Settings outcome | 8 | #265 exists; native acceptance remains blocked. |
| CON-1, CON-2, CON-3 | Every component | All | No new packages, app execution or behavior changes in this planning PR. |

## 7. Build plan

Each numbered slice is a coherent PR. Independent outcomes target `main`; only genuinely dependent storage slices may form a documented linear stack. Before implementation, create/link scoped tracking issues and move their cards to In progress. Keep closed issues closed.

| Slice | Deliverable and verification target | Requirements | State |
|---|---|---|---|
| 1 | Add cold JSON-versus-SQLite synthetic benchmarks at 10k/50k, preserve the existing 10k tests, and collect an authorized cold-folder/selection baseline. No production behavior change. | NFR-1/2, FR-4 | Building synthetic suite; runtime part waits on Q-1. |
| 2 | Detail schema/page-window contracts, add migration/transaction/restart tests first, then implement the ADR-0087 metadata/window write slice. Use actual schema version at implementation time, not a stale constant. | FR-1–3, NFR-3 | Store foundation implemented; CI pending. Backend dual-writes still pending. |
| 3 | Migrate per folder and switch bounded read/lookup/thread paths, proving old/new parity, token/generation behavior and measured query targets before cutover. | FR-1–3, NFR-1 | Planned; measurement gate required. |
| 4 | Replace remaining full-folder consumers and storage-UI reads, verify retention/removal/flag paths, then retire the duplicate file-backed cache and validate cleanup/recovery. | FR-2/3, NFR-1/3 | Planned. |
| 5 | Repeat the optimized selection/scroll trace after the storage slices and identify one expensive UI boundary. | FR-4, NFR-2 | Planned; no guessed refactor. |
| 6 | Add characterization coverage, make the smallest demonstrated UI update-scope change and verify matched timings, memory and navigation behavior. | FR-4, NFR-2/3 | Planned. |
| 7 | Implement/verify plain-text readable measure, shared alignment and missing default-theme interaction-state cases. Preserve sender HTML and existing style/privacy contracts. | FR-5/6, CON-1 | Planned; rendered acceptance required. |
| 8 | Continue #265, integrate current main and perform its focused native verification; deliver it for review without assuming merge permission. | FR-7, CON-2/3 | Blocked on Q-1 for native verification. |

Write each slice's detailed design immediately before its code, including literal contract examples, failure modes, test scope and current commit. Do not pre-design a new UI state architecture before slice 5 supplies evidence. TDD applies to meaningful behavior; docs-only and measurement-only changes state their exceptions explicitly.

Documentation is updated with each slice: README for actual current behavior, CHANGELOG for user-facing changes, ADR-0087 implementation status, privacy docs only if local lifecycle documentation needs correction, and WORKLOG for evidence/limits. No versioned live-QA report is created without new live evidence.

## 8. Open questions

| ID | Question | Blocks | Recommendation |
|---|---|---|---|
| Q-1 | Which compatible isolated runtime environment is available, or when will Henrik authorize focused host native testing/profiling? | Runtime part of slice 1, measured cutover, slices 5–8 acceptance. | Keep host tests deferred. Implement synthetic validation through CI where available; do not claim the blocked gates pass. |

Q-2 resolved: Henrik approved the design on 2026-10-28 and requested implementation. This does not resolve Q-1 or authorize host testing, real-account migration or merges.

## 9. Detailed design

### Slice 1: synthetic header-read comparison

**Placement.** Add `IMAPHeaderReadBaselineTests.swift` to `packages/BrevSyncEngine/Tests/BrevSyncEngineTests/`. This package already depends on BrevBackend, so one suite can seed both stores with identical headers without introducing the forbidden reverse dependency from BrevBackend to BrevSyncEngine. Preserve the existing `PerformanceBaselineTests` and `SearchPerformanceBaselineTests` unchanged.

**Interfaces.** Use existing `FileBackedIMAPMailboxHeaderCache(rootDirectory:)`, `setSnapshot`, `flushPendingWrites`, `snapshot`, and test-visible `SQLiteSyncStore(databaseURL:)`, `ensureAccount`, `upsertHeaders`, `headers(accountID:folderID:limit:offset:)`. No production API, schema, package dependency or runtime option changes.

**Fixture and literal example.** For `rows = 10_000` and `rows = 50_000`, generate deterministic synthetic `INBOX:<uid>` headers in newest-first order with whole-second dates, fixed synthetic addresses and predictable read/flag state. Store the same values in a legacy snapshot and the database. A first-page request is `headers(accountID: "imap-baseline", folderID: "INBOX", limit: 50, offset: 0)`; expected IDs are `INBOX:10000` through `INBOX:9951` for the 10k fixture. JSON metadata uses fixed UIDVALIDITY, MODSEQ and a `before:<uid>` cursor. SQLite page metadata is not compared because implementing it belongs to slice 2.

**Measurement sequence.** Seed/flush the legacy cache and populate/close the database before timing. Run four samples, alternating JSON-first and SQLite-first, with a new cache actor and a new database connection for every sample. Time JSON cache creation plus its full snapshot read; separately time SQLite open and first 50-row query, also reporting their total. Assertions and second-page checks happen outside the measured interval. Record sample values and medians, fixture JSON byte count, rows returned, sample order and Debug/Release compilation mode in content-free `PERF` lines.

**Meaning of cold.** `cold=store-reopen` means a fresh application-level cache/connection, not a purged OS page cache, a process-cold launch or a live folder-open measurement. Fixture generation/seeding is excluded. These timings cannot establish the runtime cutover budget or justify a Release performance claim when CI uses Debug.

**Assertions and failure handling.** Require a persisted JSON snapshot containing every seeded header; verify its metadata; require exactly the expected first 50 headers from both paths, full-value parity, and correct/disjoint SQLite second-page IDs. Disk/open/seed errors or missing snapshots fail the test instead of yielding empty benchmark results. Assert no relative or absolute speed relationship on shared CI runners. Each test owns a unique temporary root and cleans up only that synthetic root, including SQLite sidecars. No provider, credential, network client or real account store is constructed.

**Verification mapping.**

| Criterion | Test/check | Evidence limit |
|---|---|---|
| Same synthetic data yields the expected bounded page after reopen | `IMAPHeaderReadBaselineTests.coldHeaderReads`, arguments 10k and 50k | Covers current store read parity only, not new migration/page-window behavior. |
| Reopen measurements exclude seed work and distinguish open/query cost | Four alternating `PERF` samples plus summary per fixture | Informational; no flaky timing inequality. |
| Paging metadata/offset and fixture count are validated | Metadata assertions, first-page value equality and untimed second-page check in the same test | SQLite metadata ownership is deferred to slice 2. |
| Existing baselines remain available | Existing backend/search baseline files unchanged; existing CI package jobs | New runtime traces are still required by Q-1. |

**Budget and rollout.** Test instrumentation only. Read 50 SQL rows per measured query versus a complete 10k/50k legacy snapshot. Report both SQLite open and query cost so neither is hidden. No production rollout, data migration or performance-budget threshold changes occur. TDD red/green is not applicable to this record-only measurement addition; correctness assertions validate existing behavior. CI will supply automated verification while local long-running work/native tests remain constrained.

### Slice 2a: transactional store foundation

Prepare schema v7 and the internal SQLite transaction seam before wiring backend dual-writes. This is the first reviewable part of slice 2, not the read cutover or a completed migration. The PR must not ship ahead of the outstanding live baseline. Existing UI/backend read paths remain untouched.

- `storeIMAPPage(_:accountID:folderID:pageKey:uidValidity:highestModSeq:nextPageToken:)` writes headers, sync metadata and exactly one page's UID membership under the existing lock and one transaction. Example: page `first`, UIDs 51–100, generation 777, MODSEQ 888 and cursor `before:51`.
- Share the current header upsert/FTS/conversation code by adding a private optional page-write context to its transaction. Ordinary `upsertHeaders` calls keep their semantics. Empty pages still commit metadata/window replacement. Validate the folder/positive UID membership before writing. Generation changes must be explicitly cleared by the caller, not silently reconciled inside a write.
- Schema v7 adds the accepted `next_page_token` and `imap_page_windows` table. Composite foreign keys to folder state and header rows cascade window cleanup on folder/account/message deletion. Existing sync-state writes preserve `next_page_token` because they update named columns only. Unknown future schemas continue to fail closed.
- `imapPageState(accountID:folderID:)` and `imapPageUIDs(accountID:folderID:pageKey:)` are internal throwing readers for metadata and one window only, not whole-folder snapshot APIs. They distinguish SQL errors from a missing folder. Keep these SQLite-specific interfaces internal until the provider-neutral bridge is implemented in slice 2b.
- Tests first cover page replacement preserving other windows, full-width MODSEQ and nil cursor persistence after reopen, empty pages, account/folder isolation, removal cascade, v6 upgrade preserving headers, and rollback injected after header insertion but before window commit. No migration deletes legacy files in this part.
- Package tests execute in CI because host testing remains deferred. Record the absence of a locally observed red run rather than claiming TDD red/green evidence. Do not change production read defaults or claim cutover latency from these tests.

## 10. Verification

| Criterion | Check | Result | Change |
|---|---|---|---|
| Design approved before code | Henrik's approval, 2026-10-28 | Approved | #268 / #269 |
| Synthetic read comparison | `IMAPHeaderReadBaselineTests`, 10k/50k | Passed package CI at `208960eb`, run `40772828311`, BrevSyncEngine job `123114265373`; no runtime/cutover claim | #270 |
| Formatting and lint of new suite | Pinned SwiftFormat lint and SwiftLint strict on the test file | Passed | Slice 1 |
| Transactional page-store foundation | `IMAPPageWindowStoreTests`, upgrade and existing store tests | CI at `d9795bb7` failed test compilation before execution; corrected throwing `#require` input, fresh CI pending | #271 |
| Runtime baseline and UI measurements | Authorized optimized native run | Blocked on Q-1 | Not claimed |

## Codebase deltas and change log

- Current `SQLiteSyncStore` is schema v6; ADR-0087's metadata/windows are not implemented. Code migrates in slices 2–4 after baseline gates.
- Current connector still defaults to the file-backed header cache. Code migrates; it is not removed in this planning PR.
- Current list projections already use retained-buffer cache keys and WebView prewarming exists. The design preserves these; no duplicate optimization layer is proposed.
- The accepted body-parity design remains authoritative. This adds readable-measure/state checks, not a second body renderer or compose redesign.
- 2026-10-28: Drafted after Henrik selected all three recommendations. No behavior, runtime test, baseline or speedup is claimed by this document.
- 2026-10-28: Henrik approved the design. Recorded slice 1's detailed design and tracking issue #269 before implementation. Runtime permission remains unresolved.
- 2026-10-28: Added the synthetic comparison and its run instructions. Existing baseline suites and production paths remain unchanged. Package execution is delegated to existing CI, not run on the host; slice 1 stays open for CI and its separately blocked runtime baseline.
- 2026-10-28: Baseline package CI passed at `208960eb`. Prepared slice 2a's schema-v7 transaction primitives and seven focused tests; no backend wiring/read cutover or legacy-cache deletion. Existing Space remains unavailable, so runtime gates stay open.
