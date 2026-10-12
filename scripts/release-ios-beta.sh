#!/usr/bin/env bash
# release-ios-beta.sh — Build the iOS app from main and upload it to TestFlight.
#
# Usage:
#   scripts/release-ios-beta.sh --notes "What to test" [--internal-only]
#                               [--current-checkout] [--dry-run]
#
#   --notes TEXT        "What to Test" shown to TestFlight testers (English).
#   --internal-only     Upload with testFlightInternalTestingOnly. That build
#                       can never reach external testers or the App Store.
#   --current-checkout  Build the commit that is checked out instead of moving
#                       the checkout to origin/main.
#   --dry-run           Run the gates, archive, sign and export locally. Uploads
#                       nothing and leaves the build counter alone.
#
# Runs on the release machine only. Settings and state live outside the
# repository in ~/.brev-ios-release (override with BREV_IOS_RELEASE_HOME);
# docs/release.md, "iOS TestFlight", lists what release.env holds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_HOME="${BREV_IOS_RELEASE_HOME:-$HOME/.brev-ios-release}"
BUNDLE_ID="eu.brevmail.brev.ios"
# Above every build number uploaded by hand (9 was the last one recorded).
FIRST_BUILD_NUMBER=100

NOTES=""
INTERNAL_ONLY=false
CURRENT_CHECKOUT=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes)            NOTES="${2:?--notes requires a value}"; shift 2 ;;
    --internal-only)    INTERNAL_ONLY=true; shift ;;
    --current-checkout) CURRENT_CHECKOUT=true; shift ;;
    --dry-run)          DRY_RUN=true; shift ;;
    -h|--help)          sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "release-ios-beta.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() {
  echo "release-ios-beta.sh: $1" >&2
  exit 1
}

if [[ ! -f "$RELEASE_HOME/release.env" ]]; then
  fail "no $RELEASE_HOME/release.env: this is not the release machine (see docs/release.md)."
fi
set -a
# shellcheck disable=SC1091
source "$RELEASE_HOME/release.env"
set +a

# Homebrew is not on the PATH of an SSH session on the release machine.
export PATH="$PATH:/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin"

# ── Validate before anything is built ────────────────────────────────────────
[[ -n "${NOTES//[[:space:]]/}" ]] || fail '--notes "…" is required.'
if [[ "$DRY_RUN" != "true" ]] && ! command -v node >/dev/null 2>&1; then
  fail "node is needed for the TestFlight follow-up (scripts/testflight-distribute.mjs)."
fi

missing=()
for var in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH BREV_GOOGLE_OAUTH_IOS_CLIENT_ID; do
  [[ -n "${!var:-}" ]] || missing+=("$var")
done
if [[ -n "${SIGNING_KEYCHAIN:-}" && -z "${SIGNING_KEYCHAIN_PASSWORD_FILE:-}" ]]; then
  missing+=("SIGNING_KEYCHAIN_PASSWORD_FILE")
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  fail "missing from $RELEASE_HOME/release.env: ${missing[*]}"
fi
for var in ASC_KEY_PATH SIGNING_KEYCHAIN_PASSWORD_FILE; do
  if [[ -n "${!var:-}" && ! -f "${!var}" ]]; then
    fail "$var points to a missing file: ${!var}"
  fi
done

# The same derivation as BrevConstants: Google's reversed client ID.
reverse_client_id() {
  awk -F. '{ for (i = NF; i > 0; i--) printf "%s%s", $i, (i > 1 ? "." : "\n") }' <<<"$1"
}
: "${BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME:=$(reverse_client_id "$BREV_GOOGLE_OAUTH_IOS_CLIENT_ID")}"
: "${BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI:=$BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME:/oauth2redirect}"

