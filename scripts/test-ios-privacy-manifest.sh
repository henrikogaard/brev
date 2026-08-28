#!/usr/bin/env bash
# Validate the iOS app privacy manifest required for App Store uploads.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

manifest="apps/iOS/Resources/PrivacyInfo.xcprivacy"
project="apps/iOS/Project.swift"

if [[ ! -f "$manifest" ]]; then
  echo "ERROR: missing $manifest" >&2
  exit 1
fi

if git check-ignore -q "$manifest"; then
  echo "ERROR: $manifest is ignored and cannot be committed" >&2
  exit 1
fi

plutil -lint "$manifest" >/dev/null

tracking="$(plutil -extract NSPrivacyTracking raw -o - "$manifest" 2>/dev/null || true)"
if [[ "$tracking" != "false" ]]; then
  echo "ERROR: expected NSPrivacyTracking=false, got '${tracking:-<missing>}'" >&2
  exit 1
fi

collected_data="$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$manifest" 2>/dev/null || true)"
if [[ "$collected_data" != "[]" ]]; then
  echo "ERROR: expected an empty NSPrivacyCollectedDataTypes array" >&2
  exit 1
fi

accessed_apis="$(plutil -extract NSPrivacyAccessedAPITypes json -o - "$manifest" 2>/dev/null || true)"
if ! grep -q 'NSPrivacyAccessedAPICategoryFileTimestamp' <<<"$accessed_apis"; then
  echo "ERROR: missing file-timestamp required-reason API declaration" >&2
  exit 1
fi
if ! grep -q 'C617.1' <<<"$accessed_apis"; then
  echo "ERROR: missing C617.1 reason for app-container file metadata" >&2
  exit 1
fi

if ! grep -q '"Resources/PrivacyInfo.xcprivacy"' "$project"; then
  echo "ERROR: $project does not bundle the iOS privacy manifest" >&2
  exit 1
fi

echo "test-ios-privacy-manifest.sh: OK"
