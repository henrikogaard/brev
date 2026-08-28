#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_NUMBER_FILE="${BREV_BUILD_NUMBER_FILE:-$ROOT/.codex/build/local-build-number}"

usage() {
  cat <<'EOF'
usage: scripts/local-build-version.sh [current|next]

Manage Brev's local build counter. The counter is stored outside the
tracked tree so repeated local builds can stamp unique bundle versions
without dirtying git state.
EOF
}

read_build_number() {
  local raw="0"
  if [[ -f "$BUILD_NUMBER_FILE" ]]; then
    raw="$(tr -d '[:space:]' <"$BUILD_NUMBER_FILE")"
  fi

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf '%s' "$raw"
  else
    printf '0'
  fi
}

current_build_number() {
  read_build_number
  printf '\n'
}

next_build_number() {
  local current next
  current="$(read_build_number)"
  next="$((current + 1))"

  mkdir -p "$(dirname "$BUILD_NUMBER_FILE")"
  printf '%s\n' "$next" >"$BUILD_NUMBER_FILE"
  printf '%s\n' "$next"
}

case "${1:-next}" in
  current)
    current_build_number
    ;;
  next)
    next_build_number
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "error: unknown argument: ${1:-}" >&2
    usage >&2
    exit 2
    ;;
esac
