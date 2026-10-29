#!/usr/bin/env bash
# Synthetic Release-only selection profiling. Never launches the installed mail app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: profile-navigation-selection.sh <private-output-directory>}"
mkdir -p "$OUT"
swift test -c release --package-path "$ROOT/packages/BrevMail" --build-tests > "$OUT/build.log" 2>&1
BREV_PROFILE_NAVIGATION=1 swift test -c release --skip-build --package-path "$ROOT/packages/BrevMail" \
  --filter NavigationSelectionProfileTests > "$OUT/test.log" 2>&1 &
test_pid=$!
trap 'kill "$test_pid" 2>/dev/null || true' EXIT
profile_pid=""
for attempt in {1..30}; do
  profile_pid="$(pgrep -n -f '/BrevMailPackageTests.xctest/Contents/MacOS/BrevMailPackageTests' || true)"
  [[ -z "$profile_pid" ]] || break
  kill -0 "$test_pid" 2>/dev/null || { cat "$OUT/test.log"; exit 1; }
  sleep 1
done
[[ -n "$profile_pid" ]] || { echo 'Synthetic test process not found'; exit 1; }
xcrun xctrace record --template 'Time Profiler' --attach "$profile_pid" --time-limit 35s \
  --output "$OUT/navigation.trace" > "$OUT/tracer.log" 2>&1
wait "$test_pid"
trap - EXIT
grep '^PERF navigation.selection' "$OUT/test.log"
xcrun xctrace export --input "$OUT/navigation.trace" --toc --output "$OUT/trace-toc.xml"
echo "Synthetic trace recorded for commit $(git -C "$ROOT" rev-parse HEAD)."
echo 'Raw trace stays in private runner storage; no live mailbox or SwiftUI frame-budget claim.'
