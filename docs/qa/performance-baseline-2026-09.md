# Performance baseline — 2026-09 hot-path pass

Deterministic micro-baselines for the paths tuned in the 2026-09 performance
review (issue #28 §5, PR #30). They complement, not replace, the live-app
budgets in `performance-budgets.md`.

## What is measured, and how

Two Swift Testing suites build synthetic fixtures, time the **public** API
with `ContinuousClock`, print one `PERF …` line each, and assert only ordinal
relationships so they never flake on host speed:

- `packages/BrevBackend/Tests/BrevBackendTests/PerformanceBaselineTests.swift`
  (`swift test --package-path packages/BrevBackend --filter PerformanceBaseline`)
- `packages/BrevSyncEngine/Tests/BrevSyncEngineTests/SearchPerformanceBaselineTests.swift`
  (`swift test --package-path packages/BrevSyncEngine --filter SearchPerformanceBaseline`)

Fixtures contain no real mail: generated subjects, `example.org` addresses,
reply chains every third message. Nothing about a user's mailbox is recorded.

## Recorded values

Host: Apple M5 Max, macOS 27.0, debug build (`swift test`), 2026-09-16.
Debug-build numbers are pessimistic; relative ratios are the point.

| Path | Fixture | Before-shape | After-shape | Ratio |
| --- | --- | ---: | ---: | ---: |
| Cache-hit folder listing (thread resolution) | 10k headers | cold 37.6 ms → 35.0 ms | memo hit 12.2 ms → 9.3 ms | 3.8× |
| Header-cache disk writes | 10k headers × 50 flag updates | write-through 2,726 ms → 3,739 ms | coalesced 81 ms → 114 ms | 33× |
| All-folders local search | 20 folders × 500 rows, 1,000 matches | 20 queries 33.9 ms | 1 scoped query 17.2 ms | 2.0× |
| Server paging merge | 200-row pages into a growing cache | first 3 pages 0.63 ms → 0.50 ms avg | pages 18–20 3.55 ms → 2.15 ms avg | record-only |

"Before-shape" is the same code path exercised in the shape the code used
before the pass (per-mutation flush, per-folder query, no memo), so the
comparison is like-for-like on the same host and build. The left number in
each `→` pair is the previous recorded value on this host; the right number
is the incremental-thread-resolution re-run on 2026-09-16.

## Findings the harness surfaced

- **Incremental thread resolution cut per-page merge cost ~40%.** Replacing
  the fingerprint memo + whole-folder union-find with
  `IncrementalThreadResolver` (diff on thread keys, extend the forest with
  only new edges) took pages 18–20 of a 10k folder from 3.55 ms to 2.15 ms
  average, and the warm cache-hit listing from 12.2 ms to 9.3 ms. The warm
  listing no longer hashes all 10k headers or rebuilds the thread-ID
  dictionary — it diffs keys and looks up only the page's ids.
- **Paging still grows, just slower.** The per-page update still diffs the
  known set O(N) to catch removals/rekeys, so late pages cost ~4× the first
  pages (was ~6×). A removal/change-triggered rebuild is rare; if large-folder
  paging still shows in live traces, the remaining cost is the O(N) diff
  itself, not resolution.

## Not measured here — still owed under #28 §5

These need the live app and Instruments/`performance-diagnostics.md` signposts,
on the maintainer's daily-driver mailbox, and are **not** covered by this file:

- cold/warm folder selection to first interactive list
- list scroll frame time (p95)
- search latency end-to-end including provider pages
- CPU and resident memory over a 60-second idle with IDLE connections up
- sidebar resize responsiveness

The new signposts (`IMAP Header Cache Flush`, thread-resolution hit/miss,
session queue wait, presentation build) exist so that pass can attribute time
without further code changes.
