#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
VERIFY_FIXTURE="$(mktemp -d)"
trap 'rm -rf "$VERIFY_FIXTURE"' EXIT

for entitlements in \
  "$ROOT/apps/macOS/Resources/BrevMacOS.entitlements" \
  "$ROOT/apps/macOS/Resources/BrevMacOSRelease.entitlements" \
  "$ROOT/apps/iOS/Resources/BrevIOS.entitlements"; do
  if [[ ! -f "$entitlements" ]]; then
    echo "test-remote-push-retired.sh: missing ${entitlements#$ROOT/}" >&2
    exit 1
  fi
  for key in aps-environment com.apple.developer.aps-environment; do
    if "$PLIST_BUDDY" -c "Print :$key" "$entitlements" >/dev/null 2>&1; then
      echo "test-remote-push-retired.sh: ${entitlements#$ROOT/} still contains $key" >&2
      exit 1
    fi
  done
done

for retired_file in \
  "$ROOT/apps/macOS/Resources/BrevMacOSPush.entitlements" \
  "$ROOT/packages/BrevBackend/Sources/BrevBackend/APNSTokenStore.swift" \
  "$ROOT/packages/BrevBackend/Tests/BrevBackendTests/PushNotificationRegistrationPolicyTests.swift" \
  "$ROOT/packages/BrevBackend/Tests/BrevBackendTests/RemotePushRegistrationCoordinatorPolicyTests.swift" \
  "$ROOT/scripts/test-macos-push-entitlements.sh" \
  "$ROOT/scripts/test-ios-push-entitlements.sh" \
  "$ROOT/scripts/verify-ios-apns-app.sh"; do
  if [[ -e "$retired_file" ]]; then
    echo "test-remote-push-retired.sh: retired file remains at ${retired_file#$ROOT/}" >&2
    exit 1
  fi
done

if rg -n \
  'registerForRemoteNotifications|didRegisterForRemoteNotificationsWithDeviceToken|APNSTokenStore|PushNotificationRegistering|PushRegistrationCoordinator|RemotePushCoordinator|RemotePushRegistrationCoordinator|PushNotificationRegistrationPolicy|\.pushNotifications' \
  "$ROOT/apps" "$ROOT/packages" \
  --glob '*.swift' --glob '!**/.build/**'; then
  echo "test-remote-push-retired.sh: production or test Swift still references remote push" >&2
  exit 1
fi

if rg -n 'BrevMacOSPush|BREV_APS_ENVIRONMENT' \
  "$ROOT/apps" "$ROOT/script" "$ROOT/scripts" \
  --glob '!test-remote-push-retired.sh'; then
  echo "test-remote-push-retired.sh: build tooling still references remote push configuration" >&2
  exit 1
fi

mkdir -p "$VERIFY_FIXTURE/Brev.app/Contents" "$VERIFY_FIXTURE/bin"
cat >"$VERIFY_FIXTURE/Brev.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>eu.brevmail.brev</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>3</string>
</dict>
</plist>
EOF
cat >"$VERIFY_FIXTURE/bin/codesign" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--verify" ]]; then
  exit 0
fi
if [[ "${1:-}" == "-d" ]]; then
  exit 1
fi
exit 1
EOF
chmod +x "$VERIFY_FIXTURE/bin/codesign"

if verify_output="$(
  PATH="$VERIFY_FIXTURE/bin:$PATH" \
    "$ROOT/scripts/release-installed-verify.sh" \
    --app-path "$VERIFY_FIXTURE/Brev.app" \
    --skip-gatekeeper 2>&1
)"; then
  echo "test-remote-push-retired.sh: entitlement inspection failure unexpectedly passed" >&2
  exit 1
fi
if [[ "$verify_output" != *"could not inspect embedded entitlements"* ]]; then
  echo "test-remote-push-retired.sh: entitlement inspection failure was not diagnosed" >&2
  exit 1
fi

echo "test-remote-push-retired.sh: OK"
