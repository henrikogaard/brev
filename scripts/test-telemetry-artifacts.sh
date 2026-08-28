#!/usr/bin/env bash
# Guards generated and built app artifacts against provider telemetry SDKs.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0
telemetry_pattern='Sentry|sentry-cocoa|Matomo|matomo-sdk-ios'

check_no_matches() {
  local label="$1"
  shift

  echo "==> ${label}"

  local paths=()
  local path
  for path in "$@"; do
    if [[ -e "$path" ]]; then
      paths+=("$path")
    fi
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    echo "    skipped (no matching paths)"
    return
  fi

  set +e
  local output
  output="$(rg -n "$telemetry_pattern" "${paths[@]}" 2>&1)"
  local status=$?
  set -e

  if [[ $status -eq 1 ]]; then
    echo "    OK"
    return
  fi

  if [[ -n "$output" ]]; then
    echo "$output"
  fi
  failures=$((failures + 1))
}

latest_brev_ios_app() {
  local derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
  if [[ ! -d "$derived_data" ]]; then
    return
  fi

  find "$derived_data" \
    -path '*/Build/Products/*/BrevIOS.app' \
    -type d \
    -print0 |
    xargs -0 stat -f '%m %N' 2>/dev/null |
    sort -nr |
    head -n 1 |
    cut -d' ' -f2-
}

latest_brev_macos_app() {
  local derived_data="${HOME}/Library/Developer/Xcode/DerivedData"
  if [[ ! -d "$derived_data" ]]; then
    return
  fi

  find "$derived_data" \
    -path '*/Build/Products/*/Brev.app' \
    -type d \
    -print0 |
    xargs -0 stat -f '%m %N' 2>/dev/null |
    sort -nr |
    head -n 1 |
    cut -d' ' -f2-
}

check_no_matches \
  "No telemetry packages in resolved Tuist graph" \
  Tuist/Package.resolved

check_no_matches \
  "No telemetry references in generated projects/workspace" \
  apps/macOS/BrevMacOS.xcodeproj/project.pbxproj \
  apps/iOS/BrevIOS.xcodeproj/project.pbxproj \
  Brev.xcworkspace

ios_app_path="${BREV_IOS_APP_PATH:-}"
if [[ -z "$ios_app_path" ]]; then
  ios_app_path="$(latest_brev_ios_app || true)"
fi

echo "==> No telemetry frameworks in built BrevIOS.app"
if [[ -z "$ios_app_path" ]]; then
  echo "    skipped (set BREV_IOS_APP_PATH after building to inspect a specific app bundle)"
elif [[ ! -d "$ios_app_path" ]]; then
  echo "error: BREV_IOS_APP_PATH does not exist or is not a directory: $ios_app_path" >&2
  failures=$((failures + 1))
else
  set +e
  bundle_matches="$(
    find "$ios_app_path" \( \
      -iname '*Sentry*' -o \
      -iname '*Matomo*' \
    \) -print
  )"
  set -e

  if [[ -z "$bundle_matches" ]]; then
    echo "    OK (${ios_app_path})"
  else
    echo "$bundle_matches"
    failures=$((failures + 1))
  fi
fi

macos_app_path="${BREV_MACOS_APP_PATH:-}"
if [[ -z "$macos_app_path" ]]; then
  macos_app_path="$(latest_brev_macos_app || true)"
fi

echo "==> No telemetry frameworks in built Brev.app"
if [[ -z "$macos_app_path" ]]; then
  echo "    skipped (set BREV_MACOS_APP_PATH after building to inspect a specific app bundle)"
elif [[ ! -d "$macos_app_path" ]]; then
  echo "error: BREV_MACOS_APP_PATH does not exist or is not a directory: $macos_app_path" >&2
  failures=$((failures + 1))
else
  set +e
  bundle_matches="$(
    find "$macos_app_path" \( \
      -iname '*Sentry*' -o \
      -iname '*Matomo*' \
    \) -print
  )"
  set -e

  if [[ -z "$bundle_matches" ]]; then
    echo "    OK (${macos_app_path})"
  else
    echo "$bundle_matches"
    failures=$((failures + 1))
  fi
fi

if [[ $failures -ne 0 ]]; then
  echo "test-telemetry-artifacts.sh: ${failures} check(s) failed" >&2
  exit 1
fi

echo "test-telemetry-artifacts.sh: OK"
