#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ENV="$(mktemp)"
TMP_SETUP_ENV="$(mktemp -u)"
TMP_APP_BUNDLE="$(mktemp -d)"
TMP_ISSUE_120_TEMPLATE=""
trap 'rm -f "$TMP_ENV" "$TMP_SETUP_ENV" "$TMP_ISSUE_120_TEMPLATE"; rm -rf "$TMP_APP_BUNDLE"' EXIT

unset BREV_USE_MOCK BREV_TEST_DATE
unset BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME
unset BREV_GOOGLE_OAUTH_IOS_CLIENT_ID BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME
unset BREV_GOOGLE_OAUTH_CLIENT_ID BREV_GOOGLE_OAUTH_CLIENT_SECRET BREV_GOOGLE_OAUTH_ALLOW_LEGACY_FALLBACK BREV_LOCAL_QA BREV_MICROSOFT_OAUTH_CLIENT_ID
unset BREV_LIVE_MAIL_EMAIL BREV_LIVE_MAIL_PASSWORD BREV_LIVE_IMAP_HOST BREV_LIVE_SMTP_HOST BREV_LIVE_SMOKE_SEND_TO

if [[ ! -x "$ROOT/script/build_and_run.sh" ]]; then
  echo "expected desktop run script to be executable" >&2
  exit 1
fi

if [[ ! -x "$ROOT/scripts/imap-smtp-live-smoke.sh" ]]; then
  echo "expected IMAP/SMTP live smoke script to be executable" >&2
  exit 1
fi

if [[ ! -x "$ROOT/scripts/imap-autodiscovery-smoke.sh" ]]; then
  echo "expected IMAP autodiscovery smoke script to be executable" >&2
  exit 1
fi

if [[ ! -x "$ROOT/scripts/imap-smtp-local-smoke.sh" ]]; then
  echo "expected local IMAP/SMTP mailbox smoke script to be executable" >&2
  exit 1
fi

for app_source in "$ROOT/apps/macOS/Sources/BrevApp.swift" "$ROOT/apps/iOS/Sources/BrevApp.swift"; do
  if ! grep -q 'AppSessionFactory.makeDefault' "$app_source"; then
    echo "expected $app_source to use the shared production session factory" >&2
    exit 1
  fi
done

session_factory_source="$ROOT/packages/BrevMail/Sources/BrevMail/AppSessionFactory.swift"
# The platform targets delegate persistent connector construction to the shared
# factory. Keep this check at the actual ownership seam so refactors cannot make
# the production-wiring test silently stale.
if ! grep -q 'IMAPAccountConnector.standard' "$session_factory_source" ||
    ! grep -q 'FileIMAPDraftStagingStore' "$session_factory_source" ||
    ! grep -q 'OfflineMutationQueueStorage.queue' "$session_factory_source" ||
    ! grep -q 'OfflineMutationQueueStorage.conflictStore' "$session_factory_source"; then
  echo "expected $session_factory_source to wire the full production IMAP/SMTP connector" >&2
  exit 1
fi

standard_connector_source="$ROOT/packages/BrevBackend/Sources/BrevBackend/StandardIMAPAccountConnector.swift"
if ! grep -q 'NetworkIMAPSessionTransport' "$standard_connector_source" ||
    ! grep -q 'NetworkSMTPSessionTransport' "$standard_connector_source" ||
    ! grep -q 'FileBackedIMAPMessageSourceCache' "$standard_connector_source" ||
    ! grep -q 'loginAndListFolders' "$standard_connector_source" ||
    ! grep -q 'loginAndCreateFolder' "$standard_connector_source" ||
    ! grep -q 'loginAndRenameFolder' "$standard_connector_source" ||
    ! grep -q 'loginAndDeleteFolder' "$standard_connector_source" ||
    ! grep -q 'loginAndListMessages' "$standard_connector_source" ||
    ! grep -q 'loginAndSearchMessages' "$standard_connector_source" ||
    ! grep -q 'loginAndFetchMessageSource' "$standard_connector_source" ||
    ! grep -q 'loginAndSetMessageFlag' "$standard_connector_source" ||
    ! grep -q 'loginAndMoveMessages' "$standard_connector_source" ||
    ! grep -q 'loginAndPermanentlyDeleteMessages' "$standard_connector_source" ||
    ! grep -q 'loginAndValidateCredentials' "$standard_connector_source" ||
    ! grep -q 'loginAndSubmitMessage' "$standard_connector_source" ||
    ! grep -q 'appendDraftMessage' "$standard_connector_source" ||
    ! grep -q 'loginAndIdleEvents' "$standard_connector_source"; then
  echo "expected StandardIMAPAccountConnector to wire production IMAP/SMTP transports and operations" >&2
  exit 1
