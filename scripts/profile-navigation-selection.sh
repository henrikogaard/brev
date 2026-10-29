#!/usr/bin/env bash
# Synthetic Release-only selection profiling. Never launches the installed mail app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: profile-navigation-selection.sh <private-output-directory>}"
mkdir -p "$OUT"
test_pid=""
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$test_pid" ]]; then
    kill "$test_pid" 2>/dev/null || true
    wait "$test_pid" 2>/dev/null || true
  fi
  if [[ "$status" -ne 0 ]]; then
    for log in build test tracer; do
      if [[ -f "$OUT/$log.log" ]]; then
        echo "=== $log.log ===" >&2
        cat "$OUT/$log.log" >&2
      fi
    done
  fi
  exit "$status"
}
trap cleanup EXIT
swift build -c release --package-path "$ROOT/packages/BrevMail" --build-tests \
  -Xswiftc -enable-testing > "$OUT/build.log" 2>&1
BREV_PROFILE_NAVIGATION=1 swift test -c release --skip-build --package-path "$ROOT/packages/BrevMail" \
  --filter NavigationSelectionProfileTests > "$OUT/test.log" 2>&1 &
test_pid=$!
profile_pid=""
for attempt in {1..30}; do
  profile_pid="$(pgrep -n -f '/BrevMailPackageTests.xctest/Contents/MacOS/BrevMailPackageTests' || true)"
  [[ -z "$profile_pid" ]] || break
  if ! kill -0 "$test_pid" 2>/dev/null; then
    wait "$test_pid"
    echo 'Synthetic test exited before the tracer could attach' >&2
    exit 1
  fi
  sleep 1
done
[[ -n "$profile_pid" ]] || { echo 'Synthetic test process not found'; exit 1; }
# Allow discovery (30s), attachment delay (10s), workload (25s), and a 10s margin.
xcrun xctrace record --template 'Time Profiler' --attach "$profile_pid" --time-limit 75s \
  --output "$OUT/navigation.trace" > "$OUT/tracer.log" 2>&1
wait "$test_pid"
test_pid=""
grep '^PERF navigation.selection' "$OUT/test.log"
xcrun xctrace export --input "$OUT/navigation.trace" --toc --output "$OUT/trace-toc.xml"
echo "Synthetic trace recorded for commit $(git -C "$ROOT" rev-parse HEAD)."
echo 'Raw trace stays in private runner storage; no live mailbox or SwiftUI frame-budget claim.'
