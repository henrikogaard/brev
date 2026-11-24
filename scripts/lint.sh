#!/usr/bin/env bash
# scripts/lint.sh — Brev lint entry point.
#
# Runs:
#   1. swiftformat --lint  (fails if any file would be reformatted)
#   2. swiftlint --strict  (treats warnings as errors)
#   3. SwiftLint coverage self-test
#
# Per docs/design/platform-release-and-qa.md. Invoke via mise so the pinned versions are used.

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

echo "lint.sh: OK"
