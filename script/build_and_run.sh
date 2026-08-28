#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${BREV_ENV_FILE:-$ROOT_DIR/.env.local}"
OAUTH_SECRET_XCCONFIG=""

cleanup_oauth_secret_xcconfig() {
  if [[ -n "$OAUTH_SECRET_XCCONFIG" && -f "$OAUTH_SECRET_XCCONFIG" ]]; then
    rm -f "$OAUTH_SECRET_XCCONFIG"
  fi
}

trap cleanup_oauth_secret_xcconfig EXIT

trim_whitespace() {
  local raw="${1:-}"
  local trimmed="${raw#"${raw%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  printf '%s' "$trimmed"
}

env_file_value() {
  local value
  value="$(trim_whitespace "${1:-}")"

  if [[ ${#value} -ge 2 ]]; then
    local first="${value:0:1}"
    local last="${value: -1}"
    if { [[ "$first" == "\"" ]] && [[ "$last" == "\"" ]]; } ||
        { [[ "$first" == "'" ]] && [[ "$last" == "'" ]]; }; then
      value="${value:1:${#value}-2}"
    fi
  fi

  printf '%s' "$value"
}

allowed_env_key() {
  case "$1" in
    BREV_USE_MOCK|BREV_LOCAL_QA|BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK|\
    BREV_GOOGLE_OAUTH_CLIENT_ID|BREV_GOOGLE_OAUTH_CLIENT_SECRET|\
    BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID|BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI|\
    BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME|BREV_GOOGLE_OAUTH_IOS_CLIENT_ID|\
    BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI|BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME|\
    BREV_MICROSOFT_OAUTH_CLIENT_ID|BREV_SPARKLE_PUBLIC_ED_KEY)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

configured_value() {
  local raw="${1:-}"
  local trimmed
  trimmed="$(trim_whitespace "$raw")"
  local upper
  upper="$(printf '%s' "$trimmed" | tr '[:lower:]' '[:upper:]')"
  local lower
  lower="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"

  if [[ -z "$trimmed" ]]; then
    return 1
  fi

  if [[ "$upper" == *PLACEHOLDER* ]]; then
    return 1
  fi

  if [[ "$trimmed" == \$\(*\) ]]; then
    return 1
  fi

  case "$lower" in
    your-client-id|your_client_id|client-id|client_id|example-client-id|example_client_id|\
    replace-me|replace_me|changeme|change-me|todo|todo-client-id|todo_client_id|\
    your-redirect-scheme|your_redirect_scheme|redirect-scheme|redirect_scheme|\
    example-redirect-scheme|example_redirect_scheme)
      return 1
      ;;
  esac

  return 0
}

preserve_exported_value() {
  local marker="$1"
  local key="$2"
  [[ -n "$marker" ]] || return 1
  configured_value "${!key:-}"
}

load_local_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    return
  fi

  # An explicitly exported shell value wins over the optional dotenv file.
  # This keeps CI/one-shot invocations deterministic while still allowing a
  # developer's `.env.local` to provide the normal values.
  local preserve_brev_use_mock="${BREV_USE_MOCK+x}"
  local preserve_brev_local_qa="${BREV_LOCAL_QA+x}"
  local preserve_brev_google_oauth_allow_legacy_fallback="${BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK+x}"
  local preserve_brev_google_oauth_client_id="${BREV_GOOGLE_OAUTH_CLIENT_ID+x}"
  local preserve_brev_google_oauth_client_secret="${BREV_GOOGLE_OAUTH_CLIENT_SECRET+x}"
  local preserve_brev_google_oauth_macos_client_id="${BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID+x}"
  local preserve_brev_google_oauth_macos_redirect_uri="${BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI+x}"
  local preserve_brev_google_oauth_macos_callback_scheme="${BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME+x}"
  local preserve_brev_google_oauth_ios_client_id="${BREV_GOOGLE_OAUTH_IOS_CLIENT_ID+x}"
  local preserve_brev_google_oauth_ios_redirect_uri="${BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI+x}"
  local preserve_brev_google_oauth_ios_callback_scheme="${BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME+x}"
  local preserve_brev_microsoft_oauth_client_id="${BREV_MICROSOFT_OAUTH_CLIENT_ID+x}"
  local preserve_brev_sparkle_public_ed_key="${BREV_SPARKLE_PUBLIC_ED_KEY+x}"
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim_whitespace "$line")"
    if [[ -z "$line" || "${line:0:1}" == "#" ]]; then
      continue
    fi

    if [[ "$line" =~ ^export[[:space:]]+(.+)$ ]]; then
      line="${BASH_REMATCH[1]}"
    fi

    if [[ "$line" != *=* ]]; then
      echo "warning: ignoring malformed env line in $ENV_FILE: $line" >&2
      continue
    fi

    key="$(trim_whitespace "${line%%=*}")"
    if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "warning: ignoring invalid env key in $ENV_FILE: $key" >&2
      continue
    fi

    if ! allowed_env_key "$key"; then
      echo "warning: ignoring unsupported env key in $ENV_FILE: $key" >&2
      continue
    fi

    case "$key" in
      BREV_USE_MOCK)
        if [[ -n "$preserve_brev_use_mock" ]] &&
            { [[ "${BREV_USE_MOCK:-}" == "0" ]] || [[ "${BREV_USE_MOCK:-}" == "1" ]]; }; then
          continue
        fi
        ;;
      BREV_LOCAL_QA)
        preserve_exported_value "$preserve_brev_local_qa" BREV_LOCAL_QA && continue
        ;;
      BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK)
        preserve_exported_value \
          "$preserve_brev_google_oauth_allow_legacy_fallback" \
          BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK && continue
        ;;
      BREV_GOOGLE_OAUTH_CLIENT_ID)
        preserve_exported_value "$preserve_brev_google_oauth_client_id" BREV_GOOGLE_OAUTH_CLIENT_ID && continue
        ;;
      BREV_GOOGLE_OAUTH_CLIENT_SECRET)
        preserve_exported_value "$preserve_brev_google_oauth_client_secret" BREV_GOOGLE_OAUTH_CLIENT_SECRET && continue
        ;;
      BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID)
        preserve_exported_value \
          "$preserve_brev_google_oauth_macos_client_id" \
          BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID && continue
        ;;
      BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI)
        preserve_exported_value \
          "$preserve_brev_google_oauth_macos_redirect_uri" \
          BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI && continue
        ;;
      BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME)
        preserve_exported_value \
          "$preserve_brev_google_oauth_macos_callback_scheme" \
          BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME && continue
        ;;
      BREV_GOOGLE_OAUTH_IOS_CLIENT_ID)
        preserve_exported_value "$preserve_brev_google_oauth_ios_client_id" BREV_GOOGLE_OAUTH_IOS_CLIENT_ID && continue
        ;;
      BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI)
        preserve_exported_value \
          "$preserve_brev_google_oauth_ios_redirect_uri" \
          BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI && continue
        ;;
      BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME)
        preserve_exported_value \
          "$preserve_brev_google_oauth_ios_callback_scheme" \
          BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME && continue
        ;;
      BREV_MICROSOFT_OAUTH_CLIENT_ID)
        preserve_exported_value "$preserve_brev_microsoft_oauth_client_id" BREV_MICROSOFT_OAUTH_CLIENT_ID && continue
        ;;
      BREV_SPARKLE_PUBLIC_ED_KEY)
        preserve_exported_value "$preserve_brev_sparkle_public_ed_key" BREV_SPARKLE_PUBLIC_ED_KEY && continue
        ;;
    esac

    value="$(env_file_value "${line#*=}")"
    export "$key=$value"
  done <"$ENV_FILE"
}

