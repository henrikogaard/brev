# Performance Live Run (issue #28 §5)

Operator script for the live measurements that the deterministic harness in
`docs/qa/performance-baseline-2026-09.md` cannot produce: cold/warm folder
selection, list scrolling, sidebar resizing, search latency, CPU and memory on
a real multi-mailbox workspace. Budget definitions live in
`docs/qa/performance-budgets.md`; signpost names and privacy rules in
`docs/qa/performance-diagnostics.md`.

Total operator time: about 30 minutes. Nothing here uploads anything; the
unified log export contains timings, counts and path names only.

## 0. Preconditions

- Apple Silicon Mac on mains power, no other heavy apps running.
- A test build (`script/build_and_run.sh --live`) signed into the accounts you
  use daily. Never the release `Brev.app`.
- At least two accounts, one folder with 10k+ cached headers (Inbox or
  All Mail), and the header cache already warm (open the folder once and wait
  for paging to settle before starting the clock).
- Instruments installed (ships with Xcode).

Write down: date, commit (`git rev-parse --short HEAD`), macOS version,
account count and provider kinds (IMAP / Gmail — no addresses), and the header
count of the large folder (Settings › Mail Storage, or the footer stats row).

## 1. Start capture

Terminal 1 — live log, leave running for the whole session:

```sh
log stream --style compact --predicate 'subsystem == "eu.brevmail.brev" && category == "Performance"'
```

Terminal 2 — CPU sampler, leave running (records `%CPU` and RSS in MB once a
second; PID is the test build):

```sh
pid=$(pgrep -f "Brev Test" | head -1)
while sleep 1; do ps -o %cpu=,rss= -p "$pid" | awk '{printf "%s cpu=%s rss_mb=%.0f\n", strftime("%H:%M:%S"), $1, $2/1024}'; done | tee /tmp/brev-cpu.log
```

Instruments — File › New › **Blank**, add **Points of Interest**,
**Core Animation FPS** (or **Animation Hitches** on macOS 14+), **Time
Profiler** and **Allocations**. Target the test build process. Press Record.

## 2. Scenarios

Run each step once, wait for the list/reader to settle, then move on. Note
the wall-clock time at the start of each step so log lines can be attributed.

| Step | Action | What it measures |
| --- | --- | --- |
| S1 cold selection | Quit the app, relaunch, select the large folder | `ui.startup.ready`, `ui.list … path=reload`, `mail.messages.page path=cacheHit` |
| S2 warm selection | Select a different folder, then re-select the large folder; repeat 5× | `cached_inbox_usable_ms`, `cached_inbox_query_ms` |
| S3 scroll | Two-finger scroll from top to bottom of the large folder at a steady pace, then back, ~20 s each way | Core Animation FPS / hitches → `list_scroll_frame_p95_ms` |
| S4 load more | Scroll to the end until three more pages load | `mail.messages.page path=server`, `mail.threads.resolve update=incremental` |
| S5 sidebar resize | Drag the sidebar divider slowly narrower and wider for ~15 s while the large folder is shown | Frame time in Instruments; `Message List Presentation Build` signpost count should stay near zero |
| S6 open messages | Open 10 cached messages: 5 plain text, 5 HTML with images/attachments | `ui.body.visible` → `cached_thread_open_ms`, `Body Render`, `HTML Body Import` |
| S7 search | Search the current folder for a common word; then All Mailboxes; then repeat the same search (cache-warm) | `ui.search`, `mail.search path=…`, `mail.search.cacheRead` |
| S8 unified inbox | Switch to the unified inbox, reload, scroll one screen | `Unified Inbox Reload`, `Unified Inbox Presentation Build` |
| S9 idle | Leave the app in the foreground on the large folder for 60 s without touching it | Last `rss_mb` value in `/tmp/brev-cpu.log` → `idle_resident_memory_mb`; `%cpu` should be ≈0 |
| S10 background | Close the main window, with "Keep checking mail in the background" on, wait for two refresh ticks | `%cpu` between ticks; `mail.headers.cacheFlush` after each tick |

Stop Instruments after S10.

## 3. Read the numbers

Export the log for the session window:

```sh
scripts/collect-performance-trace.sh --last 40m --output /tmp/brev-performance.log
```

From Instruments:

- **Scroll p95**: Core Animation FPS track → select the S3 region → the
  summary shows frame durations; read the 95th percentile (or convert hitch
  duration if using Animation Hitches). Typical values: 8–16 ms on Apple
  Silicon.
- **Sidebar resize**: same track over the S5 region; note the worst frame and
  whether Time Profiler's heaviest stack is in `MessageListView` /
  `BrevMailRootView` body evaluation (layout) or in `BrevBackend` (which would
  mean a derivation is being recomputed on resize and is a bug).
- **CPU**: from `/tmp/brev-cpu.log`, note the peak `%cpu` during S3/S4 and the
  steady value during S9/S10.

Summarize to budget JSON (the script prints per-event count/median/p95/max
under `_detail` for the worklog):

```sh
scripts/performance-summarize-trace.py /tmp/brev-performance.log \
  --scroll-p95-ms <from Instruments> \
  --memory-mb <last rss_mb from S9> \
  --output /tmp/brev-perf-results.json
BREV_PERF_RESULTS_JSON=/tmp/brev-perf-results.json scripts/performance-budget-gate.sh
```

## 4. Record

Copy `/tmp/brev-perf-results.json` to
`docs/qa/results/performance-live-<YYYY-MM-DD>.json` and add a short section
to `docs/qa/performance-baseline-2026-09.md` under **Live measurements** with
the preconditions from step 0, the gate verdict, the S5 finding (layout vs
backend), and the S9/S10 CPU values. Leave the Instruments `.trace` out of the
repository; it can contain symbolicated paths.

## 5. What to do with the result

| Observation | Meaning | Next step |
| --- | --- | --- |
| `cached_inbox_query_ms` over target, `mail.threads.resolve hit=false` on every selection | Resolver state is being dropped between selections | Check `clearLocalCaches` callers |
| `mail.imap.sessionQueueWait` p95 over ~200 ms during S4/S7 | Foreground work queued behind background sync on the single IMAP session | Justifies the deferred second command session |
| Scroll p95 over 16 ms with `Message List Presentation Build` firing per frame | Presentation cache misses — headers buffer identity not stable | Inspect the `@State headers` path in `MessageListView` |
| S5 heaviest stack in `BrevBackend` | Sidebar resize triggers backend derivation | Bug; file it with the stack |
| S10 `%cpu` steady above 1–2 % | Background cadence or IDLE loop is busy | Check `BackgroundMailCoordinator` tick interval |
| `idle_resident_memory_mb` over 600 with one 10k folder | Header snapshots or presentation caches retained per folder | Allocations track → largest live category |
