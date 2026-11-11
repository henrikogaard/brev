#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/script/build_and_run.sh"

config="$(BREV_ENV_FILE=/dev/null /bin/bash "$SCRIPT" --isolated-mock --print-config)"
grep -Eq '^BREV_BUNDLE_ID=eu\.brevmail\.brev\.test\.mock\.[0-9A-F-]{36}$' <<<"$config"
grep -Fxq 'BREV_USE_MOCK=1' <<<"$config"
grep -Fxq 'BREV_BUILD_KIND=test' <<<"$config"
grep -Fq '/isolated-mock/' <<<"$config"
second="$(BREV_ENV_FILE=/dev/null /bin/bash "$SCRIPT" --isolated-mock --print-config)"
[[ "$(grep '^BREV_BUNDLE_ID=' <<<"$config")" != "$(grep '^BREV_BUNDLE_ID=' <<<"$second")" ]]
grep -Fxq 'BREV_ISOLATED_MOCK_PROFILE=strict' <<<"$config"
content_config="$(BREV_ENV_FILE=/dev/null /bin/bash "$SCRIPT" --isolated-mock-content-qa --print-config)"
grep -Fxq 'BREV_ISOLATED_MOCK_PROFILE=content-qa' <<<"$content_config"
grep -Fxq 'BREV_ISOLATED_MOCK=1' <<<"$content_config"
grep -Fxq 'BREV_USE_MOCK=1' <<<"$content_config"
grep -Fxq 'BREV_BUILD_KIND=test' <<<"$content_config"
grep -Eq '^BREV_BUNDLE_ID=eu\.brevmail\.brev\.test\.mock\.[0-9A-F-]{36}$' <<<"$content_config"
for arguments in '--live --print-config' '--release-main --print-config' 'install' 'install-run' '--stamp-config'; do
  if BREV_ENV_FILE=/dev/null /bin/bash "$SCRIPT" --isolated-mock-content-qa $arguments >/dev/null 2>&1; then
    echo "content QA unexpectedly accepted $arguments" >&2
    exit 1
  fi
done

for arguments in '--live --print-config' '--release-main --print-config' 'install' 'install-run' '--stamp-config'; do
  # Intentional word splitting: fixed argument fixtures, never user input.
  if BREV_ENV_FILE=/dev/null /bin/bash "$SCRIPT" --isolated-mock $arguments >/dev/null 2>&1; then
    echo "isolated mock unexpectedly accepted $arguments" >&2
    exit 1
  fi
done

if BREV_ENV_FILE=/dev/null /bin/bash "$SCRIPT" --build-only >/dev/null 2>&1; then
  echo 'build-only unexpectedly accepted without isolation' >&2
  exit 1
fi

python3 - "$ROOT/apps/macOS/Resources/BrevMacOSMock.entitlements" "$ROOT/apps/macOS/Resources/BrevMacOSMockContentQA.entitlements" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as handle:
    assert plistlib.load(handle) == {'com.apple.security.app-sandbox': True}
with open(sys.argv[2], 'rb') as handle:
    assert plistlib.load(handle) == {
        'com.apple.security.app-sandbox': True,
        'com.apple.security.network.client': True,
        'com.apple.security.files.user-selected.read-only': True,
    }
PY

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/brev-isolated-mock.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
APP_BUNDLE="$FIXTURE/Mock.app"
BUNDLE_ID='eu.brevmail.brev.test.mock.4DE6C7C8-FB92-4EE3-AFC1-B7C1A6E57948'
mkdir -p "$APP_BUNDLE/Contents"
python3 - "$APP_BUNDLE/Contents/Info.plist" "$BUNDLE_ID" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'wb') as handle:
    plistlib.dump({'CFBundleIdentifier': sys.argv[2], 'BRBuildKind': 'test', 'BRIsolatedMock': '1'}, handle)
PY

# Exercise guard control flow without signing or launching a real app.
signature_status=0
ISOLATED_MOCK_PROFILE=strict
mock_entitlements="$ROOT/apps/macOS/Resources/BrevMacOSMock.entitlements"
codesign() {
  if [[ "$1" == '--verify' ]]; then
    return "$signature_status"
  fi
  cat "$mock_entitlements"
}
eval "$(sed -n '/^verify_isolated_mock_bundle() {/,/^}/p' "$SCRIPT")"
verify_isolated_mock_bundle
expect_rejected() {
  if verify_isolated_mock_bundle >/dev/null 2>&1; then
    echo "unexpected acceptance: $1" >&2
    exit 1
  fi
}

