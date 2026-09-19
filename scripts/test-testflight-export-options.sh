#!/usr/bin/env bash
# Validate the internal and external TestFlight export policies.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

internal_plist="scripts/export-options-testflight-internal.plist"
external_plist="scripts/export-options-testflight-external.plist"
info_plist="apps/iOS/Resources/Info.plist"

require_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: ${key}: expected '${expected}', got '${actual:-<missing>}'" >&2
    exit 1
  fi
}

require_missing() {
  local plist="$1"
  local key="$2"
  if plutil -extract "$key" raw -o - "$plist" >/dev/null 2>&1; then
    echo "ERROR: ${key}: expected to be absent from $plist" >&2
    exit 1
  fi
}

for plist in "$internal_plist" "$external_plist"; do
  if [[ ! -f "$plist" ]]; then
    echo "ERROR: missing $plist" >&2
    exit 1
  fi

  plutil -lint "$plist" >/dev/null
  require_value "$plist" method app-store-connect
  require_value "$plist" destination upload
  require_value "$plist" teamID 45AD7E7G5G
  require_value "$plist" signingStyle automatic
  require_value "$plist" manageAppVersionAndBuildNumber false
done

require_value "$internal_plist" testFlightInternalTestingOnly true
require_missing "$external_plist" testFlightInternalTestingOnly

uses_non_exempt_encryption="$(
  plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$info_plist" 2>/dev/null || true
)"
if [[ "$uses_non_exempt_encryption" != "false" ]]; then
  echo "ERROR: ITSAppUsesNonExemptEncryption: expected 'false', got '${uses_non_exempt_encryption:-<missing>}'" >&2
  exit 1
fi

echo "test-testflight-export-options.sh: OK"
