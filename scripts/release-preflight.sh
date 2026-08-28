#!/usr/bin/env bash
# Checks whether this machine has the local tools and secrets needed
# to follow docs/release.md. Missing private release material is
# reported as a warning unless --strict is passed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash 2>/dev/null || mise activate zsh)" || true
fi

ENV_FILE="$ROOT/.env.local"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

strict=0
live=0
for arg in "$@"; do
  case "$arg" in
    --strict)
      strict=1
      ;;
    --live)
      live=1
      ;;
    -h|--help)
      echo "usage: scripts/release-preflight.sh [--strict] [--live]"
      exit 0
      ;;
    *)
      echo "release-preflight.sh: unknown argument: ${arg}" >&2
      exit 2
      ;;
  esac
done

errors=0
warnings=0

ok() {
  echo "    OK: $1"
}

error() {
  echo " ERROR: $1" >&2
  errors=$((errors + 1))
}

warn() {
  echo "  WARN: $1" >&2
  warnings=$((warnings + 1))
}

require_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "${command_name} available"
  else
    error "${command_name} not found on PATH"
  fi
}

warn_missing_env() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    ok "${name} set"
  else
    warn "${name} is not set"
  fi
}

read_env_alias() {
  local primary="$1"
  local secondary="$2"

  if [[ -n "${!primary:-}" ]]; then
    printf '%s' "${!primary}"
    return
  fi
  if [[ -n "${!secondary:-}" ]]; then
    printf '%s' "${!secondary}"
    return
  fi
  printf ''
}

echo "==> required commands"
require_command tuist
require_command xcodebuild
require_command xcrun
require_command hdiutil
require_command shasum
require_command spctl
require_command codesign
if [[ $live -eq 1 ]]; then
  require_command bash
fi

echo "==> release files"
[[ -f docs/release.md ]] && ok "docs/release.md present" || error "docs/release.md missing"
[[ -f docs/qa/desktop-smoke.md ]] && ok "desktop smoke checklist present" || error "docs/qa/desktop-smoke.md missing"
[[ -f scripts/export-options-developer-id.plist ]] \
  && ok "Developer ID export options present" \
  || error "scripts/export-options-developer-id.plist missing"

echo "==> project signing placeholders"
if rg -q 'teamID = "TEAMID_PLACEHOLDER"' Tuist/ProjectDescriptionHelpers/BrevConstants.swift; then
  warn "Tuist teamID is still TEAMID_PLACEHOLDER; set Henrik's Apple team ID before signed archives"
else
  ok "Tuist teamID is configured"
fi

echo "==> local signing identity"
if command -v security >/dev/null 2>&1 \
  && security find-identity -v -p codesigning 2>/dev/null | rg -q 'Developer ID Application'; then
  ok "Developer ID Application identity found in keychain"
else
  warn "Developer ID Application identity not found in keychain"
fi

echo "==> notarization and Sparkle inputs"
asc_key_path="$(read_env_alias BREV_ASC_KEY_PATH APP_STORE_CONNECT_KEY_PATH)"
asc_key_id="$(read_env_alias BREV_ASC_KEY_ID APP_STORE_CONNECT_KEY_ID)"
asc_issuer_id="$(read_env_alias BREV_ASC_ISSUER_ID APP_STORE_CONNECT_ISSUER_ID)"

if [[ -n "$asc_key_path" ]]; then
  if [[ -n "${BREV_ASC_KEY_PATH:-}" ]]; then
    ok "BREV_ASC_KEY_PATH set"
  else
    ok "APP_STORE_CONNECT_KEY_PATH set (legacy alias for BREV_ASC_KEY_PATH)"
  fi
else
  warn "BREV_ASC_KEY_PATH is not set"
fi

if [[ -n "$asc_key_id" ]]; then
  if [[ -n "${BREV_ASC_KEY_ID:-}" ]]; then
    ok "BREV_ASC_KEY_ID set"
  else
    ok "APP_STORE_CONNECT_KEY_ID set (legacy alias for BREV_ASC_KEY_ID)"
  fi
