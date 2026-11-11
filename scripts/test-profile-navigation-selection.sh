#!/usr/bin/env bash
# Hermetic profiling-harness regression tests. No build, trace, or mailbox access.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/tmp" "$TMP/Developer"
printf '%s' "$TMP/bin:$PATH" > "$TMP/path"

cat > "$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
echo fixture-source-revision
STUB

cat > "$TMP/intercept-signals.sh" <<'STUB'
# Loaded only by the harness shell; env -i removes BASH_ENV from its children.
kill() {
  local fixture_root target scenario
  fixture_root="$(dirname "$BASH_ENV")"
  scenario="$(cat "$fixture_root/case")"
  target="${!#}"
  if [[ "$scenario" == cleanup-* ]]; then
    [[ "$1" == -0 ]] || printf '%s\n' "$*" >> "$fixture_root/signals"
    if [[ "$scenario" == cleanup-escalation-reused && "$1" == -TERM && "$target" == 99991 ]]; then
      touch "$fixture_root/child-reused"
    fi
    if [[ "$scenario" == cleanup-root-escalation-reused && "$1" == -TERM && "$target" == 99990 ]]; then
      touch "$fixture_root/root-reused"
    fi
    return 0
  fi
  if [[ -f "$fixture_root/reuse-ready" ]] &&
    [[ "$target" == 99991 || "$target" == "-$(cat "$fixture_root/test-pid")" ||
       "$target" == "$(cat "$fixture_root/test-pid")" ]]; then
    [[ "$1" == -0 ]] || printf '%s\n' "$*" >> "$fixture_root/unowned-signals"
    return 0
  fi
  builtin kill "$@"
}
STUB

cat > "$TMP/fixture.sh" <<'STUB'
fixture_root="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE_TEST_CASE="$(cat "$fixture_root/case")"
PROFILE_TEST_CALLS="$fixture_root/$PROFILE_TEST_CASE.calls"
env_log="$fixture_root/$PROFILE_TEST_CASE.env"
command_name="$(basename "$0")"
echo "$command_name $*" >> "$PROFILE_TEST_CALLS"
if [[ -n "${PROFILE_SENTINEL_SECRET+x}" ]]; then
  echo "$command_name inherited secret" >> "$env_log"
fi
if [[ "$HOME" == "$fixture_root/home" && "$TMPDIR" == "$fixture_root/tmp" &&
      "$DEVELOPER_DIR" == "$fixture_root/Developer" && "$PATH" == "$(cat "$fixture_root/path")" ]]; then
  echo "$command_name $1 allowed" >> "$env_log"
fi
if [[ "$command_name $1" == 'swift test' && "${BREV_PROFILE_NAVIGATION:-}" == 1 ]]; then
  echo 'workload enabled' >> "$env_log"
fi
STUB

cat > "$TMP/bin/swift" <<'STUB'
#!/usr/bin/env bash
source "$(dirname "$0")/../fixture.sh"
if [[ "$*" == *--build-tests* ]]; then
  echo build-log
  [[ "$1" == build ]] || { echo 'Unknown option --build-tests'; exit 64; }
  [[ "$*" == *'-Xswiftc -enable-testing'* ]] || { echo 'ModuleNotTestable'; exit 65; }
  [[ "$PROFILE_TEST_CASE" != build-failure ]] || exit 23
  [[ "$PROFILE_TEST_CASE" != existing-output ]] || exit 23
else
  echo test-log
  echo "$$" > "$fixture_root/test-pid"
  [[ "$PROFILE_TEST_CASE" != test-failure ]] || exit 42
  if [[ "$PROFILE_TEST_CASE" == detached-workload ]]; then set -m; fi
  bash "$fixture_root/bin/workload" &
  wait "$!"
