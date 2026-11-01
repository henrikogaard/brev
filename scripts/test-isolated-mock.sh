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

python3 - "$ROOT/apps/macOS/Resources/BrevMacOSMock.entitlements" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as handle:
    assert plistlib.load(handle) == {'com.apple.security.app-sandbox': True}
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
mock_entitlements="$ROOT/apps/macOS/Resources/BrevMacOSMock.entitlements"
codesign() {
  if [[ "$1" == '--verify' ]]; then
    return "$signature_status"
  fi
  cat "$mock_entitlements"
}
eval "$(sed -n '/^verify_isolated_mock_bundle() {/,/^}/p' "$SCRIPT")"
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