fi

if ! grep -q 'IMAPAccountConnector(' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'provisionAndConnect' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.messages(' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.search(' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'allFoldersQuery' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.body(for:' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.send(draft:' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.setRead' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.setFlagged' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.move' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.delete' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'loginAndSetMessageFlag' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'loginAndMoveMessages' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.createFolder' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.renameFolder' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.deleteFolder' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.flushFolder' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'SyncHealthRepairing' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BrevSyncEngine(databaseURL:' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BREV_LIVE_SMOKE_ENABLE_CROSS_FOLDER_SERVER_SEARCH' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BREV_LIVE_SMOKE_ENABLE_FULL_INDEX' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'loginAndValidateCredentials' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.uploadAttachment' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.save(draft:' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'backend.discard' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'appendDraftMessage' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'permanentlyDeleteMessages' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--daily-driver' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--exercise-folder-management' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--exercise-folder-flush' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--validate-smtp-setup' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--exercise-server-search' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--exercise-cross-folder-server-search' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--exercise-full-index' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--exercise-message-mutations' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--exercise-compose-lifecycle' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q -- '--require-attachment-download' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BREV_LIVE_SMOKE_ENABLE_MESSAGE_MUTATIONS' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BREV_LIVE_SMOKE_ENABLE_FOLDER_FLUSH' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BREV_LIVE_SMOKE_ENABLE_SMTP_SETUP_VALIDATION' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BREV_LIVE_SMOKE_ENABLE_SERVER_SEARCH' "$ROOT/scripts/imap-smtp-live-smoke.sh" ||
    ! grep -q 'BREV_LIVE_SMOKE_REQUIRE_ATTACHMENT' "$ROOT/scripts/imap-smtp-live-smoke.sh"; then
  echo "expected IMAP/SMTP live smoke to exercise app-facing account setup, mailbox, body, server search, cross-folder server search, full local index rebuild/search, message mutations, folder management/flush, compose lifecycle, and send paths" >&2
  exit 1
fi

smoke_output="$("$ROOT/scripts/imap-smtp-live-smoke.sh" 2>&1)"
case "$smoke_output" in
  *"imap-smtp-live-smoke: skipped"* ) ;;
  * )
    echo "expected IMAP/SMTP live smoke to skip cleanly without credentials" >&2
    exit 1
    ;;
esac

if ! grep -q 'MailAccountAutodiscoveryResolver.system' "$ROOT/scripts/imap-autodiscovery-smoke.sh" ||
    ! grep -q 'resolver.resolve(forEmailAddress:' "$ROOT/scripts/imap-autodiscovery-smoke.sh" ||
    ! grep -q -- '--compile-only' "$ROOT/scripts/imap-autodiscovery-smoke.sh"; then
  echo "expected IMAP autodiscovery smoke to exercise system resolver discovery" >&2
  exit 1
fi

# --compile-only is now a legacy alias that compiles *and* runs the provider
# matrix (a strict superset of the old compile-only check), emitting "matrix OK".
autodiscovery_output="$("$ROOT/scripts/imap-autodiscovery-smoke.sh" --compile-only 2>&1)"
case "$autodiscovery_output" in
  *"imap-autodiscovery-smoke: matrix OK"* ) ;;
  * )
    echo "expected IMAP autodiscovery smoke compile/matrix check to pass" >&2
    exit 1
    ;;
