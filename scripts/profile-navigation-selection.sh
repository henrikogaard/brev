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
test_identity=""
tracer_identity=""
# Give background jobs owned groups; SwiftPM helpers may create their own.
set -m
process_identity() {
  "${clean_env[@]}" ps -p "$1" -o pgid=,lstart= 2>/dev/null |
    "${clean_env[@]}" awk '{$1=$1; print}'
}
same_process() {
  local current
  [[ -n "$1" && -n "$2" ]] || return 1
  current="$(process_identity "$1")" || return 1
  [[ "$current" == "$2" ]]
}
wait_for_job() {
  local name="$1" pid_var="${1}_pid" status=0
  [[ -n "${!pid_var}" ]] || return 0
  wait "${!pid_var}" || status=$?
  # A reaped PID/PGID is no longer ours, regardless of its exit status.
  printf -v "$pid_var" '%s' ""
  printf -v "${name}_identity" '%s' ""
  return "$status"
}
cleanup() {
  local status=$?
  trap - EXIT
  local pid identity index attempt alive pids=() identities=()
  # Seed only from still-owned roots; retain each descendant identity before TERM.
  while IFS='|' read -r pid identity; do
    pids+=("$pid")
    identities+=("$identity")
  done < <("${clean_env[@]}" ps -axo pid=,ppid=,pgid=,lstart= | "${clean_env[@]}" awk \
    -v test="$test_pid" -v tracer="$tracer_pid" -v owner="$$" \
    -v test_identity="$test_identity" -v tracer_identity="$tracer_identity" '
    {
      pid = $1
      parent[pid] = $2
      $1 = $2 = ""
      sub(/^ +/, "")
      identity[pid] = $0
    }
    END {
      if (test_identity != "" && identity[test] == test_identity && parent[test] == owner) depth[test] = 0
      if (tracer_identity != "" && identity[tracer] == tracer_identity && parent[tracer] == owner) depth[tracer] = 0
      for (level = 1; level <= 32; level++)
        for (pid in parent)
          if (!(pid in depth) && (parent[pid] in depth) && depth[parent[pid]] == level - 1)
            depth[pid] = level
      for (level = 32; level >= 0; level--)
        for (pid in depth) if (depth[pid] == level) print pid "|" identity[pid]
    }')
  for index in "${!pids[@]}"; do
    same_process "${pids[index]}" "${identities[index]}" || continue
    kill -TERM "${pids[index]}" 2>/dev/null || true
  done
  for attempt in {1..20}; do
    alive=false
    for index in "${!pids[@]}"; do
      if same_process "${pids[index]}" "${identities[index]}"; then alive=true; fi
    done
    "$alive" || break
    sleep 0.1
  done
  for index in "${!pids[@]}"; do
    same_process "${pids[index]}" "${identities[index]}" || continue
    kill -KILL "${pids[index]}" 2>/dev/null || true
  done
  for index in "${!pids[@]}"; do
    pid="${pids[index]}"
    if [[ "$pid" == "$test_pid" || "$pid" == "$tracer_pid" ]]; then
      wait "$pid" 2>/dev/null || true
    fi
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
test_identity="$(process_identity "$test_pid")" || test_identity=""
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
    wait_for_job test
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
tracer_identity="$(process_identity "$tracer_pid")" || tracer_identity=""
for attempt in {1..120}; do
  [[ ! -f "$OUT/workload.ready" ]] || break
  if ! kill -0 "$tracer_pid" 2>/dev/null; then
    wait_for_job tracer
    [[ ! -f "$OUT/workload.ready" ]] || break
    echo 'Tracer exited before the workload acknowledged recording start' >&2
    exit 1
  fi
  if ! kill -0 "$test_pid" 2>/dev/null; then
    wait_for_job test
    [[ ! -f "$OUT/workload.ready" ]] || break
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
wait_for_job test
wait_for_job tracer
grep '^PERF navigation.selection' "$OUT/test.log"
"${clean_env[@]}" xcrun xctrace export --input "$OUT/navigation.trace" --toc --output "$OUT/trace-toc.xml"
echo "Synthetic trace recorded for commit $("${clean_env[@]}" git -C "$ROOT" rev-parse HEAD)."
echo 'Raw trace stays in private runner storage; no live mailbox or SwiftUI frame-budget claim.'