PROVIDER_SETTINGS=(
  BREV_GOOGLE_OAUTH_IOS_CLIENT_ID
  BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME
  BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI
  BREV_MICROSOFT_OAUTH_CLIENT_ID
  BREV_GOOGLE_API_KEY
  BREV_GOOGLE_APP_ID
)
for var in "${PROVIDER_SETTINGS[@]}"; do
  value="${!var:-}"
  # An xcconfig value ends at whitespace-free text; "//" would start a comment.
  if [[ -n "$value" && ( ! "$value" =~ ^[A-Za-z0-9._:/~-]+$ || "$value" == *//* ) ]]; then
    fail "$var contains characters an xcconfig cannot carry."
  fi
done
unset value

# ── Checkout ─────────────────────────────────────────────────────────────────
cd "$REPO_ROOT"
if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  fail "the checkout $REPO_ROOT has local changes; refusing to release."
fi
if [[ "$CURRENT_CHECKOUT" != "true" ]]; then
  git fetch --quiet origin main
  git checkout --quiet --detach origin/main
fi
COMMIT="$(git rev-parse --short HEAD)"

VERSION="$(sed -n 's/.*marketingVersion = "\(.*\)".*/\1/p' Tuist/ProjectDescriptionHelpers/BrevConstants.swift)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "could not read the marketing version from BrevConstants."

# ── One release at a time; a lock left by a killed run is reclaimed ──────────
LOCK_FILE="$RELEASE_HOME/release.lock"
if ! (set -o noclobber; echo "$$" >"$LOCK_FILE") 2>/dev/null; then
  lock_pid="$(cat "$LOCK_FILE" 2>/dev/null || true)"
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
    fail "another release is running (pid $lock_pid)."
  fi
  echo "$$" >"$LOCK_FILE"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/brev-ios-release.XXXXXX")"
cleanup() {
  rm -rf "$WORK"
  rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# One counter on the release machine, so build numbers only go up.
BUILD_NUMBER=""
if [[ "$DRY_RUN" != "true" ]]; then
  counter="$RELEASE_HOME/build-number"
  last=$((FIRST_BUILD_NUMBER - 1))
  if [[ -f "$counter" ]]; then
    last="$(tr -d '[:space:]' <"$counter")"
    [[ "$last" =~ ^[0-9]+$ ]] || fail "$counter does not hold a number."
  fi
  BUILD_NUMBER=$((last + 1))
  if (( BUILD_NUMBER < FIRST_BUILD_NUMBER )); then BUILD_NUMBER=$FIRST_BUILD_NUMBER; fi
  echo "$BUILD_NUMBER" >"$counter"
fi

echo "=== Brev iOS beta ==="
echo "Commit       : $COMMIT"
echo "Version      : $VERSION"
echo "Build number : ${BUILD_NUMBER:-<dry run>}"
echo "Export policy: $([[ "$INTERNAL_ONLY" == "true" ]] && echo internal-only || echo external-capable)"

# ── Gates (docs/release.md, "iOS TestFlight") ────────────────────────────────
scripts/test-apple-team-config.sh
scripts/test-ios-privacy-manifest.sh
scripts/test-testflight-export-options.sh

# Generate with the provider settings unset, so the tracked project files stay
# as committed and no key is written into them. The archive gets the values
# from a private xcconfig instead.
(
  for var in "${PROVIDER_SETTINGS[@]}" BREV_LOCAL_QA BREV_GOOGLE_OAUTH_CLIENT_ID; do unset "$var"; done
  scripts/prepare-xcode-workspace.sh
)

# The Release mailbox launch regression: Debug builds and the normal simulator
# stack missed the launch crash in internal builds 5 and 6.
destination="$(scripts/ios-simulator-destination.sh)"
(cd packages/BrevMail && xcodebuild -scheme BrevMail \
  -configuration Release ENABLE_TESTABILITY=YES \
  -destination "$destination" -skipMacroValidation \
  -parallel-testing-enabled NO \
  -only-testing:BrevMailTests/BrevMailRootLaunchTests test)

if [[ "$INTERNAL_ONLY" != "true" ]]; then
  # A build that can reach external testers must ignore an injected demo mailbox.
  swift test -c release --package-path packages/BrevMail \
    --filter AppSessionFactoryTests.releaseBuildIgnoresInjectedDemoRequest
fi

# ── Archive ──────────────────────────────────────────────────────────────────
# The login keychain is locked over SSH, so the release machine keeps its
# Apple Development identity in a keychain this script unlocks itself.
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
  security unlock-keychain -p "$(tr -d '\n' <"$SIGNING_KEYCHAIN_PASSWORD_FILE")" "$SIGNING_KEYCHAIN" \
    || fail "could not unlock $SIGNING_KEYCHAIN"
fi

provider_xcconfig="$WORK/provider-settings.xcconfig"
(umask 077; : >"$provider_xcconfig")
for var in "${PROVIDER_SETTINGS[@]}"; do
  printf '%s = %s\n' "$var" "${!var:-}" >>"$provider_xcconfig"
done

XCODE_AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)
ARCHIVE_PATH="$WORK/BrevIOS.xcarchive"
ARCHIVE_ARGS=(
  -workspace Brev.xcworkspace
  -scheme BrevIOS
  -configuration Release
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE_PATH"
  -xcconfig "$provider_xcconfig"
  "${XCODE_AUTH[@]}"
  "MARKETING_VERSION=$VERSION"
)
[[ -n "$BUILD_NUMBER" ]] && ARCHIVE_ARGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
[[ -n "${SIGNING_KEYCHAIN:-}" ]] && ARCHIVE_ARGS+=("OTHER_CODE_SIGN_FLAGS=--keychain $SIGNING_KEYCHAIN")
xcodebuild archive "${ARCHIVE_ARGS[@]}"
rm -f "$provider_xcconfig"

# ── Verify the archive before it leaves the machine ──────────────────────────
APP_PATH="$ARCHIVE_PATH/Products/Applications/BrevIOS.app"
plist_value() {
  plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}
archived_bundle_id="$(plist_value "$ARCHIVE_PATH/Info.plist" ApplicationProperties.CFBundleIdentifier)"
archived_version="$(plist_value "$ARCHIVE_PATH/Info.plist" ApplicationProperties.CFBundleShortVersionString)"
archived_build="$(plist_value "$ARCHIVE_PATH/Info.plist" ApplicationProperties.CFBundleVersion)"
[[ "$archived_bundle_id" == "$BUNDLE_ID" ]] || fail "archive bundle id is '$archived_bundle_id', expected $BUNDLE_ID."
[[ "$archived_version" == "$VERSION" ]] || fail "archive version is '$archived_version', expected $VERSION."
if [[ -n "$BUILD_NUMBER" && "$archived_build" != "$BUILD_NUMBER" ]]; then
  fail "archive build is '$archived_build', expected $BUILD_NUMBER."
fi
[[ -f "$APP_PATH/PrivacyInfo.xcprivacy" ]] || fail "the archived app has no PrivacyInfo.xcprivacy."
# Compared, never printed.
if [[ "$(plist_value "$APP_PATH/Info.plist" BREVGoogleOAuthIOSClientID)" != "$BREV_GOOGLE_OAUTH_IOS_CLIENT_ID" ]]; then
  fail "the Google iOS client ID did not reach the archived app."
fi
if [[ "$(plist_value "$APP_PATH/Info.plist" BREVGoogleOAuthIOSCallbackScheme)" != "$BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME" ]]; then
  fail "the Google callback scheme in the archived app does not match the client ID."
fi
codesign --verify --deep --strict "$APP_PATH"

# ── Export: upload, or a local .ipa on a dry run ─────────────────────────────
if [[ "$INTERNAL_ONLY" == "true" ]]; then
  export_options="scripts/export-options-testflight-internal.plist"
else
  export_options="scripts/export-options-testflight-external.plist"
fi
if [[ "$DRY_RUN" == "true" ]]; then
  cp "$export_options" "$WORK/export-options-local.plist"
  export_options="$WORK/export-options-local.plist"
  plutil -replace destination -string export "$export_options"
fi
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$WORK/export" \
  -exportOptionsPlist "$export_options" \
  "${XCODE_AUTH[@]}"

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "Done ($COMMIT): $VERSION archive signed for distribution and exported locally (dry run, not uploaded)."
  exit 0
fi

printf '{\n  "ios": {\n    "version": "%s",\n    "buildNumber": %s,\n    "commit": "%s",\n    "releasedAt": "%s"\n  }\n}\n' \
  "$VERSION" "$BUILD_NUMBER" "$COMMIT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$RELEASE_HOME/last-release.json"
echo ""
echo "Uploaded $VERSION ($BUILD_NUMBER) from $COMMIT to App Store Connect."

# Last, because App Store Connect needs 5–20 minutes to process the upload:
# the notes testers see, and the external group when one is configured. An
# internal-only build cannot join an external group.
follow_up=(--bundle-id "$BUNDLE_ID" --version "$VERSION" --build-number "$BUILD_NUMBER" --notes "$NOTES")
if [[ "$INTERNAL_ONLY" != "true" && -n "${TESTFLIGHT_EXTERNAL_GROUP:-}" ]]; then
  follow_up+=(--group "$TESTFLIGHT_EXTERNAL_GROUP")
fi
if ! node scripts/testflight-distribute.mjs "${follow_up[@]}"; then
  fail "the upload succeeded, but the TestFlight follow-up failed. Do not rerun the release; check the build in App Store Connect."
fi
echo "Done ($COMMIT): $VERSION ($BUILD_NUMBER) is in TestFlight with notes set."
