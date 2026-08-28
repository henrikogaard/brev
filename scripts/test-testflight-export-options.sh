#!/usr/bin/env bash
# Validate the internal-only TestFlight export policy.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

plist="scripts/export-options-testflight-internal.plist"
info_plist="apps/iOS/Resources/Info.plist"

if [[ ! -f "$plist" ]]; then
  echo "ERROR: missing $plist" >&2
  exit 1
fi

plutil -lint "$plist" >/dev/null

require_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: ${key}: expected '${expected}', got '${actual:-<missing>}'" >&2
    exit 1
  fi
}

require_value method app-store-connect
require_value destination upload
require_value teamID 45AD7E7G5G
require_value signingStyle automatic
require_value manageAppVersionAndBuildNumber false
require_value testFlightInternalTestingOnly true

uses_non_exempt_encryption="$(
  plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$info_plist" 2>/dev/null || true
)"
if [[ "$uses_non_exempt_encryption" != "false" ]]; then
  echo "ERROR: ITSAppUsesNonExemptEncryption: expected 'false', got '${uses_non_exempt_encryption:-<missing>}'" >&2
  exit 1
fi

echo "test-testflight-export-options.sh: OK"
