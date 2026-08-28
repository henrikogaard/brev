# ADR-0029: IMAP/SMTP backend foundation

- **Status:** Accepted
- **Date:** 2026-06-06
- **Deciders:** Henrik

## Context

ADR-0028 changes Brev's launch backend from provider-first to
standards-first IMAP/SMTP. That change preserves the existing
`MailBackend` boundary. The first implementation slice now contains
generic IMAP/SMTP account setup, non-secret server configuration
storage, Keychain-backed password/app-password storage, autodiscovery,
an injected IMAP session client, and a narrow backend that can connect
and list, create, rename, and delete folders plus newest message headers
through `UID SEARCH` / `UID FETCH (FLAGS ENVELOPE)` with UID-based page tokens
for older windows. Folder listing decodes IMAP modified UTF-7 mailbox names
into normal app-facing folder paths, remembers the provider hierarchy
delimiter from `LIST`, preserves that delimiter for nested folder create/rename
operations, and outbound mailbox commands encode app paths back to modified
UTF-7 at the protocol boundary. The autodiscovery resolver validates email
addresses before
any network probe, checks DNS SRV before provider HTTPS autoconfig so a complete
domain-only SRV result avoids sending the full email address to autoconfig
hosts, percent-encodes provider autoconfig email query values so tagged
addresses such as `person+tag@example.org` are not reinterpreted by server
query parsers, ignores Thunderbird/Mozilla autoconfig entries that advertise
plaintext mail access, rejects provider autoconfig server entries with
host-unsafe names or zero ports, canonicalizes accepted autoconfig hosts,
tolerates harmless whitespace around autoconfig server type attributes, and can
complete partial provider autoconfig or partial DNS SRV
settings with discovered data or editable manual defaults for the missing
IMAP/SMTP side. Its RFC 6186 SRV plan includes `_submissions._tcp`, and SRV
queries are started concurrently so sparse or unavailable DNS records do not
serialize account-setup delays before HTTPS/manual fallback. SRV results
reject host-unsafe targets before account setup can select them, and prefer
implicit TLS SMTP submissions when a provider advertises them.
SRV records whose target is the root domain marker are ignored because they
explicitly mark a service unavailable. When secure provider autoconfig entries
offer both password and currently unsupported OAuth2/encrypted-password
alternatives for the same side, discovery keeps the password entry so the first
IMAP/SMTP slice can still be provisioned. The backend can also execute common
server-side IMAP search
criteria for text, sender, recipient, subject, read state, flagged
state, and date windows, returning provider results through the existing
`MailBackend.search(_:)` boundary and advertising `.serverSideSearch` only when
that operation is available. Attachment predicates are supported when
message-source fetch is available by fetching the server-search candidates and
filtering on parsed MIME attachment metadata. It can fetch
a selected message source with `UID FETCH ... BODY.PEEK[]`, parse basic
`multipart/*` MIME bodies, expose plain and HTML alternatives, decode
base64 and quoted-printable payloads for common charsets, and download
attachments discovered in the fetched source.

The selected-message fast path now asks for `BODYSTRUCTURE`, fetches the top
headers plus only the first usable plain-text and HTML MIME sections, and
defers attachment section bytes until the attachment boundary requests them.
The resulting provider-neutral `MessageBody` is persisted in a bounded,
account-scoped structured-body cache so revisits do not repeat those section
fetches. Raw-source export, attachment-filtered search, signed/encrypted MIME,
`message/rfc822`, malformed BODYSTRUCTURE responses, and other unsupported
shapes retain the full `BODY.PEEK[]` source path and existing MIME parser. This
keeps raw-source fidelity and security-container handling while removing large
attachment payloads from the ordinary reading critical path.

