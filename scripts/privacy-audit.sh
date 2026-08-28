#!/usr/bin/env bash
# Static privacy and architecture checks for the desktop beta gate.
#
# This complements SwiftLint with a plain shell command that can be
# pasted into release notes, run during smoke checks, and attached to
# the privacy decision without requiring OAuth credentials.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0

check_no_matches() {
  local label="$1"
  local pattern="$2"
  shift 2

  echo "==> ${label}"
  set +e
  local output
  output="$(rg -n "$pattern" "$@" 2>&1)"
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

check_has_match() {
  local label="$1"
  local pattern="$2"
  local path="$3"

  echo "==> ${label}"
  if rg -q "$pattern" "$path"; then
    echo "    OK"
  else
    echo "    Missing expected pattern in ${path}: ${pattern}" >&2
    failures=$((failures + 1))
  fi
}

check_no_matches \
  "No telemetry library imports" \
  '^\s*import\s+(Matomo|Sentry|FirebaseAnalytics|Mixpanel|Amplitude)\b' \
  apps packages --glob '*.swift'

check_no_matches \
  "No Realm imports in view-owned packages" \
  '^\s*import\s+RealmSwift\b' \
  apps \
  packages/BrevAI \
  packages/BrevAvatars \
  packages/BrevCalendar \
  packages/BrevDesign \
  packages/BrevMail \
  packages/BrevThemes \
  --glob '*.swift'

check_no_matches \
  "No literal colors in view-owned code" \
  'Color\.(black|blue|brown|cyan|gray|green|indigo|mint|orange|pink|purple|red|teal|white|yellow)|Color\(hex:|UIColor\.(black|blue|brown|cyan|gray|green|magenta|orange|purple|red|white|yellow)' \
  apps \
  packages/BrevDesign/Sources \
  packages/BrevMail/Sources \
  packages/BrevSettings/Sources \
  --glob '*.swift'

check_no_matches \
  "No obvious secret or message-content logging" \
  '(print|Logger|os_log).*?(accessToken|refreshToken|authorizationCode|authorization|messageBody|rawBody|attachment|token)' \
  apps \
  packages/BrevAI \
  packages/BrevBackend \
  packages/BrevMail \
  --glob '*.swift'

check_no_matches \
  "No stale BrevTesting no-network enforcement claim" \
  'A test in `BrevTesting` package runs' \
  ADRs/0005-enforcement.md \
  ADRs/0006-telemetry-and-privacy.md

echo "==> No inherited app markers in shipped code"
if scripts/test-public-source-markers.sh >/dev/null; then
  echo "    OK"
else
  scripts/test-public-source-markers.sh
  failures=$((failures + 1))
fi

echo "==> Generated/built artifacts contain no telemetry SDKs"
if scripts/test-telemetry-artifacts.sh >/dev/null; then
  echo "    OK"
else
  scripts/test-telemetry-artifacts.sh
  failures=$((failures + 1))
fi

check_has_match \
  "PRIVACY.md documents Gravatar" \
  'Gravatar' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents BIMI" \
  'BIMI' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents domain favicons" \
  'Domain favicons' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents remote HTML assets" \
  '### Remote HTML assets' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents current avatar cache storage" \
  'Avatar cache:\*\* in-memory cache' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents AI Writer" \
  'AI Writer' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents BYOK/local AI" \
  'BYOK / custom endpoints \(OpenAI-compatible and Ollama/local\)' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents local-only mail notifications" \
  '### Local mail notifications' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md says Brev does not register mail APNS tokens" \
  'does not register an APNS device token for mail delivery' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents BYOK API key Keychain storage" \
  'BYOK API keys are stored in the OS Keychain' \
  PRIVACY.md

check_has_match \
  "PRIVACY.md documents provider-dependent AI privacy" \
  'Brev cannot enforce the retention, training, or logging policy' \
  PRIVACY.md

check_has_match \
  "ADR-0006 lists Gravatar as off by default" \
  'Gravatar avatar lookup .* Background sync, if enabled .* \*\*Off\*\*' \
  ADRs/0006-telemetry-and-privacy.md

check_has_match \
  "ADR-0006 lists AI Writer as off by default" \
  'AI Writer via selected provider .* On AI Writer use, after consent .* \*\*Off\*\*' \
  ADRs/0006-telemetry-and-privacy.md

check_has_match \
  "ADR-0006 lists BYOK/local AI as off by default" \
  'BYOK/local AI endpoint \(v2\) .* On AI Writer use, once configured .* \*\*Off\*\*' \
  ADRs/0006-telemetry-and-privacy.md

check_has_match \
  "ADR-0006 lists remote HTML assets as off by default" \
  'Remote HTML assets in messages .* \| \*\*Off\*\*' \
  ADRs/0006-telemetry-and-privacy.md

check_has_match \
  "Desktop smoke covers local AI without network probing" \
  'Local/Ollama setup does not probe localhost or make public-internet' \
  docs/qa/desktop-smoke.md

check_has_match \
  "Avatar preferences keep Gravatar off by default" \
  'useGravatar: Bool = false' \
  packages/BrevAvatars/Sources/BrevAvatars/AvatarPreferences.swift

check_has_match \
  "Avatar preferences keep BIMI off by default" \
  'useBIMI: Bool = false' \
  packages/BrevAvatars/Sources/BrevAvatars/AvatarPreferences.swift

check_has_match \
  "Avatar preferences keep favicons off by default" \
  'useFavicon: Bool = false' \
  packages/BrevAvatars/Sources/BrevAvatars/AvatarPreferences.swift

check_has_match \
  "Settings keeps remote HTML assets blocked by default" \
  'allowRemoteContent: false,' \
  packages/BrevSettings/Sources/BrevSettings/MailboxViewSettings.swift

check_has_match \
  "Settings keeps AI Writer off by default" \
  'isEnabled: false,' \
  packages/BrevAI/Sources/BrevAI/AIWriterSettings.swift

check_has_match \
  "Notification settings keep local notifications off by default" \
  'notificationsEnabled: false' \
  packages/BrevSettings/Sources/BrevSettings/NotificationSettings.swift

check_has_match \
  "AI Writer storage key remains stable" \
  'public static let isEnabled = "ai\.enabled"' \
  packages/BrevAI/Sources/BrevAI/AIWriterSettings.swift

if [[ $failures -ne 0 ]]; then
  echo "privacy-audit.sh: ${failures} check(s) failed" >&2
  exit 1
fi

echo "privacy-audit.sh: OK"