fi
STUB
cat > "$TMP/bin/workload" <<'STUB'
#!/usr/bin/env bash
source "$(dirname "$0")/../fixture.sh"
echo "$$" > "$fixture_root/workload-pid"
if [[ "$PROFILE_TEST_CASE" == stubborn-child ]]; then
  /bin/bash -c 'trap "" TERM; exec /bin/sleep 60' &
else
  /bin/sleep 60 &
fi
child=$!
echo "$child" > "$fixture_root/workload-child-pid"
trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true' EXIT
trap 'exit 143' TERM
[[ "$PROFILE_TEST_CASE" != missing-process ]] || exit 0
[[ "$PROFILE_TEST_CASE" != delayed-readiness ]] || /bin/sleep 0.2
[[ "$PROFILE_TEST_CASE" != pid-timeout ]] || { wait "$child"; exit; }
directory="${BREV_PROFILE_HANDSHAKE_DIR:-$fixture_root/unconfigured}"
mkdir -p "$directory"
pid=$$
[[ "$PROFILE_TEST_CASE" != unrelated-only ]] || pid=99999
[[ "$PROFILE_TEST_CASE" != malformed-pid ]] || pid=not-a-pid
printf '%s' "$pid" > "$directory/workload.pid.partial"
mv "$directory/workload.pid.partial" "$directory/workload.pid"
for attempt in {1..400}; do
  if [[ -f "$directory/tracer.started" ]]; then
    printf '%s' "${BREV_PROFILE_TRACING_NOTIFICATION:-missing}" > "$directory/workload.ready.partial"
    mv "$directory/workload.ready.partial" "$directory/workload.ready"
    [[ "$PROFILE_TEST_CASE" != test-failure-after-ready ]] || exit 43
    echo 'PERF navigation.selection rows=10000 iterations=1 build=release'
    touch "$directory/workload.completed"
    exit 0
  fi
  /bin/sleep 0.01
done
exit 124
STUB
cat > "$TMP/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
source "$(dirname "$0")/../fixture.sh"
[[ "$PROFILE_TEST_CASE" != missing-process ]] || exit 1
for attempt in {1..50}; do
  [[ ! -s "$fixture_root/test-pid" ]] || break
  sleep 0.01
done
if [[ "$PROFILE_TEST_CASE" == unrelated-only ]]; then
  echo 99999
  exit 0
fi
if [[ "$PROFILE_TEST_CASE" == unrelated-newer ]]; then
  echo 99999
  [[ "$1" != -n ]] || exit 0
fi
echo 12345
STUB
cat > "$TMP/bin/ps" <<'STUB'
#!/usr/bin/env bash
source "$(dirname "$0")/../fixture.sh"
if [[ "$PROFILE_TEST_CASE" == cleanup-* ]]; then
  owner="$(cat "$fixture_root/cleanup-owner")"
  root_start='Mon Nov 2 22:00:00 2026'
  if [[ "$PROFILE_TEST_CASE" == cleanup-root-reused || -f "$fixture_root/root-reused" ]]; then
    root_start='Mon Nov 2 22:00:01 2026'
  fi
  if [[ "$1" == -axo ]]; then
    printf '99990 %s 99990 %s\n99991 99990 99991 Mon Nov 2 22:00:00 2026\n' "$owner" "$root_start"
  elif [[ "$2" == 99990 ]]; then
    printf '99990 %s\n' "$root_start"
  elif [[ "$2" == 99991 ]]; then
    if [[ "$PROFILE_TEST_CASE" == cleanup-child-reused || -f "$fixture_root/child-reused" ]]; then
      echo '99991 Mon Nov 2 22:00:01 2026'
    else
      echo '99991 Mon Nov 2 22:00:00 2026'
    fi
  else
    exit 1
  fi
  exit 0
fi
if [[ "$PROFILE_TEST_CASE" == recycled-root && "$1" == -axo && -f "$fixture_root/reuse-ready" ]]; then
  root="$(cat "$fixture_root/test-pid")"
  printf '%s 1 %s Mon Nov 2 22:00:01 2026\n99991 %s 99991 Mon Nov 2 22:00:01 2026\n' "$root" "$root" "$root"
  exit 0
