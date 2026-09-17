#!/usr/bin/env python3
"""performance-summarize-trace.py — Turn a Brev Performance log export into budget JSON.

Input is the output of `scripts/collect-performance-trace.sh` (or `log show`
filtered to subsystem eu.brevmail.brev / category Performance). Every event
line has the shape `<event> [finished|failed] key=value ... durationMs=N`; the
values are timings, counts, booleans and path names only, so this script never
sees message content or account identifiers.

Output is a JSON object keyed by the budget metric names understood by
scripts/performance-budget-gate.sh, plus a `_detail` block with per-event
statistics for the worklog. Scroll frame time and resident memory are not in
the unified log; pass them in with --scroll-p95-ms and --memory-mb after
reading them from Instruments / `footprint` as described in
docs/qa/performance-live-run.md.

usage:
  scripts/performance-summarize-trace.py /tmp/brev-performance.log \
      --scroll-p95-ms 14 --memory-mb 520 --output /tmp/brev-perf-results.json
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from collections import defaultdict

LINE = re.compile(r"(?P<event>(?:mail|ui)\.[A-Za-z.]+)(?:\s+(?P<status>finished|failed))?\s+(?P<body>.*?durationMs=(?P<ms>[0-9.]+))")
KV = re.compile(r"(\w+)=([A-Za-z0-9._-]+)")
TAGS = ("path", "surface", "execution", "renderer", "hit", "update")


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((pct / 100.0) * (len(ordered) - 1))))
    return ordered[index]


def summarize(values: list[float]) -> dict:
    return {
        "count": len(values),
        "median_ms": round(statistics.median(values), 2),
        "p95_ms": round(percentile(values, 95), 2),
        "max_ms": round(max(values), 2),
    }


def parse(lines) -> dict[str, list[float]]:
    buckets: dict[str, list[float]] = defaultdict(list)
    for line in lines:
        match = LINE.search(line)
        if not match:
            continue
        fields = dict(KV.findall(match.group("body")))
        key = match.group("event")
        if match.group("status") == "failed":
            key += " failed"
        for tag in TAGS:
            if tag in fields:
                key += f" {tag}={fields[tag]}"
        buckets[key].append(float(match.group("ms")))
    return buckets


def pick(buckets: dict[str, list[float]], event: str, **tags: str) -> list[float]:
    """Collect durations for `event` whose bucket carries every given tag=value."""
    values: list[float] = []
    for key, durations in buckets.items():
        parts = key.split(" ")
        if parts[0] != event or "failed" in parts:
            continue
        if all(f"{tag}={value}" in parts for tag, value in tags.items()):
            values.extend(durations)
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("trace", help="log export from scripts/collect-performance-trace.sh")
    parser.add_argument("--scroll-p95-ms", type=float, help="95th percentile frame time from Instruments while scrolling")
    parser.add_argument("--memory-mb", type=float, help="resident memory in MB after 60s idle")
    parser.add_argument("--output", help="write JSON here instead of stdout")
    args = parser.parse_args()

    with open(args.trace, encoding="utf-8", errors="replace") as handle:
        buckets = parse(handle)

    if not buckets:
        print("no Performance events found; is the log export filtered to eu.brevmail.brev/Performance?", file=sys.stderr)
        return 1

    usable = pick(buckets, "ui.list", surface="messageList", path="reload")
    query = pick(buckets, "mail.messages.page", path="cacheHit")
    thread_open = pick(buckets, "ui.body.visible", surface="messageBody") or pick(
        buckets, "ui.body.fetch", surface="messageBody")

    results: dict = {}
    # Budget values use the 95th percentile so one slow outlier in a five-minute
    # session does not hide behind the median, matching the budget table's intent.
    if usable:
        results["cached_inbox_usable_ms"] = round(percentile(usable, 95), 1)
    if query:
        results["cached_inbox_query_ms"] = round(percentile(query, 95), 1)
    if thread_open:
        results["cached_thread_open_ms"] = round(percentile(thread_open, 95), 1)
    if args.scroll_p95_ms is not None:
        results["list_scroll_frame_p95_ms"] = args.scroll_p95_ms
    if args.memory_mb is not None:
        results["idle_resident_memory_mb"] = args.memory_mb

    results["_detail"] = {key: summarize(values) for key, values in sorted(buckets.items())}

    missing = [k for k in ("cached_inbox_usable_ms", "cached_inbox_query_ms", "cached_thread_open_ms",
                           "list_scroll_frame_p95_ms", "idle_resident_memory_mb") if k not in results]
    if missing:
        print(f"warning: budget gate will fail on missing metrics: {', '.join(missing)}", file=sys.stderr)

    text = json.dumps(results, indent=2, sort_keys=True)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")
        print(f"wrote {args.output}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
