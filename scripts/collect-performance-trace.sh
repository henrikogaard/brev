#!/usr/bin/env bash
# collect-performance-trace.sh — Export Brev's privacy-safe performance events.

set -euo pipefail

output=""
pid=""
start=""

usage() {
  cat <<'EOF'
usage: scripts/collect-performance-trace.sh --pid PID --start 'YYYY-MM-DD HH:MM:SS' [--output /path/to/trace.log]

Capture the timestamp immediately before launching the test app, then supply
that app's PID (not the shell, test runner, or WebKit helper). Both are required
to isolate one run. For a simulator, run log show inside that simulator instead.

Exports only the Brev Performance log category for that PID/run. Event fields are timings,
counts, booleans, operation paths, and normalized error categories; message
content, account identifiers, and credentials are never emitted by this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid)
      pid="${2:?missing PID after --pid}"
      shift 2
      ;;
    --start)
      start="${2:?missing timestamp after --start}"
      shift 2
      ;;
    --output)
      output="${2:?missing path after --output}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "collect-performance-trace.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]] || [[ ! "$start" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
  echo "collect-performance-trace.sh: a positive --pid and --start 'YYYY-MM-DD HH:MM:SS' are required" >&2
  exit 2
fi

# --info is required: the Performance events are emitted at info level, which
# `log show` filters out by default, leaving an empty export.
command=(/usr/bin/log show --style compact --info --start "$start"
  --predicate "subsystem == \"eu.brevmail.brev\" AND category == \"Performance\" AND processIdentifier == $pid")
export_trace() {
  printf '# brev-performance pid=%s start=%s\n' "$pid" "$start"
  "${command[@]}"
}
if [[ -n "$output" ]]; then
  export_trace >"$output"
  echo "wrote performance trace to $output"
else
  export_trace
fi