fi
if [[ "$2" == 99999 ]]; then echo 1; exit; fi
if [[ "$2" == 12345 ]]; then cat "$fixture_root/test-pid"; exit; fi
if [[ "$PROFILE_TEST_CASE" == ownership-lost && "$4" == ppid= &&
      "$2" == "$(cat "$fixture_root/workload-pid")" ]]; then
  if [[ -f "$fixture_root/ownership-checked" ]]; then echo 1; exit; fi
  touch "$fixture_root/ownership-checked"
fi
/bin/ps "$@"
STUB
cat > "$TMP/bin/xcrun" <<'STUB'
#!/usr/bin/env bash
source "$(dirname "$0")/../fixture.sh"
echo tracer-log
if [[ "$2" == export ]]; then
  [[ "$PROFILE_TEST_CASE" != recycled-root ]] || touch "$fixture_root/reuse-ready"
  [[ "$PROFILE_TEST_CASE" != export-failure ]] || exit 44
  exit 0
fi
echo "$$" > "$fixture_root/tracer-pid"
/bin/sleep 60 &
child=$!
echo "$child" > "$fixture_root/tracer-child-pid"
trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true' EXIT
trap 'exit 143' TERM
[[ "$PROFILE_TEST_CASE" != tracer-failure && "$PROFILE_TEST_CASE" != stubborn-child &&
   "$PROFILE_TEST_CASE" != detached-workload ]] || exit 31
directory=""
notification=""
target=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output) directory="$(dirname "$2")"; shift ;;
    --notify-tracing-started) notification="$2"; shift ;;
    --attach) target="$2"; shift ;;
  esac
  shift
done
[[ -n "$notification" ]] || exit 32
[[ "$target" == "$(cat "$fixture_root/workload-pid")" ]] || exit 33
[[ "$PROFILE_TEST_CASE" != tracer-early-success ]] || exit 0
[[ "$PROFILE_TEST_CASE" != tracer-timeout && "$PROFILE_TEST_CASE" != interrupted ]] || { wait "$child"; exit; }
/bin/sleep 0.2
touch "$directory/tracer.started"
for attempt in {1..400}; do
  [[ ! -f "$directory/workload.completed" ]] || exit 0
  /bin/sleep 0.01
done
exit 34
STUB
cat > "$TMP/bin/sleep" <<'STUB'
#!/usr/bin/env bash
# Accelerate only harness polling, not the workload/tracer fixture.
/bin/sleep 0.01
STUB
chmod +x "$TMP/bin/"*

failures=0
check() {
  if "$@"; then return; fi
  echo "FAIL ($PROFILE_TEST_CASE): $*" >&2
  failures=$((failures + 1))
}
run_case() {
  PROFILE_TEST_CASE="$1"
  PROFILE_TEST_CALLS="$TMP/$1.calls"
  printf '%s' "$1" > "$TMP/case"
  rm -f "$TMP/"*-pid "$TMP/ownership-checked"
  : > "$PROFILE_TEST_CALLS"
  : > "$TMP/$1.env"
  local status=0
  # Use the suite's shell so system-Bash runs cannot fall back to a newer PATH shell.
  HOME="$TMP/home" PATH="$TMP/bin:$PATH" TMPDIR="$TMP/tmp" DEVELOPER_DIR="$TMP/Developer" \
    BASH_ENV="$TMP/intercept-signals.sh" \
    PROFILE_SENTINEL_SECRET=not-a-real-secret \
    "$BASH" "$ROOT/scripts/profile-navigation-selection.sh" "$TMP/$1 output" \
    > "$TMP/$1.log" 2>&1 &
  local harness_pid=$! attempt
  if [[ "$1" == interrupted ]]; then
    for attempt in {1..200}; do
      [[ ! -s "$TMP/tracer-pid" ]] || break
      /bin/sleep 0.01
    done
    kill -TERM "$harness_pid"
  fi
  wait "$harness_pid" || status=$?
  check test "$status" -eq "$2"
  if [[ "$status" -ne "$2" ]]; then cat "$TMP/$1.log" >&2; fi
  check test "$(grep -c 'inherited secret' "$TMP/$1.env" || true)" -eq 0
  for pid_file in "$TMP/"*-pid; do
    [[ -f "$pid_file" ]] || continue
    pid="$(cat "$pid_file")"
    for attempt in {1..50}; do
      kill -0 "$pid" 2>/dev/null || break
      /bin/sleep 0.01
    done
    check test "$(ps -p "$pid" -o stat= 2>/dev/null | tr -d '[:space:]' || true)" = ""
    # Reap leaked fixtures after recording a failed cleanup assertion.
    kill "$pid" 2>/dev/null || true
  done
}