esac

if ! grep -q 'IMAPAccountConnector(' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'provisionAndConnect' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'persistentSmokeDefaults' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'persistentSmokeCredentialService' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'cachedFolderRestoreBackend' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'cachedMessagePage' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'freshConnectorRestoredBackend' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'validateOutgoingServer' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedFolders' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.messages(' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedPage' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedRefreshEvents' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'idleMessagesAddedEvent' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.search(' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedSearchResults' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.body(for:' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedBody' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.downloadAttachment' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'cachedSourceBody' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedAttachmentData' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.setRead' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.setFlagged' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.move' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.delete' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedMutationCalls' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.flushFolder' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'sourceScopedFolderMutationCalls' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.createFolder' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.renameFolder' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.deleteFolder' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.uploadAttachment' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.save(' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.discard' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'appendDraftMessage' "$ROOT/scripts/imap-smtp-local-smoke.sh" ||
    ! grep -q 'backend.send(draft:' "$ROOT/scripts/imap-smtp-local-smoke.sh"; then
  echo "expected local IMAP/SMTP mailbox smoke to exercise add, persistent-store and Keychain-backed fresh connector restore, cached-folder, message-page, and source/body restore during listing outage, source-scoped list/refresh/message pages, IDLE new-mail refresh, source-scoped server search/body/attachment reads, attachment upload, source-scoped read/flag/move/delete, source-scoped folder create/rename/delete/flush, Drafts append/discard, and send" >&2
  exit 1
fi

local_smoke_output="$("$ROOT/scripts/imap-smtp-local-smoke.sh" 2>&1)"
case "$local_smoke_output" in
  *"imap-smtp-local-smoke: OK"* ) ;;
  * )
    echo "expected local IMAP/SMTP mailbox smoke to pass" >&2
    exit 1
    ;;
esac

if [[ ! -f "$ROOT/.codex/environments/environment.toml" ]]; then
  echo "expected Codex environment file to exist" >&2
  exit 1
fi

case "$(cat "$ROOT/.codex/environments/environment.toml")" in
  *'command = "./script/build_and_run.sh"'* ) ;;
  * )
    echo "expected Codex Run action to launch ./script/build_and_run.sh" >&2
    exit 1
    ;;
esac

cat >"$TMP_ENV" <<'EOF'
# Comments and simple quoting are accepted.
PATH=/does/not/exist
export BREV_USE_MOCK = "1"
BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID = "desktop.apps.googleusercontent.com"
BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI = "http://127.0.0.1"
BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME = "http"
BREV_GOOGLE_OAUTH_IOS_CLIENT_ID = "123.apps.googleusercontent.com"
BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME = "com.googleusercontent.apps.123"
BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI = "com.googleusercontent.apps.123:/oauth2redirect"
BREV_MICROSOFT_OAUTH_CLIENT_ID = "microsoft-client-id"
BREV_GOOGLE_OAUTH_CLIENT_SECRET = "must-not-be-printed"
EOF

output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    BREV_TEST_DATE="2026-08-02" \
    "$ROOT/script/build_and_run.sh" --print-config --live 2>&1
)"

case "$output" in
  *"warning: ignoring unsupported env key"*"PATH"* ) ;;
  * )
    echo "expected unsupported PATH assignment to be ignored" >&2
    exit 1
    ;;
esac

case "$output" in
  *"BREV_ENV_FILE=$TMP_ENV"* ) ;;
  * )
    echo "expected print-config output to include BREV_ENV_FILE=$TMP_ENV" >&2
    exit 1
    ;;
esac

