#!/usr/bin/env bash
# Fails when shipped Brev code claims an inherited application identity.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGETS=(
  apps
  packages/BrevAI
  packages/BrevAvatars
  packages/BrevBackend
  packages/BrevCalendar
  packages/BrevCrypto
  packages/BrevDesign
  packages/BrevMail
  packages/BrevPlugins
  packages/BrevSettings
  packages/BrevSyncEngine
  packages/BrevThemes
)

PATTERNS=(
  'forked from'
  'based on the upstream app'
  'Portions of this codebase'
)

for pattern in "${PATTERNS[@]}"; do
  set +e
  output="$(rg -n "$pattern" "${TARGETS[@]}" 2>&1)"
  status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    echo "$output"
    echo "error: found inherited app marker: $pattern" >&2
    exit 1
  fi

  if [[ $status -gt 1 ]]; then
    echo "$output" >&2
    echo "error: failed to scan for inherited app marker: $pattern" >&2
    exit 1
  fi
done

echo "test-public-source-markers.sh: OK"
