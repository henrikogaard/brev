#!/usr/bin/env bash
# Validate the direct-download Developer ID signing and export policy.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

plist="scripts/export-options-developer-id.plist"
archive_script="scripts/release-archive.sh"
dmg_script="scripts/release-dmg.sh"

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

require_value method developer-id
require_value destination export
require_value teamID 45AD7E7G5G
require_value signingStyle manual
require_value signingCertificate "Developer ID Application"
require_value 'provisioningProfiles.eu\.brevmail\.brev' "Brev Developer ID Distribution"

nightly_plist="scripts/export-options-developer-id-nightly.plist"
if [[ ! -f "$nightly_plist" ]]; then
  echo "ERROR: missing $nightly_plist" >&2
  exit 1
fi
plutil -lint "$nightly_plist" >/dev/null

require_nightly_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plutil -extract "$key" raw -o - "$nightly_plist" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: nightly ${key}: expected '${expected}', got '${actual:-<missing>}'" >&2
    exit 1
  fi
}

require_nightly_value method developer-id
require_nightly_value destination export
require_nightly_value teamID 45AD7E7G5G
require_nightly_value signingStyle manual
require_nightly_value signingCertificate "Developer ID Application"
require_nightly_value 'provisioningProfiles.eu\.brevmail\.brev\.nightly' "Brev Nightly Developer ID Distribution"

if ! grep -q 'BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER_NIGHTLY' "$archive_script" ||
    ! grep -q 'Brev Nightly Developer ID Distribution' "$archive_script"; then
  echo "ERROR: release archive must support the nightly provisioning profile specifier" >&2
  exit 1
fi

if ! grep -q 'BREV_APP_BUNDLE_ID=eu.brevmail.brev.nightly' "$archive_script" ||
    ! grep -q 'BREV_RELEASE_RING' "$archive_script"; then
  echo "ERROR: release archive must inject the nightly ring overrides" >&2
  exit 1
fi

if ! grep -q 'export-options-developer-id-nightly.plist' "$dmg_script" ||
    ! grep -q 'Brev-Nightly-' "$dmg_script"; then
  echo "ERROR: release packaging must select the nightly export options and DMG name" >&2
  exit 1
fi

if ! grep -q 'ENABLE_HARDENED_RUNTIME=YES' "$archive_script"; then
  echo "ERROR: release archive must enable hardened runtime for notarization" >&2
  exit 1
fi

if ! grep -q 'BREV_SPARKLE_PUBLIC_ED_KEY' "$archive_script" ||
    ! grep -q '44-character base64 Sparkle EdDSA public key' "$archive_script"; then
  echo "ERROR: release archive must require a real Sparkle public key" >&2
  exit 1
fi

if ! grep -Fq '[[ -z "${BREV_BUILD_NUMBER:-}" ]]' "$archive_script" ||
    ! grep -Fq 'CURRENT_PROJECT_VERSION="$BREV_BUILD_NUMBER"' "$archive_script"; then
  echo "ERROR: release archive must require and pass an explicit monotonic build number" >&2
  exit 1
fi

release_env=(
  env
  BREV_SIGNING_IDENTITY="Developer ID Application: Test (AAAAAAAAAA)"
  BREV_TEAM_ID="AAAAAAAAAA"
  BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER="Test Developer ID Profile"
  BREV_SPARKLE_PUBLIC_ED_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID="test.apps.googleusercontent.com"
  BREV_GOOGLE_OAUTH_CLIENT_SECRET="test-client-credential"
)

if "${release_env[@]}" BREV_BUILD_NUMBER=0 "$archive_script" --dry-run >/dev/null 2>&1; then
  echo "ERROR: release archive accepted a non-positive build number" >&2
  exit 1
fi

if ! "${release_env[@]}" BREV_BUILD_NUMBER=5 "$archive_script" --dry-run >/dev/null; then
  echo "ERROR: release archive rejected a valid explicit build number" >&2
  exit 1
fi

if ! grep -Fq 'codesign --force --sign "$BREV_SIGNING_IDENTITY" --timestamp "$DMG_PATH"' "$dmg_script"; then
  echo "ERROR: release packaging must sign the DMG before notarization" >&2
  exit 1
fi

if ! grep -Fq 'rm -f "$DMG_PATH" "$DMG_PATH.sha256"' "$dmg_script"; then
  echo "ERROR: release packaging must remove stale DMG/checksum outputs before rebuilding" >&2
  exit 1
fi

if ! grep -Fq 'DMG asset: \`$ASSET_NAME\`' scripts/release-draft-fill.sh ||
    ! grep -Fq 'SHA-256: \`$CHECKSUM_DIGEST\`' scripts/release-draft-fill.sh; then
  echo "ERROR: release draft fill must cross-check asset naming and checksum readback" >&2
  exit 1
fi

echo "test-developer-id-release-config.sh: OK"

exit=0
