#!/usr/bin/env bash
# Verifies the static compact-layout smoke check covers the key desktop surfaces.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$("$ROOT/scripts/desktop-compact-layout-check.sh")"

require_output() {
  local needle="$1"
  if ! grep -Fq "$needle" <<<"$OUTPUT"; then
    echo "error: expected compact layout check output to include: $needle" >&2
    echo "$OUTPUT" >&2
    exit 1
  fi
}

require_output "compact window source contract"
require_output "main window titlebar contract"
require_output "mail root pane contract"
require_output "compose compact contract"
require_output "settings compact contract"

if ! rg -q "windowserver_brev_window_info" "$ROOT/scripts/desktop-compact-layout-check.sh"; then
  echo "error: expected compact layout check to include a WindowServer fallback for AX-limited environments" >&2
  exit 1
fi

if ! rg -q "runtime_app_name" "$ROOT/scripts/desktop-compact-layout-check.sh" ||
    ! rg -q 'expected_bundle="Brev Test \(\$\{test_date\}\)\.app"' "$ROOT/scripts/desktop-compact-layout-check.sh"; then
  echo "error: expected runtime compact check to discover the dated Brev Test app bundle" >&2
  exit 1
fi

if ! rg -q "runtime partial OK" "$ROOT/scripts/desktop-compact-layout-check.sh"; then
  echo "error: expected compact layout check to distinguish partial runtime evidence from layout failures" >&2
  exit 1
fi

if ! rg -q "warning: could not capture WindowServer screenshot" "$ROOT/scripts/desktop-compact-layout-check.sh"; then
  echo "error: expected compact layout check to keep WindowServer screenshot failures non-fatal" >&2
  exit 1
fi

echo "test-desktop-compact-layout-check.sh: OK"
