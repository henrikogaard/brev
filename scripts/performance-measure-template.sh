#!/usr/bin/env bash
# performance-measure-template.sh — Write a measured budget JSON for evaluate mode.
#
# This harness validates the budget evaluation path with sample values. For a
# real local run, first collect the privacy-safe Performance category with
# scripts/collect-performance-trace.sh, then summarize the measured values into
# this script's JSON schema before running the budget gate.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

out="${1:-/tmp/brev-perf-results.json}"

if [[ "${BREV_PERF_WRITE_SAMPLE:-}" == "1" ]]; then
  cat >"$out" <<'JSON'
{
  "cached_inbox_usable_ms": 720,
  "cached_inbox_query_ms": 180,
  "cached_thread_open_ms": 260,
  "list_scroll_frame_p95_ms": 14,
  "idle_resident_memory_mb": 520
}
JSON
  echo "wrote sample measurements to $out"
  BREV_PERF_RESULTS_JSON="$out" scripts/performance-budget-gate.sh
  exit 0
fi

cat <<EOF2
usage: BREV_PERF_WRITE_SAMPLE=1 scripts/performance-measure-template.sh [/tmp/brev-perf-results.json]

For a live trace (no message content or account identifiers):
  scripts/collect-performance-trace.sh --last 10m --output /tmp/brev-performance.log

Provide summarized measurements keyed by budget metric raw values, then:
  BREV_PERF_RESULTS_JSON=/path/to/results.json scripts/performance-budget-gate.sh
EOF2