case "$output" in
  *"BREV_USE_MOCK=0"* ) ;;
  * )
    echo "expected --live to override BREV_USE_MOCK from the env file" >&2
    exit 1
    ;;
esac

for oauth_status in \
  'BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID=set' \
  'BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI=set' \
  'BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME=set' \
  'BREV_GOOGLE_OAUTH_IOS_CLIENT_ID=set' \
  'BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI=set' \
  'BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME=set' \
  'BREV_MICROSOFT_OAUTH_CLIENT_ID=set'; do
  if [[ "$output" != *"$oauth_status"* ]]; then
    echo "expected .env.local OAuth assignment to be loaded: $oauth_status" >&2
    exit 1
  fi
done

if [[ "$output" == *"must-not-be-printed"* ]] || [[ "$output" == *"BREV_GOOGLE_OAUTH_CLIENT_SECRET="* ]]; then
  echo "expected Google client secret to remain absent from --print-config output" >&2
  exit 1
fi

case "$output" in
  *"BREV_MAIL_BACKEND=imap-smtp"* ) ;;
  * )
    echo "expected live mode to report the standards-first IMAP/SMTP backend" >&2
    exit 1
    ;;
esac

case "$output" in
  *"BREV_BUILD_KIND=test"*"BREV_APP_NAME=Brev Test (2026-08-02)"* ) ;;
  * )
    echo "expected ordinary local builds to use the dated Brev Test identity" >&2
    exit 1
    ;;
esac

case "$output" in
  *"BREV_BUNDLE_ID=eu.brevmail.brev.test.d20260802"*"BREV_INSTALLED_APP_BUNDLE=/Applications/Brev Test (2026-08-02).app"* ) ;;
  * )
    echo "expected test builds to use a date-isolated bundle id and dated install path" >&2
    exit 1
    ;;
esac

if [[ "$output" == *"BREV_INSTALLED_APP_BUNDLE=/Applications/Brev.app"* ]]; then
  echo "test builds must never target the daily-driver Brev.app" >&2
  exit 1
fi

set +e
invalid_date_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    BREV_TEST_DATE="August-2" \
    "$ROOT/script/build_and_run.sh" --print-config --mock 2>&1
)"
invalid_date_status=$?
set -e
if [[ $invalid_date_status -eq 0 ]] ||
    [[ "$invalid_date_output" != *"BREV_TEST_DATE must use YYYY-MM-DD"* ]]; then
  echo "expected test builds to reject non-date bundle names" >&2
  exit 1
fi

set +e
bundle_override_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    BREV_TEST_DATE="2026-08-02" \
    BREV_APP_BUNDLE="/Applications/Brev.app" \
    "$ROOT/script/build_and_run.sh" --print-config --mock 2>&1
)"
bundle_override_status=$?
set -e
if [[ $bundle_override_status -eq 0 ]] ||
    [[ "$bundle_override_output" != *"BREV_APP_BUNDLE override is allowed only with --stamp-config"* ]]; then
  echo "expected test builds to reject app-bundle path overrides" >&2
  exit 1
fi

release_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    BREV_TEST_DATE="2026-08-02" \
    "$ROOT/script/build_and_run.sh" --print-config --release-main --live 2>&1
)"

case "$release_output" in
  *"BREV_BUILD_KIND=release"*"BREV_APP_NAME=Brev"*"BREV_BUNDLE_ID=eu.brevmail.brev"*"BREV_INSTALLED_APP_BUNDLE=/Applications/Brev.app"* ) ;;
  * )
    echo "expected explicit release-main config to target the daily-driver Brev.app" >&2
    exit 1
    ;;
esac

set +e
release_mock_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    "$ROOT/script/build_and_run.sh" --preflight --release-main --mock 2>&1
)"
release_mock_status=$?
set -e
if [[ $release_mock_status -eq 0 ]] ||
    [[ "$release_mock_output" != *"release-main builds require live mail and reject --mock"* ]]; then
  echo "expected release-main to reject placeholder mailbox mode" >&2
  exit 1
