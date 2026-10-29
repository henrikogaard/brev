#!/usr/bin/env bash
# Hermetic profiling-harness regression tests. No build, trace, or mailbox access.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/tmp" "$TMP/Developer"
printf '%s' "$TMP/bin:$PATH" > "$TMP/path"

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
  sleep 0.5
  [[ "$PROFILE_TEST_CASE" != test-failure ]] || exit 42
  echo 'PERF navigation.selection rows=10000 iterations=1 build=release'
fi
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
case "$2" in
  12345)
    if [[ "$PROFILE_TEST_CASE" == ownership-lost && -f "$fixture_root/ownership-checked" ]]; then
      echo 1
    else
      touch "$fixture_root/ownership-checked"
      echo 12344
    fi
    ;;
  12344) cat "$fixture_root/test-pid" ;;
  99999) echo 1 ;;
  *) exit 1 ;;
esac
STUB
cat > "$TMP/bin/xcrun" <<'STUB'
#!/usr/bin/env bash
source "$(dirname "$0")/../fixture.sh"
echo tracer-log
[[ "$PROFILE_TEST_CASE" != tracer-failure ]] || exit 31
sleep 0.3
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
  rm -f "$TMP/test-pid" "$TMP/ownership-checked"
  : > "$PROFILE_TEST_CALLS"
  : > "$TMP/$1.env"
  local status=0
  HOME="$TMP/home" PATH="$TMP/bin:$PATH" TMPDIR="$TMP/tmp" DEVELOPER_DIR="$TMP/Developer" \
    PROFILE_SENTINEL_SECRET=not-a-real-secret \
    bash "$ROOT/scripts/profile-navigation-selection.sh" "$TMP/$1 output" \
    > "$TMP/$1.log" 2>&1 || status=$?
  check test "$status" -eq "$2"
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
# Budget: discovery (30s), attachment delay (10s), workload (25s), plus margin.
check test "${limit:-0}" -gt 65

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
check grep -q '^xcrun xctrace record .*--attach 12345 ' "$PROFILE_TEST_CALLS"
check test "$(grep -c -- '--attach 99999 ' "$PROFILE_TEST_CALLS" || true)" -eq 0
run_case unrelated-only 1
check test "$(grep -c '^xcrun ' "$PROFILE_TEST_CALLS" || true)" -eq 0
run_case ownership-lost 1
check test "$(grep -c '^xcrun ' "$PROFILE_TEST_CALLS" || true)" -eq 0

mkdir "$TMP/existing-output output"
echo stale-sensitive-content > "$TMP/existing-output output/test.log"
echo stale-sensitive-content > "$TMP/existing-output output/tracer.log"
run_case existing-output 1
check test ! -s "$PROFILE_TEST_CALLS"
check test "$(grep -c stale-sensitive-content "$TMP/existing-output.log" || true)" -eq 0
check grep -qx stale-sensitive-content "$TMP/existing-output output/test.log"

[[ "$failures" -eq 0 ]] || { echo "$failures profiling harness checks failed" >&2; exit 1; }
echo 'test-profile-navigation-selection: all checks passed'