load_local_env

RELEASE_APP_NAME="Brev"
RELEASE_BUNDLE_ID="eu.brevmail.brev"
TEST_BUNDLE_ID="eu.brevmail.brev.test"
WORKSPACE="Brev.xcworkspace"
SCHEME="BrevMacOS"
CONFIGURATION="Debug"
MODE="run"
MODE_SET=0
BUILD_KIND="test"
RELEASE_MAIN_REQUESTED=0
MOCK_FLAG_REQUESTED=0
LIVE_FLAG_REQUESTED=0
MOCK_MODE="${BREV_USE_MOCK:-}"
TEST_BUILD_DATE="${BREV_TEST_DATE:-$(date +%F)}"
HOST_ARCH="$(uname -m)"
DESTINATION="platform=macOS,arch=$HOST_ARCH"
VERIFY_TIMEOUT_SECONDS="${BREV_VERIFY_TIMEOUT_SECONDS:-10}"
VERIFY_STABILITY_SECONDS="${BREV_VERIFY_STABILITY_SECONDS:-8}"

BUILD_ROOT="$ROOT_DIR/.codex/build/macos"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
APP_NAME=""
BUNDLE_ID=""
APP_BUNDLE=""
APP_EXECUTABLE=""
INSTALL_DIR="${BREV_INSTALL_DIR:-/Applications}"
if [[ "$INSTALL_DIR" == "~" ]]; then
  INSTALL_DIR="$HOME"
elif [[ "$INSTALL_DIR" == "~/"* ]]; then
  INSTALL_DIR="$HOME/${INSTALL_DIR#"~/"}"
fi
INSTALLED_APP_BUNDLE=""
MACOS_INFO_PLIST="$ROOT_DIR/apps/macOS/Resources/Info.plist"
MACOS_ENTITLEMENTS="$ROOT_DIR/apps/macOS/Resources/BrevMacOS.entitlements"
MACOS_RELEASE_ENTITLEMENTS="$ROOT_DIR/apps/macOS/Resources/BrevMacOSRelease.entitlements"
LOCAL_BUILD_VERSION_SCRIPT="$ROOT_DIR/scripts/local-build-version.sh"

