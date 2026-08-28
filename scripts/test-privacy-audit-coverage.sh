#!/usr/bin/env bash
# Verifies the privacy audit covers BYOK/local AI documentation guarantees.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$("$ROOT/scripts/privacy-audit.sh")"
AUDIT_SCRIPT="$ROOT/scripts/privacy-audit.sh"

require_output() {
  local needle="$1"
  if ! grep -Fq "$needle" <<<"$OUTPUT"; then
    echo "error: expected privacy audit output to include: $needle" >&2
    echo "$OUTPUT" >&2
    exit 1
  fi
}

require_output "PRIVACY.md documents BYOK/local AI"
require_output "PRIVACY.md documents local-only mail notifications"
require_output "PRIVACY.md documents remote HTML assets"
require_output "PRIVACY.md documents current avatar cache storage"
require_output "PRIVACY.md documents BYOK API key Keychain storage"
require_output "No stale BrevTesting no-network enforcement claim"
require_output "No inherited app markers in shipped code"
require_output "Generated/built artifacts contain no telemetry SDKs"
require_output "ADR-0006 lists BYOK/local AI as off by default"
require_output "PRIVACY.md says Brev does not register mail APNS tokens"
require_output "ADR-0006 lists remote HTML assets as off by default"
require_output "Desktop smoke covers local AI without network probing"
require_output "Notification settings keep local notifications off by default"

if ! rg -q 'UIColor\\\.' "$AUDIT_SCRIPT"; then
  echo "error: expected privacy audit literal-color guard to cover UIColor literals" >&2
  exit 1
fi

if rg -q '#\\[0-9A-Fa-f\\]' "$AUDIT_SCRIPT"; then
  echo "error: privacy audit should not flag arbitrary hex strings in comments or CSS payloads" >&2
  exit 1
fi

if rg -q 'MessagePrintExportRenderer\.print\(' "$ROOT/packages/BrevMail/Sources"; then
  echo "error: print/export renderer should avoid a .print(...) API that trips logging audits" >&2
  exit 1
fi

TELEMETRY_OUTPUT="$("$ROOT/scripts/test-telemetry-artifacts.sh")"
if ! grep -Fq "No telemetry references in generated projects/workspace" <<<"$TELEMETRY_OUTPUT"; then
  echo "error: expected telemetry-artifact scan to cover generated projects/workspace" >&2
  echo "$TELEMETRY_OUTPUT" >&2
  exit 1
fi

if ! grep -Fq "No telemetry frameworks in built Brev.app" <<<"$TELEMETRY_OUTPUT"; then
  echo "error: expected telemetry-artifact scan to cover the macOS app bundle" >&2
  echo "$TELEMETRY_OUTPUT" >&2
  exit 1
fi

echo "test-privacy-audit-coverage.sh: OK"
