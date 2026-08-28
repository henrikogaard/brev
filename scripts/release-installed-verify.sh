#!/usr/bin/env bash
# release-installed-verify.sh — Automated checks for an installed Brev app bundle.
#
# Usage:
#   scripts/release-installed-verify.sh [--app-path <path>] [--dmg-path <path>] [--skip-gatekeeper]
#
# Defaults:
#   app path: /Applications/Brev.app or /Applications/BrevMail.app (first existing)
#   dmg path: build/release/BrevMail.dmg (optional)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_PATH=""
DMG_PATH="$ROOT/build/release/BrevMail.dmg"
SKIP_GATEKEEPER=0

usage() {
  cat <<'EOF'
usage: scripts/release-installed-verify.sh [--app-path <path>] [--dmg-path <path>] [--skip-gatekeeper]

Examples:
  scripts/release-installed-verify.sh
  scripts/release-installed-verify.sh --app-path /Applications/BrevMail.app
  scripts/release-installed-verify.sh --app-path /tmp/Brev.app --skip-gatekeeper
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --dmg-path)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --skip-gatekeeper)
      SKIP_GATEKEEPER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "release-installed-verify.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APP_PATH" ]]; then
  if [[ -d /Applications/Brev.app ]]; then
    APP_PATH="/Applications/Brev.app"
  elif [[ -d /Applications/BrevMail.app ]]; then
    APP_PATH="/Applications/BrevMail.app"
  fi
fi

if [[ -z "$APP_PATH" ]]; then
  echo "release-installed-verify.sh: no installed app found at /Applications/Brev.app or /Applications/BrevMail.app" >&2
  echo "pass --app-path to target a specific bundle" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "release-installed-verify.sh: app path does not exist: $APP_PATH" >&2
  exit 1
fi

info_plist="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  echo "release-installed-verify.sh: missing Info.plist at $info_plist" >&2
  exit 1
fi

echo "==> app bundle"
echo "    APP_PATH=$APP_PATH"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || true)"

if [[ "$bundle_id" != "eu.brevmail.brev" ]]; then
  echo "release-installed-verify.sh: unexpected bundle id: ${bundle_id:-<missing>}" >&2
  exit 1
fi

echo "    Bundle ID: $bundle_id"
echo "    Version:   ${short_version:-<missing>} (${build_version:-<missing>})"

echo "==> code-signature verification"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "    OK"

echo "==> Retired remote-push entitlements"
if ! entitlements="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)"; then
  echo "release-installed-verify.sh: could not inspect embedded entitlements" >&2
  exit 1
fi
if printf '%s\n' "$entitlements" | grep -Eq '<key>(com.apple.developer.)?aps-environment</key>'; then
  echo "release-installed-verify.sh: retired remote-push entitlement is still embedded" >&2
  exit 1
fi
echo "    OK"

echo "==> Google OAuth loopback entitlement"
if ! printf '%s\n' "$entitlements" | grep -A1 '<key>com.apple.security.network.server</key>' | grep -q '<true/>'; then
  echo "release-installed-verify.sh: missing com.apple.security.network.server entitlement" >&2
  exit 1
fi
echo "    OK"

if [[ $SKIP_GATEKEEPER -eq 0 ]]; then
  echo "==> gatekeeper assessment (app)"
  spctl -a -t exec -v "$APP_PATH"
  echo "    OK"

  if [[ -f "$DMG_PATH" ]]; then
    echo "==> gatekeeper assessment (dmg)"
    spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
    echo "    OK"
  else
    echo "==> gatekeeper assessment (dmg)"
    echo "    SKIP: dmg not found at $DMG_PATH"
  fi
else
  echo "==> gatekeeper assessment"
  echo "    SKIP: --skip-gatekeeper"
fi

echo "release-installed-verify.sh: OK"