plist_value() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$MACOS_INFO_PLIST" 2>/dev/null || true
}

project_marketing_version() {
  local version
  version="$(awk -F'"' '/public static let marketingVersion = "/ { print $2; exit }' \
    "$ROOT_DIR/Tuist/ProjectDescriptionHelpers/BrevConstants.swift")"

  if [[ -n "$version" ]]; then
    printf '%s' "$version"
    return
  fi

  echo "error: unable to read marketing version from Tuist/ProjectDescriptionHelpers/BrevConstants.swift" >&2
  exit 1
}

project_team_id() {
  local team_id
  team_id="$(awk -F'"' '/public static let teamID = "/ { print $2; exit }' \
    "$ROOT_DIR/Tuist/ProjectDescriptionHelpers/BrevConstants.swift")"

  if [[ -n "$team_id" ]]; then
    printf '%s' "$team_id"
    return
  fi

  echo "error: unable to read team ID from Tuist/ProjectDescriptionHelpers/BrevConstants.swift" >&2
  exit 1
}

environment_build_value() {
  local key="$1"
  local value="${!key:-}"
  if configured_value "$value"; then
    printf '%s' "$value"
  fi
}

reverse_client_id() {
  local client_id="$1"
  [[ "$client_id" == *.* ]] || return 0
  awk -F. '{ for (i = NF; i >= 1; i--) printf "%s%s", $i, (i > 1 ? "." : "") }' <<<"$client_id"
}

oauth_build_args() {
  local mac_client_id mac_redirect_uri mac_callback_scheme
  local ios_client_id ios_redirect_uri ios_callback_scheme microsoft_client_id

  mac_client_id="$(environment_build_value BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID)"
  mac_redirect_uri="$(environment_build_value BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI)"
  mac_callback_scheme="$(environment_build_value BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME)"
  ios_client_id="$(environment_build_value BREV_GOOGLE_OAUTH_IOS_CLIENT_ID)"
  ios_callback_scheme="$(environment_build_value BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME)"
  ios_redirect_uri="$(environment_build_value BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI)"
  microsoft_client_id="$(environment_build_value BREV_MICROSOFT_OAUTH_CLIENT_ID)"

  # These defaults mirror BrevConstants and are passed explicitly so an old
  # generated project cannot keep a stale OAuth value after `.env.local`
  # changes. The Desktop client credential is not confidential in a native
  # binary; PKCE and the exact loopback redirect protect the authorization code.
  # The legacy client ID remains local-QA only.
  [[ -n "$mac_redirect_uri" ]] || mac_redirect_uri="http://127.0.0.1"
  [[ -n "$mac_callback_scheme" ]] || mac_callback_scheme="http"
  if [[ -z "$ios_callback_scheme" && -n "$ios_client_id" ]]; then
    ios_callback_scheme="$(reverse_client_id "$ios_client_id")"
  fi
  [[ -n "$ios_callback_scheme" ]] || ios_callback_scheme="eu.brevmail.brev"
  [[ -n "$ios_redirect_uri" ]] || ios_redirect_uri="${ios_callback_scheme}:/oauth2redirect"

  printf '%s\n' \
    "BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID=$mac_client_id" \
    "BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI=$mac_redirect_uri" \
    "BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME=$mac_callback_scheme" \
    "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID=$ios_client_id" \
    "BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI=$ios_redirect_uri" \
    "BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME=$ios_callback_scheme" \
    "BREV_MICROSOFT_OAUTH_CLIENT_ID=$microsoft_client_id"
}

oauth_secret_xcconfig() {
  local google_client_secret
  google_client_secret="$(environment_build_value BREV_GOOGLE_OAUTH_CLIENT_SECRET)"
  [[ -n "$google_client_secret" ]] || return 0
  if [[ ! "$google_client_secret" =~ ^[A-Za-z0-9._~-]+$ ]]; then
    echo "error: BREV_GOOGLE_OAUTH_CLIENT_SECRET contains unsupported characters" >&2
    return 1
  fi

  local oauth_xcconfig
  oauth_xcconfig="$(mktemp "${TMPDIR:-/tmp}/brev-google-oauth.XXXXXX")"
  chmod 600 "$oauth_xcconfig"
  printf 'BREV_GOOGLE_OAUTH_CLIENT_SECRET = %s\n' "$google_client_secret" >"$oauth_xcconfig"
  printf '%s' "$oauth_xcconfig"
}

