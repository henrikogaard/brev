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
OUT="$(cd "$OUT" && pwd)"
clean_env=(env -i "HOME=$HOME" "PATH=$PATH" "TMPDIR=${TMPDIR:-/tmp}")
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  clean_env+=("DEVELOPER_DIR=$DEVELOPER_DIR")
fi
test_pid=""
tracer_pid=""
# Give background jobs owned groups; SwiftPM helpers may create their own.
set -m
cleanup() {
  local status=$?
  trap - EXIT
  local pid attempt alive descendants=()
  # Snapshot only owned descendants, deepest first, before their parents exit.
  while IFS= read -r pid; do
    descendants+=("$pid")
  done < <("${clean_env[@]}" ps -axo pid=,ppid= | "${clean_env[@]}" awk -v test="$test_pid" -v tracer="$tracer_pid" '
    { parent[$1] = $2 }
    END {
      if (test != "") depth[test] = 0
      if (tracer != "") depth[tracer] = 0
      for (level = 1; level <= 32; level++)
        for (pid in parent)
          if (!(pid in depth) && (parent[pid] in depth) && depth[parent[pid]] == level - 1)
            depth[pid] = level
      for (level = 32; level > 0; level--)
        for (pid in depth) if (depth[pid] == level) print pid
    }')
  # Bash 3.2 treats an empty array as unset under nounset.
  for pid in ${descendants[@]+"${descendants[@]}"}; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in "$test_pid" "$tracer_pid"; do
    [[ -z "$pid" ]] || kill -TERM -- "-$pid" 2>/dev/null || true
  done
  for attempt in {1..20}; do
    alive=false
    for pid in "$test_pid" "$tracer_pid"; do
      if [[ -n "$pid" ]] && kill -0 -- "-$pid" 2>/dev/null; then alive=true; fi
    done
    for pid in ${descendants[@]+"${descendants[@]}"}; do
      if kill -0 "$pid" 2>/dev/null; then alive=true; fi
    done
    "$alive" || break
    sleep 0.1
  done
  for pid in ${descendants[@]+"${descendants[@]}"}; do
    kill -KILL "$pid" 2>/dev/null || true
  done
  for pid in "$test_pid" "$tracer_pid"; do
    [[ -n "$pid" ]] || continue
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
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
trap 'exit 130' INT
trap 'exit 143' TERM
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
notification="eu.brevmail.brev.profile.$("${clean_env[@]}" uuidgen)"
"${clean_env[@]}" BREV_PROFILE_NAVIGATION=1 BREV_PROFILE_HANDSHAKE_DIR="$OUT" \
  BREV_PROFILE_TRACING_NOTIFICATION="$notification" swift test -c release --skip-build --package-path "$ROOT/packages/BrevMail" \
  --filter NavigationSelectionProfileTests > "$OUT/test.log" 2>&1 &
test_pid=$!
profile_pid=""
for attempt in {1..30}; do
  if [[ -s "$OUT/workload.pid" ]]; then
    profile_pid="$(cat "$OUT/workload.pid")"
    [[ "$profile_pid" =~ ^[0-9]+$ ]] && is_test_descendant "$profile_pid" || {
      echo 'Announced workload is not owned by this test invocation' >&2
      exit 1
    }
    break
  fi
  if ! kill -0 "$test_pid" 2>/dev/null; then
    wait "$test_pid"
    echo 'Synthetic test exited before announcing its workload PID' >&2
    exit 1
  fi
  sleep 1
done
[[ -n "$profile_pid" ]] || { echo 'Timed out waiting for workload PID' >&2; exit 124; }
is_test_descendant "$profile_pid" || { echo 'Synthetic test process ownership changed before attachment' >&2; exit 1; }
echo "Verified profiling target pid=$profile_pid is a descendant of test pid=$test_pid."
# Startup has a separate handshake budget; recording covers the 25s workload.
"${clean_env[@]}" xcrun xctrace record --template 'Time Profiler' --attach "$profile_pid" --time-limit 75s \
  --notify-tracing-started "$notification" --output "$OUT/navigation.trace" > "$OUT/tracer.log" 2>&1 &
tracer_pid=$!
for attempt in {1..120}; do
  [[ ! -f "$OUT/workload.ready" ]] || break
  if ! kill -0 "$tracer_pid" 2>/dev/null; then
    wait "$tracer_pid"
    echo 'Tracer exited before the workload acknowledged recording start' >&2
    exit 1
  fi
  if ! kill -0 "$test_pid" 2>/dev/null; then
    wait "$test_pid"
    echo 'Synthetic test exited before recording started' >&2
    exit 1
  fi
  sleep 1
done
[[ -f "$OUT/workload.ready" && "$(cat "$OUT/workload.ready")" == "$notification" ]] || {
  echo 'Timed out waiting for tracer-start acknowledgement' >&2
  exit 124
}
echo "Workload pid=$profile_pid acknowledged tracing started."
wait "$test_pid"
wait "$tracer_pid"
grep '^PERF navigation.selection' "$OUT/test.log"
"${clean_env[@]}" xcrun xctrace export --input "$OUT/navigation.trace" --toc --output "$OUT/trace-toc.xml"
echo "Synthetic trace recorded for commit $("${clean_env[@]}" git -C "$ROOT" rev-parse HEAD)."
echo 'Raw trace stays in private runner storage; no live mailbox or SwiftUI frame-budget claim.'