The raw source parser preserves
standalone `)` lines inside the message body and treats only the final FETCH
close marker as protocol framing. Source fetch now honors IMAP literal byte
counts before reading tagged command completion, so body lines that resemble
`A0003 OK ...` responses remain part of the message instead of truncating the
fetch. Raw source literals honor declared MIME charsets such as ISO-8859-1
and Windows-1252 before fallback decoding, MIME parsing preserves
already-decoded unencoded text bodies instead of applying the declared charset
a second time, source fetch accepts both `BODY[]` and `RFC822` raw-message
literal labels, and
`text/plain; format=flowed` bodies are unwrapped before display. Inline MIME
parts with
`Content-ID` are exposed as inline attachments with content IDs, and the
HTML reader rewrites matching `cid:` image references to local `data:` URLs
after downloading those inline parts through the existing attachment boundary.
Non-text MIME leaf parts are surfaced as generic attachments even when a sender
omits `Content-Disposition` and filename parameters, so bare PDF/image payloads
do not disappear from the reader.
The WebKit remote-content blocker targets network subresources so these local
inline images can render while remote tracking assets remain blocked by
default. Folder, search, header, and raw-source fetch flows parse `LIST`,
`SEARCH`, `FETCH`, `UID`, `FLAGS`, and `ENVELOPE` response atoms
case-insensitively. Header listing ignores UID-looking text inside quoted
`ENVELOPE` strings when extracting the row UID, and it resolves IMAP literal
strings inside `UID FETCH ... ENVELOPE` responses before parsing, so providers
may send long or non-ASCII subjects/display names as RFC-compliant literals.
It also
decodes common RFC 2047 encoded words in IMAP envelope subjects,
sender display names, and attachment filenames, plus RFC 2231 `filename*`
and segmented MIME attachment filename parameters. MIME parameter parsing
preserves semicolons inside quoted values
so attachment filenames such as invoice batches are not truncated, and ignores
later duplicate filename/name parameters instead of crashing on malformed mail.
Incomplete RFC 2231 continuation sequences are rejected so the parser can fall
back to the regular filename instead of constructing a partial name.
IMAP message
mutations now cover read/unread,
flag/unflag, move, Trash-aware delete, permanent delete, and folder flush
through `UID STORE`, `UID MOVE` with copy/delete fallback, paged listing, and
UID-targeted expunge. UID-targeted expunge requires the server to advertise
UIDPLUS; Brev never falls back to plain `EXPUNGE`, because that command can
remove unrelated messages already marked `\\Deleted`. Servers without UIDPLUS
surface a typed unsupported-command error before mutation, while a failed
`UID EXPUNGE` remains a normal command failure for safe retry/replay handling.
SMTP submission is available for password/app-password accounts:
`MailBackend.send(draft:)` builds a MIME message, includes
locally staged attachment payloads as `multipart/mixed` base64 parts,
keeps Bcc recipients out of the message headers, submits via
`AUTH PLAIN`, and appends the same message bytes to the discovered Sent
folder with IMAP `APPEND` when the mailbox exposes one. If SMTP accepts the
message but the Sent-copy `APPEND` fails, Brev keeps the send successful and
returns a non-fatal `SendResultWarning.sentCopyAppendFailed` so compose and
client-side calendar invite replies can show a warning without risking
duplicate delivery on retry. If SMTP accepts a draft but later server Drafts
cleanup fails, Brev also keeps the send successful and returns
`SendResultWarning.remoteDraftCleanupFailed` so compose can tell the user the
saved draft may still need cleanup. Compose draft upload stages IMAP/SMTP draft
attachment data in a local, account-scoped
file store so send can complete through the existing view contract across
backend recreation. When the mailbox exposes a Drafts folder and the IMAP
`APPEND` response includes UIDPLUS `APPENDUID`, draft save also appends the
MIME draft to the server Drafts mailbox with `\Draft`, tracks the returned
`folder:uid` as the draft remote id, replaces the previous remote draft on
later saves, and removes server-saved drafts on discard or after SMTP send
acceptance. Discard can resolve a stable local compose draft id through the
staged/persisted draft mapping to delete the corresponding server `Drafts:<uid>`
row after backend recreation. Server-saved draft cleanup also prunes cached Drafts headers and
emits `messagesRemoved` so visible Drafts lists do not keep stale remote draft
rows after send, discard, or replacement cleanup.
First-page IMAP listing/refresh calls also maintain known message ids
and emit `messagesAdded` events when later refreshes observe new UIDs,
feeding the existing local notification path without adding an always-on
backend polling loop. The notification path reuses already visible headers for
sender, subject, snippet, and received date metadata when the affected message
is locally loaded, then falls back to the account/folder-scoped IMAP header
cache through a provider-neutral extension service when the message is not
visible. If neither source has the header, it keeps the generic fallback instead
of doing a notification-time mailbox fetch. Change subscribers are registered
synchronously before the stream is returned, so an immediate refresh after
subscription cannot drop the first `messagesAdded` event. Successful first-page
IMAP header listings are also
written to an account/folder-scoped header cache. When a later first-page
listing hits a transport-style failure, the backend can return cached
headers, and `SearchQuery(execution: .cacheOnly)` can search those cached
headers locally. Older UID page windows loaded by the user are merged into the
same folder header cache so cache-only search can include messages beyond the
newest page that have already been visited, and the folder cache persists the
last known next UID page token so cached fallback can keep the mailbox's "load
more" affordance after backend recreation or transient listing failure. Later
first-page refreshes replace the previous first-page window in that cache while
preserving already visited older windows, so stale newest-page headers are
pruned without discarding older cached search coverage. Fetched
IMAP message sources are cached in an account-scoped local file cache, so
revisiting a fetched body,
downloading an attachment from an already fetched message, or
attachment-filtering search can reuse the known MIME source across app launches
without another server round trip. The shipping macOS and iOS app wiring gives
that account-scoped file cache a local byte budget and prunes the oldest cached
message sources for that account after writes when the budget is exceeded.
Successful IMAP folder listings are also persisted as account-scoped folder
snapshots. Restored IMAP accounts may install that cached folder snapshot when
folder listing fails with a cache-fallback-eligible transient error, keeping the
backend connected in degraded sync-health state so cached folders and cached
headers remain usable during a temporary offline launch. Fresh account
provisioning clears stale local IMAP stores before its first restore/connect
attempt, so old cached folders cannot turn a new offline setup into a false
success. Same-address replacement provisioning snapshots any existing account,
configuration, credential, current-account selection, and local mailbox cache
before writing the candidate settings. The candidate replacement validates with
local cache disabled, and Brev clears the old local stores only after IMAP
connect and outgoing SMTP validation both pass. If either step fails, rollback
restores the previous account material and cache so a bad password or edited
server setting cannot destroy a working mailbox. Clearing the final account
snapshot removes the persisted folder-cache key.
Successful
IMAP move/delete mutations invalidate the old cached source ids so stale local
body data is not reused after a mailbox action. Successful IMAP read/flag
mutations also update cached header flags and emit `messagesUpdated`, while
move/delete mutations prune cached source-folder headers and emit source
`messagesRemoved` plus destination-folder refresh events when the destination
UID is not known. First-page listing/refresh reconciliation also emits
`messagesUpdated` for remotely changed cached headers, and emits
`messagesRemoved` for prior first-page headers missing from a complete
refreshed window so externally deleted or moved messages leave the visible
cache. Revisited older UID pages also emit `messagesUpdated` when their cached
headers changed remotely. The header cache records visited older page-token
windows, so reloading the same older page can also emit `messagesRemoved` for
headers that were previously in that exact page window and have disappeared.
First-page listing responses also carry SELECT `UIDVALIDITY` metadata when the
server reports it; the header cache persists that value so restored accounts can
also detect cross-launch UIDVALIDITY changes. If a folder's UIDVALIDITY changes,
Brev clears local IMAP caches before trusting the reused `folder:uid` ids again.
For providers without
a native junk API,
the message-list UI follows the `MailBackend` contract and falls back to moving
messages between discovered Spam and Inbox folders. Retryable
IMAP mutation failures are queued into Brev's provider-neutral offline
mutation queue, and restored/provisioned IMAP backends attempt to replay
queued mutations after a successful connect. Replay conflicts from missing
targets, rejected changes, or exhausted retries are stored per account and
surfaced through sync health so they survive backend recreation after the
pending queue removes the conflicted mutation; Settings can clear reviewed
conflict summaries through `SyncHealthRepairing`. Supervised mailbox action
undo restores propagate backend failures back to the root status surface
instead of silently treating rejected source-scoped IMAP restores as completed.
IMAP accounts also expose
`SyncHealthReporting`/`SyncHealthRepairing` through the existing optional
extension-service seam, surfacing pending mutation counts, source-cache bytes,
last connect errors, and a retry action that reconnects, replays queued
changes, and refreshes the first page of each connected folder when message
listing is available, emitting folder refresh events after each refreshed
folder. IMAP accounts also expose a provider-neutral background mailbox refresh
service; the app's foreground, network-recovery, and scheduled fetch triggers
use it when available to reconnect and refresh the first page for a capped,
prioritized set of each visible mail source's connected folders, with Inbox
first and provider order preserved for folders in the same priority bucket. It
emits the same folder refresh events as manual repair without replaying queued
mutations. This narrows stale unvisited-folder windows while avoiding an
unbounded activation-time sweep of very large folder trees; it remains a bounded
cache refresh, not a full delta/history sync engine. The session client now supports IMAP `IDLE` and parses common untagged
mailbox-change responses
(`EXISTS`, `RECENT`, `EXPUNGE`, and `FETCH FLAGS`). When an injected IDLE stream
is available, `IMAPSMTPBackend.subscribeToChanges()` listens to the Inbox and
converts new-count events into a normal folder refresh so the existing
`messagesAdded` event path receives concrete UIDs; those IDLE count events
reuse the connected Inbox first-page refresh path instead of relisting folders
for every mailbox change. If the IDLE stream drops or throws, the backend waits
briefly and resubscribes while the change subscriber is still active; repeated
empty or failing streams use a bounded exponential backoff so providers that
reject or drop IDLE do not trigger a tight reconnect loop. Background IDLE
failures are recorded in sync health without marking the mailbox disconnected,
preserving ordinary mailbox access while surfacing degraded live-sync status.
The IMAP and SMTP session clients also understand the STARTTLS command
sequence and expose a transport-level TLS upgrade hook. The current
Apple-platform transports keep their public `Network*SessionTransport`
names for app wiring compatibility, but are backed by a shared
socket/TLS connection seam that can open implicit-TLS sessions and
upgrade an already-established TCP socket after the protocol STARTTLS
command succeeds. IMAP and SMTP session clients apply bounded response
timeouts to greeting, command, continuation, reply, and IMAP literal reads, so
a stalled provider connection fails as a transport error instead of hanging
setup, body fetch, attachment download, or send indefinitely; the active IMAP
`IDLE` event wait remains long-lived by design. The account setup sheet now
allows incoming IMAP STARTTLS
settings instead of blocking those discovered/manual configurations at submit
time. Setup validation blocks malformed email addresses, email addresses with
embedded whitespace or host-unsafe domains, malformed manual server hostnames,
zero ports, passwords containing NUL characters, and discovered/manual
authentication modes the current protocol clients cannot use yet, including
OAuth2 and encrypted-password challenge auth. Provisioning repeats the NUL
secret validation before storing account, configuration, or Keychain material.
macOS and iOS instantiate the shipping app-facing backend through
`IMAPAccountConnector.standard`, a shared connector factory that wires the
same network IMAP/SMTP operations, outgoing SMTP validation, IDLE stream,
header/source/draft caches, and offline mutation stores on both platforms.
The factory still accepts injected transports so scripted tests can exercise
the same connector path without opening real sockets.
Provisioning enforces the same server/auth validation before storing account
configuration or Keychain credentials, and the SMTP session client rejects
encrypted-password challenge auth before opening a connection so unsupported
profiles cannot accidentally attempt `AUTH PLAIN`. The IMAP session client
rejects line breaks in quoted command arguments such as credentials, mailbox
names, and server-search strings before writing a command to the protocol
stream. The SMTP session client rejects line breaks in envelope sender and
recipient addresses before opening a connection for submission, and trims
surrounding whitespace before writing `MAIL FROM` and `RCPT TO` commands.
Both session clients also reject NUL characters in protocol credentials before
opening a connection, preserving IMAP `LOGIN` and SMTP `AUTH PLAIN` frame
structure when stored credentials are malformed. The SMTP session client also
requires the EHLO response that immediately precedes authentication to advertise
`AUTH PLAIN`, including the post-STARTTLS EHLO for upgrade sessions, before
sending the SASL PLAIN token.
During account setup, the
app-injected connector validates outgoing SMTP credentials with EHLO, optional
STARTTLS, `AUTH`, and `QUIT` before keeping the new account; no envelope or
message body is submitted, and validation failures reuse the account-data
rollback path. The
app session treats IMAP/SMTP `authenticationRequired` restore failures as
recoverable credential-attention states: it keeps the saved account and local
state retryable instead of purging account metadata, reserving destructive
stale-auth cleanup for legacy the provider token-backed accounts. The
IMAP/SMTP adapter advertises SMTP-backed send capability when a send operation
is wired, including password and app-password SMTP accounts, so backend-neutral
UI gates such as client-side calendar RSVP/iMIP actions can treat standards
accounts as SMTP-capable without checking the concrete backend type. The
repository still does not contain checked-in live credentials or recorded
supervised live-provider results for STARTTLS, long-lived IMAP IDLE recovery,
mutation replay, persistent Drafts mailbox sync across providers,
provider coverage for UIDVALIDITY cache invalidation, detailed conflict
review/resolve UX for IMAP replay, user-visible background refresh tuning and
instrumentation across very large folder trees, or a full sync/cache engine for IMAP accounts. The retired
`previous backend` code remains useful reference material, but it is still coupled
to provider API and Realm flows and is not the generic IMAP engine Brev
now needs.

