#!/usr/bin/env bash
# release-archive.sh — Build a signed macOS release archive (ADR-0080).
#
# Usage:
#   scripts/release-archive.sh [--ring stable|nightly] [--version X.Y.Z[-nightly.YYYYMMDD]]
#                              [--build-number N] [--dry-run]
#
# Required environment variables (set in .env.local or exported):
#   BREV_SIGNING_IDENTITY   Developer ID Application certificate
#                           e.g. "Developer ID Application: Henrik O. Gaard (XXXXXXXXXX)"
#   BREV_TEAM_ID            Apple Developer team ID (10-char alphanumeric)
#   BREV_SPARKLE_PUBLIC_ED_KEY  Sparkle 2 EdDSA public key (base64, required)
#   BREV_BUILD_NUMBER       Positive, monotonically increasing CFBundleVersion
#                           (or pass --build-number)
#
# Optional environment variables:
#   BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER
#                           Stable Developer ID provisioning profile
#                           (default "Brev Stable Developer ID CI Distribution")
#   BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER_NIGHTLY
#                           Nightly Developer ID provisioning profile
#                           (default "Brev Nightly Developer ID CI Distribution")
#   BREV_SPARKLE_FEED_URL   Appcast URL override (defaults to the ring feed)
#
# Output:
#   build/release/BrevMail.xcarchive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DRY_RUN=false
RING=stable
VERSION=""
BUILD_NUMBER_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ring)         RING="${2:?--ring requires stable|nightly}"; shift 2 ;;
    --version)      VERSION="${2:?--version requires a value}"; shift 2 ;;
    --build-number) BUILD_NUMBER_ARG="${2:?--build-number requires a value}"; shift 2 ;;
    --dry-run)      DRY_RUN=true; shift ;;
    -h|--help)      sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "release-archive.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ── Load .env.local if present ────────────────────────────────────────────────
ENV_FILE="$REPO_ROOT/.env.local"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

[[ -n "$BUILD_NUMBER_ARG" ]] && BREV_BUILD_NUMBER="$BUILD_NUMBER_ARG"

# ── Resolve ring metadata (ADR-0080 §1) ──────────────────────────────────────
NIGHTLY_OVERRIDES=()
case "$RING" in
  stable)
    DEFAULT_FEED_URL="https://henrikogaard.github.io/brev/appcast.xml"
    PROFILE_SPECIFIER="${BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER:-Brev Stable Developer ID CI Distribution}"
    ;;
  nightly)
    DEFAULT_FEED_URL="https://henrikogaard.github.io/brev/appcast-nightly.xml"
    PROFILE_SPECIFIER="${BREV_MACOS_PROVISIONING_PROFILE_SPECIFIER_NIGHTLY:-Brev Nightly Developer ID CI Distribution}"
    NIGHTLY_OVERRIDES=(
      "BREV_APP_PRODUCT_NAME=Brev Nightly"
      "BREV_APP_BUNDLE_ID=eu.brevmail.brev.nightly"
      "BREV_APP_ICON_NAME=AppIcon-Nightly"
    )
    ;;
  *)
    echo "ERROR: --ring must be 'stable' or 'nightly', got '$RING'." >&2
    exit 2
    ;;
esac
BREV_SPARKLE_FEED_URL="${BREV_SPARKLE_FEED_URL:-$DEFAULT_FEED_URL}"

# ── Validate required vars ────────────────────────────────────────────────────
missing=()
[[ -z "${BREV_SIGNING_IDENTITY:-}" ]] && missing+=("BREV_SIGNING_IDENTITY")
[[ -z "${BREV_TEAM_ID:-}" ]]          && missing+=("BREV_TEAM_ID")
[[ -z "${PROFILE_SPECIFIER:-}" ]] \
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

XCBUILD_ARGS=(
  -workspace Brev.xcworkspace
  -scheme BrevMacOS
  -configuration Release
  -archivePath "$ARCHIVE_PATH"
  ENABLE_HARDENED_RUNTIME=YES
  # This custom setting is consumed only by the BrevMacOS app target's
  # Release configuration; package targets must not receive a profile.
  BREV_PROVISIONING_PROFILE_SPECIFIER="$PROFILE_SPECIFIER"
  CURRENT_PROJECT_VERSION="$BREV_BUILD_NUMBER"
  BREV_RELEASE_RING="$RING"
  BREV_SPARKLE_FEED_URL="$BREV_SPARKLE_FEED_URL"
  BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID="$BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID"
  BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI="${BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI:-http://127.0.0.1}"
  BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME="${BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME:-http}"
  BREV_SPARKLE_PUBLIC_ED_KEY="$BREV_SPARKLE_PUBLIC_ED_KEY"
)
[[ -n "$VERSION" ]] && XCBUILD_ARGS+=("MARKETING_VERSION=$VERSION")
XCBUILD_ARGS+=("${NIGHTLY_OVERRIDES[@]+"${NIGHTLY_OVERRIDES[@]}"}")

echo "=== Brev macOS Release Archive ==="
echo "Ring             : $RING"
echo "Version          : ${VERSION:-<unset — keeps BrevConstants.marketingVersion>}"
echo "Signing identity : $BREV_SIGNING_IDENTITY"
echo "Team ID          : $BREV_TEAM_ID"
echo "Profile specifier: $PROFILE_SPECIFIER"
echo "Sparkle feed     : $BREV_SPARKLE_FEED_URL"
echo "Build number     : $BREV_BUILD_NUMBER"
echo "Archive path     : $ARCHIVE_PATH"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "(DRY RUN — resolved command:)"
  # shellcheck disable=SC2016
  printf 'mise exec -- tuist xcodebuild archive -xcconfig <oauth-secrets.xcconfig> '
  printf '%q ' "${XCBUILD_ARGS[@]}"
  printf '\n'
  exit 0
fi

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
# Tuist no longer exposes `tuist archive` as a top-level command; we
# use `tuist xcodebuild archive` and pass standard xcodebuild args.
mise exec -- tuist xcodebuild archive \
  -xcconfig "$oauth_xcconfig" \
  "${XCBUILD_ARGS[@]}"

rm -f "$oauth_xcconfig"
trap - EXIT

echo ""
echo "Archive complete: $ARCHIVE_PATH"
echo "Next: scripts/release-dmg.sh --ring $RING${VERSION:+ --version $VERSION}"
