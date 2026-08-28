#!/usr/bin/env bash
# performance-budget-gate.sh — Evaluate warm-cache performance budgets (#304).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mode="evaluate"

usage() {
  cat <<'EOF'
usage: scripts/performance-budget-gate.sh [--self-test]

Modes:
  (default)   Evaluate BREV_PERF_RESULTS_JSON when set; otherwise require the file.
  --self-test Run the deterministic budget policy self-check (safe on any dev machine).

Environment:
  BREV_PERF_RESULTS_JSON   JSON object keyed by budget metric raw values.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      mode="self-test"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "performance-budget-gate.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_policy_self_test() {
  python3 - <<'PY'
import math

budgets = {
    "cached_inbox_usable_ms": 1500,
    "cached_inbox_query_ms": 400,
    "cached_thread_open_ms": 600,
    "list_scroll_frame_p95_ms": 32,
    "idle_resident_memory_mb": 900,
}

def violations(data):
    failures = []
    for key, limit in budgets.items():
        if key not in data:
            failures.append(f"missing measurement: {key}")
            continue
        value = float(data[key])
        if math.isnan(value) or value > limit:
            failures.append(f"{key}={value} exceeds hard limit {limit}")
    return failures

sample = {key: limit - 1 for key, limit in budgets.items()}
assert violations(sample) == []
assert violations({**sample, "cached_inbox_query_ms": 401})
assert violations({key: value for key, value in sample.items() if key != "idle_resident_memory_mb"})
print("performance-budget-gate.sh: policy self-check OK")
PY
}

if [[ "$mode" == "self-test" ]]; then
  echo "==> performance budget policy self-check"
  run_policy_self_test
  exit 0
fi

results_path="${BREV_PERF_RESULTS_JSON:-}"
if [[ -z "$results_path" ]]; then
  echo "performance-budget-gate.sh: BREV_PERF_RESULTS_JSON is required for evaluation" >&2
  echo "Use --self-test for policy-only checks or provide summarized measurements." >&2
  exit 1
fi

if [[ ! -f "$results_path" ]]; then
  echo "performance-budget-gate.sh: missing results file: $results_path" >&2
  exit 1
fi

python3 - "$results_path" <<'PY'
import json
import math
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

budgets = {
    "cached_inbox_usable_ms": 1500,
    "cached_inbox_query_ms": 400,
    "cached_thread_open_ms": 600,
    "list_scroll_frame_p95_ms": 32,
    "idle_resident_memory_mb": 900,
}

violations = []
for key, limit in budgets.items():
    if key not in data:
        violations.append(f"missing measurement: {key}")
        continue
    value = float(data[key])
    if math.isnan(value) or value > limit:
        violations.append(f"{key}={value} exceeds hard limit {limit}")

if violations:
    print("performance-budget-gate.sh: budget violations:")
    for item in violations:
        print(f"  - {item}")
    sys.exit(1)

print("performance-budget-gate.sh: all budgets within hard limits")
PY