run_case success 0
check grep -q '^swift build -c release .*--build-tests -Xswiftc -enable-testing$' "$PROFILE_TEST_CALLS"
check grep -q '^swift test -c release --skip-build .*--filter NavigationSelectionProfileTests$' "$PROFILE_TEST_CALLS"
check grep -q '^PERF navigation.selection' "$TMP/success.log"
check test "$(grep -c 'inherited secret' "$TMP/success.env" || true)" -eq 0
check grep -qx 'swift build allowed' "$TMP/success.env"
check grep -qx 'swift test allowed' "$TMP/success.env"
check grep -qx 'xcrun xctrace allowed' "$TMP/success.env"
check test "$(grep -c '^xcrun xctrace allowed$' "$TMP/success.env")" -eq 2
check grep -qx 'workload enabled' "$TMP/success.env"
check test "$(LC_ALL=C ls -ld "$TMP/success output" | cut -c1-10)" = drwx------
check test "$(LC_ALL=C ls -l "$TMP/success output/build.log" | cut -c1-10)" = -rw-------
limit="$(sed -n 's/.*--time-limit \([0-9]*\)s .*/\1/p' "$PROFILE_TEST_CALLS")"
# Recording starts before the 25s workload; startup has its own bounded handshake.
check test "${limit:-0}" -gt 65
check grep -q -- '--notify-tracing-started eu.brevmail.brev.profile.' "$PROFILE_TEST_CALLS"
check test -s "$TMP/success output/workload.ready"
check test "$(grep -c '^pgrep ' "$PROFILE_TEST_CALLS" || true)" -eq 0

run_case delayed-readiness 0
check grep -q -- "--attach $(cat "$TMP/workload-pid") " "$PROFILE_TEST_CALLS"
run_case pid-timeout 124
check test "$(grep -c '^xcrun ' "$PROFILE_TEST_CALLS" || true)" -eq 0
run_case tracer-timeout 124
check test ! -f "$TMP/tracer-timeout output/workload.ready"
check test ! -f "$TMP/tracer-timeout output/workload.completed"
run_case tracer-early-success 1
check test ! -f "$TMP/tracer-early-success output/workload.ready"
run_case test-failure-after-ready 43
run_case export-failure 44
run_case malformed-pid 1
check test "$(grep -c '^xcrun ' "$PROFILE_TEST_CALLS" || true)" -eq 0
run_case interrupted 143
run_case stubborn-child 31
run_case detached-workload 31

run_case build-failure 23
check grep -q build-log "$TMP/build-failure.log"
run_case test-failure 42
check grep -q build-log "$TMP/test-failure.log"
check grep -q test-log "$TMP/test-failure.log"
run_case tracer-failure 31
check grep -q build-log "$TMP/tracer-failure.log"
check grep -q test-log "$TMP/tracer-failure.log"
check grep -q tracer-log "$TMP/tracer-failure.log"
run_case missing-process 1
check grep -q build-log "$TMP/missing-process.log"
check grep -q test-log "$TMP/missing-process.log"