The next implementation step must support ordinary providers while
preserving Brev's existing view-layer and privacy invariants:

- Views continue to depend on `MailBackend` and value models, not
  provider-specific or socket-protocol types.
- Account setup remains user-initiated and transparent about which
  network probes disclose a domain versus a full email address.
- Credentials are local secrets. They must not be stored in
  `UserDefaults`, cached logs, ADRs, worklogs, or app telemetry.
- Rich HTML body rendering, attachment handling, cache/search,
  offline mutation recovery, notifications, and mailbox actions remain
  acceptance criteria for the rewrite.

## Decision

Brev will build the IMAP/SMTP backend in layered, backend-neutral
slices:

1. Account setup owns autodiscovery, manual server settings,
   non-secret IMAP/SMTP configuration persistence, and Keychain-backed
   password/app-password credentials.
2. An IMAP session/client layer owns protocol login, mailbox/folder
   listing, selected-folder state, UID-based message header listing,
   UID page-window pagination, server-side SEARCH criteria construction,
   message source fetch primitives, UID-based message mutations, and IMAP
   error mapping. It is tested against injected transports first.
3. A concrete Apple-platform transport owns socket I/O for implicit TLS
   and STARTTLS-capable IMAP/SMTP. The initial implementation uses a
   narrow `MailSocketConnection` seam and a POSIX socket plus
   SecureTransport bridge so STARTTLS can upgrade the established socket
   in place. This preserves the higher-level transport protocols while
   leaving room to replace the TLS bridge later.