else
  warn "BREV_ASC_KEY_ID is not set"
fi

if [[ -n "$asc_issuer_id" ]]; then
  if [[ -n "${BREV_ASC_ISSUER_ID:-}" ]]; then
    ok "BREV_ASC_ISSUER_ID set"
  else
    ok "APP_STORE_CONNECT_ISSUER_ID set (legacy alias for BREV_ASC_ISSUER_ID)"
  fi
else
  warn "BREV_ASC_ISSUER_ID is not set"
fi

warn_missing_env BREV_SPARKLE_PUBLIC_ED_KEY
warn_missing_env SPARKLE_PRIVATE_KEY_PATH
warn_missing_env BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER
warn_missing_env BREV_BUILD_NUMBER

if [[ -n "$asc_key_path" && ! -f "$asc_key_path" ]]; then
  warn "BREV_ASC_KEY_PATH does not point to a readable file"
fi

if [[ -n "${SPARKLE_PRIVATE_KEY_PATH:-}" && ! -f "$SPARKLE_PRIVATE_KEY_PATH" ]]; then
  warn "SPARKLE_PRIVATE_KEY_PATH does not point to a readable file"
fi

if [[ -n "${BREV_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  case "$BREV_SPARKLE_PUBLIC_ED_KEY" in
    *PLACEHOLDER*|*\$\(*)
      warn "BREV_SPARKLE_PUBLIC_ED_KEY still looks like a placeholder"
      ;;
  esac
fi

if [[ -n "${BREV_BUILD_NUMBER:-}" && ! "$BREV_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  warn "BREV_BUILD_NUMBER must be a positive integer"
fi

if command -v generate_appcast >/dev/null 2>&1 \
  || [[ -x "$ROOT/Tuist/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" ]]; then
  ok "Sparkle generate_appcast available"
else
  warn "Sparkle generate_appcast not found on PATH"
fi

if command -v xcrun >/dev/null 2>&1 && xcrun notarytool --help >/dev/null 2>&1; then
  ok "notarytool available"
else
  warn "xcrun notarytool is unavailable"
fi

echo "==> working tree"
if git diff --quiet && git diff --cached --quiet; then
  ok "working tree clean"
else
  warn "working tree has uncommitted changes; release archives should come from a clean checkout"
fi

if [[ $live -eq 1 ]]; then
  echo "==> live provider readiness"
  if ./script/build_and_run.sh --preflight --live; then
    ok "live IMAP/SMTP transport preflight passed"
  else
    warn "live IMAP/SMTP transport preflight failed (see ./script/build_and_run.sh --preflight --live)"
  fi

  if ./scripts/check-imap-oauth-setup.sh; then
    ok "OAuth provider configuration check passed"
  else
    warn "OAuth provider configuration check failed (see ./scripts/check-imap-oauth-setup.sh)"
  fi

  if [[ -z "${BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID:-}" || -z "${BREV_GOOGLE_OAUTH_IOS_CLIENT_ID:-}" ]]; then
    warn "Gmail OAuth is not release-ready: configure both macOS and iOS Google client IDs"
  else
    ok "Gmail OAuth macOS and iOS client IDs set"
  fi

  if [[ -z "${BREV_GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
    warn "Gmail OAuth macOS is not release-ready: configure the Desktop client credential"
  else
    ok "Gmail OAuth macOS Desktop client credential set"
  fi

  if [[ -z "${BREV_MICROSOFT_OAUTH_CLIENT_ID:-}" ]]; then
    warn "Microsoft OAuth is not release-ready: configure BREV_MICROSOFT_OAUTH_CLIENT_ID"
  else
    ok "Microsoft OAuth client ID set"
  fi
fi

if [[ $errors -ne 0 ]]; then
  echo "release-preflight.sh: ${errors} error(s), ${warnings} warning(s)" >&2
  exit 1
fi

if [[ $strict -eq 1 && $warnings -ne 0 ]]; then
  echo "release-preflight.sh: strict mode failed with ${warnings} warning(s)" >&2
  exit 1
fi

echo "release-preflight.sh: OK (${warnings} warning(s))"