# Prefer an explicit identity, then Apple Development for the project team,
# otherwise fall back to ad-hoc (`-`). Development signing keeps a stable Team
# ID so Keychain "Always Allow" survives rebuilds.
local_signing_identity() {
  if [[ -n "${BREV_LOCAL_SIGNING_IDENTITY:-}" ]]; then
    printf '%s' "$BREV_LOCAL_SIGNING_IDENTITY"
    return 0
  fi

  local team_id
  team_id="$(project_team_id)"

  # The parenthetical in an Apple Development identity name is the certificate
  # ID ("Apple Development: Jane Doe (96P5QW3XFQ)"), not the team — the team is
  # the certificate's OU. Matching the parenthetical against the team found
  # nothing and quietly fell back to ad-hoc on machines that had a usable cert.
  local identity=""
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
      | while IFS= read -r candidate; do
          if security find-certificate -c "$candidate" -p 2>/dev/null \
            | openssl x509 -noout -subject 2>/dev/null \
            | grep -q "OU=${team_id}"; then
            printf '%s' "$candidate"
            break
          fi
        done
  )"

  if [[ -n "$identity" ]]; then
    printf '%s' "$identity"
    return 0
  fi

  printf '%s' "-"
}

current_local_build_number() {
  bash "$LOCAL_BUILD_VERSION_SCRIPT" current
}

ensure_workspace_dependencies() {
  local sparkle_xcframework="$ROOT_DIR/Tuist/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework"
  if [[ -d "$sparkle_xcframework" ]]; then
    return 0
  fi

  echo "Sparkle is not prepared; resolving Tuist dependencies before the build."
  if command -v mise >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && mise exec -- tuist install)
  else
    (cd "$ROOT_DIR" && tuist install)
  fi

  if [[ ! -d "$sparkle_xcframework" ]]; then
    echo "error: Tuist did not prepare Sparkle at $sparkle_xcframework" >&2
    echo "Run scripts/prepare-xcode-workspace.sh for a full workspace refresh." >&2
    return 1
  fi
}

usage() {
  echo "usage: $0 [run|install|install-run|--debug|--logs|--telemetry|--verify|--print-config|--preflight|--setup-env] [--mock|--live] [--release-main]" >&2
}

set_mode() {
  local next_mode="$1"
  if [[ "$MODE_SET" -eq 1 && "$MODE" != "$next_mode" ]]; then
    echo "error: choose only one mode" >&2
    usage
    exit 2
  fi

  MODE="$next_mode"
  MODE_SET=1
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      run)
        set_mode "run"
        ;;
      --install|install)
        set_mode "install"
        ;;
      --install-run|install-run)
        set_mode "install-run"
        ;;
      --debug|debug)
        set_mode "debug"
        ;;
      --logs|logs)
        set_mode "logs"
        ;;
      --telemetry|telemetry)
        set_mode "telemetry"
        ;;
      --verify|verify)
        set_mode "verify"
        ;;
      --print-config|print-config)
        set_mode "print-config"
        ;;
      --preflight|preflight)
        set_mode "preflight"
        ;;
      --setup-env|setup-env)
        set_mode "setup-env"
        ;;
      --stamp-config|stamp-config)
        set_mode "stamp-config"
        ;;
      --mock|mock)
        MOCK_FLAG_REQUESTED=1
        MOCK_MODE="1"
        ;;
      --live|live)
        LIVE_FLAG_REQUESTED=1
        MOCK_MODE="0"
        ;;
      --release-main|release-main)
        RELEASE_MAIN_REQUESTED=1
        ;;
      --help|-h|help)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown option: $arg" >&2
        usage
        exit 2
        ;;
    esac
  done
}

configure_build_identity() {
  if ! [[ "$TEST_BUILD_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "error: BREV_TEST_DATE must use YYYY-MM-DD" >&2
    exit 2
  fi

  if [[ "$RELEASE_MAIN_REQUESTED" -eq 1 ]]; then
    BUILD_KIND="release"
    APP_NAME="$RELEASE_APP_NAME"
    BUNDLE_ID="$RELEASE_BUNDLE_ID"
    # The daily driver gets optimized code. Debug (-Onone) is for test
    # builds only — an unoptimized SwiftUI+Realm build feels sluggish.
    CONFIGURATION="Release"
  else
    BUILD_KIND="test"
    APP_NAME="Brev Test ($TEST_BUILD_DATE)"
    # Every dated test app needs a distinct LaunchServices identity. Reusing
    # one bundle ID lets an older app with a higher CFBundleVersion win even
    # when the user opens today's named bundle.
    local test_bundle_date="${TEST_BUILD_DATE//-/}"
    BUNDLE_ID="${TEST_BUNDLE_ID}.d${test_bundle_date}"
  fi

  APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
  if [[ -n "${BREV_APP_BUNDLE:-}" ]]; then
    if [[ "$MODE" != "stamp-config" ]]; then
      echo "error: BREV_APP_BUNDLE override is allowed only with --stamp-config" >&2
      exit 2
    fi
    APP_BUNDLE="$BREV_APP_BUNDLE"
  fi
  APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
}

validate_release_main_checkout() {
  local branch
  local head_commit
  local remote_main_commit

  branch="$(git -C "$ROOT_DIR" branch --show-current)"
  if [[ -n "$branch" && "$branch" != "main" ]]; then
    echo "error: release-main builds require the main branch or a detached checkout at origin/main" >&2
    exit 2
  fi

  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    echo "error: release-main builds require a clean checkout" >&2
    exit 2
  fi

  git -C "$ROOT_DIR" fetch origin main --quiet
  head_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  remote_main_commit="$(git -C "$ROOT_DIR" rev-parse refs/remotes/origin/main)"
  if [[ "$head_commit" != "$remote_main_commit" ]]; then
    echo "error: release-main checkout is stale or diverged from origin/main" >&2
    exit 2
  fi
}

validate_build_request() {
  if [[ "$MOCK_FLAG_REQUESTED" -eq 1 && "$LIVE_FLAG_REQUESTED" -eq 1 ]]; then
    echo "error: choose only one of --mock or --live" >&2
    exit 2
  fi

  if [[ "$RELEASE_MAIN_REQUESTED" -eq 1 ]]; then
    if [[ "$MOCK_FLAG_REQUESTED" -eq 1 || "$LIVE_FLAG_REQUESTED" -ne 1 || "$MOCK_MODE" != "0" ]]; then
      echo "error: release-main builds require live mail and reject --mock" >&2
      exit 2
    fi

    case "$MODE" in
      print-config|stamp-config)
        ;;
      *)
        validate_release_main_checkout
        ;;
    esac
  fi
}