4. `IMAPSMTPBackend` adapts the initial lower layers to `MailBackend`
   once it can connect, list/create/rename/delete folders, list message
   headers, fetch basic bodies, download simple MIME attachments, send messages
   with locally staged attachments, append accepted sent messages to a
  discovered Sent folder, emit refresh-driven `messagesAdded` events for newly
  observed first-page UIDs, emit first-page refresh update/removal events for
  changed or missing cached headers, listen to optional Inbox IDLE events by
  refreshing the folder with bounded retry backoff, cache first-page headers
  for fallback/cache-only search, cache
  fetched message sources locally for body/attachment reuse, enqueue retryable
  mutation failures, replay queued mutations after reconnect, report sync
  health with pending mutation counts, source-cache bytes, and retry repair,
  and apply common message mutations. It may expose unsupported operations
  explicitly while deeper sync/cache behavior is implemented in later slices.
  Server search is allowed for criteria IMAP can answer directly;
   attachment predicates may be answered by fetching and parsing candidate
   message sources until BODYSTRUCTURE or a richer local cache can answer
   them more cheaply.
5. SMTP submission is a separate lower layer used by
   `MailBackend.send(draft:)`; it does not leak SMTP-specific response
   details into the view layer. Sent placement uses the already-built
   RFC 2822/MIME message data and IMAP `APPEND` when folder discovery
   finds a `.sent` role. Attachment uploads for the IMAP/SMTP adapter are
   durable account-scoped staging records that feed MIME construction at
   send time and server Drafts `APPEND`. When folder discovery finds a
   `.drafts` role and the append returns an IMAP UID, save/discard/send
   maintain the server-saved Drafts copy without exposing IMAP details to
   views.
