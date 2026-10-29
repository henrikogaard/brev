#!/usr/bin/env bash
# Synthetic Release-only selection profiling. Never launches the installed mail app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: profile-navigation-selection.sh <new-private-output-directory>}"
umask 077
if ! mkdir -m 700 "$OUT"; then
  echo 'Choose a new output directory under an existing private parent.' >&2
  exit 1
fi
clean_env=(env -i "HOME=$HOME" "PATH=$PATH" "TMPDIR=${TMPDIR:-/tmp}")
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  clean_env+=("DEVELOPER_DIR=$DEVELOPER_DIR")
fi
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
is_test_descendant() {
  local pid="$1" parent_pid depth
  for depth in {1..32}; do
    parent_pid="$("${clean_env[@]}" ps -p "$pid" -o ppid= 2>/dev/null)" || return 1
    parent_pid="${parent_pid//[[:space:]]/}"
    [[ "$parent_pid" =~ ^[0-9]+$ ]] || return 1
    [[ "$parent_pid" != "$test_pid" ]] || return 0
    [[ "$parent_pid" -gt 1 && "$parent_pid" != "$pid" ]] || return 1
    pid="$parent_pid"
  done
  return 1
}
"${clean_env[@]}" swift build -c release --package-path "$ROOT/packages/BrevMail" --build-tests \
  -Xswiftc -enable-testing > "$OUT/build.log" 2>&1
"${clean_env[@]}" BREV_PROFILE_NAVIGATION=1 swift test -c release --skip-build --package-path "$ROOT/packages/BrevMail" \
  --filter NavigationSelectionProfileTests > "$OUT/test.log" 2>&1 &
test_pid=$!
profile_pid=""
for attempt in {1..30}; do
  while IFS= read -r candidate; do
    [[ "$candidate" =~ ^[0-9]+$ ]] || continue
    if is_test_descendant "$candidate"; then
      profile_pid="$candidate"
      break
    fi
  done < <("${clean_env[@]}" pgrep -f '/BrevMailPackageTests.xctest/Contents/MacOS/BrevMailPackageTests' || true)
  [[ -z "$profile_pid" ]] || break
  if ! kill -0 "$test_pid" 2>/dev/null; then
    wait "$test_pid"
    echo 'Synthetic test exited before the tracer could attach' >&2
    exit 1
  fi
  sleep 1
done
[[ -n "$profile_pid" ]] || { echo 'Synthetic test process not found'; exit 1; }
is_test_descendant "$profile_pid" || { echo 'Synthetic test process ownership changed before attachment' >&2; exit 1; }
echo "Verified profiling target pid=$profile_pid is a descendant of test pid=$test_pid."
# Allow discovery (30s), attachment delay (10s), workload (25s), and a 10s margin.
"${clean_env[@]}" xcrun xctrace record --template 'Time Profiler' --attach "$profile_pid" --time-limit 75s \
  --output "$OUT/navigation.trace" > "$OUT/tracer.log" 2>&1
wait "$test_pid"
test_pid=""
grep '^PERF navigation.selection' "$OUT/test.log"
"${clean_env[@]}" xcrun xctrace export --input "$OUT/navigation.trace" --toc --output "$OUT/trace-toc.xml"
echo "Synthetic trace recorded for commit $("${clean_env[@]}" git -C "$ROOT" rev-parse HEAD)."
echo 'Raw trace stays in private runner storage; no live mailbox or SwiftUI frame-budget claim.'
