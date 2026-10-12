#!/usr/bin/env bash
# Exercise release-ios-beta.sh against fake Xcode, git and Node tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/brev-ios-beta-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/scripts" "$WORK/bin" "$WORK/home" "$WORK/packages/BrevMail" \
  "$WORK/Tuist/ProjectDescriptionHelpers"
cp "$ROOT/scripts/release-ios-beta.sh" \
  "$ROOT/scripts/export-options-testflight-internal.plist" \
  "$ROOT/scripts/export-options-testflight-external.plist" "$WORK/scripts/"
printf '    public static let marketingVersion = "1.2.3"\n' \
  > "$WORK/Tuist/ProjectDescriptionHelpers/BrevConstants.swift"

export TEST_LOG="$WORK/calls.log"
CLIENT_ID="1234-abc.apps.googleusercontent.com"
API_KEY="test-api-key-value"

# The gates and workspace generation have their own tests.
for gate in test-apple-team-config test-ios-privacy-manifest test-testflight-export-options; do
  # shellcheck disable=SC2016
  printf '#!/bin/bash\necho "%s" >> "$TEST_LOG"\n' "$gate" > "$WORK/scripts/$gate.sh"
done
cat > "$WORK/scripts/prepare-xcode-workspace.sh" <<'SH'
#!/bin/bash
echo "prepare client-id-in-env=${BREV_GOOGLE_OAUTH_IOS_CLIENT_ID:-unset} api-key-in-env=${BREV_GOOGLE_API_KEY:-unset}" >> "$TEST_LOG"
SH
printf '#!/bin/bash\necho "platform=iOS Simulator,OS=27.0,name=iPhone"\n' \
  > "$WORK/scripts/ios-simulator-destination.sh"
chmod +x "$WORK/scripts/"*.sh

cat > "$WORK/bin/git" <<'SH'
#!/bin/bash
echo "git $*" >> "$TEST_LOG"
case "$1" in
  status) [[ -z "${TEST_DIRTY:-}" ]] || echo " M README.md" ;;
  rev-parse) echo "abc1234" ;;
esac
SH
cat > "$WORK/bin/xcodebuild" <<'SH'
#!/bin/bash
set -eu
echo "xcodebuild $*" >> "$TEST_LOG"
mode=""; archive=""; xcconfig=""; version=""; build="1"; export_plist=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    archive) mode=archive ;;
    -exportArchive) mode=export ;;
    -archivePath) archive="${args[i + 1]}" ;;
    -xcconfig) xcconfig="${args[i + 1]}" ;;
    -exportOptionsPlist) export_plist="${args[i + 1]}" ;;
    MARKETING_VERSION=*) version="${args[i]#*=}" ;;
    CURRENT_PROJECT_VERSION=*) build="${args[i]#*=}" ;;
  esac
done
setting() { sed -n "s/^$1 = //p" "$xcconfig"; }
case "$mode" in
  archive)
    echo "xcconfig mode=$(stat -f %Lp "$xcconfig")" >> "$TEST_LOG"
    app="$archive/Products/Applications/BrevIOS.app"
    mkdir -p "$app"
    touch "$app/PrivacyInfo.xcprivacy"
    client_id="$(setting BREV_GOOGLE_OAUTH_IOS_CLIENT_ID)"
    [[ -z "${TEST_DROP_CLIENT_ID:-}" ]] || client_id=""
    cat > "$app/Info.plist" <<PLIST
<plist version="1.0"><dict>
<key>BREVGoogleOAuthIOSClientID</key><string>$client_id</string>
<key>BREVGoogleOAuthIOSCallbackScheme</key><string>$(setting BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME)</string>
</dict></plist>
PLIST
    cat > "$archive/Info.plist" <<PLIST
<plist version="1.0"><dict><key>ApplicationProperties</key><dict>
<key>CFBundleIdentifier</key><string>eu.brevmail.brev.ios</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build</string>
</dict></dict></plist>
PLIST
    ;;
  export)
    internal="$(plutil -extract testFlightInternalTestingOnly raw -o - "$export_plist" 2>/dev/null || echo absent)"
    echo "export destination=$(plutil -extract destination raw -o - "$export_plist") internal-only=$internal" >> "$TEST_LOG"
    ;;
esac
SH
for tool in swift security codesign node; do
  # shellcheck disable=SC2016
  printf '#!/bin/bash\necho "%s $*" >> "$TEST_LOG"\n' "$tool" > "$WORK/bin/$tool"