fi

set +e
release_branch_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    "$ROOT/script/build_and_run.sh" --preflight --release-main --live 2>&1
)"
release_branch_status=$?
set -e
if [[ $release_branch_status -eq 0 ]] || {
    [[ "$release_branch_output" != *"release-main builds require the main branch"* ]] &&
        [[ "$release_branch_output" != *"release-main checkout is stale or diverged from origin/main"* ]]
}; then
    echo "expected release-main to reject non-main checkouts" >&2
    exit 1
fi

if grep -Eq '^[[:space:]]+PRODUCT_NAME="\$APP_NAME"$' "$ROOT/script/build_and_run.sh" ||
    grep -Eq '^[[:space:]]+PRODUCT_BUNDLE_IDENTIFIER="\$BUNDLE_ID"$' "$ROOT/script/build_and_run.sh"; then
  echo "expected test identity overrides not to rename every Swift package target" >&2
  exit 1
fi

if ! grep -Fq 'BREV_APP_PRODUCT_NAME="$APP_NAME"' "$ROOT/script/build_and_run.sh" ||
    ! grep -Fq 'BREV_APP_BUNDLE_ID="$BUNDLE_ID"' "$ROOT/script/build_and_run.sh" ||
    ! grep -Fq '"PRODUCT_NAME": "$(BREV_APP_PRODUCT_NAME)"' "$ROOT/apps/macOS/Project.swift" ||
    ! grep -Fq '"PRODUCT_BUNDLE_IDENTIFIER": "$(BREV_APP_BUNDLE_ID)"' "$ROOT/apps/macOS/Project.swift"; then
  echo "expected the macOS app target alone to consume the selected build identity" >&2
  exit 1
fi

for oauth_build_setting in \
  BREV_GOOGLE_OAUTH_MACOS_CLIENT_ID \
  BREV_GOOGLE_OAUTH_MACOS_REDIRECT_URI \
  BREV_GOOGLE_OAUTH_MACOS_CALLBACK_SCHEME \
  BREV_GOOGLE_OAUTH_IOS_CLIENT_ID \
  BREV_GOOGLE_OAUTH_IOS_REDIRECT_URI \
  BREV_GOOGLE_OAUTH_IOS_CALLBACK_SCHEME \
  BREV_MICROSOFT_OAUTH_CLIENT_ID; do
  if ! grep -Fq "$oauth_build_setting=" "$ROOT/script/build_and_run.sh"; then
    echo "expected xcodebuild to receive current OAuth build setting $oauth_build_setting" >&2
    exit 1
  fi
done

if ! grep -Fq 'BREV_SPARKLE_PUBLIC_ED_KEY' "$ROOT/script/build_and_run.sh" ||
    ! grep -Fq 'BREV_SPARKLE_PUBLIC_ED_KEY=$sparkle_public_key' "$ROOT/script/build_and_run.sh"; then
  echo "expected local daily-driver builds to receive the configured Sparkle public key" >&2
  exit 1
fi

if grep -Fq '"BREV_GOOGLE_OAUTH_CLIENT_SECRET=$google_client_secret"' "$ROOT/script/build_and_run.sh"; then
  echo "expected the Desktop client credential to stay out of xcodebuild argv" >&2
  exit 1
fi

if ! grep -Fq -- '-xcconfig "$oauth_xcconfig"' "$ROOT/script/build_and_run.sh" ||
    ! grep -Fq -- '-xcconfig "$oauth_xcconfig"' "$ROOT/scripts/release-archive.sh" ||
    ! grep -Fq 'chmod 600 "$oauth_xcconfig"' "$ROOT/script/build_and_run.sh" ||
    ! grep -Fq 'chmod 600 "$oauth_xcconfig"' "$ROOT/scripts/release-archive.sh"; then
  echo "expected local and release builds to inject the Desktop credential through a protected xcconfig" >&2
  exit 1