6. XOAUTH2 profiles are discoverable but rejected for password-based
   provisioning until a provider OAuth flow exists. App-password
   providers may be added with user-supplied app passwords.

## Rationale

**Chosen: layered in-house protocol foundation with injected
transports.** This lets Brev test parsing, state transitions, and error
mapping without live mail credentials, and keeps UI code insulated from
IMAP details.

**Rejected: keep adapting the the provider/previous backend backend.** That path
would preserve provider coupling and reintroduce the login/session
fragility ADR-0028 is meant to remove.

**Rejected: add a large third-party IMAP stack immediately.** A library
may still be useful later, but choosing one before Brev has pinned its
minimum protocol needs would make dependency, licensing, and API
surface decisions too early.

**Rejected: fake a `MailBackend` for saved IMAP accounts.** Showing a
saved account as connected before it can validate credentials and list
folders would make QA confusing and could hide real backend work.

## Consequences

### Accepted

- Account identity, server configuration, and credentials are separate
  persistence surfaces.
- `UserDefaults` may store non-secret host, port, TLS, username
  template, and account metadata.
- Keychain stores password/app-password material with
  device-local accessibility.
- IMAP tests start with scripted transports. Live-account tests remain
  opt-in and must not run in CI with real credentials by default.
- `scripts/imap-smtp-live-smoke.sh` is the opt-in disposable-account
  harness for live IMAP/SMTP proof. Without `BREV_LIVE_*` credentials it
  exits as a clean skip, the related feature request preflight uses only its compile check,
  and the live path provisions an app-facing IMAP account, disconnects it,
  restores it through the same connector, and then exercises `MailBackend`
  folders, messages, bodies, attachment download when a sampled message has one,
  and optional send. The live connector also wires the app-facing IMAP IDLE
  change-stream operation and asserts the restored backend advertises IDLE sync
  capability before mailbox sampling. Actual provider event delivery can be
  made a hard live QA requirement with `--exercise-idle-event`, which subscribes
  through the restored backend, appends one disposable Inbox message on a second
  IMAP connection, requires the resulting `messagesAdded` event, and cleans up
  the fixture. Attachment download can be made a hard live QA requirement with
  `--require-attachment-download`, which scans the
  sampled page and fails unless a downloadable attachment is found. Server
  search proof additionally requires `--exercise-server-search`, which runs a
  read-only search through `MailBackend.search(_:)` using a sampled header from
  the selected folder. SMTP submission additionally requires
  `--send-test-message`. Folder-management proof additionally requires
  `--exercise-folder-management`, which creates, renames, and deletes a unique
  disposable folder and attempts cleanup if a later step fails. Folder-flush
  proof additionally requires `--exercise-folder-flush`, which creates a unique
  disposable folder, appends disposable messages, empties it through
  `MailBackend.flushFolder(id:)`, verifies the fixtures are gone, and deletes
  the folder. Message-mutation proof additionally requires
  `--exercise-message-mutations`, which creates disposable folders, appends a
  disposable fixture message, drives read/flag/move/delete through
  `MailBackend`, and cleans up matching fixture messages. Compose lifecycle
  proof additionally requires `--exercise-compose-lifecycle`, which stages an
  attachment, saves a server Drafts copy, sends it through SMTP, attempts
  remote Drafts cleanup, saves a second Drafts copy, and discards it; this
  fails if the provider cannot expose a Drafts mailbox with UIDPLUS
  `APPENDUID`. No-send outgoing SMTP setup validation additionally requires
  `--validate-smtp-setup`, which authenticates and quits without creating a
  message.
