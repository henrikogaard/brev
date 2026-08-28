#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/scripts/local-build-version.sh"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

if [[ ! -x "$HELPER" ]]; then
  echo "expected local build version helper to be executable" >&2
  exit 1
fi

first="$({ BREV_BUILD_NUMBER_FILE="$TMP_FILE" "$HELPER" next; })"
second="$({ BREV_BUILD_NUMBER_FILE="$TMP_FILE" "$HELPER" next; })"
current="$({ BREV_BUILD_NUMBER_FILE="$TMP_FILE" "$HELPER" current; })"

if [[ "$first" != "1" ]]; then
  echo "expected first local build number to be 1, got: $first" >&2
  exit 1
fi

if [[ "$second" != "2" ]]; then
  echo "expected second local build number to be 2, got: $second" >&2
  exit 1
fi

if [[ "$current" != "2" ]]; then
  echo "expected current local build number to remain 2, got: $current" >&2
  exit 1
fi

printf '%s\n' "garbage" >"$TMP_FILE"
reset="$({ BREV_BUILD_NUMBER_FILE="$TMP_FILE" "$HELPER" next; })"
if [[ "$reset" != "1" ]]; then
  echo "expected invalid stored build number to reset to 1, got: $reset" >&2
  exit 1
fi

echo "test-local-build-version.sh: OK"
