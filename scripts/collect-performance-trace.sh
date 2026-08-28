#!/usr/bin/env bash
# collect-performance-trace.sh — Export Brev's privacy-safe performance events.

set -euo pipefail

duration="5m"
output=""

usage() {
  cat <<'EOF'
usage: scripts/collect-performance-trace.sh [--last 5m] [--output /path/to/trace.log]

Exports only the Brev Performance log category. Event fields are timings,
counts, booleans, operation paths, and normalized error categories; message
content, account identifiers, and credentials are never emitted by this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)
      duration="${2:?missing duration after --last}"
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

command=(/usr/bin/log show --style compact --last "$duration" --predicate 'subsystem == "eu.brevmail.brev" AND category == "Performance"')
if [[ -n "$output" ]]; then
  "${command[@]}" >"$output"
  echo "wrote performance trace to $output"
else
  "${command[@]}"
fi