fi

if grep -Fq 'BREV_GOOGLE_OAUTH_CLIENT_SECRET="$BREV_GOOGLE_OAUTH_CLIENT_SECRET" \' \
    "$ROOT/scripts/release-archive.sh"; then
  echo "expected release archive to keep the Desktop credential out of the child process environment and argv" >&2
  exit 1
fi

if ! grep -Fq '<key>BREVGoogleOAuthClientSecret</key>' "$ROOT/apps/macOS/Resources/Info.plist"; then
  echo "expected macOS Info.plist to receive the configured Desktop client credential" >&2
  exit 1
fi

if grep -Fq 'BREVGoogleOAuthClientSecret' "$ROOT/apps/iOS/Resources/Info.plist"; then
  echo "expected iOS Info.plist to remain free of the Desktop client credential" >&2
  exit 1
fi
preflight_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    "$ROOT/script/build_and_run.sh" --preflight --live 2>&1
)"

case "$preflight_output" in
  *"preflight: live IMAP/SMTP account setup ready"* ) ;;
  * )
    echo "expected live preflight to pass with IMAP/SMTP account setup enabled" >&2
    exit 1
    ;;
esac

mock_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    "$ROOT/script/build_and_run.sh" --preflight --mock 2>&1
)"

case "$mock_output" in
  *"BREV_MAIL_BACKEND=mock"* )
    ;;
  * )
    echo "expected mock preflight to report the mock backend" >&2
    exit 1
    ;;
esac

if grep -Fq 'launchctl setenv BREV_USE_MOCK "$MOCK_MODE"' "$ROOT/script/build_and_run.sh" ||
    ! grep -Fq 'launchctl unsetenv BREV_USE_MOCK' "$ROOT/script/build_and_run.sh"; then
  echo "expected test launches to clear, never globally publish, placeholder mailbox mode" >&2
  exit 1
fi

if ! grep -q 'local_signing_identity' "$ROOT/script/build_and_run.sh" ||
    ! grep -q 'Apple Development' "$ROOT/script/build_and_run.sh"; then
  echo "expected local build script to prefer Apple Development signing when available" >&2
  exit 1
fi

release_preflight="$ROOT/scripts/release-preflight.sh"
if ! grep -q './scripts/check-imap-oauth-setup.sh' "$release_preflight" ||
    ! grep -q 'Gmail OAuth is not release-ready' "$release_preflight" ||
    grep -q 'live OAuth preflight passed' "$release_preflight"; then
  echo "expected release preflight to distinguish transport readiness from configured OAuth providers" >&2
  exit 1
fi

# An Apple Development certificate's name carries the *certificate* ID in
# parentheses, not the team ID -- the team is the certificate's OU. Matching
# the parenthetical against the team silently found nothing and fell back to
# ad-hoc signing on every machine that had a perfectly good dev cert.
run_local_signing_identity() {
  local listing="$1"
  local subject="$2"
  local stub_dir
  stub_dir="$(mktemp -d)"

  # The listing and subject carry quotes and parentheses, so they go through
  # files rather than being interpolated into the stub source.
  printf '%s\n' "$listing" >"$stub_dir/listing.txt"
  printf '%s\n' "$subject" >"$stub_dir/subject.txt"

  cat >"$stub_dir/security" <<STUB
#!/usr/bin/env bash
case "\$1" in
  find-identity) cat "$stub_dir/listing.txt" ;;
  find-certificate) printf 'stub-pem\n' ;;
esac
STUB

  cat >"$stub_dir/openssl" <<STUB