run_case unrelated-newer 0
check grep -q -- "--attach $(cat "$TMP/workload-pid") " "$PROFILE_TEST_CALLS"
check test "$(grep -c -- '--attach 12345 ' "$PROFILE_TEST_CALLS" || true)" -eq 0
check test "$(grep -c -- '--attach 99999 ' "$PROFILE_TEST_CALLS" || true)" -eq 0
run_case unrelated-only 1
check test "$(grep -c '^xcrun ' "$PROFILE_TEST_CALLS" || true)" -eq 0
run_case ownership-lost 1
check test "$(grep -c '^xcrun ' "$PROFILE_TEST_CALLS" || true)" -eq 0

run_case recycled-root 0
check test ! -s "$TMP/unowned-signals"
rm -f "$TMP/reuse-ready"

# Exercise cleanup with an entirely simulated process table. No signal in these
# cases is ever delegated to the OS, including signals to the invented roots.
sed '/^trap cleanup EXIT/,$d' "$ROOT/scripts/profile-navigation-selection.sh" > "$TMP/cleanup-functions.sh"
for scenario in cleanup-root-reused cleanup-child-reused cleanup-escalation-reused \
  cleanup-root-escalation-reused cleanup-stable; do
  PROFILE_TEST_CASE="$scenario"
  printf '%s' "$scenario" > "$TMP/case"
  : > "$TMP/signals"
  rm -f "$TMP/child-reused" "$TMP/root-reused"
  HOME="$TMP/home" PATH="$TMP/bin:$PATH" TMPDIR="$TMP/tmp" DEVELOPER_DIR="$TMP/Developer" \
    BASH_ENV="$TMP/intercept-signals.sh" \
    "$BASH" -c '
      source "$1" "$2"
      echo "$$" > "$(dirname "$2")/cleanup-owner"
      test_pid=99990
      test_identity="99990 Mon Nov 2 22:00:00 2026"
      cleanup
    ' cleanup "$TMP/cleanup-functions.sh" "$TMP/$scenario output" > "$TMP/$scenario.log" 2>&1
  if [[ "$scenario" == cleanup-root-reused ]]; then
    check test ! -s "$TMP/signals"
  else
    check grep -qx -- '-TERM 99990' "$TMP/signals"
    check test "$(grep -c -- '-- -' "$TMP/signals" || true)" -eq 0
    if [[ "$scenario" == cleanup-root-escalation-reused ]]; then
      check test "$(grep -c -- '-KILL 99990' "$TMP/signals" || true)" -eq 0
    else
      check grep -qx -- '-KILL 99990' "$TMP/signals"
    fi
    if [[ "$scenario" == cleanup-child-reused ]]; then
      check test "$(grep -c '99991' "$TMP/signals" || true)" -eq 0
    else
      check grep -qx -- '-TERM 99991' "$TMP/signals"
      if [[ "$scenario" == cleanup-escalation-reused ]]; then
        check test "$(grep -c -- '-KILL 99991' "$TMP/signals" || true)" -eq 0
      else
        check grep -qx -- '-KILL 99991' "$TMP/signals"
      fi
    fi
  fi
done

mkdir "$TMP/existing-output output"
echo stale-sensitive-content > "$TMP/existing-output output/test.log"
echo stale-sensitive-content > "$TMP/existing-output output/tracer.log"
run_case existing-output 1
check test ! -s "$PROFILE_TEST_CALLS"
check test "$(grep -c stale-sensitive-content "$TMP/existing-output.log" || true)" -eq 0
check grep -qx stale-sensitive-content "$TMP/existing-output output/test.log"

[[ "$failures" -eq 0 ]] || { echo "$failures profiling harness checks failed" >&2; exit 1; }
echo 'test-profile-navigation-selection: all checks passed'
