#!/usr/bin/env bash
# Validate iOS extension Info.plist metadata required for installation.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

errors=0

fail() {
  echo "ERROR: $1" >&2
  errors=$((errors + 1))
}

ok() {
  echo "OK: $1"
}

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print ${key}" "$plist" 2>/dev/null || true
}

require_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(plist_value "$plist" "$key")"
  if [[ "$actual" == "$expected" ]]; then
    ok "$(basename "$(dirname "$plist")") ${key}=${expected}"
  else
    fail "$(basename "$(dirname "$plist")") ${key}: expected '${expected}', got '${actual:-<missing>}'"
  fi
}

require_non_empty() {
  local plist="$1"
  local key="$2"
  local actual
  actual="$(plist_value "$plist" "$key")"
  if [[ -n "$actual" ]]; then
    ok "$(basename "$(dirname "$plist")") ${key} is set"
  else
    fail "$(basename "$(dirname "$plist")") ${key} is missing or empty"
  fi
}

require_missing_or_non_empty() {
  local plist="$1"
  local key="$2"
  local actual
  actual="$(plist_value "$plist" "$key")"
  if [[ -n "$actual" ]]; then
    ok "$(basename "$(dirname "$plist")") ${key} is non-empty"
  elif /usr/libexec/PlistBuddy -c "Print ${key}" "$plist" >/dev/null 2>&1; then
    fail "$(basename "$(dirname "$plist")") ${key} exists but is empty"
  else
    ok "$(basename "$(dirname "$plist")") ${key} absent"
  fi
}

require_missing() {
  local plist="$1"
  local key="$2"
  if /usr/libexec/PlistBuddy -c "Print ${key}" "$plist" >/dev/null 2>&1; then
    fail "$(basename "$(dirname "$plist")") ${key} should be absent"
  else
    ok "$(basename "$(dirname "$plist")") ${key} absent"
  fi
}

scheme_buildable_count() {
  local scheme="$1"
  local buildable_name="$2"
  /usr/bin/xmllint --xpath "count(/Scheme/BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference[@BuildableName='${buildable_name}'])" "$scheme" 2>/dev/null || echo 0
}

scheme_any_buildable_count() {
  local scheme="$1"
  local buildable_name="$2"
  /usr/bin/xmllint --xpath "count(//BuildableReference[@BuildableName='${buildable_name}'])" "$scheme" 2>/dev/null || echo 0
}

require_scheme_builds_extension() {
  local scheme="$1"
  local extension_buildable="$2"
  local extension_count
  extension_count="$(scheme_buildable_count "$scheme" "$extension_buildable")"

  if [[ "$extension_count" == "1" ]]; then
    ok "$(basename "$scheme") builds ${extension_buildable}"
  else
    fail "$(basename "$scheme") entries: expected ${extension_buildable}=1; got ${extension_buildable}=${extension_count}"
  fi
}

share_plist="apps/iOS/BrevShareExtension/Info.plist"
notification_plist="apps/iOS/BrevNotificationContent/Info.plist"
share_scheme="apps/iOS/BrevIOS.xcodeproj/xcshareddata/xcschemes/BrevShareExtension.xcscheme"
notification_scheme="apps/iOS/BrevIOS.xcodeproj/xcshareddata/xcschemes/BrevNotificationContent.xcscheme"

[[ -f "$share_plist" ]] || fail "missing $share_plist"
[[ -f "$notification_plist" ]] || fail "missing $notification_plist"
[[ -f "$share_scheme" ]] || fail "missing $share_scheme"
[[ -f "$notification_scheme" ]] || fail "missing $notification_scheme"

if [[ -f "$share_plist" ]]; then
  plutil -lint "$share_plist" >/dev/null || fail "$share_plist is not valid plist"
  require_value "$share_plist" ":NSExtension:NSExtensionPointIdentifier" "com.apple.share-services"
  require_non_empty "$share_plist" ":NSExtension:NSExtensionPrincipalClass"
  require_missing_or_non_empty "$share_plist" ":NSExtension:NSExtensionMainStoryboard"
  require_value "$share_plist" ":NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsText" "true"
  require_value "$share_plist" ":NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsWebURLWithMaxCount" "10"
  require_value "$share_plist" ":NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsFileWithMaxCount" "10"
  require_value "$share_plist" ":NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsImageWithMaxCount" "10"
  require_value "$share_plist" ":NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsMovieWithMaxCount" "3"
fi

if [[ -f "$notification_plist" ]]; then
  plutil -lint "$notification_plist" >/dev/null || fail "$notification_plist is not valid plist"
  require_value "$notification_plist" ":NSExtension:NSExtensionPointIdentifier" "com.apple.usernotifications.content-extension"
  require_non_empty "$notification_plist" ":NSExtension:NSExtensionPrincipalClass"
  require_value "$notification_plist" ":NSExtension:NSExtensionAttributes:UNNotificationExtensionCategory" "brev.newMail"
fi

if [[ -f "$share_scheme" ]]; then
  require_scheme_builds_extension "$share_scheme" "BrevShareExtension.appex"
fi

if [[ -f "$notification_scheme" ]]; then
  require_scheme_builds_extension "$notification_scheme" "BrevNotificationContent.appex"
fi

if [[ $errors -ne 0 ]]; then
  echo "test-ios-extension-plists.sh: ${errors} failure(s)" >&2
  exit 1
fi

echo "test-ios-extension-plists.sh: OK"