- `scripts/imap-autodiscovery-smoke.sh` is the opt-in account-settings
  discovery harness. Its compile check runs in the related feature request preflight, while
  live runs require an explicit email address and perform only DNS SRV and
  provider-local HTTPS autoconfig probes. It never accepts credentials or
  provisions an account.
- `scripts/imap-smtp-local-smoke.sh` is the credential-free app-facing
  mailbox harness. It provisions an in-memory IMAP/SMTP account through
  `IMAPAccountConnector`, then exercises `MailBackend` folder listing,
  folder create/rename/delete, message listing, body parsing, attachment
  download, first-page refresh reconciliation, read/flag/move/delete mailbox
  mutations, folder flush, attachment upload, Drafts append/discard, SMTP
  setup credential validation, SMTP send with staged attachment MIME,
  Sent-copy append, and remote Drafts cleanup events. It also subscribes to the
  restored backend and requires visited older-page update/removal, first-page
  refresh update/removal, read/flag/move/delete mutation events, and
  server-saved Drafts cleanup events. It complements live provider QA but does
  not replace it.
- IMAP account setup can land before the full mail session backend. The
  UI may install a connected account after folder listing succeeds and
  may show message rows once header listing succeeds. It may render
  selected messages once body fetch succeeds and may use server search
  for common IMAP criteria, but unsupported mail operations must fail
  explicitly until implemented.

