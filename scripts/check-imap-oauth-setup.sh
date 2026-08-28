#!/usr/bin/env bash
# check-imap-oauth-setup.sh — Validate standards-first IMAP OAuth (XOAUTH2)
# configuration for Gmail and Outlook (ADR-0028).
#
# Validates separate native Google client IDs/callbacks for macOS and iOS plus
# the Microsoft client ID consumed via OAuthClientConfiguration → Info.plist.
# Legacy Google values are accepted only with explicit BREV_LOCAL_QA=1.
#
# Usage:
#   scripts/check-imap-oauth-setup.sh
#
# Exit codes:
#   0  At least one provider is fully configured (or none are, which is a valid
#      app-password-only setup — reported as a warning, not a failure).
#   1  A provider is partially configured (e.g. Google ID without secret).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Load .env.local ───────────────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env.local"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
else
  echo "WARN: .env.local not found — checking environment variables only."
  echo "      Copy .env.example to .env.local and fill in your OAuth values."
fi

GOOGLE_MAC_REDIRECT_URI="${BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI:-http://127.0.0.1}"
GOOGLE_MAC_CALLBACK_SCHEME="${BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME:-http}"
GOOGLE_IOS_ID="${BREV_GOOGLE_OAUTH_IOS_CLIENT_ID:-}"
GOOGLE_IOS_CALLBACK_SCHEME="${BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME:-}"
GOOGLE_IOS_REDIRECT_URI="${BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI:-}"
MICROSOFT_REDIRECT_URI="brev://oauth"
PASS=true
CONFIGURED_COUNT=0

nonblank() { [[ -n "${1:-}" ]]; }

# ── Google ───────────────────────────────────────────────────────────────────
GID="${BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID:-}"
if [[ -z "$GID" && "${BREV_LOCAL_QA:-}" =~ ^(1|true|yes|on)$ ]]; then
  GID="${BREV_GOOGLE_OAUTH_CLIENT_ID:-}"
  [[ -n "$GID" ]] && echo "WARN: using legacy Google client ID because BREV_LOCAL_QA is enabled."
fi
GSECRET="${BREV_GOOGLE_OAUTH_CLIENT_SECRET:-}"
if nonblank "$GID"; then
  echo "PASS: Google macOS/Desktop OAuth client ID is set (native PKCE client)."
  if nonblank "$GSECRET"; then
    echo "PASS: Google macOS/Desktop client credential is set (non-confidential native credential)."
  else
    echo "FAIL: Google macOS/Desktop OAuth requires the generated Desktop client credential."
    echo "      Set BREV_GOOGLE_OAUTH_CLIENT_SECRET in ignored local or release configuration."
    PASS=false
  fi
  CONFIGURED_COUNT=$((CONFIGURED_COUNT + 1))
elif nonblank "$GSECRET"; then
  echo "FAIL: Google OAuth has a secret but no client ID."
  echo "      Set the platform-specific Google client ID; legacy values are local-QA only."
  echo "      Do not rely on a client secret in a distributed app."
  PASS=false
else
  echo "INFO: Google macOS OAuth unset — Gmail accounts will use manual IMAP only."
fi

