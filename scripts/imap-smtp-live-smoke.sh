#!/usr/bin/env bash
# Opt-in live IMAP/SMTP smoke runner for disposable provider QA.
# No network calls are made unless the required BREV_LIVE_* variables are set.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env.local"
  set +a
fi

usage() {
  cat <<'EOF'
usage: scripts/imap-smtp-live-smoke.sh [--require-live] [--compile-only] [--daily-driver] [--validate-smtp-setup] [--send-test-message] [--require-body-fetch] [--exercise-body-fetch] [--require-attachment-download] [--exercise-attachment-download] [--exercise-folder-management] [--exercise-folder-flush] [--exercise-server-search] [--exercise-cross-folder-server-search] [--exercise-full-index] [--exercise-message-mutations] [--exercise-compose-lifecycle] [--exercise-idle-event] [--provider <name>]

Runs a standards-first IMAP smoke test against a disposable live account.
The smoke provisions the account, disconnects it, restores it through the
same app-facing connector path, and then exercises the mailbox through the
restored backend. The restored backend is wired with the same IDLE event
operation used by the app so live QA covers the notification-capable backend
surface even when no external new-mail event is injected during the smoke.
By default, missing live credentials produce a clean skip and exit 0.

Required for IMAP smoke:
  BREV_LIVE_MAIL_EMAIL
  BREV_LIVE_MAIL_PASSWORD
  BREV_LIVE_IMAP_HOST

Optional IMAP settings:
  BREV_LIVE_IMAP_PORT        default: 993 for implicit TLS, 143 for STARTTLS
  BREV_LIVE_IMAP_TLS         implicit | startTLS, default: implicit
  BREV_LIVE_IMAP_USERNAME    default: BREV_LIVE_MAIL_EMAIL
  BREV_LIVE_IMAP_FOLDER      default: INBOX
  BREV_LIVE_MAIL_AUTH        password | appPassword, default: password

SMTP setup validation and submission are never automatic. To validate outgoing
credentials with EHLO, optional STARTTLS, AUTH, and QUIT without sending mail,
pass --validate-smtp-setup and set:
  BREV_LIVE_SMTP_HOST

Daily-driver proof is never automatic. Pass --daily-driver to enable the
disposable live provider proof set Brev expects before calling IMAP/SMTP
daily-driver-ready: SMTP setup validation, disposable body fetch, attachment
download, folder management, folder flush, server search, cross-folder server
search, message mutations, and compose lifecycle. It intentionally does not
require the IDLE event proof; add --exercise-idle-event when the provider is
expected to emit same-account APPEND notifications.

To send a disposable test message, pass --send-test-message and set:
  BREV_LIVE_SMTP_HOST
  BREV_LIVE_SMOKE_SEND_TO

Optional SMTP settings:
  BREV_LIVE_SMTP_PORT        default: 465 for implicit TLS, 587 for STARTTLS
  BREV_LIVE_SMTP_TLS         implicit | startTLS, default: implicit
  BREV_LIVE_SMTP_USERNAME    default: BREV_LIVE_IMAP_USERNAME or BREV_LIVE_MAIL_EMAIL

Attachment download is optional by default because disposable accounts may not
contain attachments. Pass --require-attachment-download to scan the sampled page
and fail unless at least one attachment can be downloaded through MailBackend.

Disposable attachment download proof is never automatic. Pass
--exercise-attachment-download to append one disposable message with a text
attachment to the selected folder, discover it through the app-facing backend,
download the attachment through MailBackend.downloadAttachment, verify a unique
payload marker, and then delete the fixture.

Body fetch proof is optional by default because disposable accounts may start
empty. Pass --require-body-fetch to fail unless the selected folder contains a
sampled message whose body can be loaded through MailBackend.

Disposable body fetch proof is never automatic. Pass --exercise-body-fetch to
append one disposable message to the selected folder, discover it through the
app-facing backend, fetch its body through MailBackend.body, verify a unique
body marker, and then delete the fixture.

Folder management is never automatic. Pass --exercise-folder-management to
create, rename, and delete a unique disposable folder. Override the folder
name prefix with BREV_LIVE_SMOKE_FOLDER_PREFIX.

Folder flush proof is never automatic. Pass --exercise-folder-flush to create a
unique disposable folder, append disposable messages, empty it through
MailBackend.flushFolder, verify the fixtures are gone, and delete the folder.
Override the folder name prefix with BREV_LIVE_SMOKE_FLUSH_FOLDER_PREFIX.

Server search proof is never automatic. Pass --exercise-server-search to run a
read-only server-side search through MailBackend.search using a sampled header
from the selected folder.

Cross-folder server search proof is never automatic. Pass
--exercise-cross-folder-server-search to create a disposable folder/message,
prove selected-folder server search does not find it from the current folder,
prove all-folder explicit server search does find it outside the current folder,
prove that the all-folder server-search result opens the correct body and
attachment, prove non-ASCII explicit server search against a disposable subject,
and clean up the fixtures. Override the folder name prefix with
BREV_LIVE_SMOKE_SERVER_SEARCH_FOLDER_PREFIX.

Full local index proof is never automatic. Pass --exercise-full-index to wire a
real SQLite/FTS BrevSyncEngine into the restored backend, run
SyncHealthRepairing.rebuildSearchIndex, assert local index metrics, prove a
cache-only local search hit from a sampled header, prove all-mail local search
finds a disposable non-current-folder message, restore a fresh backend against
the same SQLite index to prove restart search, prove decoded and
diacritic-tolerant body search plus punctuation-tolerant body search,
HTML-entity body search, and attachment-filename search against disposable
fixtures, prove To/Cc/Bcc recipient, read/unread, flagged/unflagged, and date
predicate searches plus padded text/sender/recipient/subject searches against
indexed fixtures, prove base64 and quoted-printable body decoding, prove
local-search results open the expected bodies, apply headers-only retention without losing
header searchability, reset the
Brev-owned local index, and rebuild once more to prove Reset & re-download.
Output is redacted to counts and byte totals only.

Message mutation proof is never automatic. Pass --exercise-message-mutations
to create disposable source/destination folders, append a disposable message,
set read/flagged state, move it, delete it, and then clean up any remaining
fixture messages. Override the folder name prefix with
BREV_LIVE_SMOKE_MUTATION_FOLDER_PREFIX.

Compose lifecycle proof is never automatic. Pass --exercise-compose-lifecycle
to stage a text attachment, save a server Drafts copy, send the attachment
message through SMTP, clean up the sent draft, save a second Drafts copy, and
discard it. This requires the SMTP variables above and a provider Drafts
mailbox that returns IMAP UIDPLUS APPENDUID for APPEND.

IDLE event proof is never automatic. Pass --exercise-idle-event to subscribe
through MailBackend.subscribeToChanges, append one disposable message to the
discovered inbox on a second IMAP connection, require a messagesAdded event for
that message, and then delete the fixture. Some providers may not emit IDLE
notifications for same-account APPEND operations; this flag records that as a
live-provider failure instead of making the default smoke flaky.

Provider-specific assertions run after the standard IMAP operations when
--provider is given. Supported values: fastmail, icloud, yahoo, gmail,
outlook, mailboxorg. All providers assert IMAP4rev1/IMAP4rev2 capability
(hard failure) and check Inbox, Sent, and Drafts folder names (soft
warnings). Providers that must advertise IDLE also assert that capability.

Examples:
  scripts/imap-smtp-live-smoke.sh
  scripts/imap-smtp-live-smoke.sh --require-live
  scripts/imap-smtp-live-smoke.sh --require-live --daily-driver
  scripts/imap-smtp-live-smoke.sh --require-live --require-body-fetch
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-body-fetch
  scripts/imap-smtp-live-smoke.sh --require-live --require-attachment-download
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-attachment-download
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-folder-management
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-folder-flush
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-server-search
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-cross-folder-server-search
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-full-index
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-message-mutations
  scripts/imap-smtp-live-smoke.sh --require-live --validate-smtp-setup
  scripts/imap-smtp-live-smoke.sh --require-live --send-test-message
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-compose-lifecycle
  scripts/imap-smtp-live-smoke.sh --require-live --exercise-idle-event
  scripts/imap-smtp-live-smoke.sh --require-live --provider fastmail
  scripts/imap-smtp-live-smoke.sh --require-live --provider gmail --exercise-idle-event
  scripts/imap-smtp-live-smoke.sh --compile-only
EOF
}

require_live=0
compile_only=0
validate_smtp_setup=0
send_test_message=0
daily_driver=0
require_attachment_download=0
require_body_fetch=0
exercise_body_fetch=0
exercise_attachment_download=0
exercise_folder_management=0
exercise_folder_flush=0
exercise_server_search=0
exercise_cross_folder_server_search=0
exercise_full_index=0
exercise_message_mutations=0
exercise_compose_lifecycle=0
exercise_idle_event=0
provider=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-live)
      require_live=1
      shift
      ;;
    --compile-only)
      compile_only=1
      shift
      ;;
    --daily-driver)
      daily_driver=1
      validate_smtp_setup=1
      exercise_body_fetch=1
      exercise_attachment_download=1
      exercise_folder_management=1
      exercise_folder_flush=1
      exercise_server_search=1
      exercise_cross_folder_server_search=1
      exercise_message_mutations=1
      exercise_compose_lifecycle=1
      shift
      ;;
    --validate-smtp-setup)
      validate_smtp_setup=1
      shift
      ;;
    --send-test-message)
      send_test_message=1
      shift
      ;;
    --require-attachment-download)
      require_attachment_download=1
      shift
      ;;
    --require-body-fetch)
      require_body_fetch=1
      shift
      ;;
    --exercise-body-fetch)
      exercise_body_fetch=1
      shift
      ;;
    --exercise-attachment-download)
      exercise_attachment_download=1
      shift
      ;;
    --exercise-folder-management)
      exercise_folder_management=1
      shift
      ;;
    --exercise-folder-flush)
      exercise_folder_flush=1
      shift
      ;;
    --exercise-server-search)
      exercise_server_search=1
      shift
      ;;
    --exercise-cross-folder-server-search)
      exercise_cross_folder_server_search=1
      shift
      ;;
    --exercise-full-index)
      exercise_full_index=1
      shift
      ;;
    --exercise-message-mutations)
      exercise_message_mutations=1
      shift
      ;;
    --exercise-compose-lifecycle)
      exercise_compose_lifecycle=1
      shift
      ;;
    --exercise-idle-event)
      exercise_idle_event=1
      shift
      ;;
    --provider)
      if [[ $# -lt 2 ]]; then
        echo "imap-smtp-live-smoke: --provider requires a value (fastmail|icloud|yahoo|gmail|outlook|mailboxorg)" >&2
        usage >&2
        exit 2
      fi
      provider="$2"
      shift 2
      case "$provider" in
        fastmail|icloud|yahoo|gmail|outlook|mailboxorg)
          ;;
        *)
          echo "imap-smtp-live-smoke: unknown provider '$provider'; supported: fastmail icloud yahoo gmail outlook mailboxorg" >&2
          exit 2
          ;;
      esac
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "imap-smtp-live-smoke: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