### Risks

- A hand-built protocol layer can miss edge cases in the large IMAP
  surface. Mitigation: keep the first layer narrow, add fixture-based
  parser tests, and consider a third-party library once Brev's required
  command set is explicit.
- The initial MIME parser intentionally handles common body/attachment
  cases rather than the full RFC surface. Mitigation: keep adding
  fixture tests for real provider messages, especially complex inline image
  layouts, encoded filenames, nested signed/encrypted parts, non-UTF charsets,
  and unusual transfer encodings. Unencoded `text/plain` attachment downloads
  now preserve significant leading/trailing spaces while trimming only
  transport newline padding from the raw MIME part.
- The initial STARTTLS-capable socket bridge uses SecureTransport, which
  is deprecated on Apple platforms and emits compiler warnings.
  Mitigation: keep the bridge isolated behind `MailSocketConnection`,
  cover implicit TLS and STARTTLS connection-mode behavior with tests,
  and replace the bridge with a modern socket/TLS layer once Brev adopts
  one that supports in-place STARTTLS upgrades.
- STARTTLS still needs disposable live-provider QA across common IMAP and
  SMTP hosts. Mitigation: autodiscovery records STARTTLS settings, the
  session clients have protocol sequencing tests, the live smoke harness
  can exercise disposable implicit-TLS and STARTTLS accounts outside CI,
  the credential-free local smoke restores a provisioned account before
  exercising mailbox operations, and the transport seam can be exercised
  against provider-specific fixtures before broad release.