done
chmod +x "$WORK/bin/"*

export PATH="$WORK/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export BREV_IOS_RELEASE_HOME="$WORK/home"

write_release_env() {
  touch "$WORK/home/AuthKey.p8"
  cat > "$WORK/home/release.env" <<ENV
ASC_KEY_ID=TESTKEY
ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
ASC_KEY_PATH=$WORK/home/AuthKey.p8
TESTFLIGHT_EXTERNAL_GROUP="Public Beta"
BREV_GOOGLE_OAUTH_IOS_CLIENT_ID=$CLIENT_ID
BREV_GOOGLE_API_KEY=$API_KEY
ENV
}

release() {
  : > "$TEST_LOG"
  bash "$WORK/scripts/release-ios-beta.sh" --current-checkout "$@" > "$WORK/out.log" 2>&1
}

expect_success() {
  release "$@" || {
    echo "ERROR: release failed for: $*" >&2
    cat "$WORK/out.log" >&2
    exit 1
  }
}

expect_failure() {
  local expected="$1"
  shift
  if release "$@"; then
    echo "ERROR: expected failure ($expected) for: $*" >&2
    exit 1
  fi
  grep -Fq -- "$expected" "$WORK/out.log" || {
    echo "ERROR: missing '$expected' in:" >&2
    cat "$WORK/out.log" >&2
    exit 1
  }
}

expect_logged() {
  grep -Fq -- "$1" "$TEST_LOG" || {
    echo "ERROR: expected call '$1'; got:" >&2
    cat "$TEST_LOG" >&2
    exit 1
  }
}

expect_not_logged() {
  if grep -Fq -- "$1" "$TEST_LOG"; then
    echo "ERROR: unexpected call '$1'" >&2
    exit 1
  fi
}

# Nothing is built, and no build number is taken, until the inputs are complete.
write_release_env
expect_failure "--notes" --dry-run
expect_not_logged "xcodebuild"

grep -v '^BREV_GOOGLE_OAUTH_IOS_CLIENT_ID=' "$WORK/home/release.env" > "$WORK/home/release.env.tmp"
mv "$WORK/home/release.env.tmp" "$WORK/home/release.env"
expect_failure "BREV_GOOGLE_OAUTH_IOS_CLIENT_ID" --notes "Test"
expect_not_logged "xcodebuild"
[[ ! -e "$WORK/home/build-number" ]]

write_release_env
TEST_DIRTY=1 expect_failure "local changes" --notes "Test"
[[ ! -e "$WORK/home/build-number" ]]

# A dry run signs and exports locally: no upload, no build number, no follow-up.
expect_success --notes "Test" --dry-run
expect_logged "export destination=export internal-only=absent"
expect_not_logged "node "
expect_not_logged "CURRENT_PROJECT_VERSION="
[[ ! -e "$WORK/home/build-number" ]]
[[ ! -e "$WORK/home/release.lock" ]]

# Provider settings reach the archive through a private xcconfig only: never
# the generated project, never the log.
expect_logged "prepare client-id-in-env=unset api-key-in-env=unset"
expect_logged "xcconfig mode=600"
if grep -Fq -e "$CLIENT_ID" -e "$API_KEY" "$WORK/out.log" "$TEST_LOG"; then
  echo "ERROR: a provider setting was printed" >&2
  exit 1
fi

# A release takes the next build number and can reach the external group.
expect_success --notes "What to test"
[[ "$(cat "$WORK/home/build-number")" == "100" ]]
expect_logged "MARKETING_VERSION=1.2.3 CURRENT_PROJECT_VERSION=100"
expect_logged "swift test -c release"
expect_logged "export destination=upload internal-only=absent"
expect_logged "node scripts/testflight-distribute.mjs --bundle-id eu.brevmail.brev.ios --version 1.2.3 --build-number 100 --notes What to test --group Public Beta"
grep -q '"buildNumber": 100' "$WORK/home/last-release.json"

# An internal-only build skips the external guard and never joins that group.
expect_success --notes "Internal" --internal-only
[[ "$(cat "$WORK/home/build-number")" == "101" ]]
expect_logged "export destination=upload internal-only=true"
expect_not_logged "swift test"
expect_not_logged "--group"

# An archive without the sign-in configuration is not uploaded.
TEST_DROP_CLIENT_ID=1 expect_failure "did not reach the archived app" --notes "Test"
expect_not_logged "-exportArchive"
expect_not_logged "node "

echo "test-release-ios-beta.sh: OK"