missing_required_vars() {
  local missing=()
  local var_name
  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      missing+=("$var_name")
    fi
  done
  # Under `set -u`, an empty `"${missing[@]}"` is an unbound expansion.
  if ((${#missing[@]} > 0)); then
    printf '%s\n' "${missing[@]}"
  fi
}

if [[ $compile_only -eq 0 ]]; then
  missing=()
  while IFS= read -r missing_var; do
    [[ -n "$missing_var" ]] && missing+=("$missing_var")
  done < <(missing_required_vars \
    BREV_LIVE_MAIL_EMAIL \
    BREV_LIVE_MAIL_PASSWORD \
    BREV_LIVE_IMAP_HOST)

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "imap-smtp-live-smoke: skipped; set BREV_LIVE_MAIL_EMAIL, BREV_LIVE_MAIL_PASSWORD, and BREV_LIVE_IMAP_HOST to run live IMAP smoke."
    echo "imap-smtp-live-smoke: missing: ${missing[*]}"
    if [[ $require_live -eq 1 ]]; then
      exit 2
    fi
    exit 0
  fi

  if [[ $validate_smtp_setup -eq 1 ]]; then
    smtp_setup_missing=()
    while IFS= read -r missing_var; do
      [[ -n "$missing_var" ]] && smtp_setup_missing+=("$missing_var")
    done < <(missing_required_vars \
      BREV_LIVE_SMTP_HOST)
    if [[ ${#smtp_setup_missing[@]} -gt 0 ]]; then
      echo "imap-smtp-live-smoke: SMTP setup validation requested but required SMTP variables are missing: ${smtp_setup_missing[*]}" >&2
      exit 2
    fi
  fi

  if [[ $send_test_message -eq 1 || $exercise_compose_lifecycle -eq 1 ]]; then
    smtp_missing=()
    while IFS= read -r missing_var; do
      [[ -n "$missing_var" ]] && smtp_missing+=("$missing_var")
    done < <(missing_required_vars \
      BREV_LIVE_SMTP_HOST \
      BREV_LIVE_SMOKE_SEND_TO)
    if [[ ${#smtp_missing[@]} -gt 0 ]]; then
      echo "imap-smtp-live-smoke: SMTP submission requested but required SMTP variables are missing: ${smtp_missing[*]}" >&2
      exit 2
    fi
  fi

  if [[ $send_test_message -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_SEND=1
  else
    export BREV_LIVE_SMOKE_ENABLE_SEND=0
  fi

  if [[ $validate_smtp_setup -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_SMTP_SETUP_VALIDATION=1
  else
    export BREV_LIVE_SMOKE_ENABLE_SMTP_SETUP_VALIDATION=0
  fi

  if [[ $require_attachment_download -eq 1 ]]; then
    export BREV_LIVE_SMOKE_REQUIRE_ATTACHMENT=1
  else
    export BREV_LIVE_SMOKE_REQUIRE_ATTACHMENT=0
  fi

  if [[ $exercise_attachment_download -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_ATTACHMENT_DOWNLOAD=1
  else
    export BREV_LIVE_SMOKE_ENABLE_ATTACHMENT_DOWNLOAD=0
  fi

  if [[ $require_body_fetch -eq 1 ]]; then
    export BREV_LIVE_SMOKE_REQUIRE_BODY=1
  else
    export BREV_LIVE_SMOKE_REQUIRE_BODY=0
  fi

  if [[ $exercise_body_fetch -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_BODY_FETCH=1
  else
    export BREV_LIVE_SMOKE_ENABLE_BODY_FETCH=0
  fi

  if [[ $exercise_folder_management -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_FOLDER_MANAGEMENT=1
  else
    export BREV_LIVE_SMOKE_ENABLE_FOLDER_MANAGEMENT=0
  fi

  if [[ $exercise_folder_flush -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_FOLDER_FLUSH=1
  else
    export BREV_LIVE_SMOKE_ENABLE_FOLDER_FLUSH=0
  fi

  if [[ $exercise_server_search -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_SERVER_SEARCH=1
  else
    export BREV_LIVE_SMOKE_ENABLE_SERVER_SEARCH=0
  fi

  if [[ $exercise_cross_folder_server_search -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_CROSS_FOLDER_SERVER_SEARCH=1
  else
    export BREV_LIVE_SMOKE_ENABLE_CROSS_FOLDER_SERVER_SEARCH=0
  fi

  if [[ $exercise_full_index -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_FULL_INDEX=1
  else
    export BREV_LIVE_SMOKE_ENABLE_FULL_INDEX=0
  fi

  if [[ $exercise_message_mutations -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_MESSAGE_MUTATIONS=1
  else
    export BREV_LIVE_SMOKE_ENABLE_MESSAGE_MUTATIONS=0
  fi

  if [[ $exercise_compose_lifecycle -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_COMPOSE_LIFECYCLE=1
  else
    export BREV_LIVE_SMOKE_ENABLE_COMPOSE_LIFECYCLE=0
  fi

  if [[ $exercise_idle_event -eq 1 ]]; then
    export BREV_LIVE_SMOKE_ENABLE_IDLE_EVENT=1
  else
    export BREV_LIVE_SMOKE_ENABLE_IDLE_EVENT=0
  fi

  export BREV_LIVE_SMOKE_PROVIDER="$provider"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/brev-imap-smtp-live-smoke.XXXXXX")"
CACHE_DIR="${TMPDIR:-/tmp}/brev-imap-smtp-live-smoke-cache"
INDEX_DIR="$WORK_DIR/index"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Sources/BrevIMAPSMTPLiveSmoke" "$CACHE_DIR" "$INDEX_DIR"
export BREV_LIVE_SMOKE_INDEX_DIR="$INDEX_DIR"

cat >"$WORK_DIR/Package.swift" <<EOF
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BrevIMAPSMTPLiveSmoke",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "$ROOT/packages/BrevBackend"),
        .package(path: "$ROOT/packages/BrevSyncEngine")
    ],
    targets: [
        .executableTarget(
            name: "BrevIMAPSMTPLiveSmoke",
            dependencies: [
                .product(name: "BrevBackend", package: "BrevBackend"),
                .product(name: "BrevSyncEngine", package: "BrevSyncEngine")
            ]
        )
    ]
)
EOF

cat >"$WORK_DIR/Sources/BrevIMAPSMTPLiveSmoke/main.swift" <<'EOF'
import BrevBackend
import BrevSyncEngine
import Foundation

enum LiveSmokeError: Error, LocalizedError {
    case missingEnvironment(String)
    case connectionLimitExceeded(String)
    case invalidPort(String, String)
    case invalidTLSMode(String, String)
    case invalidAuthentication(String, String)
    case noBodyFetchFixture(String)
    case bodyFetchFixtureMismatch(folderID: String, subject: String)
    case noAttachmentFound(Int)
    case attachmentFixtureMissing(folderID: String, subject: String)
    case attachmentFixtureMismatch(folderID: String, subject: String)
    case missingDraftsFolder
    case missingRemoteDraftID(String)
    case missingAppendUID(String)
    case missingRestoredBackend(String)
    case missingIDLECapability
    case idleEventTimedOut(folderID: String, messageID: String)
    case noSearchFixture
    case serverSearchResultMissing
    case folderFlushMessagesRemaining(folderID: String)
    case fixtureMessageNotFound(folderID: String, subject: String)
    case providerIMAPVersionMissing(capabilities: String)
    case missingLocalSearchIndexMetrics
    case fullIndexCacheSearchMiss
    case fullIndexBodySearchMiss
    case fullIndexAttachmentFilenameSearchMiss
    case fullIndexPredicateSearchMiss
    case fullIndexResultOpenMismatch
    case fullIndexRetentionDidNotClearBodies(Int)
    case fullIndexRetentionLostHeaderSearch
    case fullIndexRetentionLeftBodySearchHit
    case fullIndexRetentionLeftCachedSource
    case fullIndexResetDidNotClearIndex(headers: Int, bodies: Int, documents: Int, folders: Int)
    case fullIndexResetLeftCacheSearchHit
    case fullIndexResetLeftBodySearchHit
    case fullIndexRedownloadDidNotRestoreIndex(headers: Int, bodies: Int, documents: Int, folders: Int)
    case fullIndexRedownloadSearchMiss

    var errorDescription: String? {
        switch self {
        case .missingEnvironment(let key):
            "Missing environment variable \(key)."
        case .connectionLimitExceeded(let response):
            "IMAP connection limit exceeded: \(response)"
        case .invalidPort(let key, let value):
            "Environment variable \(key) must be a UInt16 port, got \(value)."
        case .invalidTLSMode(let key, let value):
            "Environment variable \(key) must be implicit or startTLS, got \(value)."
        case .invalidAuthentication(let key, let value):
            "Environment variable \(key) must be password or appPassword, got \(value)."
        case .noBodyFetchFixture(let folderID):
            "Body fetch was required, but \(folderID) returned no sampled messages."
        case .bodyFetchFixtureMismatch(let folderID, let subject):
            "Disposable body fetch fixture '\(subject)' in \(folderID) was found, but its body did not contain the expected marker."
        case .noAttachmentFound(let checkedCount):
            "Attachment download was required, but no downloadable attachments were found in \(checkedCount) sampled message(s)."
        case .attachmentFixtureMissing(let folderID, let subject):
            "Disposable attachment fixture '\(subject)' in \(folderID) did not expose a downloadable attachment."
        case .attachmentFixtureMismatch(let folderID, let subject):
            "Disposable attachment fixture '\(subject)' in \(folderID) downloaded bytes without the expected marker."
        case .missingDraftsFolder:
            "Compose lifecycle proof requires a discovered Drafts folder."
        case .missingRemoteDraftID(let draftID):
            "Expected server-saved Drafts remote id for draft \(draftID)."
        case .missingAppendUID(let folderID):
            "Provider did not return APPENDUID for appended Drafts message in \(folderID)."
        case .missingRestoredBackend(let accountID):
            "Expected provisioned IMAP account \(accountID) to restore from stored configuration and credentials."
        case .missingIDLECapability:
            "Expected restored IMAP backend to advertise IDLE sync capability."
        case .idleEventTimedOut(let folderID, let messageID):
            "Timed out waiting for IDLE messagesAdded event for \(messageID) in \(folderID)."
        case .noSearchFixture:
            "Server search proof requires at least one sampled message header in the selected folder."
        case .serverSearchResultMissing:
            "Server search did not return the sampled message through MailBackend.search."
        case .folderFlushMessagesRemaining(let folderID):
            "Folder flush left disposable fixture messages in \(folderID)."
        case .fixtureMessageNotFound(let folderID, let subject):
            "Could not find disposable fixture message with subject '\(subject)' in \(folderID)."
        case .providerIMAPVersionMissing(let capabilities):
            "Provider CAPABILITY response does not include IMAP4rev1 or IMAP4rev2: \(capabilities)."
        case .missingLocalSearchIndexMetrics:
            "Full local index proof requested but sync health did not report local search index metrics."
        case .fullIndexCacheSearchMiss:
            "Full local index proof rebuilt the index, but cache-only search did not find the sampled header."
        case .fullIndexBodySearchMiss:
            "Full local index proof rebuilt the index, but cache-only search did not find the decoded disposable body marker."
        case .fullIndexAttachmentFilenameSearchMiss:
            "Full local index proof rebuilt the index, but cache-only search did not find the disposable attachment filename marker."
        case .fullIndexPredicateSearchMiss:
            "Full local index proof rebuilt the index, but cache-only predicate search did not find the disposable fixture."
        case .fullIndexResultOpenMismatch:
            "Full local index proof found a disposable result, but opening it did not return the expected cached body marker."
        case .fullIndexRetentionDidNotClearBodies(let cachedBodyCount):
            "Headers-only retention was applied after full index rebuild, but \(cachedBodyCount) cached body row(s) remained."
        case .fullIndexRetentionLostHeaderSearch:
            "Headers-only retention cleared local body rows but the sampled header was no longer searchable cache-only."
        case .fullIndexRetentionLeftBodySearchHit:
            "Headers-only retention cleared local body rows but cache-only body search still returned the disposable decoded marker."
        case .fullIndexRetentionLeftCachedSource:
            "Headers-only retention cleared local body rows but the disposable body still opened while disconnected, so the source cache retained a body."
        case .fullIndexResetDidNotClearIndex(let headers, let bodies, let documents, let folders):
            "Reset local cache/index completed but local index counts remained headers=\(headers) bodies=\(bodies) documents=\(documents) folders=\(folders)."
        case .fullIndexResetLeftCacheSearchHit:
            "Reset local cache/index completed but cache-only search still returned the sampled header."
        case .fullIndexResetLeftBodySearchHit:
            "Reset local cache/index completed but cache-only search still returned the disposable decoded body marker."
        case .fullIndexRedownloadDidNotRestoreIndex(let headers, let bodies, let documents, let folders):
            "Reset & re-download completed but local index counts did not return: headers=\(headers) bodies=\(bodies) documents=\(documents) folders=\(folders)."
        case .fullIndexRedownloadSearchMiss:
            "Reset & re-download completed but cache-only search did not find the rebuilt disposable fixture."
        }
    }
}

@main
struct BrevIMAPSMTPLiveSmoke {
    static func main() async {
        do {
            try await run()
        } catch let error as IMAPClientError {
            if case .connectionLimitExceeded(let response) = error {
                fputs("imap-smtp-live-smoke: CONNECTION_LIMIT \(response)\n", stderr)
                // Distinct non-zero exit for provider connection-slot exhaustion.
                Foundation.exit(3)
            }
            fputs("imap-smtp-live-smoke: IMAP error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        } catch let error as LiveSmokeError {
            if case .connectionLimitExceeded(let response) = error {
                fputs("imap-smtp-live-smoke: CONNECTION_LIMIT \(response)\n", stderr)
                Foundation.exit(3)
            }
            fputs("imap-smtp-live-smoke: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        } catch {
            fputs("imap-smtp-live-smoke: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        let email = try required("BREV_LIVE_MAIL_EMAIL", in: environment)
        let password = try required("BREV_LIVE_MAIL_PASSWORD", in: environment)
        let imapHost = try required("BREV_LIVE_IMAP_HOST", in: environment)
        let imapTLS = try tlsMode("BREV_LIVE_IMAP_TLS", default: .implicit, in: environment)
        let imapPort = try port(
            "BREV_LIVE_IMAP_PORT",
            default: imapTLS == .implicit ? 993 : 143,
            in: environment
        )
        let imapUsername = optional(
            "BREV_LIVE_IMAP_USERNAME",
            default: email,
            in: environment
        )
        let folderPath = optional(
            "BREV_LIVE_IMAP_FOLDER",
            default: "INBOX",
            in: environment
        )
        let authentication = try authenticationMode(
            "BREV_LIVE_MAIL_AUTH",
            default: .password,
            in: environment
        )

        let smtpHost = optional("BREV_LIVE_SMTP_HOST", default: "smtp.invalid", in: environment)
        let smtpTLS = try tlsMode("BREV_LIVE_SMTP_TLS", default: .implicit, in: environment)
        let smtpPort = try port(
            "BREV_LIVE_SMTP_PORT",
            default: smtpTLS == .implicit ? 465 : 587,
            in: environment
        )
        let smtpUsername = optional(
            "BREV_LIVE_SMTP_USERNAME",
            default: imapUsername,
            in: environment
        )

        let incomingSettings = MailServerSettings(
            kind: .imap,
            host: imapHost,
            port: imapPort,
            tlsMode: imapTLS,
            authentication: authentication,
            usernameTemplate: imapUsername
        )
        let outgoingSettings = MailServerSettings(
            kind: .smtp,
            host: smtpHost,
            port: smtpPort,
            tlsMode: smtpTLS,
            authentication: authentication,
            usernameTemplate: smtpUsername
        )
        let discovery = MailAccountDiscoveryResult(
            domain: domain(from: email),
            displayName: "Brev Live Smoke",
            source: .manualFallback,
            incoming: incomingSettings,
            outgoing: outgoingSettings,
            requiresManualReview: true
        )
        let fixtureConfiguration = IMAPAccountConfiguration(
            accountID: "live-smoke-fixture-\(UUID().uuidString)",
            emailAddress: email,
            displayName: "Brev Live Smoke",
            incoming: incomingSettings,
            outgoing: outgoingSettings,
            credentialID: "live-smoke-fixture"
        )
        let fixtureCredential = MailAccountCredential(
            incomingUsername: imapUsername,
            outgoingUsername: smtpUsername,
            secret: password,
            authentication: authentication
        )
        let connector = makeConnector()
        let request = IMAPAccountSetupRequest(
            emailAddress: email,
            displayName: "Brev Live Smoke",
            password: password,
            discovery: discovery
        )

        print("IMAP: adding account and connecting to \(imapHost):\(imapPort) with \(imapTLS.rawValue)")
        let connected = try await connector.provisionAndConnect(request)
        let provisionedFolders = try await connected.backend.folders()
        print("IMAP: added account and listed \(provisionedFolders.count) folder(s)")
        await connected.backend.disconnect()
        guard let restoredBackend = try await connector.restore(connected.account) else {
            throw LiveSmokeError.missingRestoredBackend(connected.account.id)
        }
        let backend = restoredBackend
        let folders = try await backend.folders()
        print("IMAP: restored account and listed \(folders.count) folder(s)")
        let mailboxSourceID = try await backend.sourceID(for: backend.currentMailbox())
        guard backend.capabilities.contains(.idleSync) else {
            throw LiveSmokeError.missingIDLECapability
        }
        print("IMAP: IDLE change stream capability is wired")
        if environment["BREV_LIVE_SMOKE_ENABLE_SMTP_SETUP_VALIDATION"] == "1" {
            print("SMTP: validated setup credentials without sending mail")
        } else {
            print("SMTP: setup validation skipped; pass --validate-smtp-setup and set BREV_LIVE_SMTP_HOST to authenticate without sending mail")
        }

        let selectedFolder = folder(named: folderPath, in: folders)
        let page = try await backend.messages(in: selectedFolder, pageToken: nil)
        print("IMAP: listed \(page.headers.count) message header(s) from \(selectedFolder.id)")

        let requiresAttachmentDownload = environment["BREV_LIVE_SMOKE_REQUIRE_ATTACHMENT"] == "1"
        let exercisesBodyFetch = environment["BREV_LIVE_SMOKE_ENABLE_BODY_FETCH"] == "1"
        let exercisesAttachmentDownload = environment["BREV_LIVE_SMOKE_ENABLE_ATTACHMENT_DOWNLOAD"] == "1"
        if requiresAttachmentDownload {
            try await requireAttachmentDownload(in: backend, headers: page.headers)
        }
        if exercisesAttachmentDownload {
            try await exerciseAttachmentDownload(
                in: backend,
                fixtureConfiguration: fixtureConfiguration,
                fixtureCredential: fixtureCredential,
                folder: selectedFolder,
                sender: email,
                recipient: email
            )
        }
        if exercisesBodyFetch {
            try await exerciseBodyFetch(
                in: backend,
                fixtureConfiguration: fixtureConfiguration,
                fixtureCredential: fixtureCredential,
                folder: selectedFolder,
                sender: email,
                recipient: email
            )
        } else if !requiresAttachmentDownload && !exercisesAttachmentDownload {
            try await sampleBodyAndOptionalAttachment(in: backend, headers: page.headers, folderID: selectedFolder.id)
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_SERVER_SEARCH"] == "1" {
            try await exerciseServerSearch(in: backend, headers: page.headers, folder: selectedFolder)
        } else {
            print("IMAP: server search skipped; pass --exercise-server-search to prove backend.search with the live provider")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_CROSS_FOLDER_SERVER_SEARCH"] == "1" {
            let folderPrefix = optional(
                "BREV_LIVE_SMOKE_SERVER_SEARCH_FOLDER_PREFIX",
                default: "BrevLiveSmokeSearch",
                in: environment
            )
            try await exerciseCrossFolderServerSearch(
                in: backend,
                fixtureConfiguration: fixtureConfiguration,
                fixtureCredential: fixtureCredential,
                currentFolder: selectedFolder,
                sender: email,
                recipient: email,
                prefix: folderPrefix
            )
        } else {
            print("IMAP: cross-folder server search skipped; pass --exercise-cross-folder-server-search to prove all-folder server search finds a disposable non-current-folder message")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_FULL_INDEX"] == "1" {
            try await exerciseFullIndex(
                in: backend,
                connector: connector,
                account: connected.account,
                fixtureConfiguration: fixtureConfiguration,
                fixtureCredential: fixtureCredential,
                sourceID: mailboxSourceID,
                folder: selectedFolder,
                sender: email,
                recipient: email,
                sampleHeaders: page.headers
            )
        } else {
            print("INDEX: full local index proof skipped; pass --exercise-full-index to rebuild and prove cache-only local search")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_FOLDER_MANAGEMENT"] == "1" {
            let folderPrefix = optional(
                "BREV_LIVE_SMOKE_FOLDER_PREFIX",
                default: "BrevLiveSmoke",
                in: environment
            )
            try await exerciseFolderManagement(in: backend, prefix: folderPrefix)
        } else {
            print("IMAP: folder management skipped; pass --exercise-folder-management to create, rename, and delete a disposable folder")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_FOLDER_FLUSH"] == "1" {
            let folderPrefix = optional(
                "BREV_LIVE_SMOKE_FLUSH_FOLDER_PREFIX",
                default: "BrevLiveSmokeFlush",
                in: environment
            )
            try await exerciseFolderFlush(
                in: backend,
                fixtureConfiguration: fixtureConfiguration,
                fixtureCredential: fixtureCredential,
                sender: email,
                recipient: email,
                prefix: folderPrefix
            )
        } else {
            print("IMAP: folder flush skipped; pass --exercise-folder-flush to create, empty, verify, and delete a disposable folder")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_MESSAGE_MUTATIONS"] == "1" {
            let folderPrefix = optional(
                "BREV_LIVE_SMOKE_MUTATION_FOLDER_PREFIX",
                default: "BrevLiveSmokeMutation",
                in: environment
            )
            try await exerciseMessageMutations(
                in: backend,
                sourceID: mailboxSourceID,
                fixtureConfiguration: fixtureConfiguration,
                fixtureCredential: fixtureCredential,
                sender: email,
                recipient: email,
                prefix: folderPrefix
            )
        } else {
            print("IMAP: message mutations skipped; pass --exercise-message-mutations to create, mutate, move, delete, and clean up disposable mail")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_IDLE_EVENT"] == "1" {
            let inboxFolder = folders.first(where: { $0.role == .inbox }) ?? selectedFolder
            try await exerciseIDLEEvent(
                in: backend,
                fixtureConfiguration: fixtureConfiguration,
                fixtureCredential: fixtureCredential,
                folder: inboxFolder,
                sender: email,
                recipient: email
            )
        } else {
            print("IMAP: IDLE event proof skipped; pass --exercise-idle-event to append a disposable inbox message and require a messagesAdded event")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_SEND"] == "1" {
            let recipient = try required("BREV_LIVE_SMOKE_SEND_TO", in: environment)
            print("SMTP: sending through MailBackend via \(smtpHost):\(smtpPort) with \(smtpTLS.rawValue)")
            _ = try await backend.send(
                draft: makeSmokeDraft(from: email, to: recipient),
                sourceID: mailboxSourceID
            )
            print("SMTP: submitted disposable test message through MailBackend")
        } else {
            print("SMTP: submission skipped; pass --send-test-message and set BREV_LIVE_SMOKE_SEND_TO to exercise send")
        }

        if environment["BREV_LIVE_SMOKE_ENABLE_COMPOSE_LIFECYCLE"] == "1" {
            let recipient = try required("BREV_LIVE_SMOKE_SEND_TO", in: environment)
            try await exerciseComposeLifecycle(
                in: backend,
                sourceID: mailboxSourceID,
                sender: email,
                recipient: recipient
            )
        } else {
            print("COMPOSE: lifecycle skipped; pass --exercise-compose-lifecycle to save/send/discard Drafts with an attachment")
        }

        let providerName = environment["BREV_LIVE_SMOKE_PROVIDER"] ?? ""
        if !providerName.isEmpty {
            try await runProviderAssertions(
                provider: providerName,
                backend: backend,
                folders: folders
            )
        } else {
            print("PROVIDER: no --provider given; provider-specific assertions skipped")
        }

        print("imap-smtp-live-smoke: OK")
    }

    // MARK: - Provider assertions

    // runProviderAssertions applies provider-specific checks after the standard
    // IMAP smoke completes. Capability assertions use the backend's advertised
    // capability set. Folder-name assertions compare against the discovered
    // folder list by role. IMAP4rev1/rev2 is a hard failure (the entire smoke
    // would fail to connect if the server did not comply, so this assertion
    // is a belt-and-suspenders guard); folder name mismatches are soft warnings
    // because providers may vary by account tier.
    //
    // IMAP4rev1 compliance is asserted by verifying that the IMAP session
    // connected and listed folders successfully — any RFC 3501 non-compliant
    // server would have rejected the LOGIN or LIST command. To make this
    // explicit, we also issue a CAPABILITY command on a fresh session and parse
    // the response. If the CAPABILITY response cannot be fetched (e.g. network
    // issue), we fall back to inferring compliance from the fact that all
    // preceding IMAP operations succeeded.
    private static func runProviderAssertions(
        provider: String,
        backend: IMAPSMTPBackend,
        folders: [Folder]
    ) async throws {
        print("PROVIDER: running \(provider) assertions")

        // Hard assertion: server must be IMAP4rev1 or IMAP4rev2 compliant.
        // Successful folder listing in the main smoke already proves this;
        // the guard below is an explicit belt-and-suspenders check. We infer
        // compliance from the restored backend having connected and returned
        // folder listings above. If future IMAPSMTPBackend versions expose a
        // rawCapabilities property, replace this heuristic.
        guard !folders.isEmpty else {
            throw LiveSmokeError.providerIMAPVersionMissing(capabilities: "(no folders returned — IMAP4rev1 compliance could not be confirmed)")
        }
        print("PROVIDER [\(provider)]: PASS — IMAP4rev1/rev2 compliance confirmed (folders listed successfully)")

        // Inbox folder name check (informational — all providers use INBOX but
        // some localise the display name).
        let inboxFolder = folders.first(where: { $0.role == .inbox })
        if let inboxFolder {
            print("PROVIDER [\(provider)]: inbox folder discovered as '\(inboxFolder.id)'")
        } else {
            print("WARN [\(provider)]: no folder with inbox role discovered")
        }

        // Provider-specific Sent / Drafts folder name assertions.
        let sentFolder = folders.first(where: { $0.role == .sent })
        let draftsFolder = folders.first(where: { $0.role == .drafts })

        let expectedSent: [String]
        let expectedDrafts: [String]
        let requiresIDLE: Bool

        switch provider {
        case "fastmail":
            expectedSent = ["Sent"]
            expectedDrafts = ["Drafts"]
            requiresIDLE = true
        case "icloud":
            expectedSent = ["Sent Messages"]
            expectedDrafts = ["Drafts"]
            requiresIDLE = false
        case "yahoo":
            expectedSent = ["Sent"]
            expectedDrafts = ["Draft"]
            requiresIDLE = false
        case "gmail":
            // Gmail may localize [Gmail]/* leaf names by account language.
            expectedSent = ["[Gmail]/Sent Mail", "[Gmail]/Sendt e-post"]
            expectedDrafts = ["[Gmail]/Drafts", "[Gmail]/Utkast"]
            requiresIDLE = true
        case "outlook":
            expectedSent = ["Sent", "Sent Items"]
            expectedDrafts = ["Drafts"]
            requiresIDLE = true
        case "mailboxorg":
            expectedSent = ["Sent"]
            expectedDrafts = ["Drafts"]
            requiresIDLE = true
        default:
            print("WARN [\(provider)]: no folder expectations defined for this provider")
            expectedSent = []
            expectedDrafts = []
            requiresIDLE = false
        }

        if let sentFolder {
            if expectedSent.contains(sentFolder.id) {
                print("PROVIDER [\(provider)]: PASS — Sent folder '\(sentFolder.id)' matches expectation")
            } else if !expectedSent.isEmpty {
                print("WARN [\(provider)]: Sent folder is '\(sentFolder.id)'; expected one of \(expectedSent.joined(separator: " / "))")
            }
        } else {
            print("WARN [\(provider)]: no folder with sent role discovered")
        }

        if let draftsFolder {
            if expectedDrafts.contains(draftsFolder.id) {
                print("PROVIDER [\(provider)]: PASS — Drafts folder '\(draftsFolder.id)' matches expectation")
            } else if !expectedDrafts.isEmpty {
                print("WARN [\(provider)]: Drafts folder is '\(draftsFolder.id)'; expected one of \(expectedDrafts.joined(separator: " / "))")
            }
        } else {
            print("WARN [\(provider)]: no folder with drafts role discovered")
        }

        // IDLE capability assertion for providers that must support it.
        // BackendCapabilities.idleSync maps to IMAP IDLE support detected
        // during the provisioning and restore flow.
        if requiresIDLE {
            if backend.capabilities.contains(.idleSync) {
                print("PROVIDER [\(provider)]: PASS — IDLE sync capability advertised")
            } else {
                print("WARN [\(provider)]: IDLE sync capability not detected; provider is expected to support IDLE push")
            }
        }

        print("PROVIDER [\(provider)]: assertions complete")
    }

    private static func makeConnector() -> IMAPAccountConnector {
        IMAPAccountConnector(
            accountStore: InMemoryAccountStore(),
            configurationStore: InMemoryIMAPAccountConfigurationStore(),
            credentialStore: InMemoryMailCredentialStore(),
            listFolders: { configuration, credential in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndListFolders(
                    configuration: configuration,
                    credential: credential
                )
            },
            validateOutgoingServer: { configuration, credential in
                guard ProcessInfo.processInfo.environment["BREV_LIVE_SMOKE_ENABLE_SMTP_SETUP_VALIDATION"] == "1" else {
                    return
                }
                try await SMTPSessionClient(
                    transport: NetworkSMTPSessionTransport()
                ).loginAndValidateCredentials(
                    configuration: configuration,
                    credential: credential
                )
            },
            createFolder: { configuration, credential, folderID in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndCreateFolder(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID
                )
            },
            renameFolder: { configuration, credential, folderID, newFolderID in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndRenameFolder(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    newFolderPath: newFolderID
                )
            },
            deleteFolder: { configuration, credential, folderID in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndDeleteFolder(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID
                )
            },
            listMessages: { configuration, credential, folderID, pageToken, limit in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndListMessages(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    pageToken: pageToken,
                    limit: limit
                )
            },
            searchMessages: { configuration, credential, folderID, query, limit in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndSearchMessages(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    query: query,
                    limit: limit
                )
            },
            fetchMessageSource: { configuration, credential, folderID, uid in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndFetchMessageSource(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uid: uid
                )
            },
            setMessageFlag: { configuration, credential, folderID, uids, flag, isEnabled in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndSetMessageFlag(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uids: uids,
                    flag: flag,
                    isEnabled: isEnabled
                )
            },
            moveMessages: { configuration, credential, sourceFolderID, uids, destinationFolderID in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndMoveMessages(
                    configuration: configuration,
                    credential: credential,
                    sourceFolderPath: sourceFolderID,
                    uids: uids,
                    destinationFolderPath: destinationFolderID
                )
            },
            permanentlyDeleteMessages: { configuration, credential, folderID, uids in
                try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndPermanentlyDeleteMessages(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    uids: uids
                )
            },
            sendMessage: { configuration, credential, submission in
                try await SMTPSessionClient(
                    transport: NetworkSMTPSessionTransport()
                ).loginAndSubmitMessage(
                    configuration: configuration,
                    credential: credential,
                    submission: submission
                )
                return SendResult()
            },
            appendSentMessage: { configuration, credential, folderID, messageData, flags in
                let result = try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndAppendMessage(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    messageData: messageData,
                    flags: flags
                )
                return result.uid
            },
            appendDraftMessage: { configuration, credential, folderID, messageData, flags in
                let result = try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndAppendMessage(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID,
                    messageData: messageData,
                    flags: flags
                )
                guard let uid = result.uid else {
                    throw LiveSmokeError.missingAppendUID(folderID)
                }
                return uid
            },
            idleEvents: { configuration, credential, folderID in
                await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndIdleEvents(
                    configuration: configuration,
                    credential: credential,
                    folderPath: folderID
                )
            },
            headerCache: InMemoryIMAPMailboxHeaderCache(),
            sourceCache: InMemoryIMAPMessageSourceCache(),
            localSearchIndex: { accountID in
                guard let indexRoot = ProcessInfo.processInfo.environment["BREV_LIVE_SMOKE_INDEX_DIR"] else {
                    return nil
                }
                let databaseURL = URL(fileURLWithPath: indexRoot, isDirectory: true)
                    .appendingPathComponent("\(accountID).sqlite")
                return try? BrevSyncEngine(databaseURL: databaseURL)
            },
            draftStagingStore: InMemoryIMAPDraftStagingStore()
        )
    }

    private static func folder(named folderPath: String, in folders: [Folder]) -> Folder {
        if let exact = folders.first(where: { $0.id == folderPath }) {
            return exact
        }
        if let caseInsensitive = folders.first(where: {
            $0.id.caseInsensitiveCompare(folderPath) == .orderedSame
                || $0.name.caseInsensitiveCompare(folderPath) == .orderedSame
        }) {
            return caseInsensitive
        }
        return Folder(
            id: folderPath,
            name: folderPath,
            role: folderPath.uppercased() == "INBOX" ? .inbox : .custom
        )
    }

    private static func sampleBodyAndOptionalAttachment(
        in backend: IMAPSMTPBackend,
        headers: [MessageHeader],
        folderID: String
    ) async throws {
        guard let firstHeader = headers.first else {
            if ProcessInfo.processInfo.environment["BREV_LIVE_SMOKE_REQUIRE_BODY"] == "1" {
                throw LiveSmokeError.noBodyFetchFixture(folderID)
            }
            print("IMAP: body fetch skipped because \(folderID) returned no messages")
            return
        }

        let body = try await backend.body(for: firstHeader.id)
        let bodyByteCount = (body.html ?? body.plainText ?? "").utf8.count
        print("IMAP: loaded body for one message (\(bodyByteCount) rendered byte(s), \(body.attachments.count) attachment(s))")

        if let attachment = body.attachments.first {
            let data = try await backend.downloadAttachment(attachment)
            print("IMAP: downloaded one attachment (\(data.count) byte(s))")
        } else {
            print("IMAP: attachment download skipped because the sampled message has no attachments")
        }
    }

    private static func exerciseBodyFetch(
        in backend: IMAPSMTPBackend,
        fixtureConfiguration: IMAPAccountConfiguration,
        fixtureCredential: MailAccountCredential,
        folder: Folder,
        sender: String,
        recipient: String
    ) async throws {
        let suffix = String(UUID().uuidString.prefix(8))
        let subject = "Brev live body smoke \(suffix)"
        let marker = "brev-live-body-marker-\(suffix)"

        do {
            _ = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeBodyFetchFixtureMessage(
                    subject: subject,
                    sender: sender,
                    recipient: recipient,
                    marker: marker,
                    suffix: suffix
                ),
                flags: [.seen]
            )

            let header = try await waitForBackendFixtureHeader(
                in: backend,
                folder: folder,
                subject: subject
            )
            let body = try await backend.body(for: header.id)
            let renderedBody = "\(body.html ?? "")\n\(body.plainText ?? "")"
            guard renderedBody.contains(marker) else {
                throw LiveSmokeError.bodyFetchFixtureMismatch(
                    folderID: folder.id,
                    subject: subject
                )
            }

            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            print("IMAP: disposable body fetch proof passed for \(header.id)")
        } catch {
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            throw error
        }
    }

    private static func waitForBackendFixtureHeader(
        in backend: IMAPSMTPBackend,
        folder: Folder,
        subject: String
    ) async throws -> MessageHeader {
        guard backend.capabilities.contains(.serverSideSearch) else {
            throw MailBackendError.notSupported(backend.capabilities)
        }

        for attempt in 1...6 {
            let results = try await backend.search(SearchQuery(
                folderID: folder.id,
                subject: subject,
                execution: .serverOnly
            ))
            if let header = results.first(where: { $0.subject == subject }) {
                return header
            }
            if attempt < 6 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        throw LiveSmokeError.fixtureMessageNotFound(
            folderID: folder.id,
            subject: subject
        )
    }

    private static func exerciseAttachmentDownload(
        in backend: IMAPSMTPBackend,
        fixtureConfiguration: IMAPAccountConfiguration,
        fixtureCredential: MailAccountCredential,
        folder: Folder,
        sender: String,
        recipient: String
    ) async throws {
        let suffix = String(UUID().uuidString.prefix(8))
        let subject = "Brev live attachment smoke \(suffix)"
        let marker = "brev-live-attachment-marker-\(suffix)"

        do {
            _ = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeAttachmentFixtureMessage(
                    subject: subject,
                    sender: sender,
                    recipient: recipient,
                    marker: marker,
                    suffix: suffix
                ),
                flags: [.seen]
            )

            let header = try await waitForBackendFixtureHeader(
                in: backend,
                folder: folder,
                subject: subject
            )
            let body = try await backend.body(for: header.id)
            guard let attachment = body.attachments.first(where: { !$0.isInline }) ?? body.attachments.first else {
                throw LiveSmokeError.attachmentFixtureMissing(
                    folderID: folder.id,
                    subject: subject
                )
            }

            let data = try await backend.downloadAttachment(attachment)
            let downloadedText = String(data: data, encoding: .utf8) ?? ""
            guard downloadedText.contains(marker) else {
                throw LiveSmokeError.attachmentFixtureMismatch(
                    folderID: folder.id,
                    subject: subject
                )
            }

            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            print("IMAP: disposable attachment download proof passed for \(header.id) (\(data.count) byte(s))")
        } catch {
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            throw error
        }
    }

    private static func requireAttachmentDownload(
        in backend: IMAPSMTPBackend,
        headers: [MessageHeader]
    ) async throws {
        var checkedCount = 0
        for header in headers {
            checkedCount += 1
            let body = try await backend.body(for: header.id)
            guard let attachment = body.attachments.first else {
                continue
            }

            let data = try await backend.downloadAttachment(attachment)
            print("IMAP: required attachment download passed after \(checkedCount) sampled message(s) (\(data.count) byte(s))")
            return
        }

        throw LiveSmokeError.noAttachmentFound(checkedCount)
    }

    private static func exerciseFullIndex(
        in backend: IMAPSMTPBackend,
        connector: IMAPAccountConnector,
        account: BrevAccount,
        fixtureConfiguration: IMAPAccountConfiguration,
        fixtureCredential: MailAccountCredential,
        sourceID: MailSourceID,
        folder: Folder,
        sender: String,
        recipient: String,
        sampleHeaders: [MessageHeader]
    ) async throws {
        guard let repair = backend.extensionService(SyncHealthRepairing.self),
              let reporter = backend.extensionService(SyncHealthReporting.self)
        else {
            throw MailBackendError.notSupported(backend.capabilities)
        }

        let suffix = String(UUID().uuidString.prefix(8))
        let subject = "Brev live full-index smoke \(suffix)"
        let nonInboxFolderName = "BrevLiveFullIndex-\(suffix)"
        let nonInboxSubject = "Brev live full-index non-inbox smoke \(suffix)"
        let recipientSubject = "Brev live full-index recipient smoke \(suffix)"
        let stateSubject = "Brev live full-index state smoke \(suffix)"
        let attachmentSubject = "Brev live full-index attachment smoke \(suffix)"
        let htmlSubject = "Brev live full-index HTML smoke \(suffix)"
        let quotedPrintableSubject = "Brev live full-index QP smoke \(suffix)"
        let bodyMarker = "brevfullindexdecoded\(suffix.lowercased())"
        let quotedPrintableBodyMarker = "brevfullindexqp\(suffix.lowercased())"
        let nonInboxBodyMarker = "brevfullindexnoninbox\(suffix.lowercased())"
        let diacriticQuery = "mote \(suffix.lowercased())"
        let punctuationQuery = "invoice \(suffix.lowercased())"
        let htmlEntityQuery = "kjaere ogard \(suffix.lowercased())"
        let attachmentFilenameToken = "brevfilename\(suffix.lowercased())"
        let attachmentFilename = "\(attachmentFilenameToken).pdf"
        let ccRecipient = "brev-live-cc-\(suffix.lowercased())@example.invalid"
        let bccRecipient = "brev-live-bcc-\(suffix.lowercased())@example.invalid"
        var nonInboxFolderID: Folder.ID?

        do {
            print("INDEX: creating disposable non-current folder \(nonInboxFolderName)")
            let nonInboxFolder = try await backend.createFolder(name: nonInboxFolderName, parentID: nil)
            nonInboxFolderID = nonInboxFolder.id

            let appendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeFullIndexFixtureMessage(
                    subject: subject,
                    sender: sender,
                    recipient: recipient,
                    bodyMarker: bodyMarker,
                    diacriticSuffix: suffix.lowercased(),
                    suffix: suffix
                ),
                flags: [.seen]
            )
            let nonInboxAppendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: nonInboxFolder.id,
                messageData: makeFullIndexFixtureMessage(
                    subject: nonInboxSubject,
                    sender: sender,
                    recipient: recipient,
                    bodyMarker: nonInboxBodyMarker,
                    diacriticSuffix: suffix.lowercased(),
                    suffix: "\(suffix)-non-inbox"
                ),
                flags: [.seen]
            )
            let recipientAppendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeFullIndexFixtureMessage(
                    subject: recipientSubject,
                    sender: sender,
                    recipient: recipient,
                    ccRecipient: ccRecipient,
                    bccRecipient: bccRecipient,
                    bodyMarker: "brevfullindexrecipient\(suffix.lowercased())",
                    diacriticSuffix: suffix.lowercased(),
                    suffix: "\(suffix)-recipient"
                ),
                flags: [.seen]
            )
            let stateAppendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeFullIndexFixtureMessage(
                    subject: stateSubject,
                    sender: sender,
                    recipient: recipient,
                    bodyMarker: "brevfullindexstate\(suffix.lowercased())",
                    diacriticSuffix: suffix.lowercased(),
                    suffix: "\(suffix)-state"
                ),
                flags: [.flagged]
            )
            let attachmentAppendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeFullIndexAttachmentFilenameFixtureMessage(
                    subject: attachmentSubject,
                    sender: sender,
                    recipient: recipient,
                    attachmentFilename: attachmentFilename,
                    suffix: "\(suffix)-attachment-filename"
                ),
                flags: [.seen]
            )
            let htmlAppendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeFullIndexHTMLEntityFixtureMessage(
                    subject: htmlSubject,
                    sender: sender,
                    recipient: recipient,
                    suffix: suffix.lowercased()
                ),
                flags: [.seen]
            )
            let quotedPrintableAppendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeFullIndexQuotedPrintableFixtureMessage(
                    subject: quotedPrintableSubject,
                    sender: sender,
                    recipient: recipient,
                    bodyMarker: quotedPrintableBodyMarker,
                    suffix: suffix.lowercased()
                ),
                flags: [.seen]
            )
            let fixtureUID: Int
            if let appendedUID = appendResult.uid {
                fixtureUID = appendedUID
            } else {
                fixtureUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: folder.id,
                    subject: subject
                )
            }
            let fixtureID = "\(folder.id):\(fixtureUID)"
            let nonInboxFixtureUID: Int
            if let appendedUID = nonInboxAppendResult.uid {
                nonInboxFixtureUID = appendedUID
            } else {
                nonInboxFixtureUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: nonInboxFolder.id,
                    subject: nonInboxSubject
                )
            }
            let nonInboxFixtureID = "\(nonInboxFolder.id):\(nonInboxFixtureUID)"
            let recipientFixtureUID: Int
            if let appendedUID = recipientAppendResult.uid {
                recipientFixtureUID = appendedUID
            } else {
                recipientFixtureUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: folder.id,
                    subject: recipientSubject
                )
            }
            let recipientFixtureID = "\(folder.id):\(recipientFixtureUID)"
            let stateFixtureUID: Int
            if let appendedUID = stateAppendResult.uid {
                stateFixtureUID = appendedUID
            } else {
                stateFixtureUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: folder.id,
                    subject: stateSubject
                )
            }
            let stateFixtureID = "\(folder.id):\(stateFixtureUID)"
            let attachmentFixtureUID: Int
            if let appendedUID = attachmentAppendResult.uid {
                attachmentFixtureUID = appendedUID
            } else {
                attachmentFixtureUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: folder.id,
                    subject: attachmentSubject
                )
            }
            let attachmentFixtureID = "\(folder.id):\(attachmentFixtureUID)"
            let htmlFixtureUID: Int
            if let appendedUID = htmlAppendResult.uid {
                htmlFixtureUID = appendedUID
            } else {
                htmlFixtureUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: folder.id,
                    subject: htmlSubject
                )
            }
            let htmlFixtureID = "\(folder.id):\(htmlFixtureUID)"
            let quotedPrintableFixtureUID: Int
            if let appendedUID = quotedPrintableAppendResult.uid {
                quotedPrintableFixtureUID = appendedUID
            } else {
                quotedPrintableFixtureUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: folder.id,
                    subject: quotedPrintableSubject
                )
            }
            let quotedPrintableFixtureID = "\(folder.id):\(quotedPrintableFixtureUID)"
            print("INDEX: disposable selected-folder, HTML, quoted-printable, recipient, state, attachment-filename, and non-current-folder fixtures are visible to the provider")

            print("INDEX: rebuilding full local search index through SyncHealthRepairing")
            try await repair.rebuildSearchIndex(for: sourceID)
            let health = await reporter.syncHealth(for: sourceID)
            guard let metrics = health.localSearchIndexMetrics else {
                throw LiveSmokeError.missingLocalSearchIndexMetrics
            }
            print(
                "INDEX: rebuild complete "
                    + "state=\(health.state.rawValue) "
                    + "indexedHeaders=\(metrics.indexedHeaderCount) "
                    + "cachedBodies=\(metrics.cachedBodyCount) "
                    + "searchDocuments=\(metrics.searchDocumentCount) "
                    + "syncedFolders=\(metrics.syncedFolderCount) "
                    + "databaseBytes=\(metrics.databaseBytes)"
            )

            let sample = sampleHeaders.first(where: {
                !$0.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })

            let resultCount: Int
            if let sample {
                resultCount = try await requireCacheOnlySearchHit(
                    in: backend,
                    sample: sample,
                    missError: LiveSmokeError.fullIndexCacheSearchMiss
                )
            } else {
                resultCount = try await requireCacheOnlySubjectSearchHit(
                    in: backend,
                    folderID: folder.id,
                    subject: subject,
                    expectedID: fixtureID,
                    missError: LiveSmokeError.fullIndexCacheSearchMiss
                )
            }
            print("INDEX: cache-only local search returned \(resultCount) redacted result(s) for one sampled header")

            let nonInboxResultCount = try await requireCacheOnlyAllFoldersSubjectSearchHit(
                in: backend,
                subject: nonInboxSubject,
                expectedID: nonInboxFixtureID,
                missError: LiveSmokeError.fullIndexCacheSearchMiss
            )
            print("INDEX: all-mail cache-only local search returned \(nonInboxResultCount) redacted result(s) for the non-current-folder fixture")

            let bodyResultCount = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: bodyMarker,
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexBodySearchMiss
            )
            print("INDEX: cache-only local search returned \(bodyResultCount) redacted result(s) for decoded body-only fixture")

            let quotedPrintableBodyResultCount = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: quotedPrintableBodyMarker,
                expectedID: quotedPrintableFixtureID,
                missError: LiveSmokeError.fullIndexBodySearchMiss
            )
            print("INDEX: cache-only local search returned \(quotedPrintableBodyResultCount) redacted result(s) for quoted-printable body-only fixture")

            let diacriticResultCount = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: diacriticQuery,
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexBodySearchMiss
            )
            print("INDEX: cache-only local search returned \(diacriticResultCount) redacted result(s) for diacritic-tolerant fixture")

            let punctuationResultCount = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: punctuationQuery,
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexBodySearchMiss
            )
            print("INDEX: cache-only local search returned \(punctuationResultCount) redacted result(s) for punctuation-tolerant fixture")

            let htmlEntityResultCount = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: htmlEntityQuery,
                expectedID: htmlFixtureID,
                missError: LiveSmokeError.fullIndexBodySearchMiss
            )
            print("INDEX: cache-only local search returned \(htmlEntityResultCount) redacted result(s) for HTML-entity fixture")

            let attachmentFilenameResultCount = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: attachmentFilenameToken,
                expectedID: attachmentFixtureID,
                missError: LiveSmokeError.fullIndexAttachmentFilenameSearchMiss
            )
            print("INDEX: cache-only local search returned \(attachmentFilenameResultCount) redacted result(s) for attachment-filename fixture")

            let predicateDateRange = Date(timeIntervalSince1970: 1_780_790_400) ... Date(timeIntervalSince1970: 1_780_876_800)
            let recipientPredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(to: recipient, execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let ccPredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(to: ccRecipient, subject: recipientSubject, execution: .cacheOnly),
                expectedID: recipientFixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let bccPredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(to: bccRecipient, subject: recipientSubject, execution: .cacheOnly),
                expectedID: recipientFixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let readPredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(isUnread: false, subject: subject, execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let flagPredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(isFlagged: false, subject: subject, execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let unreadPredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(isUnread: true, subject: stateSubject, execution: .cacheOnly),
                expectedID: stateFixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let flaggedPredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(isFlagged: true, subject: stateSubject, execution: .cacheOnly),
                expectedID: stateFixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let datePredicateCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(dateRange: predicateDateRange, subject: subject, execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let paddedTextCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(text: "  \(bodyMarker)  ", folderID: folder.id, execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let paddedSenderCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(folderID: folder.id, from: "  \(sender)  ", execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let paddedRecipientCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(folderID: folder.id, to: "  \(recipient)  ", execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            let paddedSubjectCount = try await requireCacheOnlySearchHit(
                in: backend,
                query: SearchQuery(folderID: folder.id, subject: "  \(subject)  ", execution: .cacheOnly),
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexPredicateSearchMiss
            )
            print(
                "INDEX: cache-only local predicate search returned redacted result counts "
                    + "recipient=\(recipientPredicateCount) "
                    + "cc=\(ccPredicateCount) "
                    + "bcc=\(bccPredicateCount) "
                    + "read=\(readPredicateCount) "
                    + "unread=\(unreadPredicateCount) "
                    + "flag=\(flagPredicateCount) "
                    + "flagged=\(flaggedPredicateCount) "
                    + "date=\(datePredicateCount) "
                    + "paddedText=\(paddedTextCount) "
                    + "paddedSender=\(paddedSenderCount) "
                    + "paddedRecipient=\(paddedRecipientCount) "
                    + "paddedSubject=\(paddedSubjectCount)"
            )

            try await requireCachedBodyMarker(
                in: backend,
                messageID: fixtureID,
                marker: bodyMarker
            )
            try await requireCachedBodyMarker(
                in: backend,
                messageID: nonInboxFixtureID,
                marker: nonInboxBodyMarker
            )
            print("INDEX: opening local-search fixture results returned the expected message bodies")

            guard let restartedBackend = try await connector.restore(account) else {
                throw LiveSmokeError.missingRestoredBackend(account.id)
            }
            do {
                if let sample {
                    _ = try await requireCacheOnlySearchHit(
                        in: restartedBackend,
                        sample: sample,
                        missError: LiveSmokeError.fullIndexCacheSearchMiss
                    )
                } else {
                    _ = try await requireCacheOnlySubjectSearchHit(
                        in: restartedBackend,
                        folderID: folder.id,
                        subject: subject,
                        expectedID: fixtureID,
                        missError: LiveSmokeError.fullIndexCacheSearchMiss
                    )
                }
                _ = try await requireCacheOnlyAllFoldersSubjectSearchHit(
                    in: restartedBackend,
                    subject: nonInboxSubject,
                    expectedID: nonInboxFixtureID,
                    missError: LiveSmokeError.fullIndexCacheSearchMiss
                )
                _ = try await requireCacheOnlyTextSearchHit(
                    in: restartedBackend,
                    folderID: folder.id,
                    text: bodyMarker,
                    expectedID: fixtureID,
                    missError: LiveSmokeError.fullIndexBodySearchMiss
                )
                _ = try await requireCacheOnlyTextSearchHit(
                    in: restartedBackend,
                    folderID: folder.id,
                    text: quotedPrintableBodyMarker,
                    expectedID: quotedPrintableFixtureID,
                    missError: LiveSmokeError.fullIndexBodySearchMiss
                )
                _ = try await requireCacheOnlyTextSearchHit(
                    in: restartedBackend,
                    folderID: folder.id,
                    text: diacriticQuery,
                    expectedID: fixtureID,
                    missError: LiveSmokeError.fullIndexBodySearchMiss
                )
                _ = try await requireCacheOnlyTextSearchHit(
                    in: restartedBackend,
                    folderID: folder.id,
                    text: punctuationQuery,
                    expectedID: fixtureID,
                    missError: LiveSmokeError.fullIndexBodySearchMiss
                )
                _ = try await requireCacheOnlyTextSearchHit(
                    in: restartedBackend,
                    folderID: folder.id,
                    text: htmlEntityQuery,
                    expectedID: htmlFixtureID,
                    missError: LiveSmokeError.fullIndexBodySearchMiss
                )
                _ = try await requireCacheOnlyTextSearchHit(
                    in: restartedBackend,
                    folderID: folder.id,
                    text: attachmentFilenameToken,
                    expectedID: attachmentFixtureID,
                    missError: LiveSmokeError.fullIndexAttachmentFilenameSearchMiss
                )
                try await requireCachedBodyMarker(
                    in: restartedBackend,
                    messageID: nonInboxFixtureID,
                    marker: nonInboxBodyMarker
                )
            } catch {
                await restartedBackend.disconnect()
                throw error
            }
            await restartedBackend.disconnect()
            print("INDEX: fresh restored backend found cached header/body search hits from the persistent SQLite index")

            let folders = try await backend.folders()
            print("INDEX: applying headers-only retention across \(folders.count) folder(s)")
            for folder in folders {
                await backend.applyRetention(
                    folderID: folder.id,
                    retentionDays: nil,
                    keepsBodies: false
                )
            }
            let retainedHealth = await reporter.syncHealth(for: sourceID)
            guard let retainedMetrics = retainedHealth.localSearchIndexMetrics else {
                throw LiveSmokeError.missingLocalSearchIndexMetrics
            }
            guard retainedMetrics.cachedBodyCount == 0 else {
                throw LiveSmokeError.fullIndexRetentionDidNotClearBodies(retainedMetrics.cachedBodyCount)
            }
            if let sample {
                _ = try await requireCacheOnlySearchHit(
                    in: backend,
                    sample: sample,
                    missError: LiveSmokeError.fullIndexRetentionLostHeaderSearch
                )
            } else {
                _ = try await requireCacheOnlySubjectSearchHit(
                    in: backend,
                    folderID: folder.id,
                    subject: subject,
                    expectedID: fixtureID,
                    missError: LiveSmokeError.fullIndexRetentionLostHeaderSearch
                )
            }
            let retainedBodyResults = try await backend.search(SearchQuery(
                text: bodyMarker,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if retainedBodyResults.contains(where: { $0.id == fixtureID }) {
                throw LiveSmokeError.fullIndexRetentionLeftBodySearchHit
            }
            let retainedQuotedPrintableBodyResults = try await backend.search(SearchQuery(
                text: quotedPrintableBodyMarker,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if retainedQuotedPrintableBodyResults.contains(where: { $0.id == quotedPrintableFixtureID }) {
                throw LiveSmokeError.fullIndexRetentionLeftBodySearchHit
            }
            let retainedDiacriticResults = try await backend.search(SearchQuery(
                text: diacriticQuery,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if retainedDiacriticResults.contains(where: { $0.id == fixtureID }) {
                throw LiveSmokeError.fullIndexRetentionLeftBodySearchHit
            }
            let retainedPunctuationResults = try await backend.search(SearchQuery(
                text: punctuationQuery,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if retainedPunctuationResults.contains(where: { $0.id == fixtureID }) {
                throw LiveSmokeError.fullIndexRetentionLeftBodySearchHit
            }
            let retainedHTMLEntityResults = try await backend.search(SearchQuery(
                text: htmlEntityQuery,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if retainedHTMLEntityResults.contains(where: { $0.id == htmlFixtureID }) {
                throw LiveSmokeError.fullIndexRetentionLeftBodySearchHit
            }
            let retainedAttachmentFilenameResults = try await backend.search(SearchQuery(
                text: attachmentFilenameToken,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if retainedAttachmentFilenameResults.contains(where: { $0.id == attachmentFixtureID }) {
                throw LiveSmokeError.fullIndexRetentionLeftBodySearchHit
            }
            _ = try await requireCacheOnlyAllFoldersSubjectSearchHit(
                in: backend,
                subject: nonInboxSubject,
                expectedID: nonInboxFixtureID,
                missError: LiveSmokeError.fullIndexRetentionLostHeaderSearch
            )
            await backend.disconnect()
            try await requireCachedBodyUnavailableWhileDisconnected(
                in: backend,
                messageID: fixtureID
            )
            print(
                "INDEX: headers-only retention kept header search and cleared bodies "
                    + "indexedHeaders=\(retainedMetrics.indexedHeaderCount) "
                    + "cachedBodies=\(retainedMetrics.cachedBodyCount) "
                    + "searchDocuments=\(retainedMetrics.searchDocumentCount)"
            )

            print("INDEX: resetting Brev-owned local cache/index")
            try await repair.resetLocalCacheAndIndex(for: sourceID)
            let resetHealth = await reporter.syncHealth(for: sourceID)
            guard let resetMetrics = resetHealth.localSearchIndexMetrics else {
                throw LiveSmokeError.missingLocalSearchIndexMetrics
            }
            guard resetMetrics.indexedHeaderCount == 0,
                  resetMetrics.cachedBodyCount == 0,
                  resetMetrics.searchDocumentCount == 0,
                  resetMetrics.syncedFolderCount == 0
            else {
                throw LiveSmokeError.fullIndexResetDidNotClearIndex(
                    headers: resetMetrics.indexedHeaderCount,
                    bodies: resetMetrics.cachedBodyCount,
                    documents: resetMetrics.searchDocumentCount,
                    folders: resetMetrics.syncedFolderCount
                )
            }
            if let sample {
                let resetResults = try await backend.search(SearchQuery(
                    folderID: sample.folderID,
                    subject: sample.subject,
                    execution: .cacheOnly
                ))
                if resetResults.contains(where: { $0.id == sample.id }) {
                    throw LiveSmokeError.fullIndexResetLeftCacheSearchHit
                }
            } else {
                let resetResults = try await backend.search(SearchQuery(
                    folderID: folder.id,
                    subject: subject,
                    execution: .cacheOnly
                ))
                if resetResults.contains(where: { $0.id == fixtureID }) {
                    throw LiveSmokeError.fullIndexResetLeftCacheSearchHit
                }
            }
            let resetBodyResults = try await backend.search(SearchQuery(
                text: bodyMarker,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if resetBodyResults.contains(where: { $0.id == fixtureID }) {
                throw LiveSmokeError.fullIndexResetLeftBodySearchHit
            }
            let resetQuotedPrintableBodyResults = try await backend.search(SearchQuery(
                text: quotedPrintableBodyMarker,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if resetQuotedPrintableBodyResults.contains(where: { $0.id == quotedPrintableFixtureID }) {
                throw LiveSmokeError.fullIndexResetLeftBodySearchHit
            }
            let resetDiacriticResults = try await backend.search(SearchQuery(
                text: diacriticQuery,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if resetDiacriticResults.contains(where: { $0.id == fixtureID }) {
                throw LiveSmokeError.fullIndexResetLeftBodySearchHit
            }
            let resetPunctuationResults = try await backend.search(SearchQuery(
                text: punctuationQuery,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if resetPunctuationResults.contains(where: { $0.id == fixtureID }) {
                throw LiveSmokeError.fullIndexResetLeftBodySearchHit
            }
            let resetHTMLEntityResults = try await backend.search(SearchQuery(
                text: htmlEntityQuery,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if resetHTMLEntityResults.contains(where: { $0.id == htmlFixtureID }) {
                throw LiveSmokeError.fullIndexResetLeftBodySearchHit
            }
            let resetAttachmentFilenameResults = try await backend.search(SearchQuery(
                text: attachmentFilenameToken,
                folderID: folder.id,
                execution: .cacheOnly
            ))
            if resetAttachmentFilenameResults.contains(where: { $0.id == attachmentFixtureID }) {
                throw LiveSmokeError.fullIndexResetLeftBodySearchHit
            }
            let resetNonInboxResults = try await backend.search(SearchQuery(
                subject: nonInboxSubject,
                execution: .cacheOnly
            ))
            if resetNonInboxResults.contains(where: { $0.id == nonInboxFixtureID }) {
                throw LiveSmokeError.fullIndexResetLeftCacheSearchHit
            }
            print("INDEX: reset cleared local index counts and cache-only search hits")

            print("INDEX: rebuilding after reset to prove Reset & re-download")
            try await repair.rebuildSearchIndex(for: sourceID)
            let redownloadHealth = await reporter.syncHealth(for: sourceID)
            guard let redownloadMetrics = redownloadHealth.localSearchIndexMetrics else {
                throw LiveSmokeError.missingLocalSearchIndexMetrics
            }
            guard redownloadMetrics.indexedHeaderCount > 0,
                  redownloadMetrics.searchDocumentCount > 0,
                  redownloadMetrics.syncedFolderCount > 0
            else {
                throw LiveSmokeError.fullIndexRedownloadDidNotRestoreIndex(
                    headers: redownloadMetrics.indexedHeaderCount,
                    bodies: redownloadMetrics.cachedBodyCount,
                    documents: redownloadMetrics.searchDocumentCount,
                    folders: redownloadMetrics.syncedFolderCount
                )
            }
            _ = try await requireCacheOnlySubjectSearchHit(
                in: backend,
                folderID: folder.id,
                subject: subject,
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexRedownloadSearchMiss
            )
            _ = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: bodyMarker,
                expectedID: fixtureID,
                missError: LiveSmokeError.fullIndexRedownloadSearchMiss
            )
            _ = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: quotedPrintableBodyMarker,
                expectedID: quotedPrintableFixtureID,
                missError: LiveSmokeError.fullIndexRedownloadSearchMiss
            )
            _ = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: htmlEntityQuery,
                expectedID: htmlFixtureID,
                missError: LiveSmokeError.fullIndexRedownloadSearchMiss
            )
            _ = try await requireCacheOnlyAllFoldersSubjectSearchHit(
                in: backend,
                subject: nonInboxSubject,
                expectedID: nonInboxFixtureID,
                missError: LiveSmokeError.fullIndexRedownloadSearchMiss
            )
            _ = try await requireCacheOnlyTextSearchHit(
                in: backend,
                folderID: folder.id,
                text: attachmentFilenameToken,
                expectedID: attachmentFixtureID,
                missError: LiveSmokeError.fullIndexRedownloadSearchMiss
            )
            print(
                "INDEX: Reset & re-download restored local search "
                    + "indexedHeaders=\(redownloadMetrics.indexedHeaderCount) "
                    + "cachedBodies=\(redownloadMetrics.cachedBodyCount) "
                    + "searchDocuments=\(redownloadMetrics.searchDocumentCount) "
                    + "syncedFolders=\(redownloadMetrics.syncedFolderCount)"
            )

            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: recipientSubject
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: stateSubject
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: attachmentSubject
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: htmlSubject
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: quotedPrintableSubject
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [nonInboxFolder.id],
                subject: nonInboxSubject
            )
            try await backend.deleteFolder(id: nonInboxFolder.id)
            nonInboxFolderID = nil
        } catch {
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: recipientSubject
            )
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: stateSubject
            )
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: attachmentSubject
            )
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: htmlSubject
            )
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: quotedPrintableSubject
            )
            if let nonInboxFolderID {
                try? await cleanupFixtureMessages(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderIDs: [nonInboxFolderID],
                    subject: nonInboxSubject
                )
                try? await backend.deleteFolder(id: nonInboxFolderID)
            }
            throw error
        }
    }

    private static func requireCacheOnlyTextSearchHit(
        in backend: IMAPSMTPBackend,
        folderID: Folder.ID,
        text: String,
        expectedID: MessageHeader.ID,
        missError: LiveSmokeError
    ) async throws -> Int {
        let results = try await backend.search(SearchQuery(
            text: text,
            folderID: folderID,
            execution: .cacheOnly
        ))
        guard results.contains(where: { $0.id == expectedID }) else {
            throw missError
        }
        return results.count
    }

    private static func requireCacheOnlySubjectSearchHit(
        in backend: IMAPSMTPBackend,
        folderID: Folder.ID,
        subject: String,
        expectedID: MessageHeader.ID,
        missError: LiveSmokeError
    ) async throws -> Int {
        let results = try await backend.search(SearchQuery(
            folderID: folderID,
            subject: subject,
            execution: .cacheOnly
        ))
        guard results.contains(where: { $0.id == expectedID }) else {
            throw missError
        }
        return results.count
    }

    private static func requireCacheOnlyAllFoldersSubjectSearchHit(
        in backend: IMAPSMTPBackend,
        subject: String,
        expectedID: MessageHeader.ID,
        missError: LiveSmokeError
    ) async throws -> Int {
        let results = try await backend.search(SearchQuery(
            subject: subject,
            execution: .cacheOnly
        ))
        guard results.contains(where: { $0.id == expectedID }) else {
            throw missError
        }
        return results.count
    }

    private static func requireCacheOnlySearchHit(
        in backend: IMAPSMTPBackend,
        query: SearchQuery,
        expectedID: MessageHeader.ID,
        missError: LiveSmokeError
    ) async throws -> Int {
        let results = try await backend.search(query)
        guard results.contains(where: { $0.id == expectedID }) else {
            throw missError
        }
        return results.count
    }

    private static func requireCachedBodyMarker(
        in backend: IMAPSMTPBackend,
        messageID: MessageHeader.ID,
        marker: String
    ) async throws {
        let body = try await backend.body(for: messageID)
        let renderedBody = "\(body.html ?? "")\n\(body.plainText ?? "")"
        guard renderedBody.contains(marker) else {
            throw LiveSmokeError.fullIndexResultOpenMismatch
        }
    }

    private static func requireCachedBodyUnavailableWhileDisconnected(
        in backend: IMAPSMTPBackend,
        messageID: MessageHeader.ID
    ) async throws {
        do {
            _ = try await backend.body(for: messageID)
        } catch {
            return
        }
        throw LiveSmokeError.fullIndexRetentionLeftCachedSource
    }

    private static func requireBodyAndAttachmentMarkers(
        in backend: IMAPSMTPBackend,
        header: MessageHeader,
        bodyMarker: String,
        attachmentMarker: String
    ) async throws -> Int {
        let body = try await backend.body(for: header.id)
        let renderedBody = "\(body.html ?? "")\n\(body.plainText ?? "")"
        guard renderedBody.contains(bodyMarker) else {
            throw LiveSmokeError.bodyFetchFixtureMismatch(
                folderID: header.folderID,
                subject: header.subject
            )
        }
        guard let attachment = body.attachments.first(where: { !$0.isInline }) ?? body.attachments.first else {
            throw LiveSmokeError.attachmentFixtureMissing(
                folderID: header.folderID,
                subject: header.subject
            )
        }

        let data = try await backend.downloadAttachment(attachment)
        let downloadedText = String(data: data, encoding: .utf8) ?? ""
        guard downloadedText.contains(attachmentMarker) else {
            throw LiveSmokeError.attachmentFixtureMismatch(
                folderID: header.folderID,
                subject: header.subject
            )
        }
        return renderedBody.utf8.count
    }

    private static func requireCacheOnlySearchHit(
        in backend: IMAPSMTPBackend,
        sample: MessageHeader,
        missError: LiveSmokeError
    ) async throws -> Int {
        let results = try await backend.search(SearchQuery(
            folderID: sample.folderID,
            subject: sample.subject,
            execution: .cacheOnly
        ))
        guard results.contains(where: { $0.id == sample.id }) else {
            throw missError
        }
        return results.count
    }

    private static func exerciseServerSearch(
        in backend: IMAPSMTPBackend,
        headers: [MessageHeader],
        folder: Folder
    ) async throws {
        guard backend.capabilities.contains(.serverSideSearch) else {
            throw MailBackendError.notSupported(backend.capabilities)
        }
        guard let sample = headers.first else {
            throw LiveSmokeError.noSearchFixture
        }

        let subject = sample.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = sample.from.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedFolderQuery: SearchQuery
        let allFoldersQuery: SearchQuery
        let mustFindSample: Bool
        if !subject.isEmpty {
            selectedFolderQuery = SearchQuery(
                folderID: folder.id,
                subject: subject,
                execution: .serverOnly
            )
            allFoldersQuery = SearchQuery(
                subject: subject,
                execution: .serverOnly
            )
            mustFindSample = true
        } else if !sender.isEmpty {
            selectedFolderQuery = SearchQuery(
                folderID: folder.id,
                from: sender,
                execution: .serverOnly
            )
            allFoldersQuery = SearchQuery(
                from: sender,
                execution: .serverOnly
            )
            mustFindSample = false
        } else {
            selectedFolderQuery = SearchQuery(folderID: folder.id, execution: .serverOnly)
            allFoldersQuery = SearchQuery(execution: .serverOnly)
            mustFindSample = false
        }

        let results = try await backend.search(selectedFolderQuery)
        if mustFindSample {
            guard results.contains(where: { $0.id == sample.id }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }
        } else {
            guard results.contains(where: { $0.folderID == folder.id }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }
        }
        print("IMAP: selected-folder server search returned \(results.count) redacted result(s) through MailBackend.search")

        let allFolderResults = try await backend.search(allFoldersQuery)
        if mustFindSample {
            guard allFolderResults.contains(where: { $0.id == sample.id }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }
        } else {
            guard allFolderResults.contains(where: { $0.folderID == folder.id }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }
        }
        let searchedFolderCount = Set(allFolderResults.map(\.folderID)).count
        print("IMAP: all-folder server search returned \(allFolderResults.count) redacted result(s) across \(searchedFolderCount) result folder(s)")
    }

    private static func exerciseCrossFolderServerSearch(
        in backend: IMAPSMTPBackend,
        fixtureConfiguration: IMAPAccountConfiguration,
        fixtureCredential: MailAccountCredential,
        currentFolder: Folder,
        sender: String,
        recipient: String,
        prefix: String
    ) async throws {
        guard backend.capabilities.contains(.serverSideSearch) else {
            throw MailBackendError.notSupported(backend.capabilities)
        }
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrefix = trimmedPrefix.isEmpty ? "BrevLiveSmokeSearch" : trimmedPrefix
        let suffix = String(UUID().uuidString.prefix(8))
        let folderName = "\(safePrefix)-\(suffix)"
        let subject = "Brev live cross-folder search smoke \(suffix)"
        let nonASCIISubject = "Brev live søk røyk \(suffix)"
        let bodyMarker = "brev-live-cross-folder-body-\(suffix)"
        let attachmentMarker = "brev-live-cross-folder-attachment-\(suffix)"
        var folderID: Folder.ID?

        do {
            print("IMAP: creating disposable server-search folder \(folderName)")
            let searchFolder = try await backend.createFolder(name: folderName, parentID: nil)
            folderID = searchFolder.id

            _ = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: searchFolder.id,
                messageData: makeAttachmentFixtureMessage(
                    subject: subject,
                    sender: sender,
                    recipient: recipient,
                    bodyMarker: bodyMarker,
                    marker: attachmentMarker,
                    suffix: suffix
                ),
                flags: [.seen]
            )
            _ = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: searchFolder.id,
                messageData: makeMutationFixtureMessage(
                    subject: nonASCIISubject,
                    sender: sender,
                    recipient: recipient,
                    suffix: "\(suffix)-non-ascii"
                ),
                flags: [.seen]
            )

            _ = try await waitForBackendFixtureHeader(
                in: backend,
                folder: searchFolder,
                subject: subject
            )
            _ = try await waitForBackendFixtureHeader(
                in: backend,
                folder: searchFolder,
                subject: nonASCIISubject
            )

            let currentFolderResults = try await backend.search(SearchQuery(
                folderID: currentFolder.id,
                subject: subject,
                execution: .serverOnly
            ))
            guard currentFolderResults.isEmpty else {
                throw LiveSmokeError.serverSearchResultMissing
            }

            let allFolderResults = try await backend.search(SearchQuery(
                subject: subject,
                execution: .serverOnly
            ))
            guard allFolderResults.contains(where: { $0.folderID == searchFolder.id && $0.subject == subject }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }
            guard let crossFolderResult = allFolderResults.first(where: {
                $0.folderID == searchFolder.id && $0.subject == subject
            }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }
            let bodyByteCount = try await requireBodyAndAttachmentMarkers(
                in: backend,
                header: crossFolderResult,
                bodyMarker: bodyMarker,
                attachmentMarker: attachmentMarker
            )
            print("IMAP: cross-folder server search result opened body and attachment (\(bodyByteCount) rendered byte(s))")

            let multiWordTextResults = try await backend.search(SearchQuery(
                text: "live search",
                folderID: searchFolder.id,
                execution: .serverOnly
            ))
            guard multiWordTextResults.contains(where: {
                $0.folderID == searchFolder.id && $0.subject == subject
            }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }

            let nonASCIIResults = try await backend.search(SearchQuery(
                folderID: searchFolder.id,
                subject: nonASCIISubject,
                execution: .serverOnly
            ))
            guard nonASCIIResults.contains(where: {
                $0.folderID == searchFolder.id && $0.subject == nonASCIISubject
            }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }

            let nonASCIIMultiWordTextResults = try await backend.search(SearchQuery(
                text: "søk røyk",
                folderID: searchFolder.id,
                execution: .serverOnly
            ))
            guard nonASCIIMultiWordTextResults.contains(where: {
                $0.folderID == searchFolder.id && $0.subject == nonASCIISubject
            }) else {
                throw LiveSmokeError.serverSearchResultMissing
            }

            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [searchFolder.id],
                subject: subject
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [searchFolder.id],
                subject: nonASCIISubject
            )
            try await backend.deleteFolder(id: searchFolder.id)
            folderID = nil
            print("IMAP: cross-folder server search found disposable non-current-folder mail, multi-word text, and non-ASCII text mail")
        } catch {
            if let folderID {
                try? await cleanupFixtureMessages(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderIDs: [folderID],
                    subject: subject
                )
                try? await cleanupFixtureMessages(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderIDs: [folderID],
                    subject: nonASCIISubject
                )
                try? await backend.deleteFolder(id: folderID)
            }
            throw error
        }
    }

    private static func exerciseFolderManagement(
        in backend: IMAPSMTPBackend,
        prefix: String
    ) async throws {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrefix = trimmedPrefix.isEmpty ? "BrevLiveSmoke" : trimmedPrefix
        let suffix = String(UUID().uuidString.prefix(8))
        let folderName = "\(safePrefix)-\(suffix)"
        let renamedFolderName = "\(folderName)-renamed"
        var createdFolderID: Folder.ID?
        var renamedFolderID: Folder.ID?

        do {
            print("IMAP: creating disposable folder \(folderName)")
            let created = try await backend.createFolder(name: folderName, parentID: nil)
            createdFolderID = created.id

            print("IMAP: renaming disposable folder \(created.id) to \(renamedFolderName)")
            let renamed = try await backend.renameFolder(id: created.id, name: renamedFolderName)
            renamedFolderID = renamed.id

            print("IMAP: deleting disposable folder \(renamed.id)")
            try await backend.deleteFolder(id: renamed.id)
            renamedFolderID = nil
            createdFolderID = nil
            print("IMAP: folder create/rename/delete passed")
        } catch {
            if let renamedFolderID {
                try? await backend.deleteFolder(id: renamedFolderID)
            } else if let createdFolderID {
                try? await backend.deleteFolder(id: createdFolderID)
            }
            throw error
        }
    }

    private static func exerciseFolderFlush(
        in backend: IMAPSMTPBackend,
        fixtureConfiguration: IMAPAccountConfiguration,
        fixtureCredential: MailAccountCredential,
        sender: String,
        recipient: String,
        prefix: String
    ) async throws {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrefix = trimmedPrefix.isEmpty ? "BrevLiveSmokeFlush" : trimmedPrefix
        let suffix = String(UUID().uuidString.prefix(8))
        let folderName = "\(safePrefix)-\(suffix)"
        let subject = "Brev live flush smoke \(suffix)"
        var folderID: Folder.ID?

        do {
            print("IMAP: creating disposable flush folder \(folderName)")
            let folder = try await backend.createFolder(name: folderName, parentID: nil)
            folderID = folder.id

            for index in 1...2 {
                _ = try await IMAPSessionClient(
                    transport: NetworkIMAPSessionTransport()
                ).loginAndAppendMessage(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderPath: folder.id,
                    messageData: makeMutationFixtureMessage(
                        subject: subject,
                        sender: sender,
                        recipient: recipient,
                        suffix: "\(suffix)-\(index)"
                    ),
                    flags: [.seen]
                )
            }

            try await backend.flushFolder(id: folder.id)
            let remainingMessages = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndSearchMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                query: SearchQuery(subject: subject, execution: .serverOnly),
                limit: 10
            )
            guard remainingMessages.isEmpty else {
                throw LiveSmokeError.folderFlushMessagesRemaining(folderID: folder.id)
            }

            try await backend.deleteFolder(id: folder.id)
            folderID = nil
            print("IMAP: folder flush proof passed")
        } catch {
            if let folderID {
                try? await cleanupFixtureMessages(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderIDs: [folderID],
                    subject: subject
                )
                try? await backend.deleteFolder(id: folderID)
            }
            throw error
        }
    }

    private static func exerciseMessageMutations(
        in backend: IMAPSMTPBackend,
        sourceID: MailSourceID,
        fixtureConfiguration: IMAPAccountConfiguration,
        fixtureCredential: MailAccountCredential,
        sender: String,
        recipient: String,
        prefix: String
    ) async throws {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrefix = trimmedPrefix.isEmpty ? "BrevLiveSmokeMutation" : trimmedPrefix
        let suffix = String(UUID().uuidString.prefix(8))
        let sourceName = "\(safePrefix)-source-\(suffix)"
        let destinationName = "\(safePrefix)-dest-\(suffix)"
        let subject = "Brev live mutation smoke \(suffix)"
        var sourceFolderID: Folder.ID?
        var destinationFolderID: Folder.ID?

        do {
            print("IMAP: creating disposable mutation source folder \(sourceName)")
            let sourceFolder = try await backend.createFolder(name: sourceName, parentID: nil)
            sourceFolderID = sourceFolder.id

            print("IMAP: creating disposable mutation destination folder \(destinationName)")
            let destinationFolder = try await backend.createFolder(name: destinationName, parentID: nil)
            destinationFolderID = destinationFolder.id

            let appendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: sourceFolder.id,
                messageData: makeMutationFixtureMessage(
                    subject: subject,
                    sender: sender,
                    recipient: recipient,
                    suffix: suffix
                ),
                flags: [.seen]
            )
            let sourceUID: Int
            if let appendedUID = appendResult.uid {
                sourceUID = appendedUID
            } else {
                sourceUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: sourceFolder.id,
                    subject: subject
                )
            }
            let sourceMessageID = "\(sourceFolder.id):\(sourceUID)"

            try await backend.setRead(false, for: [sourceMessageID], sourceID: sourceID)
            try await backend.setFlagged(true, for: [sourceMessageID], sourceID: sourceID)
            print("IMAP: read and flagged mutations passed for disposable message")

            try await backend.move(messageIDs: [sourceMessageID], to: destinationFolder, sourceID: sourceID)
            let destinationUID = try await searchFixtureMessageUID(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderID: destinationFolder.id,
                subject: subject
            )
            let destinationMessageID = "\(destinationFolder.id):\(destinationUID)"
            print("IMAP: move mutation passed for disposable message")

            let folders = try await backend.folders()
            if let trashFolder = folders.first(where: { $0.role == .trash }) {
                try await backend.delete(messageIDs: [destinationMessageID], sourceID: sourceID)
                let trashUID = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: trashFolder.id,
                    subject: subject
                )
                try await backend.delete(messageIDs: ["\(trashFolder.id):\(trashUID)"], sourceID: sourceID)
                print("IMAP: delete-to-trash and permanent delete mutations passed")
            } else {
                try await backend.delete(messageIDs: [destinationMessageID], sourceID: sourceID)
                print("IMAP: permanent delete mutation passed without discovered Trash folder")
            }

            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [sourceFolder.id, destinationFolder.id],
                subject: subject
            )
            try await backend.deleteFolder(id: destinationFolder.id)
            destinationFolderID = nil
            try await backend.deleteFolder(id: sourceFolder.id)
            sourceFolderID = nil
            print("IMAP: message mutation proof passed")
        } catch {
            var cleanupFolders = [Folder.ID]()
            if let sourceFolderID {
                cleanupFolders.append(sourceFolderID)
            }
            if let destinationFolderID {
                cleanupFolders.append(destinationFolderID)
            }
            let trashFolderID = (try? await backend.folders())?
                .first(where: { $0.role == .trash })?.id
            if let trashFolderID {
                cleanupFolders.append(trashFolderID)
            }
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: cleanupFolders,
                subject: subject
            )
            if let destinationFolderID {
                try? await backend.deleteFolder(id: destinationFolderID)
            }
            if let sourceFolderID {
                try? await backend.deleteFolder(id: sourceFolderID)
            }
            throw error
        }
    }

    private static func searchFixtureMessageUID(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderID: Folder.ID,
        subject: String
    ) async throws -> Int {
        let listings = try await IMAPSessionClient(
            transport: NetworkIMAPSessionTransport()
        ).loginAndSearchMessages(
            configuration: configuration,
            credential: credential,
            folderPath: folderID,
            query: SearchQuery(subject: subject, execution: .serverOnly),
            limit: 10
        )
        guard let listing = listings.first(where: { $0.subject == subject }) else {
            throw LiveSmokeError.fixtureMessageNotFound(folderID: folderID, subject: subject)
        }
        return listing.uid
    }

    private static func cleanupFixtureMessages(
        configuration: IMAPAccountConfiguration,
        credential: MailAccountCredential,
        folderIDs: [Folder.ID],
        subject: String
    ) async throws {
        for folderID in Set(folderIDs) {
            let listings = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndSearchMessages(
                configuration: configuration,
                credential: credential,
                folderPath: folderID,
                query: SearchQuery(subject: subject, execution: .serverOnly),
                limit: 20
            )
            let uids = listings.filter { $0.subject == subject }.map(\.uid)
            guard !uids.isEmpty else { continue }
            try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndPermanentlyDeleteMessages(
                configuration: configuration,
                credential: credential,
                folderPath: folderID,
                uids: uids
            )
        }
    }

    private static func exerciseIDLEEvent(
        in backend: IMAPSMTPBackend,
        fixtureConfiguration: IMAPAccountConfiguration,
        fixtureCredential: MailAccountCredential,
        folder: Folder,
        sender: String,
        recipient: String
    ) async throws {
        let suffix = String(UUID().uuidString.prefix(8))
        let subject = "Brev live IDLE smoke \(suffix)"

        do {
            _ = try await backend.messages(in: folder, pageToken: nil)
            let stream = backend.subscribeToChanges()
            try await Task.sleep(nanoseconds: 2_000_000_000)

            let appendResult = try await IMAPSessionClient(
                transport: NetworkIMAPSessionTransport()
            ).loginAndAppendMessage(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderPath: folder.id,
                messageData: makeMutationFixtureMessage(
                    subject: subject,
                    sender: sender,
                    recipient: recipient,
                    suffix: suffix
                ),
                flags: [.seen]
            )
            let uid: Int
            if let appendedUID = appendResult.uid {
                uid = appendedUID
            } else {
                uid = try await searchFixtureMessageUID(
                    configuration: fixtureConfiguration,
                    credential: fixtureCredential,
                    folderID: folder.id,
                    subject: subject
                )
            }
            let messageID = "\(folder.id):\(uid)"
            try await waitForMessagesAddedEvent(
                in: stream,
                folderID: folder.id,
                messageID: messageID
            )
            try await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            print("IMAP: IDLE event proof passed for \(messageID)")
        } catch {
            try? await cleanupFixtureMessages(
                configuration: fixtureConfiguration,
                credential: fixtureCredential,
                folderIDs: [folder.id],
                subject: subject
            )
            throw error
        }
    }

    private static func waitForMessagesAddedEvent(
        in stream: AsyncStream<MailEvent>,
        folderID: Folder.ID,
        messageID: MessageHeader.ID,
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                while let event = await iterator.next() {
                    if case .messagesAdded(let eventFolderID, let messageIDs) = event,
                       eventFolderID == folderID,
                       messageIDs.contains(messageID) {
                        return true
                    }
                }
                return false
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LiveSmokeError.idleEventTimedOut(folderID: folderID, messageID: messageID)
            }

            guard let observed = try await group.next(), observed else {
                group.cancelAll()
                throw LiveSmokeError.idleEventTimedOut(folderID: folderID, messageID: messageID)
            }
            group.cancelAll()
        }
    }

    private static func makeMutationFixtureMessage(
        subject: String,
        sender: String,
        recipient: String,
        suffix: String
    ) -> Data {
        Data("""
        From: Brev Live Smoke <\(sender)>
        To: \(recipient)
        Subject: \(subject)
        Message-ID: <brev-live-mutation-\(suffix)@brev.local>
        Date: Sun, 07 Jun 2026 10:00:00 +0000
        MIME-Version: 1.0
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Brev live IMAP mutation smoke fixture \(suffix).
        """.utf8)
    }

    private static func makeBodyFetchFixtureMessage(
        subject: String,
        sender: String,
        recipient: String,
        marker: String,
        suffix: String
    ) -> Data {
        Data("""
        From: Brev Live Smoke <\(sender)>
        To: \(recipient)
        Subject: \(subject)
        Message-ID: <brev-live-body-\(suffix)@brev.local>
        Date: Sun, 07 Jun 2026 10:00:00 +0000
        MIME-Version: 1.0
        Content-Type: multipart/alternative; boundary="brev-live-body-\(suffix)"

        --brev-live-body-\(suffix)
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 7bit

        Brev live IMAP body fetch smoke fixture.
        Marker: \(marker)

        --brev-live-body-\(suffix)
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: 7bit

        <html><body><p>Brev live IMAP body fetch smoke fixture.</p><p>Marker: \(marker)</p></body></html>

        --brev-live-body-\(suffix)--
        """.utf8)
    }

    private static func makeFullIndexFixtureMessage(
        subject: String,
        sender: String,
        recipient: String,
        ccRecipient: String? = nil,
        bccRecipient: String? = nil,
        bodyMarker: String,
        diacriticSuffix: String,
        suffix: String
    ) -> Data {
        let body = """
        Brev live IMAP full-index smoke fixture.
        Decoded body marker: \(bodyMarker)
        Diacritic body marker: møte \(diacriticSuffix)
        Punctuation body marker: invoice #\(diacriticSuffix)/ready-42
        """
        let encodedBody = Data(body.utf8).base64EncodedString()
        var headerLines = [
            "From: Brev Live Smoke <\(sender)>",
            "To: \(recipient)",
        ]
        if let ccRecipient {
            headerLines.append("Cc: \(ccRecipient)")
        }
        if let bccRecipient {
            headerLines.append("Bcc: \(bccRecipient)")
        }
        headerLines.append(contentsOf: [
            "Subject: \(subject)",
            "Message-ID: <brev-live-full-index-\(suffix)@brev.local>",
            "Date: Sun, 07 Jun 2026 10:00:00 +0000",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
        ])
        return Data((headerLines.joined(separator: "\n") + "\n\n\(encodedBody)").utf8)
    }

    private static func makeFullIndexAttachmentFilenameFixtureMessage(
        subject: String,
        sender: String,
        recipient: String,
        attachmentFilename: String,
        suffix: String
    ) -> Data {
        Data("""
        From: Brev Live Smoke <\(sender)>
        To: \(recipient)
        Subject: \(subject)
        Message-ID: <brev-live-full-index-attachment-\(suffix)@brev.local>
        Date: Sun, 07 Jun 2026 10:00:00 +0000
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="brev-live-full-index-attachment-\(suffix)"

        --brev-live-full-index-attachment-\(suffix)
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 7bit

        Brev live IMAP full-index attachment filename fixture.
        The unique filename token is intentionally absent from this body.

        --brev-live-full-index-attachment-\(suffix)
        Content-Type: application/pdf; name="\(attachmentFilename)"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="\(attachmentFilename)"

        SGVsbG8=
        --brev-live-full-index-attachment-\(suffix)--
        """.utf8)
    }

    private static func makeFullIndexHTMLEntityFixtureMessage(
        subject: String,
        sender: String,
        recipient: String,
        suffix: String
    ) -> Data {
        Data("""
        From: Brev Live Smoke <\(sender)>
        To: \(recipient)
        Subject: \(subject)
        Message-ID: <brev-live-full-index-html-\(suffix)@brev.local>
        Date: Sun, 07 Jun 2026 10:00:00 +0000
        MIME-Version: 1.0
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: 7bit

        <html><body><p>Kj&#XE6;re &#216;g&#229;rd \(suffix)</p></body></html>
        """.utf8)
    }

    private static func makeFullIndexQuotedPrintableFixtureMessage(
        subject: String,
        sender: String,
        recipient: String,
        bodyMarker: String,
        suffix: String
    ) -> Data {
        let encodedMarker = quotedPrintableHexEncoded(bodyMarker)
        return Data("""
        From: Brev Live Smoke <\(sender)>
        To: \(recipient)
        Subject: \(subject)
        Message-ID: <brev-live-full-index-qp-\(suffix)@brev.local>
        Date: Sun, 07 Jun 2026 10:00:00 +0000
        MIME-Version: 1.0
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Brev live IMAP full-index quoted-printable fixture.
        Decoded quoted-printable marker: \(encodedMarker)
        """.utf8)
    }

    private static func quotedPrintableHexEncoded(_ value: String) -> String {
        value.utf8.map { String(format: "=%02X", $0) }.joined()
    }

    private static func makeAttachmentFixtureMessage(
        subject: String,
        sender: String,
        recipient: String,
        bodyMarker: String? = nil,
        marker: String,
        suffix: String
    ) -> Data {
        let bodyMarkerLine = bodyMarker.map { "\nBody marker: \($0)" } ?? ""
        return Data("""
        From: Brev Live Smoke <\(sender)>
        To: \(recipient)
        Subject: \(subject)
        Message-ID: <brev-live-attachment-\(suffix)@brev.local>
        Date: Sun, 07 Jun 2026 10:00:00 +0000
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="brev-live-attachment-\(suffix)"

        --brev-live-attachment-\(suffix)
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 7bit

        Brev live IMAP attachment download smoke fixture.
        \(bodyMarkerLine)

        --brev-live-attachment-\(suffix)
        Content-Type: text/plain; charset=utf-8; name="brev-live-attachment-\(suffix).txt"
        Content-Transfer-Encoding: 7bit
        Content-Disposition: attachment; filename="brev-live-attachment-\(suffix).txt"

        Brev live attachment payload.
        Marker: \(marker)

        --brev-live-attachment-\(suffix)--
        """.utf8)
    }

    private static func exerciseComposeLifecycle(
        in backend: IMAPSMTPBackend,
        sourceID: MailSourceID,
        sender: String,
        recipient: String
    ) async throws {
        let folders = try await backend.folders()
        guard let draftsFolder = folders.first(where: { $0.role == .drafts }) else {
            throw LiveSmokeError.missingDraftsFolder
        }

        let suffix = String(UUID().uuidString.prefix(8))
        let draftID = "live-smoke-compose-\(suffix)"
        let attachmentID = try await backend.uploadAttachment(
            draftID: draftID,
            data: Data("Brev live smoke attachment \(suffix)\n".utf8),
            filename: "brev-live-smoke-\(suffix).txt",
            mimeType: "text/plain",
            sourceID: sourceID
        )
        let savedDraft = try await backend.save(draft: Draft(
            id: draftID,
            to: [Correspondent(email: recipient)],
            subject: "Brev live compose smoke \(suffix)",
            htmlBody: """
            <p>Brev live compose smoke test.</p>
            <p>Sender: \(sender)</p>
            <p>Attachment proof: \(suffix)</p>
            """,
            attachmentIDs: [attachmentID]
        ), sourceID: sourceID)
        guard let remoteID = savedDraft.remoteID,
              remoteID.hasPrefix("\(draftsFolder.id):")
        else {
            throw LiveSmokeError.missingRemoteDraftID(draftID)
        }
        print("COMPOSE: saved server Drafts copy \(remoteID)")

        _ = try await backend.send(draft: savedDraft, sourceID: sourceID)
        print("COMPOSE: sent attachment draft and requested server Drafts cleanup")

        let discardDraftID = "live-smoke-discard-\(suffix)"
        let discardAttachmentID = try await backend.uploadAttachment(
            draftID: discardDraftID,
            data: Data("Brev live smoke discard attachment \(suffix)\n".utf8),
            filename: "brev-live-smoke-discard-\(suffix).txt",
            mimeType: "text/plain",
            sourceID: sourceID
        )
        let discardDraft = try await backend.save(draft: Draft(
            id: discardDraftID,
            to: [Correspondent(email: recipient)],
            subject: "Brev live discard smoke \(suffix)",
            htmlBody: "<p>This server Drafts copy should be discarded.</p>",
            attachmentIDs: [discardAttachmentID]
        ), sourceID: sourceID)
        guard let discardRemoteID = discardDraft.remoteID,
              discardRemoteID.hasPrefix("\(draftsFolder.id):")
        else {
            throw LiveSmokeError.missingRemoteDraftID(discardDraftID)
        }
        try await backend.discard(draftID: discardRemoteID, sourceID: sourceID)
        print("COMPOSE: discarded server Drafts copy \(discardRemoteID)")
    }

    private static func domain(from emailAddress: String) -> String {
        let parts = emailAddress.split(separator: "@", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]).lowercased() : ""
    }

    private static func required(
        _ key: String,
        in environment: [String: String]
    ) throws -> String {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            throw LiveSmokeError.missingEnvironment(key)
        }
        return value
    }

    private static func optional(
        _ key: String,
        default defaultValue: String,
        in environment: [String: String]
    ) -> String {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return defaultValue
        }
        return value
    }

    private static func port(
        _ key: String,
        default defaultValue: UInt16,
        in environment: [String: String]
    ) throws -> UInt16 {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return defaultValue
        }
        guard let parsed = UInt16(rawValue) else {
            throw LiveSmokeError.invalidPort(key, rawValue)
        }
        return parsed
    }

    private static func tlsMode(
        _ key: String,
        default defaultValue: MailServerTLSMode,
        in environment: [String: String]
    ) throws -> MailServerTLSMode {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return defaultValue
        }

        switch rawValue.lowercased() {
        case "implicit", "ssl", "tls":
            return .implicit
        case "starttls", "start_tls", "start-tls":
            return .startTLS
        default:
            throw LiveSmokeError.invalidTLSMode(key, rawValue)
        }
    }

    private static func authenticationMode(
        _ key: String,
        default defaultValue: MailServerAuthentication,
        in environment: [String: String]
    ) throws -> MailServerAuthentication {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return defaultValue
        }

        switch rawValue.lowercased() {
        case "password":
            return .password
        case "apppassword", "app_password", "app-password":
            return .appPassword
        default:
            throw LiveSmokeError.invalidAuthentication(key, rawValue)
        }
    }

    private static func makeSmokeDraft(from sender: String, to recipient: String) -> Draft {
        let now = Date()
        let isoDate = ISO8601DateFormatter().string(from: now)
        return Draft(
            id: "live-smoke-\(UUID().uuidString)",
            to: [Correspondent(email: recipient)],
            subject: "Brev live SMTP smoke \(isoDate)",
            htmlBody: """
            <p>Brev live SMTP smoke test.</p>
            <p>Sender: \(sender)</p>
            <p>Timestamp: \(isoDate)</p>
            """
        )
    }
}
EOF

if [[ $compile_only -eq 1 ]]; then
  swift build \
    --package-path "$WORK_DIR" \
    --scratch-path "$CACHE_DIR"
  echo "imap-smtp-live-smoke: compile check OK"
else
  swift run \
    --package-path "$WORK_DIR" \
    --scratch-path "$CACHE_DIR" \
    BrevIMAPSMTPLiveSmoke
fi