- Built-in autodiscovery profiles can correctly identify providers that require
  OAuth2 or encrypted-password challenge authentication before Brev implements
  those flows. Mitigation: keep the discovered settings visible for review,
  but block account submission and provisioning for unsupported authentication
  modes until the Google/Microsoft/provider-auth follow-up exists, and surface
  provider-specific guidance so Google/Microsoft and encrypted-password setups
  explain the likely manual-password or app-password path instead of failing
  with generic copy.
- Sent-copy append happens after SMTP acceptance and is intentionally
  non-fatal for now, because treating a failed Sent copy as a failed send
  could cause duplicate delivery on retry. Mitigation: `SendResult` now carries
  `.sentCopyAppendFailed` and `.remoteDraftCleanupFailed`, and compose surfaces
  warning statuses after the send completes.
- Initial IDLE support watches the Inbox only, converts count-change responses
  into a normal first-page refresh, and resubscribes with bounded backoff after
  dropped or failing streams. Background IDLE failures degrade sync health
  without disconnecting the mailbox.
  Mitigation: keep it optional behind an injected operation, add live provider
  QA for long-lived IDLE sessions and recovery behavior, use the opt-in live
  smoke `--exercise-idle-event` path for disposable provider event-delivery
  proof, expand beyond Inbox once the persistent sync/cache engine can
  reconcile folder-wide deltas, and keep bounded background refresh user-visible
  through sync health summaries that report refreshed/deferred folder counts.
- Initial IMAP offline mutation recovery reuses the provider-neutral queue
  and replays after a successful connect, with pending counts and retry exposed
  through sync health. Replay conflicts are now stored per account and surfaced
  through sync health after the queue removes the conflicted mutation. Sync
  health carries a typed replay-conflict count so Settings can clear reviewed
  summaries without parsing user-facing error copy, and Settings can now list
  the stored conflict summaries in a read-only review sheet before clearing
  them. There is still no detailed per-conflict resolve/retry UI and the path
  has not yet been live-provider QA'd. Mitigation: keep replay policy covered
  by backend tests, add detailed conflict review/resolve affordances in a
  follow-up, and run
  disposable mailbox replay QA before daily-driver sign-off.
- Initial IMAP cache support stores first-page headers, merges already loaded
  older page headers, persists the last known next page token for the visited
  window, prunes stale previous-first-page headers during later first-page
  refreshes, emits first-page update/removal events for changed or missing
  cached headers, emits update events for changed cached headers in revisited
  older pages, emits removal events for missing headers from exact revisited
  older page-token windows, and keeps a local fetched-source file cache for body
  and attachment reuse. Mitigation: use it for fallback display, cache-only search,
  visited-window pagination state, visible-window refresh reconciliation, and
  body/attachment reuse now, then add full folder-wide reconciliation in the
  sync/cache slice.
- IMAP/SMTP draft save can persist the current compose snapshot to a server
  Drafts mailbox when the provider exposes Drafts and returns `APPENDUID`, but
  it is not yet a full provider Drafts sync engine for listing/editing drafts
  created elsewhere. Mitigation: keep local attachment staging durable, fail
  missing attachment references before SMTP submission, clear local staging on
  send/discard/account removal, and add folder-wide Drafts reconciliation in
  the full sync/cache slice.
- Saved IMAP accounts may exist before the full backend can render a
  mailbox. Mitigation: session restore only installs a backend after the
  adapter connects and lists folders; unsupported operations remain
  explicit errors until implemented.

## References

- ADR-0001: Backend abstraction for multi-provider
- ADR-0006: Telemetry, privacy, and GDPR compliance
- ADR-0022: Offline mutation queue and local cache evolution
- ADR-0028: Standards-first IMAP/SMTP roadmap
- RFC 3501: Internet Message Access Protocol - Version 4rev1
- RFC 4954: SMTP Service Extension for Authentication
- RFC 8314: Cleartext Considered Obsolete: Use of TLS for Email
  Submission and Access
