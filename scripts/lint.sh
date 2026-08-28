#!/usr/bin/env bash
# scripts/lint.sh — Brev lint entry point.
#
# Runs:
#   1. swiftformat --lint  (fails if any file would be reformatted)
#   2. swiftlint --strict  (treats warnings as errors)
#   3. scripts/check-adr-required.sh — gates protected-path changes on a
#      matching ADR update; only runs in a staged-files context (pre-commit
#      or CI). Skip with BREV_SKIP_ADR_CHECK=1.
#
# Per ADR-0005. Invoke via mise so the pinned versions are used.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v mise >/dev/null 2>&1; then
  echo "lint.sh: mise not found on PATH — install via https://mise.jdx.dev/" >&2
  exit 127
fi

eval "$(mise activate bash 2>/dev/null || mise activate zsh)" || true

echo "==> swiftformat --lint"
mise exec -- swiftformat --lint .

echo "==> swiftlint --strict"
mise exec -- swiftlint --strict --quiet

echo "==> SwiftLint coverage self-test"
scripts/test-swiftlint-coverage.sh

if [[ "${BREV_SKIP_ADR_CHECK:-0}" != "1" ]]; then
  if [[ -x "$ROOT/scripts/check-adr-required.sh" ]]; then
    echo "==> check-adr-required"
    "$ROOT/scripts/check-adr-required.sh"
  fi
fi

echo "lint.sh: OK"