eval "$(sed -n '/^plist_set_string() {/,/^}/p' "$SCRIPT")"
eval "$(sed -n '/^plist_delete_key_if_present() {/,/^}/p' "$SCRIPT")"
eval "$(sed -n '/^stamp_built_app_config() {/,/^}/p' "$SCRIPT")"
eval "$(sed -n '/^macos_entitlements_path() {/,/^}/p' "$SCRIPT")"
MACOS_MOCK_ENTITLEMENTS="$ROOT/apps/macOS/Resources/BrevMacOSMock.entitlements"
MACOS_MOCK_CONTENT_ENTITLEMENTS="$ROOT/apps/macOS/Resources/BrevMacOSMockContentQA.entitlements"
MACOS_ENTITLEMENTS="$ROOT/apps/macOS/Resources/BrevMacOS.entitlements"
MACOS_RELEASE_ENTITLEMENTS="$ROOT/apps/macOS/Resources/BrevMacOSRelease.entitlements"
ISOLATED_MOCK_REQUESTED=1
APP_NAME='Brev Test (QA Fixture)'
BUILD_KIND=test
TEST_BUILD_DATE=2026-11-02
MOCK_MODE=1
for profile in strict content-qa; do
  ISOLATED_MOCK_PROFILE="$profile"
  stamp_built_app_config
  mock_entitlements="$(macos_entitlements_path)"
  verify_isolated_mock_bundle
  # Reject missing, disabled, nonboolean and additional permissions in either profile.
  python3 - "$mock_entitlements" "$FIXTURE" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as handle:
    expected = plistlib.load(handle)
invalid = []
for key in expected:
    missing = dict(expected)
    del missing[key]
    invalid.append(missing)
    for value in [False, 'true', 1]:
        invalid.append({**expected, key: value})
for extra in [
    'com.apple.security.application-groups', 'com.apple.security.network.server',
    'com.apple.security.files.user-selected.read-write', 'keychain-access-groups',
    'com.apple.security.personal-information.addressbook',
    'com.apple.security.personal-information.calendars',
    'com.apple.developer.ubiquity-kvstore-identifier',
]:
    invalid.append({**expected, extra: True})
for index, permissions in enumerate(invalid):
    with open(f'{sys.argv[2]}/invalid-{index}.plist', 'wb') as handle:
        plistlib.dump(permissions, handle)
PY
  for permissions in "$FIXTURE"/invalid-*.plist; do
    mock_entitlements="$permissions"
    expect_rejected "$profile $permissions"
  done
  mock_entitlements="$(macos_entitlements_path)"
  for marker in unknown ''; do
    plist_set_string "$APP_BUNDLE/Contents/Info.plist" BRIsolatedMockProfile "$marker"
    expect_rejected 'unknown profile marker'
  done
  plist_set_string "$APP_BUNDLE/Contents/Info.plist" BRIsolatedMockProfile "$profile"
done

ISOLATED_MOCK_PROFILE=strict
expect_rejected 'content bundle with strict build request'
stamp_built_app_config
expect_rejected 'content permissions with strict bundle marker'
mock_entitlements="$MACOS_MOCK_ENTITLEMENTS"
ISOLATED_MOCK_PROFILE=content-qa
stamp_built_app_config
expect_rejected 'strict permissions with content bundle marker'
ISOLATED_MOCK_PROFILE=strict
stamp_built_app_config

ISOLATED_MOCK_REQUESTED=0
stamp_built_app_config
if /usr/libexec/PlistBuddy -c 'Print :BRIsolatedMockProfile' "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
  echo 'ordinary mock retained the isolated profile marker' >&2
  exit 1
fi
[[ "$(macos_entitlements_path)" == "$MACOS_ENTITLEMENTS" ]]
BUILD_KIND=release
[[ "$(macos_entitlements_path)" == "$MACOS_RELEASE_ENTITLEMENTS" ]]
BUILD_KIND=test
ISOLATED_MOCK_REQUESTED=1
stamp_built_app_config
verify_isolated_mock_bundle
signature_status=1
if verify_isolated_mock_bundle >/dev/null 2>&1; then
  echo 'invalid signature was accepted' >&2
  exit 1
fi
signature_status=0
mock_entitlements="$ROOT/apps/macOS/Resources/BrevMacOS.entitlements"
if verify_isolated_mock_bundle >/dev/null 2>&1; then
  echo 'production entitlements were accepted' >&2
  exit 1
fi
mock_entitlements="$ROOT/apps/macOS/Resources/BrevMacOSMock.entitlements"
/usr/libexec/PlistBuddy -c 'Delete :BRIsolatedMock' "$APP_BUNDLE/Contents/Info.plist"
if verify_isolated_mock_bundle >/dev/null 2>&1; then
  echo 'missing isolation marker was accepted' >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Add :BRIsolatedMock string 1' "$APP_BUNDLE/Contents/Info.plist"
mkdir "$APP_BUNDLE/Contents/PlugIns"
if verify_isolated_mock_bundle >/dev/null 2>&1; then
  echo 'embedded extensions were accepted' >&2
  exit 1
fi

echo 'test-isolated-mock.sh: OK'