#!/usr/bin/env bash
cat >/dev/null
cat "$stub_dir/subject.txt"
STUB

  chmod +x "$stub_dir/security" "$stub_dir/openssl"

  local result
  result="$(
    PATH="$stub_dir:$PATH" bash -c '
      set -euo pipefail
      project_team_id() { printf "%s" "45AD7E7G5G"; }
      '"$(sed -n '/^local_signing_identity() {/,/^}/p' "$ROOT/script/build_and_run.sh")"'
      local_signing_identity
    '
  )"

  rm -rf "$stub_dir"
  printf '%s' "$result"
}

matching_team_listing='  1) AAAA "Apple Development: Henrik Ogard (96P5QW3XFQ)"
  2) BBBB "Developer ID Application: Henrik Ogard (45AD7E7G5G)"
     2 valid identities found'

identity="$(run_local_signing_identity "$matching_team_listing" \
  'subject=UID=3C4VS96J27, CN=Apple Development: Henrik Ogard (96P5QW3XFQ), OU=45AD7E7G5G, O=Henrik Ogard, C=US')"
if [[ "$identity" != "Apple Development: Henrik Ogard (96P5QW3XFQ)" ]]; then
  echo "expected the development certificate whose OU is the project team, got '$identity'" >&2
  exit 1
fi

identity="$(run_local_signing_identity "$matching_team_listing" \
  'subject=UID=3C4VS96J27, CN=Apple Development: Henrik Ogard (96P5QW3XFQ), OU=OTHERTEAM1, O=Henrik Ogard, C=US')"
if [[ "$identity" != "-" ]]; then
  echo "expected ad-hoc fallback when no development certificate matches the team, got '$identity'" >&2
  exit 1
fi

identity="$(BREV_LOCAL_SIGNING_IDENTITY="Explicit Override" \
  run_local_signing_identity "$matching_team_listing" 'subject=CN=irrelevant, OU=45AD7E7G5G')"
if [[ "$identity" != "Explicit Override" ]]; then
  echo "expected BREV_LOCAL_SIGNING_IDENTITY to win, got '$identity'" >&2
  exit 1
fi

run_macos_entitlements_path() {
  local build_kind="$1"
  BUILD_KIND="$build_kind"
  MACOS_ENTITLEMENTS="$ROOT/apps/macOS/Resources/BrevMacOS.entitlements"
  MACOS_RELEASE_ENTITLEMENTS="$ROOT/apps/macOS/Resources/BrevMacOSRelease.entitlements"
  eval "$(sed -n '/^macos_entitlements_path() {/,/^}/p' "$ROOT/script/build_and_run.sh")"
  macos_entitlements_path
}

if [[ "$(run_macos_entitlements_path test)" != "$ROOT/apps/macOS/Resources/BrevMacOS.entitlements" ]]; then
  echo "expected test builds to use BrevMacOS.entitlements" >&2
  exit 1
fi

if [[ "$(run_macos_entitlements_path release)" != "$ROOT/apps/macOS/Resources/BrevMacOSRelease.entitlements" ]]; then
  echo "expected release builds to use BrevMacOSRelease.entitlements" >&2
  exit 1
fi

mkdir -p "$TMP_APP_BUNDLE/Contents"
cat >"$TMP_APP_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF

stamp_output="$(
  BREV_ENV_FILE="$TMP_ENV" \
    BREV_APP_BUNDLE="$TMP_APP_BUNDLE" \
    "$ROOT/script/build_and_run.sh" --stamp-config --live 2>&1
)"

case "$stamp_output" in
  *"stamp-config: stamped Brev Test ("*" live identity"* ) ;;
  * )
    echo "expected stamp-config to report the stamped live identity" >&2
    exit 1
    ;;
esac

setup_output="$(
  BREV_ENV_FILE="$TMP_SETUP_ENV" \
    "$ROOT/script/build_and_run.sh" --setup-env 2>&1
)"

case "$setup_output" in
  *"setup-env: wrote $TMP_SETUP_ENV"* ) ;;
  * )
    echo "expected setup-env to create the requested env file" >&2
    exit 1
    ;;
esac

echo "test-build-run-env: ok"