kill_running_app() {
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" >/dev/null 2>&1 || true
  done < <(app_process_pids)
}

app_process_pids() {
  local needle="/$APP_NAME.app/Contents/MacOS/$APP_NAME"
  ps -axo pid=,command= | awk -v needle="$needle" 'index($0, needle) { print $1 }'
}

build_app() {
  local marketing_version
  local build_number
  local signing_identity
  local oauth_xcconfig
  local sparkle_public_key
  local -a build_args

  marketing_version="$(project_marketing_version)"
  build_number="$(bash "$LOCAL_BUILD_VERSION_SCRIPT" next)"
  signing_identity="$(local_signing_identity)"

  echo "Building $APP_NAME..."
  echo "    Version: ${marketing_version} (${build_number})"
  echo "    Signing: ${signing_identity}"

  # PRODUCT_NAME/PRODUCT_BUNDLE_IDENTIFIER overrides on the xcodebuild command
  # line apply across the whole target graph. Pass app-specific variables that
  # only the BrevMacOS target consumes, so Swift package products keep their
  # own names. Release builds already use the app target's default identity.
  build_args=()
  if [[ "$BUILD_KIND" != "release" ]]; then
    build_args+=(
      BREV_APP_PRODUCT_NAME="$APP_NAME"
      BREV_APP_BUNDLE_ID="$BUNDLE_ID"
      INFOPLIST_KEY_CFBundleDisplayName="$APP_NAME"
    )
  fi

  sparkle_public_key="$(environment_build_value BREV_SPARKLE_PUBLIC_ED_KEY)"
  if [[ "$BUILD_KIND" == "release" && ! "$sparkle_public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "error: release-main builds require a real 44-character Sparkle EdDSA public key" >&2
    return 2
  fi
  if [[ -n "$sparkle_public_key" ]]; then
    build_args+=("BREV_SPARKLE_PUBLIC_ED_KEY=$sparkle_public_key")
  fi

  while IFS= read -r oauth_setting; do
    build_args+=("$oauth_setting")
  done < <(oauth_build_args)
  oauth_xcconfig="$(oauth_secret_xcconfig)"
  OAUTH_SECRET_XCCONFIG="$oauth_xcconfig"
  local -a oauth_secret_build_args=()
  if [[ -n "$oauth_xcconfig" ]]; then
    oauth_secret_build_args=(-xcconfig "$oauth_xcconfig")
  fi

  # Compile unsigned for a reliable local build graph, then resign the .app
  # with Apple Development (stable Team ID → Keychain "Always Allow" sticks).
  #
  # Release builds are the exception: profile-backed entitlements (iCloud
  # KVS — ADR-0056; push, if ever re-enabled) only take effect when the
  # code signature carries a real embedded provisioning profile, and a
  # manual `codesign` after the fact cannot embed one. So for BUILD_KIND
  # "release" only, let xcodebuild sign fully here (-allowProvisioningUpdates
  # fetches/refreshes the profile); resign_built_app_if_needed below then
  # only needs to repair the signature after stamp_built_app_config's
  # Info.plist edits, not rebuild it from scratch. The project uses
  # CODE_SIGN_STYLE=Automatic, which rejects a fully-qualified identity
  # (team/hash suffix) here — unlike the manual `codesign` CLI used by
  # resign_built_app_if_needed, automatic signing already disambiguates by
  # the project's DEVELOPMENT_TEAM, so the generic "Apple Development"
  # string is required, not $signing_identity. DEVELOPMENT_TEAM must also be
  # passed here explicitly: it's already in the app target's own base
  # settings, but local Swift packages with resources (BrevSettings,
  # BrevDesign, …) get auto-generated bundle targets that Xcode resolves as
  # a separate sub-project without it, so an unqualified CODE_SIGN_IDENTITY
  # override alone makes automatic signing fail on those with "requires a
  # development team" once ANY package in the graph has a Resources/ dir.
  local -a signing_build_args
  if [[ "$BUILD_KIND" == "release" ]]; then
    signing_build_args=(
      CODE_SIGN_IDENTITY="Apple Development"
      DEVELOPMENT_TEAM="$(project_team_id)"
      -allowProvisioningUpdates
    )
  else
    signing_build_args=(CODE_SIGNING_ALLOWED=NO)
  fi

  set +e
  xcodebuild \
    -workspace "$ROOT_DIR/$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    MARKETING_VERSION="$marketing_version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    ${build_args[@]+"${build_args[@]}"} \
    "${oauth_secret_build_args[@]}" \
    "${signing_build_args[@]}" \
    -quiet \
    build
  local build_status=$?
  set -e
  if [[ -n "$oauth_xcconfig" ]]; then
    rm -f "$oauth_xcconfig"
    OAUTH_SECRET_XCCONFIG=""
  fi
  if [[ $build_status -ne 0 ]]; then
    return "$build_status"
  fi

  stamp_built_app_config
  resign_built_app_if_needed
}

plist_set_string() {
  local plist="$1"
  local key="$2"
  local value="$3"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  fi
}

plist_delete_key_if_present() {
  local plist="$1"
  local key="$2"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist"
  fi
}

stamp_built_app_config() {
  local plist="$APP_BUNDLE/Contents/Info.plist"

  if [[ ! -f "$plist" ]]; then
    echo "warning: cannot stamp built app config; missing Info.plist at $plist" >&2
    return 0
  fi

  plist_set_string "$plist" CFBundleDisplayName "$APP_NAME"
  plist_set_string "$plist" CFBundleName "$APP_NAME"
  plist_set_string "$plist" CFBundleIdentifier "$BUNDLE_ID"
  plist_set_string "$plist" BRBuildKind "$BUILD_KIND"
  if [[ "$BUILD_KIND" == "test" ]]; then
    plist_set_string "$plist" BRTestBuildDate "$TEST_BUILD_DATE"
  else
    plist_delete_key_if_present "$plist" BRTestBuildDate
  fi

  if [[ "$MOCK_MODE" == "1" ]]; then
    echo "stamp-config: stamped $APP_NAME test identity"
    return 0
  fi

  resign_built_app_if_needed

  echo "stamp-config: stamped $APP_NAME live identity"
}

macos_entitlements_path() {
  if [[ "$BUILD_KIND" == "release" ]]; then
    printf '%s' "$MACOS_RELEASE_ENTITLEMENTS"
  else
    printf '%s' "$MACOS_ENTITLEMENTS"
  fi
}

resign_built_app_if_needed() {
  if [[ ! -x "$APP_EXECUTABLE" ]]; then
    return 0
  fi

  local signing_identity
  signing_identity="$(local_signing_identity)"
  local codesign_args=(--force --deep --sign "$signing_identity")
  local local_entitlements=""
  local source_entitlements
  source_entitlements="$(macos_entitlements_path)"

  # Manual codesign (no embedded provisioning profile) cannot carry restricted
  # entitlements like iCloud KVS. Test builds keep the
  # sandbox/network/calendar set and strip those; release builds were already
  # signed with a real embedded provisioning profile in build_app above, so
  # this resign (needed to repair the signature after stamp_built_app_config's
  # Info.plist edits) must keep the entitlements file as-is or it would strip
  # capabilities the profile actually grants.
  if [[ -f "$source_entitlements" ]]; then
    local_entitlements="$(mktemp "${TMPDIR:-/tmp}/brev-local-entitlements.XXXXXX")"
    cp "$source_entitlements" "$local_entitlements"
    if [[ "$BUILD_KIND" != "release" ]]; then
      # iCloud KVS (ADR-0056) is likewise profile-backed; test builds stay local-only.
      /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-kvstore-identifier" "$local_entitlements" >/dev/null 2>&1 || true
    else
      # The source entitlements file uses Xcode build-setting macros
      # ($(TeamIdentifierPrefix), $(CFBundleIdentifier)) that Xcode's own
      # build system resolves during its CodeSign build phase. This is a
      # raw `cp` + `codesign`, which does not — left unresolved, the literal
      # macro text ships as the entitlement's value, which AMFI rejects at
      # launch ("Launchd job spawn failed", RBSRequestErrorDomain code 5).
      # Substitute them by hand to match what a real Xcode build would do.
      local team_id
      team_id="$(project_team_id)"
      sed -i '' \
        -e "s/\$(TeamIdentifierPrefix)/${team_id}./g" \
        -e "s/\$(CFBundleIdentifier)/${BUNDLE_ID}/g" \
        "$local_entitlements"
    fi
    codesign_args+=(--entitlements "$local_entitlements")
  else
    codesign_args+=(--preserve-metadata=entitlements)
  fi

  if ! codesign "${codesign_args[@]}" "$APP_BUNDLE" >/dev/null; then
    if [[ "$signing_identity" != "-" ]]; then
      echo "warning: Development signing failed; falling back to ad-hoc" >&2
      codesign_args=(--force --deep --sign -)
      if [[ -n "$local_entitlements" ]]; then
        codesign_args+=(--entitlements "$local_entitlements")
      fi
      codesign "${codesign_args[@]}" "$APP_BUNDLE" >/dev/null
    else
      if [[ -n "$local_entitlements" ]]; then
        rm -f "$local_entitlements"
      fi
      return 1
    fi
  fi

  if [[ -n "$local_entitlements" ]]; then
    rm -f "$local_entitlements"
  fi
}

open_env_args() {
  if [[ "$MOCK_MODE" == "0" || "$MOCK_MODE" == "1" ]]; then
    printf '%s\n' "--env" "BREV_USE_MOCK=$MOCK_MODE"
  fi
}

debug_env_args() {
  if [[ "$MOCK_MODE" == "0" || "$MOCK_MODE" == "1" ]]; then
    printf '%s\n' "BREV_USE_MOCK=$MOCK_MODE"
  fi
}

publish_launch_env() {
  # LaunchServices can start GUI apps outside the shell's environment.
  # Never publish mock mode globally: a later Finder launch of the daily-driver
  # Brev.app must not inherit placeholder mailboxes from a test build.
  launchctl unsetenv BREV_USE_MOCK >/dev/null 2>&1 || true
}

warn_live_configuration() {
  if [[ "$MOCK_MODE" != "1" ]]; then
    echo "info: live IMAP/SMTP account setup enabled" >&2
  fi
}

print_config() {
  local marketing_version
  local local_build_number
  marketing_version="$(project_marketing_version)"
  local_build_number="$(current_local_build_number)"

  echo "BREV_ENV_FILE=$ENV_FILE"
  echo "BREV_BUILD_KIND=$BUILD_KIND"
  echo "BREV_APP_NAME=$APP_NAME"
  echo "BREV_BUNDLE_ID=$BUNDLE_ID"
  echo "BREV_USE_MOCK=${MOCK_MODE:-<unset>}"
  if [[ "$MOCK_MODE" == "1" ]]; then
    echo "BREV_MAIL_BACKEND=mock"
  elif [[ "$MOCK_MODE" == "0" ]]; then
    echo "BREV_MAIL_BACKEND=imap-smtp"
  else
    echo "BREV_MAIL_BACKEND=developer-setting"
  fi
  echo "BREV_MARKETING_VERSION=$marketing_version"
  echo "BREV_LOCAL_BUILD_NUMBER=$local_build_number"
  echo "BREV_LOCAL_SIGNING_IDENTITY=$(local_signing_identity)"
  echo "BREV_TEAM_ID=$(project_team_id)"
  echo "BREV_INSTALL_DIR=$INSTALL_DIR"
  echo "BREV_APP_BUNDLE=$APP_BUNDLE"
  echo "BREV_INSTALLED_APP_BUNDLE=$INSTALLED_APP_BUNDLE"
  local oauth_key
  for oauth_key in \
    BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID \
    BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI \
    BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME \
    BREV_GOOGLE_OAUTH_IOS_CLIENT_ID \
    BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI \
    BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME \
    BREV_MICROSOFT_OAUTH_CLIENT_ID; do
    if configured_value "${!oauth_key:-}"; then
      echo "$oauth_key=set"
    else
      echo "$oauth_key=unset"
    fi
  done
}

preflight() {
  print_config

  if [[ "$BUILD_KIND" == "release" ]]; then
    echo "preflight: release from current origin/main with live IMAP/SMTP ready"
    return 0
  fi

  if [[ "$MOCK_MODE" == "1" ]]; then
    echo "preflight: mock mode ready"
    return 0
  fi

  echo "preflight: live IMAP/SMTP account setup ready"
  if [[ -z "$MOCK_MODE" ]]; then
    echo "preflight: demo startup is controlled by Developer settings"
  fi
  return 0
}

print_live_setup_hint() {
  if [[ ! -f "$ENV_FILE" && -f "$ROOT_DIR/.env.example" ]]; then
    echo "next: run BREV_ENV_FILE=$ENV_FILE $0 --setup-env" >&2
  fi
  echo "next: test builds may use --mock or --live; release Brev.app requires --release-main --live" >&2
}

setup_env_file() {
  local template="$ROOT_DIR/.env.example"

  if [[ -e "$ENV_FILE" ]]; then
    echo "setup-env: $ENV_FILE already exists; leaving it unchanged"
    echo "next: test builds may use --mock or --live; release Brev.app requires --release-main --live"
    return 0
  fi

  if [[ ! -f "$template" ]]; then
    echo "error: missing env template: $template" >&2
    return 1
  fi

  mkdir -p "$(dirname "$ENV_FILE")"
  cp "$template" "$ENV_FILE"
  echo "setup-env: wrote $ENV_FILE"
  echo "next: test builds may use --mock or --live; release Brev.app requires --release-main --live"
}

open_app() {
  local bundle="${1:-$APP_BUNDLE}"
  local args=()
  while IFS= read -r item; do
    args+=("$item")
  done < <(open_env_args)

  warn_live_configuration
  publish_launch_env
  echo "Launching $APP_NAME with BREV_USE_MOCK=${MOCK_MODE:-<unset>} from $bundle..."
  if (( ${#args[@]} > 0 )); then
    /usr/bin/open -n "${args[@]}" "$bundle" --args -ApplePersistenceIgnoreState YES
  else
    /usr/bin/open -n "$bundle" --args -ApplePersistenceIgnoreState YES
  fi
}

install_app() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: built app bundle missing: $APP_BUNDLE" >&2
    return 1
  fi

  if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ]]; then
    echo "error: install target is not a directory: $INSTALL_DIR" >&2
    return 1
  fi

  mkdir -p "$INSTALL_DIR"
  if [[ ! -w "$INSTALL_DIR" ]]; then
    echo "error: install directory is not writable: $INSTALL_DIR" >&2
    echo "hint: set BREV_INSTALL_DIR to a writable folder, for example $HOME/Applications" >&2
    return 1
  fi

  local temp_bundle="$INSTALL_DIR/.$APP_NAME.app.installing.$$"
  rm -rf "$temp_bundle"
  /usr/bin/ditto "$APP_BUNDLE" "$temp_bundle"
  codesign --verify --deep --strict "$temp_bundle" >/dev/null

  rm -rf "$INSTALLED_APP_BUNDLE"
  mv "$temp_bundle" "$INSTALLED_APP_BUNDLE"
  codesign --verify --deep --strict "$INSTALLED_APP_BUNDLE" >/dev/null
  echo "Installed $APP_NAME to $INSTALLED_APP_BUNDLE"
}

wait_for_app_pid() {
  local timeout="$VERIFY_TIMEOUT_SECONDS"
  if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [[ "$timeout" -lt 1 ]]; then
    timeout=10
  fi

  local deadline=$((SECONDS + timeout))
  local pid=""
  while (( SECONDS <= deadline )); do
    pid="$(app_process_pids | head -n 1 || true)"
    if [[ -n "$pid" ]]; then
      printf '%s' "$pid"
      return 0
    fi
    sleep 0.25
  done

  return 1
}

wait_for_app_stability() {
  local pid="$1"
  local duration="$VERIFY_STABILITY_SECONDS"
  if ! [[ "$duration" =~ ^[0-9]+$ ]] || [[ "$duration" -lt 1 ]]; then
    duration=8
  fi

  local deadline=$((SECONDS + duration))
  while (( SECONDS < deadline )); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "error: $APP_NAME exited during the ${duration}s startup stability window" >&2
      return 1
    fi
    sleep 0.25
  done

  return 0
}

debug_app() {
  local args=()
  while IFS= read -r item; do
    args+=("$item")
  done < <(debug_env_args)

  warn_live_configuration
  if (( ${#args[@]} > 0 )); then
    env "${args[@]}" lldb -- "$APP_EXECUTABLE"
  else
    lldb -- "$APP_EXECUTABLE"
  fi
}

parse_args "$@"
configure_build_identity
validate_build_request

if [[ "$MODE" == "print-config" ]]; then
  print_config
  exit 0
fi

if [[ "$MODE" == "preflight" ]]; then
  preflight
  exit $?
fi

if [[ "$MODE" == "setup-env" ]]; then
  setup_env_file
  exit $?
fi

if [[ "$MODE" == "stamp-config" ]]; then
  stamp_built_app_config
  exit $?
fi

kill_running_app
ensure_workspace_dependencies
build_app

case "$MODE" in
  run)
    open_app
    ;;
  install)
    install_app
    ;;
  install-run)
    install_app
    open_app "$INSTALLED_APP_BUNDLE"
    ;;
  debug)
    debug_app
    ;;
  logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  verify)
    open_app
    if ! pid="$(wait_for_app_pid)"; then
      echo "error: $APP_NAME did not stay running after launch" >&2
      exit 1
    fi
    if ! wait_for_app_stability "$pid"; then
      exit 1
    fi
    echo "$APP_NAME is running (pid $pid) after startup verification."
    ;;
  *)
    usage
    exit 2
    ;;
esac
