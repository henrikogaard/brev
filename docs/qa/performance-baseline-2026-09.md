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

The operator script for that pass is `docs/qa/performance-live-run.md`
(ten scenarios, ~30 minutes); `scripts/performance-summarize-trace.py` turns
the log export into the budget-gate JSON. Results go under
`docs/qa/results/` and a **Live measurements** section is appended here.

## Live measurements — mock smoke pass 2026-09-25

Conditions: `Brev Test (2026-09-25).app` @ `2435e40`, `BREV_USE_MOCK=1`, mock
fixtures (29-folder inbox / 38 unified). Apple Silicon, foreground Debug
build. **This is a smoke pass, not the #28 §5 gate** — the mock emits no
`mail.*` backend events and the list is small, so `cached_inbox_query_ms` and
true frame p95 are not covered. Results JSON:
`docs/qa/results/performance-mock-2026-09-25.json`.

| Metric | Measured | Budget | Verdict |
| --- | ---: | ---: | --- |
| `cached_inbox_usable_ms` | 324 (max `ui.list` reload, n=8, median 87.5) | 1500 | pass |
| `cached_inbox_query_ms` | — | 400 | not measurable in mock (IMAP-path event) |
| `cached_thread_open_ms` | 1222 (`ui.body.visible`, webView, n=1) | 600 | **over** — first WKWebView render of session; re-measure warm on live run |
| `list_scroll_frame_p95_ms` | ≈1 (proxy: Presentation Build signposts during hard scroll) | 32 | pass-by-proxy; frame timing still owed to Instruments |
| `idle_resident_memory_mb` | 208 (RSS after ~3 min idle, cpu 0.2%) | 900 | pass |
| `ui.startup.ready` (workspace) | 1773–2607 (3 launches) | — | informational; includes mock session seeding |
| `ui.search` (cacheThenServer) | 397, n=1 | — | informational |
| iOS sim (`ui.list` unified reload) | 19 | — | informational |
| iOS sim (`ui.search` unified) | 60 | — | informational |

Findings:

- **First rich-HTML thread open = 1.22 s** (single `Message Open` signpost,
  renderer=webView) — exceeds the 600 ms hard limit. Subsequent opens emit no
  sample because `cancelMessageOpenTiming` drops interrupted intervals; the
  one that lands is the WKWebView first-paint (process spawn + layout).
  Worth a warm-path re-measure and, if it reproduces live, a renderer
  pre-warm.
- **Collector script fixed**: `scripts/collect-performance-trace.sh` now
  passes `--info` — without it `log show` drops the info-level Performance
  events and the export was silently empty.
- Scroll health proxy is clean: `Message List Presentation Build` fired 15
  times at ≤1 ms during aggressive scrolling — no per-frame rebuilds.
- Idle footprint is far inside budget (208 MB RSS, 0.2% CPU).
