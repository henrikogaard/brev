#!/usr/bin/env bash
# Hermetic profiling-harness regression tests. No build, trace, or mailbox access.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/swift" <<'STUB'
#!/usr/bin/env bash
echo "swift $*" >> "$PROFILE_TEST_CALLS"
if [[ "$*" == *--build-tests* ]]; then
  echo build-log
  [[ "$1" == build ]] || { echo 'Unknown option --build-tests'; exit 64; }
  [[ "$*" == *'-Xswiftc -enable-testing'* ]] || { echo 'ModuleNotTestable'; exit 65; }
  [[ "$PROFILE_TEST_CASE" != build-failure ]] || exit 23
else
  echo test-log
  sleep 0.2
  [[ "$PROFILE_TEST_CASE" != test-failure ]] || exit 42
  echo 'PERF navigation.selection rows=10000 iterations=1 build=release'
fi
STUB
cat > "$TMP/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
[[ "$PROFILE_TEST_CASE" != missing-process ]] || exit 1
echo 12345
STUB
cat > "$TMP/bin/xcrun" <<'STUB'
#!/usr/bin/env bash
echo "xcrun $*" >> "$PROFILE_TEST_CALLS"
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
  export PROFILE_TEST_CASE="$1"
  export PROFILE_TEST_CALLS="$TMP/$1.calls"
  : > "$PROFILE_TEST_CALLS"
  local status=0
  PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/profile-navigation-selection.sh" "$TMP/$1 output" \
    > "$TMP/$1.log" 2>&1 || status=$?
  check test "$status" -eq "$2"
}

run_case success 0
check grep -q '^swift build -c release .*--build-tests -Xswiftc -enable-testing$' "$PROFILE_TEST_CALLS"
check grep -q '^swift test -c release --skip-build .*--filter NavigationSelectionProfileTests$' "$PROFILE_TEST_CALLS"
check grep -q '^PERF navigation.selection' "$TMP/success.log"
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

[[ "$failures" -eq 0 ]] || { echo "$failures profiling harness checks failed" >&2; exit 1; }
echo 'test-profile-navigation-selection: all checks passed'