reverse_client_id() {
  local id="$1" result="" field
  IFS='.' read -r -a fields <<< "$id"
  for ((i=${#fields[@]}-1; i>=0; i--)); do
    field="${fields[$i]}"
    [[ -z "$result" ]] && result="$field" || result="$result.$field"
  done
  printf '%s' "$result"
}

validate_google_callback() {
  local platform="$1" id="$2" uri="$3" callback="$4" scheme host expected
  scheme="${uri%%:*}"
  if [[ -z "$id" ]]; then
    return 0
  fi
  if [[ -z "$uri" || -z "$callback" || "$scheme" != "$callback" ]]; then
    echo "FAIL: Google $platform redirect/callback scheme must match exactly."
    PASS=false
    return 0
  fi
  if [[ "$platform" == "macOS/Desktop" ]]; then
    host="${uri#*://}"; host="${host%%[:/]*}"
    if [[ "$scheme" != "http" || "$host" != "127.0.0.1" ]]; then
      echo "FAIL: Google macOS/Desktop OAuth must use the http://127.0.0.1 loopback base."
      PASS=false
    fi
  elif [[ "$scheme" == "http" || "$scheme" == "https" ]]; then
    echo "FAIL: Google loopback callbacks are supported only on macOS/Desktop."
    PASS=false
  elif [[ "$scheme" != *.* || ! "$scheme" =~ ^[A-Za-z][A-Za-z0-9+.-]*$ ]]; then
    echo "FAIL: Google $platform callback scheme must be reverse-DNS and contain a period."
    PASS=false
  fi
  if [[ "$platform" == "iOS" ]]; then
    expected="$(reverse_client_id "$id")"
    if [[ "$callback" != "$expected" ]]; then
      echo "FAIL: Google iOS callback scheme must equal the reversed client ID."
      PASS=false
    fi
  fi
}

if [[ -z "$GOOGLE_IOS_CALLBACK_SCHEME" && -n "$GOOGLE_IOS_ID" ]]; then
  GOOGLE_IOS_CALLBACK_SCHEME="$(reverse_client_id "$GOOGLE_IOS_ID")"
fi
if [[ -z "$GOOGLE_IOS_REDIRECT_URI" && -n "$GOOGLE_IOS_CALLBACK_SCHEME" ]]; then
  GOOGLE_IOS_REDIRECT_URI="$GOOGLE_IOS_CALLBACK_SCHEME:/oauth2redirect"
fi
validate_google_callback "macOS/Desktop" "$GID" "$GOOGLE_MAC_REDIRECT_URI" "$GOOGLE_MAC_CALLBACK_SCHEME"
validate_google_callback "iOS" "$GOOGLE_IOS_ID" "$GOOGLE_IOS_REDIRECT_URI" "$GOOGLE_IOS_CALLBACK_SCHEME"
if [[ -n "$GOOGLE_IOS_ID" ]]; then
  echo "PASS: Google iOS client ID and reversed-client-ID callback are set."
  CONFIGURED_COUNT=$((CONFIGURED_COUNT + 1))
else
  echo "INFO: Google iOS OAuth unset — iOS Gmail accounts will use manual IMAP only."
fi

# ── Microsoft ────────────────────────────────────────────────────────────────
MID="${BREV_MICROSOFT_OAUTH_CLIENT_ID:-}"
if nonblank "$MID"; then
  echo "PASS: Microsoft OAuth client ID is set."
  CONFIGURED_COUNT=$((CONFIGURED_COUNT + 1))
else
  echo "INFO: Microsoft OAuth unset — Outlook accounts will use manual IMAP only."
fi

# ── Info.plist injection points ──────────────────────────────────────────────
for plist in "apps/macOS/Resources/Info.plist" "apps/iOS/Resources/Info.plist"; do
  if grep -Eq "BREVGoogleOAuth(MacOS|IOS)ClientID" "$REPO_ROOT/$plist" 2>/dev/null; then
    echo "PASS: $plist exposes the OAuth Info.plist keys."
  else
    echo "FAIL: $plist is missing its platform-specific Google OAuth client key — OAuth values can't"
    echo "      reach the app. Re-add the build-setting substitution keys."
    PASS=false
  fi
done

# When a built app or an expanded plist is available, validate the values that
# Xcode actually embedded rather than trusting only the source substitutions.
# Paths are opt-in so this check remains useful before a local build exists.
check_effective_plist() {
  local platform="$1" plist_path="$2" id_key="$3" redirect_key="$4" callback_key="$5"
  local expected_id="$6" expected_redirect="$7" expected_callback="$8" actual_id actual_redirect actual_callback
  [[ -z "$plist_path" ]] && return 0
  if [[ ! -f "$plist_path" ]]; then
    echo "FAIL: effective $platform plist does not exist at the supplied path."
    PASS=false
    return 0
  fi
  actual_id="$(plutil -extract "$id_key" raw -o - "$plist_path" 2>/dev/null || true)"
  actual_redirect="$(plutil -extract "$redirect_key" raw -o - "$plist_path" 2>/dev/null || true)"
  actual_callback="$(plutil -extract "$callback_key" raw -o - "$plist_path" 2>/dev/null || true)"
  if grep -q '\$(' <<< "$actual_id$actual_redirect$actual_callback"; then
    echo "FAIL: effective $platform plist still contains an unresolved build setting."
    PASS=false
  fi
  if [[ -n "$expected_id" && "$actual_id" != "$expected_id" ]]; then
    echo "FAIL: effective $platform plist client ID differs from configured value."
    PASS=false
  fi
  if [[ -n "$expected_redirect" && "$actual_redirect" != "$expected_redirect" ]]; then
    echo "FAIL: effective $platform plist redirect URI differs from configured value."
    PASS=false
  fi
  if [[ -n "$expected_callback" && "$actual_callback" != "$expected_callback" ]]; then
    echo "FAIL: effective $platform plist callback scheme differs from configured value."
    PASS=false
  fi
  if [[ "$actual_callback" == "$actual_redirect" ]]; then
    echo "FAIL: effective $platform plist callback must be a scheme, not the full redirect URI."
    PASS=false
  fi
  [[ "$PASS" == "true" ]] && echo "PASS: effective $platform plist values match the configured OAuth client."
}

check_effective_plist "macOS/Desktop" "${BREV_EFFECTIVE_MACOS_PLIST:-}" \
  BREVGoogleOAuthMacOSClientID BREVGoogleOAuthMacOSRedirectURI BREVGoogleOAuthMacOSCallbackScheme \
  "$GID" "$GOOGLE_MAC_REDIRECT_URI" "$GOOGLE_MAC_CALLBACK_SCHEME"
check_effective_plist "iOS" "${BREV_EFFECTIVE_IOS_PLIST:-}" \
  BREVGoogleOAuthIOSClientID BREVGoogleOAuthIOSRedirectURI BREVGoogleOAuthIOSCallbackScheme \
  "$GOOGLE_IOS_ID" "$GOOGLE_IOS_REDIRECT_URI" "$GOOGLE_IOS_CALLBACK_SCHEME"

for plist in "apps/macOS/Resources/Info.plist" "apps/iOS/Resources/Info.plist"; do
  if grep -q 'BREVGoogleOAuth.*CallbackScheme' "$REPO_ROOT/$plist" 2>/dev/null; then
    echo "PASS: $plist exposes the effective Google callback build setting."
  else
    echo "FAIL: $plist is missing its platform-specific Google callback key."
    PASS=false
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "INFO: Google macOS/Desktop redirect URI → $GOOGLE_MAC_REDIRECT_URI"
echo "INFO: Google iOS redirect URI → ${GOOGLE_IOS_REDIRECT_URI:-<derived when iOS client is set>}"
echo "INFO: Microsoft redirect URI → $MICROSOFT_REDIRECT_URI"
echo "INFO: Gmail IMAP/SMTP OAuth scope → https://mail.google.com/"
echo "INFO: Re-run 'tuist generate' after changing any BREV_*_OAUTH_* value."
if [[ "$PASS" == "true" ]]; then
  if [[ "$CONFIGURED_COUNT" -eq 0 ]]; then
    echo "preflight: no OAuth providers configured (app-password-only is OK)"
  else
    echo "preflight: IMAP OAuth configuration ready ($CONFIGURED_COUNT provider(s))"
  fi
  exit 0
else
  echo "preflight: IMAP OAuth configuration has errors (see FAIL lines above)"
  exit 1
fi
