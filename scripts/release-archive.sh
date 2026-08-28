#!/usr/bin/env bash
# release-archive.sh — Build a signed macOS release archive.
#
# Usage:
#   scripts/release-archive.sh [--dry-run]
#
# Required environment variables (set in .env.local or exported):
#   BREV_SIGNING_IDENTITY   Developer ID Application certificate
#                           e.g. "Developer ID Application: Henrik O. Gaard (XXXXXXXXXX)"
#   BREV_TEAM_ID            Apple Developer team ID (10-char alphanumeric)
#   BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER
#                           Developer ID provisioning profile for eu.brevmail.brev
#   BREV_SPARKLE_PUBLIC_ED_KEY  Sparkle 2 EdDSA public key (base64, required)
#   BREV_BUILD_NUMBER       Positive, monotonically increasing CFBundleVersion
#
# Output:
#   build/release/BrevMail.xcarchive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

# ── Load .env.local if present ────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env.local"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

# ── Validate required vars ────────────────────────────────────────────────────
missing=()
[[ -z "${BREV_SIGNING_IDENTITY:-}" ]] && missing+=("BREV_SIGNING_IDENTITY")
[[ -z "${BREV_TEAM_ID:-}" ]]          && missing+=("BREV_TEAM_ID")
[[ -z "${BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER:-}" ]] \
  && missing+=("BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER")
[[ -z "${BREV_SPARKLE_PUBLIC_ED_KEY:-}" ]] \
  && missing+=("BREV_SPARKLE_PUBLIC_ED_KEY")
[[ -z "${BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID:-}" ]] \
  && missing+=("BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID")
[[ -z "${BREV_GOOGLE_OAUTH_CLIENT_SECRET:-}" ]] \
  && missing+=("BREV_GOOGLE_OAUTH_CLIENT_SECRET")
[[ -z "${BREV_BUILD_NUMBER:-}" ]] && missing+=("BREV_BUILD_NUMBER")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required environment variables:"
  for var in "${missing[@]}"; do echo "  $var"; done
  echo "Set them in .env.local or export them before running this script."
  exit 1
fi

case "$BREV_SPARKLE_PUBLIC_ED_KEY" in
  *PLACEHOLDER*|*placeholder*|*\$\(*|todo|changeme|example)
    echo "ERROR: BREV_SPARKLE_PUBLIC_ED_KEY is a placeholder; provide the real Sparkle EdDSA public key." >&2
    exit 1
    ;;
esac

if [[ ! "$BREV_SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "ERROR: BREV_SPARKLE_PUBLIC_ED_KEY must be a 44-character base64 Sparkle EdDSA public key." >&2
  exit 1
fi

if [[ ! "$BREV_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: BREV_BUILD_NUMBER must be a positive integer that exceeds the latest shipped build." >&2
  exit 1
fi

ARCHIVE_DIR="$REPO_ROOT/build/release"
ARCHIVE_PATH="$ARCHIVE_DIR/BrevMail.xcarchive"
mkdir -p "$ARCHIVE_DIR"

echo "=== Brev macOS Release Archive ==="
echo "Signing identity : $BREV_SIGNING_IDENTITY"
echo "Team ID          : $BREV_TEAM_ID"
echo "Profile specifier: $BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER"
echo "Build number     : $BREV_BUILD_NUMBER"
echo "Archive path     : $ARCHIVE_PATH"
[[ "$DRY_RUN" == "true" ]] && echo "(DRY RUN — no build will run)" && exit 0

if [[ ! "$BREV_GOOGLE_OAUTH_CLIENT_SECRET" =~ ^[A-Za-z0-9._~-]+$ ]]; then
  echo "ERROR: BREV_GOOGLE_OAUTH_CLIENT_SECRET contains unsupported characters." >&2
  exit 1
fi

oauth_xcconfig="$(mktemp "${TMPDIR:-/tmp}/brev-google-oauth.XXXXXX")"
chmod 600 "$oauth_xcconfig"
printf 'BREV_GOOGLE_OAUTH_CLIENT_SECRET = %s\n' \
  "$BREV_GOOGLE_OAUTH_CLIENT_SECRET" >"$oauth_xcconfig"
trap 'rm -f "$oauth_xcconfig"' EXIT

# ── Run archive through Tuist xcodebuild passthrough ─────────────────────────
#
# Tuist no longer exposes `tuist archive` as a top-level command; we
# use `tuist xcodebuild archive` and pass standard xcodebuild args.
mise exec -- tuist xcodebuild archive \
  -workspace Brev.xcworkspace \
  -scheme BrevMacOS \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -xcconfig "$oauth_xcconfig" \
  DEVELOPMENT_TEAM="$BREV_TEAM_ID" \
  CODE_SIGN_IDENTITY="$BREV_SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES \
  PROVISIONING_PROFILE_SPECIFIER="$BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER" \
  CURRENT_PROJECT_VERSION="$BREV_BUILD_NUMBER" \
  BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID="$BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID" \
  BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI="${BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI:-http://127.0.0.1}" \
  BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME="${BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME:-http}" \
  BREV_SPARKLE_PUBLIC_ED_KEY="$BREV_SPARKLE_PUBLIC_ED_KEY"

rm -f "$oauth_xcconfig"
trap - EXIT

echo ""
echo "Archive complete: $ARCHIVE_PATH"
echo "Next: scripts/release-dmg.sh"
