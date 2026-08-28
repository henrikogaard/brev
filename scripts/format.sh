#!/usr/bin/env bash
# scripts/format.sh — applies swiftformat to the Brev tree.
#
# This is the "writer" counterpart to scripts/lint.sh. CI runs lint.sh only;
# this script is a developer convenience that auto-fixes formatting.
# Per ADR-0005.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

eval "$(mise activate bash 2>/dev/null || mise activate zsh)" || true

echo "==> swiftformat ."
mise exec -- swiftformat .

echo "format.sh: OK"
