# Performance Budgets

Warm-cache performance budgets for the macOS mail workspace (#304). These are
release-gate targets measured with network off the cached-inbox critical path.

See also: `docs/qa/performance-diagnostics.md` for signpost capture and privacy
rules.

## Measurement Conditions

- Apple Silicon Mac, macOS release or profiling build.
- Warm local database with headers already cached.
- Network disconnected or not required to render the first cached inbox page.
- Default fixture mailbox: **10k headers**; repeat spot checks on **100k**
  headers before major releases.
- Record only summarized durations and memory — never message content.

## Budget Table

| Metric | Target | Hard limit | Unit | Notes |
| --- | ---: | ---: | --- | --- |
| `cached_inbox_usable_ms` | 800 | 1500 | ms | First interactive inbox after selecting a warm folder |
| `cached_inbox_query_ms` | 200 | 400 | ms | Local header query / first page |
| `cached_thread_open_ms` | 300 | 600 | ms | Open a cached thread body |
| `list_scroll_frame_p95_ms` | 16 | 32 | ms | 95th percentile frame time while scrolling a warm list |
| `idle_resident_memory_mb` | 600 | 900 | MB | Resident memory after 60s idle with warm 10k-header mailbox |

Normative constants live in `MailPerformanceBudgetTable` inside `BrevBackend`.

## Running the Gate

### Policy self-test (no live app required)

```sh
scripts/performance-budget-gate.sh --self-test
```

Runs the budget-table unit tests and validates the gate script itself.

### Live measurement pass

1. Capture signposts using `docs/qa/performance-diagnostics.md`.
2. Summarize the warm-cache scenarios into JSON:

```json
{
  "cached_inbox_usable_ms": 720,
  "cached_inbox_query_ms": 180,
  "cached_thread_open_ms": 260,
  "list_scroll_frame_p95_ms": 14,
  "idle_resident_memory_mb": 540
}
```

3. Evaluate the gate:

```sh
BREV_PERF_RESULTS_JSON=/tmp/brev-perf.json scripts/performance-budget-gate.sh
```

The script exits non-zero on missing measurements or hard-limit violations.

## Release Integration

- Optional during beta: `scripts/beta-readiness.sh --perf` runs the policy
  self-test only.
- Before declaring a release blocking: run the live measurement pass on a 10k
  fixture mailbox and archive the redacted JSON under `docs/qa/results/`.

## Fixture Mailbox Sizes

| Size | Purpose |
| --- | --- |
| 10k headers | Default CI/local gate |
| 100k headers | Pre-release regression spot check for large mailboxes |

Synthetic fixtures should be generated from local cache/import tooling rather
than real user mail. Do not commit provider data.

## Measurement harness

For release evaluation, write a JSON object keyed by metric raw values and run:

```bash
BREV_PERF_RESULTS_JSON=/tmp/brev-perf-results.json scripts/performance-budget-gate.sh
```

A sample/template harness lives at `scripts/performance-measure-template.sh`.
